#!/usr/bin/env python3
"""Tests for the species validator's identity rule (rule 4).

    python3 Tools/test_validate_species.py

The rule has three parts and they are not the same strength, which is the whole
reason these exist. A uuid the seed carries must carry the same scientific name,
always. Whether every fixture entry must HAVE a seed row depends on which
inventory built the seed. And common_name is not the fixtures' to state at all.

Before this was true the validator was RED on main -- 84 failures against a
shipped seed with no local changes, every one of them the validator asserting
something the pipeline never promised. A validator that is permanently red is a
validator nobody reads, so each of these tests is calibrated in both directions:
the tolerated case must pass AND the real defect must still fail.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from validate_species import (  # noqa: E402
    FIXTURE_SOURCE_INVENTORY,
    Report,
    check_entry,
    seed_species,
)

FAILURES: list[str] = []
PASSED = 0

# A uuid that is in no seed any of these tests builds.
ABSENT_UUID = "00000000-0000-5000-8000-000000000001"
PRESENT_UUID = "11111111-1111-5111-8111-111111111111"


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def write_seed(directory: str, rows, trees_source: str) -> str:
    """A seed carrying only what rule 4 reads: species rows and the provenance."""
    path = os.path.join(directory, f"seed-{trees_source}-{len(rows)}.sqlite")
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE species (uuid TEXT PRIMARY KEY, scientific_name TEXT, "
        "common_name TEXT, leaf_retention TEXT, deleted_at TEXT);"
        "CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT);"
    )
    conn.executemany(
        "INSERT INTO species (uuid, scientific_name, common_name, leaf_retention, "
        "deleted_at) VALUES (?, ?, ?, ?, NULL)",
        rows,
    )
    conn.execute("INSERT INTO seed_meta VALUES ('trees_source', ?)", (trees_source,))
    conn.commit()
    conn.close()
    return path


def entry(**overrides) -> dict:
    """A minimal leaf_retention.yaml entry, for tests that vary one thing."""
    base = {
        "scientific_name": "Pinus radiata",
        "species_uuid": PRESENT_UUID,
        "common_name": "Monterey Pine",
        "leaf_retention": None,
        "family": None,
    }
    base.update(overrides)
    return base


def run(entries, seed_path) -> Report:
    seed, trees_source = seed_species(seed_path)
    report = Report()
    for e in entries:
        check_entry(
            e,
            seed,
            report,
            curated=False,
            strict_presence=trees_source == FIXTURE_SOURCE_INVENTORY,
        )
    return report


# ---------------------------------------------------------------------------
# Presence: strict against the inventory the fixtures were sourced from, and
# only against that one
# ---------------------------------------------------------------------------


def test_an_absent_entry_is_reported_not_failed_on_the_city_layer():
    """FAILS IF: the validator hardcodes DataSF strictness again.

    The shipped seed is built from `sf_city`, which inventories ~62,000 fewer
    records than the DataSF export the fixtures were sourced against and simply
    does not contain some of those species. `build_seed.load_species_content`
    calls these absences in the corpus and counts them; this said 58 FAILURES.
    """
    with tempfile.TemporaryDirectory() as d:
        path = write_seed(d, [(PRESENT_UUID, "Pinus radiata", "Monterey Pine", None)], "sf_city")
        report = run([entry(species_uuid=ABSENT_UUID, scientific_name="Acer ginnela")], path)
        check(not report.failures, f"a city-layer absence failed the build: {report.failures}")
        check(
            report.absent == ["Acer ginnela"],
            f"the absence was swallowed rather than reported: {report.absent}",
        )


def test_an_absent_entry_still_fails_against_the_datasf_export():
    """FAILS IF: the fix over-corrects and nothing checks presence anywhere.

    The calibration for the test above. Against `sf_datasf` -- the inventory the
    fixtures WERE sourced against -- an entry with no seed row means the fixtures
    and the qSpecies parser have drifted apart, and build_seed dies on it. So
    must this.
    """
    with tempfile.TemporaryDirectory() as d:
        path = write_seed(
            d, [(PRESENT_UUID, "Pinus radiata", "Monterey Pine", None)], FIXTURE_SOURCE_INVENTORY
        )
        report = run([entry(species_uuid=ABSENT_UUID, scientific_name="Acer ginnela")], path)
        check(
            any("is not in the seed database" in f for f in report.failures),
            f"real fixture drift went unreported against the DataSF export: {report.failures}",
        )
        check(not report.absent, "drift was filed as a tolerated absence")


# ---------------------------------------------------------------------------
# Identity: a uuid the seed carries must carry the same name, on any source
# ---------------------------------------------------------------------------


def test_a_uuid_naming_a_different_species_fails_on_every_source():
    """FAILS IF: the source-aware presence rule loosens the name rule with it.

    These are different claims. "This inventory does not carry that species" is
    a fact about a corpus. "This uuid is Quercus agrifolia in the seed and Pinus
    radiata in the fixtures" is a contradiction, and it would put one species'
    sourced botany on another species' profile. build_seed dies on it whatever
    the source, and the tolerant path must not become a way around it.
    """
    for source in ("sf_city", FIXTURE_SOURCE_INVENTORY):
        with tempfile.TemporaryDirectory() as d:
            path = write_seed(
                d, [(PRESENT_UUID, "Quercus agrifolia", "Coast Live Oak", None)], source
            )
            report = run([entry(scientific_name="Pinus radiata")], path)
            check(
                any("scientific_name does not match" in f for f in report.failures),
                f"a uuid naming a different species passed under {source}: {report.failures}",
            )


# ---------------------------------------------------------------------------
# common_name: reported, because the fixtures do not supply it
# ---------------------------------------------------------------------------


def test_a_divergent_common_name_is_reported_not_failed():
    """FAILS IF: common_name equality is asserted again.

    The seed's common_name comes from whichever inventory built it, never from
    this file. DataSF publishes "Sycamore: London Plane" and the city layer
    "Sycamore, London Plane" -- the same tree, two publishers' punctuation. This
    was 26 of the 84 failures and protected nothing.
    """
    with tempfile.TemporaryDirectory() as d:
        path = write_seed(
            d,
            [(PRESENT_UUID, "Platanus x hispanica", "Sycamore, London Plane", None)],
            "sf_city",
        )
        report = run(
            [entry(
                scientific_name="Platanus x hispanica",
                common_name="Sycamore: London Plane",
            )],
            path,
        )
        check(not report.failures, f"a common_name divergence failed the build: {report.failures}")
        check(
            len(report.common_name_divergence) == 1,
            f"the divergence was not reported: {report.common_name_divergence}",
        )


def test_an_agreeing_common_name_is_not_reported():
    """FAILS IF: the divergence report fires on everything and means nothing.

    The calibration for the test above. A note that appears for every entry is
    noise, and noise is how the 58-absence signal would get lost.
    """
    with tempfile.TemporaryDirectory() as d:
        path = write_seed(
            d, [(PRESENT_UUID, "Pinus radiata", "Monterey Pine", None)], "sf_city"
        )
        report = run([entry()], path)
        check(
            not report.common_name_divergence,
            f"an agreeing common_name was reported as divergent: "
            f"{report.common_name_divergence}",
        )


def main() -> int:
    for test in [
        test_an_absent_entry_is_reported_not_failed_on_the_city_layer,
        test_an_absent_entry_still_fails_against_the_datasf_export,
        test_a_uuid_naming_a_different_species_fails_on_every_source,
        test_a_divergent_common_name_is_reported_not_failed,
        test_an_agreeing_common_name_is_not_reported,
    ]:
        test()

    print(f"{PASSED} checks passed, {len(FAILURES)} failed")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
