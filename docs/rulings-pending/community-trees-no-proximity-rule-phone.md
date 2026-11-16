# Rulings pending: how the phone builds "a note, then still add" (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. These are the author's build choices for the owner's ruling of
2026-11-14 (`community-trees-no-proximity-rule.md`); none of them adds a string or a screen state.

---

### R??? — The Add this tree screen looks the nearby trees up itself, before the tap

**Before.** The screen learned about a nearby tree only when `addTree` threw its proximity conflict
after the tap, and drew the conflict's candidate list as a refusal.

**Now.** `addTree` does not refuse on distance, so there is nothing to throw. The screen reads the
list itself: `VisitAddTreeModel.refreshNearby` calls `treesNear` (limit 10) around the coordinate the
tree would be added at, out to `TreeDraft.proximityNoteKeepRadiusM` (15 m), over the seed and the
whole community layer, other people's cached trees included. `VisitAddTreeModel.listed(_:keeping:)`
then keeps the rows within `TreeDraft.proximityDedupeRadiusM` (10 m, the exact-meters circle the
refusal used) and, while the note is up, the rows it already listed out to 15 m (the owner's decision
on flicker, below). The view runs the read when the coordinate first becomes known and again whenever
it changes (`.task(id: model.coordinate)`): a moving GPS fix while the pin is the GPS, and a pin the
reader placed. The answer is dropped when the position moved while it was read, and once an add is
under way. Two unit tests in `CommunityAddTests` hold each of those two drops.

