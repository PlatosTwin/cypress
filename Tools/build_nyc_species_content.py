#!/usr/bin/env python3
"""
build_nyc_species_content.py -- Fixtures/species/nyc_species.yaml, with citations.

The curation half of RULING D20. NYC's street trees are an Eastern-seaboard flora
and the seed's species corpus was built from San Francisco and San Jose, so most
of the taxa NYC publishes reach the seed as a species row with NO `family` and no
`leaf_retention` -- 52.12% of NYC rows land on a species carrying both, against
93.43% for the California rows. This script closes that gap the way the corpus
was built in the first place, through the same two authorities, and writes a
third fixture file in the same shape as `leaf_retention.yaml`.

**IT INVENTS NOTHING (DECISIONS constraint 15).** Every value it writes carries a
citation naming the source, the field it came from, the query that produced it and
the date. Where neither authority answers, the value is `null`, which the app
renders as "not known yet" -- that is the existing corpus's own convention, and 66
of its 577 entries already use it.

AUTHORITIES, WHICH ARE THE CORPUS'S OWN AND NOT NEW ONES:

  * `family` -- GBIF Backbone Taxonomy, `GET /v1/species/match`, CC BY 4.0. The
    same API and the same field `leaf_retention.yaml` cites for its families.
  * `leaf_retention` -- Cal Poly SelecTree (Urban Forest Ecosystems Institute),
    `foliage_type`, with the vocabulary mapping SOURCES.md §2 records:
    `Evergreen -> evergreen`, `Deciduous -> deciduous`,
    `Partly Deciduous -> semi_deciduous`. Those are the only three values it takes.

    SelecTree's index endpoint returns the whole catalogue whatever `name` is
    passed, which is how SOURCES.md §2 says the catalogue was enumerated the
    first time; this script does the same and matches locally.

MATCHING, AND WHAT EACH MATCH IS ALLOWED TO CLAIM. Recorded per value as
`match_method`, reusing `leaf_retention.yaml`'s own vocabulary:

    selectree_name_exact          the taxon matched a SelecTree name outright
    selectree_species_level       the NYC string names a cultivar or an
                                  infraspecific taxon and the match is at species
                                  rank. Legitimate for `leaf_retention` because a
                                  cultivar's habit is its species' habit unless a
                                  source says otherwise -- and the same convention
                                  leaf_retention.yaml already uses.
    gbif_match_exact              GBIF returned matchType EXACT
    gbif_match_genus_rank         the NYC string is a bare genus and GBIF resolved
                                  it to that genus; the family of a genus is not
                                  in doubt
    gbif_match_species_level      the NYC string names a cultivar or a variety and
                                  the family comes from an EXACT match on its
                                  parent binomial

A FUZZY GBIF match is thrown away rather than recorded, and never appears here. A
fuzzy match is a guess with a confidence score attached, and this file may not
contain guesses.

Usage:
    python3 Tools/build_nyc_species_content.py --seed PATH/nyc-whole-city.sqlite
        [--out Fixtures/species/nyc_species.yaml]
        [--cache PATH/species_content_cache.json]
        [--selectree-catalogue PATH/selectree_catalogue.json]
        [--min-rows 1]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys

import yaml
import time
import urllib.parse
import urllib.request
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from inventory_adapters import normalise_species_key  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = "Cypress-tree-ingest/1.0 (research; contact nmbogdan@alumni.stanford.edu)"
ACCESSED = "2026-08-14"

GBIF_MATCH = "https://api.gbif.org/v1/species/match"
SELECTREE_DETAIL = "https://selectree.calpoly.edu/api/tree/detail/"
SELECTREE_INDEX = "https://selectree.calpoly.edu/api/tree/search-by-name"

#: SOURCES.md §2. The only three values `foliage_type` takes.
FOLIAGE_TO_LEAF_RETENTION = {
    "evergreen": "evergreen",
    "deciduous": "deciduous",
    "partly deciduous": "semi_deciduous",
}

#: SelecTree writes the hybrid sign as the HTML entity `&times` -- 63 of its
#: 2,087 catalogue names do, `Platanus &times hispanica` among them. Left
#: undecoded it makes `Platanus x acerifolia` unmatchable, which cost 97,449 rows
#: of leaf_retention on the first pass.
HTML_TIMES = re.compile(r"&times;?", re.IGNORECASE)
HYBRID_MARKER = re.compile(r"(?:^|\s)(?:x|×)\.?(?=\s)", re.IGNORECASE)
CULTIVAR_EPITHET = re.compile(r"\s*'[^']*'\s*")
INFRASPECIFIC = re.compile(r"\s+(?:var|ssp|subsp|f|cv)\.\s+\S+")


def collapse(text):
    return " ".join((text or "").split())


def parent_binomial(name):
    """`Genus species` from a cultivar/variety string, for a species-rank match."""
    return collapse(INFRASPECIFIC.sub("", CULTIVAR_EPITHET.sub(" ", name)))


def without_hybrid(name):
    """Drop the hybrid multiplication marker in any of its three spellings."""
    return collapse(HYBRID_MARKER.sub(" ", HTML_TIMES.sub(" ", name or "")))


def fetch_json(url, cache, key, decode_latin1=False):
    """Cached GET. ITIS/SelecTree serve ISO-8859-1 in places; see the NYC errata."""
    if key in cache:
        return cache[key]
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
    except Exception as error:  # noqa: BLE001
        # NOT cached. A cached failure never retries, and a transient network
        # error would then be indistinguishable from "the authority has no
        # record" for the rest of the file's life -- which is how 74 taxa lost a
        # family they could have had.
        return {"__error__": str(error)[:200]}
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("iso-8859-1")
    try:
        parsed = json.loads(text)
    except ValueError as error:
        return {"__error__": f"not json: {error}"}
    cache[key] = parsed
    time.sleep(0.25)
    return parsed


def _gbif_query(name, cache):
    url = f"{GBIF_MATCH}?" + urllib.parse.urlencode({"kingdom": "Plantae", "name": name})
    return url, fetch_json(url, cache, f"gbif:{name}")


def gbif_family(name, cache):
    """(family, citation) or (None, None).

    THREE ACCEPTED SHAPES, and each says how far it is trusted. What is never
    accepted is a FUZZY match -- that is a guess with a confidence score on it,
    and this file may not contain guesses.

      gbif_match_exact         matchType EXACT. The name is the name.
      gbif_match_genus_rank    the NYC string is a BARE GENUS (`Prunus`, `Acer`)
                               and GBIF resolved it to that genus. GBIF reports
                               this as HIGHERRANK because the query named no
                               species, but the family of a genus is not in doubt.
                               Only ever accepted when the query is one word AND
                               the returned rank is GENUS.
      gbif_match_species_level the NYC string names a cultivar or a variety
                               (`Gleditsia triacanthos var. inermis`); the family
                               is taken from an EXACT match on its parent
                               binomial. Same convention as the SelecTree
                               species-level match, and the family of a variety is
                               the family of its species.
    """
    url, payload = _gbif_query(name, cache)
    if isinstance(payload, dict) and payload.get("family"):
        if payload.get("matchType") == "EXACT":
            method, query = "gbif_match_exact", name
        elif (payload.get("matchType") == "HIGHERRANK"
              and payload.get("rank") == "GENUS"
              and len(name.split()) == 1):
            method, query = "gbif_match_genus_rank", name
        else:
            payload = None
        if payload:
            return payload["family"], _family_citation(url, query, payload, method)

    # Fall back to the parent binomial for a cultivar / infraspecific string.
    parent = without_hybrid(parent_binomial(name))
    if parent and normalise_species_key(parent) != normalise_species_key(name):
        url, payload = _gbif_query(parent, cache)
        if (isinstance(payload, dict) and payload.get("family")
                and payload.get("matchType") == "EXACT"):
            return payload["family"], _family_citation(
                url, parent, payload, "gbif_match_species_level")
    return None, None


def _family_citation(url, query, payload, method):
    return {
        "source": "GBIF Backbone Taxonomy",
        "api": "GET /v1/species/match",
        "url": url,
        "query": query,
        "field": "family",
        "value": payload["family"],
        "matched_name": payload.get("scientificName"),
        "match_type": payload.get("matchType"),
        "match_confidence": payload.get("confidence"),
        "rank_matched": payload.get("rank"),
        "match_method": method,
        "accessed": ACCESSED,
        "licence": "CC BY 4.0",
    }


def selectree_index(catalogue_path, cache):
    """The whole SelecTree catalogue, keyed by normalised accepted name."""
    if os.path.exists(catalogue_path):
        with open(catalogue_path, "r", encoding="utf-8") as fh:
            records = json.load(fh)
    else:
        payload = fetch_json(SELECTREE_INDEX + "?name=x", cache, "selectree:index")
        records = payload if isinstance(payload, list) else []
        with open(catalogue_path, "w", encoding="utf-8") as fh:
            json.dump(records, fh)
    index = {}
    by_genus = {}
    for record in records:
        for field in ("accepted_scientific", "name_unformatted", "name_concat"):
            value = record.get(field)
            if value:
                index.setdefault(normalise_species_key(value), record)
                index.setdefault(normalise_species_key(without_hybrid(value)), record)
        name = record.get("accepted_scientific") or record.get("name_unformatted") or ""
        genus = normalise_species_key(without_hybrid(name)).split(" ")[0] if name else ""
        if genus:
            by_genus.setdefault(genus, []).append(record)
    return index, by_genus, len(records)


def _leaf_from_detail(name, record, method, candidate, cache):
    tree_id = record.get("tree_id")
    detail = fetch_json(f"{SELECTREE_DETAIL}{tree_id}", cache, f"selectree:{tree_id}")
    if not isinstance(detail, dict) or detail.get("__error__"):
        return None, None
    foliage = detail.get("foliage_type")
    if isinstance(foliage, dict):
        foliage = foliage.get("value") or foliage.get("name")
    if not foliage:
        return None, None
    mapped = FOLIAGE_TO_LEAF_RETENTION.get(str(foliage).strip().lower())
    if not mapped:
        return None, None
    return mapped, {
        "source": "Cal Poly SelecTree (Urban Forest Ecosystems Institute)",
        "url": f"https://selectree.calpoly.edu/tree-detail/{tree_id}",
        "api": f"{SELECTREE_DETAIL}{tree_id}",
        "matched_taxon": record.get("accepted_scientific") or record.get("name_unformatted"),
        "query": candidate,
        "field": "foliage_type",
        "value": str(foliage),
        "derived": mapped,
        "match_method": method,
        "accessed": ACCESSED,
        "licence": "no published reuse licence; scalar facts only, see SOURCES.md §2",
    }


def selectree_synonym(name, by_genus, cache):
    """A SelecTree record that itself lists `name` among its `other_taxa`.

    This is `leaf_retention.yaml`'s own `selectree_synonym_other_taxa` method,
    which it uses 50 times: SelecTree publishes the synonymy, so following it
    asserts nothing this pipeline made up. `Platanus x acerifolia` reaches
    `Platanus x hispanica` this way -- record 1099 lists `Platanus &times
    acerifolia` in `other_taxa` -- and that one link is worth 97,449 rows.

    Only records in the SAME GENUS are consulted, which bounds the work to a
    handful of detail fetches and cannot cross a genus boundary.
    """
    target = normalise_species_key(without_hybrid(name))
    genus = target.split(" ")[0] if target else ""
    for record in by_genus.get(genus, []):
        tree_id = record.get("tree_id")
        detail = fetch_json(f"{SELECTREE_DETAIL}{tree_id}", cache, f"selectree:{tree_id}")
        if not isinstance(detail, dict) or detail.get("__error__"):
            continue
        for other in detail.get("other_taxa") or []:
            other_name = other.get("name_concat") or ""
            if normalise_species_key(without_hybrid(other_name)) == target:
                return _leaf_from_detail(
                    name, record, "selectree_synonym_other_taxa", other_name, cache)
    return None, None


def selectree_leaf_retention(name, index, cache):
    """(leaf_retention, citation) or (None, None)."""
    candidates = [
        (name, "selectree_name_exact"),
        (without_hybrid(name), "selectree_name_exact"),
        (parent_binomial(name), "selectree_species_level"),
        (without_hybrid(parent_binomial(name)), "selectree_species_level"),
    ]
    for candidate, method in candidates:
        record = index.get(normalise_species_key(candidate))
        if not record:
            continue
        mapped, citation = _leaf_from_detail(name, record, method, candidate, cache)
        if mapped:
            return mapped, citation
    return None, None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seed", required=True,
                    help="a built seed containing the NYC species (for names + row weights)")
    ap.add_argument("--out", default=os.path.join(REPO, "Fixtures", "species", "nyc_species.yaml"))
    ap.add_argument("--cache", required=True)
    ap.add_argument("--selectree-catalogue", required=True)
    ap.add_argument("--min-rows", type=int, default=1)
    args = ap.parse_args(argv)

    cache = {}
    if os.path.exists(args.cache):
        with open(args.cache, "r", encoding="utf-8") as fh:
            cache = json.load(fh)

    index, by_genus, catalogue_size = selectree_index(args.selectree_catalogue, cache)
    print(f"SelecTree catalogue: {catalogue_size:,} records, {len(index):,} lookup keys")

    # WHICH SPECIES THIS FILE IS RESPONSIBLE FOR, decided from the OTHER TWO
    # FIXTURES and never from the seed's current content.
    #
    # Reading `species.family IS NULL` off a built seed makes this script
    # non-idempotent in the worst way: once its own output has been folded into a
    # seed, those species are no longer "missing", so a re-run targets only the
    # leftovers and REWRITES the file with just those -- silently discarding
    # every entry it wrote last time. That happened once here, 506 entries down
    # to 143. The fixtures are the stable input; the seed is downstream of them.
    covered = set()
    for fixture in ("leaf_retention.yaml", "curated.yaml"):
        path = os.path.join(REPO, "Fixtures", "species", fixture)
        with open(path, "r", encoding="utf-8") as fh:
            document = yaml.safe_load(fh)
        for entry in document.get("species") or []:
            if entry.get("family") or entry.get("leaf_retention"):
                covered.add(entry.get("species_uuid"))
    print(f"already covered by the two California fixtures: {len(covered):,} species")

    con = sqlite3.connect(args.seed)
    targets = con.execute(
        """SELECT s.scientific_name, s.uuid, s.common_name, count(*) n
           FROM trees t JOIN species s ON t.species_current = s.id
           WHERE t.id_space = 'us-ny-nyc'
           GROUP BY s.id HAVING n >= ? ORDER BY n DESC""",
        (args.min_rows,),
    ).fetchall()
    con.close()
    needed = [(name, uu, common, n) for name, uu, common, n in targets if uu not in covered]
    print(f"NYC species in the seed: {len(targets):,}; lacking family or leaf_retention: "
          f"{len(needed):,}")

    entries = []
    got = {"family": 0, "leaf_retention": 0, "both": 0, "neither": 0}
    for i, (name, species_uuid, common_name, rows) in enumerate(needed, 1):
        citations = {}
        new_family, family_citation = gbif_family(name, cache)
        if new_family:
            citations["family"] = [family_citation]
            got["family"] += 1
        new_leaf, leaf_citation = selectree_leaf_retention(name, index, cache)
        if not new_leaf:
            new_leaf, leaf_citation = selectree_synonym(name, by_genus, cache)
        if new_leaf:
            citations["leaf_retention"] = [leaf_citation]
            got["leaf_retention"] += 1
        if new_family and new_leaf:
            got["both"] += 1
        if not new_family and not new_leaf:
            got["neither"] += 1
        entries.append({
            "species_uuid": species_uuid,
            "scientific_name": name,
            # NYC's OWN common name, the half of `GenusSpecies` after the dash,
            # carried through the seed. Not sourced from a botanical authority
            # because it is not a botanical claim -- it is what the publisher of
            # this inventory calls the tree, exactly as leaf_retention.yaml
            # carries DataSF's. `validate_species.py` requires it to agree with
            # the seed row, which is the check that keeps it honest.
            "common_name": common_name,
            "nyc_tree_count": rows,
            "family": new_family,
            "leaf_retention": new_leaf,
            "citations": citations,
        })
        if i % 50 == 0:
            print(f"  ...{i}/{len(needed)}", flush=True)
            with open(args.cache, "w", encoding="utf-8") as fh:
                json.dump(cache, fh)

    with open(args.cache, "w", encoding="utf-8") as fh:
        json.dump(cache, fh)

    header = f'''# Cypress NYC species content -- family and leaf retention (RULING D20).
#
# The third species fixture, beside leaf_retention.yaml (San Francisco's 577) and
# curated.yaml (the authored top 40). One entry per species NYC's Forestry Tree
# Points contributes that the California corpus did not already carry content for.
#
# RULE OF THIS FILE, from DECISIONS constraint 15, identical to the other two:
#   "Do not invent botanical content; the curated YAML is the only source."
# Every non-null value below carries a citation naming the source, the field, the
# query and the date. Where no source answered, the value is null, which the app
# renders as "not known yet" -- the same convention leaf_retention.yaml uses for
# the 66 of its 577 entries that no source covered.
#
# AUTHORITIES (both already used by leaf_retention.yaml; no new ones introduced):
#   family          GBIF Backbone Taxonomy, GET /v1/species/match, CC BY 4.0.
#                   EXACT matches only -- a fuzzy match is a guess with a number
#                   on it and is rejected rather than recorded.
#   leaf_retention  Cal Poly SelecTree (UFEI), field `foliage_type`, mapped
#                   Evergreen/Deciduous/Partly Deciduous -> evergreen/deciduous/
#                   semi_deciduous exactly as SOURCES.md section 2 records.
#
# match_method values used here, from leaf_retention.yaml's own vocabulary:
#   gbif_match_exact          GBIF returned matchType EXACT
#   selectree_name_exact      the taxon matched a SelecTree name outright
#   selectree_species_level   the NYC string names a cultivar or an infraspecific
#                             taxon; the match is at species rank, which is what
#                             leaf_retention.yaml already does for DataSF cultivars
#
# `nyc_tree_count` is this taxon's row count in the 2026-08-14 whole-city extract,
# carried so a later reader can see what each entry is worth, exactly as
# leaf_retention.yaml carries `sf_tree_count`.
#
# Generated by Tools/build_nyc_species_content.py. Not hand-edited.
#
generated: "{date.today().isoformat()}"
generator: "Tools/build_nyc_species_content.py"
schema_version: 1
species:
'''

    def yaml_str(value):
        if value is None:
            return "null"
        return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = [header]
    for entry in entries:
        lines.append(f'- species_uuid: "{entry["species_uuid"]}"')
        lines.append(f'  scientific_name: {yaml_str(entry["scientific_name"])}')
        lines.append(f'  common_name: {yaml_str(entry["common_name"])}')
        lines.append(f'  nyc_tree_count: {entry["nyc_tree_count"]}')
        lines.append(f'  family: {yaml_str(entry["family"])}')
        lines.append(f'  leaf_retention: {yaml_str(entry["leaf_retention"])}')
        if entry["citations"]:
            lines.append("  citations:")
            for field, citation_list in entry["citations"].items():
                lines.append(f"    {field}:")
                for citation in citation_list:
                    first = True
                    for key, value in citation.items():
                        prefix = "      - " if first else "        "
                        first = False
                        lines.append(f"{prefix}{key}: {yaml_str(value)}")
        else:
            lines.append("  citations: {}")
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print()
    print(f"wrote {args.out}: {len(entries):,} entries")
    print(f"  family sourced         : {got['family']:,}")
    print(f"  leaf_retention sourced : {got['leaf_retention']:,}")
    print(f"  both                   : {got['both']:,}")
    print(f"  neither (left null)    : {got['neither']:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
