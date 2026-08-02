# (pending) — R41 applied: the map's filter status line is gone, and R43 §5 goes with it (tasks #178, #179, #180)

*Written from the branch `p1/map-filters`. Unnumbered by CLAUDE.md's rule; the orchestrator splices
the real number at merge and rewrites the citations that name this file.*

## What the message actually was, and where it rendered

The owner's directive (R41) names "a message about 4 of 5 trees". It was
`MapYearFilterCopy.setAside`:

> About 4 in 5 trees have no recorded planting date—none of them can appear under a year.

**It rendered on the map**, not inside the More-filters drawer. `MapFilterStatus` was a member of
`MapHomeView`'s top chrome overlay — the block that holds the search bar, the chip row, the search
status and the legend — positioned directly under the chips, over the map glass, drawn in a capsule
borrowed from `MapSearchStatus`. It appeared whenever `filter.decade != nil`, wherever the reader
had set the decade from. This matters because it settles the question the brief raised: R41's "on
the map or beside the filter row" reaches it on both counts, so no reading of R41 saved it.

**The view drew a second line, and that is the part worth reading twice.** Above the caveat,
`MapFilterStatus` rendered `MapModel.filterResult` — the filter's result count, `31 trees`, or
`1458 trees—showing 151` when the 44 pt grid had thinned the answer. That line was nil unless
`filter.isActive`, so it too appeared only and exactly because a filter had done something.

## The decision: both lines are gone, and `MapFilterStatus` with them

R41's own test is *"does text appear because a filter did something?"* — and it lists **a count**
among the forbidden surfaces, in the same breath as a notice and a card. It then answers the
obvious objection before it is made: counts and narrowing facts "already have their three sanctioned
channels (R23.1: chip fill, count *on the chip*, spoken names) — on the chip is the chip's voice,
not a companion message". A capsule on the glass is not one of the three.

