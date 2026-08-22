#!/usr/bin/env python3
"""Tests for the NYC adapter, run against rows NYC Parks actually published.

    python3 Tools/test_nyc_inventory_adapter.py

WHY THE FIXTURE IS REAL ROWS. An adapter tested against rows invented to match it
tests nothing except that its author was self-consistent. Every row in
`Fixtures/nyc_survey/nyc_tree_point_sample.json` came verbatim off
`data.cityofnewyork.us` on 2026-08-14, and the sample was selected by querying
for each case the adapter has a rule for -- so if NYC's data does not contain the
case, the fixture does not contain it either and the test that needs it fails
loudly instead of passing on a fake. That is the same discipline
`test_ca_inventory_adapter.py` uses for San Jose.

They live here rather than in `test_inventory_contract.py` so the contract's own
suite stays a statement about the contract, and so two parallel agents adding
sources do not both edit one file.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from inventory_adapters import (  # noqa: E402
    NYC_DBH_CEILING_IN,
    NYC_MAX_SNAP_METRES,
    BoroughResolver,
    NYCTreePointAdapter,
)
from inventory_contract import (  # noqa: E402
    ID_SPACES,
    IDENTITY_SEPARATOR,
    INVENTORIES,
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    KindBasis,
    check_id_space_registry,
    require_inventory,
    validate_or_raise,
)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(REPO, "Fixtures", "nyc_survey", "nyc_tree_point_sample.json")

#: The seed epoch year plus one, matching what build_seed.py passes. Fixed, not
#: read off the clock -- a wall-clock reading inside the seed is ERRATA E13.
HORIZON = 2027

PASSED = 0
FAILURES: list = []


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def load():
    with open(FIXTURE, "r", encoding="utf-8") as fh:
        payload = json.load(fh)
    spaces = {row["globalid"]: row for row in payload["planting_spaces"]}
    return payload["tree_points"], spaces


def _resolver():
    path = os.path.join(REPO, "Fixtures", "nyc_survey", "borough_boundaries.geojson")
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return BoroughResolver(json.load(fh))


def adapter(**kwargs):
    rows, spaces = load()
    kwargs.setdefault("borough_resolver", _resolver())
    return NYCTreePointAdapter(rows, spaces, HORIZON, **kwargs)


def by_case(records_with_rows, case):
    return [r for r, row in records_with_rows if row.get("_case") == case]


def run():
    """(record, source row) pairs, so a test can name the case it is about."""
    rows, spaces = load()
    # A resolver is the ORDINARY configuration since RULING D18 -- without one
    # the adapter refuses to finish on any row lacking a stated borough, which
    # is the point. Tests that need the no-resolver behaviour ask for it.
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=_resolver())
    out = []
    produced = list(a.records())
    # `records()` skips nothing in this fixture (every row has a position), so
    # the pairing is positional and is asserted to be, rather than assumed.
    assert len(produced) == len(rows), (
        f"{len(produced)} records from {len(rows)} rows; the pairing below would be wrong"
    )
    for record, row in zip(produced, rows):
        out.append((record, row))
    return a, out


# ---------------------------------------------------------------------------
# the registry
# ---------------------------------------------------------------------------


def test_id_space_is_registered_and_healthy():
    """Fails if `us-ny-nyc` is missing, or its prefix could alias another space."""
    check(not check_id_space_registry(), f"registry problems: {check_id_space_registry()}")
    space = ID_SPACES["us-ny-nyc"]
    check(space.identity_prefix == "us-ny-nyc:", f"prefix moved to {space.identity_prefix!r}")
    check(
        space.identity_prefix.endswith(IDENTITY_SEPARATOR),
        "the prefix no longer ends in the separator; two spaces' seed strings could alias",
    )


def test_both_inventories_resolve_to_the_nyc_space():
    """Fails if either inventory is unregistered or lands in another city's space."""
    for inventory_id in ("nyc_tree_points", "nyc_planting_spaces"):
        inventory = require_inventory(inventory_id)
        check(
            inventory.id_space == "us-ny-nyc",
            f"{inventory_id} is in id space {inventory.id_space!r}, not 'us-ny-nyc'",
        )
    check("nyc_tree_points" in INVENTORIES, "nyc_tree_points is not in INVENTORIES")


