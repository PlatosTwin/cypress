# Rulings pending: community trees C1, the adder backfill (owner's rulings, 2026-11-12 and 2026-11-13)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### R??? — Every tree added before v23 gets an adder: from its own add first, then from this installation

**The owner's rulings of 2026-11-12 and 2026-11-13.** They replace the author's pending ruling "Every
tree added before v23 has an adder of nobody" in `community-trees-core.md`.

Migration v23 sets the adder of every community tree already on the phone, and the owner of its root
position, in this order:

1. **From the tree's own `add_tree` outbox row**, when that row still exists (ruling of 2026-11-13,
   "Read add record first"). The row shares the tree's `client_uuid`, and its payload's `attribution`
   is the account (`userID`) or device (`deviceID`) the add was made as. That is also what the
   service recorded as the adder when the row was sent.
2. **Otherwise, from this installation's current owner** (ruling of 2026-11-12): the signed-in
   account (`app_state.current_user_id`) if there is one, else this device (`app_state.device_uuid`).
   This is the value `LocalAPI.addTree` would write for a new tree today.

The owner can then move the pin of a tree they added before the update.

- **Why a backfill is safe at all.** `LocalAPI.addTree` is the only code that has ever inserted into
  `community_trees` (through `CommunityTreeStore.insert`), and before v23 nothing synced another
  person's tree down. So every pre-v23 row was added on this phone. v12 backfilled `photos` on the
  same fact.
- **Why the add row comes first.** A tree added while signed in as an account, followed by a sign-out
  before the update, would otherwise go to the device. The phone would then offer Move pin, and the
  service, which holds the account as the adder, refuses the move with a terminal `forbidden` or
  `not_found` (`isAddedBy`, `server/internal/store/community_trees.go`). The queue would keep a
  permanent red row, and the phone and the service would disagree about where the tree is. The add
  row records the account, so the tree goes to the account and the signed-out phone is not offered
  the move.
- **Only once.** The backfill runs only when v23 first adds the columns. A replay of the migration
  ladder never gives an anonymized tree an owner again.
- **No identity, no owner.** A database with no `device_uuid` has never added a tree. Any row left
  over stays nobody's, which the schema permits.

**What is still wrong, stated rather than hidden.**

- **A pruned add row falls back to a guess, and that is most trees.** `OutboxStore.pruneCompleted`
  deletes a row 24 hours after it is `done` (`OutboxQueue.completedRetention`), so the add row
  survives only for a tree added within a day of the update, or one whose add has not been sent.
  For a tree whose row is gone, the phone cannot read who added it, and the fallback can name the
  wrong owner in the sign-out case above. Then the phone offers a move the service refuses. The phone and
  the service agree only where the add row survived, or where the current owner happens to be the
  one the add was made as.
- **A tree the service never received (R77).** A tree added before the sync path existed was never
  queued, so it has no add row and falls back to the current owner. It gets an adder and shows Move
  pin, but the service has no such tree, and the move is answered with a terminal `not_found`. See
  ROADMAP chip 107 for a proposed rule that would hide Move pin for these trees; it is not built.

Tested in `SchemaV23Tests`: an add row made while signed in, migrated signed out, names the account; an
add row made signed out wins over an account signed in at migration time; a pruned add row falls back
to the device, or to the account signed in at migration time; no identity leaves nobody; and a v22
database with a tree and a pending item of every kind migrates, keeps every item, and lets the owner
move the pin.
