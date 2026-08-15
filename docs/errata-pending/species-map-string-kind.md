# Unnumbered — a `species_map` row described the source file's order, and `--sj-extent full` could not build

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge, and rewrites the two citations of
`<errata-pending/species-map-string-kind>` in `Tools/build_seed.py` and
`Tools/test_seed_species_map.py`.

Found by the **PR #85 reviewer** (finding 8, "info, not this PR", 2026-08-15), correctly filed as
pre-existing at `origin/main` and outside that branch's scope. Reproduced here at `8378c17` before
anything was changed. All counts below are from the 2026-07-31 caches.

---

## 1. The crash

```
File "Tools/build_seed.py", line 2076, in build
    conn.executemany(
sqlite3.IntegrityError: CHECK constraint failed:
    species_id IS NULL OR (is_placeholder = 0 AND is_non_taxon = 0)
```

`Tools/build_seed.py --source city --sj-extent full` did not build. Three rows violated the
constraint, all of them San Jose strings:

| qSpecies string | species | rows as empty site | rows as living tree |
|---|---|---|---|
| `Magnolia` | 665 | 2 | 77 |
| `Acer rubrum 'Armstrong'` | 42 | 7 | 32 |
| `Zelkova serrata 'Wireless'` | 659 | 4 | 4 |

Each row claimed a `species_id` **and** `is_placeholder = 1`, which is the one pair the table
forbids.

## 2. Why: a claim about the string, read off one row

`species_map` is keyed on `qspecies_string`, so every column in a row is a claim about the
**string**. `build` accumulated those claims in `qspecies_stats`, and two of them were taken from
whichever record reached the string first:

```python
qs = qspecies_stats.setdefault(
    record.species_text or "",
    {"kind": kind, "confidence": record.species_confidence or 0.0, ...},
)
```

`setdefault` fires once, so `kind` and `confidence` belong to record #1. `species_id`, four lines
below, is set by **any** record that resolves a species. When those disagreed, the row asserted
both.

**San Francisco cannot express the disagreement, which is why this survived from the table's
introduction.** SF's vacancy lives inside the species field itself (`Potential Site ::`), so every
record carrying a given string necessarily agrees on the kind. San Jose publishes `VACANTSITE` and
`NAMESCIENTIFIC` as two independent fields, and `SanJoseStreetTreeAdapter`'s own docstring records
that **611 rows are `VACANTSITE = 'Yes'` and name a real taxon**. The adapter handles those
correctly — it keeps the flag and drops the species — but the row still carries the string, so the
string arrives on both empty sites and living trees. Counting the at-risk rows from the other
direction, through `species_map` rather than through the adapter, gives 611 as well.

**The kind was therefore a property of the file's sort order.** The same three records in the
opposite order build a different row, and at `origin/main` build without crashing.

## 3. The shipping configuration was one row-order away from the same crash

`--sj-extent downtown` is what ships. It builds today, and it does so by luck:

| extent | strings that resolve a species *and* appear on an empty site | of those, crashed |
|---|---|---|
| `none` (San Francisco alone) | 0 | 0 |
| `downtown` (ships) | **21** (43 empty-site rows) | 0 |
| `full` | 112 (611 empty-site rows) | 3 |

For all 21 downtown strings, San Jose's export happens to list a living tree before an empty site.
Nothing holds that in place: it is the publisher's row order, and it changes when they re-export.
The green build was not evidence the code was right — only that the file arrived in a lucky order.

## 4. The fix, and why the precedence is not a tie-break

Every row that carries a string now contributes, and the kind is decided once
(`build_seed.species_map_kind`) by **which field each kind is reached through**:

1. **A string that resolved to a species names a taxon**, whatever any single row said. That is the
   CHECK constraint's own statement, so it comes first.
2. **`not_a_tree` is only ever reached THROUGH the string.** All three sites that return it match
   `NON_TAXON_SPECIES` or `SJ_NON_TREE_SPECIES` and carry basis `STATED_AS_NON_TAXON`. One such row
   is therefore a statement about the string.
3. **`placeholder` is the opposite** — San Jose reaches it from `VACANTSITE`, a field about the
   *site* that says nothing about the string — so it decides the string only when every row agrees.

`confidence` is likewise taken from the rows that **resolved** the string, so a row carrying the
string without resolving it cannot set the confidence of a resolution it took no part in. No string
in any of the three corpora shows two different confidences among its resolving rows, so this is a
defined value and not a vote.

