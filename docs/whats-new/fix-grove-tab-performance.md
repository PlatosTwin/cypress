# Screen 08, both tabs. This is a tester-visible line rather than an `internal:` one because the
# pain is what testers actually filed.
#
# ── WHAT MAKES EACH CLAUSE TRUE AT MERGE, measured rather than assumed ──────────────────────
#
#   * "opens straight away" — measured on the assigned simulator (iPhone 16 Pro Max), the same
#     instrument at both revisions, calibrated against a known 50 ms sleep and a no-op before
#     either reading, on a 40-tree grove over the shipped seed.
#
#     The Trees tab's read went from **13.2 / 16.3 / 21.7 s** — three calibrated readings by two
#     agents on one shared machine, where the spread is load rather than disagreement — to
#     **25.9 / 26.8 ms**. The stable claim is the shape, not any single figure: the old cost was
#     linear in the size of the grove at roughly a third to half a second per tree, and the new one
#     is not. The Species tab went 282 ms → 6.0 ms (381.7 → 5.6 ms on the second agent's run).
#
#     Both answers are identical across the change, and it is worth saying which grove each row is
#     about, because two fixtures were used and their numbers were conflated in an earlier draft of
#     this note. The timing fixture's forty trees all stand in **Outer Richmond**: 40 entries, 14
#     species known, 189 in the area. The screenshot fixture's stand in **Castro/Upper Market**,
#     which the screen renders as "15 of 186". Both are right for their own grove; neither is a
#     correction of the other.
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
#
# ── ON LENGTH ──────────────────────────────────────────────────────────────────────────────
#
# The first draft of the line below was 246 characters and `plan` refused it: the limit is 200,
# and it is shared with every other open branch inside TestFlight's 4000-character budget. What
# went was the clause about the cost scaling with the size of the city — true, measured, and a
# sentence about the app's internals rather than about the tester's morning.

My Grove now opens straight away. Its Trees tab used to sit on a blank column for several seconds before your trees appeared, however large or small your grove was.