Removing the sentence and keeping its neighbour would have been precisely the failure R41 was
written to end. The ruling says so in terms: this is the third filter-adjacent message to be ruled
out (#142's growing notice, the R31 correction's empty-filter box), "each time, a message survived
under a different mechanism. The rule is now categorical so no mechanism can shelter one."

**This is applying R41, not amending it.** No clause of R41 was read down or read around, and the
brief's instruction to stop and report before amending R41 was therefore not triggered. It is
flagged to the orchestrator anyway, because it is more product than the owner's sentence named, and
because it is a cheap revert if the owner disagrees: restoring the count is one view, one computed
property and one formatter.

### What this costs, stated plainly

The count was the only surface saying that the drawn pins can be a *spatial sample*. The map still
thins (`MapModel.pinLimit`, the 44 pt grid in `MapViewport.markerCellPoints`); it simply no longer
says so.

**E38 is not violated by this.** E38 — "a page is not a total" — is a constraint on a number that is
*presented*: it forbids reporting 151 when 1,458 matched. With no number presented, nothing is
misreported. E38 constrains a surface that no longer exists rather than requiring one to exist.

Likewise D1: the argument that a filter result is not a personal total was sound and is not
reversed. The count is not forbidden for being a score; it is forbidden for being a message beside
a filter. Anyone tempted to reinstate it should know that D1 is not what is in the way.

## The R41 / R43 §5 collision, and how it was resolved

R43 §5 (task #157, one hour before this branch started) generalized
`MapYearFilterCopy.undatedShareOfSeed` from the hardcoded 0.8078 into a value **measured** from
whichever inventory is attached, and derived the caveat sentence from it — pinning by test that the
fused bundle reproduces "4 in 5" verbatim.

The two rulings collide on exactly one thing, and the resolution is not close:

- **R43 §5 never decided whether the sentence should exist.** Its question was which inventory the
  sentence should be true *of*, once the reader could choose one. It generalized a sentence it
  inherited.
- **R41 decides exactly that**, it is later, and it is the owner's direct instruction rather than
  delegated design authority.

So the sentence dies, and the measurement dies with it: `CypressStore.seedUndatedShare`,
`CypressStore.measureUndatedShare`, `MapYearFilterCopy.setAside`, `setAside(undatedShare:)` and
`undatedShareOfSeed` are all removed. A measurement whose only consumer is a forbidden sentence is
dead code, and leaving the property in place unread is the #62/E126 shape the brief warned against.

**R43 §5 needs striking in `docs/RULINGS.md` at merge.** Nothing else in R43 is affected — §1–§4 and
§6 are untouched, and the city-downloads feature loses no behaviour: the undated share was never
read by anything except the caveat.

### The three tests that went with it

Two were named in the brief; a third was not, and is recorded here because the next reader will
look for it.

| test | file | what happened |
|---|---|---|
| `setAsideDerivesFromTheShare` | `CityDownloadTests` | removed — subject gone |
| `undatedShareIsMeasured` | `CityDownloadTests` | removed — subject gone |
| `yearFilterAlwaysSaysWhatItSetAside` | `MapFilterTests` | removed — asserted the caveat's wording |
| `resultLineReportsMatchesNotThePage` | `MapFilterTests` | removed — asserted `MapFilterCopy.result` |
| `resultLineIsNotAPersonalTotal` | `MapFilterTests` | removed — asserted `MapFilterCopy.result` |
| `plantingDateCoverageMatchesTheCopy` | `MapFilterTests` | **repurposed**, see below |

Each removal is recorded in a comment at the site it was removed from, naming what it asserted and
why the assertion no longer has a subject — so the deletion is legible in the file rather than only
in this document.

**The one that was kept is the one that was about a fact rather than a string.**
`plantingDateCoverageMatchesTheCopy` pinned the seed's undated share against the copy's rounding. It
is now `plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor`, and it pins three seed facts that
the *design* of the two controls rests on: that most rows are undated (why the year control buckets
by decade), that vacant sites are a large minority (why #179 is worth a control), and that many
vacant sites carry a planting date (why #178's exclusion is not theoretical). It guards a design
against a re-ingest instead of guarding a sentence against a rewrite.

## What holds R41 now

`CypressUITests/MapFilterAccessibilityTests.testNoTextAccompaniesAFilter`, which replaces
`testTheResultLineIsOneCountingPhrase` **by inversion rather than deletion** — the treatment R38
gave the AX5 wrap test it replaced, and for the same reason: the file should still testify about
this surface.

It is written as a **set difference**, because R41's own test is one: it records every static text
on the un-narrowed map, turns narrowings on (a species off the legend, then a condition chip on top
of it, then a filter set inside the drawer), and fails if any text appears that was not there before
*and* that no control on screen answers to. The exemption for control labels is R23.1's three
channels, which R41 keeps explicitly.

A guard that banned today's two sentences by name would have been the thing R41 was written
against — the previous two messages both came back under a different mechanism. Two named checks
for the count grammar and for any sentence mentioning planting dates are kept alongside the diff,
redundant by construction, because they name the two specimens.

## Audit of every other filter surface (R41 asks for this by name)

Checked, and clean:

- **`MapFilterCopy`** — no empty-state copy since task #165; `moreChipLabel` is a count *on the
  chip*, which R23.1 sanctions and R41 re-sanctions by name.
- **`MapSpeciesLegend`** — draws with or without a filter; it is the species *control*, not a report
  about one, and its entries are buttons.
- **`MapSearchStatus`** — search, not a filter. E126's carve-out survives for location and search,
  and R41 says so.
- **The drawer** — chips only, including #179's new control. No prose.
- **`MapSiteKindFilterCopy`** — deliberately holds a label and two option words and no sentence.
- **The empty map** — still draws nothing when a filter matches nothing (the task #165 correction to
  R31), which #179 makes reachable in a new way: `Empty planting site` + a decade is a contradiction
  after #178 and empties the map with no explanation, exactly as ruled.
