#!/usr/bin/env python3
"""Tests for the species validator's aim (rule 0) and the identity rules it gates.

    python3 Tools/test_validate_species.py

The validator was RED on main -- 84 failures against the shipped seed, no local
changes. The measured cause is that it was MIS-AIMED, not broken: the fixtures
describe the `sf_datasf` corpus and the shipped seed is built from `sf_city`.
Aimed at a matching seed the same code passes at 0 failures. So the fix is not
to relax any rule; it is to make the aim explicit and a mismatch loud.

That distinction is what these tests hold in place, and it cuts both ways:

  * a mismatch must be ONE error, not one per entry, and must not run the
    identity rules at all -- and
  * a MATCHED run must still catch every kind of drift at full strength.

The second half is the one that matters. Tolerating absences on a mismatched
seed instead of refusing to run would have left genuine fixture drift invisible
on the shipped-seed path, which is this repo's dominant defect class: a guard
that stays green while the defect is present.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import os
import sqlite3
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from validate_species import Report, check_entry  # noqa: E402

FAILURES: list[str] = []
PASSED = 0

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "validate_species.py")

ABSENT_UUID = "00000000-0000-5000-8000-000000000001"
PRESENT_UUID = "11111111-1111-5111-8111-111111111111"


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


def write_seed(path: str, rows, trees_source: str, contributions=None) -> str:
    """A seed carrying only what the validator reads.

    `contributions` is {inventory: row count} -- the rows rule 0 derives the
    seed's own inventory from. It defaults to a single inventory matching
    `trees_source`, which is the ordinary single-city case; pass it explicitly to
    build the shipped seed's shape, where a second inventory rides along as a
    partial overlay.
    """
    if contributions is None:
        contributions = {trees_source: 1}
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE species (uuid TEXT PRIMARY KEY, scientific_name TEXT, "
        "common_name TEXT, leaf_retention TEXT, deleted_at TEXT);"
        "CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT);"
        "CREATE TABLE inventories (id TEXT PRIMARY KEY);"
        "CREATE TABLE trees (id INTEGER PRIMARY KEY, inventory_source TEXT);"
    )
    conn.executemany(
        "INSERT INTO species (uuid, scientific_name, common_name, leaf_retention, "
        "deleted_at) VALUES (?, ?, ?, ?, NULL)",
        rows,
    )
    conn.execute("INSERT INTO seed_meta VALUES ('trees_source', ?)", (trees_source,))
    for inventory, count in contributions.items():
        conn.execute("INSERT INTO inventories VALUES (?)", (inventory,))
        conn.executemany(
            "INSERT INTO trees (inventory_source) VALUES (?)",
            [(inventory,)] * count,
        )
    conn.commit()
    conn.close()
    return path


def write_fixture(path: str, inventory, entries) -> str:
    """A species fixture. `inventory=None` omits the declaration entirely."""
    lines = ["schema_version: 1"]
    if inventory is not None:
        lines.append(f"inventory: {inventory}")
    if not entries:
        lines.append("species: []")
    else:
        lines.append("species:")
    for e in entries:
        lines.append(f"  - scientific_name: {e['scientific_name']}")
        lines.append(f"    species_uuid: {e['species_uuid']}")
        lines.append(f"    common_name: {e.get('common_name', 'Monterey Pine')}")
        lines.append("    leaf_retention: null")
        lines.append("    family: null")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return path


def entry(**overrides) -> dict:
    base = {
        "scientific_name": "Pinus radiata",
        "species_uuid": PRESENT_UUID,
        "common_name": "Monterey Pine",
    }
    base.update(overrides)
    return base


def run_script(seed, curated, leaf_retention, *extra_args):
    return subprocess.run(
        [sys.executable, SCRIPT, "--seed", seed, "--curated", curated,
         "--leaf-retention", leaf_retention, *extra_args],
        capture_output=True, text=True,
    )


# ---------------------------------------------------------------------------
# Rule 0: the aim
# ---------------------------------------------------------------------------


def test_a_flavor_mismatch_is_one_error_and_not_one_per_entry():
    """FAILS IF: the validator validates across corpora again.

    This is the exact shape of the defect. Two fixtures describing `sf_datasf`
    aimed at an `sf_city` seed produced 84 per-entry failures on main -- and 586
    once the NYC fixture joined them. The count is the tell: a category error
    that reports as hundreds of data errors trains its reader to skim, and the
    real failures are what get skimmed past.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(os.path.join(d, "s.sqlite"), [], "sf_city")
        cur = write_fixture(os.path.join(d, "curated.yaml"), "sf_datasf",
                            [entry(species_uuid=ABSENT_UUID)])
        lr = write_fixture(os.path.join(d, "lr.yaml"), "sf_datasf",
                           [entry(species_uuid=ABSENT_UUID)])
        r = run_script(seed, cur, lr)
        check(r.returncode == 2, f"a mismatched run did not exit 2 (got {r.returncode})")
        check(
            "FATAL" in r.stdout and "sf_city" in r.stdout and "sf_datasf" in r.stdout,
            "the error does not name both corpora",
        )
        check(
            "is not in the seed database species table" not in r.stdout,
            "the mismatched run still emitted per-entry identity failures",
        )


