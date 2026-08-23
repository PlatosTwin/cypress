# The case-normalisation pass went one column out of step when `region_id` landed

**Status: settled. The first s17 artifact (`4f6ebaaa`) shipped with the defect; the corrective
rebuild (`ac7b1ccc`) replaced it on the bucket on 2026-08-22 and CI is green against it. Both files
remain reachable at their own immutable `seed/<build_id>/` paths, so the comparison below can still
be re-run by anyone who wants to check it.**

`Tools/build_seed.py`'s #95 pass folds case-variant spellings in the five columns the app compares
against a string literal (`NORMALISED_SEED_COLUMNS`). It rewrites those values in place inside the
already-built `tree_rows`, so it needs each column's index in a row.

It computed those indices from **its own hand-written copy of the row layout** rather than from
`TREE_COLUMNS`. When the s17 pass inserted `region_id` at index 6, that copy was not updated, so
every index from 6 onward was one too small:

| column           | pass used | actual | what it actually read |
|------------------|----------:|-------:|-----------------------|
| `site_type`      |         9 |     10 | `address`             |
| `legal_status`   |        19 |     20 | `verification_state`  |
| `caretaker`      |        20 |     21 | `legal_status`        |
| `care_assistant` |        21 |     22 | `caretaker`           |
| `plant_type`     |        22 |     23 | `care_assistant`      |

The fold therefore looked its replacement map up against the wrong column, matched almost nothing,
and rewrote nothing. It did not crash and it did not warn: it wrote
`seed_meta.case_normalised_values = 0`, which reads exactly like "there was nothing to fold".

**The bitter part is that the same commit's own comment says this cannot happen.** `TREE_COLUMNS`
was introduced precisely to stop a hand-written index drifting — "there is ONE list and the index
is DERIVED from it, so they cannot disagree… `emit` cannot put the placeholder somewhere the
INSERT does not expect it, because there is no second place to put it." There was a second place.
It was thirty lines further down, in a pass whose job is also to index into a row, and bringing
`flush` onto the derived list did not bring it along.

## What was in the defective file

Seed `4f6ebaaa` (2026-08-22) — which `Tools/fetch_seed.sh` resolved, and CI's `unit` job built
against, for about nine hours — held three unfolded case-variant pairs:

- `plant_type`: `Tree` ×145,797 and `tree` ×1, both in `sf`
- `plant_type`: `Park Strip` ×15,894 and `Park strip` ×1, both in `us-ca-sj`
- `site_type`: `Park Strip` ×15,894 and `Park strip` ×1, both in `us-ca-sj`

**None of them is New York's.** They are San Francisco's and San Jose's, which is worth saying
because the same publish added a third city and it is the obvious thing to blame. The s17 publish
re-read both California layers on 2026-08-22, and those refreshed extracts reintroduced exactly the
kind of variant the #95 pass exists to remove.

The product consequence is #95's original one: `WHERE plant_type = 'Tree'` drops the one row spelled
`tree`, and a reader has to remember to case-fold. One row per pair, so it is small — but it is the
defect the gate was written for, and the gate caught it.

## What was done, and what was not

`Tools/build_seed.py` now derives `column_index` from `TREE_COLUMNS`.

**The gate was not touched.** `DataGates.seedContract`'s #95 assertion was correct about the
published file and stayed red until the corrected artifact replaced it. Silencing it — an allowlist,
a widened predicate, a skip keyed on the id space — would have removed the only thing that noticed,
and the finding here is that a fold reporting `0` looked identical to a fold with nothing to do.

## The corrective rebuild, and what it proves

Rebuilt from the **same cached extracts** the s17 publish used, so the index fix is the only
difference. New build id **`ac7b1ccc`**, sha256 `ac7b1cccd7de413c…`, 706,535,424 bytes.

The builder's own log is the clearest statement of both the defect and the repair:

    s17 (4f6ebaaa):  #95 plant_type: folded 2 case-variant spelling(s) over 0 rows
                     #95 site_type:  folded 1 case-variant spelling(s) over 0 rows
    corrected:       #95 plant_type: folded 2 case-variant spelling(s) over 2 rows
                     #95 site_type:  folded 1 case-variant spelling(s) over 1 rows

It had always *found* the variants — `case_counts` was right all along — and rewrote none of them.

**No row count moves.** All 30 counts compared (per id space, per status, every city column, the
R*Tree, `species_assertions`, the D18 invariants) are identical between the two files, and
`case_normalised_values` 0 → 3 is the *only* differing `seed_meta` key. The only counts that shift
are `COUNT(DISTINCT plant_type)` 18 → 16 and `COUNT(DISTINCT site_type)` 44 → 43 — the folded
variants merging into their canonical spellings, which is the repair itself. Nothing in the app or
the suite reads either.

`Tools/verify_seed.py` returns byte-identical results on the corrected artifact and the published
one (fused 42/44; `sf` pack 44/44; the six non-SF packs 41/44). **Those shortfalls are pre-existing
and were confirmed against the published file as a control** — three checks in that script still
assume San Francisco is the only id space (`zero trees outside the SF bbox`, `every tree uuid ==
uuidv5(NS_TREE, TreeID)`, and the R*Tree superset probe that uses the SF window). That is the same
family as the two gates this round extended in `DataGates`, and it is the third instance: a
San-Francisco-shaped assumption left behind by a multi-city seed. Worth its own round.

## What stops it recurring

Two mechanisms, deliberately different, because the first one alone already failed once: the index
is derived from `TREE_COLUMNS`, so there is no second copy to drift — and `TREE_COLUMNS` was
introduced by the very pass that broke this, with a comment saying the index "cannot disagree", so
derivation is necessary and not sufficient. The fold is therefore also extracted as
`build_seed.normalise_case` and pinned by `Tools/test_build_seed_status.py`, which drives it over a
specimen whose `address` column holds the exact string a one-column slip would rewrite. Re-inserting
the old hand-written list turns that harness red on five checks, including the log line reading
`over 0 rows` — the defect's own signature.

One thing worth knowing about that guard: **no workflow runs `Tools/test_*.py`.** The only Python CI
invokes are `whats_new.py` and `appstore_connect.py`, so this is a local convention guard rather
than a gate. Wiring the twelve sibling harnesses into CI is its own round.

## What still needs deciding

Whether the seed contract should also assert that `seed_meta.case_normalised_values` is *plausible*
rather than merely present — a fold reporting zero over a corpus of a million rows drawn from three
publishers is itself suspicious, and that assertion would have caught this at build time rather than
one publish later. The harness above catches the index drift specifically; it would not catch a
different mechanism producing the same silent zero.
