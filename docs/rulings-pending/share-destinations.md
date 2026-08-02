# Ruling (pending number): Screen 10's destination row, and full-height standard sheets

Owner direction (2026-08-01, verbatim, device screenshot on file): "Share is still fucked.
Also half-screened, like Care. Each button takes you to the same share dialog on the iPhone,
which makes individual buttons useless. If we're going to have a Messages button then clicking
it SHOULD INSTANTLY BRING YOU TO MESSAGES SHARING, not to the same screen that you get if you
click AirDrop…" This overrides E59's routing (every named destination → the system sheet) and
SCREENS.md 10 §4's four-button row. Ticket #146.

**The rule the rebuilt screen obeys: a destination button does exactly what its label says, and
a label that cannot keep that promise does not get a button.** As built:

1. **`Messages` opens Messages composition directly** — `MFMessageComposeViewController`,
   presented in-app with the public link as the body. Where the composer cannot exist
   (`canSendText() == false`: every simulator, and a device with no messaging account) the
   button falls back to the system share sheet rather than going dead; `MessagesRoute` in
   `SharePresentation.swift` is that decision as a pure function, so the device-side branch is
   asserted by the unit suite from a machine that cannot exhibit it. Verified on simulator that
   the fallback presents (screenshot in the #146 report); the composer branch is untestable on
   simulators and is wired through the same presentation path.

2. **`Copy link` is unchanged** — writes the public URL to the pasteboard. Verified end to end
   on simulator: the pasteboard held the exact card URL after one tap.

3. **`Share…` (tray + up arrow glyph) is the system share sheet**, via `ShareLink`. It is the
   honest name for what E59's three buttons all did. **AirDrop folded into it**: an "AirDrop"
   button cannot be built as labelled — `excludedActivityTypes` cannot exclude third-party
   share extensions, so a "trimmed" sheet is still a general share sheet with AirDrop at the
   top, i.e. not distinct from `Share…` in any way a user can perceive.

4. **`Instagram` is removed, not rerouted.** Instagram publishes no API for sharing links; the
   Stories URL scheme requires a registered Meta app ID (an external registration and an API
   key), and the product line is zero external dependencies. A button that can do nothing
   distinct from `Share…` should not exist as a separate button; when a real Instagram path
   exists someday, it comes back under this ruling's rule.

**Sheet height (the mechanism #168 rebases on):** C17's `.standard` bottom sheet is now
full-height — the card runs from the 62pt status-bar strip to the bottom of the display,
content top-aligned inside a `ScrollView` (`BottomSheet.swift`). The mocks drew 09/10 as
content-sized bottom cards; the owner's "half-screened" overrides them. Two rules ride along:

- A screen hosting `BottomSheet` must use `.ignoresSafeArea(.container)`, never the bare form —
  bare `.ignoresSafeArea()` includes `.keyboard` and is the exact mechanism by which the care
  log's keyboard covered the note field being typed into. With the keyboard region respected,
  the sheet shrinks above the keyboard and the `ScrollView` keeps the focused field visible.
- `.account` (screen 15) keeps its content-sized card: a short ask with no text input, whose
  mock is a card, not a page. Nothing about 15 was reported or changed.

The unit ledger (`SharePresentationTests`) pins the three labels by name and order, the hints,
and both `MessagesRoute` branches; `SheetHeightUITests` pins the full-height geometry of 09 and
10 and the note field's position above any keyboard's reach. A direct keyboard-frame assertion
was written first and deleted as vacuous: on a runner with a hardware keyboard attached,
`app.keyboards` exists *below the screen* (y=946 on an 874pt device), so it passed against the
broken build too. The geometry assertion went red against the pre-#146 layout (field at 0.81 of
the screen against a 0.55 ceiling); all five new/changed tests were proven red by mutation.
