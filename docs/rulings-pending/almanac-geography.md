# R29 — What the almanac is about, once the record holds more than one city

**Task #138.** Delegated by the ticket: *"Two candidate shapes, and choosing between them IS the
work."* Implemented in ERRATA **E182**.

---

## The question

`seed.neighborhoods` is San Francisco's 41 Analysis Neighborhoods and nothing else. Every read
behind screen 12 was `WHERE t.neighborhood_id = :neighborhood`. So all 52,788 San Jose rows, which
carry `neighborhood_id IS NULL`, were invisible to the almanac, to the neighborhood species mix, and
to the coverage panel — *the surface D1 makes the app's only directed ask*. E176 found the hole,
declined to make the product decision, and said so.

The decision is what "your area" means when the destination is **D16**: one database holding every
municipal tree inventory in the country, merged into a single normalized format.

## The two shapes, and what is actually wrong with each

**Give each city its own polygons.** Direct analogue of what SF has. Keeps the almanac's existing
concept whole, keeps the pill a place name, and San Jose does publish boundary sets.

The obvious objection is cost — a polygon set per city, sourced, licensed and ingested before that
city's trees are visible at all. That objection is real and it compounds under D16, but it is not
the objection that decides this. **The one that decides it is that the unit would not be the same
unit.** San Francisco publishes 41 *Analysis Neighborhoods*, a statistical construct its planning
department drew. San Jose publishes council districts, which are political and get redrawn every ten
years, and planning areas, which are neither. Most cities publish nothing. Presenting all of those
under one word would reintroduce at the polygon level exactly the seam D16's normalized format
removes at the tree level — and it would do it invisibly, because a pill reading `District 3` and a
pill reading `Sunset/Parkside` look like the same kind of promise and are not.

There is a second, quieter cost: it makes the almanac's national coverage a function of how many
polygon sets somebody has sourced. A second ingest pipeline, with its own licensing and its own
staleness, gating a screen that the first pipeline has already made answerable.

**Make the geography derive from something every city has** — a radius, a viewport, a generated
grid. No per-city asset; works for city thirty as well as city three.

The objection here is not the one the ticket anticipated. The copy's dependence on names turns out
to be thin: exactly two surfaces print the area's name, C1's trailing pill and the same pill on the
`PinSet` destination. The bloom row names a *street*, the elder names a species and a year, the
composition card names species. Nothing says "the Mission's oldest tree".

**What a radius genuinely loses is that the almanac stops being about a place and starts being about
you.** A named polygon is the same area for everybody standing in it: the elder is the elder, the
nine young trees are the nine, and two people on the same block are reading the same page. A circle
centred on the reader moves as they walk. "Walk the nine" becomes a claim about where somebody was
standing when they read it, and the coverage ask — the app's only directed ask — stops being
referenceable between two people. A generated grid recovers stability and loses the ability to be
named at all; `Almanac · cell 4829` is not a pill.

## The ruling

**The almanac's subject is a named area where the merged record holds one, and a stated radius
around the reader where it does not. The fallback is named as what it is — a distance, not a place —
and the screen says so in a sentence, not only in a pill.**

Three parts, and the third is the one that makes this a hybrid rather than a hedge.

1. **The polygon is preferred wherever it exists.** Nothing about San Francisco changes: the same
   ids, the same predicate, the same counts, the same denominators. This is not conservatism, it is
   the argument above — a stable, named, shared area is a better subject than a moving one, and it
   is kept everywhere it is available.
2. **The fallback is the default, not the exception.** A city's trees are visible in the almanac the
   day its inventory is merged, with no second asset. Under D16 that is the property that matters:
   the almanac's coverage is the inventory's coverage.
3. **The fallback never dresses itself as a place.** C1's pill reads **`Within a 15-minute walk`**,
   and a line under the header reads:

   > No neighborhood boundaries are on file for where you are, so this almanac is drawn around you
   > instead. It will name a neighborhood once this city's boundaries join the record.

   The pill alone is too quiet. A reader who has only ever seen `Sunset/Parkside` in that slot has
   no way to tell that `Within a 15-minute walk` is a different kind of thing rather than an oddly
   named neighborhood, and "your area" and "the Mission" are different promises. The sentence says
   which one is being made, and — D16(b)'s rule, that an honest degraded state must say what *would*
   change rather than only what does not — what would give the area a name back.

   It never names the city. The app does not know which city a coordinate is in; it knows only that
   no boundary in the record contains it, and saying more than that would be the screen guessing.

**And a third area exists: none.** A circle drawn around a reader in Sacramento is a perfectly
well-formed area with no record in it. The fallback is only taken where the inventory actually
covers the ground, and where it does not the screen says so instead of heading a blank page with a
distance. That state is E182's half of this work and would have been built whichever shape won.

## The radius is 1,200 m, and the number is not free

Two things had to be true and one number satisfies both.

- **It has to be a neighborhood-sized area, or the cold-start floors change meaning.** DECISIONS
  §2.6 shows aggregates only above their thresholds; a smaller area crosses them less often and
  would silently empty panels that were populating. SF's 41 polygons span 0.015–0.045 degrees of
  latitude; a 1,200 m radius is 0.0216, inside that range rather than beside it. Measured on the
  shipped seed, the circle around downtown San Jose holds **6,963 records and 167 species** — between
  Outer Richmond (6,216) and Noe Valley (6,361).
- **§4's second sentence has to stay honest.** The coverage card says "All nine are within a
  15-minute walk" only after checking, against `AlmanacMetrics.walkRadiusM` = 1,200 m. Setting the
  fallback to the same distance makes that check pass by construction — the sentence being *true*,
  not the check being skipped.

The two constants stay separate. If they diverge, the fallback may hold a tree §4 declines to call
walkable, which costs a true sentence rather than printing a false one.

## What this ruling does not do

- **It does not fetch San Jose's polygons**, though the ticket authorized it. Under this ruling they
  would be an optimization for one city rather than the mechanism, and adding them would require a
  `neighborhoods` table with a city column, a rule for name collisions between two cities'
  neighborhoods, and a seed rebuild that does not travel with a branch. If San Jose's boundaries are
  ingested later, R29 needs no amendment: the polygon path is already preferred and San Jose would
  simply start taking it. **That is the test of the hybrid and it passes** — the fallback is not a
  thing to migrate off, it is the floor under every city that has not been reached yet.
- **It does not change the resolution mechanism.** A polygon is still resolved through the nearest
  inventoried tree's `neighborhood_id` rather than by point-in-polygon (E44, A4). The seam A4 will
  move through is still one function.
- **It does not touch screen 07's `Near you` count or screen 08's resident neighborhood**, both of
  which have the identical SF-shaped hole. See E182; they are two other screens' tickets, and a
  geography ruling made on screen 12's behalf is not standing to redesign them.
