# Screen 08, both tabs. This is a tester-visible line rather than an `internal:` one because the
# pain is what testers actually filed.
#
# ── WHAT MAKES EACH CLAUSE TRUE AT MERGE, measured rather than assumed ──────────────────────
#
#   * "opens straight away" — measured on the assigned simulator (iPhone 16 Pro Max), the same
#     instrument at both revisions, calibrated against a known 50 ms sleep and a no-op before
#     either reading. A 40-tree grove over the shipped seed: the Trees tab's read went
#     21,709 ms → 26.8 ms, and the Species tab's 282 ms → 6.0 ms. Both answers are identical
#     across the change — 40 entries, 14 species known, 189 in the area.
#   * "instead of a blank column" is the part a tester can *see*, and it was photographed on the
#     running screen rather than inferred. Before: twelve consecutive screenshots over four and a
#     half seconds are byte-identical and empty under the pill row, and the list arrives about
#     twenty seconds after the tap. After: the first screenshot taken after the same tap is the
#     finished list — the same ten trees, in the same order.
#
# ── WHY NO LOADING SPINNER IS MENTIONED, OR ADDED ──────────────────────────────────────────
#
# The blank column had no loading state, and one was considered. It is not in this change: at
# 27 ms there is nothing to show a reader, a spinner that flashes for two frames is worse than
# none, and a new loading state would be copy that appears in no mock (DECISIONS constraint 21).
# The measurement is what settled it, in that order.
#
# ── WHAT IS DELIBERATELY NOT CLAIMED ───────────────────────────────────────────────────────
#
# Tree profiles also got much faster — the one-tree lookup went from a whole-inventory scan to an
# index seek — but a profile that already opened in a fifth of a second does not read as slow, so
# announcing it would send a tester looking for a difference they cannot feel. Left out.
#
# Nor does this claim anything about the map, which was never on this path and is unchanged.

My Grove now opens straight away. The Trees tab used to sit on a blank column for several seconds before your trees appeared, and both tabs got slower the more of the city the app knew about; they are now near-instant however large your grove is.
