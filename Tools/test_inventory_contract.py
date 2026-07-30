#!/usr/bin/env python3
"""Tests for the ingest contract. Pure Python, no database, no simulator.

    python3 Tools/test_inventory_contract.py

They run here rather than in `CypressTests` because the contract is a property of
the *ingest*, and the ingest is Python. What belongs in the Swift suite is the
other half -- that the seed on disk satisfies what was promised here -- and that
lives in `CypressTests/InventoryContractTests.swift`.

Every test states what would have to go wrong for it to fail, because a test
whose failure mode nobody can name is a test nobody will fix correctly.
"""

from __future__ import annotations

import datetime
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from inventory_adapters import (  # noqa: E402
    SFCityLayerAdapter,
    SFDataSFAdapter,
    parse_dbh_inches,
    parse_planted_date,
    qspecies_to_contract,
)
from inventory_contract import (  # noqa: E402
    ID_SPACES,
    IDENTITY_SEPARATOR,
    INVENTORIES,
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    ContractError,
    IdSpace,
    InventoryRecord,
    KindBasis,
    check_id_space_registry,
    require_id_space,
    require_inventory,
)

# The frozen namespace `build_seed.py` derives tree uuids in. Restated rather
# than imported so that a change to it fails here loudly instead of being
# followed silently.
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def tree(**overrides) -> InventoryRecord:
    """A minimal valid record, for tests that vary one thing about it."""
    base = dict(
        inventory="datasf",
        kind=KIND_TREE,
        kind_basis=KindBasis.STATED_CATEGORY,
        lat=37.7761,
        lon=-122.4464,
        source_ref="276198",
        scientific_name="Pinus radiata",
        common_name="Monterey Pine",
        species_confidence=1.0,
        species_text="Pinus radiata :: Monterey Pine",
    )
    base.update(overrides)
    return InventoryRecord(**base)


def uuid_for(record: InventoryRecord, space: str = "sf") -> str:
    return str(uuid.uuid5(NS_TREE, record.identity_seed(ID_SPACES[space])))


# ---------------------------------------------------------------------------
# 1. Identity is stable, and it is qualified by id space
# ---------------------------------------------------------------------------


def test_identity_is_stable_for_san_francisco():
    """FAILS IF: the uuid derivation moves. Every public tree URL would change.

    `80a237b1-...` is TreeID 276198, `1 TWIN PEAKS BLVD` -- the 36-inch Monterey
    Pine that started #91 -- read out of the shipped seed. It is written down
    here so that a change to `IdSpace.identity_prefix`, to the namespace, or to
    the seed-string format cannot pass silently.
    """
    check(
        uuid_for(tree()) == "80a237b1-ba0a-515b-8c96-3da5a790c69d",
        "SF uuid derivation moved: TreeID 276198 no longer mints the shipped uuid",
    )
    check(
        ID_SPACES["sf"].identity_prefix == "",
        "the 'sf' identity prefix is no longer empty; all 145,837 shipped uuids move",
    )


def test_the_two_sf_inventories_share_an_identity_on_purpose():
    """FAILS IF: someone 'fixes' the collision between `city` and `datasf`.

    They publish the same TreeID space. Their uuids colliding is what made the
    DataSF -> city switch reversible with zero uuids moved (E156), and what keeps
    a photograph attached to its tree across a source change.
    """
    from_export = tree(inventory="datasf", source_ref="266901")
    from_layer = tree(inventory="city", source_ref="266901")
    check(
        INVENTORIES["city"].id_space == INVENTORIES["datasf"].id_space == "sf",
        "SF's two inventories are no longer in one id space; a source switch would orphan data",
    )
    check(
        uuid_for(from_export) == uuid_for(from_layer) == "62b2911f-c0f1-5876-9922-c92a69e94bcc",
        "the same TreeID in SF's two inventories no longer mints the same uuid",
    )


def test_two_cities_cannot_collide():
    """FAILS IF: a second city's ids mint San Francisco's uuids.

    This is the whole reason identity is qualified. Los Angeles TreeID 276198 is
    not `1 TWIN PEAKS BLVD`, and before this contract there was nothing in the
    derivation that knew the difference.
    """
    la = IdSpace(id="us-ca-la", identity_prefix="us-ca-la:")
    sf_record = tree(source_ref="276198")
    la_seed = la.identity_seed("276198")
    check(la_seed == "us-ca-la:276198", f"unexpected LA seed string {la_seed!r}")
    check(
        str(uuid.uuid5(NS_TREE, la_seed)) != uuid_for(sf_record),
        "a second city's TreeID 276198 mints San Francisco's uuid",
    )