def test_nyc_uuids_cannot_collide_with_california():
    """Fails if a GlobalID could mint a uuid another city already shipped.

    The guarantee is structural, not incidental: the prefix differs, so even the
    same source_ref in two spaces produces two uuids.
    """
    ref = "D91FC1AC-D258-41E0-B3C8-235B7921DE3D"
    nyc = uuid.uuid5(uuid.NAMESPACE_URL, ID_SPACES["us-ny-nyc"].identity_seed(ref))
    sj = uuid.uuid5(uuid.NAMESPACE_URL, ID_SPACES["us-ca-sj"].identity_seed(ref))
    sf = uuid.uuid5(uuid.NAMESPACE_URL, ID_SPACES["sf"].identity_seed(ref))
    check(len({nyc, sj, sf}) == 3, "two id spaces minted the same uuid for one source_ref")


# ---------------------------------------------------------------------------
# the species parser
# ---------------------------------------------------------------------------


def test_packed_species_splits_into_two_clean_fields():
    """Fails if the adapter ever puts a common name on the scientific side."""
    split = NYCTreePointAdapter.split_genus_species
    check(split("Quercus palustris - pin oak") == ("Quercus palustris", "pin oak"),
          f"clean binomial split wrong: {split('Quercus palustris - pin oak')}")
    check(split("Morus - mulberry") == ("Morus", "mulberry"),
          f"genus-only split wrong: {split('Morus - mulberry')}")
    check(split("") == (None, None), "a blank species string must be (None, None)")


def test_the_en_dash_row_is_not_stubbed():
    """THE ONE ROW A `str.split(' - ')` GETS WRONG.

    `Asimina triloba – Pawpaw` (U+2013) is the only non-ASCII value in the whole
    620-value vocabulary, 28 rows. A naive split hands the string back whole, and
    the adapter would mint a species named `Asimina triloba – Pawpaw` shadowing
    the real `Asimina triloba` -- task #103's mechanism exactly.

    Fails if the separator regex stops matching the en dash.
    """
    scientific, common = NYCTreePointAdapter.split_genus_species("Asimina triloba – Pawpaw")
    check(scientific == "Asimina triloba",
          f"en-dash row parsed its scientific name as {scientific!r}; a species "
          f"shadowing Asimina triloba would be minted from it")
    check(common == "Pawpaw", f"en-dash row parsed its common name as {common!r}")


def test_internal_hyphens_and_cultivar_quotes_survive():
    """Fails if the separator eats a hyphen inside a name.

    `Crataegus crus-galli var. inermis` carries a hyphen with no spaces around
    it, so only a SPACED dash may separate. A cultivar epithet's quotes are the
    ICNCP's own marker and must reach the scientific side intact.
    """
    split = NYCTreePointAdapter.split_genus_species
    scientific, _ = split("Crataegus crus-galli var. inermis - Cockspur hawthorn")
    check(scientific == "Crataegus crus-galli var. inermis",
          f"an internal hyphen was treated as the separator: {scientific!r}")
    scientific, _ = split("Zelkova serrata 'Green Vase' - 'Green Vase' Zelkova")
    check(scientific == "Zelkova serrata 'Green Vase'",
          f"a quoted cultivar lost its epithet: {scientific!r}")


def test_unknown_is_a_tree_with_no_species():
    """R18 and San Jose's `Unknown`: a tree of unknown species is a tree.

    Fails if `Unknown - Unknown` ever mints a species called `Unknown` (#103) or
    becomes a planting site (#94).
    """
    _a, pairs = run()
    records = by_case(pairs, "full/Unknown - Unknown")
    check(bool(records), "the fixture lost its `Unknown - Unknown` rows")
    for record in records:
        check(record.kind == KIND_TREE, f"Unknown became {record.kind!r}, not a tree")
        check(record.scientific_name is None,
              f"Unknown minted the species {record.scientific_name!r}")
        check(record.species_text == "Unknown - Unknown",
              "the city's own word was not kept in species_text")


