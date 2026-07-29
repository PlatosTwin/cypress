### Two of screen 10's four glyphs were drawn with path defects, not with the wrong geometry

Reported by the project owner walking the app on 2026-07-27: *"On share screen airdrop symbol is
malformed and link symbol looks weird."* Both marks are hand-drawn `Shape`s — this app has no SF
Symbols and no icon font (SCREENS.md §2 C16) — so there was no wrong symbol name to find. There were
two bugs in two paths, and both of them are the same class of mistake: a `Path` API that appends to a
current point being used as though it started a fresh one.

**AirDrop — two arcs joined by a chord.** `ShareAirDropArcs` drew its two concentric arcs in a `for`
loop of `path.addArc`, with no `path.move(to:)` between them. `addArc` appends to the current
subpath, so the second call first drew a **straight line** from the inner arc's right-hand end
`(16.9, 14.1)` to the outer arc's left-hand start `(3.4, 11.5)` — a chord clean across the mark.
At `1.8pt` that chord ran within a stroke-width of the inner arc for most of its length and the two
merged into a filled-looking blob with a spur out of the lower left. What the owner saw was not a
questionable mark, it was a broken one.

**The dot had already been moved to escape it, which is the part worth recording.** The dot was
offset `0.30 · side` *below* the arcs, under a comment stating that at 24pt a centred dot touches the
inner arc. It does not, and could not: the inner arc's nearest point to its own centre of curvature
is `radius − stroke/2 = 5.1pt` away and the dot's radius is under 2. What the dot would have touched
is the **chord**, which crossed 4.4pt above that centre. So a real defect was diagnosed in the wrong
element, and the repair — a full stop floating below the mark — was carried in the file as a
deliberate decision, with a reason that reads plausibly and is false. The dot is now at the arcs'
centre of curvature, where it belongs, and the chord is gone.

**The mark stays `arcs + dot`.** Apple's own AirDrop glyph is an upward triangle under the arcs, and
the fixed mark still reads closer to a wi-fi symbol than to Apple's. That is what SCREENS.md 10 §4
transcribes — `AirDrop` (arcs + dot) — and swapping the dot for a triangle would be changing a
transcribed description rather than drawing it, which is the design's call. Flagged here rather than
taken.

**Copy link — each cap swept a quarter turn instead of a half.** `ShareChainLink` is two capsule ends
on the box's leading diagonal, each an arm in, a half turn, and an arm back out, plus a bar on the
diagonal joining them. The upper cap was written `startAngle: 225, endAngle: -45`, which is a **90°**
sweep, not the 180° the construction needs: it stopped at the top of its circle instead of at the far
side of it, and the arm that followed was then drawn from that wrong point diagonally back across the
mark. The lower cap had the same defect mirrored (`45 → 135`). The result was two lopsided hooks each
with a stroke cutting through it, which at 24pt reads as a paintbrush — which is what the owner was
looking at. The arms' own endpoints were correct all along; the fix is the two sweeps and the two
points the second arm starts from.

**Neither defect was visible to the test suite and neither ever could be.** 819 tests pass over these
files; `ScreenSweepShots` photographs screen 10 in four appearances and asserts only that an image
came out. Both were found by cropping the 24pt icon well out of that image and looking at it.

### `Add a reading` sat in the Height box and opened the DBH form

Reported by the project owner the same day: *"'add a reading' is misleading because it's in a box for
Height … if adding a reading for height the height sub screen should open, not dbh."* Two defects
under one sentence.

**The routing was a plain bug.** `Route.measure` carried a tree id and nothing else, and
`MeasureDraft.kind` defaults to `.dbh` — SCREENS.md 16 §2's drawn selection. So every entrance to
screen 16 opened on DBH, including the empty `Height` stat card whose whole meaning is that this
tree has no height on it. A contributor entering from the Height box and typing a number without
looking at the segmented control wrote a **trunk diameter in metres**, and nothing downstream would
have caught it: `MeasurePresentation`'s sanity pill compares against previous readings *of the
drafted kind*, of which there were none. The route now carries a `MeasurementKind` and the profile
hands it the kind of the card that was tapped.

**The framing was a design question, and is answered in RULINGS R15.** A general "add any reading"
action was drawn inside a per-measure box and vanished once the tree had both measures, which left a
fully-measured tree with no door to screen 16 at all — E74's original gap, reopened for exactly the
trees that have most to record. R15 splits the two entrances: the empty stat slot stays 03's door for
a *first* reading of its own kind, and screen 11 gains E74's own named candidate — an `Add a reading`
control under the measurement log — as the door for a repeat one. R15 states what it overrules.

**The first fix passed a test suite that could not see half of it, and that is the part worth
keeping.** The tests written for the routing defect all stopped at `TreeProfilePresentation
.StatDestination`. One hop further on — `TreeProfileView.route(for:)`, a private instance method
turning that destination into a `Route` — was reachable only by the renderer. Rewriting that single
line as `case .measure: return .measure(treeID, .dbh)` reinstates the original defect exactly, and
the whole suite stays green while it does. Screen 11's new link had the same shape: its `Route` was
built inside a `Button` closure with a hardcoded kind.

The remedy was already in the codebase and is now applied to both: `MapHomeView.route(for:)` is
`static` and `PinSetDestinationTests` calls it directly, on the reasoning that a second copy of a
mapping is how a basin comes to open a tree's profile (E113). Both of screen 16's entrances are now
`static` mappings a test can call — `TreeProfileView.route(for:treeID:)` and
`GrowthHistoryView.route(forAddReading:)` — and the kind screen 11 opens on has moved out of the view
into `GrowthHistoryPresentation.addReadingKind`.

The general rule this is the third instance of: **a comment naming which layer owns a decision is not
a mechanism that makes the other layer honour it.** The comment on the line above this bug said, in as
many words, "which card means which kind is the presentation's call, not this view's" — and the view
was free to ignore it, because nothing could call the view.
