# Roadmap

Sequenced plan for everything after M0. Milestones follow ARCHITECTURE §8; this document is the
detail underneath them — what gets built, in what order, and why that order.

Screen numbers refer to `docs/distilled/SCREENS.md`. Where a decision here departs from a source
document, it cites the entry in `docs/ERRATA.md` that records the conflict.

---

## Status

**M0, M1 and M2 are complete.** Screens 01–14 and 18 are built, tested and committed; M3's
remaining four (15, 16, 17, 19) are in progress. 208 tests, stable across repeated runs.

Three things learned along the way that outrank anything in the sequencing below.

**Confident comments are where bugs live.** Four defects survived because documentation asserted the
behaviour: `SQLiteError.code` described as a primary result code when the connection returns extended
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

## Now — correctness pass

Ahead of new screens because both defects corrupt data that cannot be recovered afterwards.

- **Unknown leaf retention** (ERRATA E9). `leafRetention` becomes optional so the app stops asserting
  evergreen-or-deciduous for species nobody established. Carries through to the seed, the SQLite
  round trip, and every phenology and autumn-colour surface. Loads `Fixtures/species/*.yaml` into the
  seed at the same time, and fixes two `sf_species_map.csv` defects: six non-taxa (`Shrub`, `Privet`,
  `To Be Determine`, …) mapped to real species ids, and `patanus racemosa ::` holding one species as
  two under different ids.
- **Outbox drops shot type.** The payload carries `photoPaths: [String]` with no shot type, so every
  synced photo is labelled `full_tree`. Fixed at the payload level, with migration for outbox rows
  already persisted on disk.

---

## M1 — finish the core loop (screens 05, 06)

**05 · Light check-in.** The five anchor rows, each a vitality judgement bound to its rubric
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

## Resolutions on the three open questions

These were escalated and handed back. Each is a decision I am taking, with the reasoning, so it can
be overturned on the merits rather than rediscovered.

### 1. Vacant sites (ERRATA E11)

**12,518 pins — 6.4% of the map — are planting basins with no tree in them.** No mock covers this.
Screen 14 currently offers "be the first to photograph this tree," which asserts a tree that is not
there.

**Decision: a distinct planting-site state, not a variant of the tree profile.** A site is not a
tree with missing fields; it is a different kind of thing, and modelling it as a degraded tree is
what produced the wrong copy in the first place. It shows what the city recorded about the site,
and its actions are *"report what's here"* and *"flag this as planted"* — both of which are claims
about the site, not about a tree.

**Why not just hide them:** 12,518 sites are the single best answer to "where could a tree go,"
which is close to the point of the app. Hiding them is a larger loss than an unmocked screen.

**Flagged for design.** This is new surface, and the decision above is the honest minimum rather
than a design.

### 2. Clustering versus SF's actual density (A1)

A1 says individual pins at zoom ≥ 16. At zoom 16 the median screen holds **1,899 trees and 98.6% of
pins overlap a neighbour**. 18 pt pins only separate at zoom 18.63 — a non-integer, so **no zoom
level satisfies both A1 and the city**.

**Decision: cluster until pins genuinely separate, and treat A1's threshold as an erratum.** A1 was
written without SF's density in front of it; honouring it literally produces an unreadable screen,
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

The critical part is the second half: derived tokens are **labelled as derived in TokenGallery**, so
review is one screen showing exactly the 59 values that were guessed, rather than an audit of the
whole palette. Any token a designer corrects stops being derived and becomes specified.

**Not derived, escalated instead:** any token where the transform disagrees with a documented pair by
more than a small tolerance. That is a sign the transform does not apply there — as with the taped
badge, where the dark pair was documented in prose and initially transcribed as light-only.

---

## Also outstanding

**iNaturalist licensing.** Content is CC BY-NC and Cypress has a paid organisational tier. We store
aggregate integers, which is defensible, but it is a position rather than a permission. The
dependency is kept removable: dropping it costs 11 bloom arrays, 8 fruit arrays and one fall-colour
array, and should remain a configuration change rather than a refactor. **Needs a human answer
before launch, not before the next screen.**

**The vitality rubric.** The source documents themselves flag this as the highest-value unresolved
question. Screen 05 is built with rubric text as data specifically so that answering it later is a
content change.

**The MapKit road-colour inversion.** The mock draws streets lighter than blocks; MapKit renders
roads darker and exposes no way to recolour them independently. `MapCanvas(basemap:overlay:)` is
kept as the seam for a vector basemap. Not scheduled — it is a real visual departure from the mock,
and worth doing only if the map's look is judged to matter more than the work.

**No test target.** Verification currently runs through harnesses rather than XCTest. That is
adequate for proving a round trip and inadequate as a regression net. A test target should land
before M2 widens the surface area.
