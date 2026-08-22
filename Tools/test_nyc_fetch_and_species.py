#!/usr/bin/env python3
"""Tests for the NYC fetcher's dedupe rule (D19) and the species cascade (D20).

    python3 Tools/test_nyc_fetch_and_species.py

These live apart from `test_nyc_inventory_adapter.py` because they are about the
two things that happen either side of the adapter: how the cached extract is
made, and how a species string is resolved against the corpus.

Every test states what would have to go wrong for it to fail.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_nyc_species_map as smap  # noqa: E402
import fetch_nyc_trees as fetch  # noqa: E402

PASSED = 0
FAILURES: list = []


def check(condition, message):
    global PASSED
    if condition:
        PASSED += 1
    else:
        FAILURES.append(message)


# ---------------------------------------------------------------------------
# RULING D19 -- deterministic deduplication
# ---------------------------------------------------------------------------


def test_objectid_is_compared_as_a_number():
    """THE WHOLE OF D19's TIE-BREAK, and the easiest thing here to get wrong.

    As strings, '10843890' sorts BEFORE '9'. Planting Spaces' OBJECTIDs run into
    eight figures, so a string comparison would pick a different twin than the
    documented rule and the pick would vary with the id range.

    Fails if `_objectid_of` stops coercing to a number.
    """
    # Numerically 9 < 10843890. As STRINGS the order inverts, which is the trap.
    check("10843890" < "9", "the premise of this test is wrong: string order did not invert")
    check(fetch._objectid_of({"objectid": "9"}) < fetch._objectid_of({"objectid": "10843890"}),
          "OBJECTID 9 did not compare LESS than 10843890; the comparison is textual, "
          "so the surviving twin depends on the id range rather than on the rule")
    check(fetch._objectid_of({"objectid": "42"}) == 42.0,
          f"_objectid_of returned {fetch._objectid_of({'objectid': '42'})!r} for '42'")


def test_a_missing_or_junk_objectid_sorts_last():
    """A row with no usable OBJECTID must never win the tie-break, or the
    surviving twin becomes whichever row happened to be malformed.

    Fails if a junk OBJECTID sorts before a real one.
    """
    for junk in ({}, {"objectid": ""}, {"objectid": "not-a-number"}, {"objectid": None}):
        check(fetch._objectid_of(junk) == float("inf"),
              f"a row with objectid {junk.get('objectid')!r} did not sort last")
    check(fetch._objectid_of({"objectid": "999999999"}) < fetch._objectid_of({}),
          "a real OBJECTID did not beat a missing one")


def test_the_dedupe_rule_is_order_independent():
    """The reason D19 exists: the survivor must not depend on page order.

    Fails if feeding the same two rows in the opposite order picks a different
    survivor -- which is exactly what keeping 'whichever arrived first' did.
    """
    low = {"globalid": "G", "objectid": "100", "streetname": "LOW"}
    high = {"globalid": "G", "objectid": "900", "streetname": "HIGH"}

    def survivor(rows):
        best = None
        for row in rows:
            if best is None or fetch._objectid_of(row) < fetch._objectid_of(best):
                best = row
        return best["streetname"]

    check(survivor([low, high]) == "LOW", "min-OBJECTID lost when the low row came first")
    check(survivor([high, low]) == "LOW", "min-OBJECTID lost when the high row came first")


# ---------------------------------------------------------------------------
# RULING D20 -- the species cascade, and what each rule may claim
# ---------------------------------------------------------------------------


def test_the_hybrid_marker_is_stripped_only_as_a_whole_token():
    """R1. `x` is notation in `Platanus x acerifolia` (ICN Art. H.3A.1) and a
    LETTER in `Quercus texana`.

    Fails if the regex eats an `x` inside an epithet, which would mint a species
    named `Quercus texana` -> `Quercus texana` minus its letter.
    """
    check(smap.strip_hybrid("Platanus x acerifolia") == "Platanus acerifolia",
          f"got {smap.strip_hybrid('Platanus x acerifolia')!r}")
    check(smap.strip_hybrid("Tilia x. europaea") == "Tilia europaea",
          f"got {smap.strip_hybrid('Tilia x. europaea')!r}")
    check(smap.strip_hybrid("Malus × zumi") == "Malus zumi",
          f"got {smap.strip_hybrid('Malus × zumi')!r}")
    for untouched in ("Quercus texana", "Larix kaempferi", "Prunus serrula"):
        check(smap.strip_hybrid(untouched) == untouched,
              f"{untouched!r} lost a letter to the hybrid rule: "
              f"{smap.strip_hybrid(untouched)!r}")


def test_rank_reduction_drops_only_infraspecific_and_cultivar_epithets():
    """R2/R3. Fails if the genus or specific epithet is ever damaged -- the
    resulting name would resolve to the wrong species or to none."""
    cases = [
        ("Gleditsia triacanthos var. inermis", "Gleditsia triacanthos"),
        ("Zelkova serrata 'Green Vase'", "Zelkova serrata"),
        ("Gleditsia triacanthos var. inermis 'Skyline'", "Gleditsia triacanthos"),
        ("Fagus sylvatica f. purpurea", "Fagus sylvatica"),
        ("Crataegus crus-galli var. inermis", "Crataegus crus-galli"),
        ("Quercus palustris", "Quercus palustris"),
    ]
    for raw, expected in cases:
        got = smap.to_parent_taxon(raw)
        check(got == expected, f"{raw!r} reduced to {got!r}, expected {expected!r}")


def test_the_cascade_prefers_the_most_specific_match():
    """R0 must run before R1/R2/R3, or a cultivar the corpus HOLDS BY NAME would
    be collapsed into its parent species and lose its identity.

    Fails if `Platanus x acerifolia 'Bloodgood'` stops reaching the corpus's own
    `Platanus acerifolia 'Bloodgood'` and lands on bare `Platanus acerifolia`.
    """
    corpus = {
        "platanus acerifolia": ("uuid-species", "Platanus acerifolia"),
        "platanus acerifolia 'bloodgood'": ("uuid-cultivar", "Platanus acerifolia 'Bloodgood'"),
    }
    hit = smap.resolve("Platanus x acerifolia 'Bloodgood'", corpus)
    check(hit is not None, "the cultivar resolved to nothing at all")
    if hit:
        check(hit[0] == "uuid-cultivar",
              f"the cultivar collapsed to {hit[1]!r} instead of keeping its own row")
        check(hit[2] == "R1 hybrid sign", f"it resolved by rule {hit[2]!r}")
    plain = smap.resolve("Platanus x acerifolia", corpus)
    check(plain and plain[0] == "uuid-species",
          "the bare hybrid name did not reach the species row")


def test_every_rule_carries_an_authority():
    """RULING D20: every synonymy-adjacent ruling cites a source.

    Fails if a rule is ever added that resolves a name with no authority behind
    it -- which is how an uncited judgment gets into the mapping file.
    """
    corpus = {
        "gleditsia triacanthos": ("uuid-g", "Gleditsia triacanthos"),
        "platanus acerifolia": ("uuid-p", "Platanus acerifolia"),
    }
    for name in ("Gleditsia triacanthos",
                 "Platanus x acerifolia",
                 "Gleditsia triacanthos var. inermis",
                 "Gleditsia triacanthos 'Skyline'",
                 "Platanus x acerfolia 'Exclamation'"):
        hit = smap.resolve(name, corpus)
        check(hit is not None, f"{name!r} resolved to nothing")
        if hit:
            _uuid, _corpus_name, rule, authority, _note = hit
            check(bool(rule and authority and authority != ""),
                  f"{name!r} resolved by {rule!r} with authority {authority!r}")


def test_an_unsupportable_name_is_not_resolved():
    """The anti-fabrication rule, as a test. `Fraxinus pennsylvanica` (green ash)
    must NOT resolve to `Fraxinus americana` (white ash) just because the genus
    matches -- that is the exact claim DECISIONS constraint 15 forbids.

    Fails if the cascade ever falls back to a genus-level or fuzzy match.
    """
    corpus = {"fraxinus americana": ("uuid-fa", "Fraxinus americana")}
    for name in ("Fraxinus pennsylvanica", "Quercus bicolor", "Gymnocladus dioicus"):
        check(smap.resolve(name, corpus) is None,
              f"{name!r} was resolved against a corpus that does not contain it: "
              f"{smap.resolve(name, corpus)}")


def test_the_spelling_correction_is_evidence_bound():
    """R4 applies to one misspelling this dataset itself disproves. Fails if it
    starts correcting names the evidence does not cover."""
    corrected, evidence = smap.apply_spelling_correction("Platanus x acerfolia 'Exclamation'")
    check(corrected.startswith("Platanus x acerifolia"), f"got {corrected!r}")
    check(evidence and "97,449" in evidence, f"the correction cites {evidence!r}")
    untouched, none_evidence = smap.apply_spelling_correction("Quercus palustris")
    check(untouched == "Quercus palustris" and none_evidence is None,
          "a correctly spelled name was 'corrected'")


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