def test_a_matching_flavor_runs_the_identity_rules():
    """FAILS IF: the gate refuses a run it should have allowed.

    The calibration for the test above. Same fixtures, same entries, a seed of
    the flavor they describe -- this must run, and it must be red, because the
    entry really is absent from a corpus that claims to contain it.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(os.path.join(d, "s.sqlite"), [], "sf_datasf")
        cur = write_fixture(os.path.join(d, "curated.yaml"), "sf_datasf",
                            [entry(species_uuid=ABSENT_UUID)])
        lr = write_fixture(os.path.join(d, "lr.yaml"), "sf_datasf",
                           [entry(species_uuid=ABSENT_UUID)])
        r = run_script(seed, cur, lr)
        check(r.returncode == 1, f"a matched run with real drift did not exit 1 ({r.returncode})")
        check(
            "is not in the seed database species table" in r.stdout,
            "real fixture drift went unreported on a matched seed",
        )


def test_a_city_build_seed_has_no_branch_for_can_still_be_validated():
    """FAILS IF: rule 0 goes back to comparing against `seed_meta.trees_source`.

    `build_seed` writes that key as a literal -- "sf_city" or "sf_datasf", one
    per `--source` branch -- so it can never name another city's inventory. An
    equality test against it makes every non-SF fixture unpassable by
    construction, and prints a remediation nobody can carry out. Rule 0 derives
    the seed's inventory from the rows instead, so a corpus from a city this
    script has never heard of validates on its own terms. Here the seed even
    MISREPORTS itself as sf_city, exactly as an NYC build does today.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(
            os.path.join(d, "s.sqlite"),
            [(PRESENT_UUID, "Pinus radiata", "Monterey Pine", None)],
            "sf_city",                                  # the literal, wrong
            contributions={"nyc_tree_points": 9},       # what the rows say
        )
        cur = write_fixture(os.path.join(d, "curated.yaml"), "nyc_tree_points", [])
        lr = write_fixture(os.path.join(d, "lr.yaml"), "nyc_tree_points", [entry()])
        r = run_script(seed, cur, lr)
        check(r.returncode == 0, f"an NYC-flavored corpus was refused ({r.returncode}): {r.stdout[-300:]}")
        check(
            "WARNING: seed_meta.trees_source says 'sf_city'" in r.stdout,
            "the seed misreporting its own provenance was not surfaced",
        )


def test_a_partial_overlay_inventory_does_not_make_a_seed_its_corpus():
    """FAILS IF: rule 0 weakens to membership in the `inventories` table.

    This is the shipped seed's shape and the reason membership is not enough:
    it registers `sf_datasf` and carries 12,260 rows from it, riding on top of
    133,577 from `sf_city`. A membership test therefore ADMITS the sf_datasf
    fixtures against it -- measured, that puts all 84 original failures back.
    Contributing some rows is not the same as being the corpus this file is of.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(
            os.path.join(d, "s.sqlite"), [], "sf_city",
            contributions={"sf_city": 133, "sf_datasf": 12},
        )
        cur = write_fixture(os.path.join(d, "curated.yaml"), "sf_datasf",
                            [entry(species_uuid=ABSENT_UUID)])
        lr = write_fixture(os.path.join(d, "lr.yaml"), "sf_datasf",
                           [entry(species_uuid=ABSENT_UUID)])
        r = run_script(seed, cur, lr)
        check(r.returncode == 2, f"a partial overlay was treated as the corpus ({r.returncode})")
        check(
            "is not in the seed database species table" not in r.stdout,
            "the overlay run emitted per-entry identity failures",
        )


def test_a_fixture_that_declares_no_corpus_is_refused():
    """FAILS IF: an undeclared fixture is silently assumed to match.

    A fixture that does not say what it describes cannot be aimed, and guessing
    on its behalf is how the original defect read as 84 data errors. `--extra`
    exists precisely to carry a fixture from another city, so the declaration is
    what keeps the third file honest.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(os.path.join(d, "s.sqlite"), [], "sf_datasf")
        cur = write_fixture(os.path.join(d, "curated.yaml"), "sf_datasf", [entry()])
        lr = write_fixture(os.path.join(d, "lr.yaml"), None, [entry()])
        r = run_script(seed, cur, lr)
        check(r.returncode == 2, f"an undeclared fixture did not exit 2 ({r.returncode})")
        check("no `inventory:` key" in r.stderr, f"unhelpful message: {r.stderr[:200]}")