# ---------------------------------------------------------------------------
# the join
# ---------------------------------------------------------------------------


def test_a_joined_row_takes_its_address_from_planting_spaces():
    """Fails if the join stops supplying the columns Tree Points does not have."""
    _a, pairs = run()
    joined = [r for r, _ in pairs if r.attributes_from is not None]
    check(bool(joined), "no fixture row joined to a planting space at all")
    for record in joined:
        check(record.attributes_from == "nyc_planting_spaces",
              f"attributes_from is {record.attributes_from!r}")
    check(any(r.address for r in joined), "no joined row carried an address")
    check(any(r.site_type for r in joined), "no joined row carried a site type")


def test_an_orphan_row_says_absent_rather_than_guessing():
    """22,995 of 898,643 Full points match no planting space. They are KEPT.

    Fails if an unmatched row is dropped, or if it claims an address it does not
    have, or if `attributes_from` names an inventory that supplied nothing.
    """
    _a, pairs = run()
    orphans = by_case(pairs, "full/ORPHAN no ps match")
    check(bool(orphans), "the fixture lost its orphan rows")
    for record in orphans:
        check(record.attributes_from is None,
              f"an orphan claims attributes_from={record.attributes_from!r}")
        check(record.address is None, f"an orphan invented the address {record.address!r}")
        check(record.site_type is None, f"an orphan invented the site type {record.site_type!r}")
        check(record.lat is not None and record.lon is not None,
              "an orphan lost its position; it has one on its own tree point")


def test_the_join_never_moves_a_trees_position():
    """Fails if a tree's position is ever taken from its planting space.

    Both datasets publish a point and they are NOT identical. The tree's position
    is the tree point's own; the planting space supplies attributes only.
    """
    rows, spaces = load()
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=_resolver())
    for record, row in zip(list(a.records()), rows):
        check(record.lat == row["lat"] and record.lon == row["lon"],
              f"record at ({record.lat}, {record.lon}) but its tree point is at "
              f"({row['lat']}, {row['lon']})")


# ---------------------------------------------------------------------------
# kind, and the provisional half
# ---------------------------------------------------------------------------


def test_structure_decides_kind_and_a_stump_is_not_a_tree():
    """Fails if a stump, shaft or retired record is ingested as a tree."""
    _a, pairs = run()
    for case in ("stump", "stump - uprooted", "shaft", "retired"):
        records = by_case(pairs, case)
        check(bool(records), f"the fixture lost its {case!r} rows")
        for record in records:
            check(record.kind == KIND_NOT_A_TREE, f"{case} became {record.kind!r}")
            check(record.scientific_name is None,
                  f"{case} kept the species {record.scientific_name!r}")
            check(record.dbh_in is None, f"{case} kept a trunk diameter of {record.dbh_in}")


def test_a_standing_dead_tree_is_still_a_tree_and_is_counted():
    """`TPStructure='Full'` + `TPCondition='Dead'` -- 10,635 rows city-wide.

    It is `kind=tree`: it has a trunk, a species and a location. The seed will
    currently ship it as `status='alive'`, which is a real and NAMED information
    loss, so the adapter counts it.

    Fails if the count stops being kept, or if a standing dead tree is
    reclassified as a planting site or a non-tree.
    """
    a, pairs = run()
    records = by_case(pairs, "full/STANDING DEAD")
    check(bool(records), "the fixture lost its standing-dead rows")
    for record in records:
        check(record.kind == KIND_TREE, f"a standing dead tree became {record.kind!r}")
    check(a.stats["standing_dead_mapped_to_alive"] == len(records),
          f"standing_dead_mapped_to_alive is {a.stats['standing_dead_mapped_to_alive']}, "
          f"but the fixture holds {len(records)} such rows; the build receipt would "
          f"understate a known information loss")


