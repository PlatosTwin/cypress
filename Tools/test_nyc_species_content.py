#!/usr/bin/env python3
"""Tests for the NYC species-content curation (RULING D20's curation half).

    python3 Tools/test_nyc_species_content.py

What this file is really guarding is DECISIONS constraint 15: every botanical
value in `Fixtures/species/nyc_species.yaml` must trace to an authority, and a
match that is not good enough must produce `null` rather than a plausible guess.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_nyc_species_content as content  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(REPO, "Fixtures", "species", "nyc_species.yaml")

PASSED = 0
FAILURES: list = []


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


# ---------------------------------------------------------------------------
# name handling
# ---------------------------------------------------------------------------


def test_the_html_times_entity_is_decoded():
    """SelecTree writes the hybrid sign as `&times` in 63 of its 2,087 names.

    Left undecoded, `Platanus x acerifolia` matches nothing and 97,449 NYC rows
    lose their leaf_retention. Fails if the entity stops being handled.
    """
    check(content.without_hybrid("Platanus &times hispanica") == "Platanus hispanica",
          f"got {content.without_hybrid('Platanus &times hispanica')!r}")
    check(content.without_hybrid("Platanus &times; hispanica") == "Platanus hispanica",
          "the entity with its trailing semicolon was not handled")
    check(content.without_hybrid("Platanus x acerifolia") == "Platanus acerifolia",
          "the plain ASCII hybrid marker regressed")
    check(content.without_hybrid("Quercus texana") == "Quercus texana",
          "a letter inside an epithet was eaten")


def test_parent_binomial_strips_only_what_it_should():
    """Fails if a cultivar reduction damages the genus or specific epithet."""
    for raw, expected in (
        ("Gleditsia triacanthos var. inermis", "Gleditsia triacanthos"),
        ("Zelkova serrata 'Green Vase'", "Zelkova serrata"),
        ("Quercus palustris", "Quercus palustris"),
        ("Crataegus crus-galli var. inermis", "Crataegus crus-galli"),
    ):
        got = content.parent_binomial(raw)
        check(got == expected, f"{raw!r} -> {got!r}, expected {expected!r}")


# ---------------------------------------------------------------------------
# what a match is allowed to claim
# ---------------------------------------------------------------------------


def test_a_fuzzy_gbif_match_is_rejected():
    """A fuzzy match is a guess with a confidence score on it, and this file may
    not contain guesses.

    Fails if `gbif_family` ever accepts a matchType other than EXACT, or a
    HIGHERRANK that is not a genus-rank hit on a one-word query.
    """
    cache = {"gbif:Fake namus": {"matchType": "FUZZY", "family": "Madeupaceae",
                                 "confidence": 88, "rank": "SPECIES"}}
    family, citation = content.gbif_family("Fake namus", cache)
    check(family is None and citation is None,
          f"a FUZZY GBIF match was accepted as {family!r}")


def test_a_higherrank_match_is_only_taken_for_a_bare_genus():
    """GBIF answers HIGHERRANK for both `Prunus` (rank GENUS -- fine, the family
    of a genus is not in doubt) and `Gleditsia triacanthos var. inermis` (rank
    FAMILY -- too coarse to record as that taxon's own answer).

    Fails if the guard stops distinguishing them.
    """
    genus_cache = {"gbif:Prunus": {"matchType": "HIGHERRANK", "rank": "GENUS",
                                   "family": "Rosaceae", "confidence": 95,
                                   "scientificName": "Prunus L."}}
    family, citation = content.gbif_family("Prunus", genus_cache)
    check(family == "Rosaceae", f"a bare genus did not take its family: {family!r}")
    check(citation and citation["match_method"] == "gbif_match_genus_rank",
          f"recorded as {citation['match_method'] if citation else None!r}")

    # Same shape, but the query is two words and the rank returned is FAMILY.
    coarse = {"gbif:Some species": {"matchType": "HIGHERRANK", "rank": "FAMILY",
                                    "family": "Fabaceae", "confidence": 99},
              "gbif:Some": {"matchType": "HIGHERRANK", "rank": "FAMILY",
                            "family": "Fabaceae", "confidence": 99}}
    family, _citation = content.gbif_family("Some species", coarse)
    check(family is None,
          f"a FAMILY-rank match on a two-word query was accepted as {family!r}")


def test_every_non_null_value_in_the_fixture_carries_a_citation():
    """The anti-fabrication gate, applied to the artifact rather than the code.

    Fails if any entry states a family or a leaf_retention with no citation --
    which is exactly what an invented value would look like.
    """
    import yaml
    with open(FIXTURE, "r", encoding="utf-8") as fh:
        document = yaml.safe_load(fh)
    entries = document.get("species") or []
    check(bool(entries), "the fixture is empty")
    for entry in entries:
        citations = entry.get("citations") or {}
        for field in ("family", "leaf_retention"):
            if entry.get(field) is not None:
                cited = citations.get(field) or []
                check(bool(cited),
                      f"{entry['scientific_name']}: {field} is "
                      f"{entry[field]!r} with NO citation")
                for citation in cited:
                    for required in ("source", "url", "field", "accessed", "match_method"):
                        check(citation.get(required),
                              f"{entry['scientific_name']}: {field} citation is "
                              f"missing {required!r}")


def test_leaf_retention_only_ever_takes_the_three_documented_values():
    """SOURCES.md §2: `foliage_type` maps onto exactly three values. Fails if a
    fourth appears, which the database CHECK and Species.init would reject."""
    import yaml
    with open(FIXTURE, "r", encoding="utf-8") as fh:
        document = yaml.safe_load(fh)
    allowed = {"evergreen", "deciduous", "semi_deciduous", None}
    for entry in document.get("species") or []:
        check(entry.get("leaf_retention") in allowed,
              f"{entry['scientific_name']}: leaf_retention "
              f"{entry.get('leaf_retention')!r} is not one of {sorted(x for x in allowed if x)}")


def test_the_foliage_vocabulary_is_the_one_sources_md_records():
    """Fails if the mapping drifts from SOURCES.md §2, which is the only place
    the three values are justified."""
    check(content.FOLIAGE_TO_LEAF_RETENTION == {
        "evergreen": "evergreen",
        "deciduous": "deciduous",
        "partly deciduous": "semi_deciduous",
    }, f"the vocabulary is now {content.FOLIAGE_TO_LEAF_RETENTION}")


def test_a_transient_failure_is_not_cached():
    """A cached failure never retries, so a flaky network becomes a permanent
    "the authority has no record". That cost 74 taxa a family on the first pass.

    Fails if `fetch_json` writes an error into the cache.
    """
    cache = {}
    result = content.fetch_json("http://127.0.0.1:9/nothing", cache, "probe")
    check(result.get("__error__"), "the unreachable URL did not report an error")
    check("probe" not in cache,
          f"a failure was cached under 'probe': {cache.get('probe')!r}")


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
