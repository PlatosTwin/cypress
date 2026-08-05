### EXXX — E209's Shape A, fixed: `id_spaces.short_name` in the seed, the share card off it (task #233)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `feat/e233-civic-short-names`. Latest numbered at time of writing: E222, R60.*

---

#### What E209 left open, and the decision that closes it

E209-A1 named the one surviving Shape A member: `SharePresentation.ShareCopy.city` hardcoded
`"San Francisco"`, true only while the seed held one city, so every one of San Jose's 52,788
trees was captioned with the wrong city on screen 10's share card. E209 recorded why it was not
fixed there — no table anywhere carried a short, reader-facing city name; `id_spaces` had `id`,
`identity_prefix` and a prose `note`, and `inventories.name` is the inventory's own published
name ("SF Public Works street tree inventory"), not a city's.

The owner's decision (2026-08-05, this round): the short name is a hand-maintained mapping in
`Tools/build_seed.py`, emitted into the seed itself as `id_spaces.short_name`, so one seed publish
covers both this and the `species_trigrams` work (#227/E165) already merged into the same
unpublished generation.

#### The premise checked before building on it

Neither addition had shipped. Fetched the live manifest directly
(`https://cypress-cities.t3.tigrisbucket.io/manifest.json`, 2026-08-05): both `sf` and `us-ca-sj`
are still `"schema_version": 14`, `"version": "s14-r2026-07-31-d3e3d229"` — the same publish E219
recorded. So this folds into **s15** rather than minting s16, and `SeedDatabase.newestKnownSchemaVersion`
(already 15, bumped for #227) needed no further bump — only its doc comment, which now names both
additions the generation carries.

This is the SEED schema space (`SeedDatabase.newestKnownSchemaVersion` /
`Tools/publish_cities.py`'s `SEED_SCHEMA_VERSION`), not the WRITABLE database's
(`AppSchema.currentVersion`) — the two are unrelated and this round touches only the first. No
`AppSchema` migration was needed or written.

#### What was added

- `Fixtures/seed/schema.sql` / `Tools/build_seed.py`'s embedded `SCHEMA_SQL` (kept byte-identical,
  as always): `id_spaces.short_name TEXT NOT NULL CHECK (short_name <> '')`.
- `Tools/build_seed.py`'s `SHORT_CITY_NAMES` — `{"sf": "San Francisco", "us-ca-sj": "San Jose"}` —
  the same two civic strings `Tools/publish_cities.py`'s `DISPLAY_NAMES` already ships in the
  manifest's `display_name` field, entered independently rather than imported (the two publishers
  are separately owned by design) but not invented: copied from an already-shipped, already
  owner-approved source. A contributing id space with no entry fails the build loudly, the same
  shape as `DISPLAY_NAMES`'s own refusal.
- `SeedSchema.hasCivicShortNames` — introspected via `columnNames(ofTable: "id_spaces")`, never a
  version compare, the same instrument `hasCityRaw`/`hasInventorySource` use for a column (rather
  than `hasSpeciesTrigrams`'s `tableExists`, which is the right shape for a new table but not for a
  column added to an existing one).
- `TreeQueries.tree(id:)` gained a `LEFT JOIN id_spaces isp ON isp.id = t.id_space`, conditioned on
  `schema.hasIdSpace` (not merely `hasCivicShortNames`) so the join itself is omitted — not merely
  its column — on a seed with no `id_spaces` table at all. `TreeRecord.cityShortName` and
  `TreeProfile.cityShortName` carry the answer to `SharePresentation.locationLine`, the same shape
  as the existing `neighborhoodName` (a fact the seed keys by string, not by an id `Tree` already
  carries).

#### The fix, and the fallback

`SharePresentation.locationLine` no longer reads a constant. It reads `profile.cityShortName` and
falls back **honestly** — never to a guessed or stale city:

- known address, known city → `"<address> · <city>"` (unchanged shape)
- known address, no known city → `"<address>"` (no dangling separator — the new half)
- no address, known city → `"<city>"` (unchanged)
- neither known → `""` (silence, not a placeholder)

"No known city" is not an error state — R37.3 already establishes that the bundled seed and a
downloaded city file are legitimately different generations at once, so an s14 San Jose beside an
s15 bundle, a pre-`id_space` row, or a community-added tree (which never has an id space) are all
ordinary. `ShareCopy.city` is deleted; nothing else in the app referenced it.

#### Tests

`CypressTests/CivicShortNameTests.swift` proves the introspection-gated path against three built
fixtures — `id_spaces.short_name` present, `id_spaces` present without the column, and `id_spaces`
absent entirely (the dangerous case: a `LEFT JOIN` against a table that is not there is a SQL
error, not a null result, and this is what proves the join is conditioned on `hasIdSpace` rather
than only on `hasCivicShortNames`) — plus a real-seed check gated `.enabled(if:)` the same way
`SpeciesTrigramTests` gates its four: the canonical seed on every tree is still s14 and cannot
answer it yet, so that one test is currently disabled and reactivates on its own once a seed built
by this branch's `build_seed.py` is canonical. `CypressTests/SharePresentationTests.swift` gained
four cases for the fallback matrix, including the regression case by name — a San Jose tree's card
must not read "San Francisco".

**Red-proofed, twice, and read for the reason:**

| break | result |
|---|---|
| `SharePresentation.locationLine`'s `city` reset to the literal `"San Francisco"` | 8 issues, `SharePresentationTests`: every new fallback/San-Jose case failed with the exact wrong string named (`"Great Highway at Judah · San Francisco"` where San Jose was expected, `"San Francisco"` where the empty-line case was expected) |
| `TreeQueries.tree(id:)`'s `city_short_name` column forced to `NULL` unconditionally | 3 issues, `CivicShortNameTests.aFixtureWithShortNamesResolvesTheCity`: both rows resolved to `nil` instead of their own city, and the SF/SJ-disagree control failed too |

Both restored and reconfirmed green before this was filed.

#### What was refuted

- **"An s15 seed has been published somewhere and this needs s16."** Checked against the live
  manifest directly rather than assumed: false, both cities are still s14.
- Nothing else in E209/E213's list needed reopening — E213 already confirmed Shape B is separate
  and fixed, and E209 itself states Shape A had exactly one member left (`ShareCopy.city`); a
  fresh grep for a second hardcoded city name in reader-facing copy found none.

#### Left alone, deliberately

`MapKitBasemap.defaultCentre` (E209's Shape B item, `MapKitBasemap.swift:312`) is untouched — it
needs a per-city center `CityManifest.City` does not carry, which is a different, wider ticket, and
E213 already declined it for the same reason.