def test_structure_and_condition_reach_city_record_losslessly():
    """The whole reason the standing-dead loss is recoverable later.

    Fails if `TPStructure` or `TPCondition` stops being carried verbatim, which
    is what would make the loss permanent rather than provisional.
    """
    _a, pairs = run()
    for record, row in pairs:
        check(record.city_record.get("plant_type") == (row.get("tpstructure") or None),
              f"plant_type is {record.city_record.get('plant_type')!r} for a row whose "
              f"TPStructure is {row.get('tpstructure')!r}")
        check(record.city_record.get("permit_notes") == (row.get("tpcondition") or None),
              f"permit_notes is {record.city_record.get('permit_notes')!r} for a row whose "
              f"TPCondition is {row.get('tpcondition')!r}")


def test_a_silent_row_is_the_only_place_the_kind_is_ours():
    """`TPStructure` is null on 11 rows of 1,121,106.

    Fails if a row the source said nothing about stops being counted under the
    badly-named basis -- that count is how big our own guessing is.
    """
    _a, pairs = run()
    silent = by_case(pairs, "TPStructure NULL")
    check(bool(silent), "the fixture lost its null-TPStructure rows")
    for record in silent:
        check(record.kind_basis != KindBasis.STATED_CATEGORY,
              "a row with no TPStructure claims the source put it in a category")
        if record.kind == KIND_PLANTING_SITE:
            check(record.kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES,
                  f"a silent row became a planting site on basis {record.kind_basis!r}")


# ---------------------------------------------------------------------------
# the source's own sentinels
# ---------------------------------------------------------------------------


def test_dbh_zero_is_not_recorded_rather_than_a_zero_inch_trunk():
    """650 `Full` rows publish `DBH = 0`. A `Full` tree point has a trunk.

    Fails if the sentinel reaches the contract, where `dbh_in` is defined as a
    measurement somebody took and a non-positive value is rejected outright.
    """
    a, pairs = run()
    zeros = by_case(pairs, "full/DBH zero sentinel")
    check(bool(zeros), "the fixture lost its DBH=0 rows")
    for record in zeros:
        check(record.dbh_in is None, f"a DBH of 0 became dbh_in={record.dbh_in!r}")
    check(a.stats["dbh_zero_sentinel"] >= len(zeros),
          f"the zero sentinel was not counted: {a.stats}")


def test_an_impossible_trunk_is_rejected_and_counted():
    """Five `Full` rows exceed 400 in, the largest 2,427 in.

    Fails if the ceiling stops being applied, or stops being counted.
    """
    a, pairs = run()
    over = by_case(pairs, "full/DBH over ceiling")
    check(bool(over), "the fixture lost its over-ceiling rows")
    for record in over:
        check(record.dbh_in is None,
              f"a trunk of {record.dbh_in} in survived a {NYC_DBH_CEILING_IN} in ceiling")
    check(a.stats["dbh_over_ceiling"] == len(over),
          f"dbh_over_ceiling is {a.stats['dbh_over_ceiling']}, fixture holds {len(over)}")


def test_created_date_is_never_read_as_a_planting_date():
    """`CreatedDate` is when the RECORD was made, not when the tree was planted.

    `PlantedDate` is populated on 13.77% of Full rows; `CreatedDate` on ~100%. A
    parser that fell back would report a planting date for nearly every tree and
    the number would be wrong for six trees in seven.

    Fails if `planted_on` is ever set on a row whose `PlantedDate` is empty.
    """
    _a, pairs = run()
    for record, row in pairs:
        if not (row.get("planteddate") or "").strip():
            check(record.planted_on is None,
                  f"planted_on is {record.planted_on!r} for a row with no PlantedDate "
                  f"(its CreatedDate is {row.get('createddate')!r})")


def test_planted_date_is_parsed_when_it_is_there():
    """Fails if the real date format stops parsing -- which would silently turn
    123,725 dated NYC trees into undated ones."""
    _a, pairs = run()
    dated = by_case(pairs, "full/planteddate present")
    check(bool(dated), "the fixture lost its dated rows")
    for record in dated:
        check(record.planted_on is not None, "a row with a PlantedDate parsed to None")


