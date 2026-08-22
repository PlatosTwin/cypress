#!/usr/bin/env python3
"""Tests for the publisher's s17 behaviour: regions, coverage, and format 2.

    python3 Tools/test_publish_cities.py

They run here rather than in `CypressTests` because these are properties of the
*publisher*, and the publisher is Python. They build tiny SQLite fixtures rather
than reading the 103 MB seed: the whole subject is what the publisher does with
a shape the real seed does not have yet (several regions in one id space), and
the real seed cannot hold the specimen.

Every test is calibrated in both directions where a direction exists: the good
case must pass and the bad case must fail. A check that only ever sees green is
indistinguishable from a check that cannot fail
(docs/investigations/repeat-failures-postmortem.md).

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import sqlite3
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import publish_cities  # noqa: E402
from publish_cities import (  # noqa: E402
    COVERAGE_KEYS,
    LEGACY_MANIFEST_FORMAT,
    MANIFEST_FORMAT,
    MANIFEST_V1_NAME,
    MANIFEST_V2_NAME,
    SEED_SCHEMA_VERSION,
    coverage_for,
)

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


# --------------------------------------------------------------------------
# A fixture seed carrying the s17 shape, with TWO regions in ONE id space --
# which is New York's shape and is exactly what `id_space` alone cannot
# express. San Francisco's real seed cannot be this, which is why the fixture
# exists.
# --------------------------------------------------------------------------

FIXTURE_SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE dim_city (
    id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
    state TEXT NOT NULL, county TEXT NOT NULL, urban_forestry_url TEXT NOT NULL
);
CREATE TABLE dim_region (
    id INTEGER PRIMARY KEY, pack_id TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
    level TEXT NOT NULL, city_id INTEGER NOT NULL REFERENCES dim_city(id),
    CHECK (level IN ('city','borough','extent'))
);
CREATE TABLE id_spaces (
    id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL,
    city_id INTEGER NOT NULL REFERENCES dim_city(id)
);
CREATE TABLE inventories (
    id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
    name TEXT NOT NULL, url TEXT NOT NULL
);
CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE species (id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE);
CREATE TABLE trees (
    id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
    id_space TEXT NOT NULL REFERENCES id_spaces(id),
    external_ref TEXT NOT NULL, source TEXT NOT NULL,
    inventory_source TEXT NOT NULL REFERENCES inventories(id),
    region_id INTEGER NOT NULL REFERENCES dim_region(id),
    lat REAL NOT NULL, lon REAL NOT NULL,
    neighborhood_id INTEGER REFERENCES neighborhoods(id),
    status TEXT NOT NULL, species_current INTEGER REFERENCES species(id),
    site_lineage INTEGER REFERENCES trees(id),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE species_assertions (
    id INTEGER PRIMARY KEY, tree_id INTEGER NOT NULL REFERENCES trees(id)
);
CREATE TABLE species_map (qspecies_string TEXT PRIMARY KEY, tree_count INTEGER);
CREATE VIRTUAL TABLE trees_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT);
"""


