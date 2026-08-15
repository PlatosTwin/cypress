#!/usr/bin/env python3
"""Tests for what a `species_map` row claims about a qSpecies STRING.

    python3 Tools/test_seed_species_map.py

Every test here builds a real seed from a synthetic corpus of a dozen rows,
through the real `build()`, and reads the real `species_map` table out of it.
That is deliberate and it is the point: the defect these guard against
(<errata-pending/species-map-string-kind>) lived in the aggregation *inside*
`build`, and a test that called the classifier directly would have gone green
while the build still crashed. The corpus is San Jose-shaped because San Jose is
the source that separates vacancy from species; San Francisco cannot express the
defect at all, which is why it went eight months unseen.

Every test states what would have to go wrong for it to fail, because a test
whose failure mode nobody can name is a test nobody will fix correctly.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from build_seed import ENRICHED_COLUMNS, build  # noqa: E402

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


# A point inside San Jose's bounding box, and one inside San Francisco's. Both
# are real coordinates from the cached layers, so `accepts`' bbox test sees the
# same shape of number it sees in a full build.
SJ_LON, SJ_LAT = -121.758019, 37.237292
SF_LON, SF_LAT = -122.468983, 37.786610

#: `Fixtures/raw/street_tree_list.csv`'s first line, verbatim.
DATASF_HEADER = (
    "TreeID,qLegalStatus,qSpecies,qAddress,SiteOrder,qSiteInfo,PlantType,qCaretaker,"
    "qCareAssistant,PlantDate,DBH,PlotSize,PermitNotes,XCoord,YCoord,Latitude,Longitude,"
    "Location,Fire Prevention Districts,Police Districts,Supervisor Districts,Zip Codes,"
    "Neighborhoods (old),Analysis Neighborhoods"
)


def sj_row(facility_id, species, vacant, object_id):
    """One San Jose feature, in the layer's own spelling.

    `VACANTSITE` and `NAMESCIENTIFIC` are separate fields here, which is the
    whole reason this file exists: the layer can and does say "this site is
    empty" and "the species is Magnolia" on one row.
    """
    return {
        "attributes": {
            "OBJECTID": object_id,
            "FACILITYID": str(facility_id),
            "NAMESCIENTIFIC": species,
            "TRUNKDIAM": 0,
            "INSTALLDATE": None,
            "CONDITION": None,
            "ADDRESSNUM": "1",
            "STREETNAME": "TEST ST",
            "GROWSPACE": "Park Strip",
            "SPACEWIDTH": "4",
            "VACANTSITE": vacant,
            "OWNEDBY": "San Jose",
            "MAINTBY": "General Fund",
        },
        # Each row gets its own coordinate so no two land on one point.
        "geometry": {"x": SJ_LON + object_id * 1e-5, "y": SJ_LAT + object_id * 1e-5},
    }


def write_corpus(root, sj_rows):
    """A repo-root holding the smallest corpus `build(source="city")` accepts."""
    raw = os.path.join(root, "Fixtures", "raw")
    os.makedirs(raw, exist_ok=True)
    os.makedirs(os.path.join(root, "Fixtures", "seed"), exist_ok=True)

    # The DataSF export's own header, with no rows under it. Two readers want
    # different subsets of it -- `load_datasf_attributes` the enrichment
    # columns, `SFDataSFAdapter` the geometry and species ones -- so the header
    # is spelled in full rather than assembled from either one's list.
    with open(os.path.join(raw, "street_tree_list.csv"), "w", encoding="utf-8") as fh:
        fh.write(DATASF_HEADER + "\n")
    missing = set(ENRICHED_COLUMNS) - set(DATASF_HEADER.split(","))
    assert not missing, f"DATASF_HEADER has fallen behind ENRICHED_COLUMNS: {sorted(missing)}"

    # The seed's authored species content, empty. These tests are about which
    # STRING maps to which species, and the fixtures add family, leaf retention
    # and field-guide prose to a species already minted -- they cannot change a
    # `species_map` row. Empty keeps the corpus's species catalogue exactly the
    # rows under test.
    os.makedirs(os.path.join(root, "Fixtures", "species"), exist_ok=True)
    for fixture in ("leaf_retention.yaml", "curated.yaml"):
        with open(os.path.join(root, "Fixtures", "species", fixture), "w",
                  encoding="utf-8") as fh:
            fh.write("species: []\n")

    city = [{
        "TREEID": 1, "OBJECTID": 1, "Address": "1 TEST ST", "SiteOrder": 1,
        "COMMON": "Monterey Pine", "BOTANICAL": "Pinus radiata", "DBH": 3,
        "Latitude": SF_LAT, "Longitude": SF_LON, "PlantType": "Tree",
    }]
    with open(os.path.join(raw, "city_street_trees.ndjson"), "w", encoding="utf-8") as fh:
        for row in city:
            fh.write(json.dumps(row) + "\n")
    with open(os.path.join(raw, "city_street_trees.meta.json"), "w", encoding="utf-8") as fh:
        json.dump({"rows_written": len(city), "extracted_on": "2026-07-31",
                   "server_last_edit_date": "2026-07-20"}, fh)

    with open(os.path.join(raw, "sj_street_trees.ndjson"), "w", encoding="utf-8") as fh:
        for row in sj_rows:
            fh.write(json.dumps(row) + "\n")
    with open(os.path.join(raw, "sj_street_trees.meta.json"), "w", encoding="utf-8") as fh:
        json.dump({"rows_written": len(sj_rows), "extracted_on": "2026-07-31"}, fh)


def species_map_of(sj_rows):
    """Build a seed from `sj_rows` and return its `species_map`, keyed by string.

    Returns `("crash", exception)` instead of a mapping when the build raises,
    so a test can name the failure rather than taking the whole run down with
    it. The build that this file exists for raised `sqlite3.IntegrityError`.
    """
    with tempfile.TemporaryDirectory() as root:
        write_corpus(root, sj_rows)
        try:
            # The build narrates ~60 lines per run; the tests read the database,
            # not the narration.
            with contextlib.redirect_stdout(io.StringIO()):
                build(root, do_fetch=False, limit=0, with_city_raw=False,
                      source="city", sj_extent="full")
        except Exception as exc:  # noqa: BLE001
            return "crash", exc
        db = os.path.join(root, "Fixtures", "seed", "cypress-seed.sqlite")
        conn = sqlite3.connect(db)
        try:
            rows = conn.execute(
                "SELECT qspecies_string, species_id, species_uuid, confidence, "
                "is_stub, is_placeholder, is_non_taxon, tree_count FROM species_map"
            ).fetchall()
        finally:
            conn.close()
        return {row[0]: row[1:] for row in rows}


def row_of(species_map, string, test_name):
    """`species_map[string]`, or None with the reason recorded."""
    if isinstance(species_map, tuple):
        check(False, f"{test_name}: the build raised "
                     f"{type(species_map[1]).__name__}: {species_map[1]}")
        return None
    if string not in species_map:
        check(False, f"{test_name}: no species_map row for {string!r}; "
                     f"the corpus holds {sorted(species_map)}")
        return None
    return species_map[string]


# Column positions in the tuple `species_map_of` returns.
SPECIES_ID, SPECIES_UUID, CONFIDENCE, IS_STUB, IS_PLACEHOLDER, IS_NON_TAXON, TREE_COUNT = range(7)


def test_a_string_on_an_empty_site_and_on_a_tree_still_names_its_species():
    """FAILS IF: a string that resolved to a species is filed as a placeholder.

    THE DEFECT THIS FILE WAS WRITTEN FOR. San Jose's `VACANTSITE` field marks a
    site empty while `NAMESCIENTIFIC` still names what stood there, so `Magnolia`
    arrives on 2 empty sites and 77 living trees in the real layer. The empty
    site is listed FIRST here because that is the order that crashed: the row
    took its kind from whichever record reached the string first, so it claimed
    a species AND `is_placeholder = 1`, and `species_map`'s own CHECK refuses
    that pair. `--source city --sj-extent full` did not build at all.
    """
    name = "test_a_string_on_an_empty_site_and_on_a_tree_still_names_its_species"
    rows = [
        sj_row(1, "Magnolia", "Yes", 1),   # the empty site, first
        sj_row(2, "Magnolia", "No", 2),
        sj_row(3, "Magnolia", "No", 3),
    ]
    row = row_of(species_map_of(rows), "Magnolia", name)
    if row is None:
        return
    check(row[SPECIES_ID] is not None,
          f"{name}: 'Magnolia' carries no species_id though two trees resolved it")
    check(row[IS_PLACEHOLDER] == 0,
          f"{name}: 'Magnolia' is filed as a vacant-site placeholder, but two "
          f"living trees carry it")
    check(row[IS_NON_TAXON] == 0, f"{name}: 'Magnolia' is filed as naming no taxon")
    check(row[CONFIDENCE] > 0.0,
          f"{name}: 'Magnolia' resolved to a species at confidence "
          f"{row[CONFIDENCE]}, which is the empty site's confidence and not the "
          f"resolution's")


def test_a_species_map_row_does_not_depend_on_the_order_of_the_source_file():
    """FAILS IF: reordering the source rows changes what the seed says.

    The invariant behind the crash, stated as an invariant. `species_map` is
    keyed on the string, so every column in the row is a claim about the string;
    a claim that moves when the file is re-sorted is a claim about the file.
    Both corpora below hold the same three rows.
    """
    name = "test_a_species_map_row_does_not_depend_on_the_order_of_the_source_file"
    site_first = [sj_row(1, "Magnolia", "Yes", 1),
                  sj_row(2, "Magnolia", "No", 2),
                  sj_row(3, "Magnolia", "No", 3)]
    trees_first = [sj_row(2, "Magnolia", "No", 2),
                   sj_row(3, "Magnolia", "No", 3),
                   sj_row(1, "Magnolia", "Yes", 1)]
    a = row_of(species_map_of(site_first), "Magnolia", name)
    b = row_of(species_map_of(trees_first), "Magnolia", name)
    if a is None or b is None:
        return
    check(a == b,
          f"{name}: the same three rows in two orders produced two different "
          f"species_map rows: empty-site-first {a}, trees-first {b}")


def test_a_string_that_names_no_taxon_says_so_even_where_the_flag_says_empty():
    """FAILS IF: `Stump` is filed as a vacant-site placeholder.

    `not_a_tree` is only ever reached THROUGH the species string -- every site
    that returns it matches `NON_TAXON_SPECIES` or `SJ_NON_TREE_SPECIES` and
    carries basis `STATED_AS_NON_TAXON` -- so one such row is a statement about
    the string. `Stump` names no taxon on all 1,933 of its rows in the real
    layer, including the 1,624 the vacancy flag calls empty, and the majority
    being empty sites does not make the WORD a placeholder.
    """
    name = "test_a_string_that_names_no_taxon_says_so_even_where_the_flag_says_empty"
    rows = [sj_row(1, "Stump", "Yes", 1),
            sj_row(2, "Stump", "Yes", 2),
            sj_row(3, "Stump", "Yes", 3),
            sj_row(4, "Stump", "No", 4)]
    row = row_of(species_map_of(rows), "Stump", name)
    if row is None:
        return
    check(row[IS_NON_TAXON] == 1,
          f"{name}: 'Stump' is not filed as naming no taxon")
    check(row[SPECIES_ID] is None,
          f"{name}: 'Stump' minted species {row[SPECIES_ID]}")


def test_one_empty_site_does_not_make_a_tree_string_a_placeholder():
    """FAILS IF: `Unknown` becomes a placeholder because one site is empty.

    The opposite direction, and the reason the placeholder rule needs every row
    to agree rather than any row to vote. `VACANTSITE` is a field about the
    SITE; it says nothing about the string. RULINGS R18 and
    `SanJoseStreetTreeAdapter.classify` both hold that `Unknown` is a tree whose
    species is not known -- not a hole in the pavement -- and in the real layer
    4,507 such trees carry it against 6 empty sites.
    """
    name = "test_one_empty_site_does_not_make_a_tree_string_a_placeholder"
    rows = [sj_row(1, "Unknown", "Yes", 1),
            sj_row(2, "Unknown", "No", 2),
            sj_row(3, "Unknown", "No", 3)]
    row = row_of(species_map_of(rows), "Unknown", name)
    if row is None:
        return
    check(row[IS_PLACEHOLDER] == 0,
          f"{name}: 'Unknown' is filed as a vacant-site placeholder")
    check(row[SPECIES_ID] is None,
          f"{name}: 'Unknown' minted species {row[SPECIES_ID]} (issue #103)")


def test_a_string_on_empty_sites_only_is_a_placeholder():
    """FAILS IF: the placeholder flag stops being reachable.

    The control for the two tests above. Both narrow what `is_placeholder`
    claims, and a rule that narrowed it to nothing would satisfy both while
    emptying the column -- so this asserts the flag still lands on the string
    every one of whose rows is an empty site, which is the case it is for.
    """
    name = "test_a_string_on_empty_sites_only_is_a_placeholder"
    rows = [sj_row(1, "Vacant site", "Yes", 1), sj_row(2, "Vacant site", "Yes", 2)]
    row = row_of(species_map_of(rows), "Vacant site", name)
    if row is None:
        return
    check(row[IS_PLACEHOLDER] == 1,
          f"{name}: a string carried only by empty sites is not a placeholder")
    check(row[SPECIES_ID] is None, f"{name}: 'Vacant site' minted a species")


def test_the_check_that_caught_this_is_in_the_shipped_schema():
    """FAILS IF: `species_map`'s CHECK is not in the database the build writes.

    Calibration, not coverage. Every test above reads a table whose constraint
    is what turned this defect into a crash instead of a wrong row that shipped.
    If that constraint were dropped, all of them would still pass on a seed
    nothing was guarding -- so this asserts the guard is live by writing the
    exact row the build used to write and requiring SQLite to refuse it.
    """
    name = "test_the_check_that_caught_this_is_in_the_shipped_schema"
    with tempfile.TemporaryDirectory() as root:
        write_corpus(root, [sj_row(1, "Magnolia", "Yes", 1), sj_row(2, "Magnolia", "No", 2)])
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                build(root, do_fetch=False, limit=0, with_city_raw=False,
                      source="city", sj_extent="full")
        except Exception as exc:  # noqa: BLE001
            check(False, f"{name}: the build raised {type(exc).__name__}: {exc}")
            return
        conn = sqlite3.connect(os.path.join(root, "Fixtures", "seed", "cypress-seed.sqlite"))
        try:
            species_id = conn.execute("SELECT id FROM species LIMIT 1").fetchone()
            check(species_id is not None, f"{name}: the corpus minted no species to point at")
            if species_id is None:
                return
            try:
                conn.execute(
                    "INSERT INTO species_map(qspecies_string,species_id,species_uuid,"
                    "confidence,is_stub,is_placeholder,is_non_taxon,tree_count) "
                    "VALUES('a placeholder that names a species',?,NULL,0.9,0,1,0,1)",
                    (species_id[0],),
                )
                check(False, f"{name}: the database accepted a placeholder row carrying "
                             f"a species_id; species_map's CHECK is not enforcing")
            except sqlite3.IntegrityError as exc:
                check("CHECK constraint failed" in str(exc),
                      f"{name}: the insert was refused, but for {exc} rather than "
                      f"the CHECK constraint")
        finally:
            conn.close()


def main() -> int:
    tests = [
        test_a_string_on_an_empty_site_and_on_a_tree_still_names_its_species,
        test_a_species_map_row_does_not_depend_on_the_order_of_the_source_file,
        test_a_string_that_names_no_taxon_says_so_even_where_the_flag_says_empty,
        test_one_empty_site_does_not_make_a_tree_string_a_placeholder,
        test_a_string_on_empty_sites_only_is_a_placeholder,
        test_the_check_that_caught_this_is_in_the_shipped_schema,
    ]
    for test in tests:
        # A test that raises is a failed test, not a dead run. Without this the
        # first build to hit the defect these guard against takes the runner
        # down mid-suite, and every later test's verdict is simply never printed.
        try:
            test()
        except Exception as exc:  # noqa: BLE001
            check(False, f"{test.__name__}: raised {type(exc).__name__}: {exc}")

    print(f"{PASSED} checks passed, {len(FAILURES)} failed")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