# ---------------------------------------------------------------------------
# the contract
# ---------------------------------------------------------------------------


def test_every_record_satisfies_the_contract():
    """The catch-all. Fails if any row this adapter emits is one the contract
    forbids -- a planting site naming a species, a blank string where None is
    meant, a non-positive dbh, a source_ref containing the separator."""
    _a, pairs = run()
    for record, row in pairs:
        try:
            validate_or_raise(record)
        except Exception as error:  # noqa: BLE001
            FAILURES.append(
                f"row globalid={row.get('globalid')} case={row.get('_case')!r} "
                f"produced an invalid record: {error}"
            )
        else:
            check(True, "")


def test_identity_is_the_globalid_and_nothing_else():
    """Fails if the adapter ever keys on OBJECTID, which moves on republish."""
    _a, pairs = run()
    for record, row in pairs:
        check(record.source_ref == row["globalid"],
              f"source_ref is {record.source_ref!r}, GlobalID is {row['globalid']!r}")
        check(record.source_ref != str(row.get("objectid")),
              "source_ref is the OBJECTID; it moves on republish")
        check(IDENTITY_SEPARATOR not in (record.source_ref or ""),
              f"source_ref {record.source_ref!r} contains the id-space separator")


def test_nyc_publishes_no_caretaker_so_none_is_invented():
    """Fails if a caretaker or care assistant is ever conjured for NYC."""
    _a, pairs = run()
    for record, _row in pairs:
        check(record.city_record.get("caretaker") is None,
              f"a caretaker appeared: {record.city_record.get('caretaker')!r}")
        check(record.city_record.get("care_assistant") is None,
              f"a care assistant appeared: {record.city_record.get('care_assistant')!r}")


# ---------------------------------------------------------------------------
# RULING D18 -- every tree gets a borough
# ---------------------------------------------------------------------------


def test_the_borough_resolver_places_landmarks_correctly():
    """Calibration against five coordinates whose borough is common knowledge.

    Fails if the polygons are the wrong dataset, or if lat/lon reach shapely in
    the wrong order -- which would silently place every tree in the water.
    """
    resolver = _resolver()
    check(resolver is not None, "the borough boundary fixture is missing")
    if resolver is None:
        return
    check(sorted(resolver.names) ==
          ["Bronx", "Brooklyn", "Manhattan", "Queens", "Staten Island"],
          f"boroughs are {sorted(resolver.names)}")
    for label, lat, lon, expected in (
        ("Times Square", 40.7580, -73.9855, "Manhattan"),
        ("Brooklyn Bridge Park", 40.7003, -73.9967, "Brooklyn"),
        ("Flushing Meadows", 40.7466, -73.8447, "Queens"),
        ("Yankee Stadium", 40.8296, -73.9262, "Bronx"),
        ("St George, Staten Island", 40.6437, -74.0736, "Staten Island"),
    ):
        got = resolver.contains(lat, lon)
        check(got == expected, f"{label} resolved to {got!r}, expected {expected!r}")


def test_a_point_outside_the_city_is_not_in_any_borough():
    """Fails if `contains` is really answering 'nearest' -- which would make the
    whole point-in-polygon step vacuous and place New Jersey in Staten Island."""
    resolver = _resolver()
    if resolver is None:
        return
    check(resolver.contains(40.7357, -74.1724) is None,
          "Newark, NJ resolved to a New York City borough")
    nearest, metres = resolver.nearest(40.7357, -74.1724)
    check(metres > NYC_MAX_SNAP_METRES,
          f"Newark is {metres:.0f} m from {nearest}, inside the "
          f"{NYC_MAX_SNAP_METRES:.0f} m snap cap; it would be assigned a borough")