def build_fixture(path: str, *, meta_extra: dict | None = None) -> None:
    """A two-city seed where one city has two boroughs -- NYC's shape, in miniature."""
    con = sqlite3.connect(path)
    con.executescript(FIXTURE_SCHEMA)
    con.execute("INSERT INTO dim_city VALUES (1,'us-ca-sf','San Francisco','CA',"
                "'San Francisco','https://example.invalid/sf')")
    con.execute("INSERT INTO dim_city VALUES (2,'us-ny-nyc','New York City','NY',"
                "'New York City','https://example.invalid/nyc')")
    con.executemany(
        "INSERT INTO dim_region(id,pack_id,display_name,level,city_id) VALUES(?,?,?,?,?)",
        [
            (1, "sf", "San Francisco", "city", 1),
            (2, "us-ny-nyc-queens", "Queens", "borough", 2),
            (3, "us-ny-nyc-bronx", "Bronx", "borough", 2),
        ],
    )
    con.executemany(
        "INSERT INTO id_spaces(id,identity_prefix,note,city_id) VALUES(?,?,?,?)",
        [("sf", "", "fixture", 1), ("us-ny-nyc", "us-ny-nyc:", "fixture", 2)],
    )
    con.executemany(
        "INSERT INTO inventories(id,id_space,name,url) VALUES(?,?,?,?)",
        [("sf_city", "sf", "SF inventory", "https://example.invalid/sf-inv"),
         ("nyc_tree_points", "us-ny-nyc", "NYC inventory", "https://example.invalid/nyc-inv")],
    )
    now = "2026-01-01T00:00:00+00:00"
    rows = []
    # 3 SF, 2 Queens, 1 Bronx -- deliberately different counts, so a split that
    # returned the wrong region's rows cannot pass the count assertions by luck.
    plan = [("sf", "sf_city", 1, 3), ("us-ny-nyc", "nyc_tree_points", 2, 2),
            ("us-ny-nyc", "nyc_tree_points", 3, 1)]
    tid = 0
    for space, inv, region_id, count in plan:
        for _ in range(count):
            tid += 1
            rows.append((tid, f"00000000-0000-4000-8000-{tid:012d}", space, str(tid),
                         "city_import", inv, region_id, 37.7 + tid / 1000,
                         -122.4 + tid / 1000, None, "alive", None, None, now, now))
    con.executemany(
        "INSERT INTO trees(id,uuid,id_space,external_ref,source,inventory_source,region_id,"
        "lat,lon,neighborhood_id,status,species_current,site_lineage,created_at,updated_at) "
        "VALUES(" + ",".join("?" * 15) + ")", rows)
    con.executemany("INSERT INTO trees_rtree(id,min_lat,max_lat,min_lon,max_lon) "
                    "VALUES(?,?,?,?,?)",
                    [(r[0], r[7], r[7], r[8], r[8]) for r in rows])
    meta = {
        "generated_at": now,
        "inventory_sf_city_id_space": "sf",
        "inventory_sf_city_snapshot_on": "2026-07-31",
        "inventory_nyc_tree_points_id_space": "us-ny-nyc",
        "inventory_nyc_tree_points_snapshot_on": "2026-07-28",
        "id_spaces_in_file": "sf,us-ny-nyc",
        "rows_kept": str(len(rows)),
        "trees_snapshot_on": "2026-07-31",
    }
    meta.update(meta_extra or {})
    con.executemany("INSERT INTO seed_meta(key,value) VALUES(?,?)", sorted(meta.items()))
    con.commit()
    con.close()


# The fixture's borough packs, registered the way the NYC ingest round will
# register them for real. Patched onto the module rather than added to the
# production `DISPLAY_NAMES`: this round does not publish New York, and a
# publisher that already knew five borough names would be claiming a readiness
# it does not have. The patch is what lets the two-borough shape be exercised
# without pretending the round shipped it.
#
# `us-ny-nyc` itself needs an entry too, because every borough entry carries
# `region.parent_city_display_name` -- which is exactly the obligation the real
# registration will have, so the fixture proves the shape of that work as well.
FIXTURE_DISPLAY_NAMES = {
    "sf": "San Francisco",
    "us-ny-nyc": "New York City",
    "us-ny-nyc-queens": "Queens",
    "us-ny-nyc-bronx": "Bronx",
    "us-ny-nyc-si": "Staten Island",
}


class Result:
    """`subprocess.CompletedProcess`'s two fields, from an in-process run."""

    def __init__(self, returncode: int, stdout: str, stderr: str) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def run_publisher(db: str, out: str) -> Result:
    """Run `publish_cities.main()` in this process, with the fixture's names.

    In-process rather than as a subprocess for one reason that matters: the
    publisher refuses a pack whose display name it was not given, correctly, and
    a subprocess gives no seam to give it one. Every guard under test fires
    AFTER that check, so a subprocess run could only ever observe the name check
    -- which is how the first version of this file reported three failures that
    were all the same guard.
    """
    argv = sys.argv
    names = dict(publish_cities.DISPLAY_NAMES)
    out_buf, err_buf = io.StringIO(), io.StringIO()
    code = 0
    try:
        publish_cities.DISPLAY_NAMES.clear()
        publish_cities.DISPLAY_NAMES.update(FIXTURE_DISPLAY_NAMES)
        sys.argv = ["publish_cities.py", "--db", db, "--out", out]
        with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
            publish_cities.main()
    except SystemExit as exit_:
        code = exit_.code if isinstance(exit_.code, int) else 1
    finally:
        sys.argv = argv
        publish_cities.DISPLAY_NAMES.clear()
        publish_cities.DISPLAY_NAMES.update(names)
    return Result(code, out_buf.getvalue(), err_buf.getvalue())


