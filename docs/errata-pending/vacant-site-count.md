# (pending) — 12,518 vacant sites is a San-Francisco-only number and four documents still quote it

*Written from the branch `p1/map-filters` (tasks #178, #179). Unnumbered by CLAUDE.md's rule.*

## The claim, and what it actually is

The figure **12,518 vacant planting sites — 6.4 % of the map** appears in `docs/ROADMAP.md` §1 (twice),
`docs/RULINGS.md` R7, and `docs/investigations/` (`inventory-contract.md`, `city-tree-source.md`).
It was also the premise handed to this branch in its brief.

It was measured against the **San-Francisco-only** seed, the 195,309-row file, and has been wrong
since San Jose landed (E176). Counted against the shipped two-city seed:

| | rows |
|---|---|
| `trees` total | 198,625 |
| `status = 'alive'` | 174,425 |
| `status = 'vacant_site'` | **24,200** |

So vacant sites are **24,200 rows — 12.2 % of the map**, not 12,518 and 6.4 %. Roughly twice as
many, and roughly twice the share.

## Why it matters rather than being a rounding quibble

The number is load-bearing in the documents that carry it. ROADMAP §1 argues from it that the empty
basins "are the single best answer to 'where could a tree go'" and are worth a state of their own;
R7 uses it to size the pin problem. Both arguments get *stronger* with the true number, so nothing
built on it has to be revisited — but a document that states a measured fact wrongly is a document
the next agent will measure something against.

This is the same shape as the correction inside E202-B and the R31 correction: **a figure that was
true when written, quoted forward past the event that changed it.** Under D16 the seed is a merged
inventory, so any count over it is a weighted sum over whichever cities are in, and every one of
them moves when a city is added. `MapYearFilterCopy.undatedShareOfSeed` had already fired once for
exactly this reason (0.7397 → 0.8078, E175 → E176); the vacant-site count moved on the same day and
nobody was watching it.

## Related stale figures found in code while doing #178

Both are comments, both now corrected in place:

- `TreeQueries.Narrowing.predicate` stated "107,875 of the seed's 145,837 rows have no planting
  date". The true figures are **160,440 of 198,625**.
- `MapViewport.plantedYears`'s doc comment stated "145,837 rows, of which 37,962 (26.03 %) carry
  `planted_year`", and a derived claim about 133,424 living trees. The true figures are **198,625
  rows, of which 38,185 (19.22 %)** carry a planting year.

Both were San-Francisco-only measurements presented as facts about the shipped seed.

## What is pinned now

`MapFilterTests.plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor` asserts all three of the
facts the map filters are designed around — the undated share, the vacant-site share, and the count
of vacant sites carrying a planting year — as **ranges against the live seed**, not as remembered
constants. A re-ingest that moves any of them fails the build with a message naming the design
document to re-read.

The ranges are deliberately loose (e.g. vacant sites between 8 % and 18 %). A tight pin on a number
this branch happened to measure would be a false red one city later, which is the failure this whole
entry is about.

## What to do at merge

Correct the figure in `docs/ROADMAP.md` §1, `docs/RULINGS.md` R7, and the two investigation
documents — or, if investigation documents are treated as dated records of what was true when
written (which is defensible and may be the standing convention), leave them and correct only
ROADMAP and RULINGS, which are read as current. This branch changed **no document outside
`docs/errata-pending/`**, because R7 and ROADMAP are shared files and other branches are live in
them.
