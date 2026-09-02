# The v19 index round. Two tester-visible clauses, and the reason there are two rather than one.
#
# ── THE FIRST CLAUSE IS A CORRECTNESS FIX, NOT A SPEED CLAIM ─────────────────────────────────
#
# `Show earlier` could skip entries. The list was ordered by capture time and the cursor was the
# last row's capture time, so when a run of entries recorded in the same millisecond straddled a
# page boundary, everything after the boundary in that run was never shown — not on the next
# page, not on any page. Measured on this round's branch point: 40 entries written, 40 returned
# by one unpaginated read, 32 across four pages. The CSV export follows the same cursor and came
# back 232 of 240. Repro and fix in `docs/errata-pending/journal-tie-pagination.md`.
#
# A tester with a handful of entries recorded a few seconds apart will not have hit it. A tester
# who has ever saved a check-in and a measurement together, or tapped through several trees on
# one walk, may well have. It is worth a line because a missing entry is invisible: there is
# nothing on screen that says a row was skipped, so nobody could have reported it as anything
# but "I thought I recorded that".
#
# ── THE SECOND CLAUSE IS THE SPEED, AND IT IS ONLY CLAIMED WHERE IT WAS MEASURED ─────────────
#
# Timed with EXPLAIN QUERY PLAN and repeated in-process reads against a scratch database
# carrying this schema's real DDL, 16,000 contributions, 90 % of them the caller's:
#
#     read                          before (ms)   after (ms)
#     journal page 1                    6.66         0.17
#     journal page 6                    7.10         0.18
#     a tree's visits, by tree          0.299        0.009
#     the hero photo candidates         1.144        0.460
#     the hero photo vote tallies       2.313        0.285
#
# The page-six row is the one that matters and it is the reason the sentence below says "however
# far back": the old plan sorted the contributor's whole history on every page, so paging got
# worse the further you went. It does not now.
#
# Two things are deliberately NOT claimed. Neither number above is a frame, and nothing here has
# measured a dropped frame before or after — these are database reads on a background queue, and
# the same reasoning as `fix-journal-yours-n-plus-one.md`'s applies. And on a small history none
# of it is perceptible: a first-week tester with 40 entries had a fast journal already. What a
# tester with a long history can feel is the tree profile, which is the second half of the round
# — the five per-tree indexes had been unusable since v1, so opening a tree you have visited
# often walked its whole index and then sorted.
#
# ── ON LENGTH ────────────────────────────────────────────────────────────────────────────────
# Two lines, each inside the 200 the check allows.

Journal > Yours no longer skips entries when you tap Show earlier, and neither does the CSV export — entries recorded in the same instant used to be dropped if they fell across a page boundary.
Journal pages and tree profiles open faster on a long history, and Show earlier now costs the same however far back you go.
