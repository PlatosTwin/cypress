### EXXX — #239's six 2026-08-04 UI flakes: three real, all already fixed; two claimed, unfound

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `test/239-ui-flake-class`. Latest numbered at time of writing: E240, R65.*

---

#### The ticket's own premises, checked against the evidence, and two of them wrong

#239 named PRs #29 and #30 as the source of the flakes. Both exist and both merged — on
2026-08-05, not 2026-08-04 (`gh pr view 29/30`, `createdAt: 2026-08-05T…`). Neither is a UI-suite
ticket; #29 is `feat/e233-civic-short-names`, #30 is `fix/e235-e48-copy-and-r53-scrollable`, and
every `TestFlight` run on either branch (six total) is `success`. **The PR numbers in the brief do
not match its own date.** The three PRs that actually ran, and failed, `TestFlight` on
2026-08-04 are #13 (`test/e229-symlinked-worktree-path-bucketing`), #14
(`test/voiceover-reading-order`), #15 (`fix/e217-deep-link-override-leak`).

Every `TestFlight` run with `conclusion: failure` between 2026-08-04T00:00Z and 2026-08-05T00:00Z
was pulled by `gh run list`, and every `ui-log-N`/`unit-log` artifact from those runs was
downloaded (`gh run download`) and read — not grepped for the ticket's own claims and stopped
there. Across all of it:

- **No `DeepLinkSweepTests` failure anywhere.** Both its methods (`testEveryPushedScreenSaysWhereItIsFirst`,
  `testNothingIsAnnouncedTwice`) `passed` on every run that included them (30959481241,
  30958494676, 30884912660, 30957393532). No occurrence, let alone the claimed two, and no
  `{{inf, inf}}` or any non-finite frame appears in any of the ~35,000 combined log lines searched.
- **No `MapFilterAccessibilityTests` failure anywhere.** Every one of its eleven methods `passed`
  on every run that included them (30959481241, 30958494676, 30873340010, 30871836674,
  30872810322, 30868888144).
- **No `ReadingOrderAccessibilityTests` failure, and no sign-in banner mentioned in any log at
  all.** Its three methods `passed` on both runs that included them (30959481241, 30957393532).

The brief's occurrences 1, 3 and 4 (the DeepLinkSweep inf-frame, the reading-order/sign-in-banner
failure, the MapFilterAccessibility tap-miss) are **not substantiated by any CI evidence this
investigation could retrieve.** Refuting them is the point of this section, per CLAUDE.md's own
instruction that a brief's premises may be wrong.

#### What the evidence actually shows: four real failures, already fixed on `main`

The seven runs above carried nine genuine UI-suite failures across four distinct methods — all in
the "synthetic input / settle under load" family the brief described, just not the members it
named:

