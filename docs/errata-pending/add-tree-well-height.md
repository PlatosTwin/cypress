### E1XX — The add-tree photo well was the right shape and the wrong share of the screen

Reported by the project owner, walking the app: *"Screen for Add this Tree has the photo square fill
the entire vertical area so it's not clear to the user that there is content below the photo that
they can fill out."*

**The suite asserted the thing being complained about**, which is the reason this entry is longer
than the fix. E162 (#113) found the well was a landscape frame that cropped a portrait capture and
made it the 3:4 frame a phone held upright actually takes, deriving it from
`Camera.captureAspectRatio` so the well and screen 04's viewfinder floor cannot drift. That was
right, and `VisitCameraSessionTests.theAddTreeWellIsAPortraitCaptureFrame` has guarded it since. But
3:4 at the gutter's width is 481 pt on a 393 pt phone, and E162 wrote the consequence down as a
feature:

> **No cap, deliberately.** A maximum height would be a return to the letterbox by a smaller margin:
> any well shorter than its own capture crops the live preview again, which is the defect.

That paragraph is correct about the mechanism and wrong about the conclusion, and the difference is
one word. A cap on the well's **height** does return the letterbox — the well would be gutter-wide
and too short, `VisitCameraPreview` is `.resizeAspectFill`, and the crown would go off the top of a
street tree again, which is exactly E162's defect. A cap on the well's **width** does not: the well
keeps its ratio to the last bit and is simply drawn smaller and centred. E162 refused the only cap it
considered, and there was a second one.

**Measured on the running app, iPhone 16e (390 × 844 pt), the add screen with a fix:**

| | scroll viewport | well | share |
| --- | --- | --- | --- |
| before, default type | 573 pt | 476 pt tall × 356 wide | **83 %** |
| before, AX5 | 247 pt | would be 476 | **193 %** — drawn clipped by the footer |
| after, default type | 539 pt | 357 tall × 266 wide | 66 % |
| after, AX5 | 179 pt | 116 tall × 91 wide | 65 % |

The tests host a 393 × 852 phone rather than this one, and the failures they record against the
pre-fix layout read 481 pt of a 617 pt viewport at the drawn size (78 %) and 219 *drawn* rows of a
287 pt viewport at AX5 — the second being where the footer cut the well off, because 481 pt has
nowhere to go in 287.

At the drawn size the 83 % left 105 pt under the photograph, into which the screen fitted the
photo-source link, one sentence, and the top half of the words `Move the pin` — a clipped line above
a pinned CTA, which reads as the bottom of a screen rather than as the middle of a form. At AX5 it
was worse than the owner reported: the well did not fit in the viewport at all, so the entire first
screenful was one grey box clipped at the footer, and the photo sources, the pin row, the land
question and the species row were all below a fold that nothing on the screen admitted to. That is
E159's failure in a different costume — a thing sized by something other than the type ramp growing
past the space the type ramp left it.

**The fix, in three parts.**

1. `VisitMetrics.AddTree.wellWidthCeiling(viewport:)` — the well may take at most
   `wellViewportShare` (two thirds) of the composer's scroll viewport, expressed as the **width**
   that bounds that height at the well's own ratio. `VisitAddTreePhotoWell` applies it as
   `.frame(maxWidth:)` ahead of its `.aspectRatio(_:contentMode: .fit)`, so the well shrinks along
   its own diagonal. `wellAspectRatio` is untouched and still derived from the capture; nothing here
   can move it, and `theWellCeilingTakesWidthNotShape` is the assertion that says so — it binds the
   ceiling hard and reads the ratio back off the drawing.
2. The composer's scroll is wrapped in a `GeometryReader`, whose only job is to hand the viewport's
   height to that function. Same shape as screen 04's `accessibilityLayout` and for a related
   reason: a split at a stated line rather than whatever two flexible children negotiate.
3. **The accuracy chip is pinned with the header instead of scrolling with the form.** Without this
   the ceiling means less than it says: "the well takes two thirds of the viewport" is only "a third
   of the viewport shows the form" if the well starts at the top of the viewport, and with the chip
   above it inside the scroll the chip's height came out of the third. At AX5 the chip is 78 pt of a
   247 pt viewport — the whole of the remainder. The chip is a statement about the screen rather
   than a row of the form (it is screen 02's status row, and 02 does not scroll it either), so
   pinning it is what it was always describing.

**One consequence that had to be fixed with it.** The narrower well and the type ramp stop being
compatible above a point: at AX5 the well is 91 pt wide and `"A photo of the tree is required"` sets
four lines of ~33 pt type inside it, which the well clipped top and bottom into *"photo of the tree
is requir"*. E159 already wrote the rule for this — a frame whose size does not follow the ramp
carries only furniture that does not follow the ramp either, and everything that grows moves out —
so at accessibility sizes the sentence is drawn under the well rather than inside it. Nothing is lost
to VoiceOver at any size: the well's `accessibilityLabel` is that string either way. It also lands
where the peek is, which is why AX5 now shows a legible line of copy below the photograph where it
used to show nothing at all.

**What the test now guards, and why it is a different test.**
`theAddTreeWellIsAPortraitCaptureFrame` keeps every ratio assertion it had, including the 481 pt
figure — that number is still exactly true of the well's *shape*, which is what it was always about,
and the test now says so and measures the unbounded well to prove it. What it could never assert is
the defect above: the well was the right shape and the wrong share of a screen, and a component
measured on its own has no screen to be a share of. So `theAddTreeWellLeavesTheFormOnTheScreen`
hosts the real composer at 393 × 852 at `.large` and at `.accessibility5`, draws it with
`layer.render(in:)`, and reads the well's rows out of the pixels by its `surfaceEmptyThumb` fill —
because the well is a `RoundedRectangle` inside a `ScrollView`, SwiftUI vends no `UIView` for it, and
a hosted tree vends no accessibility elements either. Three claims, all three red before the fix:
the well is at most two thirds of the viewport; the well starts at the top of the viewport; and
there is ink drawn below the well and above the CTA, which is the owner's sentence restated as a
fact about pixels.

Related: E162, whose "no cap" this narrows and whose ratio it leaves alone; E159, whose rule about
what a ramp-independent frame may carry is applied here a second time; ticket #127.
