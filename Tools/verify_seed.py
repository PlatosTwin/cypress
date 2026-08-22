#!/usr/bin/env python3
"""
verify_seed.py -- acceptance checks for Fixtures/seed/cypress-seed.sqlite.

Run after Tools/build_seed.py. Exits non-zero on the first failed assertion
class; every check is reported either way so one run tells you everything.

    python3 Tools/verify_seed.py [--db PATH]

Checks (BUILD-PLAN.md section 7 row rules + the on-device index contract):
  1. the file contains what it says it contains, per inventory
  2. zero trees outside the declared SF bounding box
  3. zero trees with NULL lat/lon
  4. stub-path share below 2%
  5. a bbox query against trees_rtree uses the R*Tree index (EXPLAIN QUERY PLAN)
  6. every tree carrying a species has exactly one species assertion, and a
     tree with no species -- a vacant site, or a qSpecies string that names no
     taxon -- carries none
  plus structural checks: FK integrity, rtree/trees parity, coordinate parity,
  vacant sites carry no species, dbh buckets well-formed, neighborhood coverage,
  UUIDv5 determinism, the curated/id_tips pairing, and the D5
  evergreen/fall-colour rule.

Note on leaf_retention: NULL is a value, not a gap. It means no authoritative
source states the species' habit, and the app renders no phenology chip and no
autumn colour for it (ERRATA E9). The checks below never require it to be set.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Imported rather than restated: check 18 asks the index a question using the
# same trigram scheme that built it, so a change to the scheme cannot leave the
# verifier quietly agreeing with a stale copy of itself.
from build_seed import species_trigrams as _trigrams  # noqa: E402

# Must match Tools/build_seed.py. Frozen: these define every public tree URL.
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")
NS_SPECIES = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0002")

STUB_CEILING_PCT = 2.0

# Test viewport: a ~1.1 km box over the Panhandle / Haight.
BBOX_TEST = (37.7680, 37.7780, -122.4560, -122.4400)


def inventory_row_counts(conn) -> tuple[dict, dict, list]:
    """What the file holds per inventory, and what it claims to hold.

    Check 1 used to be a hardcoded 150,000..260,000 row range, which is San
    Francisco's size and nothing else: every non-SF seed failed it by
    construction, and an SF seed that lost 40,000 rows passed it. The file
    already states its own contents -- `inventories` names each source and
    `seed_meta.rows_from_<inventory>` records how many of its records were kept
    -- so the check that means something in any city is that those two agree.

    Returns (actual, claimed, declared) where `actual` and `claimed` are
    inventory id -> row count and `declared` is the inventories table's ids.
    """
    actual = {
        row[0]: row[1]
        for row in conn.execute(
            "SELECT inventory_source, COUNT(*) FROM trees GROUP BY inventory_source"
        )
    }
    meta = dict(conn.execute("SELECT key, value FROM seed_meta"))
    declared = [row[0] for row in conn.execute("SELECT id FROM inventories ORDER BY id")]
    claimed = {}
    for inventory in declared:
        stated = meta.get(f"rows_from_{inventory}")
        if stated is not None:
            claimed[inventory] = int(stated)
    return actual, claimed, declared


def inventory_completeness(conn) -> list[tuple]:
    """What each inventory PUBLISHES against what this file KEPT (check 1d, s17).

    `rows_from_<inventory>` says what shipped. What the source says it holds was
    recorded under two ad-hoc names -- `trees_source_feature_count`, which is
    global and so could only ever describe one inventory, and
    `sj_source_feature_count`, prefixed by hand -- so completeness was a question
    that could be asked of one inventory at a time and never uniformly. s17
    standardises it as `inventory_<id>_source_feature_count`, the same shape as
    the name/url/date triple beside it.

    **A shortfall is REPORTED, never failed.** Shipping fewer rows than a source
    publishes is the ordinary case and usually deliberate: San Jose ships a
    downtown window out of 344,879 records, and San Francisco's build drops rows
    with no coordinates. The number that matters is that the file can SAY so.
    A silent gap is the defect; a stated one is a decision.

    Absent key means the source publishes no count -- which is a different fact
    from a count of zero and is reported as such.

    Returns (inventory, published, kept, pct) per inventory that states a count.
    """
    meta = dict(conn.execute("SELECT key, value FROM seed_meta"))
    actual = {
        row[0]: row[1]
        for row in conn.execute(
            "SELECT inventory_source, COUNT(*) FROM trees GROUP BY inventory_source"
        )
    }
    out = []
    for inventory in [r[0] for r in conn.execute("SELECT id FROM inventories ORDER BY id")]:
        stated = meta.get(f"inventory_{inventory}_source_feature_count")
        if stated is None or not stated.strip():
            continue
        published = int(stated)
        kept = actual.get(inventory, 0)
        pct = 100.0 * kept / published if published else 0.0
        out.append((inventory, published, kept, pct))
    return out


def neighborhood_coverage(conn) -> tuple[list, list, bool]:
    """Check 13, per id space. Returns (rows, below_threshold, collapsed).

    Neighborhood polygons are a per-city asset and the seed has carried two id
    spaces since #129, so one averaged percentage answers a question nobody
    asked: it read as a coverage regression (26.578%) when the truth was that a
    second city arrived without its geometry. No San Jose neighborhood polygon
    has ever been ingested, so no San Jose tree can be stamped and no threshold
    changes that.

    `rows` is (id_space, total, stamped, pct) per space.
    """
    rows = []
    below = []
    any_stamped = False
    for space, total, missing in conn.execute(
        "SELECT id_space, COUNT(*), SUM(neighborhood_id IS NULL) "
        "FROM trees GROUP BY id_space ORDER BY id_space"
    ):
        stamped = total - missing
        pct = 100.0 * stamped / total if total else 0.0
        any_stamped = any_stamped or stamped > 0
        rows.append((space, total, stamped, pct))
        if stamped > 0 and pct < 99.0:
            below.append(f"{space} at {pct:.3f}%")
    hoods = conn.execute("SELECT COUNT(*) FROM neighborhoods").fetchone()[0]
    return rows, below, bool(hoods > 0 and not any_stamped)


def duplicate_external_refs(conn) -> tuple[int, int]:
    """Check 12, keyed on the pair the schema actually declares unique.

    `trees` carries `UNIQUE (id_space, external_ref)` and its own comment says
    "Unique over the pair, never over the ref alone". Keying this check on the
    bare ref asserted something the schema never promised: SF `TreeID`s and San
    Jose `FACILITYID`s are both small integers from different cities, so they
    collide by the tens of thousands, and that collision is precisely what the
    id-space prefix exists to make safe. A cross-space collision is therefore
    reported, never failed.

    Returns (within_space_duplicates, cross_space_collisions).
    """
    within = conn.execute(
        "SELECT COUNT(*) FROM (SELECT id_space, external_ref FROM trees "
        "WHERE external_ref IS NOT NULL GROUP BY id_space, external_ref "
        "HAVING COUNT(*) > 1)"
    ).fetchone()[0]
    across = conn.execute(
        "SELECT COUNT(*) FROM (SELECT external_ref FROM trees "
        "WHERE external_ref IS NOT NULL GROUP BY external_ref "
        "HAVING COUNT(DISTINCT id_space) > 1)"
    ).fetchone()[0]
    return within, across


class Checker:
    def __init__(self) -> None:
        self.failures = 0
        self.checks = 0

    def check(self, name: str, ok: bool, detail: str = "") -> bool:
        self.checks += 1
        mark = "PASS" if ok else "FAIL"
        if not ok:
            self.failures += 1
        line = f"  [{mark}] {name}"
        if detail:
            line += f"\n         {detail}"
        print(line)
        return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--db",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "Fixtures",
            "seed",
            "cypress-seed.sqlite",
        ),
    )
    args = ap.parse_args()

    if not os.path.exists(args.db):
        print(f"FATAL: no seed database at {args.db}", file=sys.stderr)
        return 3

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    q = lambda sql, *p: conn.execute(sql, p).fetchone()  # noqa: E731
    c = Checker()

    meta = dict(conn.execute("SELECT key, value FROM seed_meta"))
    bbox = json.loads(meta["sf_bbox"])
    size_mb = os.path.getsize(args.db) / 1e6

    print("=" * 70)
    print("VERIFY SEED")
    print("=" * 70)
    print(f"  db                    {args.db}")
    print(f"  size                  {size_mb:.1f} MB")
    print(f"  generated_at          {meta.get('generated_at')}")
    print(f"  trees dataset         {meta.get('trees_dataset_id')}")
    print(f"  neighborhoods dataset {meta.get('neighborhoods_dataset_id')}")
    print(f"  bbox                  lat [{bbox['min_lat']}, {bbox['max_lat']}]  "
          f"lon [{bbox['min_lon']}, {bbox['max_lon']}]")
    print("-" * 70)

    # ---------------------------------------------------------------- 1 counts
    trees = q("SELECT COUNT(*) FROM trees")[0]
    species = q("SELECT COUNT(*) FROM species")[0]
    assertions = q("SELECT COUNT(*) FROM species_assertions")[0]
    hoods = q("SELECT COUNT(*) FROM neighborhoods")[0]
    print(f"  trees={trees:,}  species={species:,}  assertions={assertions:,}  "
          f"neighborhoods={hoods}")
    print("-" * 70)

    actual_rows, claimed_rows, declared_inv = inventory_row_counts(conn)
    c.check(
        "1a. the file carries trees, from inventories it declares",
        trees > 0 and bool(actual_rows) and not (set(actual_rows) - set(declared_inv)),
        f"{trees:,} trees from {sorted(actual_rows)}; "
        f"inventories table declares {declared_inv}"
        + (f"; UNDECLARED: {sorted(set(actual_rows) - set(declared_inv))}"
           if set(actual_rows) - set(declared_inv) else ""),
    )
    unclaimed = sorted(set(actual_rows) - set(claimed_rows))
    disagree = {
        inv: (actual_rows.get(inv, 0), claimed_rows[inv])
        for inv in claimed_rows
        if actual_rows.get(inv, 0) != claimed_rows[inv]
    }
    c.check(
        "1b. per-inventory row counts match what seed_meta claims",
        not unclaimed and not disagree,
        "; ".join(
            [f"{inv}: {a:,} rows, seed_meta says {b:,}" for inv, (a, b) in disagree.items()]
            + ([f"no rows_from_* claim for {unclaimed}"] if unclaimed else [])
        )
        or ", ".join(f"{inv}={n:,}" for inv, n in sorted(actual_rows.items())),
    )
    kept = meta.get("rows_kept")
    c.check(
        "1c. seed_meta.rows_kept is the file's own total",
        kept is not None and int(kept) == trees,
        f"rows_kept={kept} vs {trees:,} rows in trees",
    )

    # 1d. Per-inventory completeness (s17). Reported, not failed -- see
    # `inventory_completeness`. The check that CAN fail is that an inventory
    # stating a count states a coherent one.
    completeness = inventory_completeness(conn)
    silent = [inv for inv in declared_inv
              if inv not in {row[0] for row in completeness}]
    c.check(
        "1d. every inventory stating a source feature count states a coherent one",
        all(published > 0 and kept <= published
            for _, published, kept, _ in completeness),
        "; ".join(
            f"{inv}: kept {kept:,} of {published:,} published ({pct:.2f}%)"
            for inv, published, kept, pct in completeness
        )
        + (f"; NO SOURCE COUNT STATED for {silent} (the source does not publish one, "
           f"or this build did not record it)" if silent else "")
        or "no inventory in this file states a source feature count",
    )

    # ----------------------------------------------------------------- 2 bbox
    out = q(
        "SELECT COUNT(*) FROM trees WHERE lat < ? OR lat > ? OR lon < ? OR lon > ?",
        bbox["min_lat"], bbox["max_lat"], bbox["min_lon"], bbox["max_lon"],
    )[0]
    c.check("2. zero trees outside the SF bbox", out == 0, f"{out} offending rows")

    # ------------------------------------------------------------ 3 null coords
    nulls = q("SELECT COUNT(*) FROM trees WHERE lat IS NULL OR lon IS NULL")[0]
    c.check("3. zero trees with NULL lat/lon", nulls == 0, f"{nulls} offending rows")

    # ------------------------------------------------------------------ 4 stubs
    stub_rows = q(
        "SELECT COALESCE(SUM(tree_count),0) FROM species_map WHERE is_stub=1"
    )[0]
    species_rows = q(
        "SELECT COALESCE(SUM(tree_count),0) FROM species_map "
        "WHERE is_placeholder=0 AND is_non_taxon=0"
    )[0]
    stub_pct = 100.0 * stub_rows / species_rows if species_rows else 0.0
    c.check(
        "4. stub-path share under the 2% ceiling",
        stub_pct < STUB_CEILING_PCT,
        f"{stub_rows:,} / {species_rows:,} species-bearing rows = {stub_pct:.4f}% "
        f"(ceiling {STUB_CEILING_PCT}%)",
    )

    # ------------------------------------------------------------- 5 rtree plan
    plan_sql = (
        "SELECT t.id FROM trees_rtree r JOIN trees t ON t.id = r.id "
        "WHERE r.max_lat >= ? AND r.min_lat <= ? AND r.max_lon >= ? AND r.min_lon <= ?"
    )
    plan = conn.execute("EXPLAIN QUERY PLAN " + plan_sql, BBOX_TEST).fetchall()
    plan_text = " | ".join(row[-1] for row in plan)
    # An R*Tree scan always reports "VIRTUAL TABLE INDEX <n>:<constraints>". The
    # suffix after the colon is the encoded constraint list and is EMPTY when the
    # module was handed no usable constraint, i.e. when it degrades to a full
    # scan. So a non-empty suffix is the real proof the index is doing work.
    marker = "VIRTUAL TABLE INDEX"
    suffix = ""
    if marker in plan_text:
        tail = plan_text.split(marker, 1)[1].strip()
        suffix = tail.split(":", 1)[1].split(" ")[0] if ":" in tail else ""
    c.check(
        "5a. bbox query plan uses the R*Tree index with constraints",
        marker in plan_text and suffix != "",
        f"{plan_text}   (constraint token {suffix!r})",
    )

    rtree_hits = {r[0] for r in conn.execute(plan_sql, BBOX_TEST)}
    scan_hits = {
        r[0]
        for r in conn.execute(
            "SELECT id FROM trees WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            BBOX_TEST,
        )
    }
    # rtree coordinates are single-precision and are rounded OUTWARD, so the
    # index is a conservative filter: it never drops a true hit but may return a
    # few rows just outside the box. Callers must re-check exactly.
    over = len(rtree_hits) - len(scan_hits)
    c.check(
        "5b. R*Tree bbox result is a superset of the exact result",
        scan_hits <= rtree_hits and len(scan_hits) > 0 and over <= max(16, len(scan_hits) // 100),
        f"rtree={len(rtree_hits):,} scan={len(scan_hits):,} "
        f"(+{over} float32 boundary rows) in the test viewport",
    )

    recheck_sql = plan_sql + " AND t.lat BETWEEN ? AND ? AND t.lon BETWEEN ? AND ?"
    recheck = {r[0] for r in conn.execute(recheck_sql, BBOX_TEST + BBOX_TEST)}
    c.check(
        "5d. R*Tree + exact re-check is exactly the full-scan result",
        recheck == scan_hits,
        f"{len(recheck):,} rows after re-check vs {len(scan_hits):,} scanned",
    )

    latlon_plan = conn.execute(
        "EXPLAIN QUERY PLAN SELECT id FROM trees "
        "WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
        BBOX_TEST,
    ).fetchall()
    latlon_text = " | ".join(r[-1] for r in latlon_plan)
    c.check(
        "5c. (lat, lon) covering index is used for a viewport scan",
        "idx_trees_lat_lon" in latlon_text,
        latlon_text,
    )

    # --------------------------------------------------------- 6 one assertion
    # A tree with no species carries no assertion, and there are two ways to get
    # there: the site is vacant, or the city's qSpecies string names no taxon
    # ("Shrub", "Privet", "To Be Determine" -- NON_TAXON_SPECIES in
    # Tools/build_seed.py). The second kind is a live tree with an unidentified
    # occupant, so it must not be asserted onto a species it does not have.
    missing = q(
        "SELECT COUNT(*) FROM trees WHERE status <> 'vacant_site' "
        "AND species_current IS NOT NULL AND id NOT IN "
        "(SELECT tree_id FROM species_assertions WHERE source='city_import')"
    )[0]
    c.check(
        "6a. every tree carrying a species has a city_import assertion",
        missing == 0,
        f"{missing} trees with no assertion",
    )
    non_taxon_asserted = q(
        "SELECT COUNT(*) FROM species_assertions a JOIN trees t ON t.id = a.tree_id "
        "WHERE t.species_current IS NULL"
    )[0]
    c.check(
        "6d. no tree without a species carries an assertion",
        non_taxon_asserted == 0,
        f"{non_taxon_asserted} offending rows",
    )
    non_taxon_mapped = q(
        "SELECT COUNT(*) FROM species_map WHERE is_non_taxon = 1 AND species_id IS NOT NULL"
    )[0]
    c.check(
        "6e. a qSpecies string that names no taxon maps to no species",
        non_taxon_mapped == 0,
        f"{non_taxon_mapped} offending rows",
    )
    dupes = q(
        "SELECT COUNT(*) FROM (SELECT tree_id FROM species_assertions "
        "WHERE source='city_import' GROUP BY tree_id HAVING COUNT(*) > 1)"
    )[0]
    c.check(
        "6b. no tree has more than one city_import assertion",
        dupes == 0,
        f"{dupes} trees with duplicate assertions",
    )
    mismatch = q(
        "SELECT COUNT(*) FROM trees t JOIN species_assertions a ON a.tree_id = t.id "
        "WHERE a.source='city_import' AND t.species_current IS NOT a.species_id"
    )[0]
    c.check(
        "6c. trees.species_current matches its city_import assertion",
        mismatch == 0,
        f"{mismatch} mismatched rows",
    )

    # ------------------------------------------------------------- structural
    print("-" * 70)
    orphan_rtree = q(
        "SELECT COUNT(*) FROM trees_rtree r LEFT JOIN trees t ON t.id = r.id "
        "WHERE t.id IS NULL"
    )[0]
    unindexed = q(
        "SELECT COUNT(*) FROM trees t LEFT JOIN trees_rtree r ON r.id = t.id "
        "WHERE r.id IS NULL"
    )[0]
    c.check(
        "7. trees and trees_rtree are in 1:1 parity",
        orphan_rtree == 0 and unindexed == 0,
        f"{orphan_rtree} orphan rtree rows, {unindexed} untracked trees",
    )

    # rtree stores float32, so exact equality is the wrong assertion. The right
    # one is containment (the rectangle must never exclude its own point) plus a
    # drift bound at single-precision epsilon (~1.5e-5 deg, under 2 m).
    escapes = q(
        "SELECT COUNT(*) FROM trees t JOIN trees_rtree r ON r.id = t.id "
        "WHERE r.min_lat > t.lat OR r.max_lat < t.lat "
        "OR r.min_lon > t.lon OR r.max_lon < t.lon"
    )[0]
    c.check(
        "8a. every rtree rectangle contains its tree's coordinate",
        escapes == 0,
        f"{escapes} points outside their own rectangle",
    )
    dlat, dlon = q(
        "SELECT MAX(ABS(r.min_lat - t.lat)), MAX(ABS(r.min_lon - t.lon)) "
        "FROM trees t JOIN trees_rtree r ON r.id = t.id"
    )
    c.check(
        "8b. rtree float32 drift stays within single-precision epsilon",
        max(dlat, dlon) < 5e-5,
        f"max drift lat {dlat:.2e} deg, lon {dlon:.2e} deg (~{max(dlat, dlon) * 111320:.1f} m)",
    )

    fk = conn.execute("PRAGMA foreign_key_check").fetchall()
    c.check("9. foreign key integrity", not fk, f"{len(fk)} violations")

    bad_vacant = q(
        "SELECT COUNT(*) FROM trees WHERE status='vacant_site' "
        "AND species_current IS NOT NULL"
    )[0]
    c.check(
        "10. vacant_site rows carry no species",
        bad_vacant == 0,
        f"{bad_vacant} offending rows",
    )

    bad_dbh = q(
        "SELECT COUNT(*) FROM trees WHERE (dbh_city_cm_min IS NULL) "
        "<> (dbh_city_cm_max IS NULL) OR (dbh_city_cm_min IS NOT NULL AND "
        "(dbh_city_cm_max - dbh_city_cm_min <> 5 OR dbh_city_cm_min % 5 <> 0))"
    )[0]
    c.check(
        "11. dbh buckets are well-formed 5 cm ranges",
        bad_dbh == 0,
        f"{bad_dbh} offending rows",
    )

    within_dupes, cross_space = duplicate_external_refs(conn)
    c.check(
        "12. external_ref is unique within its id space",
        within_dupes == 0,
        f"{within_dupes:,} duplicated (id_space, external_ref) pairs; "
        f"{cross_space:,} refs are reused across id spaces, which the "
        f"id-space prefix exists to make safe",
    )

    # Per id space, because neighborhood polygons are per city and the seed has
    # carried two id spaces since #129. Averaged over the file this read as a
    # coverage regression (26.578%) and was really "a second city arrived without
    # its polygons": no San Jose neighborhood geometry has ever been ingested, so
    # no San Jose tree can be stamped and no threshold can change that.
    #
    # The owner ruled on 2026-08-14 that shipping the downtown San Jose window
    # with no neighborhood line is acceptable for the beta. So the rule is: a
    # space with polygons must reach 99%; a space with none is REPORTED at its
    # real coverage and not failed. It is not waived silently -- a space that
    # gains polygons and then loses them fails, and the note keeps saying 0.0%
    # for as long as that is true.
    # Which spaces have polygons is derived from the stamping itself, not from a
    # column (`neighborhoods` carries no id_space) and not from the literal "sf".
    # A space that stamps any tree at all has geometry covering it and is held to
    # the 99% bar; a space that stamps none has none and is reported.
    # The collapse case the per-space rule would otherwise go quiet on: if the
    # file carries polygons but nothing anywhere is stamped, every space reads as
    # "has no geometry" and the check would pass while being entirely broken.
    cov_rows, below, collapsed = neighborhood_coverage(conn)
    detail = [f"{space}: {stamped:,}/{total:,} stamped ({pct:.3f}%)"
              for space, total, stamped, pct in cov_rows]
    c.check(
        "13. every id space that has neighborhood geometry stamps >= 99% of its trees",
        not below and not collapsed,
        "; ".join(detail) + f"   ({hoods} polygons in the file)"
        + (f"   BELOW THRESHOLD: {', '.join(below)}" if below else "")
        + ("   NOTHING STAMPED despite the file carrying polygons" if collapsed else ""),
    )

    bad_year = q(
        "SELECT COUNT(*) FROM trees WHERE planted_year IS NOT NULL "
        "AND (planted_year < 1800 OR planted_year > 2100)"
    )[0]
    c.check("14. planted_year values are plausible", bad_year == 0, f"{bad_year} offending rows")

    # planted_on is the same fact at DataSF's own grain, and the almanac's
    # "planted this spring" reads it rather than the year (screen 12). The two
    # columns are one fact, so they are checked as one: both set or both NULL,
    # the year agreeing with the date, and the date well formed.
    bad_planted_on = q(
        "SELECT COUNT(*) FROM trees WHERE (planted_on IS NULL) <> (planted_year IS NULL) "
        "OR (planted_on IS NOT NULL AND ("
        "     planted_on <> date(planted_on) "
        "  OR CAST(substr(planted_on, 1, 4) AS INTEGER) <> planted_year))"
    )[0]
    c.check(
        "14b. planted_on agrees with planted_year and is a real date",
        bad_planted_on == 0,
        f"{bad_planted_on} offending rows",
    )

    # `curated` means "this species has an authored field-guide entry in
    # Fixtures/species/curated.yaml" (BUILD-PLAN 8). The city import never sets
    # it; only the content load does, and only for entries that carry id_tips.
    # A curated row with no id_tips would put an empty field guide on a profile.
    curated_without_tips = q(
        "SELECT COUNT(*) FROM species WHERE curated = 1 AND json_array_length(id_tips) = 0"
    )[0]
    c.check(
        "15a. every curated species carries id_tips",
        curated_without_tips == 0,
        f"{curated_without_tips} curated species with an empty id_tips array",
    )
    tips_without_curated = q(
        "SELECT COUNT(*) FROM species WHERE curated = 0 AND json_array_length(id_tips) > 0"
    )[0]
    c.check(
        "15b. no uncurated species carries id_tips",
        tips_without_curated == 0,
        f"{tips_without_curated} uncurated species with id_tips",
    )

    # ------------------------------------------------- uuid identity model --
    print("-" * 70)
    bad_uuid = q(
        "SELECT COUNT(*) FROM trees WHERE uuid IS NULL OR LENGTH(uuid) <> 36"
    )[0]
    dupe_uuid = q(
        "SELECT COUNT(*) FROM (SELECT uuid FROM trees GROUP BY uuid HAVING COUNT(*) > 1)"
    )[0]
    c.check(
        "16a. every tree has a well-formed unique uuid",
        bad_uuid == 0 and dupe_uuid == 0,
        f"{bad_uuid} malformed, {dupe_uuid} duplicated",
    )

    # Recompute UUIDv5 independently from the stored TreeID. This is the real
    # determinism guarantee: the uuid is a pure function of the frozen namespace
    # and the DataSF TreeID, so any rebuild reproduces it exactly.
    sample = conn.execute(
        "SELECT external_ref, uuid FROM trees WHERE external_ref IS NOT NULL"
    ).fetchall()
    wrong = [
        (ref, got)
        for ref, got in sample
        if str(uuid.uuid5(NS_TREE, str(ref))) != got
    ]
    c.check(
        "16b. every tree uuid == uuidv5(NS_TREE, TreeID)",
        not wrong,
        f"{len(wrong)} of {len(sample):,} rows disagree"
        + (f"; first: {wrong[0]}" if wrong else ""),
    )

    meta_ns = meta.get("ns_tree_uuid")
    c.check(
        "16c. seed_meta records the frozen tree uuid namespace",
        meta_ns == str(NS_TREE),
        f"{meta_ns} (verifier expects {NS_TREE})",
    )

    sp_sample = conn.execute("SELECT scientific_name, uuid FROM species").fetchall()
    sp_wrong = [
        (n, u)
        for n, u in sp_sample
        if str(uuid.uuid5(NS_SPECIES, " ".join(n.strip().lower().split()))) != u
    ]
    c.check(
        "16d. every species uuid == uuidv5(NS_SPECIES, normalised scientific name)",
        not sp_wrong,
        f"{len(sp_wrong)} of {len(sp_sample):,} rows disagree",
    )

    # -------------------------------------------------------------- D5 rule --
    # The database CHECK already refuses these rows on write; this asserts the
    # shipped file actually satisfies it, and gives the species content agent a
    # direct signal if a bulk load ever bypasses the constraint.
    d5 = q(
        "SELECT COUNT(*) FROM species WHERE leaf_retention = 'evergreen' AND "
        "json_array_length(COALESCE(json_extract(seasonal,'$.fall_color_months'),'[]')) > 0"
    )[0]
    c.check(
        "17a. D5: no evergreen species carries fall_color_months",
        d5 == 0,
        f"{d5} offending species",
    )
    bad_lr = q(
        "SELECT COUNT(*) FROM species WHERE leaf_retention IS NOT NULL AND "
        "leaf_retention NOT IN ('evergreen','deciduous','semi_deciduous')"
    )[0]
    c.check("17b. leaf_retention vocabulary is respected", bad_lr == 0, f"{bad_lr} offending rows")

    bad_json = q(
        "SELECT COUNT(*) FROM species WHERE NOT json_valid(id_tips) "
        "OR NOT json_valid(seasonal) OR NOT json_valid(care_notes)"
    )[0]
    c.check(
        "17c. species json columns hold valid JSON",
        bad_json == 0,
        f"{bad_json} offending rows",
    )

    # ------------------------------------------------------ 18 species trigrams
    # The similarity index of ERRATA E165, seed schema 15. These checks are not
    # "the table exists" -- they ask the index the two questions it was added to
    # answer, because a table that is present and wrong looks exactly like a
    # table that is present and right.
    has_trigrams = q(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='species_trigrams'"
    )[0]
    c.check("18a. the seed carries species_trigrams (schema 15, E165)", has_trigrams == 1)

    if has_trigrams:
        indexable = q(
            "SELECT COUNT(*) FROM species WHERE deleted_at IS NULL "
            "AND scientific_name NOT LIKE ':: %'"
        )[0]
        covered = q("SELECT COUNT(DISTINCT species_id) FROM species_trigrams")[0]
        c.check(
            "18b. every searchable species carries trigrams",
            covered == indexable,
            f"{covered} of {indexable} searchable species are indexed",
        )

        # No stub and no soft-deleted row may be reachable through the index, or
        # a fuzzy match would surface a name the search itself refuses to offer
        # (RULINGS R47).
        leaked = q(
            "SELECT COUNT(DISTINCT t.species_id) FROM species_trigrams t "
            "JOIN species s ON s.id = t.species_id "
            "WHERE s.deleted_at IS NOT NULL OR s.scientific_name LIKE ':: %'"
        )[0]
        c.check(
            "18c. no stub or deleted species is reachable through the index",
            leaked == 0,
            f"{leaked} unsearchable species are indexed",
        )

        # The calibration: a query whose answer is known before the run. These
        # are the two misses ERRATA E165 named as still-not-fixed, so if the
        # index cannot answer them it is not doing the job it was added for.
        # Kept in step with SpeciesQueries.similarityNumerator/Denominator.
        def similar(query: str) -> set:
            grams = sorted(_trigrams(query))
            marks = ",".join("?" * len(grams))
            rows = conn.execute(
                f"SELECT s.scientific_name FROM species s JOIN ("
                f"  SELECT species_id, COUNT(*) AS shared FROM species_trigrams "
                f"   WHERE trigram IN ({marks}) GROUP BY species_id "
                f"  HAVING COUNT(*) * 5 >= ? * 3) m ON m.species_id = s.id "
                f" WHERE s.deleted_at IS NULL AND s.scientific_name NOT LIKE ':: %'",
                grams + [len(grams)],
            ).fetchall()
            return {r[0] for r in rows}

        typo = similar("liquidamber")
        c.check(
            "18d. a misspelled query still reaches the species (E165, typo)",
            "Liquidambar styraciflua" in typo,
            f"'liquidamber' reached {sorted(typo)}",
        )
        alternate = similar("sweetgum")
        c.check(
            "18e. an alternate spelling reaches the species (E165, 'Sweet Gum')",
            "Liquidambar styraciflua" in alternate,
            f"'sweetgum' reached {sorted(alternate)}",
        )
        # The control: a query the substring search already answered correctly
        # must not gain anything, or the bar is too low and the map narrows to
        # species nobody asked for.
        cypress = similar("cypress")
        substring_cypress = {
            r[0] for r in conn.execute(
                "SELECT scientific_name FROM species WHERE deleted_at IS NULL "
                "AND scientific_name NOT LIKE ':: %' AND (scientific_name LIKE '%cypress%' "
                "OR common_name LIKE '%cypress%')"
            ).fetchall()
        }
        c.check(
            "18f. control: 'cypress' gains nothing it did not already match",
            cypress <= substring_cypress,
            f"the similarity bar admitted {sorted(cypress - substring_cypress)}",
        )
        print(f"  [note] species_trigrams: "
              f"{q('SELECT COUNT(*) FROM species_trigrams')[0]:,} rows over {covered} species")

    populated = q(
        "SELECT COUNT(*) FROM species WHERE leaf_retention IS NOT NULL"
    )[0]
    curated_rows = q("SELECT COUNT(*) FROM species WHERE curated = 1")[0]
    print(f"  [note] species content (BUILD-PLAN 8): {populated}/{species} rows have "
          f"leaf_retention, {species - populated} are unknown (ERRATA E9), "
          f"{curated_rows} carry an authored field guide")

    print("-" * 70)
    print(f"  {c.checks - c.failures}/{c.checks} checks passed")
    print("=" * 70)
    conn.close()
    return 1 if c.failures else 0


if __name__ == "__main__":
    sys.exit(main())
