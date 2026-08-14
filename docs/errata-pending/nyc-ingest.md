# Errata pending — the NYC ingest round (2026-08-14)

Unnumbered, per CLAUDE.md. The orchestrator splices these under real numbers at merge and rewrites
any comment that cites this filename.

---

### E??? — the seed's species corpus is 731, not 738

`docs/investigations/nyc-street-trees.md` §4 states "the seed's existing 738-species corpus" and
repeats 738 in the next paragraph. Every measurement of `Fixtures/seed/cypress-seed.sqlite` on
2026-08-14 says **731**:

    SELECT count(*) FROM species                          -> 731
    SELECT count(*) FROM species WHERE deleted_at IS NULL -> 731
    SELECT count(DISTINCT scientific_name) FROM species   -> 731
    SELECT value FROM seed_meta WHERE key='species_count' -> 731

`Tools/validate_species.py` also prints `731 species rows` on its first line, so the figure was
available from three independent places at the time the survey was written.

The number matters because the survey used it as the denominator for its "42% new-species rate".
Against 731 the rate is unchanged to the significant figure, so no downstream conclusion moves —
but the corpus size is quoted in briefs, and a brief that says 738 sends the next agent looking for
seven species that do not exist.

---

### E??? — the merged undated share for a whole-city NYC ingest is 85.24%, not ≈86.6%

The same survey's boxed note in §3 predicts that folding NYC into the seed moves the seed-wide
undated share "from **80.78%** to **≈86.6%**". 80.78% is right. 86.6% is not, and it is not a drift
artifact: **the survey's own inputs give 85.24%**.

    (160,440 + 899,094 - 123,798) / (198,625 + 899,094) = 85.24%

Measured against the 2026-08-14 extract and the shipped seed, the answer is the same to two
decimals:

    (160,441 + 774,920) / (198,625 + 898,643) = 85.24%

Per-borough, for the round that re-measures `MapFilter.undatedShareOfSeed`:

| NYC added | merged undated share |
|---|---:|
| nothing (today) | 80.78% |
| Manhattan | 83.28% |
| Bronx | 82.10% |
| Brooklyn | 82.92% |
| Queens | 85.02% |
| Staten Island | 85.28% |
| whole city | 85.24% |

Also: the shipped seed has **160,441** undated rows, not 160,440.

Nothing in `Cypress/Features/Map/MapFilter.swift` was edited by this round.

---

### E??? — `trees.status` already has a value for a standing dead tree; the gap is in the contract, not the schema

The NYC survey §6 lists "whether `trees.status` needs a value between 'alive' and 'vacant_site' for
'dead, not yet removed'" as an open schema question, and a migration round has been scheduled on
that basis.

**`dead_reported` is already that value.** `Cypress/DesignSystem/Components/StatusBadge.swift`
documents it as a tree that "is still standing over a pavement" and explicitly "**not** a second way
of saying `removed`". It has a `TreeStatus` case, a badge, a pin, an entry in the schema's `CHECK`
constraint, and RULINGS **R19** settling how it renders. It reached the app through task #58 / E170.

What actually prevents an NYC standing dead tree from shipping as `dead_reported` is two things,
both in Python and neither a database change:

  * `InventoryRecord` (`Tools/inventory_contract.py`) has no field in which a source can report a
    condition, so no adapter can express one;
  * `build_seed.STATUS_FOR_KIND` is a dict keyed on `kind` **alone** —
    `status = STATUS_FOR_KIND[record.kind]` — so every `KIND_TREE` becomes `alive`.

Consequence for the scheduled round: it is a **contract** change, not a migration. It moves San
Francisco's and San Jose's rows as well as NYC's, which is why the NYC round did not make it.

Meanwhile 10,635 NYC standing dead trees would ship as `alive`. Nothing is lost — `TPStructure` and
`TPCondition` are carried verbatim into `city_record` and the count is in
`seed_meta.nyc_standing_dead_mapped_to_alive` — but the claim is live and named.

---

### E??? — `Forestry Planting Spaces` publishes 6,864 whole-row duplicates

