# The heart that called its own save undone (#167, after #139 and #153)

**Unnumbered — pending splice by the orchestrator.**

Owner field report, 2026-08-01, physical phone, third report of the same behavior: tap Favorite,
the cell goes dark green, and about two seconds later it goes back to white — "it makes the user
think their favoriting action got undone." #139 fixed copy beside the heart and #153 fixed the
selected appearance; neither touched the revert, so the defect survived both.

## The seam

The write path is local-first by design (ARCHITECTURE §4): a favorite is **durable at enqueue**
— `FavoriteOutboxWriter.save` writes the toggle to the outbox and only then drains — and
**applied at drain**, and the drain that follows a save is explicitly best-effort. Two of its
designed exits return without applying the just-saved toggle:

- `OutboxQueue.drain` returns an empty report immediately when another drain holds `isDraining`
  (a visit's photo phase still running when the finger reaches the heart);
- one drain pass attempts one batch of `OutboxQueue.batchSize` (25) due items, oldest first, so a
  queue holding a batch's worth of older due work leaves item 26 — the tap — `pending`.

`TreeProfileModel.write()` then re-reads "the store" (RULINGS R2: the cell shows what is stored,
and a failed write must be visible as the heart going back) — but the re-read was
`api.grove()`, which sees **applied rows only**. A toggle that was safely queued and not yet
applied read back as "no favorite", the model assigned it, and the heart went off over a row
that landed on the next drain. The revert R2 reserves for a failed write was being performed for
a successful one. The ~2 s is the width of the save-plus-re-read, most of it `grove()` resolving
every held tree through `treeIfPresent` to answer one membership bit.

## The fix

"What is stored" now includes the queue's in-flight word. The re-read the composition root hands
the profile (`ProfileFavoriteWriter.storedState`) asks two questions in order:

1. `OutboxQueue.pendingFavoriteState(treeID:)` — the newest `pending`/`uploading` favorite
   toggle for the tree, which is the contributor's last durable word. A terminally `failed`
   toggle deliberately answers nothing here, so a write the queue has given up on still shows as
   the heart going back — R2's one required revert, kept.
2. Failing that, `CypressAPI.isFavorite(treeID:)` — the new per-tree arm of `GET /me/grove`
   (the pre-approved backend-boundary change), which `LocalAPI` answers with one indexed SELECT
   over both ownership arms instead of resolving the whole grove.

Pinned by `CypressTests/FavoriteRoundTripTests.swift`:
`aQueuedFavoriteIsNotReportedUndone` (a batch's worth of older work queued first; the tapped
toggle is verifiably still `pending` at re-read time and the heart must hold) and
`aFailedToggleDoesNotHoldTheHeartOn` (the terminal-failure counterpart).
