# Observed states are never gated by what the app knows

**Unnumbered — pending splice by the orchestrator. Pre-authorized under delegated authority
(ticket #151, 2026-07-31).**

## The ruling

A phenology tag at check-in is the **observer's report of what is in front of them**, not the
app's claim about the species. DECISIONS constraint 15 forbids the app asserting botanical facts
it does not have; a contributor's own observation is the opposite of that — it is the community
data D16 says the product exists to collect.

Therefore: **the observed-state options (leaf out, full leaf, flowering, fruiting, fall color,
bare) are always available at check-in, whatever the species record knows.** The species'
seasonal calendar may ORDER or HINT — e.g. surface expected states first — but it never gates
availability. An unknown calendar, an unauthored field-guide entry (`curated = 0`), and an
unsourced habit (`leaf_retention` NULL, ERRATA E9) are all states of the *app's* knowledge, and
none of them is a reason to refuse the observer a word for what they can see.

## The one exclusion that stands

D5 survives, narrowed to what it actually says: a species **known** to be evergreen is never
asked about fall color or bare. That is a sourced fact that makes the tag a contradiction rather
than an observation, it is enforced in the schema CHECK, and it is the documented decision
(DECISIONS §3.14). A species whose habit nobody sourced gets the full list — excluding fall
color there would itself assert "this is an evergreen", which is the unsourced claim E9 exists
to prevent.

## What this does NOT change

- **The app's own phenology surfaces.** Screen 07's phenology section, the season strip, and
  the chips the APP draws still render only from authored content (`showsPhenology` still
  requires a sourced habit; `FoliageStrip.enforcingD5` still clamps bare months for an unknown
  habit). The ruling is about what the observer may say, not what the app may say.
- **Vitality's leaf-off gating.** `Vitality.isRatingPermitted` / `leafOffSeason` gates the
  vitality RATING — a judgement that is meaningless against a bare deciduous canopy — and its
  reasoning (PRODUCT §3) is untouched.

## Left standing, proposed for a follow-up decision

A tree with **no species record at all** (nil species: unmapped or non-taxon rows, and profile
reads that have not landed) still draws no chip row. The same principle arguably applies — the
observer can see flowering on a tree the seed calls "Shrub" — but `VisitPhenologyChips` and
`Chip.phenology(_:for:)` are built over a non-optional `Species`, and widening that is a larger
change than #151 requires. Proposed, not done.

## Where it is pinned

`CypressTests/PhenologyObservedStatesTests.swift` — the reported record (seed `sf/222615`,
Cassia leptophylla, species row 209) through the real read path, the empty-calendar and
unknown-habit cases, D5's surviving exclusion, and the seasonal order of a known calendar.
