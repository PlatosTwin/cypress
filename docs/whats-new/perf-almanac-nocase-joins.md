# Screen 12's `First bloom` read. An `internal:` line, and the measurement is what settled that.
#
# ── WHAT WAS MEASURED, rather than assumed ──────────────────────────────────────────────────
#
# iPhone 16e (3A1F212D), the shipped seed, three readings of each statement through an instrument
# calibrated in the same process against a no-op at 0.0006 ms and a known 50 ms sleep at 53.9 ms:
#
#     arm                          before (ms)              after (ms)
#     polygon (Outer Richmond)     4.53 / 3.06 / 3.67       0.02 / 0.02 / 0.01
#     radius (1,200 m)             31.5 / 33.7 / 22.9       0.26 / 0.13 / 0.12
#
# Same numbers with forty visits on the device, so the saving is not a fact about an empty
# database. Both plans are in `AlmanacQueries.bloomTreeJoin` and both are gated by
# `AlmanacQueryPlanTests`.
#
# ── WHY NO TESTER-VISIBLE LINE ──────────────────────────────────────────────────────────────
#
# Thirty milliseconds off one of nine reads behind a screen that already opened is not something a
# tester can feel, and this repository's rule about unverified claims applies to a changelog. The
# honest version of the tester-visible sentence would be "screen 12 opens exactly as fast as it
# did", so there is no tester-visible sentence.
#
# What would have been worth announcing is the shape rather than the figure — the old radius plan
# built a transient index over the **whole merged inventory** on every open, so its cost tracked
# the size of every city installed rather than the size of the reader's own record, and New York
# is 898,643 rows. That is a sentence about the app's internals, and it belongs here rather than
# in TestFlight.
#
# ── WHAT IS DELIBERATELY NOT CLAIMED ────────────────────────────────────────────────────────
#
# ROADMAP asked for both of this file's collated joins to be fixed. Only one was. The other, in
# `youngTreesWithoutVisits`, would have to normalize the **seed** side up to seek an index in
# `main`, which is correct only while every `visits` row spells its uuid in upper case — and
# nothing asserts that. It is left as it is, its plan is pinned, and the reasoning is in the
# statement's own doc comment and in the pull request.

internal: screen 12's first-bloom read stops building a transient index over the whole inventory on every open; identical rows, and no tester-visible change.