def test_a_new_id_space_cannot_be_registered_wrongly():
    """FAILS IF: the guards that keep city two out of SF's uuid space come off."""
    saved = dict(ID_SPACES)
    try:
        ID_SPACES["us-ca-la"] = IdSpace(id="us-ca-la", identity_prefix="")
        raised = False
        try:
            require_id_space("us-ca-la")
        except ContractError:
            raised = True
        check(raised, "an id space with an empty prefix was accepted; it would mint SF's uuids")
        check(
            check_id_space_registry(),
            "the registry check did not object to a second empty-prefix id space",
        )

        ID_SPACES["us-ca-la"] = IdSpace(id="us-ca-la", identity_prefix="us-ca-la")
        raised = False
        try:
            require_id_space("us-ca-la")
        except ContractError:
            raised = True
        check(raised, "an id space whose prefix does not end in the separator was accepted")
    finally:
        ID_SPACES.clear()
        ID_SPACES.update(saved)

    check(check_id_space_registry() == [], "the shipped id-space registry does not validate")


def test_an_unregistered_source_is_refused():
    """FAILS IF: a row can name an inventory the app cannot describe on screen.

    That is the defect the per-row provenance line was added to end: a row whose
    inventory has no name and no snapshot date draws somebody else's.
    """
    raised = False
    try:
        require_inventory("us-ca-la-streets")
    except ContractError:
        raised = True
    check(raised, "an unregistered inventory was accepted")
    check(
        tree(inventory="us-ca-la-streets").validate(),
        "a record naming an unregistered inventory validated clean",
    )


def test_a_source_ref_cannot_alias_another_id_space():
    """FAILS IF: a source whose ids contain ':' can forge another space's uuid."""
    check(
        tree(source_ref=f"us-ca-la{IDENTITY_SEPARATOR}1").validate(),
        "a source_ref containing the identity separator validated clean",
    )


def test_a_record_with_no_source_ref_says_so():
    """FAILS IF: a record with no upstream id silently claims a stable identity.

    Some DataSF rows carry no TreeID. Their uuid is keyed on their own facts,
    which is a weaker promise -- it moves if the city re-geocodes the row -- and
    the weakness has to be readable rather than hidden behind a uuid that looks
    like every other uuid.
    """
    anonymous = tree(source_ref=None)
    check(not anonymous.has_stable_identity, "a record with no source_ref claims stable identity")
    check(anonymous.validate() == [], "a record with no source_ref should still be valid")
    raised = False
    try:
        anonymous.identity_seed(ID_SPACES["sf"])
    except ContractError:
        raised = True
    check(raised, "identity_seed produced a seed string for a record with no source_ref")
    check(
        tree(source_ref="   ").validate(),
        "a blank source_ref validated clean; absent must be None, not whitespace",
    )


# ---------------------------------------------------------------------------
# 2. A missing optional field does not become a lie
# ---------------------------------------------------------------------------


def test_absent_is_none_and_never_an_empty_string():
    """FAILS IF: an adapter may pass '' for a value its source did not publish.

    An empty string in a column makes "the city recorded nothing" and "the city
    recorded nothing-in-particular" indistinguishable to every reader downstream,
    and the app has a screen for each.
    """
    for field in ("address", "site_type", "species_text", "scientific_name", "common_name"):
        check(
            tree(**{field: "   "}).validate(),
            f"a blank {field} validated clean; absent must be None",
        )
    check(
        tree(city_record={"plot_size": ""}).validate(),
        "a blank city_record value validated clean; absent must be None",
    )
    check(tree(address=None, site_type=None).validate() == [], "None in an optional field is valid")


def test_a_sentinel_dimension_is_the_adapters_problem():
    """FAILS IF: a source's 'not recorded' zero reaches the seed as a measurement.

    Both SF inventories write `DBH = 0` for "not recorded". A downstream reader
    cannot know that -- only the adapter can -- so the contract refuses a
    non-positive measurement outright and `parse_dbh_inches` resolves it first.
    """
    check(tree(dbh_in=0).validate(), "dbh_in=0 validated clean; it is a sentinel, not a trunk")
    check(tree(dbh_in=-3).validate(), "a negative dbh_in validated clean")
    check(tree(dbh_in=None).validate() == [], "an absent dbh_in must be valid")
    check(tree(dbh_in=36.0).validate() == [], "a measured dbh_in must be valid")
    check(parse_dbh_inches("0") is None, "DBH '0' did not resolve to 'not recorded'")
    check(parse_dbh_inches("") is None, "a blank DBH did not resolve to 'not recorded'")
    check(parse_dbh_inches("36") == 36.0, "DBH '36' did not survive as a measurement")
    check(parse_dbh_inches("9999") is None, "an absurd DBH was not rejected")


