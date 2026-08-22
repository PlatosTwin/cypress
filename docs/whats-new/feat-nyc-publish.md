# New York City street trees, and the disclaimer the City's terms require beside them.
#
# ── REVIEWER / ORCHESTRATOR: THE FIRST LINE IS TRUE ONLY AFTER PHASE 2 RUNS ──────────────────
#
# This round is phase 1: the code that makes the packs buildable and the disclaimer that must be
# on screen before a byte of NYC data leaves the bucket (D12, R78 ruling 2). It publishes
# NOTHING. The five borough packs reach readers in phase 2, which is a bucket upload with no
# code in it.
#
# `.github/workflows/testflight.yml` mints a build on every non-prose push to `main`, so merging
# THIS pull request mints the build that carries the line below. If phase 2 has not run by then,
# that build tells testers New York has arrived while the Cities screen still shows two
# California cities — which is exactly the overclaim `docs/whats-new/README.md` forbids.
#
# The repository already has both remedies and this note does not get to choose between them:
#
#   * delete this file before the merge, and let a prose-only pull request re-add it after the
#     publish — a note added by a prose merge waits here until the next build that actually
#     ships (README, "Prose-only pull requests"), so nothing is lost and nothing is early; or
#   * accept the window, if phase 2 runs within it.
#
# Recommended: the first. It costs one small pull request and it is the only one of the two that
# cannot tell a tester something false. Raised as open question 1 on the pull request.
#
# The SECOND line has no such precondition — the disclaimer is on the screen the moment this
# merges, and it is on it whether or not any NYC pack exists.

New York City's street trees are here. The five boroughs download one at a time, so you take Brooklyn without taking the other four.
The Cities screen now carries New York City's data disclaimer, as the City's terms of use require wherever its data is offered.
