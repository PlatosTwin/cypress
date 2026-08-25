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
    MANIFEST_FORMAT,
    MANIFEST_V2_NAME,
    RETIRED_MANIFEST_V1_NAME,
    SEED_SCHEMA_VERSION,
    coverage_for,
    write_upload_sh,
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
        # The FUSED build's per-inventory claims. Deliberately larger than what
        # any one pack holds -- that is the whole of what test 3i is about.
        "rows_from_sf_city": "999",
        "rows_from_nyc_tree_points": "888",
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
    "us-ny-nyc-staten-island": "Staten Island",
}


class Result:
    """`subprocess.CompletedProcess`'s two fields, from an in-process run."""

    def __init__(self, returncode: int, stdout: str, stderr: str) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def run_publisher(db: str, out: str, names: dict | None = None, *,
                  previous: str = "none", extra: list[str] | None = None) -> Result:
    """Run `publish_cities.main()` in this process, with the fixture's names.

    In-process rather than as a subprocess for one reason that matters: the
    publisher refuses a pack whose display name it was not given, correctly, and
    a subprocess gives no seam to give it one. Every guard under test fires
    AFTER that check, so a subprocess run could only ever observe the name check
    -- which is how the first version of this file reported three failures that
    were all the same guard.

    `previous` is `--previous-manifest`, which the real tool now requires of
    every caller and which is therefore required here too. It defaults to `none`
    -- "this fixture has never published" -- because that is the only value that
    keeps a test off the network. A test that wants the same-day counter passes
    a path to a manifest it wrote itself; nothing in this file may pass `live`.
    """
    argv = sys.argv
    saved = dict(publish_cities.DISPLAY_NAMES)
    out_buf, err_buf = io.StringIO(), io.StringIO()
    code = 0
    try:
        publish_cities.DISPLAY_NAMES.clear()
        publish_cities.DISPLAY_NAMES.update(
            FIXTURE_DISPLAY_NAMES if names is None else names)
        sys.argv = ["publish_cities.py", "--db", db, "--out", out,
                    "--previous-manifest", previous, *(extra or [])]
        with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
            publish_cities.main()
    except SystemExit as exit_:
        code = exit_.code if isinstance(exit_.code, int) else 1
    except BaseException as error:
        # AN UNCAUGHT EXCEPTION IS A FAILURE MODE IN ITS OWN RIGHT AND MUST NOT
        # LOOK LIKE A `fail()`. F1 was exactly this: a `KeyError` escaping the
        # build loop after two packs were on disk. Recorded with its type so a
        # test can tell "refused, with a diagnosis" from "crashed part-way".
        code = 70
        err_buf.write(f"UNCAUGHT {type(error).__name__}: {error}")
    finally:
        sys.argv = argv
        publish_cities.DISPLAY_NAMES.clear()
        publish_cities.DISPLAY_NAMES.update(saved)
    return Result(code, out_buf.getvalue(), err_buf.getvalue())


def packs_written(out: str) -> list[str]:
    """Every .sqlite pack under `out`. The measure that makes "before anything
    is written" checkable rather than asserted."""
    found = []
    for root, _, files in os.walk(out):
        for name in files:
            if name.endswith(".sqlite") and "/seed/" not in os.path.join(root, name):
                found.append(os.path.relpath(os.path.join(root, name), out))
    return sorted(found)


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

# The retired name is still spelled the way the frozen object in the bucket is
# spelled. Fails if: someone "tidied" the constant after retirement -- the guard
# below and the app's archival fallback both name this exact object, and a
# renamed constant would silently stop matching the file it is about.
check(RETIRED_MANIFEST_V1_NAME == "manifest.json",
      f"RETIRED_MANIFEST_V1_NAME is {RETIRED_MANIFEST_V1_NAME!r}; the frozen format-1 "
      f"object in the bucket is named manifest.json and CityDownloader.legacyManifestName "
      f"still fetches that name")
check(not hasattr(publish_cities, "MANIFEST_V1_NAME"),
      "publish_cities still exports MANIFEST_V1_NAME, the name it wrote format 1 under; "
      "retirement means the writable constant is gone, not renamed")
check(not hasattr(publish_cities, "LEGACY_MANIFEST_FORMAT"),
      "publish_cities still exports LEGACY_MANIFEST_FORMAT; nothing emits format 1 any more")

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

        # -- 3e. FORMAT 1 IS RETIRED: the publish writes ONE catalogue.
        # Fails if: `write_manifest_v1` comes back, or a merge restores the
        # `legacy_entries` block. This is the whole subject of the retirement
        # round, and it is an assertion about a FILE the publisher did not write
        # rather than about a flag it set.
        check(v2["manifest_format"] == MANIFEST_FORMAT,
              f"{MANIFEST_V2_NAME} is format {v2['manifest_format']}, not {MANIFEST_FORMAT}")
        written = sorted(f for f in os.listdir(out) if f.endswith(".json"))
        check(written == [MANIFEST_V2_NAME],
              f"the publish wrote {written}; format 1 is retired, so {MANIFEST_V2_NAME} must "
              f"be the only catalogue in the output")
        check(not os.path.exists(os.path.join(out, RETIRED_MANIFEST_V1_NAME)),
              f"{RETIRED_MANIFEST_V1_NAME} was written; the copy in the bucket is FROZEN and "
              f"a fresh one beside it is the artifact that could overwrite it")

        # -- 3f. every pack the manifest names exists
        for entry in v2["cities"]:
            p = os.path.join(out, entry["path"])
            check(os.path.exists(p),
                  f"{MANIFEST_V2_NAME} names {entry['path']}, which was not written")

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

        # -- 3i. rows_from_<inventory> describes THIS PACK, not the fused build
        #
        # A borough is the first pack that holds a strict SUBSET of an
        # inventory's rows. Every pack before New York held all of its
        # inventory's -- one id space, one pack -- so the fused claim and the
        # pack's own count agreed by geometry and `verify_seed` check 1b passed
        # on every pack ever built. Measured on the real Queens pack before the
        # fix: `nyc_tree_points: 298,839 rows, seed_meta says 898,643`.
        #
        # Asserted against the pack's OWN trees rather than against a literal:
        # a literal would be a second statement of the fixture's shape and would
        # be edited alongside whatever broke this.
        qcon = sqlite3.connect(os.path.join(out, queens["path"]))
        pack_meta = dict(qcon.execute("SELECT key, value FROM seed_meta"))
        actual = dict(qcon.execute(
            "SELECT inventory_source, COUNT(*) FROM trees GROUP BY inventory_source"))
        for inventory, n in actual.items():
            claimed = pack_meta.get(f"rows_from_{inventory}")
            check(claimed == str(n),
                  f"the Queens pack claims rows_from_{inventory}={claimed} and holds {n}; "
                  f"a receipt that describes the fused build is false about this file")
        # The other direction: an inventory this pack holds NOTHING from must not
        # keep the fused claim, which would overstate the pack by a whole corpus.
        for key, value in pack_meta.items():
            if not key.startswith("rows_from_"):
                continue
            inventory = key[len("rows_from_"):]
            if inventory not in actual:
                check(value == "0",
                      f"the Queens pack claims {key}={value} for an inventory it holds no "
                      f"rows from")
        check(any(k.startswith("rows_from_") for k in pack_meta),
              "the pack carries no rows_from_* key at all, so the two checks above "
              "asserted nothing")
        qcon.close()
