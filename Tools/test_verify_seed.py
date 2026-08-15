#!/usr/bin/env python3
"""Tests for the two seed acceptance checks that were asserting the wrong thing.

    python3 Tools/test_verify_seed.py

They run here rather than in `CypressTests` because these are properties of the
*verifier*, and the verifier is Python. They build tiny SQLite fixtures rather
than reading the 103 MB seed, for one reason that matters: the real seed cannot
hold the specimens. `trees` carries `UNIQUE (id_space, external_ref)`, so a
genuine within-space duplicate is unconstructible there -- and a check nobody
has ever watched go red is a check nobody knows the direction of. The fixtures
drop that constraint on purpose so the specimen can exist.

Every test is calibrated in both directions: the good case must pass and the bad
case must fail. A check that only ever sees green is indistinguishable from a
check that cannot fail (docs/investigations/repeat-failures-postmortem.md).

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from verify_seed import (  # noqa: E402
    duplicate_external_refs,
    inventory_row_counts,
    neighborhood_coverage,
)

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


# `trees` here deliberately omits the real schema's UNIQUE (id_space,
# external_ref): the point of these fixtures is to build rows the shipped schema
# refuses, so the check can be watched failing on them.
FIXTURE_SCHEMA = """
CREATE TABLE inventories (id TEXT PRIMARY KEY, id_space TEXT NOT NULL);
CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE trees (
    id               INTEGER PRIMARY KEY,
    id_space         TEXT NOT NULL,
    external_ref     TEXT,
    inventory_source TEXT NOT NULL,
    neighborhood_id  INTEGER
);
CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY);
"""


def seed(trees, inventories=(), meta=()) -> sqlite3.Connection:
    """A throwaway in-memory seed. `trees` is (id_space, external_ref, inventory)."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(FIXTURE_SCHEMA)
    conn.executemany("INSERT INTO inventories (id, id_space) VALUES (?, ?)", inventories)
    conn.executemany("INSERT INTO seed_meta (key, value) VALUES (?, ?)", meta)
    conn.executemany(
        "INSERT INTO trees (id_space, external_ref, inventory_source) VALUES (?, ?, ?)",
        trees,
    )
    return conn