`count(*)` on Socrata `82zj-84is` is 1,091,709; `count(distinct globalid)` is 1,084,845. The 6,864
extra rows are duplicated in **every** column, `OBJECTID` included, so they are one planting space
published twice rather than two spaces sharing an id. Verified across the full extract on
2026-08-14 by comparing every duplicate pair field by field: **zero pairs disagree**.

`GlobalID` is the join key from `Forestry Tree Points`, so this is load-bearing.
`Tools/fetch_nyc_trees.py` drops the duplicates and reports `disagreeing_duplicates`; a nonzero
value there means the key is not a key and is a stop, not a dedup.

Calibration note worth keeping: `count(distinct objectid)` returns **the same** 1,084,845, which
reads like the signature of an approximate `count(distinct)`. It is not — both columns genuinely
repeat, together. The distinction was settled by pulling the actual rows, not by reasoning about it.

---

### E??? — `Tools/validate_species.py` is red on `main`, with 84 failures

Running it on an untouched `origin/main` worktree (commit `63607f1`) with the shipped seed copied in
exits **1** with 84 failures, of the form:

    - Ulmus glabra: species_uuid 4d1f3b24-... is not in the seed database species table
    - Castanea dentata: common_name does not match the seed row (None in the database)

The NYC branch produces **byte-identical** output apart from the seed's file path, so this predates
the round and was not caused by it. Recorded because CLAUDE.md's verification rules make an
already-red gate a hazard: the next agent to run it will not be able to tell its own breakage from
this, and the round after that will be tempted to treat 84 failures as the baseline.

---

### E??? — `Tools/verify_seed.py` checks 1, 2, 13 and 16b are San Francisco-only

A whole-city NYC seed fails four checks. A **San Jose** control build — the shipped, blessed
configuration, no NYC in it at all — fails three of the same four:

| check | NYC | San Jose control | cause |
|---|---|---|---|
| 1. row count in 150,000..260,000 | FAIL | pass | a hardcoded SF-era range |
| 2. zero trees outside the SF bbox | FAIL | **FAIL** | reads `seed_meta.sf_bbox`; every non-SF row is outside it |
| 13. neighborhood stamping ≥ 99% | FAIL | **FAIL** | `neighborhoods` holds SF's 41 analysis neighborhoods only |
| 16b. uuid == uuid5(NS_TREE, TreeID) | FAIL | **FAIL** | recomputes without the id-space prefix |
| 12. external_ref is unique | pass | **FAIL** | checks `external_ref` globally, ignoring `id_space` — see below |

So checks 2, 13 and 16b have been failing for the second city since #129 and are a pre-existing gap.
NYC's only *new* failure is check 1's row-count range.

**Check 12 is the sharpest of the five and is worth stating exactly.** On the San Jose control it
reports 27,714 duplicated refs. Those are not San Jose ids colliding with each other — every one is
a San Francisco `TreeID` colliding with a San Jose `FACILITYID`, both being small integers:

    SELECT external_ref, count(*) c, group_concat(DISTINCT id_space)
    FROM trees GROUP BY 1 HAVING c > 1     ->  ('99987', 2, 'sf,us-ca-sj'), ...

    SELECT count(*) FROM (
      SELECT id_space, external_ref FROM trees GROUP BY 1,2 HAVING count(*) > 1
    )                                      ->  0

**Zero duplicate `(id_space, external_ref)` pairs.** That is the seed's own `UNIQUE` constraint and
it holds. Check 12 asserts something stricter that the schema never promised, and that
`inventory_contract.py`'s whole id-space design exists to make unnecessary — two cities' numbering
*may* collide, which is why the uuid seed string carries a prefix.

NYC happens to pass check 12 only because its `GlobalID`s are UUIDs and cannot collide with a small
integer. A fourth city numbering on integers would fail it on day one while being perfectly correct.

The verifier is therefore not currently a gate for any city but San Francisco, and its exit code
cannot be used to accept or reject a multi-city seed until it learns about id spaces.

---

### E??? — three NYC `PlantedDate` values are in the future, and one trips `verify_seed.py`

Across all 1,121,106 tree points, `PlantedDate` is non-null on 136,730 and exactly three are in the
future; none is before 1800.

