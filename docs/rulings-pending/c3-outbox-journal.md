# Rulings pending: how the C3 round read the owner's pin-move answers for the Outbox and the Journal

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

The owner's answers are in `community-trees-c3-answers.md` (the Move pin and Journal entries) and
`community-trees-answers-2026-11-15.md` (the square on a history row). This entry records the
decisions the building round made where those answers left a detail open. Each is a reading of the
nearest specified thing, not a new design.

### R??? — The Outbox row and the Journal row for a pin move

1. **The Outbox row.** `OutboxCopy.kindLabel(.locationCorrection)` is "Pin moved", so the row is
   "Pin moved · Grandmother Cypress". It has no sub-line; the time follows the title alone, as for
   every other kind with no sub-line. A refused move reads "This couldn't be sent.", which
   `OutboxFailureReason.describe` already gave every terminal non-moderation refusal regardless of
   kind. Nothing changed there; `PinMovedOutboxTests` pins it for `forbidden` and `not_found`.
2. **Which moves are Journal rows.** A row of `tree_locations` that is not the tree's root row (the
   root records the add), that this phone's person wrote (the owner predicate the four other arms
   use), whose tree is not withdrawn (every Journal row opens a profile), and whose key is not
   tombstoned by an account deletion. The row's date is the move's `occurred_at`, the moment the
   person saved it.
3. **No second line in the Journal.** The owner's words are the title, "Moved the pin of X". The
   row's subtitle is empty, so `IconTextRow` draws one line. A distance ("12 m north") was the
   owner's choice for the profile's history rows, not for the Journal, and the Journal has no
   other place that names one.
4. **The square.** The community tree mark (`CommunityTreeTile`) at the Journal row's 34 pt tile
   size and corner. It replaces the tree's photograph too, not only the accent: the row is about
   where the pin is, and the owner chose the mark for this row by name.
5. **The export carries pin moves.** The Journal export is "a copy of everything you have recorded
   on this phone" and is built from the whole journal, so each move is a row of kind `pinMoved`
   with an empty summary. The GeoJSON point is the tree's current position, as for every other
   kind. The add's root row is not exported, because it is not a move.
6. **No migration.** The Journal's fifth arm walks `tree_locations` (it has no index on
   `occurred_at` alone) and hands its rows to the outer sort without sorting them itself. The plan
   gate allows the walk by name, because the table holds only the chains of trees this phone added:
   one root per add and one row per move. That exemption rests on the premise that only this
   phone's own adds and moves write `tree_locations`. It is true today: the cache of other people's
   trees writes only `community_tree_cache` and `community_tree_cache_tiles`.

#### A limit the round found (a fact, not a ruling)

- **After sign-out, pin moves leave the Journal and the export, and visits stay.** Sign-in moves a
  `tree_locations` row to the account (`user_id` set, `device_id` NULL), and visits keep their
  `device_id`. A signed-out phone reads by `device_id`, so it no longer finds the moves. They come
  back at the next sign-in. The review's probe: add a tree signed out, move it, visit it, sign in,
  move and visit again, sign out; the Journal then reads 0 moves and 2 visits.
- The arm has no column that could keep these moves after sign-out without a schema change. The
  owner has not ruled on it. The arm's behavior was not changed.
- **Resolved on 2026-11-16** by `feat/journal-keeps-pin-moves`. The owner chose "Everything, pin
  moves too". Migration v24 adds `tree_locations.set_on_device`, and the fifth arm also matches a
  move this phone set, so the probe above now reads 2 moves and 2 visits. The ruling is
  `journal-keeps-pin-moves.md` in this folder.
