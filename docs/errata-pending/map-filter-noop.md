### The `In bloom` and `Needs care` chips did nothing to a clustered map, and the badges that survived lied about their counts (task #240)

Owner-reported, 2026-08-04, verbatim:

> try clicking the In Bloom or Needs Care filters. Nothing changes on the main screen, esp zoomed
> out, EVEN THOUGH NOTHING MEETS THOSE FILTER CRITERIA!

Reproduced on the running app before any code was read (iPhone 16 Pro, `CYPRESS_LOCATION=37.795,
-122.403`), and it is two defects wearing one symptom.

**1 · A filter applied after the fetch cannot narrow an answer the fetch already aggregated.**

`MapFilter` is a conjunction of dimensions, and five of the six rode on `MapViewport` into the SQL.
`condition` — SCREENS.md 01 §12's own two chips — did not. `MapModel.recomputeAdmittedPins` fetched
the viewport un-narrowed and filtered **the pins it got back**:

```swift
switch filter.condition {
case nil:        pins = fetched.items
case .needsCare: pins = fetched.items.filter { MapPinKind.needsCare(status: $0.status) }
case .inBloom:   … pin.speciesID → species[id]?.seasonal.bloomMonths.contains(month) …
}
```

That is correct at zoom ≥ 16 and is *nothing at all* at zoom ≤ 15, because the first line of that
method is `guard case let .pins(fetched) = content else { pins = []; return }`. Below A1's
clustering threshold the answer is `MapContent.clusters` — one badge per 64 pt cell, carrying a
`COUNT(*)` and a centroid — the guard takes the early branch, and the badges the map actually draws
are read straight off `content` having never met a filter.

Measured on the running screen, whole-city zoom over San Francisco: with `In bloom` off and with it
on, every badge identical — `117 · 87 · 313 · 140 · 511 · 558 · 30 · 248 · 118 · 168 · 549 · 327 ·
377 · 347 · 537 · 61 · 203 · 302 · 305 · 349 · 413`. Same for `Needs care`, which **no tree in the
shipped seed satisfies**: the seed's only two statuses are `alive` (174,425) and `vacant_site`
(24,200), so the correct render is an empty map and what drew was San Francisco.

There is no version of `recomputeAdmittedPins` that could have fixed this. A `TreeCluster` carries
an id, a centroid and a count; the trees it stands for are not in the answer and cannot be recovered
from it. This is the family of E36 and E38 — a predicate applied downstream of a budget already
spent — and `TreeQueries.Narrowing`'s own comments prescribe the only fix: the `WHERE` clause, where
all four map statements read it.

- `TreeStatus.needsCare` (`Core`) — the one definition, an exhaustive switch beside
  `acceptsNewContributions`. The amber pin reads it, `TreeQueries.Narrowing` builds `AND t.status IN
  (…)` from it, `LocalAPI` filters the community layer with it. `deadReported` is deliberately
  outside the arm: a reported death is a claim awaiting a lead (DECISIONS §3.7) and `MapPinKind` has
  never drawn it amber.
- `MapViewport.bloomMonth` / `.needsCare`. `In bloom` **is a species narrowing** — it resolves
  through `TreeQueries.bloomingSpeciesIDs` and is *intersected* with any typed or tapped species,
  never substituted for it.
- `MapFilter.Condition.narrowing(month:)`, a total function. A third chip cannot be added without
  saying how the database answers it, which is the guarantee that stops this recurring.

The post-fetch switch is gone, and `resolveSpeciesForVisiblePins` with it — the bloom chip no longer
needs a species read per pin on screen.

**A stale comment was refuted on the way.** `MapModel` asserted that "every `seasonal` in the
shipped seed is `{}` and this chip currently matches no tree in any month". It is not: 11 species
carry bloom months, and 2,472 trees are `Corymbia ficifolia`, which blooms in July, August and
September. The chip has had something real to match for at least a corpus, and was showing the whole
city instead. A confident comment is where bugs survive here.

**2 · A cluster badge kept the count it was born with.**