def test_a_sentinel_date_is_the_adapters_problem():
    """FAILS IF: a placeholder planting date becomes a planting date.

    The almanac's elder and plantings rows read `planted_on` directly, so a
    sentinel year here is a wrong sentence on screen, not a wrong number in a file.
    """
    check(
        parse_planted_date("03/08/2024 12:00:00 AM", 2027) == datetime.date(2024, 3, 8),
        "a real DataSF PlantDate did not parse",
    )
    check(parse_planted_date("", 2027) is None, "a blank PlantDate did not resolve to None")
    check(parse_planted_date("01/01/1700", 2027) is None, "a pre-1800 sentinel date was accepted")
    check(parse_planted_date("01/01/2999", 2027) is None, "a far-future sentinel date was accepted")
    check(
        parse_planted_date("03/08/2028", 2027) is None,
        "the horizon is not the seed epoch's; a clock reading is back in the build (E13)",
    )


def test_confidence_cannot_float_free_of_a_name():
    """FAILS IF: a record claims confidence in a species it does not name."""
    check(
        tree(scientific_name=None, species_confidence=0.9).validate(),
        "species_confidence survived with no scientific_name to be confident about",
    )
    check(tree(species_confidence=1.4).validate(), "a confidence above 1 validated clean")
    check(
        tree(scientific_name=None, common_name=None, species_confidence=None).validate() == [],
        "a tree of unknown species must be valid; that is the point",
    )


# ---------------------------------------------------------------------------
# 3. Kind is stated, not inferred from a hole  (tasks #94 and #103)
# ---------------------------------------------------------------------------


def test_a_tree_of_unknown_species_is_a_tree():
    """FAILS IF: omitting a species turns a tree into an empty hole in the pavement.

    This is task #94's mechanism at the schema level. The seed holds 1,326 rows
    whose `qLegalStatus` is `DPW Maintained` -- the city maintains a street tree
    there -- and whose species field is blank, and it draws all of them as vacant
    planting sites. Under this contract a source that says nothing about the
    species of a tree still has a tree.
    """
    unknown = tree(scientific_name=None, common_name=None, species_confidence=None, species_text=None)
    check(unknown.kind == KIND_TREE, "the fixture is not a tree")
    check(unknown.validate() == [], f"a tree of unknown species was rejected: {unknown.validate()}")


def test_a_planting_site_cannot_name_a_species():
    """FAILS IF: an empty planting site can carry a species.

    The other direction of the same defect, and the one that would put a field
    guide, a phenology strip and an autumn colour chip on a hole in the pavement.
    """
    check(
        tree(kind=KIND_PLANTING_SITE, kind_basis=KindBasis.STATED).validate(),
        "a planting site naming a species validated clean",
    )
    empty = tree(
        kind=KIND_PLANTING_SITE,
        kind_basis=KindBasis.STATED,
        scientific_name=None,
        common_name=None,
        species_confidence=None,
        species_text="Tree(s) ::",
    )
    check(empty.validate() == [], f"a real planting site was rejected: {empty.validate()}")


def test_kind_must_be_stated_and_cannot_be_defaulted():
    """FAILS IF: `kind` gains a default. A default is an inference with no author."""
    import inspect

    signature = inspect.signature(InventoryRecord.__init__)
    for required in ("inventory", "kind", "kind_basis", "lat", "lon"):
        check(
            signature.parameters[required].default is inspect.Parameter.empty,
            f"{required} has a default; a source can now omit it and get one silently",
        )
    check(tree(kind="sapling").validate(), "an unknown kind validated clean")
    check(tree(kind_basis="because").validate(), "an unknown kind_basis validated clean")


def test_the_inferred_basis_is_only_ever_a_planting_site():
    """FAILS IF: the counter that measures #94 can be attached to anything else.

    `INFERRED_FROM_ABSENT_SPECIES` exists to be counted. If it can appear on a
    tree the count stops meaning what the build receipt says it means.
    """
    check(
        tree(kind_basis=KindBasis.INFERRED_FROM_ABSENT_SPECIES).validate(),
        "the inferred-from-absent-species basis was accepted on a tree",
    )


