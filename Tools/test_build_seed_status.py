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

import contextlib
import io
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
    NORMALISED_SEED_COLUMNS,
    REGION_ROW_INDEX,
    REGIONS,
    STATUS_FOR_CONDITION,
    TREE_COLUMNS,
    canonical_case_map,
    check_rows_from,
    normalise_case,
    resolve_region_ids,
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
#
# UPDATED BY THE NYC PUBLISH ROUND, and the reason it was safe to update is not
# "the round needed it". `build_seed` iterates `sorted(spaces)` -- the spaces
# THIS BUILD contributes -- and `us-ny-nyc` sorts after both existing keys, so
# appending it cannot move a rowid any existing seed already assigned:
#
#   SF only        -> sf=1                        (unchanged)
#   SF + SJ        -> sf=1, us-ca-sj=2            (unchanged)
#   SF + SJ + NYC  -> sf=1, us-ca-sj=2, then the five boroughs 3..7
#
# The check below turns that argument into a measurement rather than leaving it
# as reasoning in a comment. An INSERTION anywhere but the end, or a reorder
# within a space, is still the breaking edit this line exists to catch.
check([(s, [e["pack_id"] for e in es]) for s, es in REGIONS.items()]
      == [("sf", ["sf"]),
          ("us-ca-sj", ["us-ca-sj"]),
          ("us-ny-nyc", ["us-ny-nyc-manhattan", "us-ny-nyc-brooklyn", "us-ny-nyc-queens",
                         "us-ny-nyc-bronx", "us-ny-nyc-staten-island"])],
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
# 7b. Adding a city must not renumber the cities already published (F5b)
# --------------------------------------------------------------------------
# The rowid a region gets is its 1-based position in the flattening of REGIONS
# over `sorted(spaces)` -- `build_seed` INSERTs in exactly that order and takes
# `cur.lastrowid`. So the whole of "a new space did not move an old region's
# rowid" is the statement that a SMALLER space set's flattening is a PREFIX of a
# LARGER one's.
#
# Checked against REGIONS itself rather than against a copied-out list of ids:
# a list of expected ids would have to be edited by the same hand that broke the
# order, and would then agree with it.
#
# FIRST DRAFT OF THIS CHECK WAS VACUOUS AND IS RECORDED SO IT IS NOT REWRITTEN.
# It asserted that a smaller space set's flattening is a PREFIX of a larger
# one's, over the hardcoded chain {sf} -> {sf,sj} -> {sf,sj,nyc}. Red-proved by
# moving `us-ny-nyc` to the front of REGIONS -- and it stayed GREEN, because
# both this helper and `build_seed` read `sorted(spaces)` and index REGIONS by
# key, so the dict's own key order cannot reach either of them. Two other checks
# went red on that edit and the prefix line contributed nothing. What is below
# is the statement that actually breaks.


def _packs_in_rowid_order(spaces):
    """The pack ids in the order `build_seed` INSERTs them for these spaces."""
    return [e["pack_id"] for s in sorted(spaces) for e in REGIONS[s]]


# Determinism: the same input twice gives the same answer, and it is not the
# accident of a set's iteration order. (F5b asked for exactly this.)
check(_packs_in_rowid_order({"sf", "us-ca-sj", "us-ny-nyc"})
      == _packs_in_rowid_order({"us-ny-nyc", "us-ca-sj", "sf"}),
      "the rowid order depends on how the space set was spelled, not on sorting it")

# THE PUBLISHED ROWIDS, PINNED AS THE FACTS THEY ARE. `sf` and `us-ca-sj` are
# already inside downloaded packs on readers' devices as `dim_region.id` 1 and 2
# with `trees.region_id` pointing at them. Those two numbers are therefore not
# free any more, in ANY build, and this is the line that says so.
#
# It is not the prefix line rewritten: it fails on the two edits that would
# really move them -- a new id space sorting before `sf`, and a second region
# inserted into `sf` -- neither of which the prefix form over a hardcoded chain
# could see. Red-proved both ways, messages verbatim in the PR body.
_full = _packs_in_rowid_order(set(REGIONS))
for _pack, _rowid in (("sf", 1), ("us-ca-sj", 2)):
    check(_pack in _full and _full.index(_pack) + 1 == _rowid,
          f"{_pack!r} is registered at dim_region rowid "
          f"{_full.index(_pack) + 1 if _pack in _full else 'nowhere'}, not {_rowid}. Packs "
          f"already downloaded carry {_rowid} in every trees.region_id; a full build "
          f"registering it elsewhere republishes that city with different bytes for the "
          f"same data. Registration order is {_full}.")

# --------------------------------------------------------------------------
# 8. `check_rows_from` -- the round's most important new guard (review N1)
# --------------------------------------------------------------------------
# It was written INLINE in `build()`, which made a full three-city build against
# a scratch repo root the only way to exercise it -- the reviewer had to stand
# one up to red-prove it, and deleting the guard would have gone unnoticed by
# every suite in this repository. It is now module-level and these are the lines
# that notice.
#
# The two failure shapes below are the two that were REAL, not invented for a
# test: shape A is New York's `rows_from_*` key never being written, and shape B
# is the residual not subtracting New York -- the state that had actually shipped
# a seed_meta claiming 1,032,349 rows for an inventory holding 133,706.


def _refusal(source_meta, contributing, kept):
    """`check_rows_from`'s stderr, or None if it accepted the build.

    `die` prints and calls `sys.exit`, so a refusal is a `SystemExit` plus a line
    on stderr. Returning the LINE rather than a boolean is the point: a test that
    only caught the exit would pass against a guard that refused for the wrong
    reason, which is what red-proof N1a below actually produced.
    """
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            check_rows_from(source_meta, contributing, kept)
    except SystemExit:
        return err.getvalue()
    return None


# A build that is correct: three contributors, three claims, and they add up.
# This runs FIRST and is not decoration -- every check below asserts a REFUSAL,
# and a `check_rows_from` that refused everything would satisfy all of them. This
# is the control that says it does not.
_GOOD = {
    "rows_from_sf_city": "133706",
    "rows_from_sf_datasf": "12258",
    "rows_from_nyc_tree_points": "898643",
}
_GOOD_CONTRIBUTING = ["nyc_tree_points", "sf_city", "sf_datasf"]
_GOOD_KEPT = 133706 + 12258 + 898643

_control = _refusal(_GOOD, _GOOD_CONTRIBUTING, _GOOD_KEPT)
check(_control is None,
      f"check_rows_from refused a correct build: {_control!r}. Every other check in this "
      f"block asserts a refusal and would pass against a guard that refuses everything")

# ---- shape A: a contributor with no claim of its own.
# Exactly what `feat/nyc-ingest` merged onto s17 produced -- New York contributed
# 898,643 rows and no `rows_from_nyc_tree_points` key existed.
_no_claim = {k: v for k, v in _GOOD.items() if k != "rows_from_nyc_tree_points"}
_a = _refusal(_no_claim, _GOOD_CONTRIBUTING, _GOOD_KEPT)
check(_a is not None, "a contributor with no rows_from_* claim was accepted")
check(_a is not None and "nyc_tree_points" in _a,
      f"the refusal does not name the inventory that has no claim: {_a!r}")
check(_a is not None and "rows_from_<inventory>" in _a,
      f"the refusal does not say what to add: {_a!r}")

# ---- shape B: the claims do not sum to the file's own rows.
# The state that shipped: `rows_from_sf_city` was a residual that did not
# subtract New York, so it absorbed 898,643 rows New York's own key also claimed
# -- every contributor named, and the total far too large.
_double_counted = {**_GOOD, "rows_from_sf_city": str(133706 + 898643)}
_b = _refusal(_double_counted, _GOOD_CONTRIBUTING, _GOOD_KEPT)
check(_b is not None, "claims that do not sum to the file's rows were accepted")
check(_b is not None and "sum to" in _b and f"{_GOOD_KEPT:,}" in _b,
      f"the refusal does not print both the claimed total and the file's own: {_b!r}")

# ---- a claim for an inventory that contributed nothing. A pack's receipt
# inheriting a fused key is what this looks like one layer down, in the publisher.
_stray = {**_GOOD, "rows_from_sj_street_tree": "52775"}
_c = _refusal(_stray, _GOOD_CONTRIBUTING, _GOOD_KEPT)
check(_c is not None and "sj_street_tree" in _c,
      f"a nonzero claim for a non-contributor was accepted or unnamed: {_c!r}")

# A ZERO claim for a non-contributor must NOT be refused -- that is exactly what
# the publisher writes when it zero-fills a pack's receipt, and refusing it would
# make the two tools disagree about a legal file.
check(_refusal({**_GOOD, "rows_from_sj_street_tree": "0"},
               _GOOD_CONTRIBUTING, _GOOD_KEPT) is None,
      "a ZERO claim for a non-contributing inventory was refused; the publisher writes "
      "exactly that when it zero-fills a pack's receipt")

# --------------------------------------------------------------------------
# 9. The `sole` region rule, which is what enforces D18 (review N2)
# --------------------------------------------------------------------------
# `build_seed` registers `(space, None)` -- "this id space's sole region" -- ONLY
# when the space has exactly one region. With New York's five, `region=None`
# resolves to nothing and the build stops with the count.
#
# That refusal is not an inconvenience this round worked around; it is what
# FORCES RULING D18's point-in-polygon assignment to have run on the ~22,995 tree
# points that join no planting space. Register `(space, None)` to make the error
# go away and those trees land in an arbitrary pack, silently.
#
# Nothing pinned it. `resolve_region_ids` is importable and carries the half that
# matters: what a record naming no region resolves to, given a registration.


def _resolve(rows, keys):
    """`resolve_region_ids`'s refusal, or None if every row resolved."""
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            resolve_region_ids(rows, keys)
    except SystemExit:
        return err.getvalue()
    return None


def _row(space, region):
    """A tree row shaped as `emit` builds it -- the region placeholder at
    REGION_ROW_INDEX, full width, so a wrong index is visible."""
    row = [None] * len(TREE_COLUMNS)
    row[REGION_ROW_INDEX] = (space, region)
    return row


# A SOLE-region space registers (space, None), so a record naming no region
# resolves. San Francisco and San Jose have always been this.
_sole_keys = {("sf", None): 1}
check(_resolve([_row("sf", None)], _sole_keys) is None,
      "a record with region=None in a SOLE-region space did not resolve; that is what "
      "San Francisco and San Jose are")

# ...and it resolved to the registered rowid, not merely survived.
_resolved = [_row("sf", None)]
resolve_region_ids(_resolved, _sole_keys)
check(_resolved[0][REGION_ROW_INDEX] == 1,
      f"the row carries {_resolved[0][REGION_ROW_INDEX]!r} where dim_region rowid 1 was "
      f"registered; the key resolved to something else")

# A MULTI-region space does NOT register (space, None), so a record naming no
# region is a STOP, with the count.
#
# Built from `source_names`, which is what `build_seed` registers -- NOT from
# `display_name`, which happens to be the same five strings for New York and
# would make this fixture silently wrong for the next city where they differ.
_nyc_keys = {("us-ny-nyc", name): i + 3
             for i, e in enumerate(REGIONS["us-ny-nyc"])
             for name in e["source_names"]}
check(("us-ny-nyc", None) not in _nyc_keys,
      "this test registered the bare key it exists to prove is absent")
# SEVEN DISTINCT ROWS, and `[_row(...)] * 7` is what this must not be. `* 7`
# builds seven references to ONE list, so the first row `resolve_region_ids`
# rewrites in place changes all seven -- and the next iteration tries to unpack
# an int as a `(space, region)` key. The all-unresolvable case never gets that
# far and passed happily; a red-proof that registered the bare key crashed with
# `TypeError: cannot unpack non-iterable int object` instead of failing, which is
# how the aliasing was found. The count below is only a real count with distinct
# rows.
_stop = _resolve([_row("us-ny-nyc", None) for _ in range(7)], _nyc_keys)
check(_stop is not None,
      "a record with region=None in a five-region space resolved anyway; nothing would then "
      "force D18's orphan assignment and those trees would land in an arbitrary pack")
check(_stop is not None and "us-ny-nyc" in _stop and "None" in _stop,
      f"the refusal does not name the id space and the missing region: {_stop!r}")
check(_stop is not None and "7" in _stop,
      f"the refusal does not carry the COUNT of unresolved rows, which is what tells an "
      f"operator whether this is one bad row or a whole city: {_stop!r}")

# The control: the same five keys DO resolve a record that names its borough, so
# the check above is about `None` specifically and not about a broken fixture.
check(_resolve([_row("us-ny-nyc", "Queens")], _nyc_keys) is None,
      "a record naming its borough did not resolve against the borough keys, so the checks "
      "above prove nothing about `None` in particular")

# --------------------------------------------------------------------------
# THE #95 FOLD, PINNED AT ITS INDEX.
#
# `normalise_case` rewrites values inside `tree_rows` by column index. It once
# computed those indices from its own hand-written copy of the row layout, and
# when `region_id` was inserted at index 6 for s17 every index from 6 onward
# went one too small: the fold read `address` where it meant `site_type` and
# `verification_state` where it meant `legal_status`. It matched nothing,
# rewrote nothing, and reported `case_normalised_values = 0` -- which reads
# exactly like "there was nothing to fold". The published s17 seed shipped with
# the unfolded pairs and the seed contract caught it a publish later.
#
# THE SPECIMEN IS BUILT TO CATCH THAT DRIFT SPECIFICALLY, not merely to exercise
# the fold. One row carries the literal string `Park strip` in `address` -- a
# column deliberately NOT in NORMALISED_SEED_COLUMNS, and the exact column the
# broken index read when it meant `site_type`. So if the index slips by one
# again, the fold rewrites that address and the control below fails, whichever
# way the slip goes.
# --------------------------------------------------------------------------


def _tree_row(**values) -> list:
    """A `tree_rows` row of the right width, addressed by column NAME."""
    row = [None] * len(TREE_COLUMNS)
    for name, value in values.items():
        row[TREE_COLUMNS.index(name)] = value
    return row


_fold_rows = [
    # The majority spellings, which decide the canonical form.
    _tree_row(plant_type="Tree", site_type="Park Strip", address="100 Main St"),
    _tree_row(plant_type="Tree", site_type="Park Strip", address="200 Main St"),
    # The variants the fold must merge -- one per column, so the two counts are
    # distinguishable and a fold that moved only one of them cannot pass.
    _tree_row(plant_type="tree", site_type="Park Strip", address="300 Main St"),
    # The trap: `address` holds the string `site_type`'s mapping would match,
    # and `address` is the column the historical off-by-one actually read.
    _tree_row(plant_type="Tree", site_type="Park strip", address="Park strip"),
]
_fold_counts = {column: {} for column in NORMALISED_SEED_COLUMNS}
for _row in _fold_rows:
    for _column in NORMALISED_SEED_COLUMNS:
        _value = _row[TREE_COLUMNS.index(_column)]
        if _value:
            _fold_counts[_column][_value] = _fold_counts[_column].get(_value, 0) + 1

_fold_log: list[str] = []
_fold_changed = normalise_case(_fold_rows, _fold_counts, _fold_log.append)

check(_fold_changed == 2,
      f"the fold rewrote {_fold_changed} values over a specimen carrying exactly two case "
      "variants (one plant_type, one site_type); 0 is the signature of the index drift the "
      "published s17 seed shipped with")
check(_fold_rows[2][TREE_COLUMNS.index("plant_type")] == "Tree",
      "the fold left plant_type spelled 'tree' beside 'Tree', which is the pair #95 exists "
      "to remove")
check(_fold_rows[3][TREE_COLUMNS.index("site_type")] == "Park Strip",
      "the fold left site_type spelled 'Park strip' beside 'Park Strip'")

# THE CONTROL, and the reason the specimen looks like this. `address` is not a
# normalised column, so it must survive verbatim -- including the row whose
# address is the very string site_type's mapping replaces. This is what goes red
# if the index slips by one in either direction.
check(_fold_rows[3][TREE_COLUMNS.index("address")] == "Park strip",
      "the fold rewrote `address`, which is not in NORMALISED_SEED_COLUMNS -- the column index "
      "has drifted off TREE_COLUMNS again, exactly as it did when region_id landed")

# The fold's own report is part of the contract: `over 0 rows` beside a non-empty
# mapping is what the defect looked like in the build log, and nobody read it.
check(any("plant_type" in line and "over 1 rows" in line for line in _fold_log),
      f"the fold did not report folding one plant_type row; it said {_fold_log}")
check(any("site_type" in line and "over 1 rows" in line for line in _fold_log),
      f"the fold did not report folding one site_type row; it said {_fold_log}")

# Calibration in the other direction: a corpus with no variant folds nothing and
# says nothing, so the assertions above are about variants and not about the
# function always reporting something.
_clean_rows = [_tree_row(plant_type="Tree", site_type="Park Strip", address="100 Main St")]
_clean_counts = {column: {} for column in NORMALISED_SEED_COLUMNS}
_clean_counts["plant_type"] = {"Tree": 1}
_clean_counts["site_type"] = {"Park Strip": 1}
_clean_log: list[str] = []
check(normalise_case(_clean_rows, _clean_counts, _clean_log.append) == 0 and not _clean_log,
      "a corpus with no case variant still reported a fold, so the counts above prove nothing")

# And the mapping itself picks the commonest spelling, which is what makes the
# fold reproducible across rebuilds rather than dependent on row order.
check(canonical_case_map({"Tree": 2, "tree": 1}) == {"Tree": "Tree", "tree": "Tree"},
      "canonical_case_map did not choose the commonest spelling as the winner")

# --------------------------------------------------------------------------

if FAILURES:
    print(f"{len(FAILURES)} failing check(s):")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    sys.exit(1)
print(f"{PASSED} checks passed, 0 failed")
