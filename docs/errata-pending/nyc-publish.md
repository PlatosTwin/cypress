# Errata pending — the NYC publish round, phase 1 (2026-08-22)

Unnumbered, per CLAUDE.md. The orchestrator splices these under real numbers at merge and rewrites
any comment that cites this filename.

Everything here was found by **running the pipeline**, not by reading the diff. Three of the five
are things a bare merge of `feat/nyc-ingest` into `main` produces, and two of those are silent.

---

### E??? — `seed_meta.rows_from_sf_city` is a residual, and it absorbed a third city's rows

**Found by `Tools/verify_seed.py` check 1b, on the first full three-city build**, at the very end of
the pipeline this round exists to run:

```
[FAIL] 1b. per-inventory row counts match what seed_meta claims
       sf_city: 133,706 rows, seed_meta says 1,032,349;
       no rows_from_* claim for ['nyc_tree_points']
```

`rows_from_sf_city` was written as `kept - export_vacant_carried - sj_kept` — everything not
attributed to the two inventories that existed when the line was written. New York's **898,643**
rows therefore landed in San Francisco's count, and `rows_from_nyc_tree_points` was never written at
all. Both keys are seed receipts; the app resolves a row's provenance line through the
`inventory_<id>_*` family beside them, and `verify_seed` reads this one to certify a build.

**Severity: a wrong number in a shipped receipt, caught before publish, no corrupt data.** The
`trees.inventory_source` column — what the app actually reads per row — was correct throughout;
what was wrong is the file's own summary of itself. Nothing would have mis-rendered. What would have
happened is that the first published three-city seed carried a receipt claiming San Francisco holds
1,032,349 trees, which is the kind of number a later round quotes.

**The fix is the guard, not the arithmetic.** Correcting the subtraction alone leaves the same trap
for the fourth city. `build_seed` now refuses a build whose `rows_from_*` claims do not name exactly
the inventories `contributing` holds rows from, and do not sum to `rows_kept`. `contributing` is
built from the records actually emitted, so a new city either brings its own key or stops the build
naming itself.

`verify_seed` 1b is deliberately kept and deliberately not made redundant: it reads the **written
file** where the guard reads the **build's own counters**, so the two disagree if the emit dropped
rows — a different failure, and the one 1b is really for.

---

### E??? — `feat/nyc-ingest`'s adapter set neither `region` nor `condition`, so s17's two seams were dead code

PR #108's F6 thread named the first half of this and the review's own reply corrected the PR body's
"the ingest needs no rework" to "the ingest needs a real code change". Both halves are recorded here
because the second was **not** on that list and is silent where the first is loud.

**`region` — loud.** `NYCTreePointAdapter` writes the borough into `raw_json["boroughcode"]` and
never sets `InventoryRecord.region`, with a comment saying a real region column is "the honest
destination and it is a SCHEMA question, so it is named here and not taken." RULING D17 took it. A
bare merge dies in `resolve_region_ids` with all ~898,643 rows named, because `(us-ny-nyc, None)` is
not registered for a space with five regions. **That refusal is the design working** — it is what
forces D18's point-in-polygon assignment to have run on the ~22,995 orphans rather than trusting it.

**`condition` — silent, and this is the one worth the entry.** The same adapter counted the standing
dead into `stats["standing_dead_mapped_to_alive"]` and left `InventoryRecord.condition` unset. After
a bare merge the build **succeeds** and produces:

```
status=alive          41,256
status=vacant_site    12,758
                                <- no dead_reported row at all
```

on a slice of the extract that holds them. s17's entire second half — `InventoryRecord.condition`,
`status_for_record`, `STATUS_FOR_CONDITION`, the `dead_reported` mapping D17 was written for — is
unreachable, and 10,635 standing dead New York trees ship saying the City called them living. The
ingest round's own pending erratum (its item 3) named this and it stayed open across the merge,
because nothing fails when a field is left at its default.

