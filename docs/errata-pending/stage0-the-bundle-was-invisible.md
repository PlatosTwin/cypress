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

### 1a. The first fix re-opened the defect through a type that could not tell presence from freshness

Found by adversarial review, on the branch, before merge. Worth its own entry because the shape is
general and the single-gate argument did not catch it.

`CityInstallState.bundled` carried a **non-optional** `contentRev`, so the caller had only one
`nil` to say two different things with: *"the bundle does not hold this city"* and *"the bundle
holds it and no record date derives."* The second fell through to `.notInstalled`, whose
`allowsDownload` is `true` — `81 MB`, a `Download` button, and a transfer that started, for a city
inside the app. The owner's original report, from the fixed build.

**`allowsDownload` being the single gate did not help, because the gate was asked the wrong
question.** The state was already wrong before anything consulted it. A single source of truth
protects against two answers to one question; it does nothing about one answer to the wrong one.

**Reachable, and the reachability is a transliteration seam.** `Tools/build_seed.py` writes San
Jose's snapshot date as `sj_meta.get("extracted_on", "")` — an empty-string default with no `die()`
behind it, where the San Francisco path at the same file's `load_city_layer` does have one. So a
bundle can genuinely ship a city whose `content_rev` does not derive. `SeedCities.contentRev`
correctly skips empty snapshots, matching the publisher's `if snap:`; what diverges is what the two
sides *do* about it. `content_rev_for` calls `fail()` and the publish stops. A read on a reader's
phone cannot usefully refuse to answer, so it returns nil — and the caller then read nil as
absence.

**The rule this leaves behind:** when a transliteration's source treats a case as fatal, the port's
non-fatal answer for that case is a new value that did not exist upstream, and every caller has to
be told what it means. `SeedCities.City`'s own doc comment now says presence is the `id` and
nothing else, and `CityInstallState.init` takes the whole `SeedCities.City` rather than a
`String?`, so a caller cannot hand it a record date without also handing it a city.

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

## 4. A guard whose offline half could not see the defect it named

`BundledCityTests.aCityCanNeverOccupyTwoRows` asserted the no-duplicate-rows invariant on both the
loaded and the offline path. The offline half read `model.rows` before any `load()`, and
`CityDownloadsModel.installed` is populated only inside `load()` — so the fold it was checking was
`[] + bundledIDs`, which has nothing to deduplicate. Removing the deduplication left those two
assertions **green**, proven by re-running the round's own red-proof: only the loaded assertions
failed.

Squarely the guard-green-when-the-defect-is-present shape, and on the one path the fold exists for.
The fix is to make the catalog unreachable and `await load()` before reading rows: the disk facts
land, the catalog does not, and the offline branch is exercised for real. Under the same break it
now reports `["built-in", "sf", "sf", "us-ca-sj"]`.

**The tell, for the next reader:** the assertion named a precondition (*"disk plus bundle both name
`sf`"*) that no line in the test had established. A precondition a test states in prose and does
not assert is a precondition it does not have — `#expect(model.installed.map(\.id) == ["sf"])` is
now in the test, above the assertions that depend on it.

## 5. Two rulings taken by the owner on this round, 2026-08-14

Both surfaced by the adversarial review as judgment calls rather than defects, and both ruled the
same day. Recorded here because they are decisions about what a screen says, not implementation
detail, and the next round should not re-open them by accident.

- **A bundled city whose published entry is a newer schema generation keeps `Included in the app`.**
  The row states neither the format refusal (`needsNewerApp`'s detail line) nor the fact that a
  newer record exists. Both branches draw no button, so nothing promises what it cannot keep;
  what such a row owes the reader is revisited by the round that bumps the published format, not
  before. Pinned by `BundledCityTests.futureSchemaIsRefusedBothWays`.
- **The offline screen shows the same cities as the online one.** A bundled city keeps its card
  when the catalog is unreachable rather than disappearing with the network. R43 §3's fetch-failure
  sentence lists *"the built-in card, every installed city from disk facts alone"* and predates the
  app being able to read its bundle at all; the ruling extends it rather than contradicting it.
  Pinned by `BundledCityTests.aCityCanNeverOccupyTwoRows`.

## What this round deliberately did not do

- **No schema change in any of the three version spaces.** `AppSchema.currentVersion`,
  `SeedDatabase.newestKnownSchemaVersion` and `CityManifest.knownFormat` are all untouched, which
  is Stage 0's defining property.

**Coverage from the bundle was briefly in this list and is not any more.** It was omitted on the
argument that an offline row had never drawn a coverage note — true of `installedOffline`, which
describes a *downloaded* city, and not of the new bundled row, which is a city card by R43 §3's own
definition and was the one place the fact was available and unstated. §3.3 lists coverage as one of
the four things Stage 0 derives from the bundle and §6.1 — the text D5 approved *as scoped* —
repeats it, so the omission was a deviation from approved scope that a reviewer should not have had
to catch. It is read now (`SeedCities.coverage`), and San Jose's `Covers downtown only` survives the
network going away.

The `COVERAGE_KEYS` duplication that argued against it is real and is handled rather than avoided:
`SeedCities.coverage` prefers the standardized `coverage_<id_space>` key R37 plans, so the shim is
dead rather than wrong on the day `build_seed.py` writes it, and
`BundledCityTests.everyPublisherCoverageKeyIsMirrored` parses `COVERAGE_KEYS` out of
`Tools/publish_cities.py` and fails if the two tables disagree.