def test_the_sf_species_strings_classify_the_way_the_data_says():
    """FAILS IF: the split between 'the source said so' and 'we guessed' moves.

    Counts are from the live DataSF export, measured 2026-07-28:
      `Tree(s) ::`                        11,818 rows, 9,738 `Permitted Site`
      `Potential Site :: Potential Site`     155 rows
      `::`                                 1,657 rows, 1,326 `DPW Maintained`
      `Tree :: Tree`                         130 rows
    The first two are the source describing a site. The last two are our seed
    describing one, and the source describing a tree or nothing at all.
    """
    stated = ["Tree(s) ::", "Potential Site :: Potential Site", "Vacant Site ::"]
    for text in stated:
        kind, basis, sci, common, conf, stub = qspecies_to_contract(text)
        check(kind == KIND_PLANTING_SITE, f"{text!r} is no longer a planting site")
        check(basis == KindBasis.STATED, f"{text!r} is no longer a STATED vacancy")

    guessed = ["", "::", "Tree :: Tree", ":: Tree", "nan ::"]
    for text in guessed:
        kind, basis, sci, common, conf, stub = qspecies_to_contract(text)
        check(kind == KIND_PLANTING_SITE, f"{text!r} is no longer a planting site")
        check(
            basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES,
            f"{text!r} now claims the source stated a vacancy; it did not",
        )

    for text in ("Shrub :: Shrub", "Private shrub :: Private shrub", "Privet ::"):
        kind, basis, sci, common, conf, stub = qspecies_to_contract(text)
        check(kind == KIND_NOT_A_TREE, f"{text!r} is no longer classified as not-a-tree")
        check(basis == KindBasis.STATED_AS_NON_TAXON, f"{text!r} lost its basis")
        check(sci is None, f"{text!r} minted a species name")

    kind, basis, sci, common, conf, stub = qspecies_to_contract("Pinus radiata :: Monterey Pine")
    check((kind, sci, common, conf, stub) == (KIND_TREE, "Pinus radiata", "Monterey Pine", 1.0, False),
          "a clean binomial no longer parses to a tree with full confidence")


def test_a_common_name_alone_does_not_mint_a_scientific_name():
    """FAILS IF: a vernacular can become a species row's scientific name.

    Task #103: eight stub species shadow a species already in the corpus because
    a source named it in a form the catalogue did not match. The contract holds
    the two names in two fields, so a source that publishes only a common name
    can set `common_name` and leave `scientific_name` None -- the one shape in
    which no stub can be minted at all.
    """
    vernacular_only = tree(
        scientific_name=None,
        common_name="Brisbane Box",
        species_confidence=None,
        species_text=":: Brisbane Box",
    )
    check(vernacular_only.validate() == [], "a common-name-only record was rejected")
    check(
        vernacular_only.species_is_stub is False and vernacular_only.scientific_name is None,
        "a common-name-only record carries a scientific name it never had",
    )
    check(
        tree(scientific_name=None, species_is_stub=True).validate(),
        "a record claims a stubbed species with no name to have stubbed",
    )


# ---------------------------------------------------------------------------
# 4. The adapters actually satisfy the contract
# ---------------------------------------------------------------------------