def hood_seed(rows, polygons: int) -> sqlite3.Connection:
    """A seed for check 13. `rows` is (id_space, total, stamped)."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(FIXTURE_SCHEMA)
    conn.executemany("INSERT INTO neighborhoods (id) VALUES (?)",
                     [(i + 1,) for i in range(polygons)])
    for space, total, stamped in rows:
        conn.executemany(
            "INSERT INTO trees (id_space, external_ref, inventory_source, "
            "neighborhood_id) VALUES (?, NULL, ?, ?)",
            [(space, space, 1 if i < stamped else None) for i in range(total)],
        )
    return conn


# ---------------------------------------------------------------------------
# Check 12: uniqueness is a property of the pair, never of the ref alone
# ---------------------------------------------------------------------------


def test_a_ref_shared_across_id_spaces_is_not_a_duplicate():
    """FAILS IF: check 12 goes back to keying on the bare external_ref.

    This is the shipped seed's actual shape. SF's TreeID and San Jose's
    FACILITYID are both small integers issued by different cities, so tens of
    thousands of them collide numerically -- 17,518 refs in the seed this was
    written against. The `id_spaces` prefix exists precisely to make that safe,
    and `trees` declares `UNIQUE (id_space, external_ref)` and nothing narrower.
    Failing the file for it reports a defect that does not exist.
    """
    conn = seed([("sf", "276198", "sf_city"), ("us-ca-sj", "276198", "sj_street_tree")])
    within, across = duplicate_external_refs(conn)
    check(within == 0, f"a cross-space ref collision counted as a duplicate ({within})")
    check(across == 1, f"the cross-space collision was not reported at all ({across})")


def test_a_repeated_ref_inside_one_id_space_is_a_duplicate():
    """FAILS IF: the fix over-corrects and check 12 stops catching anything.

    The calibration for the test above. Two rows in ONE id space claiming one
    external_ref is a real defect -- it means the ingest minted two trees for
    one city record, and their uuids collide -- and it must still go red.
    """
    conn = seed([("sf", "276198", "sf_city"), ("sf", "276198", "sf_datasf")])
    within, across = duplicate_external_refs(conn)
    check(within == 1, f"a genuine within-space duplicate went unreported ({within})")
    check(across == 0, f"a within-space duplicate was miscounted as cross-space ({across})")


def test_a_null_external_ref_is_not_a_duplicate():
    """FAILS IF: NULL refs start grouping together.

    A tree with no source ref is a row the inventory published without an asset
    id. SQL's GROUP BY treats NULLs as equal, so several of them would report as
    one duplicated ref if the NULL filter were ever dropped.
    """
    conn = seed([("sf", None, "sf_city"), ("sf", None, "sf_city")])
    within, across = duplicate_external_refs(conn)
    check(within == 0, f"NULL external_refs counted as duplicates ({within})")


# ---------------------------------------------------------------------------
# Check 1: the file must contain what it claims, in any city
# ---------------------------------------------------------------------------


def test_a_non_sf_seed_reports_its_own_inventories():
    """FAILS IF: check 1 goes back to a hardcoded San Francisco row range.

    The old check was `150,000 <= trees <= 260,000`. A San Jose-only seed of
    9,000 trees is a correct file and failed it by construction; an SF seed that
    silently lost 40,000 rows was inside it and passed. Neither number is a
    property of the file. What the file states about itself is.
    """
    conn = seed(
        [("us-ca-sj", "1", "sj_street_tree"), ("us-ca-sj", "2", "sj_street_tree")],
        inventories=[("sj_street_tree", "us-ca-sj")],
        meta=[("rows_from_sj_street_tree", "2"), ("rows_kept", "2")],
    )
    actual, claimed, declared = inventory_row_counts(conn)
    check(actual == {"sj_street_tree": 2}, f"per-inventory counts wrong: {actual}")
    check(claimed == {"sj_street_tree": 2}, f"seed_meta claim not read: {claimed}")
    check(declared == ["sj_street_tree"], f"inventories not read: {declared}")


def test_a_seed_that_lost_rows_disagrees_with_its_own_claim():
    """FAILS IF: check 1 stops comparing the count to the claim.

    The calibration for the test above, and the failure the old range check
    could not see: seed_meta says the build kept three rows and the file holds
    two, so a row was lost between the count and the write.
    """
    conn = seed(
        [("sf", "1", "sf_city"), ("sf", "2", "sf_city")],
        inventories=[("sf_city", "sf")],
        meta=[("rows_from_sf_city", "3"), ("rows_kept", "3")],
    )
    actual, claimed, _ = inventory_row_counts(conn)
    check(
        actual["sf_city"] != claimed["sf_city"],
        "a seed holding fewer rows than it claims read as agreeing with itself",
    )


def test_an_undeclared_inventory_is_visible():
    """FAILS IF: trees can arrive from a source the file never registers.

    `inventories` is what `InventorySource(id:seedMeta:)` resolves a row's
    provenance through. A tree whose inventory_source is absent from that table
    has provenance the app cannot name, and check 1a is what says so.
    """
    conn = seed(
        [("sf", "1", "sf_city"), ("us-ca-sj", "1", "sj_street_tree")],
        inventories=[("sf_city", "sf")],
        meta=[("rows_from_sf_city", "1"), ("rows_kept", "2")],
    )
    actual, _, declared = inventory_row_counts(conn)
    check(
        set(actual) - set(declared) == {"sj_street_tree"},
        f"an undeclared inventory did not stand out: {sorted(actual)} vs {declared}",
    )


# ---------------------------------------------------------------------------
# Check 13: neighborhood coverage is per city, because polygons are
# ---------------------------------------------------------------------------


def test_a_city_with_no_polygons_is_reported_not_failed():
    """FAILS IF: check 13 averages two cities into one percentage again.

    The shipped shape. San Jose has never had neighborhood geometry ingested, so
    none of its 52,788 trees can be stamped; averaged with San Francisco that
    read as "26.578% have no neighborhood" and looked like a coverage
    regression. The owner ruled on 2026-08-14 that shipping the downtown San
    Jose window with no neighborhood line is acceptable, so this reports rather
    than fails -- and keeps saying 0.000% for as long as it is true.
    """
    conn = hood_seed([("sf", 1000, 999), ("us-ca-sj", 500, 0)], polygons=41)
    rows, below, collapsed = neighborhood_coverage(conn)
    check(not below, f"a city with no polygons was failed: {below}")
    check(not collapsed, "a partly-stamped file was called collapsed")
    check(
        dict((r[0], round(r[3], 1)) for r in rows) == {"sf": 99.9, "us-ca-sj": 0.0},
        f"per-space coverage is wrong: {rows}",
    )


def test_a_city_that_has_polygons_is_still_held_to_the_threshold():
    """FAILS IF: the per-space rule becomes a way to excuse real under-stamping.

    The calibration. San Francisco stamps, so it has geometry, so a drop to 90%
    is a genuine regression in the polygon join and must still go red. Waiving
    the cities that cannot stamp must not waive the one that can.
    """
    conn = hood_seed([("sf", 1000, 900), ("us-ca-sj", 500, 0)], polygons=41)
    rows, below, _ = neighborhood_coverage(conn)
    check(
        any(b.startswith("sf ") for b in below),
        f"a real SF stamping regression went unreported: {below}",
    )


def test_a_total_stamping_collapse_is_caught():
    """FAILS IF: 'no space stamps anything' reads as 'no space has polygons'.

    The hole the per-space rule opens and this closes. If the polygon join broke
    entirely, every space would stamp zero, every space would look like San Jose,
    and a purely per-space rule would pass a completely broken file. The file
    still carrying polygons is what makes it a contradiction.
    """
    conn = hood_seed([("sf", 1000, 0), ("us-ca-sj", 500, 0)], polygons=41)
    _, below, collapsed = neighborhood_coverage(conn)
    check(collapsed, "a total stamping collapse passed as 'no city has geometry'")
    conn2 = hood_seed([("us-ca-sj", 500, 0)], polygons=0)
    _, _, collapsed2 = neighborhood_coverage(conn2)
    check(not collapsed2, "a seed with no polygons at all was called collapsed")


def main() -> int:
    for test in [
        test_a_ref_shared_across_id_spaces_is_not_a_duplicate,
        test_a_repeated_ref_inside_one_id_space_is_a_duplicate,
        test_a_null_external_ref_is_not_a_duplicate,
        test_a_non_sf_seed_reports_its_own_inventories,
        test_a_seed_that_lost_rows_disagrees_with_its_own_claim,
        test_an_undeclared_inventory_is_visible,
        test_a_city_with_no_polygons_is_reported_not_failed,
        test_a_city_that_has_polygons_is_still_held_to_the_threshold,
        test_a_total_stamping_collapse_is_caught,
    ]:
        test()

    print(f"{PASSED} checks passed, {len(FAILURES)} failed")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
