# The Journal tab's `Yours` segment. One tester-visible clause, and the reason it is only one.
#
# ── WHAT WAS SEEN, on the running screen rather than inferred ────────────────────────────────
#
# iPhone 16 Pro Max (DE8E11AE), the app built from this branch, 60 visits and a check-in on the
# device against real bundled-seed trees. Photographed at each step:
#
#   1. Journal > Yours paints the list, names resolved from the seed — Swamp Myrtle, Victorian
#      Box, Blackwood Acacia, Indian Laurel Fig Tree 'Green Gem' — grouped under AUG 31, 30, 29.
#   2. Scrolled to the end of page one: "There are earlier entries than these." and `Show
#      earlier`. Tapped it; AUG 24 appears below AUG 25, so page two appended.
#   3. Tapped `Neighborhood`, then `Yours` again. The list still holds page two — scrolling
#      reaches AUG 20, 19 and 18, rows that exist only because `Show earlier` fetched them.
#   4. (Review round 2.) Repeated with a contribution written into the device's database while
#      the app sat on `Neighborhood`: coming back to `Yours` draws `Visited Dawn Redwood` at the
#      top of SEP 1, above everything that was already there, and scrolling still runs past
#      AUG 26 — page one's old end — into AUG 25 with no `Show earlier` in between. Both halves
#      of the ruling, in one pass.
#
# Steps 3 and 4 are the two clauses of the line below. Before this change the model was `@State`
# on a view inside the segment `switch`, so step 3 destroyed it: the reader came back to page one
# with a `Show earlier` button again, and whatever they had loaded was gone. Step 4's refresh did
# not exist at all in the first draft of this branch, which PR #143's review is what caught.
#
# ── WHY NO SPEED CLAIM, WHICH IS THE PART A DRAFT OF THIS FILE GOT WRONG ─────────────────────
#
# The round was commissioned as a performance fix — the N+1 display-name read PR #131 removed
# from `grove()` was still in `journal()` — and it was, and it is gone. But it was NOT costing
# seconds, and the measurement is what settled that. Timed in one process on one fixture at one
# moment (25-row page, 120 photographs, three readings each, calibrated against a no-op at
# 0.001 ms and a known 50 ms sleep measured at 52.5 ms), at three history sizes:
#
#     history      before (ms)            after (ms)
#     40 rows      21.5 / 21.0 / 20.9     17.1 / 16.9 / 16.5
#     400 rows     21.6 / 21.8 / 23.1     17.3 / 17.4 / 16.3
#     4000 rows    22.1 / 22.4 / 21.9     17.8 / 18.8 / 17.8
#
# About four milliseconds, flat in the size of the history. Grove's thirteen seconds lived in
# `TreeQueries.treeSQL()` itself — a materialized view and a whole-inventory scan per row — and
# PR #131 fixed that statement for every caller, `journal()` included. What was left here was
# the round-trips, and they are worth four milliseconds, not four seconds. Announcing a speed-up
# a tester cannot feel would send them looking for a difference that is not there.
#
# The one measured cost that is on the main thread is the day headers: 25 of them took 1.8 ms
# per derivation with a formatter built per group and 0.06 ms with the cache, and the derivation
# itself ran on every SwiftUI body pass and now runs once per read. That is a real 30x, on the
# thread that draws — but nothing here has measured a dropped frame before or after, so it is
# not claimed either.
#
# ── ON LENGTH ────────────────────────────────────────────────────────────────────────────────
# Inside the 200 the check allows and the 4000 shared with every other branch.

The Journal tab's Yours list now keeps what you loaded when you switch to Neighborhood or City and back, and picks up anything you recorded meanwhile instead of starting over.
