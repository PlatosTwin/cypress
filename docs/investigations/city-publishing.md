# City publishing — per-city seed files and the manifest (#156)

*2026-08-01, w1-publisher. The R36 base layer's publish step: what
`Tools/publish_cities.py` produces, the manifest contract #157 consumes, and how the
artifacts reach the `cypress-cities` Tigris bucket. Design decisions delegated to this
ticket are recorded as RULINGS R37.*

> **Historical — read the code for the current contract.** This records the state at #156, when
> there was one catalog and it was format 1 at `manifest.json`. Since then the s17 round added
> `manifest-v2.json` (format 2, one entry per published *region* rather than per city), and on
> 2026-08-23 format 1 retired: the publisher writes only `manifest-v2.json`, and the format-1
> object is frozen in the bucket rather than deleted. See
> `docs/rulings-pending/format1-retirement.md`. Everything below about narrowing, determinism,
> immutable paths and upload ordering still holds; substitute `manifest-v2.json` for
> `manifest.json` and "region" for "city" when reading it.

## What the publisher does

`Tools/publish_cities.py` consumes the ingest pipeline's output — the fused seed at
`Fixtures/seed/cypress-seed.sqlite` — and writes, per `id_space` present in it:

    dist/cities/<id>/<version>/<id>.sqlite
    dist/manifest.json
    dist/upload.sh

Each city file starts as a byte-copy of the fused seed and is narrowed by DELETE +
VACUUM, so its schema is the fused seed's schema **by construction** — the publisher
never re-states `Fixtures/seed/schema.sql` and cannot drift from it. What each table
keeps, and why, is documented in the tool's own docstring (species and species_map are
kept whole; foreign id_spaces/inventories rows are dropped; only referenced
neighborhoods survive).

The narrowing is deterministic: no wall-clock value enters a city file, so two runs
over the same fused seed produce byte-identical files (verified 2026-08-01: two runs,
identical sha256 on both cities). The manifest's `generated_at` is the one wall-clock
field and lives only in the manifest.

## Measured on the 2026-07-31 fused seed (198,625 rows)

| city | trees | species_assertions | file | sha256 (prefix) |
|---|---|---|---|---|
| `sf` | 145,837 | 133,339 | 80.6 MB | `b63ad949a5ca61a7` |
| `us-ca-sj` | 52,788 | 40,199 | 28.0 MB | `c1ea8e0bfcf708af` |

Counts measured independently with `sqlite3` against both the fused seed and the
produced files; the two per-city sums equal the fused totals exactly (trees
198,625; assertions 173,538). UUID spot-checks confirm identities survive the split
byte-for-byte.

## The manifest contract (`manifest_format: 1`)

`manifest.json` lives at the bucket root and is the only object that is ever
rewritten in place; every city file lives under an immutable versioned path. The app
(#157) polls the manifest, compares `version` per city against what it has installed,
and downloads `path` when they differ — verifying `bytes` and `sha256` before
swapping the file in.

Top level:

| key | type | meaning |
|---|---|---|
| `manifest_format` | int | envelope version; bumped only on breaking shape changes, additive keys do not bump it. Reader must reject formats it does not know. |
| `generated_at` | ISO-8601 UTC | when this manifest was written (wall clock; informational) |
| `generator` | string | provenance |
| `base_url_hint` | string | where the publisher believed the files were headed. **Informational only — the app must not read it.** The app's base URL is app configuration, so a compromised or stale manifest cannot redirect downloads. |
| `source_seed` | object | receipt for the fused seed the run consumed: `generated_at`, `tree_count`, `sha256` |
| `cities` | array | one entry per published city, see below |

Per city:

| key | type | meaning |
|---|---|---|
| `id` | string | the `id_space` (`sf`, `us-ca-sj`). Stable key for install state. |
| `display_name` | string | entered by hand in the publisher; never derived (constraint 15 discipline) |
| `coverage` | string | `full`, or the ship-window name when the file deliberately holds a subset (`us-ca-sj` is `downtown` today per the R31-era ship window) |
| `bbox` | object | min/max lat/lon **measured from the file's rows**, not the admission box — for `us-ca-sj` these differ hugely and the measured one is the honest one for "offer the reader's city" |
| `centroid` | object | bbox center, for distance ranking on first launch |
| `tree_count` | int | measured `COUNT(*)` of `trees` in the file |
| `schema_version` | int | seed schema generation (14 today — the record's own "v14 seed pass" numbering). The app compares against the generation it was built to read and must not download a file whose generation it does not understand. |
| `content_rev` | string | `YYYY-MM-DD`, newest upstream snapshot among the city's own inventories; derived from `seed_meta`, never from the clock |
| `version` | string | `s<schema_version>-r<content_rev>`; equality against the installed version is the whole update check |
| `path` | string | bucket-relative object key, `cities/<id>/<version>/<id>.sqlite`; joined to the app-configured base URL |
| `bytes`, `sha256` | int, string | verified before install; a mismatched download is discarded |
| `attribution` | array | one entry per inventory in the file — `inventory`, `name`, `url`, optional `snapshot_on`, `license`. R36 binding consequence (b): the attribution obligation travels with the published data. |

The city files additionally carry their own receipt in-band: `seed_meta` gains
`publish_city_id`, `publish_schema_version`, `publish_content_rev`,
`publish_generator`, `publish_source_generated_at`, and the two fused-receipt keys
that name the file rather than the build (`id_spaces_in_file`, `rows_kept`) are
rewritten to the truth about the file. `trees_snapshot_on` is rewritten to the city's
own content revision so `InventorySource`'s "city record as of" sentence stays true
per city.

## Upload — deliberately credential-free in the tool

The Tigris keys exist only as `cypress-sync` app secrets and in the owner's Tigris
dashboard (`server/README.md`); the publisher never reads, prints, or stores them.
`dist/upload.sh` is generated per run and uses the standard `aws` CLI resolving
credentials from a named profile — `cypress-tigris` by default, overridable with
`CYPRESS_TIGRIS_PROFILE` — never from ambient `AWS_*` environment variables. Both
s15 and s16 publishes failed with `InvalidAccessKeyId` under the old
export-into-shell flow, because an unset environment silently falls back to
`~/.aws/credentials [default]` (Amazon keys Tigris has never heard of); ticket
#248 pinned the profile into every generated `aws` invocation and added a
fail-fast preflight, since an explicit `--profile` ignores whatever the shell
happens to carry:

    aws s3 cp cities/sf/s14-r2026-07-31/sf.sqlite \
        s3://cypress-cities/cities/sf/s14-r2026-07-31/sf.sqlite \
        --endpoint-url https://fly.storage.tigris.dev \
        --profile "$PROFILE"
    # … one line per city, then manifest.json last

Upload order matters and the script encodes it: **city files first, manifest last**,
so a reader never sees a manifest describing an object that is not there yet.

Two open items for whoever runs the upload:

1. The bucket is **private**. R36's design has the app fetching over plain HTTPS, so
   public read (or signed URLs) must be enabled before #157 can fetch —
   `server/README.md` left that switch to this publish step's operator on purpose.
   `flyctl storage dashboard cypress-cities` reaches the setting.
2. Nothing in this repo should ever contain the keys. Run `upload.sh` from a shell
   that already has them; do not paste them into any file or command visible in a
   transcript.
