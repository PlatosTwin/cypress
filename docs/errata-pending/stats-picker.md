# Pending errata — the neighborhood/city stats picker round (`feat/stats-picker`)

Unnumbered, per CLAUDE.md. The orchestrator splices these under the real next E-numbers at merge and
rewrites the code comments that cite this filename.

---

### E??? — F17's mechanism was never "the nearest tree is far away". The fix's own accuracy was carried and never read.

**The report** (tester, build 49, 2026-08-23, PR #118's verbatim table, item 17):

> "I am nowhere near Castro/upper market and am out of the city closest to marina. Why does this
> page seem to default to showing stats for Castro/market in this instance?"

**The premise everybody carried forward was wrong.** ROADMAP's own entry described it as
"neighborhood stats far from home" and the round's brief restated it as "a reader far from any tree
gets the nearest tree's neighborhood". Measured against the shipped code, that state does not
exist: `SpeciesQueries.resolveNeighborhood(near:)` is bounded at **400 m** and
`CityQueries.resolveIDSpace(near:)` at `AlmanacLimits.fallbackRadiusM` (**1,200 m**), and beyond
those the almanac already drew E182's out-of-range screen and named nothing. A reader genuinely far
from the record was, and had been, handled honestly.

**What the code does support is the opposite geometry.** `MapLocationProvider.Availability.located`
carries `accuracyM`, and **nothing on the path from it to either stats segment ever read it** —
`JournalTabView` took a bare `Coordinate?`. So a fix good to ±5 m and a fix good to ±3,000 m were
treated identically: search 400 m around the point, take the nearest tree's neighborhood, print the
name in the header as plain fact. iOS returns the second kind whenever the reader has granted
**approximate** rather than precise location — a point snapped to a large region tile.

Two facts make that the mechanism rather than a theory:

- measured against the shipped seed on this branch, the nearest inventoried tree to the middle of
  San Francisco (`MapLayout.defaultCenter`, 37.7596/−122.4269) is in **Castro/Upper Market** — the
  name the report says the screen "seems to default to";
- the app requests `kCLLocationAccuracyBest` and **never consults `accuracyAuthorization`**, so a
  reduced-accuracy grant is invisible to it. `grep -rn "accuracyAuthorization" Cypress/` returns
  nothing.

**What is NOT established**, and is stated so nobody later reads this as proven: the tester's actual
coordinate. The ASC artifact is screenshots with no location metadata, one tester on one device
(E254's own warning). The mechanism above is the only one in the code that produces the reported
symptom; that is not the same as a receipt.

**The fix.** `AlmanacLimits.fixCanResolveAnArea(accuracyM:)` — a fix whose own error circle is wider
than the circle we search cannot pick out a tree inside it, so it is not used to place the reader at
all, and the screen says so and offers the picker instead. An unknown accuracy is permitted, which
is the direction that leaves previews and tests unchanged.

**The near-miss on the way in.** ROADMAP's own "confident comments" list already carries
`RootView` "explaining that the location provider carried no accuracy an hour after it started to".
The comment was corrected; nothing then asked what should *read* the accuracy now that it existed.

---

### E??? — `Tools/run_tests.sh` refuses a run when the shell that launches it merely mentions `xcodebuild`

**Three consecutive false refusals on this branch**, each reporting a live pid against the assigned
simulator, each with `ps -eo pid,lstart,command` showing no such process a second later.

`collision_check()` reads `ps -eo pid,command` and refuses on any line whose command string contains
`xcodebuild` and the target UDID or worktree path. It skips exactly one pid — its own, `$$`. It does
**not** skip its ancestors, and an agent's shell command routinely contains both: the literal name
of the tool (`ps aux | grep -F xcodebuild` appended to the same line that launches the run) and the
UDID (which is the script's first argument). The launching `zsh -c` is then a perfect match for a
collision with itself.

The refusal is indistinguishable from a real one, and the remedy it prints — inspect with `ps` —
shows nothing, because by then the shell has moved on. An agent that reads it as a real collision
kills processes that do not exist, or waits for a run that already ended.

**The guard is right to exist** (E202 is real and expensive) and the script's own comment is right
that bash string matching beats `grep [x]codebuild`. The gap is narrower than either: the exclusion
set is `{$$}` where it should also hold the script's ancestors, or the match should require the
command to *start* with an `xcodebuild` binary path rather than merely contain the word.

**Workaround while it stands, and it is a rule an agent can follow:** never put the string
`xcodebuild` in the same shell command that invokes `Tools/run_tests.sh`. Check for orphans in a
separate call, before or after.

---

### E??? — "this app has no city name to print" stopped being true at seed schema 16, and three comments still said it

`CityQueries`'s header states that "nothing in this file, and nothing built on it, prints a city's
proper name", `CityPresentation`'s header states the same rule for the screen, and `CityView.header`
says "no trailing pill, ever — this screen has no city name to put in one".

All three were true when written: `id_spaces` carried no display name, and `inventories.name` names
the *inventory* ("City of San Jose Street Tree inventory") rather than the city.

**s16 (task #237) added `dim_city`** — slug, display name, state, county — with `id_spaces.city_id`
pointing into it, on disk, in the file the City segment already reads. `SeedCities` and
`CityDownloadsPresentation` have printed `San Francisco` and `San Jose` off it since. The Journal's
City segment went on drawing a bare `City` header for another two seed generations, because three
confident comments said it could not do otherwise.

Corrected in this round: the segment names its city from `dim_city.display_name` and names nothing
when the record carries none (a pre-s16 file). What stays forbidden is what R28 and R48 actually
closed the door on — *composing* a name out of an id space's key or an inventory's title.

This is the "start with the most confident comment in the file" rule paying out again, and it is the
second entry in this file where a true sentence outlived its subject.

---

### E??? — One `AreaResolution` covered two different mechanisms, and the sentence written to explain the screen was false for a whole city

The neighborhood/city picker round put a provenance line under the Journal's stats headers — the half
of the F17 fix that answers *"why does this page seem to default to Castro/market?"* — and chose the
wording from `AreaResolution`, which has two cases: the reader picked this area, or their fix
resolved it.

**`.fromFix` is two mechanisms, not one.** R29 created `AlmanacScope` precisely to keep them apart:
a polygon the seed carries, found through the nearest inventoried tree, and — where no polygon covers
the reader — a 1,200 m circle drawn around them, which no tree chose. Keyed on the resolution alone,
*"Chosen from the tree nearest you in the city record."* printed over both.

Over the second it is false, and it is false immediately above `AlmanacCopy.areaNote` saying no
boundary exists and the almanac was drawn around the reader instead. **All 52,788 San Jose rows carry
`neighborhood_id IS NULL`** (`SELECT COUNT(*), SUM(neighborhood_id IS NULL) FROM trees WHERE
id_space = 'us-ca-sj'` → `52788 | 52788`), so this was not an edge case: it was every reader in the
bundle's second city, permanently, reading two adjacent sentences that contradicted each other.

**Why the round's own tests did not catch it.** `provenanceIsStated` built *both* of its fixtures
from `.named("Mission")`. The mechanism that was wrong was never handed to the presentation at all —
the guard was green because the defect's input was outside it, which is this project's dominant
test-suite defect class. The repair is one fixture per mechanism and an assertion that all three
sentences differ.

The general shape is worth naming, because it is not about copy: **an enum that answers a question
adjacent to the one you are asking will agree with you most of the time.** `AreaResolution` answers
"did the reader choose this"; the sentence answers "what chose it". They coincide for a polygon and
come apart for the fallback.

---

### E??? — A sheet that is a `ZStack` layer inside a tab's content is not modal, and looks identical to one that is

The same round drew its picker as `ZStack { column; if isPicking { BottomSheet(…) } }` inside
`AlmanacScreen` and `CityScreen`. It rendered correctly, dismissed correctly, and was not a modal.

The segment's content slot sits **between** the C5 segmented control and the tab bar in
`JournalTabView`'s `VStack`, so a layer inside it covers neither. Three consequences, all found by a
reviewer on the device:

1. the scrim stopped short of the segmented control and behind the tab bar;
2. **the controls behind it were live** — a tap on `City` switched segments and cancelled the sheet
   with no dismissal and no `onClose`, a fourth exit R42 never designed;
3. VoiceOver modality was lost: the column was not `.accessibilityHidden`, so the rotor still reached
   `Change`, the header pill and every card underneath.

Every other `BottomSheet` in the app (09, 10, 15) is presented from the composition root through
`RootView`'s single `.fullScreenCover(isPresented:)`, keyed on `AppRouter.sheet`, and gets all three
properties from the cover being a separate hosting context. `RootView`'s own comment already says why
there is exactly one cover; what it did not say — and now does — is that a feature drawing its own
card inside its own content is the failure mode on the other side of that rule.

**A note on the guard that now pins this**, because it is narrower than it looks:
`AreaPickerUITests` asserts `!app.buttons["City"].isHittable` and `!app.buttons["Journal"].isHittable`
while the sheet is up. Red-proved against the exact arrangement above. It was **also** tried against a
full-window `.overlay` on the `NavigationStack`, which **passed** — correctly, because such an overlay
does cover both controls. The assertion catches a sheet drawn inside the tab's content, which is the
defect that shipped; it is not a general proof that any given presentation is a system modal.
