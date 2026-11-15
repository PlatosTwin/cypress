# Rulings pending: how the phone builds "a note, then still add" (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. These are the author's build choices for the owner's ruling of
2026-11-14 (`community-trees-no-proximity-rule.md`); none of them adds a string or a screen state.

---

### R??? — The Add this tree screen looks the nearby trees up itself, before the tap

**Before.** The screen learned about a nearby tree only when `addTree` threw its proximity conflict
after the tap, and drew the conflict's candidate list as a refusal.

**Now.** `addTree` does not refuse on distance, so there is nothing to throw. The screen reads the
list itself: `VisitAddTreeModel.refreshNearby` calls `treesNear` at `TreeDraft.proximityDedupeRadiusM`
(10 m, limit 10) around the coordinate the tree would be added at. That is the query and the
exact-meters circle the refusal used, over the seed and the whole community layer, other people's
cached trees included. The view runs it when the coordinate first becomes known and again whenever
it changes (`.task(id: model.coordinate)`): a moving GPS fix while the pin is the GPS, and a pin the
reader placed. The answer is dropped when the position moved while it was read, and once an add is
under way.

**What the reader sees.** The same "ALREADY ON RECORD" card, at the top of the scrolling form, above
the photo (the owner's decision below), with the owner's two sentences and the same list of trees,
each row opening its tree. The Add this tree button does not read the list: it stays active, and one
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

### R??? — What stays of the proximity conflict on the phone

Nothing. Its one producer was the phone's own refusal, and the service half
(`feat/no-proximity-refusal-server`) no longer sends a candidate list at all; a `conflict` from the
service now comes only from `tree_withdrawal`. So this change removes `ProximityConflict`, the
outbox's mapping of it to `conflict`, `ProximityConflictDetail` in `RemoteWire.swift`, the two
`GoldenWireFixtureTests` cases that decoded the service's conflict body, the fixture
`proximity_conflict.json` under `server/testdata/` and its row in that folder's README, and
`NearbyTree`'s `Decodable` conformance, which only that body used. A `conflict` from the service is
still handled the general way: not retryable, the item fails at once. Builds already installed
are not affected by any of this.

### R??? — A deep link for the screen, for the UI test

`CYPRESS_SCREEN=addTreeNearby` (DEBUG only) opens the Add this tree screen on a pinned fix 4 m from a
community tree it adds at its own spot at sea, with a photograph already chosen, so a UI test can see
the note over an active button and tap it. It writes: one tree at its spot on the first launch, and
one more for each tap. It is `AddTreeNearbyUITests`' only entrance.
