### screen 04 lost its framing chips off the top of the display at the accessibility sizes

SCREENS 04 draws a `flex:1` viewfinder over a `flex:none` tray, with the framing chips and the
shutter as an `.overlay` on the viewfinder's bottom edge. That is drawn at the default type size and
at no other, and R14 is the ruling that says what the screen does at the rest of the ramp.

What went wrong is the overlay, not the tray. An overlay aligned `.bottom` pins its bottom edge to
the viewfinder's, so as the tray grows with the type ramp and squeezes the viewfinder shorter than
the overlay, the chip row grows **upward, off the top of the screen** — under the status bar and the
Dynamic Island, where it cannot be read and does not answer a tap. E152's feature, one session taking
a full tree, a trunk and a leaf, was not merely cramped at AX5. It was unreachable.

R14's answer: the viewfinder keeps a floor and the controls beneath it scroll. Three things it
deliberately left to be decided against the running layout, and what they were decided as.

**The floor is 524 pt on a 393 pt phone, and it is read off the capture rather than chosen.**
`VisitCameraController` sets `sessionPreset = .photo`, which is 4:3 on every iPhone, and
`VisitCameraPreview` sets the layer to `.resizeAspectFill`. A viewfinder `width` points wide
therefore shows the whole frame at exactly `width × 4/3`; taller than that and the preview crops the
sides, shorter and it crops the top and the bottom — and on a street tree the first thing off the top
is the crown. So the floor is the height at which the viewfinder stops showing the photograph it is
about to take, which is where R14's reasoning stops being comfort and becomes fact.

**The switch is `isAccessibilitySize`, and it is not a number of its own.** Measured on the running
app: the viewfinder is 583 pt at the drawn size, 550 at `xxxLarge`, 503 at AX1. The floor first binds
exactly where that predicate first turns true, so no second spelling of "large text" was invented.

**The shutter pins and the chips travel.** A person on this screen is holding a phone up at a tree,
and aiming and firing are one gesture: a shutter you have to scroll to find is a shot you lose your
aim to reach. It also costs a constant 68 pt at every text size where the controls' cost grows
without bound. The argument the other way, so it is on the record rather than lost: those points are
viewport the controls could have had, and once all three framings are photographed the shutter has
nothing left to do. Refused because the screen cannot know when a contributor is finished, and
because a control that is sometimes pinned and sometimes not is worse than one that always is.

The rule the variant follows, stated so the next person does not have to derive it: **the viewfinder
carries only furniture whose size does not depend on the type ramp** — the close button, the framing
corners, the shutter. Everything that grows with the ramp moves into the scrolling controls. The one
exception is the guidance pill, because with the chips moved down it is the only thing left saying
which framing is being aimed; it is top-anchored, so it grows down into the frame rather than off the
display, and it is hit-transparent.

`SCREENS.md` §3 · 04 now draws the result as screen 04's accessibility variant, per R14's own
instruction that whoever builds it leaves a spec rather than a precedent.

---

### the tests written for that variant could not run, and had never been run

Worth recording separately from the fix, because the fix was sound and the tests were not, and the
combination is the exact shape this project keeps catching itself in.

Two tests were written to host screen 04 and ask which control ended up on which side of the fold, by
**accessibility label**. Every one of those lookups came back empty. A hosted SwiftUI tree in an
off-screen window vends no accessibility elements at all: probed directly, a bare
`Button("Hello button")` inside a `UIHostingController` reports `accessibilityElementCount() == 0`,
and there are no elements anywhere in its hierarchy — SwiftUI builds that tree lazily for a real
assistive client, and a unit-test host is not one. So both tests failed on the first run they ever
got. They had been committed unreviewed after the agent writing them was killed mid-run, in the
window between writing them and running them.

The same helper had a second, independent fault. `firstScrollView(in:)` returned the first
`UIScrollView` in the hierarchy, and `UITextView` **is** a `UIScrollView` — screen 04's note field is
a `TextField(axis: .vertical)`, which UIKit backs with one, and it sits inside the controls. So the
helper answered "yes, the controls scroll" on the drawn layout, where they do not, and reported the
note field's origin as the viewfinder's floor.

Rewritten on geometry, which UIKit will answer for a hosted tree, and which is what R14's split
actually is: the viewfinder ends at its floor, the scroll view begins exactly there, and it holds
more than fits in it. **Which** control is on which side is verified by looking, per ARCHITECTURE §7
and exactly as `theChipRowFitsTheWidthItIsGivenAtAX5` already says of the row above it.

Two measuring traps found on the way, written down because both would have been read as the view
being wrong rather than the ruler:

- `UIHostingController` resolves a safe area even in a bare window and folds it into
  `sizeThatFits`. A phenology chip measured 83.67 pt tall where the layout draws it at 56.67, and the
  add-tree well measured 535 pt where it draws 481 — the same 54 pt of inset both times.
  `safeAreaRegions = []` is the fix and it is load-bearing.
