# New York City: the ingest half

Ingest note, 2026-08-14. Follows `docs/investigations/nyc-street-trees.md` (the 2026-08-01 survey)
and builds the thing that note recommended. Read the survey first; this note answers what it left
open, and **corrects it in four places** (§8).

Everything below is measured against a full extract of both Socrata datasets taken on 2026-08-14 —
1,121,106 Tree Points and 1,091,709 Planting Spaces rows, fetched by `Tools/fetch_nyc_trees.py`.
The extracts live outside the repo (~430 MB); `Fixtures/raw/nyc/` still holds only the survey's 38
sample rows, and the fetcher refuses a cache directory `git check-ignore` does not cover.

**Nothing here ships.** No seed was published, `dist/upload.sh` was not run, and the trial seeds in
§6 are measurement instruments.

---

## 1. What was fetched, and the drift since the survey

| | survey, 2026-08-01 | this extract, 2026-08-14 | drift |
|---|---:|---:|---:|
| Tree Points, all rows | 1,120,697 | **1,121,106** | +409 |
| Tree Points, `TPStructure='Full'` | 899,094 | **898,643** | −451 |
| `Full` with a `PlantedDate` | 123,798 | **123,725** | −73 |
| distinct `GenusSpecies` on `Full` | 620 | **620** | 0 |
| Planting Spaces, all rows | 1,091,709 | **1,091,709** | **0** |

The Tree Points drift is expected — the layer updates every two weeks. **The Planting Spaces count
not moving at all is the more interesting number**, and it is the root of §3: that dataset's
`rowsUpdatedAt` is **2025-03-05**, seventeen months before this extract, while Tree Points' is
2026-07-28. The two datasets that must be joined are not published on the same clock.

Every count in this note was reproduced locally and checked against the server's own `GROUP BY`
before being believed. That calibration caught one real error: `count(distinct genusspecies)`
returned 621 locally against the server's 620, because the CSV renders NULL as `''` and SQL's
`count(distinct)` excludes NULL but not the empty string. 21 `Full` rows carry an empty
`GenusSpecies`; the server confirms the same 21. Empty is normalized to NULL and every other
aggregate then matched exactly.

## 2. Planting Spaces ships 6,864 duplicate rows, and how they are dropped (D19)

`count(*)` is 1,091,709 and `count(distinct globalid)` is 1,084,845. The extra 6,864 are **whole-row
duplicates** — identical in every column, `OBJECTID` included — so they are one planting space
published twice, not two spaces sharing an id. That was checked on the full extract and not
inferred from a sample: `fetch_nyc_trees.py` compares every duplicate pair field by field and
reports `disagreeing_duplicates`, which is **0**.

This matters because `GlobalID` is the join key. Had any pair disagreed, the join would be
ambiguous and this would be a stop rather than a dedup.

**RULING D19's rule: among rows sharing a `GlobalID`, keep the one with the smallest NUMERIC
`OBJECTID`.** It is recorded in the receipt as `seed_meta.nyc_dedupe_rule`.

A rule is needed even though every duplicate pair here is byte-identical and the choice cannot change
the output, because "it does not matter which" is a property of *today's data*, not of the pipeline.
Keeping whichever row arrived first made the survivor depend on page order, which depends on
`$order=:id` — Socrata's own row identifier, not promised stable across a republish. The comparison
is numeric on purpose: as strings, `'10843890'` sorts before `'9'`, so a textual comparison would
pick a different twin as soon as the id range crossed a digit boundary.

**The staleness is now recorded rather than remembered.** Both datasets' `rowsUpdatedAt` are read
live at fetch time and stamped into the seed: `nyc_planting_spaces_rows_updated_at` = **2025-03-05**,
`nyc_tree_points_rows_updated_at` = **2026-08-12**.

Note the calibration trap here, because it nearly produced a wrong finding: `count(distinct
objectid)` also returns 1,084,845 — the *same* number — which looks like a hallmark of an
approximate `count(distinct)`. It is not. Both columns really do repeat, together, because the
duplication is of whole rows.

## 3. The join, and why 22,995 trees have no address

Every one of the 1,121,106 tree points carries a `PlantingSpaceGlobalID` — **zero nulls**.

| | rows |
|---|---:|
| `Full` tree points | 898,643 |
| …joining to a planting space | **875,648** (97.44%) |
| …whose key matches nothing | **22,995** (2.56%) |
| planting spaces referenced by ≥1 `Full` tree point | 875,645 |
| `Populated` spaces with no `Full` tree point | 91,775 |