def test_the_escape_hatch_skips_identity_and_says_so():
    """FAILS IF: --allow-flavor-mismatch ever reports a rule it did not run.

    It runs the rules that read only the fixture and skips the ones that read
    the seed. A skipped rule that printed as satisfied would be strictly worse
    than the 84 failures it replaced, so the count of skipped entries is stated.
    """
    with tempfile.TemporaryDirectory() as d:
        seed = write_seed(os.path.join(d, "s.sqlite"), [], "sf_city")
        cur = write_fixture(os.path.join(d, "curated.yaml"), "sf_datasf",
                            [entry(species_uuid=ABSENT_UUID)])
        lr = write_fixture(os.path.join(d, "lr.yaml"), "sf_datasf",
                           [entry(species_uuid=ABSENT_UUID)])
        r = run_script(seed, cur, lr, "--allow-flavor-mismatch")
        check(
            "IDENTITY NOT CHECKED for 2 entries" in r.stdout,
            f"the skip was not reported: {r.stdout[-400:]}",
        )
        check(
            "is not in the seed database species table" not in r.stdout,
            "identity was checked despite the flavor mismatch",
        )


# ---------------------------------------------------------------------------
# The identity rules themselves, at full strength on a matched seed
# ---------------------------------------------------------------------------


def test_a_uuid_naming_a_different_species_fails():
    """FAILS IF: the aim gate is mistaken for permission to loosen a rule.

    "This inventory does not carry that species" is a fact about a corpus. "This
    uuid is Quercus agrifolia in the seed and Pinus radiata in the fixtures" is a
    contradiction that would put one species' sourced botany on another's
    profile. build_seed dies on it; nothing about rule 0 may soften it.
    """
    seed = {PRESENT_UUID: {
        "uuid": PRESENT_UUID, "scientific_name": "Quercus agrifolia",
        "common_name": "Coast Live Oak", "leaf_retention": None,
    }}
    report = Report()
    check_entry(entry(), seed, report, curated=False, check_identity=True)
    check(
        any("scientific_name does not match" in f for f in report.failures),
        f"a uuid naming a different species passed: {report.failures}",
    )


def test_skipping_identity_does_not_skip_the_anti_fabrication_gate():
    """FAILS IF: --allow-flavor-mismatch turns into a way to skip D5.

    The citation requirement and D5 read the fixture, never the seed, so they
    are valid whatever the seed is. An evergreen carrying fall_color_months
    still throws in Species.init and is still refused by the database CHECK.
    """
    report = Report()
    check_entry(
        {
            "scientific_name": "Pinus radiata",
            "species_uuid": PRESENT_UUID,
            "leaf_retention": "evergreen",
            "seasonal": {"fall_color_months": [10, 11]},
            "citations": {"leaf_retention": [
                {"source": "x", "url": "https://example.org/a", "licence": "CC-BY"},
            ]},
        },
        {},
        report,
        curated=False,
        check_identity=False,
    )
    check(
        any("D5 VIOLATION" in f for f in report.failures),
        f"D5 was skipped along with identity: {report.failures}",
    )
    check(report.skipped_identity == 1, "the skipped entry was not counted")


def main() -> int:
    for test in [
        test_a_flavor_mismatch_is_one_error_and_not_one_per_entry,
        test_a_matching_flavor_runs_the_identity_rules,
        test_a_city_build_seed_has_no_branch_for_can_still_be_validated,
        test_a_partial_overlay_inventory_does_not_make_a_seed_its_corpus,
        test_a_fixture_that_declares_no_corpus_is_refused,
        test_the_escape_hatch_skips_identity_and_says_so,
        test_a_uuid_naming_a_different_species_fails,
        test_skipping_identity_does_not_skip_the_anti_fabrication_gate,
    ]:
        test()

    print(f"{PASSED} checks passed, {len(FAILURES)} failed")
    for failure in FAILURES:
        print(f"  FAIL: {failure}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
