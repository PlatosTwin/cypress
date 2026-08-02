# (pending) — The two screens E182 left blind outside San Francisco now resolve R29's area

Task #141. The family is E182's (task #138, RULINGS R29): a read scoped to `seed.neighborhoods` is
scoped to San Francisco's 41 Analysis Neighborhoods and to nothing else, so all 52,788 San Jose rows
— every one carrying `neighborhood_id IS NULL` — are invisible to it. R29 fixed screen 12 and named
the two surfaces it had no standing to redesign; E182 §5 recorded them, unfixed, in so many words.
This entry closes both. No third was found: the sweep over every `neighborhood_id` predicate and
`neighborhoods` join in the app leaves exactly `TreeQueries.tree` (a `LEFT JOIN` whose `nil` is an
honest absence on the profile, not a dropped row) and the reads behind these two screens.

## What was actually blind, with the measurements

Probed against the shipped seed (108,007,424 bytes, `sf|145837`, `us-ca-sj|52788`) before writing
any fix:

- **Screen 07, the `Near you` card.** `LocalAPI.speciesGuide` resolved an area through
  `SpeciesQueries.resolveNeighborhood` — an inner join through `seed.neighborhoods` — or resolved
  nothing. Downtown San Jose's 400 m resolution box holds 1,275 inventoried trees and the join
  returns **zero** of them, so `nearYou` was nil and the card silently did not draw for every reader
  in the city. The same box in the Outer Sunset resolves `Sunset/Parkside`.
- **Screen 08, the recognition ring.** `GroveQueries.residentNeighborhood` joins the contributor's
  own contributions through `seed.trees` to `seed.neighborhoods`, so every San Jose contribution was
  dropped by the join and the resident area was nil *forever* in that city — a contributor could
  visit a thousand San Jose trees and never get a ring, a denominator, or a locked tile.

Neither rendered anything false. Both were honest absences that had stopped being honest the day a
second city landed whose readers they would never serve.

## The fix, at the layer of the defect

R29's resolution order, verbatim in both places: **the polygon first, the stated radius where none
resolves, and nothing where the record does not cover the ground.**

- `SpeciesQueries.neighborhoodTreeCount(speciesID:neighborhoodID:)` became
  `treeCount(speciesID:scope: AlmanacScope)`; `GroveQueries.neighborhoodSpeciesIDs(neighborhoodID:)`
  became `speciesIDs(scope: AlmanacScope)`. For a `.neighborhood` scope both render the identical
  predicate string they always ran, which is the safety argument in the same words E182 used: San
  Francisco cannot move, and the suite asserts its counts against direct SQL rather than trusting
  the claim.
- `LocalAPI.speciesGuide` resolves the polygon, then `AlmanacScope.radius` around the reader at
  `AlmanacLimits.fallbackRadiusM`, guarded by `AlmanacQueries.holdsAnyRecord` — the guard is what
  keeps a true `0` ("none of these grow in your covered area") distinct from a card counting ground
  the inventory has never seen. In Sacramento the card still does not draw, now for the stated
  reason. The card's label — `Near you` — required no change: it is exactly true of either area, and
  the payload carries `AlmanacArea` so no surface can dress the distance as a place.
- `LocalAPI.groveSpecies` prefers `residentNeighborhood` (the exact query it always ran), and where
  that returns nil falls back to the new `GroveQueries.mostVisitedTree` — A4's own inference,
  "resident neighborhood inferred from most-visited", still with **no location permission**: the
  radius is centred on the tree the contributor's record says they go to, not on where they are
  standing. No coverage guard is needed on this arm; the centre is itself an inventoried tree, so
  the circle covers record by construction.

## Two copy decisions, both NOT SPECIFIED, recorded here for the owner

1. **Screen 07 adds no copy.** The fallback card is the same `Near you` label over a count. Nothing
   on screen 07 ever printed the polygon's name, so nothing new needed a name withheld from it.
2. **Screen 08's fallback caption** reads `you can recognize within a 15-minute walk of your
   most-visited tree`. The mock draws only the polygon case (`you can recognize in the Outer
   Sunset`); R29's third rule decides the fallback's shape — never dressed as a place, the distance
   stated in the words screen 12's pill already uses for the same 1,200 m, and what the distance is
   measured *from* said out loud, because "within a 15-minute walk" alone would read as centred on
   the reader and it is not. It never names the city. R29's screen-12 fallback also carries an
   explanatory sentence under the header; this caption was judged to carry the same information in
   its own line, and adding a second sentence to §3's ring would be inventing a surface the mock
   does not draw. If the owner wants the sentence, it slots under the ring without moving the data.

## What a mixed-city contributor gets, decided and named

A contributor with visits in both cities takes the polygon path if *any* touched tree carries a
polygon — `residentNeighborhood` is preferred outright, not weighed against the fallback. So a
contributor whose San Jose visits outnumber their one San Francisco visit still reads an SF
polygon's ring. This is deliberate: R29 prefers the polygon wherever it exists, the alternative
(most-visited *tree* deciding which path wins) would let one visit move a San Francisco reader's
ring off the polygon path, and "San Francisco did not move" was the non-negotiable. The asymmetry
costs exactly the contributor who has crossed cities and visits the second one more — their ring is
about a place they go less — and it self-corrects the day San Jose's boundaries join the record.

## Verification

- `SecondCityGeographyTests`, five tests: SF's card and ring asserted equal to direct SQL of the old
  join (the did-not-move half); San Jose's card and ring asserted present with the radius area (the
  fix half); Sacramento asserted cardless; each San Jose test checks the no-polygons precondition
  first so a future San Jose boundary layer fails the suite loudly instead of letting it measure the
  wrong path.
- Mutation proof: with the fallback arm removed from `speciesGuide`, and separately with
  `groveSpecies`'s fallback arm removed, the corresponding San Jose tests fail; restored, the suite
  passes. (Run details in the task report.)
- Watched on iPhone 16 Pro Max at a San Jose fix: screen 07 draws `Near you` beside the whole-city
  count; screen 08 after a San Jose visit draws the ring with the walk-distance caption.

## Not done here

- The seed-coverage constants for city downloads (#157's ground) are untouched: this change is
  confined to the two screens' reads and the two payload types; `AlmanacScope`,
  `AlmanacLimits.fallbackRadiusM` and `AlmanacMetrics.walkRadiusM` are referenced, not redefined.
- `SpeciesNeighborhoodCount.neighborhoodName: String` became `area: AlmanacArea`, and
  `GroveNeighborhood.name: String` likewise (the type names stay, A4's word). Both are shared
  identifiers; any live branch constructing either will need the one-line change at merge.
- E176's SF-hardcoded copy on the tree profile, and screen 12's own surfaces, are exactly where
  E182 left them.
