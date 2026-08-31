# Roadmap

Sequenced plan for everything after M0. Milestones follow ARCHITECTURE §8; this document is the
detail underneath them — what gets built, in what order, and why that order.

Screen numbers refer to `docs/distilled/SCREENS.md`. Where a decision here departs from a source
document, it cites the entry in `docs/ERRATA.md` that records the conflict.

---

## Status

**M0 through M4 are complete.** All nineteen screens are built, routed, tested and committed, with
the animation, Dynamic Type and VoiceOver passes behind them. What remains before the app installs on
a phone is M5, below.

**The five questions that were design's and had no answer are now ruled on** — see `docs/RULINGS.md`.
They were delegated explicitly by the project owner on 2026-07-21, and R1 is the only place in the
app where a transcribed hex has been overruled. That file, not this one, is where a designer arriving
later should start.

Three things learned along the way that outrank anything in the sequencing below.

**Confident comments are where bugs live.** Four defects survived because documentation asserted the
behavior: `SQLiteError.code` described as a primary result code when the connection returns extended
ones, `Photo` documented as EXIF-stripped when nothing stripped it, `awaitingWifiCount` describing a
predicate it did not implement, and `RootView` explaining that the location provider carried no
accuracy an hour after it started to. Each read as verified. None was. **When auditing, start with
the most confident comment in the file.**

**Fix the representation, not the instance.** The changes that will still be true in a year made the
bug unrepresentable: `Series` with no `count`, so a page cannot be printed as a total;
`ReportSelection` as one enum, so a hazard and a note cannot be held at once; `OutboxPhoto` with no
`[String]` overload left behind; `MonthRange.spanning`, so authoring order stops mattering;
`VitalityRow` with no initializer that accepts copy.

**A red test seen during concurrent work is not evidence.** See ARCHITECTURE §7. This produced one
wrong diagnosis already.

### The handoff is a set of screens, not an app — resolved, under an exception

It used to read: five of thirteen built screens have no way in — **05, 11, 12, 13 have no entrance
at all, and 07 has exactly one** — their exits drawn while nothing opens them, every route wired,
every destination tested, and each affordance a design decision that neither an agent nor I should
invent (DECISIONS constraint 21). By the time 16 and 17 landed the count was six.

**All six are reachable now.** I granted a one-time, explicit exception to constraint 21 covering
exactly these six entrances and nothing else. What was invented under it, what turned out to have
been specified all along, and what each of it can be overruled from is `docs/ERRATA.md` **E98**;
E24, E57, E63, E66, E74 and E75 each carry their own resolution. The `Journal` and `You` tabs were
built to hold two of them, minimally — E99 and E100 record what they deliberately do not contain.

The exception is spent. Constraint 21 stands for everything else.

---

## Ordering principle

Build outward from the loop a contributor actually walks, not inward from the data model. The
sequence below is roughly: finish the thing a person does on their first walk, then the thing they
do on their tenth, then the thing they do when something goes wrong.

Two rules hold throughout:

**No screen ships against a mock alone.** Every screen is implemented against `SCREENS.md`, which is
the transcription; the mock is the check, not the source. Where they disagree the disagreement is an
ERRATA entry before it is a code change.

**Nothing is invented.** DECISIONS constraint 21 — an unmocked destination is a question for the
design, not a case to make up. Where a state genuinely has no mock (vacant sites, error surfaces),
the resolution is written down here first and flagged for design review, rather than settled quietly
inside a view file.

---

## Now — correctness pass (resolved)

Ahead of new screens because both defects corrupt data that cannot be recovered afterwards.

- **Unknown leaf retention** (ERRATA E9, resolved). `leafRetention` becomes optional so the app stops asserting
  evergreen-or-deciduous for species nobody established. Carries through to the seed, the SQLite
  round trip, and every phenology and autumn-color surface. Loads `Fixtures/species/*.yaml` into the
  seed at the same time, and fixes two `sf_species_map.csv` defects: six non-taxa (`Shrub`, `Privet`,
  `To Be Determine`, …) mapped to real species ids, and `patanus racemosa ::` holding one species as
  two under different ids.