With the chips reaching the query, the running screen showed the second half. `MapAnnotationLayer`'s
`sync` diffed cluster annotations by membership in `Set(clusters.map(\.id))`. `TreeCluster.id` is
`z<zoom>:<cellY>:<cellX>` — deliberately stable across a pan so badges do not flicker (E130) — and
the count and centroid are not in it, while `TreeClusterAnnotation` freezes its `kind`, count
included, at init. So a cell wanted before and wanted now kept the badge it already had. Pressing
`In bloom` dropped the cells that emptied out and left every survivor reading `511 · 549 · 347 ·
537 · 377` — the un-narrowed counts. A map that had answered the question and was still displaying
the old answer, which is worse than the no-op it replaced.

The pin loop three lines below already had the rule ("an id that is still wanted but now draws
differently is retired here"); the cluster loop never did. It compares the whole `TreeCluster` now,
so identical clusters still compare equal and E130's "an update that changes nothing costs nothing"
is intact.

**This half is not new and was not caused by the first half.** A species typed into C20 has narrowed
clustered counts since #116, and had the same stale badges.

**Cost, measured rather than assumed.** `t.status` is not in `idx_trees_lat_lon`, so a needs-care
cluster query stops being covering — the exact cost `clusters(in:)` warns about. Over the shipped
seed, whole-city box, warm: 68 ms un-narrowed, **96 ms** with the status clause, against **95 ms**
for the year narrowing that has shipped since #116. `sqlite_stat1` records 99,313 rows per status,
half the table, so the planner declines `idx_trees_status` and is right to. The bloom narrowing is
cheaper than un-narrowed (3 ms), because the planner answers it through
`idx_trees_species_current`. Only a pressed chip pays anything.

**After the fix, on the same screen**: `In bloom` at whole-city zoom draws `15 · 7 · 3 · 6 · 5 · 4`
where it drew `511 · 549 · 347 · 537 · 377`; `Needs care` empties the map entirely, with the
`Clear filters` chip as the one way out and no message box (task #165, RULINGS R41).

**Tests.** `CypressTests/MapFilterTests` section 8 — every load-bearing expectation is against a
*clustered* viewport, because the pin regime is the half that already worked and a pin-only test
would have passed on the broken code. `aConditionMeansTheSameThingAtBothZooms` states the invariant
the defect denied: one box, one filter, asked at zoom 12 and at zoom 16, standing for the same
trees. `CypressTests/MapMarkerRenderingTests.clusterBadgeFollowsItsCount` drives the real
coordinator's `sync` against a real `MKMapView`. Every expectation is derived from a second,
independent read of the seed.

Six red-proofs, each watched failing for its stated reason and restored:

| break | test that went red | message |
|---|---|---|
| `needsCare` clause dropped from the SQL predicate | needs-care badges | `(narrowed → 145837) == (expected → 0)` |
| `deadReported` admitted to `TreeStatus.needsCare` | one definition | `!(.deadReported.needsCare → true)` |
| `bloomMonth` ignored in `narrowing(for:)` | in-bloom badges | `(narrowed → 145837) == (expected → 26237)` |
| bloom resolved for the pin query only | same thing at both zooms | `(clustered → 157) == (pinned → 21)` |
| bloom set replaces the species set | intersection | `(both → 26237) == (speciesAlone → 4703)` |
| cluster diff back to id-only membership | badge follows its count | `(kind → .cluster(count: 549…)) == .cluster(count: 12…)` |

**One test asserted the defect and is inverted.** `MapDetailTests.filterChangeRecomputesTheAdmittedPins`
— "changing the filter re-admits the pins without another read" — set the chip and read `model.pins`
on the next line with no refetch, which is exactly the post-fetch filter that does nothing at
zoom ≤ 15. It passed for as long as the defect shipped. It is now
`a condition chip refetches, and the pins that come back honor it`.

**Not taken, owner's call.** Nothing here invents a surface. An empty filtered map remains the whole
answer (task #165: "if nothing matches, fine") and no sentence accompanies it (R41). Whether
`Needs care` is worth a chip at all while the seed carries zero `declining` rows is a product
question this task did not answer: the chip is specified by SCREENS.md 01 §12 and it now tells the
truth, which is that nothing here needs care.
