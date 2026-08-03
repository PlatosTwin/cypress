### E?? — E206's replacement figure was itself off by one, and three shipped comments copied it (task #122)

*UNNUMBERED — the orchestrator splices the number at merge.*

*Found on branch `p1/round13-a`, 2026-08-03, iPhone 16 Pro Max `DE8E11AE-…`, while auditing #122's
list of quoted seed figures. Amends **E206**, which is otherwise correct and whose vacant-site
correction (24,200 / 12.2 %) re-measures exactly as written.*

---

#### The claim

E206's *"Related stale figures found in code while doing #178"* corrected two comments that had been
quoting San-Francisco-only numbers past San Jose's landing, and gave the replacements:

> `TreeQueries.Narrowing.predicate` … The true figures are **160,440 of 198,625**.
> `MapViewport.plantedYears` … The true figures are **198,625 rows, of which 38,185 (19.22 %)** carry
> a planting year.

The row total and the percentage are right. **The two counts are each off by one.**

#### The count

Against the shipped seed (`Cypress/Resources/cypress-seed.sqlite`, 108,003,328 bytes,
sha256 `d3e3d229…`, sqlite 3.51.0), seven formulations, all agreeing:

```
SELECT COUNT(planted_year)                     FROM trees;  -- 38,184
SELECT SUM(planted_year IS NOT NULL)           FROM trees;  -- 38,184
SELECT COUNT(*) FROM trees WHERE planted_year IS NOT NULL;  -- 38,184
SELECT COUNT(*) - SUM(planted_year IS NULL)    FROM trees;  -- 38,184
SELECT COUNT(*) FROM trees WHERE planted_year IS NOT NULL
                             AND deleted_at IS NULL;        -- 38,184
SELECT COUNT(*) FROM trees WHERE planted_on IS NOT NULL;    -- 38,184
SELECT COUNT(*) FROM trees WHERE planted_year IS NULL;      -- 160,441  (198,625 − 38,184)
```

Split by id space, which is what settles it:

| id space | rows | dated | share |
|---|---|---|---|
| `sf` | 145,837 | **37,962** | 26.03 % |
| `us-ca-sj` | 52,788 | **222** | 0.42 % |
| | 198,625 | **38,184** | 19.22 % |

37,962 is E175's own San Francisco figure and 222 is E176's own San Jose figure. **They sum to
38,184.** E206's 38,185 contradicts the two entries it was reconciling, and its 160,440 is the same
error carried through the subtraction. The decade table in `MapFilter.swift` carried it too, as
`2020s 3,070` where the seed holds **3,069** — SF's 2,847 plus San Jose's 222, again per E175/E176.

#### Where it reached

Three shipped comments and one distribution table, all written or amended from E206:

- `Cypress/Features/Map/MapFilter.swift` — header (`38,185`), decade table (`3,070`), and the R41
  note (`160,440`).
- `Cypress/Data/API/CypressAPI.swift`, `MapViewport.plantedYears` — `38,185 (19.22 %)`.
- `Cypress/Data/Store/TreeQueries.swift`, `Narrowing.predicate` — `160,440`.

Every one of them announced itself as measured: *"Counted against the shipped seed, not assumed"*,
*"Re-measured against the shipped two-city seed rather than inherited"*. They were copied from a
document. That is the confident-comment failure mode with the word "measured" written into it, and
it is why CLAUDE.md's rule is about comments rather than about carelessness.

#### Why the existing test did not catch it

It could not, by design, and the design was defended in E206 itself:

> The ranges are deliberately loose (e.g. vacant sites between 8 % and 18 %). A tight pin on a number
> this branch happened to measure would be a false red one city later, which is the failure this
> whole entry is about.

`MapFilterTests.plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor` asserts `0.75 < undated share
< 0.85`. A one-row error moves that share by 0.0000050. **The reasoning was right and the conclusion
was too weak.** A loose range is the correct guard against a *new city*; it is no guard at all
against arithmetic.

#### What was done

The figure is now pinned exactly, **keyed by corpus**, which is the shape E175 established and
E206 did not reach for: `SeedCorpus.datedTrees` — 37,962 for `city`, 38,184 for `cityWithSanJose`,
`nil` for `dataSF` because this repo ships no copy of that seed and a number there would be
remembered rather than counted. A keyed constant does not false-red on a new city, because a new
city is a new corpus entry and the red is the reminder to write one. The range assertions stay
where they are; they answer a different question.

The four prose sites now state a ratio ("about one row in five", "four rows in five"), name the test
that counts it, and carry **D16**'s sentence: under a merged inventory this share is a weighted
average over whichever cities are installed, not a property of this app. That sentence is worth more
than any of the numbers it replaced, and unlike them it cannot go stale.

Red-proved by setting `datedTrees` to E206's own 38,185:

```
MapFilterTests.swift:321:13: Expectation failed: (dated → 38184) == (expected → 38185)
↳ 38184 rows carry a planting year; the sf_city corpus is pinned at 38185. Count it before
  repinning — do not carry the figure across from a document, which is how E206's 38,185 reached
  three comments (E175, E176, #122).
```

#### What is not changed

E206's headline correction. `SELECT COUNT(*), SUM(status='vacant_site') FROM trees` re-measures as
**24,200 of 198,625 (12.18 %)** on this branch, exactly as E206 recorded, and every argument built on
it stands. This entry amends one paragraph of a long and otherwise sound entry.

The pattern worth naming is not that E206 slipped. It is that the *corrections* are where the slips
land: E175's heading was amended within a day of being written, and E206's replacement figures were
wrong the moment they were written. Both were prose. The constants beside them — E175's
`undatedShareOfSeed`, `SeedCorpus`' counts — have never been wrong, because a wrong one does not
survive a build. That is the whole of #122's finding, and the ratio the ticket asked for is its
measure: on this branch, one figure asserted for every prose figure removed rather than reworded.
