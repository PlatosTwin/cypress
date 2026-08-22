#!/usr/bin/env python3
"""Tests for s17's condition field and the status lookup that reads it.

    python3 Tools/test_build_seed_status.py

The subject is `build_seed.status_for_record`, which replaced the
`STATUS_FOR_KIND` dict, and the `condition` / `condition_text` fields it reads
off `InventoryRecord`.

WHY THIS EXISTS. `STATUS_FOR_KIND` was keyed on `kind` ALONE, so no adapter --
however good its source -- could cause a row to ship as anything but `alive` or
`vacant_site`. NYC Parks publishes `TPCondition`, and 10,635 of its rows are a
`Full` structure in `Dead` condition: a tree still standing over a pavement,
which is exactly what RULINGS R19 defines `trees.status = 'dead_reported'` to
mean. The seed schema could always hold it. The contract could not express it.

Every test states what would have to go wrong for it to fail, and the two that
have a direction are calibrated in both.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from inventory_contract import (  # noqa: E402
    CONDITION_ALIVE,
    CONDITION_DEAD,
    CONDITION_DECLINING,
    CONDITION_REMOVED,
    CONDITIONS,
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    KINDS,
    InventoryRecord,
    KindBasis,
)
from build_seed import (  # noqa: E402
    REGION_ROW_INDEX,
    REGIONS,
    STATUS_FOR_CONDITION,
    TREE_COLUMNS,
    status_for_record,
)

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def record(**kwargs) -> InventoryRecord:
    base = dict(inventory="sf_city", kind=KIND_TREE, kind_basis=KindBasis.STATED_CATEGORY,
                lat=37.7, lon=-122.4)
    base.update(kwargs)
    return InventoryRecord(**base)


# --------------------------------------------------------------------------
# 1. THE REGRESSION GUARD THAT MATTERS MOST: no condition, no movement.
# --------------------------------------------------------------------------
# San Francisco and San Jose publish no condition field at all, so every one of
# their records arrives with `condition=None`. If that case does not map exactly
# where `STATUS_FOR_KIND` mapped it, this round silently rewrites the status of
# 198,625 shipped rows -- which is the thing RULING D17 was careful to say it
# would not do without meaning to.
#
# Fails if: the None case stops reproducing the pre-s17 dict.
PRE_S17_STATUS_FOR_KIND = {
    KIND_TREE: "alive",
    KIND_PLANTING_SITE: "vacant_site",
    KIND_NOT_A_TREE: "alive",
}
for kind in KINDS:
    check(
        status_for_record(kind, None) == PRE_S17_STATUS_FOR_KIND[kind],
        f"a {kind!r} record with no condition became "
        f"{status_for_record(kind, None)!r}, not {PRE_S17_STATUS_FOR_KIND[kind]!r} -- s17 moved "
        f"rows from sources that publish no condition, which it must not",
    )

# --------------------------------------------------------------------------
# 2. A stated condition reaches the seed's own vocabulary.
# --------------------------------------------------------------------------
# Fails if: the lookup stops reading `condition`, i.e. regresses to keying on
# `kind`. Under the old dict every one of these was `alive`.

check(status_for_record(KIND_TREE, CONDITION_DEAD) == "dead_reported",
      "a standing dead tree did not reach `dead_reported`; that is the whole of what the NYC "
      "ingest could not express and what this round exists to make representable")
check(status_for_record(KIND_TREE, CONDITION_DECLINING) == "declining",
      "a declining tree did not reach `declining`")
check(status_for_record(KIND_TREE, CONDITION_ALIVE) == "alive",
      "a stated-alive tree did not reach `alive`")
check(status_for_record(KIND_TREE, CONDITION_REMOVED) == "removed",
      "a removed tree did not reach `removed`")
# The control that separates "reads the condition" from "happens to agree":
# same kind, four conditions, four different answers.
answers = {status_for_record(KIND_TREE, c) for c in CONDITIONS}
check(len(answers) == len(CONDITIONS),
      f"four conditions on one kind produced {len(answers)} distinct statuses ({answers}); "
      f"the lookup is collapsing them, which is the pre-s17 defect")

# A non-taxon record -- a shrub -- can be dead too. It is `not_a_tree` because of
# what it IS, and that says nothing about how it is DOING.
check(status_for_record(KIND_NOT_A_TREE, CONDITION_DEAD) == "dead_reported",
      "a dead shrub was flattened to alive; kind and condition are independent")

# Every status the lookup can produce must be one the seed's CHECK permits.
# Fails if: a condition is added here without a home in `trees.status`.
SEED_STATUS_VOCABULARY = {"alive", "declining", "dead_reported", "removed", "vacant_site"}
produced = {status_for_record(k, c) for k in KINDS for c in (None,) + CONDITIONS
            if not (k == KIND_PLANTING_SITE and c is not None)}
check(produced <= SEED_STATUS_VOCABULARY,
      f"status_for_record can produce {produced - SEED_STATUS_VOCABULARY}, which the seed's "
      f"CHECK constraint on trees.status refuses -- the build would die on its first such row")
check(set(STATUS_FOR_CONDITION.values()) <= SEED_STATUS_VOCABULARY,
      "STATUS_FOR_CONDITION maps onto a status the seed cannot hold")

# --------------------------------------------------------------------------
# 3. The one pair that cannot mean anything is refused, twice.
# --------------------------------------------------------------------------
# An empty planting site has nothing standing in it to be in a condition. The
# contract refuses the pair, and `status_for_record` refuses it again rather
# than being correct only because someone else was careful.
#
# Fails if: either guard is removed. Both are asserted because either alone
# would let the pair through by a path the other does not cover.

problems = record(kind=KIND_PLANTING_SITE, condition=CONDITION_DEAD,
                  condition_text="Dead").validate()
check(any("nothing in it to be in a condition" in p for p in problems),
      f"InventoryRecord.validate accepted a planting site with a condition: {problems}")

raised = False
try:
    status_for_record(KIND_PLANTING_SITE, CONDITION_DEAD)
except ValueError:
    raised = True
check(raised,
      "status_for_record accepted a planting site with a condition; it must refuse the pair "
      "itself, not rely on validate having run")

# And the valid neighbour still passes, which is what makes the check above a
# check rather than a blanket refusal.
check(record(kind=KIND_PLANTING_SITE, scientific_name=None,
             kind_basis=KindBasis.STATED).validate() == [],
      "a planting site with NO condition was rejected; only the pair is forbidden")

# --------------------------------------------------------------------------
# 4. A condition is the source's claim, so the source's words travel with it.
# --------------------------------------------------------------------------
# Fails if: the `condition_text` requirement is dropped. Without it a normalised
# value with no input behind it is an inference wearing a claim's clothes, and
# #94 is the whole reason this contract counts those rather than allowing them.

check(any("condition_text" in p for p in record(condition=CONDITION_DEAD).validate()),
      "a condition with no condition_text was accepted; the source's own words must travel "
      "with the adapter's normalisation of them")
check(record(condition=CONDITION_DEAD, condition_text="Dead").validate() == [],
      "a properly sourced condition was rejected")
check(any("not one of" in p for p in
          record(condition="mostly dead", condition_text="Mostly Dead").validate()),
      "an out-of-vocabulary condition was accepted")
check(any("blank" in p for p in
          record(condition=CONDITION_DEAD, condition_text="   ").validate()),
      "a blank condition_text was accepted; absent must be None, not whitespace")

# --------------------------------------------------------------------------
# 5. The region field's one rule.
# --------------------------------------------------------------------------
# `None` means the id space's sole region and is the ordinary case; a blank
# string is a named region that names nothing.
#
# Fails if: the blank check is dropped, letting `""` reach `resolve_region_ids`
# as a key distinct from `None` -- which would die there with a confusing
# message instead of here with a clear one.

check(record(region=None).validate() == [],
      "a record with no region was rejected; None is how a one-region city is spelled")
check(record(region="Queens").validate() == [],
      "a record naming its region was rejected")
check(any("region is blank" in p for p in record(region="  ").validate()),
      "a blank region was accepted")

# --------------------------------------------------------------------------
# 6. The region placeholder's index is DERIVED, not written twice (F5a)
# --------------------------------------------------------------------------
# Fails if: `REGION_ROW_INDEX` becomes a literal again. It and the INSERT column
# list were two hand-written facts that had to agree, and an off-by-one writes
# region ids into `lat` -- which SQLite accepts silently, both being numbers.

check(TREE_COLUMNS[REGION_ROW_INDEX] == "region_id",
      f"REGION_ROW_INDEX points at {TREE_COLUMNS[REGION_ROW_INDEX]!r}, not 'region_id'")
check(TREE_COLUMNS.count("region_id") == 1,
      "region_id appears more than once in TREE_COLUMNS, so .index() is ambiguous")
check(len(TREE_COLUMNS) == len(set(TREE_COLUMNS)),
      "TREE_COLUMNS holds a duplicate column name")

# --------------------------------------------------------------------------
# 7. dim_region's INSERTION ORDER is load-bearing, on purpose (F5b)
# --------------------------------------------------------------------------
# `dim_region.id` is the table's rowid and it is what `trees.region_id` STORES.
# A rebuild that inserted the same regions in a different order would produce a
# seed with different `region_id` values in every row -- different bytes for the
# same data, which breaks R60's determinism argument (the build_id is a hash of
# the file) and therefore the immutable-path promise built on it.
#
# `build_seed` iterates `spaces`, which is `sorted({...})`, and then REGIONS'
# own declared order within each space. Both halves are pinned here so that
# neither can be "tidied" into something order-independent-looking.
#
# Fails if: REGIONS becomes an unordered container, or a space's regions are
# reordered without someone deciding to.
check(list(REGIONS) == sorted(REGIONS),
      f"REGIONS' top-level keys {list(REGIONS)} are not in sorted order; build_seed iterates "
      f"`sorted(spaces)`, so a reader comparing the two would be misled")
for _space, _entries in REGIONS.items():
    check(isinstance(_entries, list),
          f"REGIONS[{_space!r}] is a {type(_entries).__name__}, not a list -- rowid assignment "
          f"follows this container's iteration order and it must be an ordered one")
    _packs = [e["pack_id"] for e in _entries]
    check(len(_packs) == len(set(_packs)),
          f"REGIONS[{_space!r}] declares a duplicate pack_id: {_packs}")

# The exact order today, written out. Not a tautology: it is the statement a
# future reordering has to be deliberate enough to edit.
check([(s, [e["pack_id"] for e in es]) for s, es in REGIONS.items()]
      == [("sf", ["sf"]), ("us-ca-sj", ["us-ca-sj"])],
      f"REGIONS' declared order changed to "
      f"{[(s, [e['pack_id'] for e in es]) for s, es in REGIONS.items()]}. Every existing seed's "
      f"trees.region_id values were assigned from the old order -- confirm this reordering is "
      f"intended and that the seed is being rebuilt, then update this line.")

# Every registered region carries the three entered facts, with a legal level.
for _space, _entries in REGIONS.items():
    for _e in _entries:
        check(set(_e) == {"pack_id", "display_name", "level", "source_names"},
              f"REGIONS[{_space!r}] entry has keys {sorted(_e)}; the insert reads exactly four")
        check(_e["level"] in ("city", "borough", "extent"),
              f"REGIONS[{_space!r}] declares level {_e['level']!r}")
        check(bool(_e["pack_id"]) and bool(_e["display_name"]),
              f"REGIONS[{_space!r}] has a blank pack_id or display_name")

# --------------------------------------------------------------------------

if FAILURES:
    print(f"{len(FAILURES)} failing check(s):")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    sys.exit(1)
print(f"{PASSED} checks passed, 0 failed")
