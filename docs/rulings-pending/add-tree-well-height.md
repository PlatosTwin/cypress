### RXX — the add-tree photograph is bounded by the viewport; at accessibility sizes it keeps its share and the form scrolls

The open question was what the community add's photo well does when the frame it must be — 3:4, the
shape of the capture, fixed by E162 and derived from `Camera.captureAspectRatio` — does not fit on the
screen alongside the form it sits above. `SCREENS.md` draws no add-tree screen at all (the view's own
header says so), so there is no specified variant at any text size, and ARCHITECTURE §5.8 says stop
rather than invent one. This is that stop, answered under the standing delegation, against the running
app rather than from a document.

**The finding.** At the drawn size on a 390 pt phone the well took 83 % of the composer's scroll
viewport, leaving 105 pt into which the screen fitted a link, a sentence and the top half of the words
`Move the pin`. At AX5 the well was taller than the whole viewport, so the first screenful was one
clipped grey box and every field was below a fold nothing on the screen admitted to. The owner's
report — that it is not clear there is content below the photo — was an understatement of the AX5 case.

**The ruling, in two parts.**

**1 · A bound on the photograph takes width, never height, and never ratio.** The well is the frame of
the photograph it holds, so it is always exactly the photograph's shape; when there is not room for it
at the gutter's width it takes less width and is centred. This is the point E162 missed when it refused
a cap, and E162's reasoning is otherwise intact: a *height* cap on a gutter-wide well does return the
letterbox, and with a `.resizeAspectFill` preview it crops the crown off a street tree, which is the
defect E162 exists to prevent. A width cap does neither. Anyone revisiting this may move the share; the
one thing they may not do is bound the height or restate the ratio.

**2 · At accessibility sizes the well keeps its share of the viewport, and the form scrolls.** This is
R14's answer to the same conflict on screen 04, and it lands differently here because the screens are
different. On 04 a person is aiming a camera and the viewfinder must survive, so the viewfinder keeps a
floor and the controls scroll under it. On the add screen the photograph is one field of a form: there
is a library path and a shutter, the well is as often a *review* of a shot as a viewfinder for one, and
everything on the screen is already inside a scroll. So the well takes two thirds of whatever viewport
it has and no more, at every size — which at AX5 on a 390 pt phone is 91 × 116 pt.

**The cost of part 2, stated rather than buried:** a 91 pt-wide live viewfinder is not a viewfinder
anybody can compose a shot in. The alternative was refused because it is worse: give the well a floor
big enough to aim in and the AX5 viewport is entirely consumed by it again, which is the reported
defect, on the display of the reader least able to absorb it. **At accessibility sizes this screen is a
form with a photograph in it rather than a photograph with a form under it**, and the shutter and the
library are both a scroll away and both reachable. If that trade turns out to be wrong in the field,
the thing to change is the *screen* at accessibility sizes — a variant that makes the photograph its
own step — and not the share.

**Deliberately not decided here**, because they want evidence this ticket does not have: whether two
thirds is the right share at the drawn size or merely a defensible one (it was chosen so that the
remainder is a band of form rather than a clipped line, and looked at on the running app); whether the
accuracy chip, now pinned above the scroll so that the remaining third is genuinely below the
photograph, should stay pinned once the screen has more chips than one; and whether the AX5 layout
deserves its own drawn variant in `SCREENS.md` the way R14 gave screen 04 one. Whoever answers the last
of those draws the result, so the next person inherits a spec rather than a precedent.