def test_the_city_adapter_reads_the_layers_own_fields():
    """FAILS IF: the city layer's two clean name fields stop round-tripping.

    475 of its rows leave `BOTANICAL` null and put the botanical name in
    `COMMON`. Without the swap each mints a stub species beside the real species
    it names.
    """
    rows = [
        {"TREEID": 276198, "Latitude": 37.75916, "Longitude": -122.448345,
         "Address": "1 TWIN PEAKS BLVD", "PlantType": "Tree",
         "BOTANICAL": "Pinus radiata", "COMMON": "Monterey Pine", "DBH": 36},
        # BOTANICAL null, binomial in COMMON -- the 475.
        {"TREEID": 999001, "Latitude": 37.76, "Longitude": -122.44,
         "Address": "1 TEST ST", "PlantType": "Tree",
         "BOTANICAL": None, "COMMON": "Lophostemon confertus", "DBH": 0},
        # The city's own literal statement of an empty site.
        {"TREEID": 999002, "Latitude": 37.76, "Longitude": -122.44,
         "Address": "2 TEST ST", "PlantType": "Tree",
         "BOTANICAL": "Potential Site", "COMMON": "Potential Site", "DBH": None},
        # The city said nothing at all about the species.
        {"TREEID": 999003, "Latitude": 37.76, "Longitude": -122.44,
         "Address": "3 TEST ST", "PlantType": "Tree",
         "BOTANICAL": None, "COMMON": None, "DBH": None},
        # No position: dropped by the adapter, counted, never yielded.
        {"TREEID": 999004, "Latitude": None, "Longitude": None,
         "Address": "4 TEST ST", "PlantType": "Tree",
         "BOTANICAL": "Pinus radiata", "COMMON": "Monterey Pine", "DBH": 1},
    ]
    adapter = SFCityLayerAdapter(rows, enrichment={}, horizon_year=2027)
    got = list(adapter.records())

    check(len(got) == 4, f"the city adapter yielded {len(got)} records, expected 4")
    check(adapter.stats["dropped_no_coords"] == 1, "the positionless record was not dropped")
    check(all(r.validate() == [] for r in got),
          "the city adapter produced a record the contract refuses: "
          + str([r.validate() for r in got]))
    check(all(r.inventory == "city" for r in got), "the city adapter mislabelled its inventory")
    check(
        all(r.attributes_from is None for r in got),
        "with no export index every record must say its facts are the layer's own",
    )

    by_ref = {r.source_ref: r for r in got}
    check(by_ref["276198"].scientific_name == "Pinus radiata", "the plain case stopped parsing")
    check(by_ref["276198"].dbh_in == 36.0, "DBH 36 did not survive as a measurement")
    check(
        by_ref["999001"].scientific_name == "Lophostemon confertus",
        "the BOTANICAL/COMMON swap stopped working; 475 stub species come back",
    )
    check(by_ref["999001"].dbh_in is None, "DBH 0 was read as a zero-inch trunk")
    check(
        (by_ref["999002"].kind, by_ref["999002"].kind_basis)
        == (KIND_PLANTING_SITE, KindBasis.STATED),
        "the city's literal 'Potential Site' is no longer a stated vacancy",
    )
    check(
        by_ref["999003"].kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES,
        "a city record with no species text no longer reports that its vacancy was inferred",
    )
    # The seven export columns are absent, and absent reads as absent.
    check(
        by_ref["276198"].city_record["legal_status"] is None
        and by_ref["276198"].city_record["plant_type"] == "Tree",
        "the city adapter filled in a column its layer does not publish",
    )
    check(by_ref["276198"].planted_on is None, "the city adapter invented a planting date")


def test_where_the_facts_came_from_is_a_property_of_the_record():
    """FAILS IF: 'which list supplied this row's facts' stops being on the record.

    It was a counter inside the city adapter, incremented at the moment of the
    join — which overstated `seed_meta.rows_enriched` by 55, because a record can
    be joined and then dropped by the corpus bounding box or as a duplicate ref.
    A count of rows that shipped has to be taken where rows ship.

    It is also the other half of provenance: `inventory` says which list contained
    the record, `attributes_from` says which list its facts came from, and without
    the second a reader cannot tell a joined record from one whose columns are
    simply absent.
    """
    rows = [
        {"TREEID": 1, "Latitude": 37.76, "Longitude": -122.44, "Address": "1 A ST",
         "PlantType": "Tree", "BOTANICAL": "Pinus radiata", "COMMON": "Monterey Pine", "DBH": 10},
        {"TREEID": 2, "Latitude": 37.76, "Longitude": -122.44, "Address": "2 A ST",
         "PlantType": "Tree", "BOTANICAL": "Pinus radiata", "COMMON": "Monterey Pine", "DBH": 10},
    ]
    enrichment = {"1": {"qLegalStatus": "DPW Maintained", "qSiteInfo": None, "qCaretaker": None,
                        "qCareAssistant": None, "PlantDate": None, "PlotSize": None,
                        "PermitNotes": None}}
    got = {r.source_ref: r for r in SFCityLayerAdapter(rows, enrichment, 2027).records()}

    check(got["1"].attributes_from == "datasf", "a joined record does not say where its facts came from")
    check(
        got["2"].attributes_from is None,
        "a record only the listing inventory holds claims its facts came from elsewhere",
    )
    check(all(r.validate() == [] for r in got.values()), "attributes_from broke validation")
    check(
        tree(inventory="city", attributes_from="city").validate(),
        "attributes_from naming the listing inventory validated clean; that case is spelled None",
    )
    check(
        tree(attributes_from="us-ca-la-streets").validate(),
        "attributes_from naming an unregistered inventory validated clean",
    )


