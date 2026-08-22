# The case-normalisation pass went one column out of step when `region_id` landed

**Status: the published s17 seed carries the defect. It cannot be cleared by any change in this
repository — it needs a seed rebuild and a republish.**

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

## What is in the published file

Seed `4f6ebaaa` (2026-08-22), the one `Tools/fetch_seed.sh` resolves and CI's `unit` job builds
against, holds three unfolded case-variant pairs:

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

`Tools/build_seed.py` now derives `column_index` from `TREE_COLUMNS`, so the next build folds these.

**The gate was not touched.** `DataGates.seedContract`'s #95 assertion is correct about the
published file and stays red until a rebuild replaces it. Silencing it — an allowlist, a widened
predicate, a skip keyed on the id space — would have removed the only thing that noticed, and the
finding here is that a fold reporting `0` looked identical to a fold with nothing to do.

## What still needs deciding

A rebuild and republish is a publish round, with a migration author named for it, and it is not
this round's to make. Until then CI's `unit` job cannot be fully green on the published seed. The
open question is whether the seed contract should also assert that
`seed_meta.case_normalised_values` is *plausible* rather than merely present — a fold that reports
zero over a corpus of a million rows drawn from three publishers is itself suspicious, and that
assertion would have caught this at build time rather than one publish later.