**The 22,995 orphans are a publication-cadence artifact, not corruption**, and the measurement says
so: **99.9%** of them were created in 2025 or later, against **2.8%** of the 875,648 that do join.
They are trees ForMS recorded after the Planting Spaces extract was last refreshed (2025-03-05).
**The gap grows until NYC refreshes that dataset.**

They are kept, with `None` for address, site type and borough. They are also the reason a
borough-partitioned build cannot be complete: borough is a Planting Spaces column, so these 22,995
cannot be placed in any borough at all, and no attempt is made to infer one from their coordinates.

The join barely fans out: 898,633 planting spaces hold exactly one `Full` tree point and **5 hold
two**. NYC's own user guide states that "each Planting Space can have no more than one active Tree
Point at a given time", so those 5 are upstream rule violations. They are carried, not corrected.

## 4. Species

620 distinct `GenusSpecies` values on `Full` rows, in six shapes:

| shape | values | rows |
|---|---:|---:|
| clean binomial | 258 | 570,768 |
| quoted cultivar | 321 | 101,429 |
| hybrid (`x`) | 12 | 99,797 |
| variety (`var.`) | 8 | 72,421 |
| genus only | 17 | 52,385 |
| **en dash** | **1** | **28** |

**`Asimina triloba – Pawpaw` uses U+2013 and is the only non-ASCII value in the entire vocabulary.**
A `str.split(" - ")` hands that string back whole and mints a species named `Asimina triloba –
Pawpaw` shadowing the real `Asimina triloba` — task #103's mechanism exactly. The parser splits on a
regex over both dash characters, and the mutation test that proves this matters is in
`Tools/test_nyc_inventory_adapter.py`. The spaces around the dash are load-bearing in the other
direction: `Crataegus crus-galli var. inermis` carries an internal hyphen, and no value contains
more than one *spaced* dash.

### Coverage against RULING D20's 90% gate: **85.99%**, and that is the ceiling

`Fixtures/nyc_species_map.csv` resolves **772,785 of 898,643 rows (85.99%)** to a species already in
the corpus, through a five-rule cascade with one cited line per string in
`Fixtures/nyc_species_map_citations.csv`:

| rule | what it claims | authority | values | rows |
|---|---|---|---:|---:|
| R0 exact | nothing | — | 147 | 532,483 |
| R1 hybrid sign | `Platanus x acerifolia` ≡ `Platanus acerifolia` — the × is notation, not epithet | ICN (Shenzhen) Art. H.3A.1, 23.1 | 3 | 99,515 |
| R2/R3 rank within species | a variety/form/cultivar is a member of its species | ICN Art. 4; ICNCP 9th ed. Art. 2.1 | 199 | 139,039 |
| R1+R2/R3 | both of the above | as above | 2 | 33 |
| R4 spelling | one misspelling this dataset itself disproves | the extract's own spelling frequency | 1 | 1,715 |
| non-taxon | `Unknown - Unknown` is a tree, not a species | RULINGS R18 | 1 | 5,238 |
| **unmapped** | | | **267** | **120,599** |

R0 runs before R1–R3 on purpose: a cultivar the corpus already carries by name keeps its own
identity, so NYC's `Platanus x acerifolia 'Bloodgood'` reaches the corpus's own
`Platanus acerifolia 'Bloodgood'` and is never collapsed to the bare species.

**It is 35,993 rows short of the 90% gate, and the gap cannot be closed honestly.** Every one of the
268 residual values was checked against ITIS on 2026-08-14, and **not one is a synonym of a name in
the corpus**:

| ITIS status | values | rows | what they are |
|---|---:|---:|---|
| accepted | 150 | 106,956 | valid taxa the corpus simply lacks |
| synonym | 11 | 470 | synonyms of taxa the corpus **also** lacks |
| not indexed | 107 | 14,888 | cultivars, governed by the ICNCP rather than the ICN |

The corpus is California-derived and NYC's flora is the Eastern seaboard. `Fraxinus pennsylvanica`
(green ash, 15,608 rows) is not the corpus's `Fraxinus americana` (white ash); `Quercus bicolor`
(swamp white oak, 14,949) is not `Quercus suber` (cork oak); `Taxodium distichum` (bald cypress) is
not `Taxodium mucronatum`; and `Gymnocladus`, `Eucommia`, `Amelanchier` and `Cladrastis` are absent
from the corpus at genus level. Mapping any of them would be a synonymy ruling no authority supports
— exactly what D20 and DECISIONS constraint 15 forbid — so they stay unmapped and the number stays
honest. **This is a stop-and-ask: see the round's report.**