def test_a_stated_borough_wins_and_geometry_only_calibrates():
    """RULING D18's precedence. Fails if geometry ever OVERRIDES the City's own
    attribution -- 7 rows city-wide disagree, and they keep what NYC says."""
    rows, spaces = load()
    resolver = _resolver()
    if resolver is None:
        return
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=resolver)
    for record, row in zip(list(a.records()), rows):
        space = spaces.get((row.get("plantingspaceglobalid") or "").strip())
        stated = (space or {}).get("boroughcode")
        if not stated:
            continue
        carried = json.loads(record.raw_json)
        check(carried["boroughcode"] == stated,
              f"a stated borough {stated!r} was overridden with "
              f"{carried['boroughcode']!r}")
        check(carried["boroughsource"] == "planting_space",
              f"a stated row records its source as {carried['boroughsource']!r}")


def test_an_orphan_gets_a_borough_from_geometry():
    """The whole point of D18: before it, 22,995 trees had no borough and no
    borough pack could contain them.

    Fails if an orphan comes back with no borough, or claims its planting space
    supplied one.
    """
    rows, spaces = load()
    resolver = _resolver()
    if resolver is None:
        return
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=resolver)
    records = list(a.records())
    orphans = [r for r, row in zip(records, rows) if row.get("_case") == "full/ORPHAN no ps match"]
    check(bool(orphans), "the fixture lost its orphan rows")
    for record in orphans:
        carried = json.loads(record.raw_json or "{}")
        check(carried.get("boroughcode") in resolver.names,
              f"an orphan carries borough {carried.get('boroughcode')!r}")
        check(carried.get("boroughsource") in ("point_in_polygon", "nearest_polygon"),
              f"an orphan credits its borough to {carried.get('boroughsource')!r}")


def test_every_row_is_placed_and_the_counters_sum():
    """RULING D18 requires borough packs to sum EXACTLY to the whole city.

    Fails if any row is unassigned, or if the four outcome counters do not
    account for every row read -- which is how a silent drop hides.
    """
    rows, spaces = load()
    resolver = _resolver()
    if resolver is None:
        return
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=resolver)
    records = list(a.records())
    s = a.stats
    check(s["borough_unassigned"] == 0,
          f"{s['borough_unassigned']} rows were left with no borough")
    placed = (s["borough_stated_by_planting_space"]
              + s["borough_from_point_in_polygon"]
              + s["borough_from_nearest_polygon"]
              + s["borough_unassigned"])
    check(placed == s["source_rows"],
          f"the D18 counters total {placed} of {s['source_rows']} rows: {s}")
    for record in records:
        carried = json.loads(record.raw_json or "{}")
        check(carried.get("boroughcode"),
              f"a record shipped with no borough at all (ref {record.source_ref})")


def test_a_row_that_cannot_be_placed_stops_the_run():
    """Fails if an unplaceable row is emitted with no borough instead of stopping.

    Driven with NO resolver, which is the only way to make the fixture's own rows
    unplaceable without inventing a coordinate in the Atlantic.
    """
    rows, spaces = load()
    orphan_rows = [r for r in rows if not spaces.get((r.get("plantingspaceglobalid") or "").strip())]
    check(bool(orphan_rows), "the fixture holds no row lacking a stated borough")
    a = NYCTreePointAdapter(orphan_rows, spaces, HORIZON, borough_resolver=None)
    try:
        list(a.records())
    except ValueError as error:
        check("could not be placed in any borough" in str(error),
              f"the run stopped, but for the wrong reason: {error}")
    else:
        FAILURES.append(
            "a run with unplaceable rows finished quietly; RULING D18 requires "
            "borough packs to sum exactly to the whole city"
        )


