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
Each row opens its tree's profile over the add screen (the owner's decision below, "Keep the draft"). The Add this tree button does not read the list: it stays active, and one
tap adds the tree. A read that fails shows no note rather than an error, because the note is advice
and the add does not depend on it.

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
species, and the note) is there after Back. The camera stops while the profile is up and starts
again on return. The profile is built by the composition root (`ExistingTreeScreen`, built by
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