- **Outbox drops shot type** (resolved). The payload carries `photoPaths: [String]` with no shot type, so every
  synced photo is labeled `full_tree`. Fixed at the payload level, with migration for outbox rows
  already persisted on disk.

---

## M1 — finish the core loop (screens 05, 06)

**05 · Light check-in.** The five anchor rows, each a vitality judgment bound to its rubric
sentence verbatim (D3). This is the highest-frequency contribution in the app and the one most
exposed to the unresolved rubric question below, so it is built with the rubric text as data rather
than as string literals in a view.

**06 · Report an issue.** The 311 redirect. Cypress does not accept hazard reports itself — D4 keeps
`HazardCategory` and `CommunityNote.Category` disjoint precisely so that a safety issue cannot
degrade into a community note. This screen must hand off cleanly and record that it did.

Also in M1: permission-denied states for location and camera, which the design mocks and the current
build does not implement.

---

## M2 — one level deeper (screens 07–13)

Ordered by how much each depends on data the app already has.

| | Screen | Note |
|---|---|---|
| 1 | **07 Species page** | Unblocked by the correctness pass; renders the curated content and must render nothing where knowledge is absent. |
| 2 | **08 My Grove** | Species tab, C27 progress ring, C29 tiles. First screen keyed on the contributor rather than on a tree. |
| 3 | **13 Tree activity** | Reads timeline data the outbox already produces. |
| 4 | **09 Care log** | Bottom sheet over a dimmed profile. |
| 5 | **10 Share** | Public photo locations snap to the universal 25 m grid (DECISIONS §3). Non-negotiable and easy to get wrong. |
| 6 | **11 Growth history** | Only plots readings that pass `isEligibleForGrowthCharting` (D6). Sparse charts are correct output, not a bug. |
| 7 | **12 Neighborhood almanac** | Needs the neighborhood geometries from `j2bu-swwd` (ERRATA E2); the dataset the spec names serves empty polygons. |

---

## M3 — in the field (screens 14–19)

**14 Cold-start profile**, **15 the account ask** (third save; magic-link only, no passwords ever —
DECISIONS §3), **16 Measure**, **17 Outbox** (the queue made visible, including the 48 h give-up
state), **18 Next tree**, **19 Memorial**.

Plus the vacant-site screen decided below, which belongs with 14.

---

## M4 — dark mode and polish

D1–D3 are the only dark screens specified. The remaining coverage is resolved below. Then the
animation pass and an accessibility pass — Dynamic Type, VoiceOver labels on every C-component, and
contrast verification on the amber family, which is the palette most likely to fail.

---

## M5 — the thing installs on a phone

M4 was the last milestone about screens. M5 is about the difference between nineteen screens and an
app, which turns out to be short.

| | Work | Where it landed |
|---|---|---|
| 1 | **The vacant planting-site state** — 12,518 pins, 6.4% of the map (SF alone, as measured then; 24,200 / 12.2% across both cities today — E206), had been rendering as a stripped-down cold profile | E11 → **E107** |
| 2 | **The caption ramp** — `text.faint` failed AA in both appearances across 61 call sites | R1, R1a → **E108** |
| 3 | **Account deletion** — §3.12 and the exclusive-ownership CHECK could not both hold | R3 → **E109** |
| 4 | **Screen 01's navigation bar** — an opaque 91pt band on the one screen the spec calls full-bleed | **E110** |
| 5 | **Screen 15 gated** behind `BetaCapability.accountsAvailable` | R4 → **E111** |
| 6 | **The favorite comes off** — a tap that could be made and not taken back | R2 → **E112** |
| 7 | **A vacant site cannot open the tree profile** from any entrance | **E113** |
| 8 | **Icon, accent, launch screen** | — |

**M5 is complete.** Two of these were not on the list when M5 opened. E110 was found by photographing the
running app; E113 by noticing that E107 had fixed one entrance out of six.

Bundle identity was already set: `app.cypress.Cypress`, marketing version 0.1, portrait only, iPhone
only. **A local beta needs no Apple Developer Program membership** — a free Apple ID signs the app for
seven days at a time on the owner's own device, which is the right shape for this stage. A paid Team
ID buys a year instead of a week, TestFlight, and distribution to people who are not you; none of
that is needed until someone else is holding the phone.