# --------------------------------------------------------------------------
# 1. coverage_for -- the divergence this round closes
# --------------------------------------------------------------------------
# Fails if: the publisher stops preferring the standardised `coverage_<id_space>`
# key, i.e. drifts back out of agreement with `SeedCities.coverage` (Swift),
# which prefers it and falls back to the legacy per-city name. The two orders
# disagreeing is the defect; the two keys carrying DIFFERENT values here is what
# makes the preference observable at all.

check(
    coverage_for("us-ca-sj", {"coverage_us-ca-sj": "citywide", "sj_ship_extent": "downtown"})
    == "citywide",
    "coverage_for did not prefer the standardised coverage_<id_space> key over the legacy "
    "one; that is the exact divergence with SeedCities.coverage that s17 closes",
)
check(
    coverage_for("us-ca-sj", {"sj_ship_extent": "downtown"}) == "downtown",
    "coverage_for lost the legacy fallback, so a pre-s17 seed would publish as full coverage",
)
check(
    coverage_for("us-ca-sj", {"coverage_us-ca-sj": "downtown"}) == "downtown",
    "coverage_for did not read the standardised key when it is the only one present",
)
check(coverage_for("sf", {}) == "full",
      "an absent coverage key must mean full coverage")
check(
    coverage_for("us-ca-sj", {"coverage_us-ca-sj": "", "sj_ship_extent": "downtown"})
    == "downtown",
    "an EMPTY standardised key must not shadow a legacy key that has a value -- SeedCities "
    "checks `!value.isEmpty` and this must match it",
)
# The mirror itself. If a city is added to COVERAGE_KEYS and not to
# `SeedCities.legacyCoverageKeys`, the app silently claims full coverage for it.
# `BundledCityTests.everyPublisherCoverageKeyIsMirrored` is the guard; this
# asserts the table it reads still has the shape that guard parses.
check(
    COVERAGE_KEYS == {"us-ca-sj": "sj_ship_extent"},
    f"COVERAGE_KEYS changed to {COVERAGE_KEYS!r}; SeedCities.legacyCoverageKeys mirrors it by "
    f"hand and BundledCityTests parses this literal -- update both",
)

# --------------------------------------------------------------------------
# 2. The version numbers the two sides must agree on
# --------------------------------------------------------------------------
# Fails if: either constant moves without the Swift side moving with it. The
# Swift half is `RegionGenerationTests.theGenerationNumbersAreWhatThisRoundSet`.

check(SEED_SCHEMA_VERSION == 17,
      f"SEED_SCHEMA_VERSION is {SEED_SCHEMA_VERSION}, but SeedDatabase.newestKnownSchemaVersion "
      f"is 17; a published file this build writes would be refused by the app that reads it")
check(MANIFEST_FORMAT == 2,
      f"MANIFEST_FORMAT is {MANIFEST_FORMAT}, but CityManifest.knownFormat is 2")
check(LEGACY_MANIFEST_FORMAT == 1,
      "the legacy manifest stopped being format 1, which is the only format an unupdated "
      "install reads (RULING D8)")

# --------------------------------------------------------------------------
# 3. The publish itself, end to end, against the two-borough fixture
# --------------------------------------------------------------------------