finally:
    shutil.rmtree(workdir, ignore_errors=True)

# --------------------------------------------------------------------------
# 3i. THE DISPLAY-NAME GUARD COVERS BOTH KINDS OF KEY (review finding F1)
# --------------------------------------------------------------------------
# `FIXTURE_DISPLAY_NAMES` above registers `us-ny-nyc` as well as the boroughs,
# which is what a correct registration looks like -- and it is therefore exactly
# the wrong fixture for asking whether the guard NOTICES a missing one. The
# fixture supplied the key, so the suite could not see this class at all.
#
# Fails if: the guard goes back to checking pack ids alone. Measured before the
# fix: `KeyError: 'us-ny-nyc'` escaping the build loop as an uncaught traceback
# AFTER two packs were already on disk.

workdir = tempfile.mkdtemp(prefix="test-publish-f1-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    out = os.path.join(workdir, "dist")
    build_fixture(db)
    # Every PACK registered; the PARENT CITY deliberately withheld.
    result = run_publisher(db, out, names={
        "sf": "San Francisco",
        "us-ny-nyc-queens": "Queens",
        "us-ny-nyc-bronx": "Bronx",
    })
    check(result.returncode != 0,
          "the publisher accepted a run whose parent city has no display name; "
          "`parent_city_display_name` would index DISPLAY_NAMES[space] and raise")
    check("UNCAUGHT" not in result.stderr,
          f"the publisher CRASHED rather than refusing: {result.stderr.strip()[:200]}")
    check("us-ny-nyc" in result.stderr and "display name" in result.stderr,
          f"the refusal does not name the missing key: {result.stderr.strip()[:200]}")
    # THE HALF THAT MAKES THIS A GUARD RATHER THAN A LATE ERROR.
    written = packs_written(out)
    check(written == [],
          f"{len(written)} pack(s) were written before the run refused: {written}. A guard "
          f"that fires after files are on disk leaves a half-populated output tree, and "
          f"R37.2's paths are supposed to be written once.")

    # The calibration: the SAME fixture with the parent city registered publishes
    # fine, so the check above is about the missing name and not about the shape.
    out2 = os.path.join(workdir, "dist2")
    ok = run_publisher(db, out2)
    check(ok.returncode == 0,
          f"the control run failed, so the F1 test proves nothing: {ok.stderr[:200]}")
    check(len(packs_written(out2)) == 3,
          f"the control run wrote {packs_written(out2)}, expected three packs")
finally:
    shutil.rmtree(workdir, ignore_errors=True)


# --------------------------------------------------------------------------
# 3j. THE PARENT CITY'S NAME IS ALSO CHECKED AGAINST THE SEED (review finding N4)
# --------------------------------------------------------------------------
# `DISPLAY_NAMES[pack]` is compared with `dim_region.display_name` (test above,
# and the guard it exercises). `DISPLAY_NAMES[space]` becomes
# `region.parent_city_display_name` on every borough entry and had NO instrument:
# two hand-entered copies of one civic name -- this table and `build_seed`'s
# `DIM_CITY`, which is what the seed's `dim_city` holds -- with nothing comparing
# them.
#
# A drift is not a crash. It publishes: the Cities screen would show one civic
# name over the pack list and a tree profile another, both plausible.
#
# Fails if: the parent-city drift check is removed or narrowed to packs.

workdir = tempfile.mkdtemp(prefix="test-publish-n4-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    build_fixture(db)

    # Every name PRESENT -- this is not F1 again -- but the parent city's name
    # disagrees with the `dim_city` row the fixture wrote ("New York City").
    drifted_names = dict(FIXTURE_DISPLAY_NAMES)
    drifted_names["us-ny-nyc"] = "New York"
    result = run_publisher(db, os.path.join(workdir, "dist"), names=drifted_names)

    check(result.returncode != 0,
          "the publisher accepted a parent-city display name that disagrees with the seed's "
          "own dim_city; every borough entry would publish it as parent_city_display_name")
    check("UNCAUGHT" not in result.stderr,
          f"the publisher CRASHED rather than refusing: {result.stderr.strip()[:200]}")
    check("dim_city" in result.stderr and "parent_city_display_name" in result.stderr,
          f"the refusal does not say which two things disagree or why it matters: "
          f"{result.stderr.strip()[:300]}")
    check("'New York'" in result.stderr and "'New York City'" in result.stderr,
          f"the refusal does not print BOTH names, so an operator cannot tell which copy "
          f"is wrong: {result.stderr.strip()[:300]}")
    check(packs_written(os.path.join(workdir, "dist")) == [],
          "a pack was written before the parent-city drift was refused")

    # The calibration: the same fixture with the names agreeing publishes fine,
    # so the refusal above is about the drift and not about the fixture's shape.
    out2 = os.path.join(workdir, "dist2")
    ok = run_publisher(db, out2)
    check(ok.returncode == 0,
          f"the control run failed, so this test proves nothing: {ok.stderr[:200]}")
    check(len(packs_written(out2)) == 3,
          f"the control run wrote {packs_written(out2)}, expected three packs")
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


def orphan_region_city(con):
    """A region whose dim_city has no id_spaces row (review finding F4).

    The region still HAS trees, and those trees' `id_space` is perfectly legal --
    so nothing is wrong with any tree. Under the inner join this replaced, the
    region was dropped and the orphan check then reported
    `trees carry region_id(s) [3] that dim_region does not declare`, which is a
    false statement: dim_region declares it.
    """
    con.execute("INSERT INTO dim_city VALUES (3,'us-ny-si','Staten Island City','NY',"
                "'Richmond','https://example.invalid/si')")
    con.execute("UPDATE dim_region SET city_id = 3 WHERE pack_id = 'us-ny-nyc-bronx'")


def orphan_region_city_no_trees(con):
    """The same drop, with the region holding no trees.

    This is the half that did not fail at all: exit 0, and `us-ny-nyc-bronx`
    simply never published. A region the seed declares vanished from the
    catalogue with no error anywhere.
    """
    orphan_region_city(con)
    con.execute("DELETE FROM species_assertions")
    con.execute("DELETE FROM trees_rtree WHERE id IN "
                "(SELECT id FROM trees WHERE region_id = 3)")
    con.execute("DELETE FROM trees WHERE region_id = 3")


def partial_coverage_across_several_regions(con):
    """A city with two regions that ships only part of itself (finding F9).

    `coverage` is stated per ID SPACE and every pack of that city inherits it,
    which is exact while a partial city has ONE region and while a multi-region
    city ships all of each. This is both at once: "how much of this pack
    shipped" then has no single answer, and publishing would put one value on
    packs it is true of none of.
    """
    con.execute("INSERT INTO seed_meta(key,value) VALUES ('coverage_us-ny-nyc','downtown')")


def drop_dim_region(con):
    con.executescript("PRAGMA foreign_keys=OFF; DROP TABLE dim_region;")


def region_with_no_trees(con):
    con.execute("INSERT INTO dim_region(id,pack_id,display_name,level,city_id) "
                "VALUES (9,'us-ny-nyc-staten-island','Staten Island','borough',2)")


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
# F4, both directions. The message assertion is the point of the first: it used
# to be a FALSE statement about the data, so "it failed" was not good enough.
expect_failure("a region whose city has no id_spaces row, holding trees",
               orphan_region_city, "no id_spaces row points at")
expect_failure("a region whose city has no id_spaces row, holding NO trees",
               orphan_region_city_no_trees, "no id_spaces row points at")
# F9: the divergence is deliberate, and this is the state it cannot describe.
expect_failure("several regions in one id space AND partial coverage",
               partial_coverage_across_several_regions,
               "coverage is stated per id space and cannot describe these")
expect_failure("a region declared but holding no trees", region_with_no_trees, "hold no trees")
expect_failure("dim_region.display_name drifted from DISPLAY_NAMES", drift_display_name,
               "DISPLAY_NAMES disagrees")
expect_failure("a site_lineage link crossing two regions of one id space",
               sever_lineage_across_regions, "cross regions")

# --------------------------------------------------------------------------
# 4b. F9's CONTROL: partial coverage on a ONE-region city is legal
# --------------------------------------------------------------------------
# The guard above must refuse an ambiguous state, not partial coverage as such.
# San Jose ships `downtown` out of one city-level region today and that is the
# live, correct case -- a guard that also refused it would break the shipping
# publisher. This is what separates the two.

workdir = tempfile.mkdtemp(prefix="test-publish-f9ok-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    out = os.path.join(workdir, "dist")
    build_fixture(db, meta_extra={"coverage_sf": "downtown"})
    result = run_publisher(db, out)
    check(result.returncode == 0,
          f"partial coverage on a ONE-region city was refused; that is San Jose's live shape: "
          f"{result.stderr.strip()[:220]}")
    if result.returncode == 0:
        with open(os.path.join(out, MANIFEST_V2_NAME)) as fh:
            doc = json.load(fh)
        sf = next(c for c in doc["cities"] if c["id"] == "sf")
        check(sf["coverage"] == "downtown",
              f"the one-region city's coverage did not reach its entry: {sf['coverage']!r}")
finally:
    shutil.rmtree(workdir, ignore_errors=True)


# --------------------------------------------------------------------------
# 5. THE F4 MESSAGE MUST BE TRUE, NOT MERELY PRESENT
# --------------------------------------------------------------------------
# `expect_failure` above proves the run refuses. This proves it refuses for the
# right reason and does NOT emit the old false sentence -- a test that only
# checked "non-zero exit" would have passed against the defect.

workdir = tempfile.mkdtemp(prefix="test-publish-f4-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    out = os.path.join(workdir, "dist")
    build_fixture(db)
    con = sqlite3.connect(db)
    con.executescript("PRAGMA foreign_keys=OFF;")
    orphan_region_city(con)
    con.commit()
    con.close()
    result = run_publisher(db, out)
    check("dim_region does not declare" not in result.stderr,
          f"the publisher still blames the trees for a region the join dropped -- dim_region "
          f"DOES declare it: {result.stderr.strip()[:220]}")
    check("The regions ARE declared" in result.stderr,
          f"the refusal does not say which side the fault is on: "
          f"{result.stderr.strip()[:220]}")
    check(packs_written(out) == [],
          f"packs were written before the region resolution failed: {packs_written(out)}")
finally:
    shutil.rmtree(workdir, ignore_errors=True)

# --------------------------------------------------------------------------
# 6. A STALE FORMAT-1 MANIFEST IN --out STOPS THE RUN
# --------------------------------------------------------------------------
# The retirement guard, calibrated in both directions. `--out` is only cleared of
# `cities/`, so a dist/ left over from a dual-publish round still carries that
# round's manifest.json -- and an operator uploading dist/ by hand would rewrite
# the FROZEN object in the bucket with an older truth.
#
# Fails if: the guard is removed, or is turned into a silent cleanup step. Both
# directions are exercised because the passing case here is the entire body of
# section 3 above -- a guard that refused every run would also make section 3 red,
# but a guard that refused NO run would leave section 3 green, and only the first
# half below can tell those apart.

workdir = tempfile.mkdtemp(prefix="test-publish-stale-v1-")
try:
    db = os.path.join(workdir, "seed.sqlite")
    out = os.path.join(workdir, "dist")
    build_fixture(db, meta_extra={"coverage_us-ny-nyc": "full"})

    # -- 6a. RED: a stale format-1 object present, and the run must refuse.
    os.makedirs(out, exist_ok=True)
    stale = os.path.join(out, RETIRED_MANIFEST_V1_NAME)
    with open(stale, "w") as fh:
        json.dump({"manifest_format": 1, "cities": []}, fh)
    result = run_publisher(db, out)
    check(result.returncode != 0,
          "the publisher finished with a retired format-1 manifest.json sitting in --out; "
          "that file is what an operator would upload over the frozen object")
    check(RETIRED_MANIFEST_V1_NAME in result.stderr,
          f"the refusal does not name the offending file: {result.stderr.strip()[:220]}")
    check("frozen" in result.stderr.lower(),
          f"the refusal does not say WHY the stale file matters -- that the bucket's copy is "
          f"frozen: {result.stderr.strip()[:220]}")
    # The diagnosis must match the call site. This file arrived with the operator,
    # so the fix is `rm` -- telling them instead that the publisher is broken sends
    # them to read code that is fine. The two causes have opposite fixes, which is
    # why the message is chosen rather than shared.
    check("THIS RUN WROTE IT" not in result.stderr,
          f"the early guard blamed the publisher for a file the operator brought: "
          f"{result.stderr.strip()[:220]}")
    check(f"rm {stale}" in result.stderr,
          f"the refusal does not give the operator the command that fixes it: "
          f"{result.stderr.strip()[:220]}")
    check(os.path.exists(stale),
          "the guard DELETED the stale manifest instead of refusing; a guard that removes its "
          "own subject can never fail again")

    # -- 6a-ii. A REFUSED RUN WROTE NOTHING.
    # The guard runs before any write for this reason. Refusing only at the end
    # still exits non-zero -- every check above would pass -- while leaving packs,
    # a seed copy and a fresh manifest on disk: a staging directory that looks
    # complete, sitting beside the artifact that made the run illegal. Nothing in
    # 6a can tell those two apart, which is why this is measured separately.
    #
    # Fails if: the early call is removed and only the late one survives.
    check(packs_written(out) == [],
          f"the refused run wrote packs: {packs_written(out)}")
    leftovers = sorted(f for f in os.listdir(out) if f != RETIRED_MANIFEST_V1_NAME)
    check(leftovers == [],
          f"the refused run left {leftovers} in the output directory; a refusal must write "
          f"nothing, or the operator is handed a staging dir that looks publishable")

    # -- 6b. GREEN: remove it, and the identical run succeeds.
    # Without this half, a guard that refused unconditionally would look correct.
    #
    # Guarded rather than a bare `os.remove`: if the guard under test has been
    # turned into a silent cleanup, the file is already gone here and a bare
    # remove raises FileNotFoundError -- killing the run before the summary, so
    # the operator would see a traceback from THIS file instead of 6a's named
    # diagnosis of the actual defect. Found by red-proofing that exact mutation.
    if os.path.exists(stale):
        os.remove(stale)
    result = run_publisher(db, out)
    check(result.returncode == 0,
          f"the same publish failed once the stale file was removed, so the guard is not "
          f"reacting to that file:\n{result.stderr.strip()[:400]}")
    check(not os.path.exists(stale),
          "a format-1 manifest reappeared in --out after a clean run")
finally:
    shutil.rmtree(workdir, ignore_errors=True)


# --------------------------------------------------------------------------
# 6c. THE LATE SITE'S DIAGNOSIS, ASSERTED POSITIVELY
# --------------------------------------------------------------------------
# Everything above pins the late message only NEGATIVELY -- 6a asserts the early
# refusal does *not* say "THIS RUN WROTE IT". Replacing the whole `when="after"`
# cause string with garbage therefore left the suite green: the swap red-proof
# only fails because swapping makes the EARLY site emit the after-text, which
# says nothing about whether that text is still correct. Adversarial review found
# this; the check below is the positive half.
#
# Called directly rather than through a publish, because the shipping publisher
# cannot reach the late refusal -- that is the whole point of the early guard.
# The only way to exercise the second call site is to call it.
#
# Fails if: the after-branch stops naming what the operator must do -- that this
# run produced the file, which file to fix, and that deleting it is the wrong
# move. Those three are the difference between the two diagnoses, and sending an
# operator to `rm` a file the publisher will just rewrite is the failure this
# prevents.
probe_dir = tempfile.mkdtemp(prefix="test-publish-late-msg-")
try:
    with open(os.path.join(probe_dir, RETIRED_MANIFEST_V1_NAME), "w") as fh:
        json.dump({"manifest_format": 1, "cities": []}, fh)

    captured, exit_code = io.StringIO(), None
    with contextlib.redirect_stderr(captured):
        try:
            publish_cities.assert_no_legacy_manifest(probe_dir, when="after")
        except SystemExit as exc:
            exit_code = exc.code
    late_msg = captured.getvalue()

    check(exit_code == 1,
          f"the late guard exited {exit_code!r}, not 1; a self-write regression must fail the "
          f"run that produced the file")
    check("THIS RUN WROTE IT" in late_msg,
          f"the late refusal does not say the run itself wrote the file: {late_msg.strip()[:220]}")
    check("Tools/publish_cities.py" in late_msg,
          f"the late refusal does not name the file to fix: {late_msg.strip()[:220]}")
    check("fix the publisher" in late_msg,
          f"the late refusal does not tell the operator to fix the publisher rather than delete "
          f"and re-run: {late_msg.strip()[:220]}")
    check(RETIRED_MANIFEST_V1_NAME in late_msg,
          f"the late refusal does not name the offending file: {late_msg.strip()[:220]}")

    # Mutual exclusivity, stated from this side too: the late message must not
    # carry the EARLY site's cause. Without this, widening both branches to one
    # string containing every phrase would satisfy every check above.
    check("left over from an earlier round" not in late_msg,
          f"the late refusal carries the early site's diagnosis, so the two are no longer "
          f"distinguishable: {late_msg.strip()[:220]}")
finally:
    shutil.rmtree(probe_dir, ignore_errors=True)


# --------------------------------------------------------------------------
# 7. upload.sh NEVER TOUCHES THE RETIRED OBJECT
# --------------------------------------------------------------------------
# The publisher not WRITING format 1 and the upload script not UPLOADING it are
# two different properties, and only the second one can overwrite the frozen copy
# in the bucket. `write_upload_sh` was documented as extracted so it could be
# exercised directly (#248) and until this round nothing exercised it.

upload_dir = tempfile.mkdtemp(prefix="test-publish-upload-")
try:
    fake_entries = [
        {"id": "sf", "path": "cities/sf/s17-r2026-08-22-abcd1234/sf.sqlite"},
        {"id": "us-ny-nyc-queens",
         "path": "cities/us-ny-nyc-queens/s17-r2026-08-22-abcd1234/us-ny-nyc-queens.sqlite"},
    ]
    script_path = write_upload_sh(upload_dir, fake_entries, "seed/abcd1234/cypress-seed.sqlite")
    with open(script_path) as fh:
        script = fh.read()

    # Fails if: the legacy manifest is uploaded or verified again. Checked against
    # the whole script rather than one line, because either an `aws s3 cp` or a
    # `curl ... | cmp` naming it would be a write or a claim about the frozen file.
    offending = [ln for ln in script.splitlines()
                 if RETIRED_MANIFEST_V1_NAME in ln and "manifest-v2.json" not in ln]
    check(offending == [],
          f"upload.sh still references the retired {RETIRED_MANIFEST_V1_NAME}: {offending}")

    # Calibration: the same search DOES find the live manifest, so an empty result
    # above means "absent" rather than "the search matches nothing".
    v2_lines = [ln for ln in script.splitlines() if MANIFEST_V2_NAME in ln]
    check(len(v2_lines) >= 2,
          f"upload.sh does not both upload and verify {MANIFEST_V2_NAME}; the check above "
          f"cannot be trusted to find a filename at all. Found: {v2_lines}")

    # R37.2's ordering: every immutable file lands before the mutable catalogue
    # that names it. Fails if: the manifest upload drifts above the pack uploads.
    cp_lines = [ln for ln in script.splitlines() if ln.startswith("aws s3 cp")]
    check(MANIFEST_V2_NAME in cp_lines[-1],
          f"the manifest is not the LAST object uploaded; a reader could see a catalogue "
          f"naming files that are not there yet. Last cp: {cp_lines[-1]!r}")
    check(len(cp_lines) == len(fake_entries) + 2,
          f"upload.sh uploads {len(cp_lines)} objects for {len(fake_entries)} packs; expected "
          f"one per pack plus the seed plus one manifest")
finally:
    shutil.rmtree(upload_dir, ignore_errors=True)


# --------------------------------------------------------------------------
# 8. SAME-DAY REPUBLISH: content_rev MUST ADVANCE
# --------------------------------------------------------------------------
# The defect, in one sentence: the corrective republish of 2026-08-22 reused
# content_rev "2026-08-22", and `CityInstallState.installedIsCurrent` compares
# content_rev + schema_version whenever the version strings differ -- so every
# device from the superseded publish was judged current and never offered the
# fix. Owner-confirmed from a live device, 2026-08-24.
# --------------------------------------------------------------------------

# -- 8a. THE ORDERING PROPERTY THE APP RELIES ON, PINNED AS STRING COMPARISONS.
#
# Two comparisons, and only two, are made on this value by the app:
#
#   equality      CityInstallState.swift:196   installedContentRev == publishedContentRev
#   strictly `>`  CityInstallState.swift:161   publishedRev > bundledRev
#
# Swift's `<`/`>` on `String` and Python's on `str` are both lexicographic over
# Unicode scalars, and every character here is ASCII, so these assertions are the
# app's assertions. Fails if: the counter format stops sorting in publish order.
#
# THE SEQUENCE IS GENERATED BY THE FORMATTER, NOT TYPED OUT. A hand-written list
# of well-ordered strings proves that Python sorts strings, which nothing here
# doubts; it goes green no matter what the publisher emits. Asking
# `format_content_rev` for every revision of two adjacent record dates is what
# makes an un-padded counter -- or any other reformatting -- show up as red.
ORDERED = (
    [publish_cities.format_content_rev("2026-08-22", n)
     for n in range(1, publish_cities.REV_COUNTER_MAX + 1)]
    + [publish_cities.format_content_rev("2026-08-23", n)
       for n in range(1, publish_cities.REV_COUNTER_MAX + 1)]
)
check(len(ORDERED) == 2 * publish_cities.REV_COUNTER_MAX and ORDERED[0] == "2026-08-22",
      f"the generated sequence is not what this check thinks it is: {ORDERED[:3]}... "
      f"({len(ORDERED)} entries)")
out_of_order = [(a, b) for a, b in zip(ORDERED, ORDERED[1:]) if not a < b]
check(out_of_order == [],
      f"the published revision sequence is not in lexicographic order: {out_of_order}. "
      f"CityInstallState's `.bundledOutdated` branch compares these as STRINGS, so an "
      f"inversion here is a Download button that is not drawn (or is drawn backwards).")

# The two specific pairs the defect and its near-miss turn on, stated separately
# so a failure names which property broke rather than pointing at a zip.
check("2026-08-22.02" != "2026-08-22",
      "a same-day republish must not compare EQUAL to the publish it corrects -- that "
      "equality IS the defect (installedIsCurrent returns true and no update is offered)")
check("2026-08-22" < "2026-08-22.02",
      "a counter must sort AFTER the bare date it extends")
check("2026-08-22.02" < "2026-08-23",
      "a counter must sort BEFORE the next record date, or a genuinely newer inventory "
      "would look older than a same-day correction")
check("2026-08-22.02" < "2026-08-22.10",
      "the tenth same-day publish must sort after the second")

# CALIBRATION, AND THE REASON THE FORMAT IS NOT WHAT THE DECISION'S EXAMPLE SAID.
# The un-padded form the worked example used (`2026-08-22.2`) passes every check
# above except this one, and fails it silently at the tenth publish. If this
# assertion ever stops holding, the checks above have stopped measuring anything.
check("2026-08-22.10" < "2026-08-22.2",
      "UNPADDED counters were expected to sort WRONG ('...10' < '...2'); if they now "
      "sort correctly then string comparison is not doing what every check in this "
      "section assumes, and the padded format's justification is void")

# -- 8b. split/format round-trip, and the ceiling that is a refusal not a wrap.
# Fails if: the parser and the formatter stop being inverses, or `.100` becomes
# emittable -- it would sort below `.99` and re-open the defect from the far end.
for rev, expected in [("2026-08-22", ("2026-08-22", 1)),
                      ("2026-08-22.02", ("2026-08-22", 2)),
                      ("2026-08-22.99", ("2026-08-22", 99))]:
    got = publish_cities.split_content_rev(rev)
    check(got == expected, f"split_content_rev({rev!r}) == {got!r}, expected {expected!r}")
    check(publish_cities.format_content_rev(*got) == rev,
          f"format_content_rev{got!r} did not round-trip back to {rev!r}")

check(publish_cities.format_content_rev("2026-08-22", 1) == "2026-08-22",
      "counter 1 is the bare date -- there is no `.01`")

with contextlib.redirect_stderr(io.StringIO()) as ceiling_err:
    ceiling_code = 0
    try:
        publish_cities.format_content_rev("2026-08-22", 100)
    except SystemExit as exit_:
        ceiling_code = exit_.code
check(ceiling_code == 1 and "sort" in ceiling_err.getvalue(),
      f"the 100th same-day publish must be refused, not emitted as `.100` (which sorts "
      f"below `.99`). Got exit {ceiling_code}, stderr {ceiling_err.getvalue()!r}")

# Calibration for the check above: 99 is NOT refused, so the refusal is about the
# ceiling and not about the function raising on everything.
check(publish_cities.format_content_rev("2026-08-22", 99) == "2026-08-22.99",
      "99 must still be emittable; if it is not, the ceiling check above proves nothing")

# -- 8c. bump_content_rev, case by case.
# `previous` is a manifest entry as the live catalogue holds one.
LIVE = {"id": "sf", "content_rev": "2026-08-22", "version": "s17-r2026-08-22-4f6ebaaa",
        "sha256": "a" * 64}


def bump(previous, derived="2026-08-22", build="ac7b1ccc", republish=False):
    return publish_cities.bump_content_rev(
        pack="sf", derived=derived, previous=previous, build_id=build,
        schema_version=17, republish=republish)


# 1. never published -> the derived date, untouched.
check(bump(None) == "2026-08-22",
      "a pack that has never published must publish under its derived date")

# 2. the record date advanced -> the date distinguishes them; no counter.
check(bump({**LIVE, "content_rev": "2026-08-22.02",
            "version": "s17-r2026-08-22.02-4f6ebaaa"}, derived="2026-08-23")
      == "2026-08-23",
      "a genuinely newer record date must reset to the bare date, not keep counting")

# 3. THE DEFECT'S OWN SHAPE: same date, different source seed -> the counter.
# This is the exact pair the owner observed: 4f6ebaaa live, ac7b1ccc being
# published, both deriving 2026-08-22. Fails if: the publisher reuses the rev,
# which is what shipped and what left every 4f6ebaaa device stuck.
check(bump(LIVE) == "2026-08-22.02",
      "a same-day republish from a DIFFERENT source seed must advance content_rev; "
      "reusing it is the defect of 2026-08-22")
# ...and it keeps counting from wherever the live catalogue already is.
check(bump({**LIVE, "content_rev": "2026-08-22.02",
            "version": "s17-r2026-08-22.02-4f6ebaaa"}) == "2026-08-22.03",
      "the counter must continue from the live value, not restart at 02")

# 4. Same date, same source seed, no --republish -> a REPRODUCTION.
# The determinism promise in publish_cities.py's header depends on this: two runs
# over the same seed produce the same version and therefore the same path.
check(bump(LIVE, build="4f6ebaaa") == "2026-08-22",
      "re-running the publisher over the ALREADY-PUBLISHED seed must reproduce the live "
      "revision exactly -- bumping here would republish identical bytes at a new path "
      "and offer every device an update to what it already holds")

# 5. --republish forces case 4 to advance. THIS ROUND'S REMEDY: the corrected
# bytes are already live at ac7b1ccc, and the devices that need reaching are the
# ones from 4f6ebaaa, so nothing derived from the seed can ask for the bump.
check(bump(LIVE, build="4f6ebaaa", republish=True) == "2026-08-22.02",
      "--republish must advance the revision even when the source seed is unchanged")

# 6. The record date going BACKWARDS is refused, not counted.
with contextlib.redirect_stderr(io.StringIO()) as back_err:
    back_code = 0
    try:
        bump(LIVE, derived="2026-08-21")
    except SystemExit as exit_:
        back_code = exit_.code
check(back_code == 3 and "backwards" in back_err.getvalue(),
      f"a seed built from an OLDER upstream snapshot than the live publish must stop the "
      f"run. Got exit {back_code}, stderr {back_err.getvalue()!r}")

# 7. A previous rev whose suffix this tool did not write is refused rather than
# ordered by guesswork.
with contextlib.redirect_stderr(io.StringIO()) as shape_err:
    shape_code = 0
    try:
        publish_cities.split_content_rev("2026-08-22.beta")
    except SystemExit as exit_:
        shape_code = exit_.code
check(shape_code == 3 and "not a counter" in shape_err.getvalue(),
      f"an unrecognised revision suffix must stop the run. Got exit {shape_code}, "
      f"stderr {shape_err.getvalue()!r}")


# -- 8d/8e/8f/8g. The same behaviour end to end, through `main()`.
def iso_day(value: str) -> bool:
    """`InventorySource.date(fromISODay:)`, transliterated.

    The Swift side is a `DateFormatter` pinned to `yyyy-MM-dd` and POSIX --
    "deliberately strict and deliberately not ISO8601DateFormatter", says its own
    note at InventorySource.swift:136. `datetime.strptime(..., "%Y-%m-%d")` is
    the same contract: it accepts a bare calendar day and rejects trailing text.
    """
    from datetime import datetime as _dt
    try:
        _dt.strptime(value, "%Y-%m-%d")
        return True
    except ValueError:
        return False


# CALIBRATE THE INSTRUMENT BEFORE TRUSTING IT. `iso_day` is about to be the whole
# evidence for "the app can still parse this key", so it is run first against one
# value whose answer is known in each direction. Without this, an `iso_day` that
# returned True for everything would certify the very thing it is checking for.
check(iso_day("2026-07-31"),
      "iso_day rejects a plain calendar day, so it cannot certify anything below")
check(not iso_day("2026-07-31.02"),
      "iso_day ACCEPTS a suffixed revision, so the check that trees_snapshot_on stayed "
      "parseable would pass no matter what the publisher wrote -- exactly the "
      "green-guard failure this project keeps paying for")


def pack_meta(out_dir: str, entry: dict) -> dict:
    """`seed_meta` as the published pack itself holds it -- read off the artifact,
    not off the manifest that describes it."""
    con = sqlite3.connect(os.path.join(out_dir, entry["path"]))
    try:
        return dict(con.execute("SELECT key, value FROM seed_meta"))
    finally:
        con.close()


revdir = tempfile.mkdtemp(prefix="test-publish-rev-")
try:
    first_db = os.path.join(revdir, "seed-1.sqlite")
    first_out = os.path.join(revdir, "dist-1")
    build_fixture(first_db, meta_extra={"coverage_us-ny-nyc": "full"})
    first = run_publisher(first_db, first_out, previous="none")
    check(first.returncode == 0,
          f"the first publish failed:\n{first.stdout}\n{first.stderr}")

    first_manifest = os.path.join(first_out, MANIFEST_V2_NAME)
    with open(first_manifest) as fh:
        m1 = json.load(fh)
    revs1 = {c["id"]: c["content_rev"] for c in m1["cities"]}
    check(revs1 == {"sf": "2026-07-31", "us-ny-nyc-queens": "2026-07-28",
                    "us-ny-nyc-bronx": "2026-07-28"},
          f"a first publish must carry the bare derived dates; got {revs1}")

    # -- 8d. A SECOND PUBLISH OF DIFFERENT CONTENT ON THE SAME RECORD DATE.
    # The fixture's snapshot dates are untouched -- only an unrelated seed_meta
    # key differs -- so `content_rev_for` derives exactly what is already live.
    # That is the 4f6ebaaa/ac7b1ccc shape: different bytes, same record date.
    second_db = os.path.join(revdir, "seed-2.sqlite")
    second_out = os.path.join(revdir, "dist-2")
    build_fixture(second_db, meta_extra={"coverage_us-ny-nyc": "full",
                                         "an_unrelated_receipt_key": "changed"})
    second = run_publisher(second_db, second_out, previous=first_manifest)
    check(second.returncode == 0,
          f"the corrective republish failed:\n{second.stdout}\n{second.stderr}")

    with open(os.path.join(second_out, MANIFEST_V2_NAME)) as fh:
        m2 = json.load(fh)
    revs2 = {c["id"]: c["content_rev"] for c in m2["cities"]}
    check(revs2 == {"sf": "2026-07-31.02", "us-ny-nyc-queens": "2026-07-28.02",
                    "us-ny-nyc-bronx": "2026-07-28.02"},
          f"a same-day republish of different content must advance every pack's "
          f"content_rev; got {revs2}")

    # The property the app actually consumes: the two catalogue entries must not
    # compare equal, because equality is what withholds the update.
    stuck = [c["id"] for c in m2["cities"] if revs2[c["id"]] == revs1[c["id"]]]
    check(stuck == [],
          f"packs {stuck} republished at a content_rev equal to the live one; a device "
          f"holding the superseded publish would be judged current and never offered "
          f"the correction (CityInstallState.swift:196)")

    # And the paths must differ, or the new bytes would overwrite an object R37.2
    # promises is written once.
    paths1 = {c["id"]: c["path"] for c in m1["cities"]}
    paths2 = {c["id"]: c["path"] for c in m2["cities"]}
    collided = [i for i in paths1 if paths1[i] == paths2[i]]
    check(collided == [],
          f"packs {collided} would republish to the same immutable path: {[paths1[i] for i in collided]}")

    # -- 8e. THE LOAD-BEARING SEPARATION, ASSERTED ON THE PUBLISHED ARTIFACT.
    #
    # This is why the ruling's "no app change" holds. The counter goes where the
    # app COMPARES (`publish_content_rev`, and the manifest's `content_rev`) and
    # never where the app PARSES (`trees_snapshot_on`). Two app sites parse it:
    #
    #   InventorySource.swift:101  snapshotDate = date(fromISODay: trees_snapshot_on)
    #   DataGates.swift:1420       the seed contract expects that to be non-nil,
    #                              naming this key in its failure message
    #
    # Fails if: the publisher goes back to writing `rev` into `trees_snapshot_on`.
    # Measured consequence of that regression: every published pack fails the seed
    # contract gate, and the city-record provenance line loses its date.
    for entry in m2["cities"]:
        pmeta = pack_meta(second_out, entry)
        check(iso_day(pmeta["trees_snapshot_on"]),
              f"{entry['id']}: seed_meta.trees_snapshot_on is "
              f"{pmeta['trees_snapshot_on']!r}, which the app cannot parse as a calendar "
              f"day -- InventorySource.snapshotDate goes nil and DataGates' seed contract "
              f"fails on every published pack")
        check(pmeta["publish_content_rev"] == entry["content_rev"],
              f"{entry['id']}: the file says publish_content_rev "
              f"{pmeta['publish_content_rev']!r} and the manifest says content_rev "
              f"{entry['content_rev']!r}. installedIsCurrent compares exactly these two "
              f"across the file/manifest boundary, so a disagreement makes every device "
              f"look out of date forever")
        # The pair that proves the separation is real rather than incidental:
        # on a republished pack these two keys must DIFFER.
        check(pmeta["trees_snapshot_on"] != pmeta["publish_content_rev"],
              f"{entry['id']}: trees_snapshot_on and publish_content_rev are both "
              f"{pmeta['trees_snapshot_on']!r} on a REPUBLISHED pack. They are equal only "
              f"until a counter appears; if they are still equal here the counter never "
              f"reached the key the app versions on")

    # Calibration for the check above: on the FIRST publish the two keys are
    # legitimately equal, so "they differ" is a fact about the republish and not
    # about the publisher always writing two different strings.
    first_meta = pack_meta(first_out, m1["cities"][0])
    check(first_meta["trees_snapshot_on"] == first_meta["publish_content_rev"],
          "on a first publish the record date and the revision must be the same string; "
          "if they already differ, the inequality asserted above measures nothing")

    # -- 8f. DETERMINISM: republishing the SAME seed over its own manifest is a
    # reproduction, not a new revision. Fails if: the bump fires on identical
    # content, which would offer every device an update to bytes it already holds
    # -- the exact tester report that CityInstallState's fallback exists to stop.
    same_out = os.path.join(revdir, "dist-same")
    same = run_publisher(first_db, same_out, previous=first_manifest)
    check(same.returncode == 0, f"the reproduction run failed:\n{same.stderr}")
    with open(os.path.join(same_out, MANIFEST_V2_NAME)) as fh:
        m_same = json.load(fh)
    revs_same = {c["id"]: c["content_rev"] for c in m_same["cities"]}
    check(revs_same == revs1,
          f"re-publishing the already-live seed changed content_rev from {revs1} to "
          f"{revs_same}; a reproduction must reproduce")
    shas_same = {c["id"]: c["sha256"] for c in m_same["cities"]}
    shas1 = {c["id"]: c["sha256"] for c in m1["cities"]}
    check(shas_same == shas1,
          "the reproduction produced different bytes, so the determinism this test "
          "depends on does not hold and 8f proves nothing")

    # -- 8g. --republish ADVANCES THE SAME SEED. This round's own operation: the
    # corrected data is already live and identical, and the devices that need
    # reaching came from a publish that is no longer in the catalogue at all.
    forced_out = os.path.join(revdir, "dist-forced")
    forced = run_publisher(first_db, forced_out, previous=first_manifest,
                           extra=["--republish"])
    check(forced.returncode == 0, f"the --republish run failed:\n{forced.stderr}")
    with open(os.path.join(forced_out, MANIFEST_V2_NAME)) as fh:
        m_forced = json.load(fh)
    revs_forced = {c["id"]: c["content_rev"] for c in m_forced["cities"]}
    check(revs_forced == {"sf": "2026-07-31.02", "us-ny-nyc-queens": "2026-07-28.02",
                          "us-ny-nyc-bronx": "2026-07-28.02"},
          f"--republish over an identical seed must advance every revision; got "
          f"{revs_forced}")

    # -- 8h. --previous-manifest IS REQUIRED. A publish that does not state what
    # it is following cannot make this check at all, and a DEFAULT would make the
    # guard silently absent for the operator who runs the tool the way they always
    # have. Fails if: the argument acquires a default.
    argv_saved = sys.argv
    missing_code = 0
    missing_err = io.StringIO()
    try:
        sys.argv = ["publish_cities.py", "--db", first_db,
                    "--out", os.path.join(revdir, "dist-nomanifest")]
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(missing_err):
            publish_cities.main()
    except SystemExit as exit_:
        missing_code = exit_.code if isinstance(exit_.code, int) else 1
    finally:
        sys.argv = argv_saved
    check(missing_code == 2 and "previous-manifest" in missing_err.getvalue(),
          f"a publish with no --previous-manifest must be refused by argparse. Got exit "
          f"{missing_code}, stderr {missing_err.getvalue()!r}")

    # -- 8i. --republish with nothing to republish over is a contradiction.
    contradiction = run_publisher(first_db, os.path.join(revdir, "dist-contradiction"),
                                  previous="none", extra=["--republish"])
    check(contradiction.returncode == 3
          and "no previous publish" in contradiction.stderr,
          f"--republish with --previous-manifest none must be refused. Got exit "
          f"{contradiction.returncode}, stderr {contradiction.stderr!r}")

    # -- 8j. R37.2 WRITE-ONCE, ASSERTED AGAINST THE ARTIFACT. If the previous
    # catalogue names this exact version with DIFFERENT bytes, the run stops
    # rather than rewriting an immutable object. Unreachable by construction
    # today -- the version carries the source seed's hash, so equal versions
    # imply equal bytes -- which is precisely why it is exercised here: a
    # backstop that has never been seen to fire is a backstop nobody has tested.
    lying = json.loads(json.dumps(m1))
    for city in lying["cities"]:
        city["sha256"] = "0" * 64
    lying_path = os.path.join(revdir, "lying-manifest.json")
    with open(lying_path, "w") as fh:
        json.dump(lying, fh)
    caught = run_publisher(first_db, os.path.join(revdir, "dist-lying"),
                           previous=lying_path)
    check(caught.returncode == 1 and "write-once" in caught.stderr,
          f"a previous manifest claiming different bytes at this run's own version must "
          f"stop the publish. Got exit {caught.returncode}, stderr {caught.stderr!r}")
finally:
    shutil.rmtree(revdir, ignore_errors=True)


# --------------------------------------------------------------------------

if FAILURES:
    print(f"{len(FAILURES)} failing check(s):")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    sys.exit(1)
print(f"{PASSED} checks passed, 0 failed")
