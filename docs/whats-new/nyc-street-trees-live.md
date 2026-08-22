# The tester-voice line for New York, re-added after the phase-2 publish.
#
# `docs/whats-new/feat-nyc-publish.md` carried this sentence, drafted, and shipped an
# `internal:` line in its place — because the merge that landed the phase-1 code minted the
# build, and at that moment no NYC pack existed in the bucket. Telling testers New York had
# arrived would have been the overclaim `docs/whats-new/README.md` forbids (reviewer finding
# F1, adjudicated 2026-08-22).
#
# **A NEW FILE rather than an edit to that note**, deliberately. The README's rename-and-reword
# hazard runs the other way — a note that has already shipped cannot be un-shipped by editing
# it — but the relevant rule here is simpler: `feat-nyc-publish.md` is the record of what build
# 49 told testers, and it should keep saying what it said. This file is a new statement made at
# the moment it became true, which is what a note is.
#
# It rides into the next build that actually ships. This pull request is prose-only, so it
# mints no build of its own and the line waits here until one is minted — the README's
# "Prose-only pull requests" mechanism, used as intended rather than worked around.
#
# MERGE ORDER MATTERS AND IS THE ONE THING TO CHECK: this line is true only once the five
# borough packs are actually being served from the bucket. If the phase-2 publish has not
# completed and been verified, this file is the same defect F1 caught, one round later.

New York City's street trees are here. The five boroughs download one at a time, so you take Brooklyn without taking the other four.
