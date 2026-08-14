#!/usr/bin/env python3
"""
build_nyc_species_map.py -- Fixtures/nyc_species_map.csv from the live extract.

One row per distinct `GenusSpecies` string NYC publishes, in the same three-column
shape as `Fixtures/sj_species_map.csv`:

    qSpecies_string,species_id,confidence

`species_id` is the seed's own `species.uuid` when the string resolves to a
species already in `Fixtures/seed/cypress-seed.sqlite`, and EMPTY when it does
not. An empty id is not a defect and it is not a TODO: it is this file saying the
corpus has no row for that taxon yet, which the build resolves by minting one.
What it must never be is a guess.

---------------------------------------------------------------------------
HOW A STRING IS RESOLVED (RULING D20), AND WHAT EACH STEP MAY CLAIM
---------------------------------------------------------------------------

Five rules, tried in order, stopping at the first that lands. Each is recorded
per line in `Fixtures/nyc_species_map_citations.csv`, so every mapped row can be
audited back to the rule and the authority that produced it.

  R0  EXACT. The scientific half already matches a corpus name, case-folded.
      Claims nothing.

  R1  HYBRID SIGN. `Platanus x acerifolia` -> `Platanus acerifolia`. The
      multiplication sign in a nothospecies name is NOTATION and not part of the
      epithet -- ICN (Shenzhen Code) Art. H.3A.1, Art. 23.1. The two strings
      denote one taxon, so this is an ORTHOGRAPHIC equivalence, not a synonymy.

  R2/R3  RANK WITHIN THE SPECIES. `Gleditsia triacanthos var. inermis` ->
      `Gleditsia triacanthos`; `Zelkova serrata 'Green Vase'` -> `Zelkova
      serrata`. A variety, subspecies or form is a rank within the species (ICN
      Art. 4) and a cultivar is an assemblage selected within a taxon (ICNCP 9th
      ed., Art. 2.1), so every member of one is a member of the species. The
      "thornless" and "'Green Vase'" facts are lost; nothing false is asserted.

      R0 runs first, so a cultivar the corpus already carries keeps its own
      identity: NYC's `Platanus x acerifolia 'Bloodgood'` reaches the corpus's
      own `Platanus acerifolia 'Bloodgood'` through R1 and never reaches R3.

  R4  ORTHOGRAPHIC CORRECTION, only for a misspelling THIS SAME DATASET
      disproves. `Platanus x acerfolia 'Exclamation'` sits beside 97,449 rows
      spelling it `acerifolia`. This is the `patanus racemosa` precedent in
      `inventory_adapters.QSPECIES_NAME_CORRECTIONS` -- an edit-distance-1
      variant of a name present in the same publisher's own data. Anything
      needing more than that is not corrected here.

WHAT IS DELIBERATELY NOT DONE, AND WHY THE 90% GATE IS NOT MET.

**No synonymy ruling is applied, because none is available to apply.** All 268
values left over after R0-R4 were checked against ITIS on 2026-08-14 and **not
one is a synonym of a name in the corpus**:

    150 values / 106,956 rows   accepted names in their own right
     11 values /     470 rows   synonyms -- of taxa the corpus also lacks
    107 values /  14,888 rows   cultivars, which the ICNCP governs and ITIS
                                does not index

Mapping any of them would assert that `Fraxinus pennsylvanica` is `Fraxinus
americana`. Green ash is not white ash, `Gymnocladus`/`Eucommia`/`Amelanchier`/
`Cladrastis` are absent from the corpus entirely, and `Taxodium distichum` is not
the corpus's `Taxodium mucronatum`. That is the fabrication DECISIONS constraint
15 forbids, so those rows stay unmapped and the coverage number stays honest.

AUTHORITIES, NAMED ONCE AND USED CONSISTENTLY:
  * nomenclatural rank and notation -- ICN (Shenzhen Code, 2018); ICNCP 9th ed.
  * accepted-name and synonym status -- ITIS, https://www.itis.gov/, with the
    per-name TSN recorded in the citations file.

Usage:
    python3 Tools/build_nyc_species_map.py --extract PATH/tree_points.csv
        [--seed Fixtures/seed/cypress-seed.sqlite]
        [--out Fixtures/nyc_species_map.csv]
        [--citations Fixtures/nyc_species_map_citations.csv]
        [--itis-cache PATH/itis_cache.json] [--unmapped-report PATH]
        [--structures Full]
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inventory_adapters import NYCTreePointAdapter, normalise_species_key  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: The hybrid multiplication marker as NYC writes it -- `x`, `x.` or `×` as a
#: WHOLE TOKEN. Never a letter inside an epithet: `Malus x zumi` has a marker and
#: `Quercus texana` must not lose its `x`.
HYBRID_MARKER = re.compile(r"(?:^|\s)(?:x|×)\.?(?=\s)", re.IGNORECASE)

#: A quoted cultivar epithet. Single quotes are the ICNCP's own marker (Art. 21).
CULTIVAR_EPITHET = re.compile(r"\s*'[^']*'\s*")

#: An infraspecific rank and its epithet (ICN Art. 24).
INFRASPECIFIC = re.compile(r"\s+(?:var|ssp|subsp|f|cv)\.\s+\S+")

#: R4. Keyed on the misspelling, valued (correction, the evidence for it).
#: ONE ENTRY, and it earns its place the way `patanus racemosa` did.
NYC_SPELLING_CORRECTIONS = {
    "platanus x acerfolia": (
        "Platanus x acerifolia",
        "edit-distance-1 of 'Platanus x acerifolia', which occurs 97,449 times in "
        "the same 2026-08-14 extract against this spelling's 1,715",
    ),
}


def collapse(text: str) -> str:
    return " ".join((text or "").split())


def strip_hybrid(name: str) -> str:
    return collapse(HYBRID_MARKER.sub(" ", name))


def to_parent_taxon(name: str) -> str:
    """Drop cultivar and infraspecific epithets, leaving the species."""
    return collapse(INFRASPECIFIC.sub("", CULTIVAR_EPITHET.sub(" ", name)))


def apply_spelling_correction(name: str):
    """(corrected, evidence) or (name, None). R4."""
    lowered = normalise_species_key(name)
    for wrong, (right, evidence) in NYC_SPELLING_CORRECTIONS.items():
        if lowered.startswith(wrong):
            return collapse(right + name[len(wrong):]), evidence
    return name, None


def resolve(scientific: str, corpus: dict):
    """(species_uuid, corpus_name, rule, authority, note), or None.

    The R0..R4 cascade. Order matters: R0 before R1 so a corpus cultivar keeps
    its own identity, and R4 last so a correction is only reached when nothing
    else worked.
    """
    for candidate, rule, authority, note in (
        (scientific, "R0 exact", "-", "already a corpus name"),
        (strip_hybrid(scientific), "R1 hybrid sign",
         "ICN (Shenzhen Code) Art. H.3A.1, Art. 23.1",
         "the multiplication sign is notation, not part of the epithet"),
        (to_parent_taxon(scientific), "R2/R3 rank within species",
         "ICN Art. 4 (infraspecific); ICNCP 9th ed. Art. 2.1 (cultivar)",
         "a variety/form/cultivar is a member of its species"),
        (to_parent_taxon(strip_hybrid(scientific)), "R1+R2/R3",
         "ICN Art. H.3A.1 + Art. 4 / ICNCP Art. 2.1",
         "hybrid notation stripped, then reduced to the species"),
    ):
        hit = corpus.get(normalise_species_key(candidate))
        if hit:
            return hit[0], hit[1], rule, authority, note

    corrected, evidence = apply_spelling_correction(scientific)
    if evidence:
        for candidate in (corrected, strip_hybrid(corrected), to_parent_taxon(corrected),
                          to_parent_taxon(strip_hybrid(corrected))):
            hit = corpus.get(normalise_species_key(candidate))
            if hit:
                return (hit[0], hit[1], "R4 spelling correction",
                        "this dataset's own spelling frequency", evidence)
    return None


def load_corpus(seed_path: str) -> dict:
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
    ap.add_argument("--extract", required=True)
    ap.add_argument("--seed", default=os.path.join(REPO, "Fixtures", "seed", "cypress-seed.sqlite"))
    ap.add_argument("--out", default=os.path.join(REPO, "Fixtures", "nyc_species_map.csv"))
    ap.add_argument("--citations",
                    default=os.path.join(REPO, "Fixtures", "nyc_species_map_citations.csv"))
    ap.add_argument("--itis-cache", default=None)
    ap.add_argument("--unmapped-report", default=None)
    ap.add_argument("--structures", default="Full")
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
    total_rows = sum(counts.values())

    itis = {}
    if args.itis_cache and os.path.exists(args.itis_cache):
        with open(args.itis_cache, "r", encoding="utf-8") as fh:
            itis = json.load(fh)

    rows, citations, unmapped = [], [], []
    by_rule = collections.Counter()
    rule_rows = collections.Counter()

    for packed, n in counts.most_common():
        if not packed:
            by_rule["blank species string"] += 1
            rule_rows["blank species string"] += n
            continue
        scientific, _common = NYCTreePointAdapter.split_genus_species(packed)
        confidence = NYCTreePointAdapter.confidence_for(scientific)

        if scientific and scientific.strip().lower() == "unknown":
            rows.append((packed, "", 0.0))
            citations.append((packed, "", "non-taxon", "RULINGS R18",
                              "a tree of unknown species is a tree, not a species"))
            by_rule["non-taxon"] += 1
            rule_rows["non-taxon"] += n
            continue

        hit = resolve(scientific, corpus)
        if hit:
            species_uuid, corpus_name, rule, authority, note = hit
            rows.append((packed, species_uuid, confidence or 0.0))
            citations.append((packed, corpus_name, rule, authority, note))
            by_rule[rule] += 1
            rule_rows[rule] += n
        else:
            rows.append((packed, "", confidence or 0.0))
            record = itis.get(scientific or "", {})
            status = record.get("status") or "not checked"
            tsn = record.get("tsn") or ""
            citations.append((
                packed, "", f"unmapped ({status})",
                f"ITIS TSN {tsn}" if tsn else "ITIS: no exact match",
                record.get("accepted") or
                ("accepted taxon absent from the corpus; the build mints it"
                 if status == "accepted" else "cultivar, not indexed by ITIS"),
            ))
            by_rule["unmapped"] += 1
            rule_rows["unmapped"] += n
            unmapped.append((packed, scientific, n, status, tsn, record.get("accepted")))

    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["qSpecies_string", "species_id", "confidence"])
        for packed, species_id, confidence in rows:
            writer.writerow([packed, species_id, f"{confidence:.2f}"])
    print(f"wrote {args.out}: {len(rows):,} distinct species strings")

    with open(args.citations, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["qSpecies_string", "resolved_to", "rule", "authority", "note"])
        for line in citations:
            writer.writerow(line)
    print(f"wrote {args.citations}")

    print()
    mapped_rows = sum(v for k, v in rule_rows.items()
                      if k not in ("unmapped", "non-taxon", "blank species string"))
    print(f"{'rule':34} {'values':>7} {'rows':>10}")
    for rule in ("R0 exact", "R1 hybrid sign", "R2/R3 rank within species", "R1+R2/R3",
                 "R4 spelling correction", "non-taxon", "blank species string", "unmapped"):
        if by_rule[rule] or rule_rows[rule]:
            print(f"{rule:34} {by_rule[rule]:>7,} {rule_rows[rule]:>10,}")
    print()
    print(f"MAPPED TO AN EXISTING CORPUS SPECIES: {mapped_rows:,} of {total_rows:,} rows "
          f"= {100 * mapped_rows / total_rows:.2f}%")
    gate = int(total_rows * 0.9)
    print(f"RULING D20 requires >= 90% ({gate:,} rows) before a first NYC publish")
    if mapped_rows < gate:
        print(f"  SHORT BY {gate - mapped_rows:,} rows. See the unmapped report: not one of the")
        print(f"  remaining values is a synonym of a corpus name, so closing this gap by")
        print(f"  mapping is not available without asserting a synonymy no authority supports.")

    if args.unmapped_report:
        with open(args.unmapped_report, "w", encoding="utf-8") as fh:
            fh.write(
                "# NYC GenusSpecies values that resolve to NO species in the seed corpus\n"
                "#\n"
                "# Checked against ITIS (https://www.itis.gov/) on 2026-08-14. NOT ONE of\n"
                "# these is a synonym of a name the corpus holds -- they are accepted taxa\n"
                "# the corpus does not carry (a California-derived corpus meeting an\n"
                "# Eastern-seaboard flora), or cultivars the ICNCP governs and ITIS does\n"
                "# not index. Mapping any of them would assert a synonymy no authority\n"
                "# supports, which DECISIONS constraint 15 forbids.\n"
                "#\n"
                "# columns: rows<TAB>ITIS status<TAB>TSN<TAB>accepted name<TAB>scientific name\n\n"
            )
            for packed, scientific, n, status, tsn, accepted in sorted(unmapped, key=lambda r: -r[2]):
                fh.write(f"{n}\t{status}\t{tsn or ''}\t{accepted or ''}\t{scientific}\n")
        print(f"wrote {args.unmapped_report}: {len(unmapped):,} values for review")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