| # | Test | Run(s) | Failure text |
|---|------|--------|--------------|
| 1 | `MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` | 30884912660 (06:44 UTC, push to main), 30958494676 (23:19, PR #15), 30959481241 (00:05, PR #14) | "panning the map did not move the camera off the reader…" — matches the brief's occurrence 2 |
| 2 | `AccessibilityTreeTests.testTheFourTabsAreReachable` | 30871836674 (02:31), 30872810322 (02:54) | "the Map tab is present but cannot be activated by an assistive technology" |
| 3 | `SheetExitUITests.testShareSheetDragDownDismisses` | 30868888144 (01:35), 30872810322 (02:54) | "the gesture was never read as a drag. Look at dragDown, not at the map (#200)." — that literal is 30872810322's; 30868888144 predates #200's message rewrite and fails the same way under the older text |
| 4 | `SheetExitUITests.testCareLogDragDownDismisses` | 30872810322 (02:54), 30873340010 (03:05) | same #200 signature |

**All nine occurrences are already fixed on `main`, by work that landed before this ticket was
opened.** `git log` on the affected files shows the chain: `4147118` ("Wait for reachable, not
just present") added `assertReachable`/`settledFrame`; `43f598c`/`62c83f2` (#200/#209) added
`deliberateDrag`, the suite's one drag spelling, gated by `DragGestureGateTests`; `c1501af` (#230)
added `panUntilMoved`'s drag-precondition retry. The doc comments on all three already cite the
exact run IDs this investigation independently found — `MapPanTabSwitchUITests.swift`,
`SheetExitUITests.swift` and `UIWait.swift` name 30871836674, 30873340010, 30868888144 and
30884912660 by number. **Per the brief's own instruction to check whether #230 pre- or post-dates
an occurrence before concluding it's insufficient: all three `MapPanTabSwitch` failures found here
pre-date #230's merge (PR #23, 2026-08-05T09:27:25Z) — 06:44 and 23:19/00:05 the day before. They
are the failures #230 was written to fix, not evidence it didn't work.**

**Amended hours after this entry merged: #230's retry reduces the class, it does not eliminate
it.** Run 31067670540 — main at `cc9eefd`, the merge of this very ticket — failed
`testADeliberatePanSurvivesLeavingForJournalAndBack` at the same precondition, post-fix, on a
loaded runner (`ui (4)`, 2026-08-06T03:17 UTC), with the retry present in the tree that failed.
The identical tree had passed all four shards on the PR run some twenty minutes earlier, so the
occurrence is intermittent, but it is the first one #230 cannot explain away. The pan precondition is the one
member of this family still standing; the next occurrence should reopen it as its own ticket
rather than another rerun.

#### What this round adds, given the above

With the four real, evidenced failure modes already hardened, the remaining work was auditing the
rest of `CypressUITests` for the one property CLAUDE.md's own postmortem calls out as the shared
root cause — synthesized input or a reading-order comparison built on a frame read before it
settled — using the **existing** idiom (`assertReachable`/`settledFrame`/`deliberateDrag`) rather
than a parallel one. Two gaps found, both call sites doing exactly that:

1. **`UIWait.swift`: `settledFrame` decided "stopped moving" with plain `CGRect.equalTo`.**
   `equalTo` treats `.infinity == .infinity` as `true`, so a frame XCUITest could not resolve a
   real position for — read mid-transition as `{{inf, inf}, {inf, inf}}` rather than raised as an
   error — would satisfy the settle check on its first two samples and be handed to a caller as a
   real coordinate. Split into `isFiniteFrame` + `frameHasSettled`, both free functions so they are
   testable with no live element and no simulator. Red-proofed: `FrameFinitenessGateTests` broke
   the finiteness half, watched `testTwoEqualInfiniteFramesHaveNotSettled` fail with exactly that
   message, restored it. This closes the general shape of the brief's occurrence 1 even though the
   specific incident could not be found in any available log.
2. **`DeepLinkSweepTests.testNothingIsAnnouncedTwice`** compared `outer.frame`/`inner.frame`
   directly — the one containment/reading-order check in the suite with no settle-or-finite wait
   at all, across up to six app launches per run. Now reads each element's frame once through
   `settledFrame` (cached per element, not re-read per pair compared).
3. **`MapFilterAccessibilityTests.revealedChip`** returned a chip the instant `isHittable` went
   true, which a chip still mid-momentum-scroll can satisfy on a frame it is about to leave before
   a caller's `.tap()` actually synthesizes. Now also waits for a settled frame — only when the
   loop already found the chip hittable, so a chip that never became hittable is returned exactly
   as before, and every caller's own (more specific) failure message for that case is unchanged.

`Tools/ui-test-shards.txt` gained one class, `FrameFinitenessGateTests`, on the shortest line by
count (no per-class timing to place it by — it launches no `XCUIApplication` and cost ~0s in the
full-suite runs below).

#### What this round deliberately does not touch

No app code. No weakened assertion — every `XCTFail`/`XCTAssert` call site asserts the same fact
it did before; what changed is when a frame is trusted enough to build a coordinate from. The
already-landed `assertReachable`/`deliberateDrag`/`panUntilMoved` hardening for the four evidenced
failures is left as-is — it already works, per the two full-suite runs below.

#### Verification

Full `CypressUITests` suite, iPhone 16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`, both via
`Tools/run_tests.sh` + `Tools/verify_test_log.sh`, head `5fa3c61` (`test/239-ui-flake-class`):

- Run 1: `CYPRESS-RUN: started 2026-08-05 18:04:53 PDT` — `VERIFY-OK: Executed 92 tests, with 0
  failures (0 unexpected) in 1521.028 seconds`, `XCTest skipped=0`, `** TEST SUCCEEDED **`.
- Run 2: `CYPRESS-RUN: started 2026-08-05 18:31:08 PDT` — `VERIFY-OK: Executed 92 tests, with 0
  failures (0 unexpected) in 1668.923 seconds`, `XCTest skipped=0`, `** TEST SUCCEEDED **`.

Zero-warning line certified on a fresh `DerivedData` build (`Tools/verify_test_log.sh --warnings`,
`437` compile tasks, all four changed files named and confirmed compiled): `VERIFY-WARNINGS-OK: 0
source warnings`.
