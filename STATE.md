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

## Unverified / exact next step

ON-SCREEN verification (step 4 of brief) is IN PROGRESS, nothing observed yet:
- App built+installed on DE8E11AE from dd-w4cb; camera+location granted; location set
  37.3352,-121.8895 (downtown SJ). NOT yet launched/watched.
- Next: launch app.cypress.Cypress; screen 07: open a species page (e.g. search Platanus) and see
  the `Near you` card draw a count; screen 08: create a visit on an SJ tree (in-app flow, or
  inject a `visits` row into the app container DB then relaunch), open My Grove → Species, see the
  ring + caption "you can recognize within a 15-minute walk of your most-visited tree".
- After watching: delete this STATE.md, final report (screens blind + evidence, fix, test names,
  VERIFY-OK line, branch + final commit).
