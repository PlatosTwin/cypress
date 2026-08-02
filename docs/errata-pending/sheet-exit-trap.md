# PENDING — 09/10 were inescapable: a decorative grabber over an OS-swallowed scrim (#175)

*Unnumbered on purpose. The orchestrator splices this under the real next number at merge
(CLAUDE.md, Numbering).*

**The defect.** The care log (09) and share (10) sheets could not be left by any means a
person would try. Owner's report: "clicking outside of them does nothing, and while you think
you'd be able to drag the top of the page down (it looks like the kind of page that does
that, because of the bar at the top), in practice the page is stuck… your only option is to
close the app entirely."

**What was actually wrong — two defects wearing one symptom.**

1. **The grabber promised a drag nobody built.** `BottomSheet .standard` drew the 40×5
   grabber capsule (it is in the mocks) but no drag gesture existed anywhere in the shell.
   R39 made these cards full-height *because a control should do what it looks like*; the
   grabber then looked like drag-to-dismiss and did nothing. A drawing of a control is a
   promise, and this one was false from the day the card went full-height (#146) — the
   content-sized card the mocks drew left acres of tappable scrim, so the gap was invisible
   until the card grew.

2. **The scrim tap worked and could not be reached.** Both hosts wired `onScrimTap: onClose`
   correctly. But a full-height card exposes only the 62pt `statusBarInset` strip of scrim,
   and the system status bar's own hit region (clock, indicators, Dynamic Island) consumes
   roughly the top 54pt of it. Measured by injecting taps on the iPhone 16 Pro simulator:
   taps at (201, 30) and (60, 45) never reach the app — the OS eats them — while taps at
   (60, 58) and (201, 58) reach the scrim and dismiss. The one wired exit was an ~8pt
   invisible sliver under the clock. **This is the discrimination that mattered: not a broken
   control but an unreachable one.** Every unit test passed; the wiring was fine; the failure
   lived in who owns the pixels the wiring sat behind.

**The trap pattern, named for next time.** A layout change that shrinks a control's exposed
area can hand the remainder to the operating system without any code in the diff touching the
control. The scrim tap's tests (had there been any) would have kept passing too, because a
synthesized tap *below* the system's gate still works — only a person aiming at "outside the
sheet" fails, because people aim at the middle of what they can see.

**The fix** (docs/rulings-pending/sheet-exits.md): the shell now keeps the grabber's promise —
a full-width 62pt handle band at the top of the card drags it down, `SheetDismissRule` decides
commit-or-spring-back (quarter-height drag, half-height predicted flick), the scrim tap and
its VoiceOver "Dismiss" element stay, and the interior `ScrollView` keeps every drag below the
band so #146's keyboard mechanism is untouched. Pinned by `SheetDismissRuleTests` (Swift
Testing, the arithmetic) and `SheetExitUITests` (XCTest: drag dismisses 09 and 10, the y=58
strip tap dismisses, a drag on 09's note field does not — each watched red first).

**A test lesson paid for en route.** The first dismissal assertion — "the map's FAB exists
after the drag" — was born vacuous: a `fullScreenCover` leaves the presenting screen's
elements in the accessibility tree, so `exists` was true while the sheet still stood. Its own
red-proof caught it (gesture deleted, tests still green). Dismissal from outside the app is
the covered element becoming **hittable**, not existing.