**What the reader sees.** The same "ALREADY ON RECORD" card, at the top of the scrolling form, above
the photo (the owner's decision below), with the owner's two sentences and the same list of trees.
Each row opens its tree's profile over the add screen (the owner's decision below, "Keep the
draft"). The Add this tree button does not read the list: it stays active, and one tap adds the tree.
A read that fails leaves the list as it was rather than showing an error, so one failed read does not
take a note down that is showing (second review, 2026-11-15). The note is advice, and the add does
not depend on it. An answer is dropped when a newer read has started since it was asked.

### R??? — Where the note sits: the top of the form (owner's decision, 2026-11-15)

**The question**, asked with AskUserQuestion: where should the "ALREADY ON RECORD" note sit, given
that at normal text size on an iPhone 17 Pro it is below the photo, the pin line, the land chips and
the species line, while the Add this tree button is pinned and active.

**Offered:** "Top of the form (Recommended)"; "Where it is now"; "Scroll to it".

**Chosen: Top of the form.** In the owner's words: "The note moves to the top of the scrolling form,
above the photo. The reader sees it without scrolling, before they can add a second copy of a tree.
It shows only when a tree is within 10 m."

**As built.** The card is the first thing in `VisitAddTreeView`'s scrolling form, under the header
and the pinned GPS chip and directly above the photo. With no tree within 10 m it is not drawn, and
the form starts at the photo exactly as before. When a tree is within 10 m, the photo and the rest of
the form sit lower by the card's height, which is the trade the owner chose.

**What did not change.** The photo requirement, the 75 m bound on the pin, and a second tap during an
add (the button stays disabled while the add runs and after it succeeds).

**Measured by the reviewer of 2026-11-15** on the 390 pt iPhone 17e simulator, default text size, no
photo yet. With no tree nearby, "Choose a photo from this phone" is at about 517 pt. With one tree
nearby it is at about 646 pt. That is still on screen, above the pinned Add this tree button, whose
top is at about 696 pt. "Move the pin", the land chips and the species line are below the fold. The
live shutter cannot be seen on a simulator, so its position with a tree nearby is owed on a real
phone (ROADMAP chip 140's note).

### R??? — A tap on a row of the note opens the tree over the add screen (owner's decision, 2026-11-15)

**The question**, asked with AskUserQuestion. A row of the note was wired to `onOpenTree`, which in
`RootView` sets `router.sheet = nil`: the cover that holds the whole visit flow closed, the profile was
pushed onto the app's stack, and Back landed on the map with the photo, the pin and the species lost.

**Offered:** "Keep the draft (Recommended)"; "Rows are not tappable"; "As built".

**Chosen: Keep the draft.** In the owner's words: "The tree's profile opens on top of the add screen.
Back returns to the add screen with the photo, pin, and species still there."

**As built.** The add screen presents the profile over itself (`fullScreenCover(item:)`), so the
screen and its model stay alive under it, and the draft (photo, pin and placement, land answer,
species) is there after Back. A `fullScreenCover` leaves the screen under it in place, so the add
screen's `onDisappear` does not fire when the profile opens and its `.task`s do not run again when it
closes; the second review of 2026-11-15 logged both, and the note kept saying "4 m" for a tree moved
15 m from its profile. So the row's tap calls `VisitAddTreeModel.openListedTree()`, which stops the
camera before the cover goes up, and while it is up `load()` starts nothing. The cover's dismissal
calls `closeListedTree()`, which reads the note again and then starts again what `load()` starts.
`AddTreeNearbyUITests.testAMovedListedTreeShowsItsNewDistanceAfterBack` holds the read on Back. A
simulator has no camera, so that a live session stops under the profile is shown by the code and the
unit test of the gate, not observed. Two capture sessions at once were never observed on a phone;
this closes the path to them. The profile is built by the composition root (`ExistingTreeScreen`, built by
`RootView.existingTreeScreen`) in an `ExistingTreeHost` with **its own `AppRouter`**, because the
profile navigates only through the router in its environment: with the app's router, every push
would land under the visit flow's cover and every sheet would replace that cover. The host draws the
same pushed screens (`destination(for:in:)`) and the same sheets (`presentedSheet(in:)`) as the app's
own stack. The profile's Back closes the host in one move (`AppRouter.closesInsteadOfPoppingLast`).
There was no existing pattern for this: every other way into a profile from a cover closes the cover
first. No string was added.

**What the profile's controls do from there.** Every push (Show me where this is, the photos, Move
pin, check-in, report, the record-defect screen, growth history, activity) goes onto the host's own
stack, and Back from it returns to the profile, then to the add screen. The care log and the share
card open in the host's own cover and close back onto the profile. The profile's Visit opens a whole
visit flow in that cover, over the profile. From there, closing the camera returns to the profile.
Screen 18's "Back to the map" and "Route done · see your grove" call `goToMap()` and `goToTab(_:)` on
the host's router, which has no tabs: they empty its stack and close the host, so the reader lands on
the add screen with the draft, not on the map or the grove. Nothing discards the draft. A flow started
there whose own add screen lists a tree nests a further host the same way.

### R??? — Screen 18's exits inside a visit started from a note-opened profile (owner's decision, 2026-11-15)

**The question**, asked by the orchestrator in a dialog: "On the Add this tree screen, a tap on a tree
in the "ALREADY ON RECORD" note opens that tree's profile over the add screen, and Back returns to
your draft (your earlier choice). If the person starts a visit from that profile and finishes it, the
last visit screen offers "Back to the map" and "Route done · see your grove". As built, both of those
land on the add screen with the draft still there, not on the map or the grove. What should they do?"

**Offered:** "Land on the add screen (Recommended)"; "Go to the map or the grove"; "Hide Visit on that
profile".

**Chosen: Land on the add screen.** As built; no code change.

### R??? — The note shows at 10 m and hides past 15 m (owner's decision, 2026-11-15)

**The question**, asked with AskUserQuestion. A GPS fix drifting across 10 m made the note appear and
disappear, and the form jumped by the card's height (about 129 pt) each time.

**Offered:** "Show at 10 m, hide past 15 m (Recommended)"; "Freeze after the photo"; "Leave it live".

**Chosen: Show at 10 m, hide past 15 m.** In the owner's words: "The note appears when a tree is
within 10 m and goes away only when every listed tree is more than 15 m away. Normal drift no longer
flips it. A listed tree can briefly show a distance of 11 to 15 m under the words 'within 10 m'."

**As built, in the model.** `TreeDraft.proximityNoteKeepRadiusM` is 15, next to the 10 m constant.
`VisitAddTreeModel.listed(_:keeping:)` lists a tree within 10 m, keeps a tree it already listed out to
15 m, and lists nothing else, so the note goes when no listed tree is left. A tree that newly comes
within 10 m joins. The distances shown are the fresh read's. A pin placed by hand gets the same rule
from its new position. The words of the note did not change.

**The orchestrator's reading, 2026-11-15, with no owner question needed.** A pin the reader places by
hand follows the same keep rule as a GPS move, as built: the owner's "Show at 10 m, hide past 15 m"
covers both, because the rule is about where the pin is, not how it got there.

**A known limit.** The read asks for 10 rows out to 15 m, nearest first. In a dense block with ten
or more trees nearer than a listed tree at 10 to 15 m, that tree is not in the answer and drops out of
the note, although it is within 15 m. No code change; recorded so it is not mistaken for a defect.

### R??? — What stays of the proximity conflict on the phone

Nothing. Its one producer was the phone's own refusal, and the service half
(`feat/no-proximity-refusal-server`) no longer sends a candidate list at all; a `conflict` from the
service no longer comes from adding a tree. Among the outbox kinds, only `tree_withdrawal` is answered
with `conflict` now (`server/internal/api/sync.go`); outside the outbox, the account sign-in and the
device claim answer `conflict` for a device already linked to another account
(`server/internal/api/auth.go`). So this change removes `ProximityConflict`, the
outbox's mapping of it to `conflict`, `ProximityConflictDetail` in `RemoteWire.swift`, the two
`GoldenWireFixtureTests` cases that decoded the service's conflict body, the fixture
`proximity_conflict.json` under `server/testdata/` and its row in that folder's README, and
`NearbyTree`'s `Decodable` conformance, which only that body used. A `conflict` from the service is
still handled the general way: not retryable, the item fails at once. Builds already installed
are not affected by any of this.

### R??? — Two deep links for the screen, for the UI tests

`CYPRESS_SCREEN=addTreeNearby` (DEBUG only) opens the Add this tree screen with a photograph already
chosen, on a pinned fix 4 m from a community tree, so a UI test can see the note over an active
button and tap it. Each launch adds that one tree on the first free slot of a line of its own at sea,
40 m apart, the way `movePin` does, so every launch finds exactly one tree under the note however many
earlier runs added theirs. A tap on the button adds one more, 4 m from the slot.

`CYPRESS_SCREEN=addTreeAlone` (DEBUG only) opens the same screen on a spot at sea with nothing on
record within 10 m, so the note is not drawn. It writes nothing, and it reports a failure if a tree is
within 10 m of its spot. These two are `AddTreeNearbyUITests`' entrances.