### What M5 deliberately does not include

**A backend.** There is none and none is planned for the beta. Everything the app does is local: the
seed database ships in the bundle, contributions queue in the outbox and stay there, and no request
leaves the device. The outbox is not disabled for this — it runs, retries, and backs off exactly as
designed, against nothing. That is a better beta than a stubbed-out queue, because the thing being
exercised is the thing that will ship.

**Sign-in** — R4. **Moderation** — there is no moderator; E-numbered entries record what
`moderationState` means in the meantime. **iNaturalist licensing** — a position, not a permission,
and the owner has accepted it for the beta.

---

## Resolutions on the three open questions

These were escalated and handed back. Each is a decision I am taking, with the reasoning, so it can
be overturned on the merits rather than rediscovered.

### 1. Vacant sites (ERRATA E11)

**24,200 pins — 12.2% of the map — are planting basins with no tree in them.** No mock covers this.
(The figure was 12,518 / 6.4% when this was written; that was San Francisco alone, and San Jose has
since landed. Re-measured on the shipped two-city seed 2026-08-02 — ERRATA E206.)
Screen 14 currently offers "be the first to photograph this tree," which asserts a tree that is not
there.

**Decision: a distinct planting-site state, not a variant of the tree profile.** A site is not a
tree with missing fields; it is a different kind of thing, and modeling it as a degraded tree is
what produced the wrong copy in the first place. It shows what the city recorded about the site,
and its actions are *"report what's here"* and *"flag this as planted"* — both of which are claims
about the site, not about a tree.

**Why not just hide them:** 24,200 sites are the single best answer to "where could a tree go,"
which is close to the point of the app. Hiding them is a larger loss than an unmocked screen.

**Flagged for design.** This is new surface, and the decision above is the honest minimum rather
than a design.

### 2. Clustering versus SF's actual density (A1)

A1 says individual pins at zoom ≥ 16. At zoom 16 the median screen holds **1,899 trees and 98.6% of
pins overlap a neighbor**. 18 pt pins only separate at zoom 18.63 — a non-integer, so **no zoom
level satisfies both A1 and the city**.

**Decision: cluster until pins genuinely separate, and treat A1's threshold as an erratum.** A1 was
written without SF's density in front of it; honoring it literally produces an unreadable screen,
which cannot be what it was for. The map opens closer than the spec implies and transitions to
individual pins where they actually resolve.

Recorded as an ERRATA entry proposing the change rather than silently violated — the number in A1 is
wrong, and the document should say so.

### 3. Dark mode for the 59 unspecified tokens (ERRATA E8)

78 of 137 tokens have a documented dark value; 59 do not. Bottom sheets and the entire amber family
would glare.

**Decision: derive the missing values from the documented pairs, then mark every derived token as
derived.** The 78 specified pairs are a sample of a transform the designer applied consistently;
fitting that transform and applying it to the remaining 59 is a far better guess than either
per-token invention or leaving the app broken in the dark.

The critical part is the second half: derived tokens are **labeled as derived in TokenGallery**, so
review is one screen showing exactly the 59 values that were guessed, rather than an audit of the
whole palette. Any token a designer corrects stops being derived and becomes specified.

**Not derived, escalated instead:** any token where the transform disagrees with a documented pair by
more than a small tolerance. That is a sign the transform does not apply there — as with the taped
badge, where the dark pair was documented in prose and initially transcribed as light-only.

---

## Also outstanding

### Tester feedback, reconciled against main 2026-08-28

The 20 re-queued reports from PR #118's verbatim table, audited item by item against origin/main
with receipts. Nine were already shipped (1, 2, 3, 5, 6, 7, 8, 10, 11 — all but the first two in
PR #102's beta-polish, which merged the day build 49 was cut, so the tester reported against fixes
that had not yet reached a build). What remains OPEN:

- **F4 — a time filter** (today / this week / this month / last 30 days / past year). No period
  selector exists on any screen; which screen the tester meant is itself unconfirmed.
- **F15 — enrich the tree profile**: ID help, history/etymology, usage/edibility. Content work;
  pairs with the parked seed-prose pass, and invented botanical content is forbidden (DECISIONS
  constraint 15) — sourcing is the work.
