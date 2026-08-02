# STATE — ticket #157 (city downloads), branch p1/city-downloads

Written for a successor agent. Worktree: /Users/nikitabogdanov/PycharmProjects/cypress-w4dl.
Simulator (yours alone): iPhone 16 Plus 24D1629F-9FA8-4E3D-812E-F6BC85C9E668 (currently Booted).
Private DerivedData: <scratchpad>/dd-w4dl/ where scratchpad =
/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad

## Done and committed
- docs/rulings-pending/city-downloads.md — the ruling (the surface's mock). Key decisions:
  ONE inventory attached at a time under the `seed` schema (bundle default, or one downloaded
  city); switching re-boots the DataLayer; You tab "City data" section → Route.cityDownloads
  "Cities" screen; exact copy strings are in the ruling §3 and mirrored in CityDownloadsCopy.
- Data layer (Cypress/Data/Cities/): CityManifest (format-1 strict decode), CityInstallState
  (pure compare, refuses schema_version > SeedDatabase.newestKnownSchemaVersion = 14),
  CityLibrary (App Support/Cypress/cities/<id>/<version>/<id>.sqlite mirror, .staging dir,
  atomic install + new-then-prune, `active-city` marker file, validateCityFile = introspect +
  publish_schema_version gate read from the file itself), CityDownloader (GET only, sha256
  via CryptoKit + byte count verified BEFORE install, base URL constant
  https://cypress-cities.t3.tigrisbucket.io per R37.4, file:// injectable for tests).
- CypressStore.seedUndatedShare measured at open; MapYearFilterCopy.setAside(undatedShare:)
  derives the year caveat (fused share 0.8078 must reproduce the constant sentence VERBATIM —
  pinned in tests); threaded RootView → MapHomeView → MapFilterStatus.
- DataLayer.bootPreferringActiveCity(library:) — validated marker → city file, else bundle;
  AppModel.boot uses it; AppModel.reboot() + CypressApp keys RootView identity to
  ObjectIdentifier(data.store) and passes onInventoryChange: { model.reboot() }.
- Features/Cities/: CityDownloadsPresentation (copy + pure row builder — every ruling §3
  branch), CityDownloadsModel (@Observable; one download at a time; cancel; use/remove trigger
  onInventoryChange), CityDownloadsView (You-tab card idiom, ProgressRing for progress).
  YouTabView gained citiesSection + onOpenCities; RootView destination .cityDownloads.
- CypressTests/CityDownloadTests.swift — 10 tests (decode, refuse format 2, install-state
  branches incl. refuse-newer-schema, sha mismatch installs nothing, size mismatch, verified
  install + failed-update-leaves-v1 + prune, activation refuses schema 99 & clears marker,
  dangling marker, measured undated share via mini seed, setAside sentences, row presentation).

## Verified LIVE (2026-08-02, this session)
- Manifest GET works anonymously on https://cypress-cities.t3.tigrisbucket.io/manifest.json.
  City ids are `sf` and `us-ca-sj` (BRIEF SAID us-ca-sf — WRONG, verified).
- 1-byte range GET → 206 for manifest + both city files.
- Full download of us-ca-sj: 27,975,680 bytes, sha256
  c1ea8e0bfcf708af9d9d95e2df5552de18ccf085f1a6afacb109894224a3d667 — matches manifest exactly.
  File's own seed_meta: publish_city_id=us-ca-sj, publish_schema_version=14, rows_kept=52788.
  Live copy at <scratchpad>/sj-live.sqlite.

## In flight RIGHT NOW
- Background build (id br683fyrh) → <scratchpad>/dd-w4dl/build3.log. Previous errors fixed:
  build1 = CypressStore guard destructure; build2 = RootView init missing onInventoryChange
  param (fixed by adding it to the explicit init). Judge by grep error:/TEST BUILD SUCCEEDED
  in the log, NEVER the exit code.

## Next steps, in order
1. When build3.log is clean: run the unit suite:
   Tools/run_tests.sh 24D1629F-9FA8-4E3D-812E-F6BC85C9E668 <scratchpad>/dd-w4dl/unit.log \
     -derivedDataPath <scratchpad>/dd-w4dl -only-testing:CypressTests
   Judge with Tools/verify_test_log.sh; the only meaningful line is "Test run with N tests
   passed". Camera grant is handled by the script.
2. Prove new tests can fail: e.g. invert sha comparison in CityDownloader (watch
   checksumMismatchInstallsNothing go red), and change setAside table "4 in 5"→"4 in 6";
   restore both. Record red output.
3. Full suite (drop -only-testing) for the zero-warning line + no regressions
   (MapFilterTests.plantingDateCoverageMatchesTheCopy must still pass — bundled fused seed
   unchanged).
4. Simulator smoke: install the built app, open You tab → Cities, screenshot; optionally
   download us-ca-sj live on the sim and Use it (look at the running screen; map should draw
   SJ only). App bundle in dd-w4dl/Build/Products/Debug-iphonesimulator/Cypress.app.
5. If any defect found along the way: unnumbered note to docs/errata-pending/.
6. Report: ruling shape, attach mechanics, test names, VERIFY-OK line, live-smoke result
   (above), branch + final commit.

## Watch out
- Never edit project.pbxproj (synchronized root group — new files compile automatically).
- No schema migration is allowed in this ticket (none was needed; app_state untouched — the
  active choice is a marker FILE, deliberately).
- MapFilterStatus default yearCaveat keeps old callers exact; RootView passes the derived one.
- CityDownloader progress: URLSession.bytes byte-loop with 512 KiB flushes; cancellation →
  CancellationError → model treats as silent revert.
