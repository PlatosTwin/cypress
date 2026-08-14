# Unnumbered — the app could not read its own bundle, and three entries blamed the wrong artifact (Stage 0, city data distribution)

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `feat/stage0-bundle-truth`, the round that implemented
Stage 0 of `docs/design-proposals/2026-08-14-city-data-distribution.md` (owner ruling D5).

Three findings. The second is a correction to entries already in `docs/ERRATA.md`, and the third
corrects the citation the design proposal itself used for it.

---

## 1. The Cities screen offered an 81 MB download of a city the app was drawing

The owner's report, verbatim in the design proposal: *"i can download from sf and sjc even though
those ostensibly ship with the app"*.

`CityDownloadsModel.rows` built each city's state as
`CityInstallState(published:installedVersion:)` where `installedVersion` came from
`CityLibrary.installedCities()`. `CityLibrary` reads `Application Support/Cypress/cities/` and
nothing else — it is the record of what was **downloaded**. The bundled seed is not in that
directory and has no entry there by design, so `sf` resolved `.notInstalled`, and
`CityDownloadRow.decide` returned `(CityDownloadsCopy.size(city.bytes), nil, [.download])`: `81 MB`
and a `Download` button, for 145,837 trees already on the map.

**The root cause is not the comparison, it is that nothing anywhere asked the bundled seed which
cities it held.** Every fact needed was inside the file the app already has open —
`id_spaces.id`, `dim_city.display_name`, and `Tools/publish_cities.py`'s own `content_rev_for`
rule over `seed_meta` — and no code path read any of it. `CityLibrary`'s own doc comment records
the assumption that made this invisible: *"Disk is the record."* That was right for downloads and
silently wrong for the bundle, which is installed in every sense the reader cares about and in
none the directory layout can express.

Fixed by `Cypress/Data/Cities/SeedCities.swift`, which lifts those three facts out of any seed or
city file, and by `CityInstallState.bundled` / `.bundledOutdated`, the two row states the owner's
ruling D5 added to R43 §3's enumeration.

**A second consequence, one press of the button further along.** Downloading `sf` left the reader
with two rows for San Francisco — `Built-in inventory` and `San Francisco` — and a `Use` that
switched between two copies of the same data with no way to tell them apart. Closed structurally
rather than by the fix above alone: `CityDownloadsModel.rows` folds catalog, library and bundle ids
to a unique ordered sequence *before* any row is made, and `CityDownloadsModel.download` refuses on
the same `CityInstallState.allowsDownload` the row draws its button from, so no caller can start a
transfer the screen would not offer.

## 2. `CityManifest.City` does carry a bbox and a centroid — the data side was never the blocker

**E209 shape B3**, **E213** and **E238** each state that a per-city center is unavailable because
*"`CityManifest.City` carries no center or bbox to derive one from"*, and E238 files the fix as
*"a different, wider ticket"*. E213 declined `MapKitBasemap.defaultCentre` for the same stated
reason.

**That is true of the Swift type and false of the artifact.** `Tools/publish_cities.py` has emitted
`bbox` (min/max lat and lon) and `centroid` for every city since the original #156 commit, and both
keys are in the live manifest — fetched 2026-08-14, San Francisco's bbox is
`lat [37.70802, 37.819956]`, `lon [-122.511131, -122.366622]`, its centroid
`{37.763988, -122.438877}`. `CityManifest.City` simply did not decode them, and R37.4's tolerance
for additive keys is why it did not have to.

The blocker named in all three entries was two `Decodable` properties. They are decoded now
(`CityManifest.City.bbox`, `.centroid`, both optional so a manifest predating them still decodes),
along with `content_rev`, which is likewise an existing key this reader had never looked at.

**`MapKitBasemap.defaultCentre` is still untouched** — this round is Stage 0 and the opening-camera
work is Stage 2 (§7 of the design proposal). What changes is why it is deferred: it is a decision
about the map's opening state, not a missing data field.

## 3. The design proposal cites E214 where it means E238

`docs/design-proposals/2026-08-14-city-data-distribution.md` §1.2 attributes the "no center or
bbox" claim to *"E209 shape B3, E213 and E214"*. E214 is #106's premise round — San Francisco Rec
& Park publishes no tree inventory — and says nothing about the manifest. The third entry carrying
the claim is **E238** (E209's Shape A, fixed), in its "Left alone, deliberately" section. §6.1 of
the proposal repeats the same citation. Recorded here rather than corrected in the proposal, which
is a dated design document.

## What this round deliberately did not do

- **Coverage from the bundle.** §3.3 lists coverage as one of four facts the bundle could state.
  It is not read: an online row already takes `coverage` from the manifest entry, and an offline
  row has never drawn a coverage note (R43 §3's `installedOffline` shape). Reading it would mean
  transliterating `publish_cities.py`'s hand-entered `COVERAGE_KEYS` shim into Swift for no visible
  change — and R37's trailing clause plans to retire that shim when `build_seed.py` writes
  `coverage_<id_space>` keys. Left for whichever round needs it to draw something.
- **No schema change in any of the three version spaces.** `AppSchema.currentVersion`,
  `SeedDatabase.newestKnownSchemaVersion` and `CityManifest.knownFormat` are all untouched, which
  is Stage 0's defining property.