def test_a_planting_date_in_the_future_is_dropped_and_counted():
    """Three of NYC's 136,730 PlantedDates are in the future -- 2030-11-02 and
    2108-11-23 twice, each a transposition whose intended year is legible from
    its own CreatedDate. They resolve to None; CORRECTING them would be
    inventing a fact.

    Fails if the horizon clamp stops applying, which would ship a tree planted
    in 2108 and trip verify_seed.py check 14.
    """
    rows, spaces = load()
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=_resolver())
    records = list(a.records())
    # The count is asserted from the FIXTURE's own rows, before any probe call
    # touches the counter -- an assertion a direct parse_planted_date() call had
    # already incremented would be proving its own probe, not the adapter.
    future_rows = [r for r in rows if (r.get("planteddate") or "") > "2027"]
    check(bool(future_rows),
          "the fixture holds no future-dated row, so this test proves nothing")
    check(a.stats["planted_date_beyond_horizon"] == len(future_rows),
          f"the clamp counted {a.stats['planted_date_beyond_horizon']} rejections "
          f"but the fixture holds {len(future_rows)} future-dated rows")
    for record, row in zip(records, rows):
        if (row.get("planteddate") or "") > "2027":
            check(record.planted_on is None,
                  f"a PlantedDate of {row['planteddate']!r} survived the horizon clamp "
                  f"as {record.planted_on!r}")
    check(a.parse_planted_date("2015-08-25 10:46:44") is not None,
          "the clamp rejected a real 2015 planting date")


def test_the_horizon_is_the_seed_epoch_not_the_wall_clock():
    """ERRATA E13: a clock reading inside a byte-for-byte reproducible seed is a
    defect. Fails if the adapter reads the current year instead of its argument."""
    rows, spaces = load()
    tight = NYCTreePointAdapter(rows, spaces, 2016, borough_resolver=_resolver())
    check(tight.parse_planted_date("2020-01-01 00:00:00") is None,
          "a horizon of 2016 accepted a 2020 date; the adapter is not using its argument")


def test_the_borough_rides_on_every_record_that_has_one():
    """The distribution design makes a borough-level region the published unit,
    and `boroughcode` exists only on Planting Spaces. If it does not ride on the
    record, recovering it later means re-fetching 1.09 million rows.

    Fails if the borough stops reaching `raw_json`, or is emitted only under
    `--with-city-raw` (it must be unconditional), or is invented for a row that
    joined to no planting space.
    """
    rows, spaces = load()
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough_resolver=_resolver())  # NOTE: with_raw defaults to False
    for record, row in zip(list(a.records()), rows):
        space = spaces.get((row.get("plantingspaceglobalid") or "").strip())
        stated = (space or {}).get("boroughcode") or None
        carried = json.loads(record.raw_json)["boroughcode"] if record.raw_json else None
        source = json.loads(record.raw_json)["boroughsource"] if record.raw_json else None
        if stated:
            # A stated borough must be carried verbatim and credited to the
            # planting space -- RULING D18's precedence.
            check(carried == stated and source == "planting_space",
                  f"record carries borough {carried!r} from {source!r} but its planting "
                  f"space states {stated!r} (globalid={row.get('globalid')})")
        else:
            # No stated borough: D18 requires geometry to supply one, and the
            # record must say that is where it came from.
            check(carried is not None and source in ("point_in_polygon", "nearest_polygon"),
                  f"a row with no stated borough carries {carried!r} from {source!r} "
                  f"(globalid={row.get('globalid')}, case={row.get('_case')!r})")
    check(a.stats["borough_carried"] > 0, "no record carried a borough at all")
    check(a.stats["borough_carried"] + a.stats["no_borough_to_carry"] == a.stats["source_rows"],
          f"the borough counters total "
          f"{a.stats['borough_carried'] + a.stats['no_borough_to_carry']} of "
          f"{a.stats['source_rows']} rows")


def test_an_orphan_borough_is_geometric_and_says_so():
    """SUPERSEDES a pre-D18 test that asserted the opposite.

    Before RULING D18 an orphan carried NO borough, precisely so that none was
    ever inferred from coordinates. D18 reverses that -- borough packs must sum
    to the whole city -- so geometry now ASSIGNS one. What must not be lost is
    the distinction, so the record records WHICH source placed it.

    Fails if a geometric borough is passed off as the City's own attribution.
    """
    _a, pairs = run()
    orphans = by_case(pairs, "full/ORPHAN no ps match")
    check(bool(orphans), "the fixture lost its orphan rows")
    for record in orphans:
        carried = json.loads(record.raw_json or "{}")
        check(carried.get("boroughsource") != "planting_space",
              "an orphan credits its borough to a planting space it never joined")
        check(carried.get("boroughsource") in ("point_in_polygon", "nearest_polygon"),
              f"an orphan's borough source is {carried.get('boroughsource')!r}")


