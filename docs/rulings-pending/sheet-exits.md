# PENDING — How a full-height sheet is exited (ticket #175, delegated)

*Unnumbered on purpose. The orchestrator splices this under the real next number at merge
(CLAUDE.md, Numbering). Written under the delegated design authority for #175 — the mocks are
static HTML and draw no gesture, so nothing here contradicts a drawing; it decides what the
drawing's grabber and scrim actually do on a phone. Everything below was measured on the
running app (iPhone 16 Pro simulator), not inferred from the brief.*

## What this rules

Screens 09 (care log) and 10 (share) are `BottomSheet .standard`: full-height cards under R39,
with a grabber, no close button, presented in a `fullScreenCover` — so the shell owns every way
out. The owner's report: "clicking outside of them does nothing, and while you think you'd be
able to drag the top of the page down (it looks like the kind of page that does that, because
of the bar at the top), in practice the page is stuck… your only option is to close the app
entirely."

## The diagnosis this ruling is built on

The scrim tap was **wired and working** — both hosts pass `onScrimTap: onClose`, and a tap
that reaches the scrim dismisses. What was broken is reachability:

- A full-height card exposes exactly one strip of scrim: the 62pt `statusBarInset` band at the
  very top of the display.
- On a Dynamic Island device the system's own status-bar hit region (clock, indicators,
  island) consumes roughly the top 54pt of that band. Measured by injecting taps on the
  simulator: **(201, 30) and (60, 45) never reach the app; (60, 58) and (201, 58) dismiss.**
- So the one exit was an ~8pt-tall invisible sliver between the system's gate and the card's
  top corner radius. Not a broken control — an unreachable one. "Clicking outside does
  nothing" is the OS eating the tap.
- And the grabber was pure decoration: no drag gesture existed anywhere in the shell, on a
  card whose grabber is precisely the drawing that promises one.

## The ruling

**1. The primary exit is the drag the grabber promises.** R39's own principle — a control does
exactly what it looks like — cuts both ways: the full-height card kept the grabber, so it must
keep the grabber's meaning. A full-width handle band across the top of the card
(`CypressSpacing.Component.sheetDragZone`, 62pt: the card's top padding, the grabber row, and
the title line — the "bar at the top" the owner tried to pull) drags the card down with the
finger. Release commits or springs back by `SheetDismissRule`: a slow drag commits at a
quarter of the card's height; a flick commits when its *predicted* end — velocity folded into
distance, `predictedEndTranslation` — crosses half. Upward drags do nothing: the card refuses
to rise above its resting place. The spring back animates on `czSheet` through
`CypressMotion.resolved`, so Reduce Motion snaps instead of springing; following the finger is
direct manipulation, not decoration, and is not switched off.

**2. The whole card does not drag, and that is deliberate.** The native-sheet feel — the card
dragging from anywhere once the interior scroll sits at its top — was considered and declined.
The interior `ScrollView` is load-bearing for #146's keyboard mechanism (it is what moves 09's
focused note field clear of the keyboard), and SwiftUI offers no gesture-failure ordering
against a `ScrollView` that would not gamble with it. A competing whole-card gesture is
exactly how a drag on the note field starts dismissing the page someone is typing into. Below
the handle band, every drag belongs to the content; `SheetExitUITests` pins that a drag on the
note field leaves the sheet standing.

**3. The scrim tap stays, as wiring, sliver, and VoiceOver's exit.** The strip still dismisses
where the OS lets a tap through (pinned at y=58 by test), and the scrim remains the named
"Dismiss" element — VoiceOver activation reaches it without hit-testing, so it is the
accessible exit regardless of what the status bar swallows. But the strip is no longer *the*
exit; it is the margin of one.

**4. 09 and 10 stay close-button-less.** The mocks draw no close button on either screen
(constraint 21 — a control not in the mocks is not invented here), and with a working drag,
a working scrim margin, and a named VoiceOver exit, none is needed. If a future walk still
finds the exits under-discoverable, a close button is the owner's call, not this delegation's.

**5. Scope.** `.account` (15) is untouched: its card is content-sized, most of the display is
reachable scrim, it draws no grabber — so it promises no drag — and it has its own buttons.
Check-in (05) is a pushed screen with a back control, not this shell. The only two surfaces in
the trap were the only two `.standard` hosts, 09 and 10, and the fix is in the shell they
share, so a third `.standard` host inherits its exits.
