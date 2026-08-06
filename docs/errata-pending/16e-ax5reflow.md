### EXXX — `AX5ReflowTests`'s height guards measured the simulator's safe-area inset, not the view (task #30)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `fix/30-16e-ax5reflow`. Latest numbered at time of writing: E240, R65.*

---

#### The symptom, and which of the ticket's two hypotheses held

Task #30 reported that the iPhone 16e (`3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`) fails
`CypressTests/AX5ReflowTests` deterministically on unmodified main, before and after a
`simctl erase`, and offered two hypotheses: (a) the tests are device-geometry-sensitive, or (b) the
device image is bad.

**(a) held, and (b) is refuted.** The image is fine — the same device runs the same suite green
with the fix, and every other test in the suite passed on it throughout. But the geometry the tests
were sensitive to is *not* the screen width the ticket guessed at. It is the device's **top
safe-area inset**, arriving through the measuring harness.

Reproduction, unmodified `origin/main` at `7da18bc`, `-only-testing:CypressTests/AX5ReflowTests`:

| run | device | `screen-width-pt` | verdict |
|---|---|---|---|
| `ax5-16e-repro.log` | iPhone 16e | 390 | `✘ Test run with 9 tests in 1 suite failed … with 2 issues` |
| `ax5-16pro-control.log` | iPhone 16 Pro | 402 | `✔ Test run with 9 tests in 1 suite passed` |

Both `CYPRESS-RUN: worktree /Users/nikitabogdanov/PycharmProjects/cypress-wt-16e`,
`CYPRESS-RUN: head 7da18bc`, two minutes apart, `camera-auto-healed no`. The two issues, in full:

```
Expectation failed: (recenter.height → 91.0) == (MapLayout.locateButtonHeightAX5 → 98.0)
Expectation failed: (fab.height → 130.0)     == (MapLayout.fabHeightAX5        → 137.0)
```

Both short by **exactly 7 pt** — an additive term, identical on two controls with nothing in
common, which is not what a width sensitivity looks like.

#### The mechanism, measured rather than reasoned

A throwaway probe suite, run on each device in turn against the same tree, printed the geometry
`AX5ReflowTests.ax5Size` works in. The two runs differ in exactly one number:

| probe | iPhone 16e | iPhone 16 Pro |
|---|---|---|
| `host.view.safeAreaInsets` | `top: 47` | `top: 54` |
| bare `MapRecenterButton` at AX5 (never mounted in a window) | `44.0` | `44.0` |
| bare `IdentifyFAB` at AX5 | `83.0` | `83.0` |
| windowed `MapRecenterButton` (what `ax5Size` returned) | `91.0` | `98.0` |
| windowed `IdentifyFAB` | `130.0` | `137.0` |
| `window.frame`, `window.safeAreaInsets`, `window.windowScene` | `(-2000,0,393,852)`, all-zero, `nil` | identical |

`ax5Size` mounts its content in a real `UIWindow` and asks
`UIHostingController.sizeThatFits(in:)` for the result. **A hosted root view inherits the running
device's safe-area insets even though this window is parked at `x = -2000`, is sized 393×852 rather
than to the screen, and has no `windowScene` at all** — the window's own `safeAreaInsets` are zero
while `host.view.safeAreaInsets.top` is 47 or 54 — and `sizeThatFits` adds them to the height it
reports. 44 + 47 = 91; 44 + 54 = 98. 83 + 47 = 130; 83 + 54 = 137. Every height `ax5Size` ever
returned carried a term naming the simulator rather than the view.

The left and right insets are 0 on both devices, so the width guards in the same file — E196 §1
and §3's, the reason the helper exists — were never affected and are unchanged by the fix. The
defect reached main inside the only two assertions that read a height, and they were `==` against
numbers recorded on a 16 Pro.

#### What this says about the two shipped constants

`MapLayout.locateButtonHeightAX5 = 98` and `.fabHeightAX5 = 137` were recorded through this
harness, so each is its control's real AX5 footprint **plus 54 pt of 16 Pro safe area**. The
comment on the first one claimed the 98 was iOS growing the control's minimum hit target across the
accessibility range. That is not what it was, and it is not a thing this control does:
`MapRecenterButton` is a fixed `CypressSpacing.minTapTarget` square and measures 44 pt at
`.accessibility5` on both devices — the exact claim the fix now asserts in place of the old
equality. The FAB's label does scale, and it measures 83 pt.

**The shipped numbers are deliberately left alone.** Everything downstream of them is a *reserve*
(`bottomSlotReservedAboveAX5`, then `noticeMaxHeight`, which documents itself as conservative
rather than exact). Over-reserving costs `MapLocationNotice` about 108 pt of scroll budget it does
not use; under-reserving is E183 §2 — the card laid out from its bottom edge growing off the top of
the screen. Correcting them downward would change what ships at AX5 under an owner ruling (R53 §6)
and is a decision for the owner, not for a ticket about a red simulator. It is flagged here so the
next person to touch that budget knows the 108 pt is available and why nobody took it.

#### The fix

`ax5Size` subtracts the insets it measured from the size it returns, which makes it
device-independent; the two guards become `<=` against the reservations (under-reserving is the
only direction that is a defect), and the exact half is kept exact and device-independently as
`recenter.height == CypressSpacing.minTapTarget`. `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5`
is the other caller of `ax5Size`; it compares two notices' heights against each other, so the term
cancelled there and cancels still.

#### Red-proof

`MapLayout.fabHeightAX5` set to 80 — below the FAB's real 83 pt footprint, so the reservation
under-reserves — and the suite run on the 16e (`redproof-16e.log`). It failed on the assertion
under test, with the numbers in the message:

```
✘ Test "the recenter control and the FAB fit what the notice's scroll budget reserves at AX5"
  recorded an issue at AX5ReflowTests.swift:219:9:
  Expectation failed: (fab.height → 83.0) <= (MapLayout.fabHeightAX5 → 80.0)
  ↳ IdentifyFAB now measures 83.0 pt at AX5, past the 80.0 pt the notice's scroll budget
    reserves for it
✘ Test run with 9 tests in 1 suite failed after 2.032 seconds with 1 issue.
```

The other two expectations in the same test — the recenter control against its own reservation, and
the exact `== CypressSpacing.minTapTarget` — passed on the 16e in that same run, which is the fix's
device-independence showing up on the device that used to fail.

One issue, on the intended expectation, for the intended reason. Restored to 137, green again.

#### For the operator

There is nothing wrong with the 16e image and nothing to erase. Any AX5 measurement taken through a
hosted `UIWindow` on this project is device-dependent by default — if a future guard pins a height,
it must either strip the insets (as `ax5Size` now does) or host bare, the pattern
`accountProviderLabelRefusesCompressionAtAX5` and
`mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5` already use.