def test_optional_passthroughs_are_gated_but_the_borough_is_not():
    """`RiskRating` and `psstatus` have no seed column either, but they are bulk
    and the borough is load-bearing. Fails if they stop being gated, or if
    gating them also gates the borough."""
    rows, spaces = load()
    plain = NYCTreePointAdapter(rows, spaces, HORIZON, with_raw=False, borough_resolver=_resolver())
    rich = NYCTreePointAdapter(rows, spaces, HORIZON, with_raw=True, borough_resolver=_resolver())
    plain_keys, rich_keys = set(), set()
    for record in plain.records():
        if record.raw_json:
            plain_keys |= set(json.loads(record.raw_json))
    for record in rich.records():
        if record.raw_json:
            rich_keys |= set(json.loads(record.raw_json))
    check(plain_keys == {"boroughcode", "boroughsource"},
          f"an ungated build emitted {sorted(plain_keys)}; only the borough and the "
          f"provenance of the borough are unconditional")
    check("boroughcode" in rich_keys, "the borough vanished from a --with-city-raw build")
    check(rich_keys - plain_keys, "--with-city-raw added nothing; the gate does nothing")


def test_the_borough_filter_drops_rather_than_reassigns():
    """A borough build is one flag. Fails if a filtered build keeps a row from
    another borough, or silently places an orphan (which has no borough at all)."""
    rows, spaces = load()
    boroughs = {(s.get("boroughcode") or "").strip() for s in spaces.values()}
    boroughs.discard("")
    check(bool(boroughs), "the fixture's planting spaces carry no borough at all")
    target = sorted(boroughs)[0]
    a = NYCTreePointAdapter(rows, spaces, HORIZON, borough=target, borough_resolver=_resolver())
    produced = list(a.records())
    for record in produced:
        check(record.attributes_from == "nyc_planting_spaces",
              "a borough build kept a row that joined to no planting space, so it "
              "cannot have a borough")
    check(a.stats["dropped_wrong_borough"] > 0,
          "the borough filter dropped nothing; it is not filtering")
    check(len(produced) + a.stats["dropped_wrong_borough"] == len(rows),
          f"{len(produced)} kept + {a.stats['dropped_wrong_borough']} dropped != {len(rows)} rows")


def test_the_structure_filter_reads_only_what_it_is_asked_for():
    """Fails if `--structures Full` silently ingests stumps too."""
    rows, spaces = load()
    a = NYCTreePointAdapter(rows, spaces, HORIZON, structures={"full"}, borough_resolver=_resolver())
    produced = list(a.records())
    check(bool(produced), "the Full filter produced nothing at all")
    for record in produced:
        check(record.city_record.get("plant_type") == "Full",
              f"a structures={{'full'}} build emitted plant_type="
              f"{record.city_record.get('plant_type')!r}")
    check(a.stats["dropped_wrong_structure"] > 0, "the structure filter dropped nothing")


def test_the_stats_account_for_every_row():
    """Fails if a row is read and lands in no counter -- which is how a silent
    drop hides."""
    a, pairs = run()
    check(a.stats["source_rows"] == len(pairs),
          f"source_rows={a.stats['source_rows']} against {len(pairs)} records")
    joined = a.stats["joined_to_planting_space"] + a.stats["no_planting_space_match"]
    check(joined == a.stats["source_rows"],
          f"the join counters total {joined} of {a.stats['source_rows']} rows: {a.stats}")
    kinds = (a.stats["kind_from_structure_tree"]
             + a.stats["kind_from_structure_not_a_tree"]
             + a.stats["kind_inferred_from_absent_species"])
    check(kinds <= a.stats["source_rows"],
          f"the kind branches counted {kinds} of {a.stats['source_rows']} rows: {a.stats}")


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
