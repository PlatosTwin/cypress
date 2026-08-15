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
  0. THE AIM. Every fixture describes ONE corpus, and states which in its own
     `inventory:` key. A species fixture is a sourcing record for the species a
     particular inventory publishes, so validating it against a seed built from
     a different inventory compares two things that were never the same list.
     That is a category error, and it is reported as ONE error naming both
     sides -- not as a per-entry failure for every species the other corpus
     happens not to carry.
     This is the whole of the defect that made this script red on main. The
     fixtures describe `sf_datasf`; the shipped seed is built `--source city`,
     i.e. `sf_city`. Aimed at a matching seed the script passed at 0 failures;
     aimed at the shipped one it reported 84 failures, and every one of them was
     the flavor mismatch rather than a defect in the data. Measured 2026-08-14:
     against a matched `sf_datasf` seed, 16,434 checks and no failures; against
     the shipped `sf_city` seed, 84 failures (58 absences, 26 common_name); with
     `nyc_species.yaml` added against that same SF seed, 586 (525 absences, 61
     common_name) and -- the part that matters -- ZERO scientific_name conflicts
     in any cell. A flavor mismatch produces absence and common-name noise and
     never a genuine contradiction, which is why refusing to run is safe and
     tolerating the noise would not be: an absence tolerated on the wrong seed
     is exactly where real fixture drift would hide.
     Pass --allow-flavor-mismatch to run the rules that do not need the seed
     (D5, months, citations, shape) against any seed. The identity rules are
     then SKIPPED and reported as skipped, never quietly passed.
  4. Scientific names, species ids and common names match the seed database's
     `species` table exactly, so the loading migration cannot silently create rows.
     The exception is the handful of entries `Tools/build_seed.py` deliberately
     retires or merges (its `RETIRED_SPECIES_NAMES` / `MERGED_SPECIES_NAMES`,
     imported here rather than restated): the YAML is a sourcing record with
     citations and is not rewritten when the qSpecies map is corrected, so those
     entries are expected to have no seed row of their own. They are held to a
     stricter rule instead -- a retired non-taxon must carry no botanical claim,
     and a merged entry must agree with the species it merged into.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_seed import MERGED_SPECIES_NAMES, RETIRED_SPECIES_NAMES  # noqa: E402

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
        # Entries whose identity rules were skipped by --allow-flavor-mismatch.
        self.skipped_identity = 0
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


def fixture_inventory(doc: dict, path: Path) -> str:
    """Which inventory's corpus this fixture describes (rule 0).

    Declared in the fixture, not guessed here and not passed on the command
    line: the corpus a sourcing record describes is a property of the record,
    and a flag would let one run aim two fixtures that describe different
    cities at one seed without either of them ever saying so.
    """
    inventory = doc.get("inventory")
    if not inventory:
        die(
            f"{path.name}: no `inventory:` key. A species fixture must state which "
            f"inventory's corpus it describes -- it is the only thing that makes "
            f"'this species is missing' distinguishable from 'this species was "
            f"never in that city'. Add e.g. `inventory: sf_datasf` at the top level."
        )
    return inventory


def die(message: str) -> None:
    # Flush first: without it the stderr line overtakes the buffered stdout
    # above it and the reader sees the verdict before the context for it.
    sys.stdout.flush()
    print(f"FATAL: {message}", file=sys.stderr)
    sys.exit(2)


def seed_species(path: Path) -> tuple[dict[str, dict], str]:
    """The seed's species rows, and which inventory built the file (rule 0).

    `trees_source` is the string `build_seed` writes and `trees.inventory_source`
    stores -- `sf_city`, `sf_datasf`, and so on. It is what a fixture's own
    `inventory:` key is compared against.
    """
    uri = f"file:{path}?mode=ro"
    with sqlite3.connect(uri, uri=True) as con:
        con.row_factory = sqlite3.Row
        # `uuid` is the stable external identity; the integer `id` is an internal
        # primary key and must not be referenced from checked-in content.
        rows = con.execute(
            "SELECT uuid, scientific_name, common_name, leaf_retention FROM species "
            "WHERE deleted_at IS NULL"
        ).fetchall()
        source = con.execute(
            "SELECT value FROM seed_meta WHERE key = 'trees_source'"
        ).fetchone()
    return {row["uuid"]: dict(row) for row in rows}, (source[0] if source else "")


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


