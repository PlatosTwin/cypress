# Unnumbered — two more `verify_seed.py` checks are San Francisco-only, plus a named limit of the species-fixture gate

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `fix/seed-tooling`, the branch that repaired checks 1, 12 and 13 of
the same script.

**Check 13 of the three below was fixed on this branch after the owner ruled on it (2026-08-14);
it is kept here as the record of what was measured and what was decided. Checks 2 and 16b are
still failing and are the live items.**

`Tools/verify_seed.py` on `origin/main` reports `34/38 checks passed` against
`Fixtures/seed/cypress-seed.sqlite` — the seed the app actually bundles, unmodified. Two of the four
failures were the checks that branch was scoped to fix. **Checks 2 and 16b are still failing after
it, and with check 13 they are one defect wearing three hats:** the script was written when a seed meant
San Francisco, and the shipped seed has carried two id spaces since #129.

Measured 2026-08-14 against a seed whose `seed_meta` reads
`id_spaces_in_file = sf,us-ca-sj`, `rows_from_sj_street_tree = 52788`, `sj_ship_extent = downtown`.

## 1. Check 2 — "zero trees outside the SF bbox" — 52,788 offending rows

```
  [FAIL] 2. zero trees outside the SF bbox
         52788 offending rows
```

That is exactly `rows_from_sj_street_tree`. The check reads one bounding box, `seed_meta.sf_bbox`,
and holds every tree in the file to it. San Jose's 52,788 shipped rows are 60 km outside it and are
supposed to be. `build_seed.BBOX_BY_ID_SPACE` already carries a box per id space, so the fact the
check needs is in the build; the check is asking a question with only one city's answer in it.

The honest form is per id space: every tree must sit inside the box declared for **its own** space.
That is strictly stronger than what check 2 asks today, because it would also catch a San Jose tree
that had landed in San Francisco's coordinates.

## 2. Check 13 — "neighborhood stamping covers >= 99% of trees" — 26.578%  [FIXED on this branch]

```
  [FAIL] 13. neighborhood stamping covers >= 99% of trees
         52,790 trees (26.578%) have no neighborhood
```

Same 52,788 rows, plus two SF trees that genuinely missed a polygon. The `neighborhoods` table holds
41 rows and all of them are the DataSF SF analysis neighborhoods (`j2bu-swwd`); no San Jose
neighborhood geometry has ever been ingested, so no San Jose tree can be stamped. The check reads as
a coverage regression and is really a statement that a second city arrived without its polygons.

This one was **not** purely a verifier defect — there was a product question inside it. A San Jose
tree with no neighborhood is a tree whose profile cannot render a neighborhood line. **The owner
ruled on 2026-08-14: acceptable for the beta's downtown window, report per id space.** Check 13 now
holds each id space that has geometry to the 99% bar and reports one that has none, rather than
averaging two cities into a number that describes neither:

```
  [PASS] 13. every id space that has neighborhood geometry stamps >= 99% of its trees
         sf: 145,835/145,837 stamped (99.999%); us-ca-sj: 0/52,788 stamped (0.000%)   (41 polygons in the file)
```

Which spaces have geometry is derived from the stamping itself rather than from a column
(`neighborhoods` carries no `id_space`) or from the literal `"sf"`. That opens one hole, which is
closed explicitly: if the polygon join broke entirely, every space would stamp zero, every space
would look like San Jose, and a purely per-space rule would pass a wholly broken file. The file still
carrying polygons is what makes that a contradiction, and it is asserted as one.

San Jose still has no neighborhood geometry. The ruling makes that acceptable to ship; it does not
make it invisible, and the 0.000% line is printed on every run.

## 3. `validate_species.py` rule 0 cannot yet tell a partial corpus from a complete one

Not a `verify_seed` check, and not a defect in what shipped on this branch — a **named limit** of it,
recorded here because the next round needs it and because the failure it produces is silent.