One upstream misspelling worth noting: `Platanus x acerfolia 'Exclamation'` (1,715 rows) — NYC's own
typo for `acerifolia`. Not corrected here.

## 5. `DNP` — still open, and here is exactly what was tried

**Unresolved from published sources.** Three official documents were fetched on 2026-08-14:

  * the Socrata column metadata — `PSStatus` is "Indicates if planting space is populated, empty, or
    retired". No DNP.
  * the **official ForMS data dictionary** (the Google Sheet the dataset's own description links),
    fetched as CSV — same sentence, no DNP, no allowed-values list for `PSStatus`.
  * the **official ForMS user guide** (likewise linked from the dataset description), fetched as
    text — the string `DNP` does not appear, nor does "do not plant".

So the suffix is undocumented by its own publisher. What the data shows, offered as evidence and
**not** as a definition:

| `PSStatus` | spaces | hold any tree point | hold a `Full` one |
|---|---:|---:|---:|
| `Empty` | 137,818 | 65.2% | 19.5% |
| `Empty - DNP` | 1,690 | 23.1% | **2.0%** |
| `Retired` | 3,358 | 77.1% | 0.4% |
| `Retired - DNP` | 1,442 | 89.2% | 0.6% |

An `Empty - DNP` space is ten times less likely to hold a standing tree than a plain `Empty` one,
and the 3,132 DNP spaces concentrate in Brooklyn (1,415) and Staten Island (1,213). "Do Not Plant"
is the obvious expansion and the behavior is consistent with it. **It is still a guess, so no
meaning for `DNP` is encoded anywhere in the adapter.** §5 of the survey suggested asking NYC Parks
directly; the terms' own "notify the City" obligation gives a natural occasion.

## 6. Trial seeds, per borough

Measurement instruments, not ship candidates. Every build also contains San Francisco, because
`build_seed.py` has no "no SF" option, so the NYC contribution is the **delta** against an SF-only
baseline of **108,363,776 bytes**.

| borough | NYC rows | seed size | NYC delta | bytes/row | dated | merged undated share |
|---|---:|---:|---:|---:|---:|---:|
| Manhattan | 97,104 | 167.3 MB | 58.9 MB | 607 | 11.59% | 83.28% |
| Bronx | 134,225 | 189.4 MB | 81.1 MB | 604 | 15.94% | 82.10% |
| Brooklyn | 231,514 | 248.8 MB | 140.5 MB | 607 | 15.23% | 82.92% |
| Queens | 290,364 | 284.1 MB | 175.7 MB | 605 | 12.08% | 85.02% |
| Staten Island | 121,956 | 183.3 MB | 75.0 MB | 615 | 7.39% | 85.28% |
| **whole city** | **898,643** | **651.6 MB** | **543.3 MB** | 605 | 13.77% | **85.24%** |

The five borough deltas sum to 531.1 MB against the whole city's 543.3 MB. The 12.2 MB difference is
the 22,995 orphans of §3, which no borough build can contain. At 605 bytes/row those rows are
13.9 MB of content against a 12.2 MB file difference; SQLite page allocation is not linear in row
count, so the two agree in size without agreeing exactly. Borough row counts sum to 875,163; plus 22,995 orphans and 485 rows whose planting space
carries no borough, that is 898,643 exactly.

**605 bytes/row is remarkably close to the 540 the survey estimated**, and the whole-city 543 MB is
within the survey's "on the order of 480 MB" for the row data.

## 7. `verify_seed.py` is San Francisco-only, and a San Jose control proves it

Every NYC build fails four checks. A **San Jose** control build — the shipped, blessed
configuration — fails three of the same four, which is what separates "NYC is broken" from "the
verifier has one city in it":

| check | NYC | San Jose control | why |
|---|---|---|---|
| 1. row count in 150,000..260,000 | FAIL | pass | a hardcoded SF-era range |
| 2. zero trees outside the SF bbox | FAIL | **FAIL** | reads `seed_meta.sf_bbox` |
| 13. neighborhood stamping ≥ 99% | FAIL | **FAIL** | `neighborhoods` holds SF's 41 analysis neighborhoods; San Jose is stamped 0 |
| 16b. uuid == uuid5(NS_TREE, TreeID) | FAIL | **FAIL** | ignores the id-space prefix |
| 12. external_ref is unique | pass | **FAIL** | NYC's GlobalIDs are unique; San Jose's are not |

So NYC's only *new* failure is check 1's row-count range. Checks 2, 13 and 16b have been failing for
San Jose since #129 and are a pre-existing gap, not something this round introduced.

**Check 14 caught a real defect and is now fixed.** It flagged a tree planted in **2108**. Across all
1,121,106 tree points `PlantedDate` is non-null on 136,730 and exactly **three** are in the future —
`2030-11-02` (CreatedDate 2020-11-04) and `2108-11-23` twice (CreatedDate 2018-11-27) — each a
transposition whose intended year is legible from its own `CreatedDate`. The adapter clamps them to
`None` and counts them. **Correcting them to the implied year would be inventing a fact**, which is
the one thing an adapter may not do.

## 8. Where the survey is wrong

Four corrections, all measured:

  1. **The seed corpus is 731 species, not 738.** The survey's §4 says 738 twice. `count(*)` on
     `species` is 731, `count(distinct scientific_name)` is 731, there are no soft-deleted rows, and
     `seed_meta.species_count` says `731`. `Tools/validate_species.py` prints 731 as well.
  2. **The merged whole-city undated share is 85.24%, not ≈86.6%.** The survey's own inputs give
     85.24% — `(160,440 + 899,094 − 123,798) / (198,625 + 899,094)` — so the 86.6% is an arithmetic
     slip rather than a drift artifact. Measured against this extract and the shipped seed:
     `(160,441 + 774,920) / 1,097,268` = **85.24%**. The current shipped share is 80.78%.
  3. **The schema is not what blocks standing-dead trees.** See §9.
  4. Minor: the shipped seed has 160,441 undated rows, not 160,440; and `TPStructure` is NULL on 11
     rows, a sixth value the survey's table does not list.

## 9. Standing dead trees: the schema already has the slot

The survey (§6) and the brief both treat "a standing dead tree" as a fact the schema cannot hold,
and the owner has scheduled a migration round on that basis. **The migration may not be needed.**

`trees.status` already permits `dead_reported`, and its own documentation defines it as exactly this
case — `Cypress/DesignSystem/Components/StatusBadge.swift`: a `dead_reported` tree "is still standing
over a pavement", and is "**not** a second way of saying `removed`". It has a badge, a pin, a
`TreeStatus` case and a RULINGS entry (R19) settling how it renders.

What is actually missing is one field and one lookup, both in Python:

  * `InventoryRecord` has no field for a source's condition, so an adapter cannot report one;
  * `build_seed.STATUS_FOR_KIND` is a dict keyed on `kind` **alone**, so every `KIND_TREE` becomes
    `alive` and no adapter can produce `dead_reported`.

That is a change to `Tools/inventory_contract.py`, not a database migration. It is **not made here**,
because it moves San Francisco's and San Jose's rows too and this round is forbidden to touch either.

Until it is made, 10,635 standing dead trees ship as `alive`. **Nothing is lost**: `TPStructure` and
`TPCondition` are carried verbatim into `city_record` (`plant_type` and `permit_notes`), so every one
is recoverable from the seed, and `seed_meta.nyc_standing_dead_mapped_to_alive` states the size of
the claim in the file.

The full `(TPStructure, TPCondition)` cross-tab the schema round needs is in §10.

## 10. `(TPStructure, TPCondition)`, all 1,121,106 rows

| TPStructure | Excellent | Good | Fair | Poor | Critical | Dead | Unknown | total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Full** | 100,342 | 450,857 | 309,651 | 22,046 | 946 | **10,635** | 4,166 | 898,643 |
| Retired | 10,020 | 20,525 | 10,888 | 20,697 | 4,135 | 82,366 | 25,454 | 174,085 |
| Stump | 86 | 424 | 666 | 5,722 | 1,593 | 32,445 | 3,211 | 44,147 |
| Shaft | 21 | 168 | 331 | 535 | 95 | 1,349 | 45 | 2,544 |
| Stump - Uprooted | 0 | 12 | 12 | 41 | 83 | 1,272 | 256 | 1,676 |
| *(null)* | — | — | — | — | — | — | — | 11 |

The condition columns sum to 1,121,095; the missing 11 are the rows with no `TPStructure` **and**
no `TPCondition`, which is the same 11.
| **total** | 110,469 | 471,986 | 321,548 | 49,041 | 6,852 | 128,067 | 33,132 | **1,121,106** |

The adapter's current, **provisional** mapping uses `TPStructure` only: `Full` → `tree`, and
`Retired`/`Stump`/`Shaft`/`Stump - Uprooted` → `not_a_tree`. Condition decides nothing yet.

## 11. Borough, after RULING D18

**Every NYC tree now carries a borough, and the five packs sum exactly to the whole city.**

The authority is the City's own `Borough Boundaries` (Socrata `gthc-hcne`, shoreline-clipped, 3.1 MB,
five MultiPolygons), cached beside the two extracts and checked in at
`Fixtures/nyc_survey/borough_boundaries.geojson` so the tests are real. Its `boroname` values are the
same five strings Planting Spaces writes in `boroughcode`, so no code mapping is needed — asserted in
the tests rather than assumed. The water-included variant (`wh2p-dxnf`) was measured on the same
898,643 points and leaves 522 outside every polygon against `gthc-hcne`'s 543, a 21-row difference
that does not justify claiming a tree stands in open water.