def check_entry(
    entry: dict,
    seed: dict[str, dict],
    report: Report,
    *,
    curated: bool,
    check_identity: bool = True,
) -> None:
    name = entry.get("scientific_name", "<unnamed>")
    species_uuid = entry.get("species_uuid")

    # ---- Rule 0: with --allow-flavor-mismatch the seed is a different corpus,
    # so every rule that reads it is skipped outright. Skipped is reported as
    # skipped; a rule that cannot be evaluated must never report as satisfied.
    if not check_identity:
        report.skipped_identity += 1
        check_content(entry, report, curated=curated)
        return

    # ---- Rule 4, first exception: strings that name no taxon. Tools/build_seed.py
    # maps them to no species, so there is no seed row to match against. What
    # matters instead is that nobody has written botany onto a growth habit.
    if name in RETIRED_SPECIES_NAMES:
        report.check(
            species_uuid not in seed,
            f"{name}: retired as a non-taxon by build_seed, but the seed still carries "
            f"a species row for it",
        )
        report.check(
            entry.get("family") is None and entry.get("leaf_retention") is None,
            f"{name}: names no taxon, so it must carry no family and no leaf_retention",
        )
        return

    # ---- Rule 4, second exception: a misspelling merged onto the species it
    # misspells. The entry's own uuid is retired; what it says must agree with
    # the row it merged into, or the merge changed a botanical fact.
    merged_into = MERGED_SPECIES_NAMES.get(name)
    if merged_into is not None:
        target = next(
            (r for r in seed.values() if r["scientific_name"] == merged_into), None
        )
        if report.check(
            target is not None,
            f"{name}: merged into {merged_into!r}, which is not in the seed",
        ):
            report.check(
                target["leaf_retention"] == entry.get("leaf_retention"),
                f"{name}: merged into {merged_into!r} but their leaf_retention disagrees "
                f"({entry.get('leaf_retention')!r} vs {target['leaf_retention']!r} in the seed)",
            )
        return

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

    check_content(entry, report, curated=curated)