Rule 0 decides whether a species fixture may be validated against a seed by asking which inventory
that seed is a corpus of, per id space, derived as the inventory contributing the most rows within
the space. That answers *"which inventory dominates this space"*. It does **not** answer *"is this
inventory's corpus complete here"*, and the two come apart for a partial ingest of a city that has
only one inventory — a borough-scoped pack is the obvious candidate. Such a space's only inventory
is trivially its primary, so the gate opens and every species the partial ingest did not reach
reports as fixture drift.

Measured 2026-08-14, on a seed built `--source datasf` with 300,000 NYC **tree** rows added under
`nyc_tree_points` in id space `us-ny-nyc` and **no NYC species rows at all**:

```
seed corpora: sf -> 'sf_datasf', us-ny-nyc -> 'nyc_tree_points'
10391 checks run
503 FAILURES:
```

decomposing as:

```
 503 species_uuid <uuid> is not in the seed database species table
   0 common_name does not match the seed row
   0 scientific_name does not match the seed row
```

**Write the decomposition down, because it is the whole finding.** All-absences / zero-common_name /
zero-scientific_name is character-for-character the wrong-corpus signature — the same shape as the
original 84 and the 586 that rule 0 was built to refuse. Here rule 0 *accepts* the run, so those 503
arrive looking exactly like fixture drift and there is nothing on screen to say otherwise. A reader
who does not know this signature will go hunting for 503 nonexistent defects. A reader who does can
tell in one glance that the seed, not the fixture, is the wrong side of the comparison.

The real answer is for the seed to record per-inventory completeness: `rows_from_<inventory>` against
that inventory's own published feature count. `seed_meta` carries those counts only ad hoc today —
`trees_source_feature_count` for whichever source was active, `sj_source_feature_count` for San Jose,
no general key — so this is a seed-format change and was deliberately not invented on this branch. It
is on the s17/region round's agenda, alongside the `trees_source` literal below.

## 4. Check 16b — "every tree uuid == uuidv5(NS_TREE, TreeID)" — 52,788 of 198,625 rows disagree

```
  [FAIL] 16b. every tree uuid == uuidv5(NS_TREE, TreeID)
         52788 of 198,625 rows disagree
```

This is the most misleading of the three, because it reads as a failure of the identity guarantee and
is the opposite: it is the identity guarantee working. The check recomputes
`uuid5(NS_TREE, str(external_ref))` — the bare ref. Identity is minted from
`record.identity_seed(ID_SPACES[space])`, which prefixes the space: `sf` is frozen empty (so SF rows
match by coincidence of the prefix being `""`), and `us-ca-sj` declares `us-ca-sj:`. Every San Jose
row therefore "disagrees" with a recomputation that dropped the prefix.

It is the same root cause as check 12 (fixed on this branch): a check keyed on `external_ref` alone
where the schema and the contract are keyed on `(id_space, external_ref)`. Note the same family of
defect was independently found in `build_seed` itself during this round — `seed_meta.trees_source` is
written as one of two San Francisco string literals, so a seed built for any other city misreports
its own provenance to `InventorySource(id:seedMeta:)`. `Tools/validate_species.py` now warns when a
seed's largest inventory is not the one it names, which makes that defect visible; fixing it is
`build_seed`'s job and is not done here. The fix is to recompute
through `inventory_contract`'s own `identity_seed` rather than restating the derivation — the same
argument the file already makes for importing `species_trigrams` instead of copying it, so that a
change to the scheme cannot leave the verifier agreeing with a stale copy of itself.

## Why 2 and 16b were not fixed on that branch

Scope. The branch was chartered on four named defects and these were three more; check 13 was folded
in only because the owner's ruling arrived while the branch was open, and folding the rest in would
have put more untested check rewrites into one review. They are recorded here rather than fixed because
**the failure they produce is the dangerous kind**: a verifier that has been red for a while trains
its readers to skim the failures, and the two real defects on this branch sat in that noise. Whoever
takes this should also decide whether `verify_seed.py` should refuse to run at all on a file whose id
spaces it has no per-space rule for, rather than reporting a confident wrong number.

Item 3 is different in kind: nothing about it is failing, and that is exactly the problem with it.