**The precedence is the ruling's, and geometry never overrides the City.**

| outcome | rows |
|---|---:|
| borough STATED by the planting space | 875,163 |
| assigned by point-in-polygon | 22,998 |
| assigned by nearest polygon, within 500 m | 482 |
| **unassigned** | **0** |

The 500 m cap is measured, not chosen: the 543 points outside every polygon sit min 0.03 m, median
25.4 m, **max 310.0 m** from the nearest borough — trees on the shoreline side of a clipped boundary,
or on the Queens/Nassau and Bronx/Westchester city lines. Beyond the cap the build **stops**;
`records()` raises rather than emitting a row with no borough.

**Calibration, which the ruling asked for.** Geometry was run on the 875,163 rows that already state
a borough, purely to compare:

| | rows |
|---|---:|
| geometry agrees with the City | 875,095 |
| geometry **disagrees** | **7** |
| outside every polygon (keeps its stated borough) | 61 |

The seven are: Staten Island→Queens (3), Manhattan→Brooklyn (2), Brooklyn→Queens (1),
Queens→Brooklyn (1). **They keep what NYC says.** Overriding a city's own attribution from a
shoreline-clipped polygon would be this pipeline deciding a civic question it has no standing to
decide, and seven rows in 898,643 is not evidence that the City is wrong.

