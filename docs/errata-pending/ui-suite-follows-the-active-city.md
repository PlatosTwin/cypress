# PENDING — The UI suite reads whatever inventory the device has chosen, and a leftover choice reads as 33 broken screens

*Unnumbered on purpose. The orchestrator splices this under the real next number at merge
(CLAUDE.md, Numbering). Found closing #157 (city downloads), 2026-08-02, on iPhone 16 Plus
`24D1629F-9FA8-4E3D-812E-F6BC85C9E668`.*

## What happened

The unit suite was green (`Test run with 1016 tests in 96 suites passed`) and the full suite on
the same tree, same commit, same simulator was red: 33 of 64 `CypressUITests` cases failed inside
one run. Every failure said the same thing —

    DEEP LINK FAILED · a standing tree · none among the 0 records nearest 37.7596, -122.…

— and `AlmanacGroupTapTests` added `screen 01 drew no tree pins in thirty seconds`. Nothing in the
diff touches the map, the deep link, or the seed.

The cause was on the device, not in the tree. A live smoke run an hour earlier had downloaded San
Jose and tapped `Use`, which is exactly what #157 built: the choice is a marker file at
`Application Support/Cypress/cities/active-city`, and it **survives reinstall**, because
`xcodebuild test` replaces the app bundle and leaves the data container alone. So every UI case
launched against an inventory that holds San Jose and nothing else, and every deep link asks for a
tree near **San Francisco** (37.7596, -122.…). Zero records is the honest answer. The app was
right; the assertion was asking the wrong device.

Deleting the marker and re-running the same target on the same commit turned the same cases green.

## Why it is worth a number

1. **It is a false red, and this project's cheapest lie is a green — but a red that is not yours
   costs the same afternoon.** The failure text names the map and the deep link, so the obvious
   first suspicion is the map or the deep link. It is neither, and nothing in the log points at
   `active-city`.
2. **The UI target is not hermetic about the attached inventory, and as of #157 it never can be by
   accident.** Before #157 the attached inventory was the bundle, always, so no test needed to say
   so. Now the seed under the suite is a *reader preference* that persists in the data container.
   `CYPRESS_SEED_PATH` is a unit-target convention only (`SeedContractTests`); nothing on the app
   side reads it, so it cannot be used to pin the UI target's inventory.
3. Any agent that runs a live smoke of the Cities screen and then runs the suite reproduces this,
   in that order, every time.

## What to check before believing a red map

    C=$(xcrun simctl get_app_container <udid> app.cypress.Cypress data)
    cat "$C/Library/Application Support/Cypress/cities/active-city"   # absent = built-in

An id there means the suite is reading that city. Delete the file (that is exactly what
`CityLibrary.deactivate()` does) and the bundle attaches again.

## The fix this deserves, and what it is not

Not a change to the app's behavior: persisting the choice across launches *is* the ruling
(city-downloads §1/§4), and a "reset on launch" seam would make the one thing #157 must get right
untestable on a real device.

The honest fix belongs to the harness — the UI target should assert the inventory it is reading
rather than inherit it. Cheapest version: a shared `XCTestCase` setup step that fails fast with a
readable message when `active-city` exists, so the suite says *"this device is set to us-ca-sj"*
instead of thirty-three variations of *"0 records"*. It is deliberately left out of #157: the
ticket's own tree is green on a clean device, and a change to every UI test's setup is a change
every other live branch inherits at merge (CLAUDE.md, shared files).