- **F16 — trees-seen counters (30d / year / lifetime). BLOCKED ON A RULING**: D1 / ARCHITECTURE
  §5.1 forbids counting a person's actions into a user-visible string. Needs the owner to amend or
  refuse; not schedulable as written.
- **F22 — species distribution as a static city map** (one point per tree) on the field guide's
  §5; today it is two stat cards.
- ~~**F23 — "See them all on the map"** link from Grove/Journal into the map filtered to yours; the
  target filter exists (`MapFilter.membership`, chip "Yours"), nothing routes into it.~~
  **DONE — the link ships on the Journal tab's `Yours` segment.** `AppRouter.goToMap(showing:)` arms
  a one-shot narrowing that screen 01 applies on arrival; the chip reads selected and `Clear
  filters` is in the row from the first frame. **The placement is the owner's to ratify** — no mock
  draws this link (DECISIONS constraint 21) — and the PR asks. It is deliberately **not** on My
  Grove's `Trees` pill, which is where the sentence reads most naturally and where it cannot keep
  its promise: the grove's list includes trees you have only favorited and the map's `Yours` filter
  deliberately does not (R23), so the same link there would silently drop rows the reader can still
  see. See `docs/errata-pending/three-answers-to-which-trees-are-mine.md`, and
  `CypressTests/SeeAllOnMapTests`, which pins both halves.
- **F25 — Account/You page UI/UX pass.**
- **F26 — Measure: unit switch clears the entered value. BLOCKED ON A RULING**: deliberate today —
  `Quantity.value` is "the number as the human typed it, never converted", and keeping digits
  across a unit flip would falsify it. Needs the owner to choose: keep-and-annotate, convert, or
  keep the clear.
- **F27 — measurements can be neither edited nor deleted.** The data model already carries the
  tombstone (`deletedAt`); no user-facing path reaches it, and no withdrawal mutation exists in
  the outbox vocabulary. The unhappy sibling of the photo-withdrawal work.
- **F28 — adding a reading on a tree holding both height and DBH** is two small-text taps deep;
  the add-a-reading card only exists while its own measurement is missing.
- **F17 — neighborhood stats far from home — folded into the neighborhood/city picker item
  below**: nearest-tree resolution is unchanged since the report and R84 D4 deliberately kept it;
  the picker round is its designated fix, and should also decide what the screen says when the
  nearest tree is very far away.

### Follow-up tickets from the 2026-08-30 rounds

