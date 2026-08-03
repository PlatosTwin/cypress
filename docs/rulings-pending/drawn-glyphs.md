# (pending number) — The no-SF-Symbols policy stands, and is now written down and tested

Ticket #130. Delegated design authority; decided against the code and the running screen on an
iPhone 16 Pro Max, at default type and at AX5.

**The ruling: option 1. Every glyph in Cypress is a `Shape` drawn in this repo. No SF Symbols, no
icon font, no exceptions — not for close, not for trash, not for a thumb.** The five call sites are
drawn. The policy is stated at app scope in `ShareDestinationGlyph.swift` and enforced by
`CypressTests/DrawnGlyphGuardTests.swift`.

## 1 · What the ticket got right, and the three things it did not

The five call sites were real and are exactly as listed. Three corrections, all of which changed how
the decision had to be written:

- **The policy had never been written at app scope anywhere.** `ShareDestinationGlyph` cited
  "SCREENS.md §2 C16" for it. C16 is the `BottomTabBar` component, and its "Icons (all hand-drawn,
  no icon font)" is a bullet introducing *that bar's own four icons* — Map, My Grove, Journal, You.
  `RULINGS` R16 then cited `ShareDestinationGlyph` as "the statement of the policy". So the
  app-wide rule everyone was enforcing rested on a citation loop that bottomed out in one
  component's spec. **This is why neither option was "restore the rule": the rule had to be written
  for the first time either way**, and the only question was which rule to write.
- **Five call sites, but seven distinct symbols.** `TreePhotosPresentation.glyph(_:filled:)`
  returned four names — `hand.thumbsup`, `hand.thumbsup.fill`, `hand.thumbsdown`,
  `hand.thumbsdown.fill` — from one call site. A gate that counted call sites would have let a line
  add symbols without adding a hit. The gate counts *uses of the API*, and its own control asserts
  the token list is populated.
- **`ShareDestinationGlyph`'s policy paragraph is at lines 18–20, not 16–18**, and none of the five
  sites is dead code: the library shutter is reached from both `VisitCameraView` and
  `ContributionCameraView`.

## 2 · Why the policy stands

The brief framed this as a real choice, and the honest case for narrowing — E163's receipt that
hand-drawing costs path defects — was weighed. Three things decided it.

**The record is one-sided, and it is a record of practice, not of prose.** Every design decision
this project has taken on a glyph refused a symbol *while these five sat in the tree*: R16 drew the
search bar's ✕ by hand rather than take `xmark.circle`; R39 drew `Share…` as a tray and arrow rather
than take `square.and.arrow.up`; R2 refused to invent a heart and counted doing so as a "**sixth**
violation of the drawn-glyph policy the project is already carrying five of"; the #166 site-kind
ruling chose a `Menu` partly because it "draws no SF Symbol (adding nothing to #130's five debts)".
The five were never an exception anybody granted. They are the un-ruled residue of one corner of the
app — Photos and the visit camera — and the project has been routing around them, in writing, for
months. Narrowing the policy would have ratified an oversight as a decision.

**One of the five was already solved twice over.** The app ships two hand-drawn ✕ marks —
`VisitCloseGlyph` (the camera's) and `CypressClearGlyph` (C20's, a ring with an ✕ in it). The photo
viewer's close button reached for `xmark` anyway. Any "closed set of system-conventional
affordances" would have had to include close, and including it would have meant permitting a symbol
for a mark this repo had already drawn, twice, on screens a person reaches in the same session.

**The cost did not materialize — and that was checked before it was claimed, not after.** The five
marks were drawn as SVG at the same coordinates the Swift uses and rasterized at 17, 24 and 53 pt,
stroke and fill, before a line of Swift was written. All five read. Four of them are straight lines,
rounded rectangles and one ellipse — none needs the arc-chaining that broke AirDrop and Copy link in
E163. The thumb is the only hard one, and it is one closed subpath.

E163's actual lesson is narrower than "hand-drawing is expensive": both of its defects were a path
API that *appends to a current point* being used as though it started a fresh one. Every subpath in
the new marks opens with its own `move(to:)`, and each file says so and cites E163 by number, so the
next reader knows what to check for rather than being told the code is fine.

