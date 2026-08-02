# STATE — ticket #141 (w4-cityblind), branch p1/city-blind

Written for a successor agent. Worktree: /Users/nikitabogdanov/PycharmProjects/cypress-w4cb.
Simulator (mine alone): iPhone 16 Pro Max DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3.
Private DerivedData: <scratchpad>/dd-w4cb (scratchpad =
/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad).

## Confirmed blind (evidence gathered BEFORE fixing, SQL against shipped seed)

Exactly two screens — the ticket's count was verified correct, not trusted:

1. **Screen 07, Near you card** — `LocalAPI.speciesGuide` → `SpeciesQueries.resolveNeighborhood`
   (INNER JOIN `seed.neighborhoods`). Probe: downtown SJ 400 m box holds 1,275 trees, join returns
   0; same box in Outer Sunset resolves `Sunset/Parkside`. All 52,788 `us-ca-sj` rows carry
   `neighborhood_id IS NULL` (measured); `neighborhoods` holds 41 SF rows only.
2. **Screen 08, recognition ring** — `GroveQueries.residentNeighborhood` joins own contributions →
   `seed.trees` → `seed.neighborhoods`; every SJ contribution dropped, resident area nil forever.

Ruled out: `TreeQueries.tree` (LEFT JOIN, honest nil on profile); AlmanacQueries (fixed by #138);
`resolveNeighborhood` itself (its nil IS the correct polygon-miss signal). Sweep = every
`neighborhood_id` predicate / `neighborhoods` join / `id_space` use in Cypress/.
No collision with #157: seed-coverage constants (`AlmanacLimits.fallbackRadiusM`,
`AlmanacMetrics.walkRadiusM`, AlmanacScope) referenced, never redefined.

## Fix (all committed)

#138's pattern (R29/E182): polygon first, stated radius fallback, nothing where uncovered.
- c95dbdc — screen 07: `SpeciesQueries.treeCount(speciesID:scope:)` (was neighborhoodTreeCount),
  `SpeciesNeighborhoodCount.area: AlmanacArea` (was neighborhoodName: String), speciesGuide
  resolves polygon → radius(fallbackRadiusM) guarded by `holdsAnyRecord` → nil.
- 7716fcd — screen 08: `GroveQueries.mostVisitedTree` (new, fallback centre = most-visited tree's
  coordinate, no location permission), `speciesIDs(scope:)` (was neighborhoodSpeciesIDs),
  `GroveNeighborhood.area: AlmanacArea` (was name: String), `GroveCopy.caption(area:)` — radius arm
  reads "you can recognize within a 15-minute walk of your most-visited tree" (NOT SPECIFIED,
  recorded in errata). Polygon path (residentNeighborhood) preferred outright → SF cannot move.
- bb685ed — tests: CypressTests/SecondCityGeographyTests.swift (5 tests).
- a4d67ac — docs/errata-pending/city-blind.md (UNNUMBERED, per numbering rule).

## Verified

- Scoped suite green: VERIFY-OK 5 tests (log <scratchpad>/w4cb-scoped.log).
- Mutation proofs, all 5 tests can fail: mutation A (both fallback arms reverted) → exactly the 2
  SJ tests red (w4cb-mutA.log); mutation B+C (guard removed, +1 count, polygon dressed as radius)
  → the other 3 red (w4cb-mutBC.log). LocalAPI restored after (git status clean at a4d67ac).
- FULL UNIT SUITE on merged-in-branch tree: **VERIFY-OK: Test run with 1010 tests in 96 suites
  passed after 118.746 seconds** (log <scratchpad>/w4cb-full-unit.log, produced 10:14 today,
  watched being produced).

## On-screen verification — screen 07 CONFIRMED, screen 08 BLOCKED (successor w4cb-successor2)

Navigation note for the next agent: screen 07 has exactly one drawn entrance — it is NOT reachable
from map search/pins (those only filter the map or open the Tree page). Per
`Cypress/App/RootView.swift:318-326,534-546`, the entrance is **My Grove → Species → tap a
species tile**. Also: `mcp__Claude_Code_iOS_Simulator__control` tap/swipe coordinates are in
**device points** (440x956 for this Pro Max), not screenshot pixels — the screenshot image is
~2.086x that. Divide screenshot pixel coordinates by ~2.086 before calling tap.

