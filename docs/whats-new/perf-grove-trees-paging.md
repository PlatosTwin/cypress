# My Grove · Trees. Tester-visible, because the blank column is what a tester sees and the pain
# scales with how much they have used the app — the people most likely to file it are the ones
# with the biggest groves.
#
# ── WHAT MAKES EACH CLAUSE TRUE, MEASURED RATHER THAN ASSUMED ───────────────────────────────
#
# One device, one seeded grove, both revisions: iPhone 16 Pro
# (EA0AD796-3052-4EE5-A7A8-A1DE807A3653), **1,027 grove trees** written as device-owned
# contribution rows against real seed trees (880 visited, 147 favorite-only, so the
# never-visited tail is represented; `PRAGMA user_version` read 19 before and after — no
# migration). Both builds were installed over the same data container, and the row count was
# re-read after each install to prove the grove survived it.
#
# The instrument is a timestamped screenshot burst, sampling every 250–380 ms, with each frame
# classified by ink against the page background rather than by eye. The tap's own moment is not
# known exactly — it lands inside one sampling gap — so every figure below is a **bound**, not a
# point. That is also why the code comments say 3.3–3.7 s and not a single figure.
#
#   * "opens straight away" — AFTER: the last frame showing the Species grid is at 12797 ms and
#     the first frame showing tree rows is at 13031 ms, one sampling interval later. **No blank
#     frame was captured at all**, and the frame that shows the rows still has the Trees pill
#     mid-animation — the first page was on the glass before the pill finished selecting. The
#     honest statement of the bound is "under one 234 ms sample", not a smaller number invented
#     to sound better.
#
#     BEFORE, same device and same grove, built from the merge base (e574a0a): the blank column
#     runs from the tap (bracketed between 8959 ms and 9395 ms) to the first painted frame at
#     12694 ms — **3.30 to 3.74 s** of a screen with a selected pill above it and nothing under
#     it. Photographed; the frames are the evidence, not a stopwatch.
#
#   * "the first 50" — `GroveLimits.pageSize`. Seen on the running screen: page one ends with
#     "There are more trees than these." and a `Show more` control.
#
#   * "Show more" — pressed on the running screen. Page two appended in place, below the rows
#     already there, with the scroll position kept.
#
#   * "keeps its place when you switch tabs" — flipped to Journal and back. The Trees pill was
#     still selected, the column drew immediately with no blank, and scrolling to the bottom
#     reached the **same last row** ("Swamp Myrtle") with the same `Show more` block as before
#     the flip — the two-page bottom, not the one-page bottom. The model-level guarantee is
#     `GroveTreesPagingTests`' "a revisit keeps the pages that were revealed".
#
# ── WHAT IS DELIBERATELY NOT CLAIMED ────────────────────────────────────────────────────────
#
# **No loading spinner is mentioned.** There is one now, and every phase draws something, but on
# this device at this grove it was never captured on screen — the page arrives faster than the
# burst samples. Announcing a spinner would send a tester looking for something they will not
# see. It is guarded by `GroveDrawnLoadingShot`, which photographs the column and carries its own
# calibration case, not by this line.
#
# **No number is given to a tester.** "Straight away" is what they can feel; 3.3–3.7 s is a
# figure about the old build, and the note is about the new one.
#
# Nothing here claims the database got faster. It did not — the five statements already totalled
# about 38 ms at this size. The cost was building a thousand rows for a screen that shows eight.
#
# ── LENGTH ──────────────────────────────────────────────────────────────────────────────────
# The line below is 163 characters, under the 200 the checker enforces.

My Grove's Trees tab now opens straight away however many trees you have. It shows your 50 most recent, with a Show more button for the rest, and keeps your place.
