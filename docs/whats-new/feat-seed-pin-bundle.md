# The seed pin, and holding the app's bundle at San Francisco + San Jose.
#
# ── WHY THIS LINE IS TESTER-VISIBLE AND NOT `internal:` ──────────────────────────────────────
#
# Most of this round is mechanism nobody can look at: a checked-in pin so a publish cannot turn a
# green commit red, and the guards that keep it honest. The half that IS visible is the app's own
# download. Without this change the next build bundles the published fused seed — 706 MB, all five
# New York boroughs inside the install — and the Cities screen then offers those same boroughs as
# downloads it refuses, because a bundled city is never offered. A tester would have waited for
# 600 MB and then found nothing to download.
#
# ── WHAT MAKES THE SENTENCE TRUE AT MERGE, checked rather than assumed ───────────────────────
#
#   * "carries San Francisco and San Jose" — `Fixtures/seed/pinned-seed.json` names the fused seed
#     built before New York, and `BundleContractTests.bundledSeedHoldsOnlyTheRuledScope` asserts
#     the built app's bundle holds exactly those two id spaces.
#   * "every other city downloads from the Cities screen" — all five borough packs are live in the
#     published format-2 manifest as this is written, at `s17-r2026-08-22-ac7b1ccc`. The claim was
#     not written against a plan; the packs were fetched and read.
#   * "stays a small install" — the pinned seed is 108,249,088 bytes, and it is what build 49
#     shipped too. This is a sentence about what does NOT change, which is the honest shape: no
#     tester is being promised a reduction.
#
# It sits beside `docs/whats-new/nyc-street-trees-live.md`, which is also unshipped and says the
# boroughs download one at a time. That line is TRUE ONLY WITH THIS CHANGE — had the 706 MB bundle
# shipped, every borough would have been inside the app and none of them downloadable. The two
# notes ride the same build deliberately.

Cypress carries San Francisco and San Jose inside the app. Every other city, New York's five boroughs included, downloads from the Cities screen, so the app itself stays a small install.
