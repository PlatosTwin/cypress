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

*(The "structural VoiceOver is not machine-checked" entry that stood here is resolved. `CypressUITests`
is a black-box XCUITest target (E116), and `DebugDeepLink`'s `CYPRESS_SCREEN` environment variable
opens any screen for it (E117), so fifteen structural tests now read the accessibility tree of the map
plus fourteen screens behind it. Every one of the 188 interactive elements found was labeled; the
suite additionally pins that no modal leaks the screen behind it to assistive technology, and that
every pushed screen has a reachable Back. **Screen 19 remains unread, and the reason is the data**: the
seed holds only `alive` and `vacant_site`, so no `removed` tree exists to open a memorial with, and
faking one would be the exact class of lie the suite exists to catch. **Reading order and grouping
have partial coverage now (task #221).** `ReadingOrderAccessibilityTests` asserts composition order
on three screens chosen because a wrong order there is a real usability failure: the map's field →
suggestions → filter chips, screen 05's five vitality rows in rubric order (worst to best, never
phrasing-dependent), and screen 03's identity block before the primary CTA before the secondary quad
actions. `testAStatCardIsOneStop` (E118) already asserted the narrower grouping claim — a caption and
its value arrive as one stop. **What this does not close**: every other screen's order is still
unasserted, and — found while building the map test — `debugDescription`, the only order XCUITest
exposes to a black-box test here, does not appear to move under `accessibilitySortPriority` at all, so
nothing in this suite can yet verify that mechanism specifically (map task #143's fix for E183 §3 is
therefore still unverified by any automated test); see
`docs/errata-pending/debugdescription-blind-to-sortpriority.md`.)

*(The "Two contrast pairs are still failing" entry that stood here is resolved. E120 fixed the C10 locked glyph via lightness-only OKLCh (3.06:1/3.05:1), and E122 fixed the C23 chart series via the same method — chartSeriesPrimary 2.53→3.05, chartSeriesTertiary 2.27→3.06, both moved from `knownFailures` to `retinted`.)*

*(The "no test target" entry that stood here is resolved: `CypressTests` is a hosted swift-testing
bundle and has been since M2. It found two shipped bugs on the day it was wired.)*