- SwiftUI wraps a `ScrollView` in a `PlatformContainer` and positions *that*, leaving the scroll view
  at its parent's origin. `scroll.frame.minY` is therefore 0 on a scroll view sitting 524 pt down the
  screen; the measurement has to be converted into the root's coordinate space.

---

### the phenology chips on screen 04 were squeezed until their labels broke mid-word

Reported by the project owner: *"The photo check in labels are too narrow. Text gets all compressed
in them as they're currently implemented."* **At the default text size**, which is the part that
matters — this was not an accessibility-size defect.

The phenology row was an `HStack`, and an `HStack` compresses its children rather than overflowing
its proposal. A row wider than the space it is given does not spill off the phone; it squeezes every
chip below the width its own label needs, and the labels wrap. A curated deciduous species offers all
six tags, and six chips want about 537 pt in the 361 pt the tray leaves them. On a 393 pt phone at
`.large` the row read:

> `Leaf/out · Full/leaf · Flow/ering · Fruit/ing · Fall/colo/r · Bar/e`

Every label broken mid-word, one of them across three lines.

**Why it survived so long.** `VisitPhenologyVocabulary` offers this row "for the curated 40 and
nobody else" — a species needs a curated field-guide entry *and* a sourced `leaf_retention` before a
single chip appears. No preview and no fixture in the project had ever stood screen 04 over one of
the 40 with a habit on it, so every rendering of this screen the suite had ever made showed an empty
phenology row. The owner met it immediately, because London Plane is both one of the 40 and the
commonest street tree in San Francisco.

The fix is `CypressChipFlow`, the component the app's other three chip rows already use. The
mechanism was already written down in this codebase, in `VisitShotTypeChips`' own note explaining why
*that* row had stopped being an `HStack` — and that note even named this row as the place still doing
it, "which is what the phenology row below already looks like at AX5". It was wrong about one thing
only, and it is the thing that made this a live defect rather than a known rough edge: it does not
wait for AX5.

The row is now its own type, `VisitPhenologyChips`, for the reason `VisitShotTypeChips` already
established: a row whose geometry is the defect has to be hostable on its own, or the test guarding
it is a test of its parent.

---

### the "Add this tree" photo well was a landscape frame, so the viewfinder cropped the shot

Reported by the project owner: *"Add this tree photo window is still awkwardly horizontal and doesn't
capture full view on vertical orientation."*

"Still" is exact. #79 had already fixed the reported half of this — *"photo for custom tree should be
standard photo style, right now it's horizontal and cuts off vertical frame"* — by drawing the
captured still with `PhotoFit` instead of `scaledToFill`. That stopped the crop. It did not change
the **well**, and the well was the actual defect.

`VisitMetrics.AddTree.wellHeight` was `268`, and its own comment said what it was meant to be: "the
4:3 frame that photograph will be, at the gutter's width on the drawn 393 pt frame". 361 × 3/4 ≈ 271.
That is a 4:3 frame lying on its side. A phone held upright captures **3:4 portrait**, which at 361 pt
wide is 481 pt tall. One inverted ratio — dividing where the photograph multiplies — and the well had
been a landscape letterbox for its whole life.

What it cost, in each of the well's two states:

- **Live.** The well holds `VisitCameraPreview`, whose layer is `.resizeAspectFill`. A 3:4 frame
  filling a 361 × 268 landscape box is scaled until it covers, cropping 44 % off the top and the
  bottom. A volunteer aiming at a street tree could not see the crown they were framing. This is the
  half the owner's "doesn't capture full view" names, and it is the worse half: a viewfinder that
  does not show the shot.
- **Still.** After #79 the photograph was whole, but whole inside a box the wrong shape for it —
  drawn at 201 × 268 with a third of the well standing empty on either side.

The well now takes its shape from `Camera.captureAspectRatio`, inverted for SwiftUI's width ÷ height
convention, so the well and screen 04's viewfinder floor cannot drift apart: they are two views of
the same photograph, and that value is read off the capture path rather than chosen. It is an aspect
ratio and not a height, so the well is right on a phone this was never measured on.

**No cap, deliberately.** A maximum height would be a return to the letterbox by a smaller margin:
any well shorter than its own capture crops the live preview again, which is the defect. The composer
scrolls and the CTA is pinned outside that scroll, so a taller well costs scrolling, never reach.

One consequence worth naming, because the old behaviour had been written up as a feature. The code
argued that the jump from a filling viewfinder to a fitted still was intended — the frame "pulls
back" at the moment of capture and shows what the well was never going to show. With the well the
same shape as the capture there is no jump: fill and fit are the same drawing, and what you aimed at
is what you are shown. The old behaviour was a symptom being read as a design, and what it really
told a volunteer was that the viewfinder had been lying to them.
