# New York City street trees, and the disclaimer the City's terms require beside them.
#
# ── THE NYC-AVAILABILITY LINE IS DELIBERATELY NOT TESTER-VISIBLE YET ─────────────────────────
#
# This round is phase 1: the code that makes the five borough packs buildable, and the
# disclaimer that must be on screen before a byte of NYC data leaves the bucket (D12, R78
# ruling 2). It publishes NOTHING. The packs reach readers in phase 2, a bucket upload with no
# code in it.
#
# `.github/workflows/testflight.yml` mints a build on every non-prose push to `main`, so the
# merge that lands this mints the build that carries these lines. A tester-voice sentence saying
# New York had arrived would therefore reach testers BEFORE the packs existed, and the Cities
# screen would still show two California cities -- exactly the overclaim
# `docs/whats-new/README.md` forbids. The first line is `internal:` for that reason and no
# other; it is not a judgement that the work is uninteresting.
#
# **The tester-voice line is re-added by a prose-only pull request after the phase-2 publish.**
# DONE, 2026-08-22: it lives in `docs/whats-new/nyc-street-trees-live.md`, as a new note rather
# than an edit here -- this file is the record of what build 49 told testers and should keep
# saying what it said.
# That is the README's own mechanism rather than a workaround: a note added by a prose merge
# mints no build and waits here until the next build that actually ships, so the sentence lands
# with a release whose readers can go and see it. The draft, kept here so the follow-up round
# does not have to reinvent it:
#
#     New York City's street trees are here. The five boroughs download one at a time, so you
#     take Brooklyn without taking the other four.
#
# The SECOND line below stays tester-visible and has no such precondition -- the disclaimer is
# on the screen the moment this merges, whether or not any NYC pack exists.
#
# Reviewer finding F1, adjudicated by the orchestrator 2026-08-22.

internal: makes the five NYC borough packs buildable and puts the City's required disclaimer on the Cities screen; the packs are not published yet, so nothing about New York is visible.
The Cities screen now carries New York City's data disclaimer, as the City's terms of use require wherever its data is offered.
