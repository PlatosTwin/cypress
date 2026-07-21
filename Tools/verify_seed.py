#!/usr/bin/env python3
"""
verify_seed.py -- acceptance checks for Fixtures/seed/cypress-seed.sqlite.

Run after Tools/build_seed.py. Exits non-zero on the first failed assertion
class; every check is reported either way so one run tells you everything.

    python3 Tools/verify_seed.py [--db PATH]

Checks (BUILD-PLAN.md section 7 row rules + the on-device index contract):
  1. row count within the expected range
  2. zero trees outside the declared SF bounding box
  3. zero trees with NULL lat/lon
  4. stub-path share below 2%
  5. a bbox query against trees_rtree uses the R*Tree index (EXPLAIN QUERY PLAN)
  6. every tree with a non-placeholder qSpecies has exactly one species assertion
  plus structural checks: FK integrity, rtree/trees parity, coordinate parity,
  vacant sites carry no species, dbh buckets well-formed, neighborhood coverage,
  UUIDv5 determinism, and the D5 evergreen/fall-colour rule.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import uuid

# Must match Tools/build_seed.py. Frozen: these define every public tree URL.
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")
NS_SPECIES = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0002")

EXPECTED_MIN_ROWS = 150_000
EXPECTED_MAX_ROWS = 260_000
STUB_CEILING_PCT = 2.0

# Test viewport: a ~1.1 km box over the Panhandle / Haight.
BBOX_TEST = (37.7680, 37.7780, -122.4560, -122.4400)


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

    c.check(
        "1. row count in expected range",
        EXPECTED_MIN_ROWS <= trees <= EXPECTED_MAX_ROWS,
        f"{trees:,} trees (expected {EXPECTED_MIN_ROWS:,}..{EXPECTED_MAX_ROWS:,})",
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
        "SELECT COALESCE(SUM(tree_count),0) FROM species_map WHERE is_placeholder=0"
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
    missing = q(
        "SELECT COUNT(*) FROM trees WHERE status <> 'vacant_site' AND id NOT IN "
        "(SELECT tree_id FROM species_assertions WHERE source='city_import')"
    )[0]
    c.check(
        "6a. every non-placeholder tree has a city_import assertion",
        missing == 0,
        f"{missing} trees with no assertion",
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

    bad_ref = q(
        "SELECT COUNT(*) FROM (SELECT external_ref FROM trees WHERE external_ref "
        "IS NOT NULL GROUP BY external_ref HAVING COUNT(*) > 1)"
    )[0]
    c.check("12. external_ref is unique", bad_ref == 0, f"{bad_ref} duplicated refs")

    no_hood = q("SELECT COUNT(*) FROM trees WHERE neighborhood_id IS NULL")[0]
    hood_pct = 100.0 * no_hood / trees if trees else 0.0
    c.check(
        "13. neighborhood stamping covers >= 99% of trees",
        hood_pct <= 1.0,
        f"{no_hood:,} trees ({hood_pct:.3f}%) have no neighborhood",
    )

    bad_year = q(
        "SELECT COUNT(*) FROM trees WHERE planted_year IS NOT NULL "
        "AND (planted_year < 1800 OR planted_year > 2100)"
    )[0]
    c.check("14. planted_year values are plausible", bad_year == 0, f"{bad_year} offending rows")

    stub_species = q(
        "SELECT COUNT(*) FROM species WHERE curated = 1"
    )[0]
    c.check(
        "15. no city-import species is marked curated",
        stub_species == 0,
        f"{stub_species} species with curated=1",
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

    populated = q(
        "SELECT COUNT(*) FROM species WHERE leaf_retention IS NOT NULL"
    )[0]
    print(f"  [note] species content pipeline (BUILD-PLAN 8) progress: "
          f"{populated}/{species} rows have leaf_retention")

    print("-" * 70)
    print(f"  {c.checks - c.failures}/{c.checks} checks passed")
    print("=" * 70)
    conn.close()
    return 1 if c.failures else 0


if __name__ == "__main__":
    sys.exit(main())
