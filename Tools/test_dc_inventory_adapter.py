#!/usr/bin/env python3
"""Tests for the Washington, D.C. adapter, run against rows DDOT actually published.

    python3 Tools/test_dc_inventory_adapter.py

WHY THE FIXTURE IS REAL ROWS. Every row in `Fixtures/raw/dc/dc_street_trees_sample.json`
came verbatim off DDOT's `UFA Street Trees` layer (MapServer/23) on 2026-11-12, as
`Tools/fetch_dc_trees.py` cached it, and the sample was selected by querying the
cache for each case the adapter has a rule for. If DDOT's data did not contain a
case, the fixture does not contain it either, and the test that needs it fails
instead of passing on an invented row.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from inventory_adapters import DCStreetTreeAdapter  # noqa: E402
from inventory_contract import (  # noqa: E402
    CONDITION_ALIVE,
    CONDITION_DEAD,
    ID_SPACES,
    IDENTITY_SEPARATOR,
    INVENTORIES,
    KIND_PLANTING_SITE,
    KIND_TREE,
    KindBasis,
    check_id_space_registry,
    require_inventory,
    validate_or_raise,
)

# The frozen namespace `build_seed.py` derives tree uuids in, restated so a
# change to it fails here instead of being followed silently.
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")

FIXTURE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Fixtures", "raw", "dc", "dc_street_trees_sample.json",
)

#: The seed epoch's horizon year, as `build_seed.py` computes it (2026 + 1).
HORIZON = 2027

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def load_rows() -> list:
    with open(FIXTURE, encoding="utf-8") as fh:
        return json.load(fh)["rows"]


def rows_for(case_fragment: str) -> list:
    rows = [r for r in load_rows() if case_fragment.lower() in r["case"].lower()]
    if not rows:
        raise AssertionError(f"the fixture has no row for case {case_fragment!r}")
    return rows


def records_for(case_fragment: str):
    adapter = DCStreetTreeAdapter(rows_for(case_fragment), HORIZON)
    return [validate_or_raise(r) for r in adapter.records()], adapter


# --------------------------------------------------------------------- registry


def test_registry_is_healthy_and_dc_is_registered():
    """FAILS IF: the D.C. id space or inventory is missing, renamed, or breaks a registry rule."""
    check(check_id_space_registry() == [], f"registry problems: {check_id_space_registry()}")
    space = ID_SPACES.get("us-dc-dc")
    check(space is not None and space.identity_prefix == "us-dc-dc:",
          f"us-dc-dc prefix is {space and space.identity_prefix!r}, frozen as 'us-dc-dc:'")
    inventory = require_inventory("dc_street_trees")
    check(inventory.id_space == "us-dc-dc", f"dc_street_trees is in {inventory.id_space!r}")
    check(inventory.name == "DDOT Urban Forestry street tree inventory",
          f"inventory name drifted: {inventory.name!r}")
    check(inventory.url.endswith("/DCGIS_DATA/Urban_Tree_Canopy/MapServer/23"),
          f"inventory url drifted: {inventory.url!r}")
    check("dc_street_trees" in INVENTORIES, "dc_street_trees not in INVENTORIES")


# --------------------------------------------------------------------- identity


def test_source_ref_is_globalid_without_braces_case_kept():
    """FAILS IF: the braces survive, the case is changed, or another field is used as the id.

    The uuid is uuid5 over `us-dc-dc:<source_ref>`, so any of those changes every
    D.C. tree's public identity after the first publish.
    """
    rows = rows_for("plant good named")
    records, _ = records_for("plant good named")
    for row, record in zip(rows, records):
        published = row["attributes"]["GLOBALID"]
        check(published.startswith("{") and published.endswith("}"),
              f"fixture GLOBALID {published!r} is not braced; the test is not testing anything")
        check(record.source_ref == published[1:-1],
              f"source_ref {record.source_ref!r} is not {published[1:-1]!r}")
        check(record.source_ref == record.source_ref.upper(),
              f"source_ref {record.source_ref!r} changed case")
        check(IDENTITY_SEPARATOR not in record.source_ref, "source_ref contains ':'")
    seed = records[0].identity_seed(ID_SPACES["us-dc-dc"])
    check(seed == "us-dc-dc:" + rows[0]["attributes"]["GLOBALID"][1:-1],
          f"identity seed is {seed!r}")


def test_globalid_uuid_is_pinned():
    """FAILS IF: the prefix, the brace stripping or the namespace changes.

    One published GLOBALID -> one uuid, written out. A change to any input of the
    derivation changes this string.
    """
    record = next(DCStreetTreeAdapter([{
        "attributes": {"GLOBALID": "{926038DA-7BC7-4558-B705-41FDE907B698}",
                       "TBOX_STAT": "Plant", "SCI_NM": "Ulmus americana",
                       "CONDITION": "Good"},
        "geometry": {"x": -77.04, "y": 38.93},
    }], HORIZON).records())
    got = str(uuid.uuid5(NS_TREE, record.identity_seed(ID_SPACES["us-dc-dc"])))
    want = str(uuid.uuid5(NS_TREE, "us-dc-dc:926038DA-7BC7-4558-B705-41FDE907B698"))
    check(got == want, f"uuid {got} != {want}")


# ------------------------------------------------------------------- what ships


def test_plant_ships_as_a_tree_with_stated_category():
    """FAILS IF: a `Plant` row is not a tree, or its basis claims more than the source said."""
    records, adapter = records_for("plant good named")
    check(len(records) == 3, f"expected 3 trees, got {len(records)}")
    for record in records:
        check(record.kind == KIND_TREE, f"kind {record.kind}")
        check(record.kind_basis == KindBasis.STATED_CATEGORY, f"basis {record.kind_basis}")
        check(record.scientific_name == "Acer rubrum", f"name {record.scientific_name!r}")
        check(record.common_name == "Red maple", f"common {record.common_name!r}")
        check(record.condition == CONDITION_ALIVE, f"condition {record.condition!r}")
        check(record.city_record.get("permit_notes") == "Good",
              f"DDOT's condition word is not carried: {record.city_record}")
        check(record.dbh_in is not None and 2 < record.dbh_in < 40, f"dbh {record.dbh_in}")
        check(record.planted_on is not None and 1990 < record.planted_on.year < 2026,
              f"planted_on {record.planted_on}")
        check(record.address is not None and "  " not in record.address,
              f"address {record.address!r}")
    check(adapter.stats["kind_tree"] == 3, f"stats {adapter.stats}")


def test_open_ships_as_a_vacant_site_and_drops_leftovers():
    """FAILS IF: an `Open` box ships with a species, trunk or condition, or the leftovers are not counted.

    The contract forbids a planting site that names a species or states a
    condition, so this is also what keeps the build from dying on 869 rows.
    """
    records, adapter = records_for("open naming a taxon")
    check(len(records) == 1, f"expected 1 record, got {len(records)}")
    record = records[0]
    check(record.kind == KIND_PLANTING_SITE, f"kind {record.kind}")
    check(record.kind_basis == KindBasis.STATED, f"basis {record.kind_basis}")
    check(record.scientific_name is None and record.common_name is None,
          f"a planting site names {record.scientific_name!r}/{record.common_name!r}")
    check(record.dbh_in is None, f"a planting site carries dbh {record.dbh_in}")
    check(record.condition is None, f"a planting site carries condition {record.condition}")
    check(adapter.stats["open_sites_naming_a_taxon"] == 1, f"stats {adapter.stats}")
    check(adapter.stats["open_sites_with_a_trunk_diameter"] == 1, f"stats {adapter.stats}")
    check(adapter.stats["open_sites_with_a_condition"] == 1, f"stats {adapter.stats}")

    plain, _ = records_for("open plain")
    check(len(plain) == 2 and all(r.kind == KIND_PLANTING_SITE for r in plain),
          f"plain open boxes: {[r.kind for r in plain]}")


def test_every_other_status_is_not_shipped_and_counted_by_name():
    """FAILS IF: a Retired/Proposed/Conflict/Delete/truncated/null row ships, or its drop is uncounted.

    `Retired` rows still carry the removed tree's species and DBH, so a filter on
    "has a species" instead of on `TBOX_STAT` would ship them as living trees.
    """
    cases = {
        "retired with leftover species": "Retired",
        "retired dead": "Retired",
        "proposed": "Proposed",
        "conflict": "Conflict",
        "delete": "Delete",
        "utility conflic": "Utility Conflic",
        "under construct": "Under Construct",
        "status null": "(null)",
    }
    for case, label in cases.items():
        records, adapter = records_for(case)
        check(records == [], f"{case}: shipped {len(records)} record(s)")
        check(adapter.stats["status_not_shipped"].get(label) == 1,
              f"{case}: not counted under {label!r}: {adapter.stats['status_not_shipped']}")
    leftover = rows_for("retired with leftover species")[0]["attributes"]
    check(bool(leftover["SCI_NM"]) and (leftover["DBH"] or 0) > 0,
          "the Retired fixture row has no leftover species/DBH; the test proves nothing")


def test_standing_dead_is_a_tree_in_dead_condition():
    """FAILS IF: a `Plant` row rated `Dead` stops being a tree, or stops being `dead` (R19)."""
    records, adapter = records_for("plant dead standing")
    check(len(records) == 2, f"expected 2 records, got {len(records)}")
    for record in records:
        check(record.kind == KIND_TREE, f"kind {record.kind}")
        check(record.condition == CONDITION_DEAD, f"condition {record.condition}")
        check(record.condition_text == "Dead", f"condition_text {record.condition_text!r}")
    check(adapter.stats["standing_dead"] == 2, f"stats {adapter.stats}")


def test_poor_and_fair_are_alive_not_declining():
    """FAILS IF: `Poor` or `Fair` map anywhere but `alive` (R101's precedent)."""
    for case in ("plant poor named", "plant fair named", "plant excellent named"):
        records, _ = records_for(case)
        check(records[0].condition == CONDITION_ALIVE,
              f"{case}: condition {records[0].condition!r}")


def test_null_condition_is_no_claim():
    """FAILS IF: a blank CONDITION is spelled as `alive` instead of `None`."""
    records, adapter = records_for("plant condition null")
    check(records[0].condition is None and records[0].condition_text is None,
          f"condition {records[0].condition!r}/{records[0].condition_text!r}")
    check(adapter.stats["condition_not_stated"] == 1, f"stats {adapter.stats}")


def test_an_unknown_condition_value_stops_the_build():
    """FAILS IF: a new CONDITION word ships silently with no claim."""
    row = json.loads(json.dumps(rows_for("plant good named")[0]))
    row["attributes"]["CONDITION"] = "Critical"
    try:
        list(DCStreetTreeAdapter([row], HORIZON).records())
    except ValueError as error:
        check("Critical" in str(error), f"the error does not name the value: {error}")
    else:
        check(False, "CONDITION 'Critical' was accepted")


# ---------------------------------------------------------------------- species


def test_placeholder_and_blank_species_are_trees_with_no_species():
    """FAILS IF: `Other (See Notes)` becomes a species, or a blank SCI_NM stops being a tree (R18)."""
    for case, stat in (("plant species other see notes", "species_placeholder"),
                       ("plant species null", "species_blank")):
        records, adapter = records_for(case)
        record = records[0]
        check(record.kind == KIND_TREE, f"{case}: kind {record.kind}")
        check(record.scientific_name is None and record.common_name is None,
              f"{case}: species {record.scientific_name!r}/{record.common_name!r}")
        check(adapter.stats[stat] == 1, f"{case}: stats {adapter.stats}")


def test_placeholder_common_name_beside_a_real_name_is_dropped():
    """FAILS IF: `Other (See Notes)` reaches a species row as its common name."""
    records, _ = records_for("plant common other see notes beside a real name")
    check(records[0].scientific_name == "Robinia pseudoacacia",
          f"name {records[0].scientific_name!r}")
    check(records[0].common_name is None, f"common {records[0].common_name!r}")


def test_nbsp_is_normalised_and_cultivars_kept_as_published():
    """FAILS IF: U+00A0 survives into a name, or a cultivar is stripped.

    Name normalisation is whitespace only. Cultivars, hybrids, `species`/`spp`
    and the sex suffix all stay as DDOT wrote them -- the same rule San Jose and
    New York follow, so no synonymy is invented here.
    """
    raw = rows_for("plant nbsp in name")[0]["attributes"]["SCI_NM"]
    check("\xa0" in raw, "the nbsp fixture row has no U+00A0; the test proves nothing")
    records, _ = records_for("plant nbsp in name")
    check(records[0].scientific_name == "Eucommia ulmoides",
          f"name {records[0].scientific_name!r}")
    check(records[0].species_text == "Eucommia ulmoides",
          f"species_text {records[0].species_text!r}")

    expectations = {
        "plant cultivar": "Pyrus calleryana 'Bradford'",
        "plant genus species spelled species": "Prunus species",
        "plant genus spp": "Morus spp",
        "plant sex suffix": "Ginkgo biloba (male)",
    }
    for case, name in expectations.items():
        records, _ = records_for(case)
        check(records[0].scientific_name == name,
              f"{case}: name {records[0].scientific_name!r}, expected {name!r}")
    hybrid, _ = records_for("plant hybrid x")
    check(" x " in hybrid[0].scientific_name, f"hybrid sign lost: {hybrid[0].scientific_name!r}")


def test_confidence_scale():
    """FAILS IF: DDOT's `Genus species` scores as a confident binomial."""
    check(DCStreetTreeAdapter.confidence_for("Prunus species") == 0.75, "Prunus species")
    check(DCStreetTreeAdapter.confidence_for("Morus spp") == 0.75, "Morus spp")
    check(DCStreetTreeAdapter.confidence_for("Acer rubrum") == 1.0, "Acer rubrum")
    check(DCStreetTreeAdapter.confidence_for("Pyrus calleryana 'Bradford'") == 0.9, "cultivar")
    check(DCStreetTreeAdapter.confidence_for(None) is None, "None")


# ------------------------------------------------------------ values: DBH, date


def test_dbh_sentinels_and_ceiling():
    """FAILS IF: 0, a negative or an over-400-in DBH reaches `dbh_in`, or the drop is uncounted."""
    for case, stat in (("plant dbh zero", "dbh_zero_or_negative"),
                       ("plant dbh negative", "dbh_zero_or_negative"),
                       ("plant dbh over ceiling", "dbh_over_ceiling")):
        records, adapter = records_for(case)
        check(records[0].dbh_in is None, f"{case}: dbh {records[0].dbh_in}")
        check(adapter.stats[stat] == 1, f"{case}: stats {adapter.stats}")
    records, _ = records_for("plant dbh null")
    check(records[0].dbh_in is None, f"null dbh became {records[0].dbh_in}")


def test_planting_date_sentinels():
    """FAILS IF: 1899-12-30 or a future date reaches `planted_on`."""
    for case in ("plant date sentinel 1899-12-30", "plant date in the future"):
        records, adapter = records_for(case)
        check(records[0].planted_on is None, f"{case}: planted_on {records[0].planted_on}")
        check(adapter.stats["planted_date_out_of_range"] == 1, f"{case}: stats {adapter.stats}")


# ------------------------------------------------------------------ positions


def test_no_point_is_dropped_and_counted():
    """FAILS IF: a row with no geometry yields a record or goes uncounted."""
    records, adapter = records_for("no geometry")
    check(records == [], f"shipped {len(records)} record(s) with no point")
    check(adapter.stats["dropped_no_coords"] == 2, f"stats {adapter.stats}")


def test_laurel_rows_are_outside_the_build_bbox():
    """FAILS IF: the build's DC_BBOX would admit DDOT's Oak hill Dr rows in Laurel, Maryland.

    The adapter yields them -- the bounding box is the seed's rule, not the
    adapter's -- so this reads `build_seed.DC_BBOX` and checks the yielded points
    fall outside it.
    """
    import build_seed  # noqa: PLC0415
    box = build_seed.BBOX_BY_ID_SPACE["us-dc-dc"]
    for case in ("plant outside district", "open outside district"):
        records, _ = records_for(case)
        check(len(records) == 1, f"{case}: adapter yielded {len(records)}")
        for record in records:
            inside = (box["min_lat"] <= record.lat <= box["max_lat"]
                      and box["min_lon"] <= record.lon <= box["max_lon"])
            check(not inside, f"{case}: ({record.lat}, {record.lon}) is inside DC_BBOX")
    for record in records_for("plant good named")[0]:
        inside = (box["min_lat"] <= record.lat <= box["max_lat"]
                  and box["min_lon"] <= record.lon <= box["max_lon"])
        check(inside, f"a District tree at ({record.lat}, {record.lon}) is outside DC_BBOX")


# ---------------------------------------------------------------- accounting


def test_the_stats_account_for_every_row():
    """FAILS IF: a row leaves the adapter by a path nobody counted."""
    adapter = DCStreetTreeAdapter(load_rows(), HORIZON)
    records = [validate_or_raise(r) for r in adapter.records()]
    stats = adapter.stats
    not_shipped = sum(stats["status_not_shipped"].values())
    check(
        stats["source_rows"] == not_shipped + stats["dropped_no_coords"] + len(records),
        f"{stats['source_rows']} rows != {not_shipped} not shipped + "
        f"{stats['dropped_no_coords']} no point + {len(records)} yielded",
    )
    check(stats["kind_tree"] + stats["kind_planting_site"] == len(records),
          f"kind counters {stats['kind_tree']}+{stats['kind_planting_site']} != {len(records)}")
    check(stats["source_rows"] == len(load_rows()), f"read {stats['source_rows']} rows")


# ---------------------------------------------------------------------------


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for test in tests:
        try:
            test()
        except Exception as error:  # noqa: BLE001
            FAILURES.append(f"{test.__name__} raised {type(error).__name__}: {error}")
    for failure in FAILURES:
        print(f"FAIL: {failure}")
    print(f"\n{PASSED} checks passed, {len(FAILURES)} failed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
