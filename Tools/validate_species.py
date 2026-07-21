#!/usr/bin/env python3
"""Validate the curated species YAML against the rules that make it shippable.

Usage:
    python3 Tools/validate_species.py
    python3 Tools/validate_species.py --curated Fixtures/species/curated.yaml \
        --leaf-retention Fixtures/species/leaf_retention.yaml \
        --seed Fixtures/seed/cypress-seed.sqlite

Checks, in the order BUILD-PLAN section 8 and DECISIONS D5 care about them:

  1. D5 / DECISIONS section 3.14: no evergreen carries a non-empty `fall_color_months`.
     This is the one that fails the build loudly, because Species.init in
     Cypress/Core/Models/Species.swift throws on it and the database has a CHECK.
  2. Every month in every seasonal array and every care_note month_range is 1..12,
     and every seasonal array is a sorted, duplicate-free list of ints.
  3. Every non-null botanical field carries at least one citation with a real URL.
     Botanical fields are `family`, `leaf_retention`, each non-empty seasonal array,
     each id_tip, and each care_note. This is the anti-fabrication gate from
     BUILD-PLAN section 15: "Do not invent botanical content".
  4. Scientific names, species ids and common names match the seed database's
     `species` table exactly, so the loading migration cannot silently create rows.
  5. Shape rules: leaf_retention is one of the three enum values, curated entries
     carry 2 to 4 id_tips, ids are unique, id_tip icons come from the documented
     vocabulary.

The script reads only. It never writes to the .sqlite or to the YAML.

Exit code 0 when everything passes, 1 when anything fails.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit(
        "PyYAML is required: python3 -m pip install -r Tools/requirements.txt\n"
        "(or: python3 -m pip install pyyaml)"
    )

REPO = Path(__file__).resolve().parent.parent
LEAF_RETENTION_VALUES = {"evergreen", "deciduous", "semi_deciduous"}
SEASONAL_KEYS = ("bloom_months", "fall_color_months", "fruit_months", "new_growth_months")
# Authored for this repo; see the header of Fixtures/species/curated.yaml.
ICONS = {"leaf", "bark", "flower", "fruit", "cone", "form", "trunk"}
URL_RE = re.compile(r"^https?://\S+$")


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.notes: list[str] = []
        self.checks = 0

    def check(self, ok: bool, message: str) -> bool:
        self.checks += 1
        if not ok:
            self.failures.append(message)
        return ok

    def note(self, message: str) -> None:
        self.notes.append(message)


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def seed_species(path: Path) -> dict[str, dict]:
    uri = f"file:{path}?mode=ro"
    with sqlite3.connect(uri, uri=True) as con:
        con.row_factory = sqlite3.Row
        # `uuid` is the stable external identity; the integer `id` is an internal
        # primary key and must not be referenced from checked-in content.
        rows = con.execute(
            "SELECT uuid, scientific_name, common_name FROM species WHERE deleted_at IS NULL"
        ).fetchall()
    return {row["uuid"]: dict(row) for row in rows}


def citations_ok(citations, where: str, report: Report) -> None:
    """Rule 3. A cited fact needs a source name and a fetchable URL."""
    report.check(
        isinstance(citations, list) and len(citations) >= 1,
        f"{where}: value is present but carries no citation",
    )
    if not isinstance(citations, list):
        return
    for index, citation in enumerate(citations):
        label = f"{where}: citation[{index}]"
        if not isinstance(citation, dict):
            report.check(False, f"{label} is not a mapping")
            continue
        report.check(bool(citation.get("source")), f"{label} has no `source`")
        url = citation.get("url")
        report.check(
            isinstance(url, str) and bool(URL_RE.match(url)),
            f"{label} has no retrievable url (got {url!r})",
        )
        report.check("licence" in citation, f"{label} does not state a licence")


def check_months(values, where: str, report: Report) -> None:
    """Rule 2."""
    if not report.check(isinstance(values, list), f"{where} is not a list"):
        return
    for month in values:
        report.check(
            isinstance(month, int) and 1 <= month <= 12,
            f"{where} contains {month!r}, which is not a month in 1..12",
        )
    report.check(len(set(values)) == len(values), f"{where} repeats a month: {values}")
    report.check(list(values) == sorted(values), f"{where} is not sorted: {values}")


def check_entry(entry: dict, seed: dict[str, dict], report: Report, *, curated: bool) -> None:
    name = entry.get("scientific_name", "<unnamed>")
    species_uuid = entry.get("species_uuid")

    # ---- Rule 4: the seed database is the authority on identity.
    row = seed.get(species_uuid)
    if report.check(
        row is not None,
        f"{name}: species_uuid {species_uuid} is not in the seed database species table",
    ):
        report.check(
            row["scientific_name"] == name,
            f"{name}: scientific_name does not match the seed row "
            f"({row['scientific_name']!r} in the database)",
        )
        report.check(
            (row["common_name"] or None) == (entry.get("common_name") or None),
            f"{name}: common_name does not match the seed row "
            f"({row['common_name']!r} in the database)",
        )

    # ---- Rule 5 plus Rule 3 for the two scalar botanical fields.
    citations = entry.get("citations") or {}
    leaf_retention = entry.get("leaf_retention")
    if leaf_retention is not None:
        report.check(
            leaf_retention in LEAF_RETENTION_VALUES,
            f"{name}: leaf_retention {leaf_retention!r} is not one of "
            f"{sorted(LEAF_RETENTION_VALUES)}",
        )
        citations_ok(citations.get("leaf_retention"), f"{name}.leaf_retention", report)
    if entry.get("family") is not None:
        citations_ok(citations.get("family"), f"{name}.family", report)

    seasonal = entry.get("seasonal") or {}
    for key in SEASONAL_KEYS:
        values = seasonal.get(key, [])
        check_months(values, f"{name}.seasonal.{key}", report)
        if values:
            citations_ok(citations.get(f"seasonal.{key}"), f"{name}.seasonal.{key}", report)

    # ---- Rule 1: D5. The reason this file exists.
    if leaf_retention == "evergreen":
        fall = seasonal.get("fall_color_months") or []
        report.check(
            not fall,
            f"D5 VIOLATION: {name} is evergreen but carries fall_color_months {fall}. "
            "Species.init throws on this and the database CHECK rejects it.",
        )

    id_tips = entry.get("id_tips") or []
    if curated:
        report.check(
            2 <= len(id_tips) <= 4,
            f"{name}: curated entries need 2 to 4 id_tips, found {len(id_tips)}",
        )
        report.check(entry.get("curated") is True, f"{name}: curated is not true")
    for index, tip in enumerate(id_tips):
        where = f"{name}.id_tips[{index}]"
        report.check(bool(tip.get("text")), f"{where} has no text")
        report.check(
            tip.get("icon") in ICONS,
            f"{where} icon {tip.get('icon')!r} is not in the documented vocabulary "
            f"{sorted(ICONS)}",
        )
        text = tip.get("text") or ""
        report.check(
            " — " not in text and " – " not in text,
            f"{where}: em dash must not carry spaces around it (house style)",
        )
        citations_ok(tip.get("citations"), where, report)

    for index, note in enumerate(entry.get("care_notes") or []):
        where = f"{name}.care_notes[{index}]"
        report.check(bool(note.get("text")), f"{where} has no text")
        month_range = note.get("month_range") or {}
        for bound in ("start", "end"):
            value = month_range.get(bound)
            report.check(
                isinstance(value, int) and 1 <= value <= 12,
                f"{where}.month_range.{bound} is {value!r}, not a month in 1..12",
            )
        citations_ok(note.get("citations"), where, report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--curated", default=REPO / "Fixtures/species/curated.yaml", type=Path)
    parser.add_argument(
        "--leaf-retention", default=REPO / "Fixtures/species/leaf_retention.yaml", type=Path
    )
    parser.add_argument("--seed", default=REPO / "Fixtures/seed/cypress-seed.sqlite", type=Path)
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()

    report = Report()
    seed = seed_species(args.seed)
    print(f"seed database: {len(seed)} species rows in {args.seed}")

    curated_doc = load_yaml(args.curated)
    curated = curated_doc["species"]
    print(f"curated.yaml: {len(curated)} entries")
    for entry in curated:
        check_entry(entry, seed, report, curated=True)

    lr_doc = load_yaml(args.leaf_retention)
    lr = lr_doc["species"]
    print(f"leaf_retention.yaml: {len(lr)} entries")
    for entry in lr:
        check_entry(entry, seed, report, curated=False)

    # ---- Cross-file consistency and uniqueness.
    for label, entries in (("curated.yaml", curated), ("leaf_retention.yaml", lr)):
        ids = [e.get("species_uuid") for e in entries]
        report.check(len(set(ids)) == len(ids), f"{label}: duplicate species_uuid")

    lr_by_id = {e["species_uuid"]: e for e in lr}
    for entry in curated:
        other = lr_by_id.get(entry["species_uuid"])
        if other is None:
            report.check(False, f"{entry['scientific_name']} is curated but absent from leaf_retention.yaml")
            continue
        report.check(
            other.get("leaf_retention") == entry.get("leaf_retention"),
            f"{entry['scientific_name']}: leaf_retention disagrees between the two files "
            f"({entry.get('leaf_retention')!r} vs {other.get('leaf_retention')!r})",
        )
        report.check(
            other.get("family") == entry.get("family"),
            f"{entry['scientific_name']}: family disagrees between the two files",
        )

    # ---- Coverage, reported rather than asserted; the threshold is a product call.
    total_rows = sum(e.get("sf_tree_count") or 0 for e in lr)
    covered = sum(e.get("sf_tree_count") or 0 for e in lr if e.get("leaf_retention"))
    with_family = sum(e.get("sf_tree_count") or 0 for e in lr if e.get("family"))
    nulls = [e for e in lr if not e.get("leaf_retention")]
    # The DataSF snapshot in Fixtures/raw/street_tree_list.csv. 13,773 of its rows are
    # vacant sites or placeholder strings that map to no species, so 93.06% is the ceiling
    # for any species-keyed table.
    datasf_rows = 198_435
    report.note(
        f"leaf_retention set for {len(lr) - len(nulls)}/{len(lr)} species, "
        f"{covered:,}/{total_rows:,} mapped rows ({covered / total_rows * 100:.2f}% of mapped rows, "
        f"{covered / datasf_rows * 100:.2f}% of all {datasf_rows:,} DataSF rows)"
    )
    report.note(
        f"family set for {sum(1 for e in lr if e.get('family'))}/{len(lr)} species, "
        f"{with_family:,} mapped rows"
    )
    report.note(f"{len(nulls)} species carry a null leaf_retention and render as 'not known yet'")
    evergreens = [e for e in lr if e.get("leaf_retention") == "evergreen"]
    report.note(f"{len(evergreens)} evergreen species; all checked against D5")

    if args.json:
        print(json.dumps({"checks": report.checks, "failures": report.failures}, indent=1))
    print()
    for note in report.notes:
        print(f"  note: {note}")
    print()
    print(f"{report.checks} checks run")
    if report.failures:
        print(f"{len(report.failures)} FAILURES:")
        for failure in report.failures:
            print(f"  - {failure}")
        return 1
    print("PASS: no failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
