# PENDING — City file versioning and manifest shape (#156, delegated)

*Unnumbered on purpose; the orchestrator splices this under the real next number at
merge. Delegated design authority for the R36 base layer's publish step. Full
mechanics: `docs/investigations/city-publishing.md`; implementation:
`Tools/publish_cities.py`.*

The publish step needed four decisions R36 did not make. Taken 2026-08-01:

**1. A city file's version is `s<schema_version>-r<content_rev>`, both parts derived,
neither invented.** `schema_version` continues the seed-pass numbering the record
already uses (E176's "v14 pass" — the generation that added `id_space`), starting at
14; it bumps when `Fixtures/seed/schema.sql` changes shape, and the app refuses
generations it was not built to read. `content_rev` is the newest upstream snapshot
date among the city's own inventories, read from `seed_meta` — never the wall clock,
so republishing the same seed yields the same version and byte-identical files. There
is no third "build number" component: two publishes of the same data ARE the same
version, which is what makes the object paths immutable.

**2. Versioned paths are immutable; only `manifest.json` is ever rewritten.** Objects
land at `cities/<id>/<version>/<id>.sqlite`, written once; the update check on device
is string equality on `version`. Files upload before the manifest that names them.

**3. City files are narrowed copies, not rebuilt files.** The publisher byte-copies
the fused seed and DELETEs the other city out (then VACUUMs), so schema fidelity is
by construction. What survives: the city's `trees`, its `species_assertions` and
R*Tree entries, only its `id_spaces`/`inventories` rows, only referenced
`neighborhoods` — but `species`/`species_map` stay WHOLE, because the species
catalogue and its curated content are shared authored work, not city data, and
splitting them would fork curation. `species_map.tree_count` therefore still
describes the fused build; `seed_meta.species_map_counts_scope` says so in-band.

**4. Files ship uncompressed, and the manifest's `base_url_hint` is not for the
app.** Uncompressed: Tigris egress is free (R36), `#157`'s consumer stays a plain
file download with a sha256 check, and gzip (~2x) can be added later as a new
manifest key without breaking format 1. The download base URL is app configuration;
a manifest field that named it would let a stale or hostile manifest redirect
downloads.

Also binding on the next ingest round: manifest `coverage` currently maps the ad-hoc
`seed_meta.sj_ship_extent` key by hand; when a third city lands, `build_seed.py`
should write `coverage_<id_space>` keys and the publisher's `COVERAGE_KEYS` shim
retires.
