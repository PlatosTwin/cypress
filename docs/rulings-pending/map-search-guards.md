### Screen 01's opening camera does not gain a test-only door, and the search UI tests read the viewport instead

Tasks #104 and #101. Not a design decision about anything a person sees — recorded here because the
obvious repair *would* have been one, and the next reader of `MapSearchUITests` will think of it
within a minute.

**The question.** `testTypingASpeciesNameNarrowsTheMap` needs a viewport that holds the species it is
about to search for. There are two ways to get one:

1. **Tell the app where to open.** `DebugDeepLink` already establishes the pattern — a `#if DEBUG`
   environment variable the UI test target sets, read at launch, compiled out of Release. A
   `CYPRESS_MAP_CENTRE=lat,lon` beside `CYPRESS_SCREEN` would pin screen 01's camera, and the test
   could then assert unconditionally and never skip.
2. **Ask the map what it is holding, and search for that.** The pins already name their own species
   once the map colours them, so a black-box test can read the viewport's census off the
   accessibility tree and pick its query from it.

**The ruling: (2), and (1) is deliberately not built.**

- **A camera door is product surface with a test's name on it.** `DebugDeepLink` earned its exception
  by reaching sixteen screens that a test otherwise cannot reach at all (E117); nothing here is
  unreachable. Screen 01 is the app's default screen and its opening camera is being actively
  reworked (task #115 — it should open on the person, or on a persisted camera). A second mechanism
  that overrides that camera at launch is a second answer to the question #115 is deciding, added by
  a test, in the same week.
- **Pinning the camera would only move the assumption.** A test that pins `37.78485,-122.4215` and
  searches `Platanus` still hardcodes a fact about the seed at a coordinate; it is the same defect as
  #104 with a longer fuse — it just fails on the day the inventory changes rather than on the day the
  machine's location does. Reading the viewport has no such expiry.
- **The cost is accepted openly: this test can skip.** Over a park, over the ocean, or over a street
  of one species, it reports "not checked here" rather than a green tick. That is the honest report,
  it names the census it found and the fix in its own message, and it has been shown firing. The
  alternative — a test that cannot skip because it forced its own preconditions into the app — is
  how this file got a guard that could not fire in the first place.

**What this does not decide**, and is left to whoever takes #115: whether screen 01 should have a way
to be opened on a given coordinate at all, for screenshots or for a share link. If one is ever built
for a product reason, these tests may use it, and should then assert instead of skipping.