def test_the_datasf_adapter_reads_the_exports_own_fields(tmp_csv):
    """FAILS IF: the export adapter stops resolving the export's own conventions."""
    adapter = SFDataSFAdapter(tmp_csv, horizon_year=2027)
    got = list(adapter.records())
    check(len(got) == 3, f"the export adapter yielded {len(got)} records, expected 3")
    check(adapter.stats["dropped_no_coords"] == 1, "the positionless row was not dropped")
    check(all(r.validate() == [] for r in got),
          "the export adapter produced a record the contract refuses: "
          + str([r.validate() for r in got]))
    by_ref = {r.source_ref: r for r in got}
    check(by_ref["1"].scientific_name == "Pinus radiata", "a clean qSpecies stopped parsing")
    check(by_ref["1"].planted_on == datetime.date(2024, 3, 8), "PlantDate stopped parsing")
    check(by_ref["1"].city_record["legal_status"] == "DPW Maintained",
          "qLegalStatus is no longer carried into the seed column")
    check(by_ref["2"].kind == KIND_PLANTING_SITE and by_ref["2"].kind_basis == KindBasis.STATED,
          "'Tree(s) ::' is no longer a stated planting site")
    check(by_ref["3"].kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES,
          "a blank qSpecies on a DPW Maintained row no longer reports an inferred vacancy")

    only_sites = list(SFDataSFAdapter(tmp_csv, horizon_year=2027, planting_sites_only=True).records())
    check(
        len(only_sites) == 2 and all(r.kind == KIND_PLANTING_SITE for r in only_sites),
        "planting_sites_only let something through that is not a planting site",
    )


def _write_csv(path):
    import csv as _csv

    columns = [
        "TreeID", "qSpecies", "qAddress", "Latitude", "Longitude", "PlantDate", "DBH",
        "qSiteInfo", "qLegalStatus", "qCaretaker", "qCareAssistant", "PlantType",
        "PlotSize", "PermitNotes", "SiteOrder",
    ]
    rows = [
        ["1", "Pinus radiata :: Monterey Pine", "1 Twin Peaks Blvd", "37.75916", "-122.448345",
         "03/08/2024 12:00:00 AM", "36", "Sidewalk: Curb side : Cutout", "DPW Maintained",
         "Private", "", "Tree", "3x3", "", "1"],
        ["2", "Tree(s) ::", "2 Test St", "37.76", "-122.44", "", "0", "", "Permitted Site",
         "Private", "", "Tree", "", "notes", "1"],
        ["3", "", "3 Test St", "37.76", "-122.44", "", "", "", "DPW Maintained",
         "DPW", "", "Tree", "", "", "1"],
        ["4", "Pinus radiata :: Monterey Pine", "4 Test St", "", "", "", "12", "", "DPW Maintained",
         "DPW", "", "Tree", "", "", "1"],
    ]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = _csv.writer(fh)
        writer.writerow(columns)
        writer.writerows(rows)
    return path


def main() -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        csv_path = _write_csv(os.path.join(directory, "export.csv"))
        tests = [
            test_identity_is_stable_for_san_francisco,
            test_the_two_sf_inventories_share_an_identity_on_purpose,
            test_two_cities_cannot_collide,
            test_a_new_id_space_cannot_be_registered_wrongly,
            test_an_unregistered_source_is_refused,
            test_a_source_ref_cannot_alias_another_id_space,
            test_a_record_with_no_source_ref_says_so,
            test_absent_is_none_and_never_an_empty_string,
            test_a_sentinel_dimension_is_the_adapters_problem,
            test_a_sentinel_date_is_the_adapters_problem,
            test_confidence_cannot_float_free_of_a_name,
            test_a_tree_of_unknown_species_is_a_tree,
            test_a_planting_site_cannot_name_a_species,
            test_kind_must_be_stated_and_cannot_be_defaulted,
            test_the_inferred_basis_is_only_ever_a_planting_site,
            test_the_sf_species_strings_classify_the_way_the_data_says,
            test_a_common_name_alone_does_not_mint_a_scientific_name,
            test_the_city_adapter_reads_the_layers_own_fields,
            test_where_the_facts_came_from_is_a_property_of_the_record,
        ]
        for test in tests:
            test()
        test_the_datasf_adapter_reads_the_exports_own_fields(csv_path)

    print(f"{PASSED} checks passed, {len(FAILURES)} failed")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