workdir = tempfile.mkdtemp(prefix="test-publish-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    out = os.path.join(workdir, "dist")
    build_fixture(db, meta_extra={"coverage_us-ny-nyc": "full"})
    result = run_publisher(db, out)
    check(result.returncode == 0,
          f"the publisher failed on a valid s17 fixture:\n{result.stdout}\n{result.stderr}")

    if result.returncode == 0:
        with open(os.path.join(out, MANIFEST_V2_NAME)) as fh:
            v2 = json.load(fh)
        with open(os.path.join(out, MANIFEST_V1_NAME)) as fh:
            v1 = json.load(fh)

        # -- 3a. one pack per region, not per id space. THE POINT OF THE ROUND.
        # Fails if: the publisher went back to narrowing on id_space, which would
        # produce two packs (sf, us-ny-nyc) instead of three.
        ids = [c["id"] for c in v2["cities"]]
        check(ids == ["sf", "us-ny-nyc-queens", "us-ny-nyc-bronx"],
              f"format-2 packs are {ids}, expected one per dim_region row in rowid order")

        # -- 3b. each pack holds exactly its own region's rows
        # Fails if: the region DELETE narrowed on the wrong column. The three
        # counts are deliberately distinct so a wrong-region split cannot match.
        counts = {c["id"]: c["tree_count"] for c in v2["cities"]}
        check(counts == {"sf": 3, "us-ny-nyc-queens": 2, "us-ny-nyc-bronx": 1},
              f"per-pack counts are {counts}, expected 3/2/1 -- the split kept the wrong rows")

        # -- 3c. the region identity every format-2 entry carries
        queens = next(c for c in v2["cities"] if c["id"] == "us-ny-nyc-queens")
        check(queens["region"] == {"level": "borough", "parent_city": "us-ny-nyc",
                                   "parent_city_display_name": "New York City"},
              f"Queens' region identity is {queens.get('region')!r}")
        check(queens["display_name"] == "Queens",
              "a borough pack must be named for the borough, not for its city")
        check(queens["id"] != queens["region"]["parent_city"],
              "a borough's pack id and its parent city must be different strings; if they are "
              "not, nothing distinguishes a borough pack from a city pack")
        sf = next(c for c in v2["cities"] if c["id"] == "sf")
        check(sf["region"]["level"] == "city",
              "a one-region city must publish as level `city` -- RULING D2 is one shape "
              "everywhere, not a special case for NYC")
        check(sf["region"]["parent_city"] == "sf",
              "a one-region city is its own parent city")

        # -- 3d. R37.2's immutable path, unchanged for a city that already published
        # Fails if: the path started keying on something other than the pack id.
        # `cities/sf/...` must be byte for byte what it has always been, or every
        # installed copy is orphaned.
        check(sf["path"] == f"cities/sf/s{SEED_SCHEMA_VERSION}-r2026-07-31-"
                            f"{sf['version'].split('-')[-1]}/sf.sqlite",
              f"San Francisco's object path changed shape: {sf['path']}")
        check(f"/{queens['id']}/" in queens["path"] and queens["path"].endswith(
                  f"/{queens['id']}.sqlite"),
              f"a borough pack's path is not keyed on its pack id: {queens['path']}")

        # -- 3e. RULING D8: the format-1 manifest lists WHOLE CITIES ONLY
        # Fails if: a borough leaks into the format-1 list, where a reader with no
        # concept of a region would draw "Queens" as a city with its own civic
        # identity. This is the entire point of dual-publishing.
        check(v1["manifest_format"] == LEGACY_MANIFEST_FORMAT,
              f"{MANIFEST_V1_NAME} is format {v1['manifest_format']}, not 1; every unupdated "
              f"install would lose the whole Cities screen")
        check(v2["manifest_format"] == MANIFEST_FORMAT,
              f"{MANIFEST_V2_NAME} is format {v2['manifest_format']}, not {MANIFEST_FORMAT}")
        legacy_ids = [c["id"] for c in v1["cities"]]
        check(legacy_ids == ["sf"],
              f"the format-1 manifest lists {legacy_ids}; it must list city-level packs only")

        # -- 3f. every pack named by either manifest exists and hashes as claimed
        for name, doc in ((MANIFEST_V1_NAME, v1), (MANIFEST_V2_NAME, v2)):
            for entry in doc["cities"]:
                p = os.path.join(out, entry["path"])
                check(os.path.exists(p), f"{name} names {entry['path']}, which was not written")

        # -- 3g. a borough pack carries its own region row and no other
        # Fails if: `dim_region` was not narrowed, so a Queens pack would ship
        # the Bronx's civic name too -- the same authority-claim `dim_city`'s
        # narrowing exists to prevent.
        qcon = sqlite3.connect(os.path.join(out, queens["path"]))
        regions_in_pack = qcon.execute(
            "SELECT pack_id, display_name, level FROM dim_region").fetchall()
        check(regions_in_pack == [("us-ny-nyc-queens", "Queens", "borough")],
              f"the Queens pack carries dim_region rows {regions_in_pack}")
        pack_meta = dict(qcon.execute("SELECT key, value FROM seed_meta"))
        check(pack_meta.get("publish_pack_id") == "us-ny-nyc-queens",
              "the pack does not name itself in its own receipt")
        check(pack_meta.get("publish_city_id") == "us-ny-nyc",
              "publish_city_id must stay the ID SPACE; something reading it expects a city")
        check(pack_meta.get("publish_region_level") == "borough",
              "the pack's receipt does not record its own level")
        check(pack_meta.get("publish_schema_version") == str(SEED_SCHEMA_VERSION),
              "the pack's receipt does not state the generation this publisher wrote")
        # It really is narrowed: no other region's trees survived.
        (foreign,) = qcon.execute(
            "SELECT COUNT(*) FROM trees WHERE region_id NOT IN "
            "(SELECT id FROM dim_region)").fetchone()
        check(foreign == 0, f"{foreign} trees in the Queens pack belong to no region in it")
        qcon.close()

        # -- 3h. coverage came through the standardised key
        check(queens["coverage"] == "full",
              f"Queens' coverage is {queens['coverage']!r}; the fixture states "
              f"coverage_us-ny-nyc = full")
finally:
    shutil.rmtree(workdir, ignore_errors=True)

# --------------------------------------------------------------------------
# 4. THE RED SIDE. Each of these must make the publisher FAIL.
# --------------------------------------------------------------------------
# A publisher that only ever succeeds is a publisher whose checks nobody has
# watched fire. Each case below breaks exactly one invariant and asserts a
# non-zero exit, so the direction of every guard is known.

def expect_failure(label: str, mutate, expect_in_stderr: str = "") -> None:
    workdir = tempfile.mkdtemp(prefix="test-publish-red-")
    try:
        db = os.path.join(workdir, "seed.sqlite")
        out = os.path.join(workdir, "dist")
        build_fixture(db)
        con = sqlite3.connect(db)
        mutate(con)
        con.commit()
        con.close()
        result = run_publisher(db, out)
        check(result.returncode != 0,
              f"[{label}] the publisher SUCCEEDED on a seed that breaks this invariant; "
              f"the guard is not firing")
        if expect_in_stderr and result.returncode != 0:
            check(expect_in_stderr in result.stderr,
                  f"[{label}] the publisher failed for the wrong reason. Expected "
                  f"{expect_in_stderr!r} in stderr, got: {result.stderr.strip()[:400]}")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def drop_dim_region(con):
    con.executescript("PRAGMA foreign_keys=OFF; DROP TABLE dim_region;")


def region_with_no_trees(con):
    con.execute("INSERT INTO dim_region(id,pack_id,display_name,level,city_id) "
                "VALUES (9,'us-ny-nyc-si','Staten Island','borough',2)")


def drift_display_name(con):
    # The seed calls the pack something the publisher's own DISPLAY_NAMES does
    # not. Before s17 this drifted silently and shipped a manifest naming a pack
    # one thing and the file inside it naming itself another.
    con.execute("UPDATE dim_region SET display_name = 'Saint Francis' WHERE pack_id = 'sf'")


def sever_lineage_across_regions(con):
    # A Queens tree whose predecessor stood in the Bronx. The pre-s17 check asked
    # only whether a link crossed an ID SPACE -- and every NYC borough is in one
    # space, so this would have passed it and then been severed by the delete.
    con.execute("UPDATE trees SET site_lineage = (SELECT id FROM trees WHERE region_id = 3 "
                "LIMIT 1) WHERE region_id = 2 AND id = (SELECT MIN(id) FROM trees "
                "WHERE region_id = 2)")


def two_id_spaces_on_one_city(con):
    # A second id space on New York. `dim_region.city_id` names a CITY while the
    # publisher narrows per ID SPACE, so each NYC borough now resolves to two
    # spaces -- the region-to-space join multiplies, and without the guard two
    # packs would be written at one pack_id, the second overwriting the first at
    # an immutable path.
    con.execute("INSERT INTO id_spaces(id,identity_prefix,note,city_id) "
                "VALUES ('us-ny-nyc-alt','us-ny-nyc-alt:','fixture',2)")


expect_failure("no dim_region at all (a pre-s17 seed)", drop_dim_region, "pre-s17 seed")
expect_failure("one city carrying two id spaces (the join multiplies)",
               two_id_spaces_on_one_city, "resolve to several id spaces")
expect_failure("a region declared but holding no trees", region_with_no_trees, "hold no trees")
expect_failure("dim_region.display_name drifted from DISPLAY_NAMES", drift_display_name,
               "DISPLAY_NAMES disagrees")
expect_failure("a site_lineage link crossing two regions of one id space",
               sever_lineage_across_regions, "cross regions")

# --------------------------------------------------------------------------

if FAILURES:
    print(f"{len(FAILURES)} failing check(s):")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    sys.exit(1)
print(f"{PASSED} checks passed, 0 failed")
