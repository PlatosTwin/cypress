# PENDING — The UI suite inherits the device's state, and two kinds of leftovers read as broken screens

*Unnumbered on purpose. The orchestrator splices this under the real next number at merge
(CLAUDE.md, Numbering). Both halves found closing #157 (city downloads), 2026-08-02, on iPhone 16
Plus `24D1629F-9FA8-4E3D-812E-F6BC85C9E668`. Neither is a defect in #157's diff; both are false
reds that cost an afternoon each if the next agent believes the failure text.*

## A. A leftover city choice: 33 failures that all say the map is broken

The unit suite was green (`Test run with 1016 tests in 96 suites passed`) and the full suite on the
same commit, same simulator, was red: 33 of 64 `CypressUITests` cases failed in one run. Every
failure said the same thing —

    DEEP LINK FAILED · a standing tree · none among the 0 records nearest 37.7596, -122.…

— and `AlmanacGroupTapTests` added `screen 01 drew no tree pins in thirty seconds`. Nothing in the
diff touches the map, the deep link, or the seed.

The cause was on the device. A live smoke an hour earlier had downloaded San Jose and tapped
`Use`, which is exactly what #157 built: the choice is a marker file at
`Application Support/Cypress/cities/active-city`, and it **survives reinstall**, because
`xcodebuild test` replaces the app bundle and leaves the data container alone. So every case
launched against an inventory holding San Jose and nothing else, while every deep link asks for a
tree near **San Francisco**. Zero records is the honest answer. The app was right; the assertion
was asking the wrong device.

Deleting the marker and re-running the same target on the same commit: `Executed 64 tests, with 8
tests skipped and 0 failures`.

**Why it will keep happening.** Before #157 the attached inventory was the bundle, always, so no
test needed to say so. It is now a reader preference that persists in the data container.
`CYPRESS_SEED_PATH` is a unit-target convention only (`SeedContractTests`); nothing on the app side
reads it, so it cannot pin the UI target's inventory.

## B. A leftover camera: two Almanac failures, and a confident comment that is wrong

With the marker cleared, a later full run still failed twice, both in `AlmanacGroupTapTests`, both
at `AlmanacGroupTapTests.swift:231`:

    screen 01 drew no tree pins in thirty seconds, which it does with a fix and without one

Also mine, also device state — the same smoke had left the map pinched out over the Bay Area, and
screen 01 reopens where it was left (`MapCameraMemory`, `map.lastCamera` in `UserDefaults`, #128).
The stored value read `[37.065701, -122.166977, 1.659115, 1.065655]`: a 1.66°-wide camera, well
inside `MapCameraMemory.maximumSpanDegrees` (10) and therefore restored, at which zoom the map
draws cluster badges rather than tree pins. `cityTreePins(app) > 0` is then never true. Deleting
that one default let both tests reach their own location guard again (they `XCTSkip` on this
fixless device, which is what they do on a clean one too — they are 2 of the suite's 8 skips).

The comment above that assertion says screen 01 "opens at `MapLayout.defaultSpanMetres` — 120 m
across — either way, and only the centre differs". **That is false whenever a camera is
remembered**, which is any device a human or an agent has actually driven. The measurement it
records was taken before the camera was remembered across launches; it was true then and has not
been true since. It is the CLAUDE.md rule about confident comments, caught in the act: the comment
is what makes the failure look like a map regression instead of a stale default.

## What to check before believing a red map

    C=$(xcrun simctl get_app_container <udid> app.cypress.Cypress data)
    cat "$C/Library/Application Support/Cypress/cities/active-city"        # absent = built-in
    /usr/libexec/PlistBuddy -c Print "$C/Library/Preferences/app.cypress.Cypress.plist"

An id in the first is the suite reading that city (delete the file — that is exactly
`CityLibrary.deactivate()`). A wide `map.lastCamera` in the second is the suite reading cluster
badges (delete the key with the app not running, or it is rewritten on exit).

## The fix this deserves, and what it is not

Not a change to the app. Persisting the inventory choice is the ruling (city-downloads §1/§4) and
persisting the camera is #128; a "reset on launch" seam would make the two things they must get
right untestable on a real device.

The honest fix belongs to the harness: the UI target should **assert the device state it needs
rather than inherit it** — fail fast, with a readable message, when `active-city` exists or
`map.lastCamera` is wider than the screen a test is about, so the suite says *"this device is set
to us-ca-sj"* instead of thirty-three variations of *"0 records"*. Deliberately out of scope for
#157: the ticket's tree is green on a clean device, and a change to every UI test's setup is a
change every other live branch inherits at merge (CLAUDE.md, shared files). `AlmanacGroupTapTests`'s
comment should be corrected in the same change.