def check_content(entry: dict, report: Report, *, curated: bool) -> None:
    """Rules 1, 2, 3 and 5 -- everything that reads the fixture and not the seed.

    Split out so that --allow-flavor-mismatch can skip the identity rules
    without also skipping the anti-fabrication gate, which is the reason this
    script exists and does not depend on any seed.
    """
    name = entry.get("scientific_name", "<unnamed>")
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
    # A fixture describing a city this seed does not contain. `nyc_species.yaml`
    # names 503 species an SF-only seed has never heard of, so it is passed
    # explicitly and checked against a seed that HAS them, rather than being
    # bolted onto the two California files where every entry would read as drift.
    # Same rules, same gate: every non-null botanical value needs a citation.
    parser.add_argument("--extra", action="append", default=[], type=Path,
                        help="an additional species fixture, held to the same rules")
    parser.add_argument(
        "--allow-flavor-mismatch",
        action="store_true",
        help="run the rules that do not read the seed (D5, months, citations, "
             "shape) even when a fixture describes a different inventory than the "
             "seed was built from. The identity rules are SKIPPED, not relaxed, "
             "and the count of skipped entries is reported.",
    )
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()

    report = Report()
    seed, seed_inventory = seed_species(args.seed)
    print(f"seed database: {len(seed)} species rows in {args.seed}")
    print(f"seed inventory: {seed_inventory!r}")

    # ---- Rule 0: the aim. Each fixture states the corpus it describes, and a
    # fixture aimed at another corpus is one error, not one per entry.
    fixtures = [
        ("curated.yaml", args.curated, True),
        ("leaf_retention.yaml", args.leaf_retention, False),
    ] + [(p.name, p, False) for p in args.extra]

    loaded, mismatched = [], []
    for label, path, is_curated in fixtures:
        doc = load_yaml(path)
        declared = fixture_inventory(doc, path)
        entries = doc["species"]
        matches = declared == seed_inventory
        print(f"{label}: {len(entries)} entries, describes {declared!r}"
              + ("" if matches else "  <-- NOT this seed's inventory"))
        if not matches:
            mismatched.append((label, declared))
        loaded.append((label, entries, is_curated, matches))

    if mismatched and not args.allow_flavor_mismatch:
        detail = "; ".join(f"{label} describes {declared!r}" for label, declared in mismatched)
        print()
        print(f"FATAL: this seed was built from {seed_inventory!r}, but {detail}.")
        print("  These are different corpora, so 'the seed has no row for this species'")
        print("  means 'that city never listed it', not 'the fixtures have drifted'.")
        print("  Validating across the mismatch reports hundreds of failures and hides")
        print("  the real ones. Aim this at a matching seed:")
        # Deduplicated on the inventory, not on the fixture: two fixtures
        # describing one corpus need one command, printed once.
        for declared in dict.fromkeys(d for _, d in mismatched):
            # `--source` names one of SAN FRANCISCO'S two inventories; only that
            # mapping is known here, and inventing a flag for another city's
            # inventory would be a confident wrong instruction.
            if declared in ("sf_city", "sf_datasf"):
                print(f"    python3 Tools/build_seed.py --source "
                      f"{declared.split('_', 1)[1]}   # builds an {declared!r} seed")
            else:
                print(f"    (build a seed whose seed_meta.trees_source is {declared!r})")
        print("  ...or pass --allow-flavor-mismatch to run only the rules that do not")
        print("  read the seed. Those cannot be faked; the identity rules can.")
        return 2

    for label, entries, is_curated, matches in loaded:
        for entry in entries:
            check_entry(entry, seed, report, curated=is_curated,
                        check_identity=matches)

    curated = next(e for label, e, _, _ in loaded if label == "curated.yaml")
    lr = next(e for label, e, _, _ in loaded if label == "leaf_retention.yaml")

    # ---- Cross-file consistency and uniqueness.
    for label, entries in [(lbl, e) for lbl, e, _, _ in loaded]:
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
    # `sf_tree_count` is San Francisco's own column and a fixture from another
    # city carries none, so this coverage note has no denominator to work with.
    # Guarded rather than assumed: an unguarded divide ended an otherwise
    # entirely passing run in a ZeroDivisionError traceback, which reads as a
    # broken tool rather than as "this note does not apply here".
    if total_rows:
        report.note(
            f"leaf_retention set for {len(lr) - len(nulls)}/{len(lr)} species, "
            f"{covered:,}/{total_rows:,} mapped rows "
            f"({covered / total_rows * 100:.2f}% of mapped rows, "
            f"{covered / datasf_rows * 100:.2f}% of all {datasf_rows:,} DataSF rows)"
        )
    else:
        report.note(
            f"leaf_retention set for {len(lr) - len(nulls)}/{len(lr)} species; "
            f"no sf_tree_count in this fixture, so no row-weighted coverage"
        )
    report.note(
        f"family set for {sum(1 for e in lr if e.get('family'))}/{len(lr)} species, "
        f"{with_family:,} mapped rows"
    )
    # A null leaf_retention is a value the app can represent, not a hole to be
    # filled: unknown renders no phenology chip and no autumn colour (ERRATA E9).
    report.note(f"{len(nulls)} entries carry a null leaf_retention and render as 'not known yet'")
    retired = [e for e in lr if e.get("scientific_name") in RETIRED_SPECIES_NAMES]
    report.note(
        f"{len(retired)} of those entries name no taxon and were retired from the seed "
        f"entirely ({sum(e.get('sf_tree_count') or 0 for e in retired):,} planting sites, "
        f"now carrying no species at all)"
    )
    evergreens = [e for e in lr if e.get("leaf_retention") == "evergreen"]
    report.note(f"{len(evergreens)} evergreen species; all checked against D5")
    if report.skipped_identity:
        report.note(
            f"IDENTITY NOT CHECKED for {report.skipped_identity} entries "
            f"(--allow-flavor-mismatch). Nothing here says their species_uuid, "
            f"scientific_name or common_name agrees with any seed."
        )

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
