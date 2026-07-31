#!/usr/bin/env python3
"""Tests for the San Jose adapter, run against rows San Jose actually published.

    python3 Tools/test_ca_inventory_adapter.py

WHY THE FIXTURE IS REAL ROWS. An adapter tested against rows invented to match
it tests nothing except that its author was self-consistent. Every row in
`Fixtures/ca_survey/san_jose_street_tree_sample.json` came verbatim off
`geo.sanjoseca.gov/.../MapServer/510` on 2026-07-31, and the sample was selected
by querying for each case the adapter has a rule for -- so if the city's data
does not contain the case, the fixture does not contain it either and the test
that needs it fails loudly instead of passing on a fake.

They live here rather than in `test_inventory_contract.py` so that the contract's
own suite stays a statement about the contract, and so two parallel agents adding
sources do not both edit one file.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import json
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from inventory_adapters import SanJoseStreetTreeAdapter  # noqa: E402
from inventory_contract import (  # noqa: E402
    ID_SPACES,
    IDENTITY_SEPARATOR,
    INVENTORIES,
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    ContractError,
    KindBasis,
    check_id_space_registry,
    require_id_space,
    require_inventory,
    validate_or_raise,
)

# The frozen namespace `build_seed.py` derives tree uuids in. Restated rather
# than imported, exactly as `test_inventory_contract.py` restates it, so a change
# to it fails here loudly instead of being followed silently.
NS_TREE = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")

FIXTURE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Fixtures", "ca_survey", "san_jose_street_tree_sample.json",
)

FAILURES: list[str] = []
PASSED = 0


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def load_rows() -> list:
    with open(FIXTURE) as fh:
        return json.load(fh)["rows"]


def rows_for(case_fragment: str) -> list:
    """The fixture rows whose recorded case mentions `case_fragment`."""
    return [r for r in load_rows() if case_fragment.lower() in r["case"].lower()]


def records_for(case_fragment: str, adapter=None):
    adapter = adapter or SanJoseStreetTreeAdapter(rows_for(case_fragment))
    return list(adapter.records()), adapter


def by_ref(records) -> dict:
    return {r.source_ref: r for r in records}


# ---------------------------------------------------------------------------
# 1. The fixture is what it claims to be
# ---------------------------------------------------------------------------


def test_the_fixture_is_real_rows_covering_every_rule():
    """FAILS IF: the fixture was regenerated from invented data, or a case vanished.

    The adapter has a branch per case below. A fixture missing one of them makes
    the corresponding test vacuously green, which is the failure mode that makes
    an adapter test suite worthless.
    """
    rows = load_rows()
    check(len(rows) == 29, f"the fixture holds {len(rows)} rows, expected the 29 sampled")
    cases = {r["case"] for r in rows}
    for needed in (
        "ordinary tree", "genus only", "cultivar", "lower-case vacancy string",
        "title-case vacancy string", "silent in the spec", "stump",
        "could not identify", "exactly 0", "install date", "names a real taxon",
        "trailing space", "no vacancy statement", "past any believable",
        "flag says occupied",
    ):
        check(
            any(needed.lower() in c.lower() for c in cases),
            f"the fixture no longer covers the case {needed!r}; a rule below is untested",
        )
    for r in rows:
        a = r["attributes"]
        check(a.get("FACILITYID") is not None, "a fixture row has no FACILITYID")
        check(
            (r.get("geometry") or {}).get("x") is not None,
            f"fixture row {a.get('FACILITYID')} has no geometry; it was not taken from the layer",
        )


# ---------------------------------------------------------------------------
# 2. Identity -- the load-bearing half of R18
# ---------------------------------------------------------------------------


def test_san_jose_is_its_own_id_space():
    """FAILS IF: San Jose is registered into San Francisco's uuid space.

    `sf`'s prefix is the frozen empty string, so an `sf` seed string IS a TreeID.
    San Jose's FACILITYID 3 and San Francisco's TreeID 3 are different trees in
    different cities and must not be one uuid.
    """
    space = require_id_space("us-ca-sj")
    check(space.identity_prefix == "us-ca-sj:", f"unexpected prefix {space.identity_prefix!r}")
    check(
        space.identity_prefix.endswith(IDENTITY_SEPARATOR),
        "San Jose's prefix does not end in the separator, so seed strings could alias",
    )
    sj = uuid.uuid5(NS_TREE, space.identity_seed("276198"))
    sf = uuid.uuid5(NS_TREE, ID_SPACES["sf"].identity_seed("276198"))
    check(sj != sf, "San Jose's FACILITYID 276198 mints San Francisco's uuid for TreeID 276198")
    check(
        str(sf) == "80a237b1-ba0a-515b-8c96-3da5a790c69d",
        "the premise is wrong: SF's uuid for 276198 is no longer the shipped one",
    )


def test_the_registry_still_agrees_with_itself():
    """FAILS IF: adding San Jose broke a rule the registry enforces for everyone.

    Two spaces sharing a prefix is the silent failure R18 names: it produces
    valid-looking uuids and is discovered only when two cities' trees turn out to
    share an identity.
    """
    problems = check_id_space_registry()
    check(problems == [], f"the id-space registry objects to itself: {problems!r}")
    inventory = require_inventory("sj_street_tree")
    check(inventory.id_space == "us-ca-sj", "San Jose's inventory is in the wrong id space")
    check(
        INVENTORIES["sj_street_tree"].id_space != INVENTORIES["sf_city"].id_space,
        "San Jose shares an id space with San Francisco; their uuids would collide",
    )


def test_every_record_has_a_stable_identity():
    """FAILS IF: a San Jose record falls back to the weaker facts-keyed identity.

    FACILITYID was measured non-null and distinct on all 344,879 rows on
    2026-07-31. If that stops being true the fallback is silent, so it is asserted.
    """
    records, _ = records_for("")
    check(len(records) == 29, f"got {len(records)} records from 29 rows")
    for record in records:
        check(
            record.has_stable_identity,
            f"record at {record.lat},{record.lon} has no source_ref and would be keyed on facts",
        )
        check(
            IDENTITY_SEPARATOR not in (record.source_ref or ""),
            f"source_ref {record.source_ref!r} contains {IDENTITY_SEPARATOR!r} and could alias",
        )
    refs = [r.source_ref for r in records]
    check(len(set(refs)) == len(refs), f"the sample has duplicate source_refs: {refs}")


# ---------------------------------------------------------------------------
# 3. Every record the adapter emits satisfies the contract
# ---------------------------------------------------------------------------


def test_every_record_validates():
    """FAILS IF: the adapter emits a record the contract forbids.

    This is the whole claim of the exercise -- that a genuinely foreign inventory
    goes through `InventoryRecord` without the contract being widened for it.
    """
    records, _ = records_for("")
    for record in records:
        problems = record.validate()
        check(
            problems == [],
            f"record {record.source_ref} does not satisfy the contract: {problems}",
        )
        try:
            validate_or_raise(record)
        except ContractError as error:
            check(False, f"validate_or_raise rejected {record.source_ref}: {error}")


# ---------------------------------------------------------------------------
# 4. The kind decision, branch by branch
# ---------------------------------------------------------------------------


def test_an_ordinary_tree_is_a_tree_with_its_own_species():
    """FAILS IF: the clean-field path regressed into DataSF's packed convention.

    `NAMESCIENTIFIC` is one field holding one scientific name. It goes to
    `scientific_name` directly. A `::` appearing anywhere here means the third
    source inherited San Francisco's serialization format, which is what
    `SFCityLayerAdapter.species_of`'s docstring promised would not happen.
    """
    records, _ = records_for("ordinary tree")
    check(len(records) == 2, f"expected 2 ordinary-tree rows, got {len(records)}")
    for record in records:
        check(record.kind == KIND_TREE, f"{record.source_ref} is {record.kind}, not a tree")
        check(
            record.kind_basis == KindBasis.STATED_CATEGORY,
            f"{record.source_ref} has basis {record.kind_basis}; VACANTSITE='No' is a stated category",
        )
        check(
            record.scientific_name == "Platanus acerifolia",
            f"{record.source_ref} has scientific_name {record.scientific_name!r}",
        )
        check(record.species_confidence == 1.0, "a clean binomial did not earn confidence 1.0")
        check(record.common_name is None, "a common name was invented; San Jose publishes none")
        check("::" not in (record.species_text or ""), "a `::` reached a San Jose record")
    check(
        by_ref(records)["3"].dbh_in == 12.5,
        f"the measured 12.5 in trunk did not survive: {by_ref(records)['3'].dbh_in}",
    )


def test_a_genus_alone_is_a_tree_and_says_it_is_less_sure():
    """FAILS IF: `Quercus` is trusted like `Quercus agrifolia`, or is made a stub.

    644 rows name a genus and no epithet. That is a real, if partial, identification
    and it earns the same 0.7 the SF parser gives a genus -- one scale, two sources.
    """
    records, _ = records_for("genus only")
    for record in records:
        check(record.kind == KIND_TREE, f"{record.source_ref} is not a tree")
        check(record.scientific_name == "Quercus", f"got {record.scientific_name!r}")
        check(record.species_confidence == 0.7, f"got confidence {record.species_confidence}")
        check(not record.species_is_stub, "a genus published by the city was marked a stub")


def test_a_cultivar_survives_verbatim():
    """FAILS IF: quoting inside a name is stripped, or trips a parser.

    `Acer x fremanii 'Autumn Blaze'` carries single quotes, which is exactly the
    shape that breaks a source that round-trips names through a query string.
    """
    records, _ = records_for("cultivar")
    for record in records:
        check(
            record.scientific_name == "Acer x fremanii 'Autumn Blaze'",
            f"the cultivar did not survive: {record.scientific_name!r}",
        )
        check(record.species_confidence == 0.75, f"got confidence {record.species_confidence}")


def test_both_spellings_of_the_vacancy_string_mean_the_same_thing():
    """FAILS IF: `Vacant site` and `Vacant Site` are treated as two different facts.

    71,590 rows say one, 1,405 say the other, and they are one claim. A rule keyed
    on the literal string would classify 1,405 planting sites as trees of a species
    called `Vacant Site` -- #103's mechanism, at scale.
    """
    lower, _ = records_for("lower-case vacancy string")
    upper, _ = records_for("title-case vacancy string")
    for record in lower + upper:
        check(
            record.kind == KIND_PLANTING_SITE,
            f"{record.source_ref} ({record.species_text!r}) is {record.kind}, not a planting site",
        )
        check(
            record.kind_basis == KindBasis.STATED,
            f"{record.source_ref} has basis {record.kind_basis}; the city stated this vacancy",
        )
        check(
            record.scientific_name is None and record.common_name is None,
            f"{record.source_ref} is a planting site that names a species -- the record the "
            f"contract exists to forbid",
        )
        check(
            record.species_text is not None,
            "the city's own word was discarded; species_text is what the build reports on",
        )


def test_a_planting_site_never_carries_a_trunk_diameter():
    """FAILS IF: an empty hole ships a measured trunk.

    1,808 `Vacant site` rows carry a positive `TRUNKDIAM`. The contract permits
    it -- `validate()` only refuses a non-positive one -- so nothing but this rule
    stops a planting site claiming a 9 in trunk on the tree profile.
    """
    upper, adapter = records_for("title-case vacancy string")
    for record in upper:
        check(
            record.dbh_in is None,
            f"planting site {record.source_ref} kept a {record.dbh_in} in trunk",
        )
    check(
        adapter.stats["planting_sites_with_a_trunk_diameter"] == 2,
        f"the dropped trunks were not counted: {adapter.stats}",
    )


def test_a_vacant_site_that_names_a_taxon_keeps_the_flag_and_loses_the_species():
    """FAILS IF: 611 empty holes ship as trees, or the conflict stops being counted.

    The city says both things. `VACANTSITE` is the field whose only meaning is
    vacancy; `NAMESCIENTIFIC` carries four kinds of claim. The flag wins, and the
    row is counted so the size of the disagreement is a number in the receipt
    rather than an argument.
    """
    records, adapter = records_for("names a real taxon")
    check(len(records) == 2, f"expected 2 conflicting rows, got {len(records)}")
    for record in records:
        check(record.kind == KIND_PLANTING_SITE, f"{record.source_ref} is {record.kind}")
        check(record.scientific_name is None, f"{record.source_ref} kept {record.scientific_name!r}")
    check(
        adapter.stats["vacant_sites_naming_a_taxon"] == 2,
        f"the conflict was resolved silently: {adapter.stats}",
    )


def test_the_species_vocabulary_decides_when_the_flag_contradicts_it():
    """FAILS IF: 82 rows saying `Vacant site` under `VACANTSITE = 'No'` ship as trees.

    THIS IS THE BRANCH THE VACANCY VOCABULARY ACTUALLY DECIDES, and until this
    fixture case existed it was untested: every other vacancy row in the sample is
    also flagged `Yes`, so the flag reached the answer first and the vocabulary
    could have been keyed on the wrong case, or emptied, with the suite still
    green. A mutation run is what found that.

    Both rows also carry `TRUNKDIAM = 1`, so this is simultaneously the case where
    a planting site would ship a measured trunk.
    """
    records, adapter = records_for("flag says occupied")
    check(len(records) == 2, f"expected 2 rows, got {len(records)}")
    for record in records:
        check(
            record.kind == KIND_PLANTING_SITE,
            f"{record.source_ref} says {record.species_text!r} and became {record.kind}",
        )
        check(
            record.kind_basis == KindBasis.STATED,
            f"{record.source_ref} has basis {record.kind_basis}; the city stated this in words",
        )
        check(record.scientific_name is None, f"a species called {record.scientific_name!r} was minted")
        check(record.dbh_in is None, f"a planting site kept a {record.dbh_in} in trunk")
    check(
        adapter.stats["kind_from_species_vocabulary"] == 2,
        f"the vocabulary's decisions were counted as the flag's: {adapter.stats}",
    )


def test_a_stump_is_not_a_tree_and_is_not_an_empty_site():
    """FAILS IF: 1,933 stumps become street trees, or become vacant planting sites.

    Both halves of E169's defect meet here. A stump is a thing that is present --
    so not a planting site -- and it is not a tree. `not_a_tree` is the value that
    exists precisely so this fact has somewhere to go.
    """
    records, _ = records_for("stump")
    for record in records:
        check(record.kind == KIND_NOT_A_TREE, f"{record.source_ref} is {record.kind}")
        check(
            record.kind_basis == KindBasis.STATED_AS_NON_TAXON,
            f"{record.source_ref} has basis {record.kind_basis}",
        )
        check(record.scientific_name is None, "a stump was given a species")
        check(record.species_text == "Stump", "the city's own word was discarded")


def test_a_tree_the_surveyor_could_not_identify_is_still_a_tree():
    """FAILS IF: 4,513 `Unknown` rows become empty holes, or mint a species.

    R18 settled this: a tree of unknown species is a tree. `Unknown` is also the
    string most likely to be mistaken for a placeholder, and treating it as one
    would delete 4,513 trees from the map.
    """
    records, _ = records_for("could not identify")
    for record in records:
        check(record.kind == KIND_TREE, f"{record.source_ref} is {record.kind}, not a tree")
        check(record.scientific_name is None, f"a species was minted: {record.scientific_name!r}")
        check(record.species_confidence is None, "confidence was set with no name to be sure of")
        check(not record.species_is_stub, "`Unknown` minted a stub species")
        check(record.species_text == "Unknown", "the city's own word was discarded")


def test_a_row_with_no_vacancy_statement_falls_back_to_the_species_field():
    """FAILS IF: the 680 rows with a null `VACANTSITE` are silently guessed at.

    Two of them are in the fixture: one names `Acer rubrum` and one says nothing
    at all. They must not get the same basis, because only the second is our guess.
    """
    records, adapter = records_for("no vacancy statement")
    named = [r for r in records if r.scientific_name]
    silent = [r for r in records if not r.scientific_name]
    check(len(named) == 1 and len(silent) == 1, f"the fixture's two null-flag rows changed: {records}")
    check(named[0].kind == KIND_TREE, "a row naming Acer rubrum is not a tree")
    check(
        named[0].kind_basis == KindBasis.STATED,
        f"a named species with no flag got basis {named[0].kind_basis}",
    )
    check(
        silent[0].kind == KIND_PLANTING_SITE,
        f"a row where the source said nothing became {silent[0].kind}",
    )
    check(
        silent[0].kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES,
        f"the one branch that IS our guess is not spelled as one: {silent[0].kind_basis}",
    )
    check(
        adapter.stats["kind_inferred_from_absent_species"] == 1,
        f"the guess was not counted into the receipt: {adapter.stats}",
    )


# ---------------------------------------------------------------------------
# 5. Sentinels are the adapter's problem
# ---------------------------------------------------------------------------


def test_a_zero_trunk_diameter_is_not_a_measurement():
    """FAILS IF: 72,142 rows ship a zero-inch trunk as a measured dimension.

    `validate()` refuses a non-positive `dbh_in` outright, so a regression here is
    a hard failure rather than a wrong number -- which is the contract working.
    """
    records, _ = records_for("exactly 0")
    check(len(records) == 2, f"expected 2 zero-trunk rows, got {len(records)}")
    for record in records:
        check(
            record.dbh_in is None,
            f"{record.source_ref} shipped dbh_in={record.dbh_in} from a TRUNKDIAM of 0",
        )
        check(record.validate() == [], f"{record.source_ref}: {record.validate()}")


def test_an_impossible_trunk_diameter_is_refused_and_counted():
    """FAILS IF: a 2,304 in trunk -- 58 m across -- ships as a measurement.

    Two rows exceed the 400 in ceiling. They are dropped to None rather than
    clamped, because a clamped 400 is a number nobody measured.
    """
    records, adapter = records_for("past any believable")
    for record in records:
        check(record.dbh_in is None, f"{record.source_ref} shipped dbh_in={record.dbh_in}")
    check(
        adapter.stats["trunk_diameter_over_ceiling"] == 2,
        f"the impossible trunks were not counted: {adapter.stats}",
    )


def test_an_install_date_is_read_and_the_absent_ones_stay_absent():
    """FAILS IF: `ORIGINALINVENTORYDATE` is read as a planting date.

    `INSTALLDATE` is populated on 1,342 of 344,879 rows. Every other row has no
    planting date, and the date somebody walked past the tree is not one. Filling
    343,537 planting dates from the survey date would be the most plausible-looking
    wrong number this source could produce.
    """
    records, _ = records_for("install date")
    for record in records:
        check(
            record.planted_on is not None and record.planted_on.year == 2026,
            f"{record.source_ref} has planted_on {record.planted_on!r}",
        )
    others, _ = records_for("ordinary tree")
    for record in others:
        check(
            record.planted_on is None,
            f"{record.source_ref} acquired a planting date from somewhere: {record.planted_on}",
        )


def test_whitespace_in_the_species_field_is_not_a_second_species():
    """FAILS IF: `Ulmus ` and `Ulmus` become two species.

    146 rows carry the trailing space. Left alone it produces a species row whose
    name differs from a real one by a character nobody can see.

    THIS FIXTURE ROW WAS HARD TO FETCH AND THE REASON MATTERS. Querying the layer
    for `NAMESCIENTIFIC = 'Ulmus '` returns rows holding `Ulmus`, because trailing
    spaces are insignificant to SQL comparison -- so the obvious query produced a
    fixture that made this test pass without ever containing the case. It is
    fetched with `LIKE 'Ulmus_'` instead, and the assertion below is written to
    fail on the value as stored rather than as compared.
    """
    records, _ = records_for("trailing space")
    check(len(records) == 1, f"the trailing-space case has {len(records)} rows, expected 1")
    raw = [r["attributes"]["NAMESCIENTIFIC"] for r in rows_for("trailing space")]
    check(
        raw == ["Ulmus "],
        f"the fixture no longer holds a genuine trailing space: {raw!r}. Re-fetch with "
        f"LIKE 'Ulmus_'; an `=` query silently returns the clean value instead.",
    )
    for record in records:
        check(
            record.scientific_name == "Ulmus",
            f"the trailing space survived into {record.scientific_name!r}",
        )
        check(
            record.species_text == "Ulmus",
            f"species_text kept the invisible character: {record.species_text!r}",
        )


# ---------------------------------------------------------------------------
# 6. Absent means absent
# ---------------------------------------------------------------------------


def test_absent_fields_are_none_and_never_an_empty_string():
    """FAILS IF: a blank layer value reaches a column as ''.

    `''` and NULL are different claims and the contract refuses the first. San
    Jose leaves `CONDITION`, `SPACEWIDTH` and `MAINTENANCENEED` null on real rows.
    """
    records, _ = records_for("")
    for record in records:
        for name in ("address", "site_type", "species_text", "scientific_name", "common_name"):
            value = getattr(record, name)
            check(
                value is None or (isinstance(value, str) and value.strip() == value and value),
                f"{record.source_ref}.{name} is {value!r}; absent must be None",
            )
        for key, value in record.city_record.items():
            check(
                value is None or (isinstance(value, str) and value.strip()),
                f"{record.source_ref}.city_record[{key!r}] is {value!r}; absent must be None",
            )


def test_the_stats_account_for_every_row():
    """FAILS IF: a row is classified by a branch nobody counted.

    The three kind-decision counters are meant to partition the rows. If they stop
    summing to the row count, some branch is reaching a kind without saying so, and
    the build receipt's numbers become decorative.
    """
    records, adapter = records_for("")
    stats = adapter.stats
    counted = (
        stats["kind_from_vacancy_flag"]
        + stats["kind_from_species_vocabulary"]
        + stats["kind_inferred_from_absent_species"]
    )
    check(
        counted == stats["source_rows"] == len(records) == 29,
        f"the kind branches counted {counted} of {stats['source_rows']} rows: {stats}",
    )
    check(stats["dropped_no_coords"] == 0, f"a fixture row lost its position: {stats}")


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