- **Map camera fits the filtered set.** "See them all on the map" (PR #130) arrives with the
  remembered viewport, so the reader's trees can be off-screen; the owner ruled the link ships
  as-is and the camera change is its own small round — camera policy carries its own errata
  history, so it gets its own review, not a rider.
- **Screen 12's `COLLATE NOCASE` joins.** `AlmanacQueries` lines ~321 and ~394 carry the same
  index-defeating collation the Grove round (PR #131) removed from its own path; the almanac pays
  the same class of full-inventory walk. Same fix shape (`lower()` + the seed-contract test PR
  #131 added), and the query-plan gate should grow to cover these two statements.

### Owner backlog additions, 2026-08-28

Three items queued by the owner, recorded verbatim in intent; none is scheduled yet.

- **A tree's photos through the seasons.** A screen showing one tree's photographs as a grid,
  browsable by season or by year, with a toggle between only this device's photos and all photos.
  No mock exists — the round that builds it starts as a design round under DECISIONS constraint 21
  (screen and states proposed to the owner before code), and its all-photos half must respect the
  photo-visibility rules (D11 privacy defaults, R82 hero provenance).
- **Journal: stats for a chosen neighborhood, and a chosen city.** The Journal's neighborhood
  segment gains a way to select a different neighborhood and read its stats; the City segment gets
  the same for a different city. Today both resolve from the nearest tree (R84's D4 kept it that
  way deliberately); this item is the round that supersedes that scoping with an explicit picker,
  and with R84's union live it must define which inventories a non-local pick may draw from.
- **Update the repo README.** The README predates most of what shipped; bring it current with the
  app as it stands (cumulative inventories, the publish pipeline, the beta process).

### Chip backlog (logged 2026-08-28, so dismissal of a session chip loses nothing)

Five follow-up tasks were surfaced as one-click session chips during the 2026-08-22..28 rounds.
Four disappeared from the pending list without being run; whatever dismissed them, the work is
still owed, so it is recorded here as the durable queue. Each stands alone.

1. **Close `PendingCitationGuardTests`' blind spots.** The guard that keeps code comments from
   citing pending errata/rulings filenames has known gaps in what it scans; enumerate the blind
   spots and cover them, with a planted-citation calibration per shape.
2. **Rebuild `Tools/ui-test-shards.txt` from live CI data.** The shard assignments have drifted
   from the suites' actual durations (shard runtimes are visibly unbalanced in recent runs);
   regenerate from measured per-class times and re-prove `UITestShardCoverageTests` still covers
   every class.
3. **Fix `Tools/fetch_seed.sh`'s silent scope-check death under `pipefail`.** A failure inside the
   scope-check pipeline can kill the script without a diagnostic; make every exit path name itself,
   with a calibrated failure case.
4. **Redesign `CityDownloadsFeedbackTests`' perf-margin test.** The "transfer beats a per-byte walk
   by an order of magnitude" test (`CityDownloadsFeedbackTests.swift:920`-era) compares two
   wall-clock timings with a hard margin and flaked on CI with no concurrent load (8.5x against a
   10x threshold, 2026-08-23). PR #123's fix round narrowed a sibling window the same way and the
   review flagged the class again — rebuild these guards load-independent (count work, or assert
   the mechanism), keeping the regression they guard: a per-byte walk reappearing must fail.
5. **Harden `MapPanTabSwitchUITests` against slow runners.** Four CI sightings by 2026-08-28
   (latest: run 33208371211, on code byte-identical to a green run), always the same shape: the
   probe records `panBegan=3 panEnded=3` yet the camera never leaves "Centered on you" — the
   drag is delivered but the runner is too slow for MapKit to register it as a pan. Rework the
   test's gesture (or its precondition) so a delivered-but-unregistered pan retries or fails as
   an environment refusal rather than a red; keep the regression it guards (a deliberate pan
   surviving a tab switch must still fail if the camera resets).
6. **Sweep `library.stagingURL`'s lifecycle for leaks** (chip still pending as of this note). The
   #123 reviewer left it deliberately unfiled: can a process death, failed verification, cancelled
   transfer, or refused install leave orphans in the staging directory, and does anything clean
   them? Happy path verified empty on device; the sweep is every unhappy path, pinned with
   red-proved tests.


**Retire the format-1 manifest — DONE, 2026-08-23.** The owner overrode the trigger the day after
setting it: rather than firing at the publish *after* New York, format 1 retired immediately. Full
reasoning, and what it supersedes, in `docs/rulings-pending/format1-retirement.md`.

`Tools/publish_cities.py` no longer writes `manifest.json` and `dist/upload.sh` no longer uploads
or verifies it, so the NYC publish of 2026-08-23 is the last format-1 object there will ever be.
**The published object is frozen, not deleted** — it still names two immutable city packs that are
still served (checked anonymously, with a 404 control), so an install that never updated past build
47 keeps a working Cities screen and simply stops receiving anything newer.

Two departures from the enumeration this entry previously carried, both deliberate:
`CityDownloader.fetchManifest`'s fallback to the legacy name is **kept** rather than removed — its
remaining job is any base URL that is not the live bucket (an archived mirror, a fixture directory),
and every shipped build 48–55 has it compiled in regardless. And the publisher gained a guard it did
not have: it refuses a `--out` still holding a format-1 manifest from a dual-publish round, because
`--out` only clears `cities/` and that leftover file is the one artifact an operator could upload
over the frozen object. **`CityManifest.knownFormats` keeps `1`**, as previously planned — what
retired is writing a format-1 manifest, never reading one.

**City-inventory disputes.** Owner ruling, 2026-08-21, refined the same day (both in RULINGS
**R79**, which carries the full spec): city data must be
disputable from the UI, and city-tree disputes are richer than the community-tree flags. City
trees: checkboxes for nature of issue (pin in wrong location; wrong species; wrong other metadata
— e.g. a clearly wrong planted year, or a recorded tree whose plot is empty), suggested values,
and a notes field; plus a missing-tree defect for a tree that is on city property but absent from
the city database, whose entry point cannot be a tree profile. Flagged trees get a small badge
showing their flags, and the filters box gains a "trees with data issues" filter. Community trees:
location and species disputes only — and the existing community flagging view is itself not
quality (owner, same day: bad copy throughout, and a flag cannot be retracted by its author),
so the round gives community flagging a detailed design pass with owner decision rounds rather
than inheriting the shipped flow. Disputes are stored app-side in the writable database; the
city inventory stays read-only, and sync-back to the city is explicitly deferred. Reverses the
"community rows only" deferral in `SpeciesClaim.swift`'s header. Needs the writable-schema
migration seat after the §3.4 round's. Sequenced after §3.4 lands; exact slot at scheduling.

**Copy audit: remove demo-era narrative holdovers.** Owner instruction, 2026-08-21: every piece of
user-facing copy gets screened for usefulness and appropriateness. Lines narrating the app to
itself — "This is that almanac's 'walk the nine' list, one tree at a time" (screen 14) and its
kin — are holdovers from a demo-era voice and come out. The audit enumerates every candidate line
with its screen and source location, then brings them to the owner as batched decision rounds
(copy on mock-specified screens is constraint-21 territory); nothing is reworded silently. Not
scheduled.

**Seed inventory expansion beyond NYC.** Owner requests, 2026-08-21: add street trees to the data
seed for **Oakland and Los Angeles**, and then also **Dallas, Phoenix, Philadelphia, San Antonio,
San Diego, Jacksonville, Austin, Charlotte, Columbus, Seattle, Denver, and Nashville**. Each city
is the NYC shape again — source the inventory, read its license, ingest, validate species
coverage, cut packs — and the s17 region dimension is the prerequisite, so all of it queues behind
NYC's first publish. Whether each city publishes an open street-tree inventory at all, and under
what terms, is unresearched: the first step per city is the sourcing-and-license pass, and a city
with no usable inventory comes back to the owner as a finding, not a silent drop. A tester asked
for Marin/Sausalito/Mill Valley coverage the same day (RULINGS **R80**, the deferral "Coverage
outside San Francisco: Marin, Sausalito, Mill Valley", which reframes it as an inventory question
for the distribution plan); when this is scheduled, evaluate the whole list together against the
distribution plan's
per-inventory machinery rather than one city at a time. Not scheduled.

**iNaturalist licensing.** Content is CC BY-NC and Cypress has a paid organizational tier. We store
aggregate integers, which is defensible, but it is a position rather than a permission. The
dependency is kept removable: dropping it costs 11 bloom arrays, 8 fruit arrays and one fall-color
array, and should remain a configuration change rather than a refactor. **Needs a human answer
before launch, not before the next screen.**

**The vitality rubric.** The source documents themselves flag this as the highest-value unresolved
question. Screen 05 is built with rubric text as data specifically so that answering it later is a
content change.

**The MapKit road-color inversion.** The mock draws streets lighter than blocks; MapKit renders
roads darker and exposes no way to recolor them independently. `MapCanvas(basemap:overlay:)` is
kept as the seam for a vector basemap. Not scheduled — it is a real visual departure from the mock,
and worth doing only if the map's look is judged to matter more than the work.

**`assertEveryControlIsLabeled` asserts over a screen it does not own.** `DeepLinkHarness
.assertEveryControlIsLabeled` walks `app.buttons`, `app.staticTexts` and five more queries — *every
element in the app*, not the screen under test. Screens 09, 10 and 18 are presented over the map tab
root rather than pushed, so screen 01's MapKit annotations stay in the accessibility tree behind
them and are read as part of that screen's audit. `DeepLinkSweepTests.testNothingIsAnnouncedTwice`
does the same thing one query wider.

Everything that has gone wrong with this is a consequence of the scope, and each fix so far has
treated a consequence:

- an annotation whose frame XCUITest can resolve no activation point inside makes `isHittable`
  **raise** — fixed at the read (`XCUIElement.isHittableWithoutRaising`, `CypressUITests/UIWait.swift`);
- which annotations land in that state depends on where the camera was left — fixed at the state
  (`CYPRESS_MAP_CAMERA`, `Cypress/Features/Map/DebugMapCameraOverride.swift`);
- enumerating that many elements against a live tree is itself a race — an index that stopped
  resolving mid-walk failed CI three times with both of the above in place (indexes 25, 3 and 17,
  the last on a tree byte-identical to a passing run). Fixed at the binding for
  `testNothingIsAnnouncedTwice`: `allElementsBoundByAccessibilityElement` and one read of each
  value into a plain `(String, CGRect)`, so nothing re-resolves a proxy mid-comparison.
  `assertEveryControlIsLabeled` still walks by index and has not been seen to lose one. The reason
  is worth a clause rather than being left as luck: it makes one pass and re-resolves no ordinal
  *between two reads that have to agree with each other*, which is exactly the property
  `testNothingIsAnnouncedTwice`'s pair-wise comparison did not have. That is not immunity, only a
  smaller window — it still reads `.label` after `.exists`, and PR #66 measured on a device that the
  sibling pair `.exists` then `.frame` **raises** rather than answering when the query stops
  resolving in between.

**The scope itself is untouched, and it is the actual defect**: a labeling audit of screen 18 that
passes or fails on the contents of screen 01 is not an audit of screen 18. The shape of the repair is
to scope the walk to the presented screen's own subtree — but that changes what the helper *claims*,
and the claim is load-bearing: the helper's own comment records that it is scoped to what is hittable
"for the same reason E116's version is", and four files depend on it. It needs its own red-proof
(a genuinely unlabeled control on the screen under test must still be caught) and an argument about
what happens to the elements that stop being examined.

Not scheduled, deliberately, and the reason is the size and shape of the work rather than the state
of any one run. The symptoms are each guarded — `HittabilityFilterGateTests`,
`ContainerSpellingGateTests`, `FrameFinitenessGateTests`, `DebugMapCameraOverrideTests` — so what is
left is a question about what the helper *claims* to examine, which no failure will report. The full
history is in the errata entry for the hittability round.

*This paragraph used to open "The suite is green", and that is why it does not now.* It was false at
the head it was written on — CI run 31347748098 had `ui (3)` red on the very repair the third bullet
above describes — and a decision not to schedule work should not rest on a sentence that has to be
re-checked every time the tree moves. Two of the gates named here were widened on PR #66 after a
reviewer red-proved that `if x.isHittable` and `descendants(matching: .scrollView)` walked straight
past them, which is the other half of the same lesson: "guarded" is a claim about an instrument, and
an instrument has a calibration.

**Five UI test classes still inherit the opening camera, and still write one.** PR #66 gave the
tests a way to pin screen 01's opening camera (`CYPRESS_MAP_CAMERA`) and applied it to four launch
helpers: `DeepLinkHarness.launch`, `DeepLinkOverrideReset`, `PrimaryCTAReachabilityTests
.launchAtAX5` and `IdentifyFABReachabilityTests.launchAtAX5Denied`. `AccessibilityTreeTests`,
`MapFilterAccessibilityTests`, `MapRecenterUITests`, `MapPanTabSwitchUITests` and
`AlmanacGroupTapTests` were deliberately left alone, and they still open on whatever the previous
launch left in `map.lastCamera` — and still write one on the way out, which is what the next
unpinned class inherits.

That is a gap the harness cannot close on its own: `Tools/run_tests.sh` normalizes the stored camera
**once, before `xcodebuild` starts**, and can say nothing about what the twentieth launch inside a
run inherits from the nineteenth.

Three sightings so far, none of them reproduced, all in unpinned classes:

- `AlmanacGroupTapTests.testWalkTheNineOpensAMapOfThemAll` — one CI failure on `94b1d81`, green on
  the next run.
- `MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` — timed out waiting on
  the recenter control through three retries on a local merged-tree run.
- `MapPanTabSwitchUITests.testAnUntouchedCameraStillCentersOnTheReaderAfterTheRoundTrip` — a cascade
  from the previous one, the app wedged and would not terminate.

**The second and third are not attributable, and that matters more than the count.** That run took
3,289 s against a normal ~1,580, `run_tests.sh` had already refused one launch on a competing
`xcodebuild`, and CI then passed the byte-identical tree on the shard carrying that class. So those
two are at least as likely to be the simulator degradation CLAUDE.md describes as anything about the
camera. They are recorded here because the class is unpinned, not because the camera was shown to be
the cause.

The work is not "pin the other five" — `MapPanTabSwitchUITests` deliberately pans and
`AlmanacGroupTapTests` pins its own location fix, so a pin could quietly change what either one
asserts. It is to decide, per class, whether the camera it opens on is something the test means to
control, and to give the ones that do the seam that already exists.

*(The "structural VoiceOver is not machine-checked" entry that stood here is resolved. `CypressUITests`
is a black-box XCUITest target (E116), and `DebugDeepLink`'s `CYPRESS_SCREEN` environment variable
opens any screen for it (E117), so fifteen structural tests now read the accessibility tree of the map
plus fourteen screens behind it. Every one of the 188 interactive elements found was labeled; the
suite additionally pins that no modal leaks the screen behind it to assistive technology, and that
every pushed screen has a reachable Back. **Screen 19 remains unread, and the reason is the data**: the
seed holds only `alive` and `vacant_site`, so no `removed` tree exists to open a memorial with, and
faking one would be the exact class of lie the suite exists to catch. **Reading order and grouping
have partial coverage now (task #221).** `ReadingOrderAccessibilityTests` asserts composition order
on six screens chosen because a wrong order there is a real usability failure: the map's field →
suggestions → filter chips, screen 05's five vitality rows in rubric order (worst to best, never
phrasing-dependent), screen 03's identity block before the primary CTA before the secondary quad
actions, and — added since — the three screens that WRITE: screen 06's two chip vocabularies each
kept under its own heading (the boundary E131 rests on), screen 16's kind and method controls before
the keypad before `Save measurement`, and screen 09's four care toggles before the optional
photo/note well before `Done`. `testAStatCardIsOneStop` (E118) already asserted the narrower
grouping claim — a caption and its value arrive as one stop. **What this does not close**: several
screens' order is still unasserted, and three were examined and deliberately left out because their
order is a property of seed or device state rather than of the code (11 growth history and 13
activity resolve to trees with no rows at all; 17 outbox reads a device-local queue). **The
`accessibilitySortPriority` question is settled for one whole class of API, in the negative and for
a structural reason**: not only `debugDescription` but the query engine under both binding
strategies, the snapshot's own `children` arrays and `.children(matching:)` all report raw
view-composition order — a purely geometric inversion of two elements moves none of them. Those five
are *traversals of one `XCUIElementSnapshot`*, not five independent instruments, and that is exactly
why the result generalises the way it does: **no traversal of that snapshot can observe a sort
priority**, so reaching for a sixth traversal is not worth anyone's time. **What is NOT closed** —
this sentence over-claimed it before PR #54's review — is focus-driven or
assistive-technology-driven order, a different mechanism that does not read the snapshot at all.
That reviewer tried a focus-engine probe (`typeKey(.tab)` then a `hasFocus` sweep) and got no
element reporting focus on a simulator without Full Keyboard Access: **no counterexample and no
working probe — untried, not refuted**, and the place for the next attempt to start. See ERRATA
**E230** and its amendment. What replaces the search is `CypressTests/MapSwipeOrderDeclarationTests`, which
pins that screen 01's declared priorities descend in the same order the block composes its children,
since that agreement is what makes a composition-order assertion mean anything at all. Verifying the
mechanism itself on the glass is still a physical-phone VoiceOver pass — the debt E192 recorded, and
unchanged.)

*(The "Two contrast pairs are still failing" entry that stood here is resolved. E120 fixed the C10 locked glyph via lightness-only OKLCh (3.06:1/3.05:1), and E122 fixed the C23 chart series via the same method — chartSeriesPrimary 2.53→3.05, chartSeriesTertiary 2.27→3.06, both moved from `knownFailures` to `retinted`.)*

*(The "no test target" entry that stood here is resolved: `CypressTests` is a hosted swift-testing
bundle and has been since M2. It found two shipped bugs on the day it was wired.)*
