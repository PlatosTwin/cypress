#!/usr/bin/env python3
"""
build_nyc_species_map.py -- Fixtures/nyc_species_map.csv from the live extract.

One row per distinct `GenusSpecies` string NYC publishes, in the same three-column
shape as `Fixtures/sj_species_map.csv`:

    qSpecies_string,species_id,confidence

`species_id` is the seed's own `species.uuid` when the parsed scientific name
matches a species already in `Fixtures/seed/cypress-seed.sqlite`, and EMPTY when
it does not. An empty id is not a defect and it is not a TODO: it is this file
saying the corpus has no row for that taxon yet, which the build resolves by
minting one. What it must never be is a guess.

THE ANTI-FABRICATION RULE IS THE POINT OF THIS SCRIPT (DECISIONS constraint 15).
Matching is EXACT on a case-folded, whitespace-collapsed scientific name and
nothing else. No fuzzy matching, no edit distance, no "Acer rubrum Red Sunset
is probably Acer rubrum", no synonymy. A name this script cannot match exactly
lands in the unmapped report for a human to read, because every one of those
judgments is a botanical claim and this script has no source for one.
`QSPECIES_NAME_CORRECTIONS` in inventory_adapters.py is the shape a sourced
correction takes, and it has exactly one entry for a reason.

Usage:
    python3 Tools/build_nyc_species_map.py --extract PATH/tree_points.csv
        [--seed Fixtures/seed/cypress-seed.sqlite]
        [--out Fixtures/nyc_species_map.csv]
        [--unmapped-report PATH]
        [--structures Full]
"""

from __future__ import annotations

import argparse
import collections
import csv
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inventory_adapters import NYCTreePointAdapter, normalise_species_key  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_corpus(seed_path: str) -> dict:
    """{case-folded scientific name -> (uuid, scientific_name)} from the seed."""
    con = sqlite3.connect(seed_path)
    corpus = {}
    for uuid_value, scientific in con.execute(
        "SELECT uuid, scientific_name FROM species WHERE deleted_at IS NULL"
    ):
        corpus[normalise_species_key(scientific)] = (uuid_value, scientific)
    con.close()
    return corpus


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extract", required=True, help="tree_points.csv from fetch_nyc_trees.py")
    ap.add_argument("--seed", default=os.path.join(REPO, "Fixtures", "seed", "cypress-seed.sqlite"))
    ap.add_argument("--out", default=os.path.join(REPO, "Fixtures", "nyc_species_map.csv"))
    ap.add_argument("--unmapped-report", default=None)
    ap.add_argument("--structures", default="Full",
                    help="comma-separated TPStructure values to read, or 'all'")
    args = ap.parse_args(argv)

    corpus = load_corpus(args.seed)
    print(f"seed corpus: {len(corpus):,} species")

    structures = None
    if args.structures.lower() != "all":
        structures = {s.strip().lower() for s in args.structures.split(",") if s.strip()}

    counts = collections.Counter()
    with open(args.extract, "r", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            if structures is not None:
                if (row.get("tpstructure") or "").strip().lower() not in structures:
                    continue
            counts[(row.get("genusspecies") or "").strip()] += 1

    rows = []
    unmapped = []
    stats = collections.Counter()
    for packed, n in counts.most_common():
        if not packed:
            stats["blank_species_string"] += n
            continue
        scientific, _common = NYCTreePointAdapter.split_genus_species(packed)
        confidence = NYCTreePointAdapter.confidence_for(scientific)
        if scientific and scientific.strip().lower() in {"unknown"}:
            # A tree nobody identified. Not a taxon, and deliberately mapped to
            # nothing with confidence 0 -- the same shape `Vacant site` takes in
            # sj_species_map.csv. R18: a tree of unknown species is still a tree.
            rows.append((packed, "", 0.0))
            stats["non_taxon_rows"] += n
            stats["non_taxon_values"] += 1
            continue
        key = normalise_species_key(scientific or "")
        hit = corpus.get(key)
        if hit:
            rows.append((packed, hit[0], confidence or 0.0))
            stats["mapped_rows"] += n
            stats["mapped_values"] += 1
        else:
            rows.append((packed, "", confidence or 0.0))
            stats["unmapped_rows"] += n
            stats["unmapped_values"] += 1
            unmapped.append((packed, scientific, n, confidence))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["qSpecies_string", "species_id", "confidence"])
        for packed, species_id, confidence in rows:
            writer.writerow([packed, species_id, f"{confidence:.2f}"])
    print(f"wrote {args.out}: {len(rows):,} distinct species strings")

    print()
    print("  distinct values mapped to an existing seed species:"
          f" {stats['mapped_values']:,} ({stats['mapped_rows']:,} rows)")
    print("  distinct values with NO seed species (new taxa):   "
          f" {stats['unmapped_values']:,} ({stats['unmapped_rows']:,} rows)")
    print("  distinct values that name no taxon at all:        "
          f" {stats['non_taxon_values']:,} ({stats['non_taxon_rows']:,} rows)")
    print(f"  rows with a blank species string:                  {stats['blank_species_string']:,}")

    if args.unmapped_report:
        with open(args.unmapped_report, "w", encoding="utf-8") as fh:
            fh.write(
                "# NYC GenusSpecies values with no exact match in the seed corpus\n"
                "#\n"
                "# NOT a defect list and NOT a TODO list. Each of these is a taxon the\n"
                "# corpus does not carry yet; the build mints a species row for it. They\n"
                "# are listed so a human can read them before that happens, because an\n"
                "# exact-match miss is sometimes a real new species and sometimes a\n"
                "# spelling the corpus already holds under another name -- and telling\n"
                "# those apart is a botanical judgment no script here is allowed to make\n"
                "# (DECISIONS constraint 15).\n"
                "#\n"
                "# columns: rows<TAB>confidence<TAB>parsed scientific name<TAB>packed string\n\n"
            )
            for packed, scientific, n, confidence in sorted(unmapped, key=lambda r: -r[2]):
                fh.write(f"{n}\t{confidence}\t{scientific}\t{packed}\n")
        print(f"wrote {args.unmapped_report}: {len(unmapped):,} values for review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