**Both are the same shape**: an adapter written before a seam existed, merged after it was built,
with no check anywhere that the seam is used. A test asserting a record's `region`/`condition` is
what closes it, and this round added both.

---

### E??? — an XCUITest element subscript RAISES on a string that long, and the raise reads as a failed assertion

`app.staticTexts[<the NYC disclaimer>]` — a 341-character sentence — does not answer:

```
NSInternalInconsistencyException: Invalid query - string identifier 'The City of New York
can not vouch for the accuracy or completeness of data provided by this w …'
```

XCTest reports the raise through the enclosing `XCTAssertTrue`, so the failure reads as
`XCTAssertTrue failed: throwing "NSInternalInconsistencyException…"` — i.e. **as the disclaimer
being absent**, on a screen that carries it. A test written this way and never seen red would have
been believed.

`app.staticTexts.matching(NSPredicate(format: "label == %@", …)).firstMatch` asks the same question
and answers it. Same family as `isHittableWithoutRaising` (`CypressUITests/UIWait.swift`): an
XCUITest query that raises is not a query that returned false.

Recorded with it, from the same file's first run: **`IconTextRow` merges its title and subtitle into
one `Button` accessibility label**, so `app.buttons["Cities"]` finds nothing on the You tab and
`app.buttons` matched on a label PREFIX does. Neither fact is written down anywhere else in this
repository.

---

### E??? — a "prefix property" test over a hardcoded chain of id-space sets is vacuous

Recorded because it was written, red-proved, found green, and replaced **inside this round** — the
guard-green-when-the-defect-is-present family, caught by the red-proof discipline rather than by
review.

The first version of `Tools/test_build_seed_status.py`'s new check asserted that a smaller id-space
set's flattening of `REGIONS` is a PREFIX of a larger one's, over the chain
`{sf} → {sf,sj} → {sf,sj,nyc}`. Red-proof: move `us-ny-nyc` to the front of `REGIONS`, which is the
edit a future author most plausibly makes while tidying. **It stayed green** — both the helper and
`build_seed` read `sorted(spaces)` and index `REGIONS` by key, so the dict's own key order reaches
neither. Two other checks in the file went red on that edit and the new line contributed nothing.

The replacement pins what is actually load-bearing: `sf` is `dim_region` rowid **1** and `us-ca-sj`
is rowid **2** *in a full build*, because packs already on readers' devices carry those numbers in
every `trees.region_id`. Red-proved on the two edits that really move them — a new id space sorting
before `sf`, and a second region inserted into `sf` — and both messages name the moved pack.

The general lesson, which is not new here but is newly cheap to state: **a property that holds by
construction of the thing under test is not a test of it.** The question that finds it is "what edit
makes this line, specifically, go red?" — and if the answer is "the same edits another line already
catches", the line is decoration.

---

### E??? — a rebuild today moves San Francisco and San Jose, and the 2026-07-31 extract is not reproducible

Not a defect. A fact about this round's numbers that a reader comparing them to the shipped seed
will otherwise call one.

The shipped s16 seed was built from extracts dated **2026-07-31** and holds 145,837 San Francisco
rows and 52,788 San Jose rows. The raw caches those came from are git-ignored and live outside the
repository, so **that build cannot be reproduced here**. Fetching today gives extracts dated
2026-08-22 and:

| | shipped s16 (2026-07-31) | this round (2026-08-22) | delta |
|---|---:|---:|---:|
| San Francisco | 145,837 | 145,964 | +127 |
| San Jose | 52,788 | 52,775 | −13 |

That is ordinary upstream churn over three weeks, in both directions, and it is why the round's SF
and San Jose objects are **updated** rather than re-published unchanged. It also means R37.2's
byte-identity promise is being kept at the level it actually makes — a new `s17-r2026-08-22-…` path
holding new content, with the old objects untouched — and not at the level of "the same city
republishes the same bytes", which no fetch-based pipeline can promise across three weeks.