**Rule 3 needs every row to agree, and that is load-bearing.** An earlier draft let any empty-site
row decide, which is the obvious reading and is wrong: it turns `Unknown` — 4,507 living trees
against 6 empty sites — into a vacant-site placeholder, against RULINGS R18 and the adapter's own
`Unknown is a tree whose species is not known`. The data caught it; the reasoning had not.

## 5. What changed in the seed, measured

| | strings | kind changes | confidence changes |
|---|---|---|---|
| `--sj-extent none` | 630 | **0** | **0** |
| `--sj-extent downtown` | 1,012 | 1 (`Stump`) | 0 |
| `--sj-extent full` | 1,245 | 4 | 3 |

**San Francisco alone is untouched, and that is a measurement rather than an argument**: the
`species_map` table built at `origin/main` and the one built with the fix are byte-identical over
all 630 rows, and `Fixtures/sf_species_map.csv` has the same SHA-256 from both. The same comparison
against a tree that does differ reports a difference, so the check is not blind.

The four changes, all San Jose:

- the three crash rows above now carry their species, `is_placeholder = 0`, and the confidence of
  the resolution (0.7, 0.9, 0.9) rather than the empty site's 0.0;
- `Stump` moves from `is_placeholder = 1` to `is_non_taxon = 1`. It is in `SJ_NON_TREE_SPECIES`, so
  it names no taxon on all 1,933 of its rows — including the 1,624 the vacancy flag calls empty.
  The majority of its rows being empty sites does not make the *word* a placeholder.

`''` and `Unknown` are deliberately unchanged: both are trees whose species is not known.

## 6. `--sj-extent full` now builds, and what `verify_seed` still says about it

The build completes (490,716 trees; San Jose's 344,879 is the largest inventory, which is what the
extent exists to make possible). `Tools/verify_seed.py` reports **33/38**, failing checks 1, 2, 12,
13 and 16b. **None is about this change** — every one is the verifier assuming a
San-Francisco-only seed, and each counts exactly the 344,879 San Jose rows:

- **1** row count outside `150,000..260,000`; **2** SF bbox; **13** neighborhood coverage, which
  `build_seed` already documents as expected (E176: there is no San Jose neighborhood layer);
  **16b** tree uuids, which San Jose derives through its own frozen id-space prefix by design.
- **12** `external_ref is unique` reports 137,886 duplicates because it groups by `external_ref`
  alone. The schema's constraint is `UNIQUE (id_space, external_ref)`, and grouped that way the
  count is **0**. The PR #85 reviewer measured the same blindness independently on the shipped seed
  (0 within-space, 17,518 cross-space).

The species_map checks — 4, 6d, 6e — pass. `--sj-extent downtown` verifies at **34/38**, failing 2,
12, 13 and 16b: the same four the PR #85 reviewer measured on the shipped seed, from a different
worktree and a different build.

**These five are recorded, not fixed.** Teaching `verify_seed` about id spaces is a change to what
the verifier means, and it belongs to whoever owns the multi-city verification round.

## 7. The guard

`Tools/test_seed_species_map.py`. Every test builds a real seed from a dozen synthetic San
Jose-shaped rows through the real `build()` and reads the real `species_map` out of it — not the
classifier in isolation, because the defect lived in the aggregation *inside* `build` and a test of
the classifier alone would have gone green while the build still crashed.

Red-proved by restoring `Tools/build_seed.py` to `origin/main` with the test file untouched: 5 of 6
tests fail, three of them with the original `IntegrityError` verbatim, and the two flag tests with
`'Stump' is not filed as naming no taxon` and `'Unknown' is filed as a vacant-site placeholder`.
The sixth — a string carried only by empty sites is still a placeholder — passes in **both** states,
which is what it is for: it is the control against a rule that satisfied the others by emptying the
column.

`test_the_check_that_caught_this_is_in_the_shipped_schema` writes the offending row by hand and
requires SQLite to refuse it, so the constraint the other five lean on is proven live rather than
assumed.

## 8. What adversarial review of the fix added (PR #90, review 4944399783)

Four findings, all taken. The reviewer's own instruments were calibrated against a case whose answer
was already known — a patched dump of main's crashing build, checked row-for-row against the
`downtown` build that does not crash (1,012/1,012) — and the diagnosis was independently
strengthened: **reversing all 344,879 source rows at `origin/main` moves the crash to a different
set of strings** (`Citrus japonica`, `Eucalyptus cinerea`, `Zelkova serrata 'Wireless'`), which is
the order-dependence demonstrated rather than argued.

