# Rulings pending: community trees C1, the adder backfill (owner's ruling, 2026-11-12)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### R??? — Every tree added before v23 belongs to this installation's own owner

**The owner's ruling of 2026-11-12.** It replaces the author's pending ruling "Every tree added before
v23 has an adder of nobody" in `community-trees-core.md`.

Migration v23 sets the adder of every community tree already on the phone, and the owner of its root
position, to the same value `LocalAPI.addTree` writes for a new tree: the signed-in account
(`app_state.current_user_id`) when there is one, and this device (`app_state.device_uuid`) when there
is not. The owner can then move the pin of a tree they added before the update.

- **Why it is safe.** `LocalAPI.addTree` is the only code that has ever inserted into
  `community_trees` (through `CommunityTreeStore.insert`), and before v23 nothing synced another
  person's tree down. So every pre-v23 row was added on this phone. v12 backfilled `photos` on the
  same fact.
- **It matches the service.** The service's `community_trees` has recorded the adder since migration
  001, and its migration 007 gave each tree's root position that adder.
- **What it can get wrong.** A tree added while one account was signed in, followed by a sign-out
  before the update, goes to the device. The next account that signs in on this phone adopts it
  through `claimDevice`. This is the over-attribution ERRATA E136 already records for visits.
- **Only once.** The backfill runs only when v23 first adds the columns. A replay of the migration
  ladder never gives an anonymized tree an owner again.
- **No identity, no owner.** A database with no `device_uuid` has never added a tree. Any row left
  over stays nobody's, which the schema permits.

Tested in `SchemaV23Tests`: the device case, the signed-in case, the no-identity case, and a v22
database with a tree and a pending item of every kind that migrates, keeps every item, and lets the
owner move the pin.