## 3 · What is drawn, and the one construction worth recording

`Cypress/Features/Photos/PhotoGlyphs.swift` — `PhotoTrashGlyph`, `PhotoThumbGlyph`,
`PhotoCloseGlyph`. `Cypress/Features/Visit/VisitCameraView.swift` — `VisitLibraryGlyph`. Each lives
beside the screen that uses it rather than in `DesignSystem/Components`, which is the arrangement
`ShareDestinationGlyph` and 14's camera glyph already state and give the reason for: C1–C30 is a
closed catalog and no other screen uses these.

**One thumb serves all four states.** A downvote is the same mark turned a half turn
(`rotationEffect`), and the reader's own vote fills the path instead of stroking it. There is one
set of numbers, so the two directions cannot drift apart and the filled state cannot disagree with
the outline. Which vote turns it is `TreePhotosPresentation.thumb(_:filled:)`, a value a test can
call — E164's rule that a mapping only the renderer can reach is a mapping no test can check.

**The stroke scales with the box.** All marks are authored in a 24×24 box at stroke 1.8, the app's
own line weight, and drawn at 17 pt. A 1.8 pt line left unscaled in a 17 pt frame is the weight of a
2.5 pt line in the box it was drawn in — the difference between a mark and a blob. `stroke(for:)`
carries this and a test pins it.

**The library shutter keeps its second card.** A single framed picture says "a photo"; the stack
says "*pick* one", which is the distinction that button is drawing against the camera shutter beside
it, and the reason the old comment gave for choosing `photo.on.rectangle` in the first place.

## 4 · What was looked at

Screens 20 (photo browser), the viewer, and the visit camera's library shutter, on the running app,
at default type and at AX5 — recorded in the ticket report with screenshots. The marks are drawn at
a fixed point size and do not scale with Dynamic Type, which is the behavior the SF Symbols they
replace also had (`.font(.system(size:))` is a fixed size); AX5 changes the rows around them, not
the marks. **This is a deliberate limit, not an oversight, and it is the obvious thing to revisit:**
a 17 pt mark beside body text at 53 pt is small, and it was small before #130 too. Whoever takes
that up should take it up for every drawn mark in the app at once rather than for these five, which
is why it is not taken here.

## 5 · The gate

`DrawnGlyphGuardTests` reads every `.swift` file in the app target off disk through `#filePath` —
the walk is `BritishSpellingGuardTests`' (R56), reused rather than duplicated — and fails on
`systemName:` or `systemImage:` appearing in code. It blanks comments and string-literal interiors
first, which is load-bearing: #130 deliberately writes the token `Image(systemName:)` into prose in
`MapChrome`, `ShareDestinationGlyph` and `PhotoGlyphs` to record what was removed and why. A control
asserts those prose mentions still exist *and* are not counted, so the day the scanner stops
stripping comments, the control fails rather than the gate — and the next reader fixes the scanner
instead of deleting a gate that has started crying wolf.

Provenance controls, in the same shape R56 established: the guard fails if it cannot find the source
tree and if it sweeps fewer than 150 files, because this project's signature failure is a green
result from a check that ran on nothing.

**What it cannot check:** a symbol reached through a name built at runtime, or a UIKit view
configured without ever spelling `systemName`. The gate covers the spellings SwiftUI and UIKit
actually offer and claims nothing beyond them.

## 6 · What this overrules

Nothing. It writes down a rule the project has been enforcing in every ruling since R2 and states
it at the scope it was always being applied at. It corrects two comments that asserted the rule as a
fact about the code while the code disagreed (`MapChrome`'s "two calls, both inside a photo picker"
— it was five, in three files, none in a picker) and two that cited `SCREENS.md §2 C16` for an
app-wide claim C16 does not make (`ShareDestinationGlyph`, `ComponentSupport`).

`SCREENS.md` is **not** amended. C16's bullet is correct about C16; the error was in citing it, not
in what it says. R16's citation of it is left as written — the ruling record is not rewritten after
the fact — and the correction is recorded here and in the two code comments that carried it forward.