| PlantedDate | TPStructure | CreatedDate | reading |
|---|---|---|---|
| 2030-11-02 | Full | 2020-11-04 | 2020 typed as 2030 |
| 2108-11-23 | Full | 2018-11-27 | 2018 typed as 2108 |
| 2108-11-23 | Stump | 2018-11-27 | the same error, twice |

`verify_seed.py` check 14 bounds `planted_year` at 2100, so only the 2108 rows trip it; the 2030 row
would have shipped silently. `NYCTreePointAdapter.parse_planted_date` now clamps to
`1800..horizon_year` and counts rejections in `nyc_planted_date_beyond_horizon`.

They are **not** corrected to the year their `CreatedDate` implies, obvious though it is: an adapter
may resolve a source's sentinels and may not invent its facts.

---

### E??? — `build_seed.py` rewrites the checked-in species maps as a side effect

Any run of `Tools/build_seed.py` regenerates `Fixtures/<space>_species_map.csv` for every id space
that contributed rows. So a build made purely to *measure* something leaves the working tree dirty
in files nobody meant to change, and the content depends on flags that have nothing to do with the
map's purpose.

Concretely, on this round: seven trial builds run with `--source datasf` rewrote
`Fixtures/sf_species_map.csv` with 375 insertions and 419 deletions, because the shipped seed is
built with `--source city` and the two inventories spell their species differently. The same runs
rewrote `Fixtures/nyc_species_map.csv` against the trial build's own 569-species corpus rather than
the shipped 731, silently replacing an artifact that had been generated deliberately and reviewed.

Both were restored from `HEAD` and neither change was committed. Recorded because the trap is quiet:
`git status` after a measurement build shows plausible-looking churn in a checked-in data file, and
committing it would corrupt San Francisco's map with a build flag's side effect.

Worth considering for the round that owns `build_seed.py`: write the map only under an explicit
flag, or write it beside the seed rather than into `Fixtures/`.

---

### E??? — an ITIS client that decodes as UTF-8 reports valid names as network errors

The species work for RULING D20 checked 268 names against ITIS
(`https://www.itis.gov/ITISWebService/jsonservice/`). Ten came back as errors that looked exactly
like transient network failures and survived a retry:

    Crataegus            'utf-8' codec can't decode byte 0xfc in position 20781
    Amelanchier          'utf-8' codec can't decode byte 0xe9 in position 18583
    Tsuga canadensis     'utf-8' codec can't decode byte 0xe8 in position 105

They are not network errors and they are not bad names. **ITIS serves ISO-8859-1**, and its taxonomic
author strings are full of accented characters (`Michx.`, `Muhl. ex Willd.`, `Dum.Cours.`). A client
doing `json.load(response)` — which assumes UTF-8 — raises on exactly those records and on no others.

The tell was that a retry did not clear them and that they clustered on genera with long author
lists. Decoding UTF-8 first and falling back to ISO-8859-1 resolved all ten, and the answers changed
the round's numbers: the residual went from "141 accepted / 10 error" to **150 accepted**.

Recorded because the failure mode is generic to this project's habit of querying public taxonomic
APIs, and because it is indistinguishable from a flaky network at the call site. It is also a clean
instance of the calibration rule: the instrument was wrong, and the wrongness was reported as data.

---

### E??? — RULING D20's 90% species gate is not reachable for NYC by mapping

Recorded as a standing fact rather than a defect, because the next round will meet it again.

D20 requires mapped-species coverage ≥ 90% of rows before a first NYC publish. The measured ceiling
is **85.99%** (772,785 of 898,643), reached with a five-rule cited cascade. The remaining 35,993 rows
cannot be mapped without asserting a synonymy no authority supports:

  * 150 values / 106,956 rows are **accepted** names in ITIS that the corpus does not carry;
  * 11 values / 470 rows are synonyms — of taxa the corpus **also** lacks;
  * 107 values / 14,888 rows are cultivars, which the ICNCP governs and ITIS does not index.

The cause is structural, not sloppy: the corpus was built from San Francisco and San Jose, and NYC's
street trees are an Eastern-seaboard flora. Green ash is not white ash.

The gap closes by ADDING species to the corpus, not by mapping — which is what the build already does
for an unmapped string. So the gate as written measures "how much of NYC overlaps California", and a
number that can only be moved by curating ~270 new species is a curation-round dependency, not an
ingest-round one.