### The borough packs

| pack | NYC rows | seed size | NYC delta | dated |
|---|---:|---:|---:|---:|
| Manhattan | 98,929 | 173.1 MB | 64.7 MB | 12.45% |
| Bronx | 137,858 | 197.2 MB | 88.8 MB | 17.22% |
| Brooklyn | 237,596 | 263.8 MB | 155.4 MB | 16.18% |
| Queens | 298,839 | 302.4 MB | 194.0 MB | 13.15% |
| Staten Island | 125,421 | 190.2 MB | 81.9 MB | 7.93% |
| **sum of packs** | **898,643** | | | |
| **whole city** | **898,643** | 693.8 MB | 585.4 MB | 13.77% |

Sizes are ~42 MB larger than the pre-D18 measurement because `boroughcode` and `boroughsource` now
ride on every row in `trees.city_raw` (~47 bytes/row). That is the interim cost of carrying the
borough at all, and it goes away when `trees.region` lands in s17.

## 12. Where borough lives on the record

The distribution design makes a borough-level region the published unit, and `boroughcode` exists
only on Planting Spaces — so it travels **on the record**, in `raw_json` → `trees.city_raw`,
**unconditionally** (not gated behind `--with-city-raw`, which does gate `RiskRating` and
`psstatus`). 875,163 of 898,643 rows carry one; 23,480 do not, and no borough is ever derived from
coordinates.

**It is deliberately not in `city_record`.** That dict is keyed by *seed column name*, the seed has
no region column, and the only two unused columns are `caretaker` and `care_assistant` —
`CityRecordPresentation` renders `caretaker` on the tree profile under the label "Cared for by". A
Queens tree reading "Cared for by Queens" is a visible falsehood shipped to a user, which is worse
than the problem it solves. **A real `trees.region` column is the honest destination and it is a
schema question, so it is named here and not taken.**

## 13. Terms

Unchanged from the survey §2 and now recorded in the seed: both datasets publish `license: null`, so
the operative grant is the NYC.gov Data Mine terms. Redistribution is permitted; an application built
on this data **must notify the City and carry a verbatim disclaimer**. The owner has accepted both
obligations. `seed_meta.inventory_nyc_tree_points_licence` says so in the file, and
`Tools/fetch_nyc_trees.py`'s docstring says neither is discharged by this repo yet.
