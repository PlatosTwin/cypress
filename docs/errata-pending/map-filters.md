### E175 — Three trees in four have no planting date, so a year filter is mostly a claim about the city's paperwork

**Ticket #116, screen 01.** The owner's instruction on the year filter was to check the seed before
designing the control: "`plant_date` coverage is not 100% and a filter that silently drops every row
with no date is a lie. Count it first."

#### The count

Against the shipped seed (`Cypress/Resources/cypress-seed.sqlite`, `trees_source = city`,
`trees_snapshot_on = 2026-07-26`):

```
total rows                     145,837
carrying planted_year           37,962   26.03 %
carrying no planted_year       107,875   73.97 %
```

By status, which is the split that matters, because the map mostly draws living trees:

```
status        rows      with year    %
alive       133,424       28,725    21.5
vacant_site  12,413        9,237    74.4
```

Range of the dated rows: **1955–2026**. Distribution: pre-1990 7,742 · 1990s 8,746 · 2000s 10,134 ·
2010s 8,493 · 2020s 2,847.

The schema already says this is one fact at two grains and holds them together —
`CHECK ((planted_on IS NULL) = (planted_year IS NULL))` — so there is no partial state to exploit. A row
either has a planting date or it does not, and four out of five living street trees do not.

#### Why that is a design fact and not a footnote

`planted_year BETWEEN 2010 AND 2019` is an honest predicate. SQLite's three-valued logic drops every
NULL, which is correct — a tree with no recorded date is not a tree known to have been planted in the
2010s. The dishonesty is not in the SQL, it is in **what the reader concludes from the silence.**

A map that empties out under `Year: 2010s` is read as "there are no 2010s trees on this block". What is
actually true is "the city did not record when about three of these four trees were planted." Those are
different claims and the app is only entitled to the second one. At 26 % coverage the first claim is
wrong far more often than it is right.

This is the same shape as E158 — screen 11 spent its whole life telling people their GPS fix was "too
weak" when the phone had merely not answered yet — and the same shape as E38's page-as-total: an
absence rendered as an answer.

#### What was done

The predicate stands. The **surface** carries the rest: whenever a decade is chosen, screen 01 renders

> About 3 in 4 trees have no recorded planting date—none of them can appear under a year.

The `planted_year IS NOT NULL` clause is written into the SQL beside the `BETWEEN` even though it
changes no row, so a reader of the query plan sees the decision rather than inferring it from a missing
clause. `LocalAPI` applies the same rule to the community layer in Swift — a community tree with a nil
`plantedYear` is excluded, matching the seed side exactly — because a dashed pin surviving a year filter
would be the map claiming the community recorded a date the city did not.

The proportion is stated rather than a per-viewport count. That trade is argued in RULINGS **R23** §4:
the honest per-viewport number costs a second full fetch of the box on every pan, and the proportion is
a property of the inventory that is true on every screenful. `CypressTests/MapFilterTests` pins it
against the shipped seed on both the raw share and the rounding, so a re-ingest that moves coverage
fails the build instead of leaving the sentence lying on screen.

#### Proving the new tests can fail

Six deliberate mutations, applied together, one per assertion, run against
`CypressTests/MapFilterTests` — `Test run with 16 tests in 1 suite failed after 0.412 seconds with 10
issues.` Each mutation was reverted afterwards and the tree re-verified clean.

| # | Mutation | Test that went red |
|---|---|---|
| M1 | `contributedTreeIDs` loses its owner clause | Yours holds the trees this device contributed to, and no one else's |
| M2 | an empty `treeIDs` set resolves to "not narrowed" instead of `.matchesNothing` | an empty membership set empties the map rather than showing every tree |
| M3 | `favoriteTreeIDs` drops `deleted_at IS NULL` | Favourites excludes a tree whose favourite was turned back off |
| M4 | the `plantedYears` clause is never emitted | a year-narrowed viewport returns no tree without a planting date |
| M5 | `MapFilterCopy.result` always reports the drawn page | the result line reports matches, not the size of the thinned page |
| M6 | `MapViewport.shouldCluster` stops exempting membership | only a membership narrowing suspends clustering |

Selected red output, verbatim:

```
MapFilterTests.swift:104:9: Expectation failed:
  (yours → [14C2C728-…, C37AE43F-…]) == ([mine] → [C37AE43F-…])
MapFilterTests.swift:105:9: Expectation failed:
  !((yours → […]).contains(theirs → 14C2C728-…) → true)

MapFilterTests.swift:201:9: Expectation failed:
  (favourites → [14C2C728-…, C37AE43F-…]) == ([kept] → [C37AE43F-…])

MapFilterTests.swift:315:9: Expectation failed:
  (undated → [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, …
MapFilterTests.swift:317:9: Expectation failed:
  (outside → [2020, 1997, 2023, 2024, 1994, 1995, 1994, 1994, 1998, …

MapFilterTests.swift:351:9: Expectation failed:
  (thinned.contains("1458") → false) || (thinned.contains("1,458") → false)
MapFilterTests.swift:353:9: Expectation failed: (thinned → "151 trees") != "151 trees"

MapFilterTests.swift:473:9: Expectation failed:
  !((MapViewport(bounds: city, zoom: 12, treeIDs: [UUID()]) → …).shouldCluster → true → true)
```

M4's output is the one worth reading twice: with the year clause gone, the viewport came back holding
a long run of `nil` planting years and a spread of 1992–2024. That is precisely the silent set the
caveat above exists to speak for.

#### A second defect, found by running the app and not by reading it

With `Yours` on and no matches in view, screen 01 drew a `0 trees` pill in the chrome **and** a
`No trees of yours here` card below it. The same fact twice, with the weaker phrasing on top; the card
says why the map is empty and offers the way out (E126), and a bare zero says neither. The result line
now draws nothing when the map is empty.

The unit suite was green across both states. It could not have caught this — the two surfaces are
correct individually and only wrong beside each other, which is a thing you see and not a thing you
assert. `Test run with 917 tests passed` said nothing about it.
