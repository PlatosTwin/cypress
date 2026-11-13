# Rulings pending: community trees C1, the Move pin control (owner's decision, 2026-11-12)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. Every string below is a draft for the owner to ratify.

---

### R??? — A minimal Move pin control, an exception to constraint 21

**The owner's decision of 2026-11-12.** No mock draws this control. The owner approved it as an
exception to DECISIONS constraint 21, ahead of the full C3 round, so that a reader can fix the pin of
a tree they added (F31(a), F37).

**Where it lives.** On the tree profile (screen 03, and 14 when cold), in the identity block, directly
under "Show me where this is", which is the other control about where the tree is. It is drawn only
when the reader is the tree's adder (`TreeProfile.canMovePin`): a community tree this phone added, not
withdrawn, whose adder is the signed-in account or this device. It is hidden for a city record, for a
cached tree another person added, and for a tree whose adder is nobody.

**What it opens.** A pushed screen built from the add flow's own pin screen (`VisitPinAdjustView`):
the same basemap, the pin drawn at the center while the reader drags the map under it, and the same
four nudge buttons (5 m each). The screen opens centered on the tree's current position. Save writes
the move through `RoutedAPI.correctLocation`: on this phone first, then queued as a
`location_correction`. Cancel, and the header's back control, leave without writing anything.

- **Pin under the center, not a draggable annotation.** The brief asked for "a draggable pin". The
  add flow already rejected a draggable annotation for three reasons (`VisitPinAdjustView.map`), and a
  second, different way to move a pin in one app would be worse than either. Dragging the map moves
  the pin, so the reader still drags.
- **Save and Cancel are plain buttons on a pushed screen**, not a `confirmationDialog`. iOS 26 does
  not draw a dialog's cancel action (ROADMAP chip 77). PR #185 moved its take-back to controls that
  draw on both runtimes for that reason.
- **The move is recorded as placed by hand** (`placement = contributor_placed`), with no accuracy,
  because no instrument measured the new position. The profile's provenance line then reads
  "position placed by hand".

- **A move waits for its tree** (review of #209, F2). The queue holds a `location_correction` while
  the same tree's `add_tree` has not reached the service (`OutboxStore.dueItems`), and the drain that
  sends the add sends the move right after it. Without the hold, a tree added offline and then moved
  could send the move first, and the service's `not_found` for it is terminal.
- **Where the offer is still wrong** (review of #209, F1). A tree the service never received (R77),
  or one whose adder the v23 backfill had to guess, can show Move pin for a move the service refuses.
  ROADMAP chip 107 proposes a rule; it is not built.

### R??? — No distance limit on a pin move, because the service has none

The brief asked to read the limit from the server and enforce the same one. The service has none.
Its `location_correction` handler (`server/internal/api/sync.go`) and
`store.applyLocationCorrection` (`server/internal/store/community_trees.go`) check only that the
position is on the map, that the placement is known, that an accuracy is a distance, and that no
other tree is within the 10 m dedupe radius (`ProximityDedupeRadiusM`). Migration 007 adds no bound
either. So the phone sets no bound, and refuses exactly what the service refuses, through
`LocalAPI.correctLocation`. This matches the author's earlier pending ruling "A pin move has no
distance bound" in `community-trees-core.md`. Whether to add a bound stays the owner's C3 question.

### R??? — The Move pin strings (drafts)

| Where | Draft |
|---|---|
| Profile action | Move pin |
| Screen title | Move pin |
| Placement, before any move | The pin has not moved. |
| Placement, after a move | `<N> m <direction> of where it was.` (whole meters, eight compass directions spelled out) |
| Rule under the placement | Drag the map to put the pin on the tree. A pin cannot be within 10 m of another tree. |
| Nudge label and buttons | Reused from the add flow: "NUDGE THE PIN · 5 M", N/E/S/W, spoken "Move the pin north" and so on |
| Pin's spoken label | Reused: "This tree's pin" |
| Save | Save (disabled until the pin has moved at least 1 m) |
| Cancel | Cancel |
| Return control | Back to where it was |
| Refusal: another tree within 10 m | Another tree is recorded within 10 m of that spot. Move the pin farther from it. |
| Refusal: not the reader's, or gone | This pin can no longer be moved from this phone. |
| Any other failure | The pin could not be moved. Try again. |
| Release note | You can now move the pin of a tree you added: open the tree and choose Move pin. |

Screen 17 still labels a queued move "Location correction", the author's earlier provisional label in
`community-trees-core.md`.
