# The Cities screen, answering six of the eight reports filed against it on 2026-08-23.
#
# ── WHAT MAKES EACH CLAUSE TRUE AT MERGE, checked rather than assumed ────────────────────────
#
#   * "grouped" — `On this phone` / `Available to download`, with the five boroughs under a
#     `New York City` heading. Rendered on a 402 pt iPhone 16 Pro and photographed, not inferred
#     from a unit test: the two headings and the built-in card's new `Includes San Francisco and
#     San Jose` line are visible on the running screen.
#   * "says which cities are already inside the app" — the built-in card names them, and San
#     Francisco and San Jose now lead with `Included in the app · record as of 2026-07-31` instead
#     of announcing only that something newer exists. Names are read from the shipped seed's own
#     `dim_city.display_name`, so the sentence cannot go stale against a future bundle.
#   * "can still be switched to when an update is waiting" — `Use` is drawn for the
#     `update available` state, which R43 §3's table omitted. This is the tester's own report
#     ("I can't seem to use manhattan even though it's on my phone"), and the three-button row was
#     photographed on the device rather than assumed to fit.
#   * "downloads faster" — `downloadCity` walked the response ONE BYTE AT A TIME through
#     `URLSession.AsyncBytes`. Measured on the assigned simulator over the committed 4 MB fixture:
#     0.280 s before, 0.0059 s after. The guard in the suite is a ratio against a per-byte control
#     run in the same test, not a wall-clock bound, because a bound loose enough to be stable sits
#     above both numbers and would certify the defect as fixed. (An earlier draft of this note
#     quoted a 6 MB run against a 4 MB fixture; the numbers above are the committed test's.)
#
# ── WHY THE PROGRESS RING IS NOT MENTIONED ───────────────────────────────────────────────────
#
# The determinate ring R43 §3 rules was dead in the first draft of this branch:
# `session.download(from:delegate:)` never delivers `didWriteData` — measured at 0 calls — so it
# sat at 0% for an entire 199 MB transfer. It reports honestly now. It is deliberately not a clause
# here: a reader who never saw the broken build has nothing to compare against, and announcing that
# a progress bar moves is noise. The same goes for `Cancel`, which used to draw
# "Download failed. Nothing was changed." over a download the reader themselves stopped.
#
# ── WHAT IS DELIBERATELY NOT CLAIMED ─────────────────────────────────────────────────────────
#
# The tester also reported that a download "fails if app closes or phone screen sleeps". That is a
# separate defect needing a background `URLSession`, which R43 §6 explicitly defers to its own
# ticket, and it is NOT fixed here — so this line does not say a word about downloads surviving a
# locked screen. Faster is true; resumable is not, and would be the more tempting sentence.
#
# Nor does it mention the spurious "Update available" that a re-publish used to show for identical
# data. That one IS fixed, and it is left out because a tester who reads this note has no way to
# see it: it is the absence of a prompt they were never supposed to get. Claiming it would be
# accurate and unverifiable from the outside, which is the wrong trade for a changelog.

The Cities screen is now grouped, says which cities are already inside the app, and lets you switch back to a downloaded city while an update is waiting. City downloads are also much faster.