### 8a. The fix falsified a comment that ships inside the seed

`Stump` becoming `is_non_taxon = 1` created the first counterexample to the `species_map` DDL's own
sentence: *"A tree stands at the site, so it is NOT a placeholder and its status is `alive`."* At
`origin/main` that was true of every `is_non_taxon = 1` string in all three extents — San Francisco
has five, and all five sit on `alive` rows only. After the fix, **240 of `Stump`'s 337 rows are
`vacant_site` at the shipping extent** and 1,624 of 1,933 at `full`.

The comment travels: it is carried verbatim in the built seed's `sqlite_master.sql` and in the
`Fixtures/seed/schema.sql` written beside it, so it reaches every reader of the artifact. Corrected
to say the flag is a claim about the *string* and says nothing about any row's status. **The change
is comment-only** — the DDL with comments stripped is identical to `origin/main`'s, and the same
comparison reports a difference on the raw text, so it is not a blind check. Nothing else moved:
`verify_seed` 6e and `DataGates` both assert only the species side.

This is the shape CLAUDE.md means by "a confident comment is where bugs have survived here", and it
is worth noting that the comment was true when written and was falsified by a change fifteen hundred
lines away.

### 8b. The stated justification was false for 61 rows

The rule's docstring argued that `placeholder` differs from `not_a_tree` because San Jose reaches it
from `VACANTSITE`, a field about the site. True of 76,048 of San Jose's 76,109 placeholder rows —
and **not of 61**, whose basis is `INFERRED_FROM_ABSENT_SPECIES` and which reach `placeholder`
*through the string*, the string being empty.

The value is unaffected and stays `is_placeholder = 0` for `''`. What was wrong was the reasoning the
next author would extend, so the docstring now names those 61 and says why unanimity still wins: an
empty string is the *absence* of content rather than a reading of it, and that basis says the kind is
ours rather than the source's, where `not_a_tree` earns its one-row power by matching the string
against a vocabulary. `''` comes out on the strength of the 229 rows San Jose itself placed in the
ordinary category, against 812 stated-vacant and those 61.

### 8c. A guard with a hole, found by mutation rather than by reading

`return "stub" if "stub" in kinds else "parsed"` → `return "parsed"` left the new suite **13/13
green** while five real rows at `--sj-extent full` silently flipped `is_stub` to 0. The other three
rules each went red under their own mutant, so the suite was otherwise well-aimed; this one branch
had no specimen.

The cause is structural and worth remembering: **San Jose cannot mint a stub** — its adapter passes
`species_is_stub=False` unconditionally — so a San Jose-shaped corpus could never reach that branch,
however many cases it held. The fix is a San Francisco row (`BOTANICAL` null, `COMMON` a single
word) that packs to `:: Magnolia` and takes the stub path. Now red under the same mutant, naming the
flag.

The corpus needed 100 ordinary rows to carry that one stub: the build refuses when the stub path
exceeds 2% of species-bearing rows, and one stub in four rows is 25%.

### 8d. The order test asserted more than the seed promises

It compared the whole row, which includes the integer `species_id` — and integer ids are minted in
encounter order *by design*, as the DDL says in as many words. It passed only because the corpus
minted a single species. The comparison now excludes `species_id` and asserts `species_uuid`
instead, which is the order-independent identity the checked-in mapping files are keyed on, and the
corpus carries two species compared against its own exact reversal. Verified load-bearing:
`species_id` genuinely swaps 3↔4 under that reversal while the uuid holds, so the old assertion
would now fail on a non-defect.

### 8e. The test suite was reaching the network on every build

Not a review finding — surfaced while fixing 8c, when data.sfgov.org returned HTTP 503. `build`
fetches `sf_analysis_neighborhoods.geojson` when it is absent **even without `--fetch`**, so a
synthetic corpus that omitted the file downloaded it on every one of its seven builds. Writing an
empty `FeatureCollection` makes the suite hermetic and takes it from minutes to **0.3 seconds**. A
test that silently depends on a third party is one CI outage away from a red nobody caused.

**No workflow runs `Tools/test_*.py` at all** — observed by the reviewer, being filed separately, and
not fixed here.
