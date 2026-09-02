# The v19 index round. Two tester-visible clauses, and the reason there are two rather than one.
#
# ── WHAT WAS SEEN, on the running screen rather than inferred ────────────────────────────────
#
# iPhone 16 Pro Max (DE8E11AE), a FRESH install of this branch's build — fresh because an
# earlier build on this branch had already carried that database to user_version 19 with only
# half of v19's DDL, so the migration would not have re-run. (An artifact of splitting the round
# into two commits; v19 ships as one step.) 60 visits written into the app's own database
# against real bundled-seed trees, twelve of them sharing one capture time at rows 20…31, so the
# run straddles the 25-row page boundary. Journal > Yours, paged by hand:
#
#   1. Page one paints, names resolved from the seed — Monterey Pine, Yew Pine, Evergreen Pear,
#      Italian Buckthorn, Sweet Bay, Cherry Plum, Small-leaf Tristania 'Elegant', Crape Myrtle —
#      grouped under SEP 1 and AUG 31, `walk 0` … `walk 19` in order.
#   2. Inside the tie the notes stop being consecutive — 28, 22, 29, 23, 24 — which is the total
#      order doing its job: within one capture time the rows sort by id, and the note numbers are
#      just the order they were written in. Page one ends at `walk 24`, four rows into the tie,
#      with "There are earlier entries than these." and `Show earlier`.
#   3. Tapped it. Page two begins `walk 27` — still inside the tie — and runs on through 32, 33,
#      … 49 with no gap. Page two *continuing inside the run* is the fix, visible: a cursor that
#      carried only the timestamp could not express that position and had to skip to the next
#      distinct one. What the old build does at this exact step was measured in the unit suite
#      rather than photographed — 8 rows dropped of 40 — and is not claimed as an observation.
#   4. Tapped `Show earlier` again. The list ends at `walk 59` and the button is gone. All sixty
#      rows, across three pages, none dropped and none repeated.
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
# ── A THIRD BENEFICIARY, MEASURED BUT NOT CLAIMED HERE ───────────────────────────────────────
#
# `AlmanacQueries.youngTreesWithoutVisits` runs a correlated `NOT EXISTS` against `visits` once
# per candidate tree, spelled `v.tree_uuid = t.uuid COLLATE NOCASE` — so it is the same dead
# index this round revives, reached from a screen this round did not set out to touch. On the
# scratch fixture the probe goes `SCAN v` at 0.319 ms to
# `SEARCH v USING INDEX idx_visits_tree (tree_uuid=? AND captured_at>?)` at 0.008 — both columns
# of the recollated index used, and 41x per tree, which is 64 ms against 1.5 for a 200-tree card.
#
# It is NOT in the lines below, on this round's own rule: nothing here has opened that card on a
# device before and after. The almanac PR (#145) merges ahead of this one and its plan gate pins
# that scan deliberately; the gate has to be re-derived on the merged tree, where the seek is
# available. Recorded so the person doing that has the measurement rather than a surprise.
#
# ── ON LENGTH ────────────────────────────────────────────────────────────────────────────────
# Two lines, each inside the 200 the check allows.

Journal > Yours no longer skips entries when you tap Show earlier, and neither does the CSV export — entries recorded in the same instant used to be dropped if they fell across a page boundary.
Journal pages and tree profiles open faster on a long history, and Show earlier now costs the same however far back you go.
