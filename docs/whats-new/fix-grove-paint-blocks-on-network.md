# Screen 08, both pills. Tester-visible rather than `internal:`, because the owner filed it as a
# complaint about the app and not about the code: "My Grove is very slow to load, Species worst."
#
# ── WHAT MAKES EACH CLAUSE TRUE, AND WHAT IT DELIBERATELY DOES NOT CLAIM ───────────────────
#
#   * "opens straight away, whatever the signal" — the two reads no longer await the service
#     before drawing anything. They were `local` (≈6 ms and ≈26 ms after PR #131) followed by a
#     round trip to `cypress-sync.fly.dev` with no `timeoutIntervalForRequest` configured
#     anywhere, so an unreachable host cost `URLSession`'s 60-second default before a single row
#     appeared. The paint now reaches no wire at all, which is asserted as a census of requests
#     made rather than as a stopwatch reading — `GroveLocalFirstTests`, and its header says why
#     there is not a number in the file.
#
#     **"Whatever the signal" is the honest half of that sentence and the reason it is in the
#     line.** The old failure was not slowness in the ordinary sense — on a good connection it was
#     a beat, and on a captive portal or in a park it was a minute of blank tab. A tester who reads
#     "faster" will look for a stopwatch difference; what they should look for is the tab behaving
#     the same way on airplane mode as on wi-fi.
#
#   * "keeps what it was showing when you come back to it" — the model is owned by the composition
#     root now instead of by the tab's own view, which `RootView` destroys on every switch. Before,
#     every return to My Grove was a cold read; now the last data is on screen at once and the
#     refresh runs behind it.
#
#   * "anything you added on another device turns up a moment later" — this is the part that got
#     *slower*, and saying so is the point of the clause. The account's half used to be in the
#     first frame or not at all; it now arrives after it. A tester who signs in on two phones will
#     see the second phone's species land a beat after the grid draws, and that is correct
#     behavior rather than a glitch to file.
#
# Nothing about what the screen draws changed: same ring, same grid, same rows, same copy. No
# loading state was added — there is nothing to show for 6 ms, and a spinner that flashes for two
# frames would be copy in no mock (DECISIONS constraint 21), which is the same argument PR #131's
# note settled for the Trees column.
#
# ── ON LENGTH ──────────────────────────────────────────────────────────────────────────────
#
# 189 characters, against `plan`'s limit of 200, shared with every other open branch inside
# TestFlight's 4000-character budget.

My Grove opens straight away now, whatever the signal, and keeps what it was showing when you come back to it. Anything you added on another device turns up a moment after the screen draws.
