### EXXX — `dim_city`: a city dimension table, absorbing `id_spaces.short_name` (task #237)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `feat/237-dim-city`. Latest numbered at time of writing: E222, R60.*

---

#### What this adds, and why

`id_spaces.short_name` (task #233, ERRATA E209 Shape A) put one civic string — "San Francisco",
"San Jose" — beside an id space so the share card could stop hardcoding a city that had stopped
being true the moment a second city shipped. That was the minimum fix at the time. Task #237 asks
for the fuller shape: a real city dimension table — `id`, `slug`, `display_name`, `state`,
`county`, `urban_forestry_url` — joined through `id_spaces.city_id`, so a tree's civic facts are
looked up in one place instead of being scattered one column at a time across whatever table
happened to need the next one.

This mints **s16** (`SeedDatabase.newestKnownSchemaVersion` / `Tools/publish_cities.py`'s
`SEED_SCHEMA_VERSION`). Both are the SEED schema space, not the WRITABLE database's
(`AppSchema.currentVersion`) — this round touched only the first, and no `AppSchema` migration was
needed or written.

#### The premise this ticket handed me, and what I refuted

**"SUPERSEDES any `sf`→`us-ca-sf` rename of `id_spaces.id`."** Correct as briefed, and built that
way: `id_spaces.id` is untouched — still `"sf"` and `"us-ca-sj"`, still the foreign key
`trees.id_space` carries, still what `Tools/inventory_contract.py`'s `IdSpace.identity_prefix`
(frozen per space; `sf`'s is the empty string) is keyed on. The "us-ca-sf" slug convention lives
only on the new `dim_city.slug`. Verified by reading `Tools/inventory_contract.py` before writing
anything: `ID_SPACES` is still `{"sf": ..., "us-ca-sj": ...}`, unchanged.

**"`id_spaces.short_name` is ABSORBED into dim_city — decide whether s16 drops the column."**
Dropped, not duplicated. `id_spaces.city_id INTEGER NOT NULL REFERENCES dim_city(id)` replaces
`short_name TEXT NOT NULL` outright in the same schema pass, so a v16 file has one source of truth
for a city's display name rather than two hand-maintained mappings that could drift apart. A v15
file (the one CI still serves — see below) keeps `short_name` and keeps working through it; the
read layer asks each flag independently rather than assuming one generation implies the other's
shape (`SeedSchema.hasDimCity`, `hasCivicShortNames`, both checked in `TreeQueries.treeSQL()`).

**Everything else in the brief held.** `SharePresentation.locationLine`'s fallback matrix needed no
change and still passes unchanged — it already read `profile.cityShortName`, and `TreeQueries` is
the only layer that changed how that field gets filled in.

#### What was added, file by file

- **`Tools/build_seed.py` / `Fixtures/seed/schema.sql`** (kept byte-identical, as always — the
  build regenerates `schema.sql` from the embedded `SCHEMA_SQL` string, never hand-edited
  separately): `CREATE TABLE dim_city (id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL, state TEXT NOT NULL, county TEXT NOT NULL, urban_forestry_url TEXT
  NOT NULL, ...)`; `id_spaces.short_name` → `id_spaces.city_id INTEGER NOT NULL REFERENCES
  dim_city(id)`. `DIM_CITY` (was `SHORT_CITY_NAMES`) is the hand-maintained dict, same loud-failure
  shape as `DISPLAY_NAMES`/`SHORT_CITY_NAMES` before it — a contributing id space with no entry
  fails the build with `FATAL: no dim_city row registered for id space(s) [...] in DIM_CITY --
  civic facts are entered, never derived` (reproduced below, under Red-proofs).
- **`Tools/publish_cities.py`**: `SEED_SCHEMA_VERSION` 15 → 16. `build_city_file` narrows
  `dim_city` to the one row the surviving `id_spaces` row still references, the same shape as the
  existing `id_spaces`/`inventories` narrowing and for the same reason — a city file carrying
  another city's civic facts would be claiming an authority it does not have. `DISPLAY_NAMES` is
  left as its own dict (see "left alone, deliberately" below).
- **`Cypress/Data/Store/SeedDatabase.swift`**: `newestKnownSchemaVersion` 15 → 16.
  `SeedSchema.hasDimCity` — `tableExists("dim_city")`, table-gated like `hasSpeciesTrigrams`
  (a new table), unlike `hasCivicShortNames` (column-gated, because that one landed on the
  pre-existing `id_spaces`).
- **`Cypress/Data/Store/TreeQueries.swift`**: `treeSQL()` tries three sources for a row's city name
  in order — `dim_city.display_name` through `id_spaces.city_id` when `hasDimCity && hasIdSpace`;
  `id_spaces.short_name` when that did not resolve and `hasCivicShortNames && hasIdSpace` (a v15
  file); `NULL` otherwise. Both joins are conditioned on `hasIdSpace`, not merely on the table/column
  flag that names what they read — the same discipline `CivicShortNameTests` established for `isp`,
  extended to `dc`, which is joined *through* `isp` (`dc.id = isp.city_id`) and is therefore doubly
  exposed to the same class of defect. `TreeRecord.cityShortName` / `TreeProfile.cityShortName` /
  `SharePresentation.locationLine` are all unchanged — the field name and its fallback contract
  did not move, only what fills it in did.
- **`CypressTests/DimCityTests.swift`**: fixture-based coverage for s14 (no `id_spaces` at all),
  s15 (`short_name`, no `dim_city`), s16 (`dim_city`), and the adversarial
  dim_city-without-`trees.id_space` shape (mirrored from PR #29's finding against `short_name`) —
  plus real-seed tests gated `.enabled(if:)` on the canonical seed actually carrying `dim_city`,
  exactly like `SpeciesTrigramTests`/`CivicShortNameTests` gate theirs.

#### Civic content (DECISIONS constraint 15 — entered, never invented), with sources

| id space | slug | display name | state | county | urban forestry URL | source, verified live 2026-08-05 |
|---|---|---|---|---|---|---|
| `sf` | `us-ca-sf` | San Francisco | CA | San Francisco | <https://sfpublicworks.org/streettreesf> | Fetched directly: title "StreetTreeSF \| Public Works", confirmed as San Francisco Public Works' Bureau of Urban Forestry program page. |
| `us-ca-sj` | `us-ca-sj` | San Jose | CA | Santa Clara | <https://www.sanjoseca.gov/your-government/departments-offices/transportation/forestry> | Loaded in a browser directly (a plain fetch 403s behind Akamai bot protection): title "Forestry \| City of San José", the City's Forestry / Trees & Landscaping program page. |

**State format — flagged for owner sign-off, not decided unilaterally.** Postal abbreviation
(`"CA"`) was picked over the full name (`"California"`) for parity with how the app already treats
short-form civic strings (`id_spaces.short_name`/`dim_city.display_name` are city names, not
sentences) and because it is the shorter, more citable form for a slug-adjacent column. Either is
defensible; the PR body asks for a decision rather than assuming this one is final.

`county` is San Francisco's own name for itself (the city and county are coextensive and
consolidated; DataSF and the city's own materials both write "San Francisco" for both) and Santa
Clara for San Jose (San Jose is not its own county). Neither is inferred — both are the county each
city's inventory data and the seed's existing bbox/neighborhood tooling already treat as ground
truth.

#### `Tools/publish_cities.py`'s `DISPLAY_NAMES` — left alone, deliberately

Evaluated deriving `DISPLAY_NAMES` from the fused seed's `dim_city.display_name` instead of
carrying a second hand-entered dict. Left as its own dict, for the same reason
`SHORT_CITY_NAMES`/`DISPLAY_NAMES` were kept independent before this pass (see the civic-short-names
entry this one follows): the seed builder and the publisher are separately owned by design, and a
change to the seed's civic content should not silently reach into the manifest's `display_name` on
the next publish run, nor should a manifest wording change require touching the seed schema
author's file. The two dicts hold the same two values today; if they ever drift, the fix is to keep
them in sync by hand, the same maintenance cost `SHORT_CITY_NAMES`/`DISPLAY_NAMES` already carried
and that task #237 does not make any worse.

#### Sequencing — the seed this ships against, and the one CI still serves

The canonical seed every worktree gets (`Tools/setup_worktree.sh`) and CI fetches
(`Tools/fetch_seed.sh`) is still the published **s15** file as of this writing — publishing the s16
rebuild is the owner's step, deliberately deferred past this PR (the brief said not to publish, and
this PR does not). This branch's own worktree rebuild (`python3 Tools/build_seed.py --sj-extent
downtown`, matching the canonical invocation read out of the current seed's own `seed_meta`:
`trees_source=sf_city`, i.e. the default `--source city`; `sj_ship_extent=downtown`;
`city_raw_populated=0`, i.e. no `--with-city-raw`) is the first file that carries `dim_city`, and it
reproduced the canonical row count exactly: `trees written 198,625` against the current seed's own
`seed_meta.rows_kept = 198625`.

Both directions were run for real, not just reasoned about:

- **Against this branch's own s16 rebuild** (`Cypress/Resources/cypress-seed.sqlite` and
  `Fixtures/seed/cypress-seed.sqlite`, both replaced by the rebuild): full `CypressTests` suite —
  1249 tests, 124 suites, green. The new `dim_city`-gated real-seed test activated and passed; the
  s15-gated `CivicShortNameTests` real-seed test self-deactivated (skipped), because the rebuilt
  seed no longer carries `short_name` at all.
- **Against the actual published s15 seed** (temporarily swapped in from the untouched main
  checkout, to stand in for what CI fetches, then swapped back): same full suite, same 1249 tests,
  124 suites, green. The `dim_city`-gated test skipped (honestly — the file cannot answer it) and
  the `short_name`-gated test activated and passed, the inverse of the run above. This is the
  concrete check that CI stays green on this branch without needing the s16 seed published first.

#### Red-proofs

All three broken, watched red for the stated reason, restored, reconfirmed green.

| break | result |
|---|---|
| `TreeQueries.treeSQL()`'s `dim_city.display_name` projection short-circuited to never fire (`if false && hasResolvableDimCityName`) | `DimCityTests`: 5 issues — `aFixtureWithDimCityResolvesTheCity` failed on both rows (`cityShortName → nil` where `"San Francisco"`/`"San Jose"` were expected, and the SF≠SJ control), `queryPlanJoinsDimCityByRowid` failed because the plan no longer contained the `dc` step, and the real-seed test failed the same way as the fixture test. |
| `hasResolvableDimCityName` computed as `schema.hasDimCity` alone, dropping the `&& schema.hasIdSpace` guard (the PR #29-shaped defect, reproduced against `dc` instead of `isp`) | `DimCityTests.aFixtureWithDimCityButNoTreeIDSpaceStillPrepares` failed with `Caught error: SQLiteError(1/1): no such column: isp.city_id` — a prepare-time SQL error, not a null result, exactly the failure mode the test exists to catch. |
| `Tools/build_seed.py`'s `DIM_CITY` dict had its `"sf"` key renamed to `"sf_TEMP_REMOVED"` | `python3 Tools/build_seed.py --sj-extent downtown --limit 500` died with `FATAL: no dim_city row registered for id space(s) ['sf'] in DIM_CITY -- civic facts are entered, never derived` before writing a seed file. |

#### Left alone, deliberately

- **`Fixtures/raw/`'s cached upstream snapshots** — copied into the worktree from the main checkout
  to run the canonical rebuild, not regenerated with `--fetch`. This is a reproduction of the
  existing canonical seed's provenance, not a new snapshot; a future refresh of the underlying
  city data is a separate concern from this table's schema.
- **`AppSchema` / the writable database** — untouched. This round's addition is entirely in the
  SEED schema space; no migration was needed or written, per the ticket's own explicit warning
  about the two version spaces colliding at the number 14.