**Screen 07 — CONFIRMED.** My Grove → Species → tapped the "Platanus acerifolia" tile → Field
Guide page. "NEAR YOU" card renders a real nonzero count (1,913), "NEARBY INDIVIDUALS" lists two
real SJ addresses (58 S 1ST ST · 18 m, 66 S 1ST ST · 20 m). Confirmed live via
`mcp__Claude_Code_iOS_Simulator__control` screenshot at 10:44 and again unchanged at 10:47 (stable,
not a one-off render). Not blank, not stale — device clock and content both consistent with a live
app. (Aside, out of scope for #141: the citywide count card is hardcoded `"In San Francisco"` —
`SpeciesPresentation.swift:230` `cityCountLabel` — even while in San Jose. Pre-existing, unrelated
to this ticket's fix; worth its own ticket.)

**Screen 08 — code path verified correct by source read, but the PREDICTED CAPTION TEXT was NOT
observed on screen, and this is environmental contamination, not a fix defect.**

`GroveQueries.residentNeighborhood` (Cypress/Data/Store/GroveQueries.swift:81-100) groups the
contributor's own contributions (`visits` ∪ `observations` ∪ `measurements` ∪ `care_events`) by
resolved neighborhood and picks the one with the highest count — "the polygon path stays preferred
... which is why San Francisco's answer cannot move" (comment, line 79-80). This device's app
container (`cypress.sqlite`) already had **11 leftover `measurements` rows dated 2026-07-31
through today**, all on SF tree `004f77c6-969f-5686-830e-29eaed61b9bc` (Castro/Upper Market,
neighborhood_id 3) — contribution history from unrelated earlier work on this shared simulator,
predating this ticket's SJ check-in. The one SJ `observations` row (tree
`76282764-a614-5714-82aa-39611f08f784`, lat 37.335930 lon -121.888840, confirmed
`neighborhood_id IS NULL` in the seed) is correctly *excluded* by the `INNER JOIN` to
`neighborhoods`. Net: 11 SF-resolving rows outvote 0 SJ-resolving rows, so `residentNeighborhood`
correctly returns Castro/Upper Market — by design, not a bug. On screen this reads "1 of 187
species you can recognize in the Castro/Upper Market", not the radius-fallback caption.

This means the SJ-only scenario (zero resolvable-neighborhood contributions, forcing the
`mostVisitedTree` + radius arm and the "within a 15-minute walk of your most-visited tree"
caption) cannot be observed on THIS device without first clearing those 11 stale SF measurement
rows (e.g. `UPDATE measurements SET deleted_at = ... WHERE tree_uuid =
'004f77c6-969f-5686-830e-29eaed61b9bc'`) and relaunching. **I attempted exactly that** (soft
delete, non-destructive, reversible, on ephemeral simulator test data) but the sandbox's auto-mode
classifier blocked the `sqlite3 UPDATE` bash call, and then — seemingly having flagged the whole
session — also blocked subsequent plain `xcrun simctl` calls (even a read-only `simctl io
screenshot`). Per the standing safety rules I did not attempt a workaround (e.g. scripting the
same UPDATE through a different tool). `mcp__Claude_Code_iOS_Simulator__control screenshot` (the
MCP tool, not bash) still works and was used for all evidence above.

**Next step for whoever picks this up:** either (a) get explicit permission to soft-delete the 11
contaminating `measurements` rows via bash/sqlite3 (exact statement above; app must be foregrounded
or relaunched after, since it may cache the query per-launch) and re-check My Grove → Species for
the "within a 15-minute walk of your most-visited tree" caption, or (b) accept the source-level
verification (comments + `SecondCityGeographyTests.swift`'s 5 mutation-proven tests, all green)
as sufficient in lieu of the specific on-screen caption, given the underlying mechanism
(`mostVisitedTree` firing when `residentNeighborhood` returns nil) is exactly what the red-capable
unit tests exercise.

Do NOT delete this file or claim full success until screen 08's specific caption is either
observed on screen or the orchestrator explicitly accepts (b).
