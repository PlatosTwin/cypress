### E189's correction list missed E33, so "every `seasonal` in the shipped seed is empty" is still on the books — and the sentence #261 actually needs is a narrower one

Ticket #261, found while confirming the second defect Candidate A repairs.

E189 established that the seed carries seasonal data and listed what to correct at merge: R23, R23.1,
R31, E183 §5 and `SeasonalWindowTests`' header. **E33 was not on that list and still ends with the
sentence E189 refuted:**

> This is latent, not live: every `seasonal` in the shipped seed is empty, so every deciduous species
> takes the fallback today.

`SeasonalWindowTests`' header was duly corrected and now cites E189. E33 was not, so an agent reading
E33 — which is the natural place to read, because E33 is the entry about `leafOnMonths` — still gets
the refuted sentence, with nothing pointing at E189. The pending #260 entry took it from E33 and
repeated it, which is how it reached ticket #261's brief.

#### The measurement, against the seed this build ships

`Cypress/Resources/cypress-seed.sqlite` and `Fixtures/seed/cypress-seed.sqlite` are identical
(sha256 `c9a440b2…`, md5 `de7b55a957ef15439052af64305cfdbf`). This is **not** E189's binary — E189
measured md5 `815ed501445e6f188cc7898e6b2901cb` — and the species count has moved with a re-ingest,
so E189's own figures need reading with that in mind:

| | E189's seed | this seed |
|---|---|---|
| species rows | 569 | **731** |
| `seasonal <> '{}'` | 511 | **511** |
| non-empty `bloom_months` | 11 | **11** |

The seasonal data itself did not change; 162 species rows arrived carrying `{}`. E189's denominator
is stale, its numerators are not, and nothing it concluded about `In bloom` is disturbed.

Two figures E189 did not report, and #261 depends on the second:

- **13 rows carry at least one non-empty array** (9 evergreen, 3 deciduous, 1 semi-deciduous). Eleven
  carry `bloom_months`, **eight** carry `fruit_months` — seven rows carry both, which is why 11 + 8 + 1
  does not sum to 13 — and `Ginkgo biloba` carries `fall_color_months` `[11, 12]`. So "511 carry a
  non-empty `seasonal` JSON" means 511 rows whose JSON object has *keys*, not 511 rows with a calendar
  in them — a distinction worth stating, since the two readings differ by a factor of forty.

  The `fruit_months` figure first went into this entry as **three**, and how it went wrong is this
  document's own subject one level down: it was counted by eye off a `GROUP BY seasonal` listing
  instead of derived by a predicate, and seven of the eight sat in rows that also carried
  `bloom_months` and read as bloom rows. Re-derived with
  `json_array_length(COALESCE(json_extract(seasonal,'$.fruit_months'),'[]')) > 0`, which returns 8:
  `Prunus cerasifera`, `Pittosporum undulatum`, `Acacia melanoxylon`, `Metrosideros excelsa`, `Olea
  europaea`, `Myoporum laetum`, `Callistemon citrinus`, `Ligustrum lucidum`. A count read off a
  listing is not a measurement.
- **`new_growth_months` is empty on all 731 rows.** Zero exceptions, Ginkgo included.

#### The sentence that should replace E33's

`Species.leafOnMonths` derives a deciduous window from `MonthRange.spanning(newGrowthMonths)` **and**
`MonthRange.spanning(fallColorMonths)`, falling back to April–October if *either* is absent. Because
no row authors `new_growth_months`, the `guard` fails for every deciduous species and all 181 of them
take the fallback today. E33's conclusion is therefore correct and its stated reason is not. The
accurate form:

> No species in the shipped seed authors `new_growth_months`, so every deciduous species takes the
> April–October fallback today, and E33's wrapping-fall bug lands the moment one does.

#### What that means for #261's row 3, stated no more strongly than the seed supports

Draft v0's row 3 read "Noticeable thinning or discoloration", and `Vitality.isRatingPermitted` gates
on leaf-on/leaf-off and nothing else. Two separate claims follow, and only the first is unconditional:

- **By construction, for any species that authors both seasons.** `leafOnMonths` closes the window at
  `fallColor.end`, so the entire authored fall-color season is inside leaf-on and therefore ratable.
  That is not a bug in the derivation — it is what E33 established the window should be, and narrowing
  the gate to exclude fall color would suppress the rubric for trees that are in leaf, which is what
  E33 exists to prevent. Any species with an authored calendar is exposed the day it lands.
- **Today, through the fallback only, and the seed does not author the botany.** All 181 deciduous
  species take April–October. The single species with an authored fall-color calendar, `Ginkgo
  biloba`, has it at `[11, 12]` — *outside* the fallback — so the app suppresses vitality for Ginkgo
  in exactly the two months its calendar says it is discoloring, and **no row in the shipped seed is
  simultaneously ratable and inside an authored fall-color window.** Saying the defect is "live today"
  therefore rests on October being fall-color season for deciduous street trees in San Francisco,
  which is real-world botany this seed does not state and this project must not invent (DECISIONS
  constraint 15).

The copy repair stands on the first bullet alone, and on something neither bullet needs: a rater
cannot tell seasonal color from stress color by looking, and the anchor asked them to. E33 did not
create any of this — it repaired a *different* bug in the same derivation, and fall color sitting
inside the leaf-on window is the intended behavior, not the defect.

#### Calibration

Every count above is from a `sqlite3` predicate checked against an answer known in advance before it
was believed. `SELECT count(*) FROM species` returns 731, which the candidates document measured
independently. `seasonal = '{}'` (220) plus `seasonal <> '{}'` (511) sums to 731, so the two
predicates partition the table. The `json_array_length` predicate on `bloom_months` returns 11,
matching E189's independent figure, and the same predicate on `new_growth_months` returns 0, matching
the `guard`'s observed behavior.

The one figure here that was **not** derived that way was wrong, which is the calibration lesson
rather than an aside: `fruit_months` was eyeballed off a `GROUP BY` and reported as three against a
true eight. The rule that catches it is the same rule the rest of this entry applies — a listing is
not a count, and a predicate is.
