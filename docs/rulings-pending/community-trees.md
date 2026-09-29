# Rulings pending — community trees, the server half (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. No code comment cites this filename: the server comments name the owner's
decisions by number and date ("decision 7", "the orchestrator's ruling of 2026-09-28") and the
migration by its file.

The owner's decisions 1–9 and the orchestrator's rulings of 2026-09-28 are the round's; this file
records what **PR S1** (`server/community-trees-007`, migration 007) decided in applying them, where
the decisions and the design left a choice. Each is a ruling within delegated authority and is
logged for review; none reverses an existing ruling.

---

### R??? — A published community tree belongs to an account that accepted the license, or to nobody

**Decided by:** PR S1, applying decision 7. **Replaces** the design's constraint
`community_trees_live_iff_not_device_owned`, which decision 7 makes false (an account-owned tree can
now be unpublished).

1. `published_at IS NOT NULL` implies `device_id IS NULL`. A CHECK
   (`community_trees_published_is_not_device_owned`).
2. A published tree's account has accepted the license (`users.license_version IS NOT NULL`), or
   the tree is anonymized. It spans two tables, so it is kept in code by the only four writers of
   `published_at`: a signed-in insert, the claim, license acceptance, and license decline. The test
   `TestNoPublishedTreeBelongsToAnAccountThatDeclined` walks every path and checks the whole table
   after each.
3. The owner rule is `contributions_owner`'s: exactly one owner, or none with `anonymized_at` set
   (`community_trees_owner`). This makes a forgotten step in account deletion fail loudly: the
   `users` foreign key's `ON DELETE SET NULL` on a tree nobody anonymized first is refused, and the
   whole deletion rolls back.

### R??? — Declining the license after accepting it takes the account's trees back off the map

**Decided by:** PR S1. Decision 7 says what happens when an account declines, and when it later
accepts. It does not say what happens when an account that accepted later declines. That is
reachable: screen 15 sends the license answer on every sign-in, so signing out and back in with the
box clear records a decline.

**Ruling:** a decline unpublishes every tree the account owns (anonymized trees have no account and
are untouched) and writes an `unpublished` event for each. A later acceptance publishes them again.
This is the only reading under which R???'s invariant holds.

**For the owner:** open licenses are usually irrevocable for work already published. If the owner
reads decision 7 that way, the alternative is to keep published trees published on a later decline
and to weaken the invariant to "accepted at the time of publication". That is one function
(`unpublishAccountTrees`) and one test to change.

### R??? — What 007 does with trees that already exist

- **An account's tree** is published at its `updated_at` if the account has accepted the license,
  and is left unpublished otherwise. `updated_at` is the moment it went live: before 007, the only
  writers of that column were insert and claim. This is decision 7 applied to rows that already
  exist.
- **A device's tree** stays unpublished (decision 1).
- **An orphan** is a tree whose account was deleted. Before 007, deletion never touched
  `community_trees`, so the foreign key left both owners NULL under **both** doors. An orphan is
  anonymized and left **unpublished**. Its account is gone, so whether that account accepted the
  license cannot be known. It may also have chosen to erase everything. Publishing it now would
  decide both questions for somebody who can no longer be asked. It is visible to nobody, so it is
  inert. Deleting it instead would be an owner call.
- Every published tree gets a `published` event, and every tree gets an `added` event and a root
  location. The design wrote a `published` event only where `published_at > created_at`. This PR
  writes one for every publication, backfilled or live, because decision 4's history should not
  depend on how the publication happened.

### R??? — The two deletion doors, for trees

Decision 6, applied, plus one case it does not name:

- **`leaveRecords`**: a published tree the account added is anonymized. It stays published, and
  nobody may move or withdraw it afterwards.
- **`eraseEverything`**: a published tree is deleted and tombstoned (`withdrawn_community_trees`),
  unless another identity has a live contribution or photograph on it, in which case it is
  anonymized.
- **An unpublished tree** (its account declined the license) is **deleted and tombstoned under
  both doors.** Nobody but its adder ever saw it. Anonymized, it would be a row that no account
  could ever publish, move, withdraw or erase.
- Actor columns on the location chain and the audit log are nulled for the account **and for
  every device it claimed** before `devices.user_id` is cleared.

### R??? — "Somebody else has built on it" (decisions 6 and 8)

This means another identity has a **live contribution or photograph** on the tree:

- A contribution counts when it is not deleted and is not a removal. The four withdrawal kinds
  (`photo_withdrawal`, `measurement_withdrawal`, `data_dispute_withdrawal`, `tree_withdrawal`) are
  somebody taking their own work back, not work anchored to the tree.
- A photograph counts when it is not deleted and not `rejected`.
- An anonymized row counts. It is somebody's work with the name taken off.
- Every other kind counts, including a stranger's favorite and private reminder.

### R??? — The adder's withdrawal: kind `tree_withdrawal`, soft, and arrival-order safe

Decision 8's new verb travels as outbox kind **`tree_withdrawal`**. Its payload is
`{"clientUUID","treeID","attribution","occurredAt"}`, and `treeID` must equal `tree_uuid`.

- **Soft, through `deleted_at`, not delete-and-tombstone.** The act must write a `withdrawn` event.
  Events cascade from the tree, so a hard delete would remove the record of the withdrawal along
  with the tree. Every existing read of community trees already filters `deleted_at` (the dedupe,
  `MapMembership`). S2's tile delta reports it as withdrawn, the same way it reports a tombstone.
- **The answers.** The adder, with nobody else's work on the tree, gets `applied`. The adder, with
  somebody else's work on it, gets `conflict`. Anybody else, or anybody once the tree is
  anonymized, gets `forbidden`. An erased (tombstoned) tree gets `not_found`. An already withdrawn
  or taken-down tree gets `applied` and nothing changes.
- **A tree this service never received** gets `applied` and nothing changes, and its later
  `add_tree` from the same owner arrives already withdrawn. The outbox drains only what is due, so
  a withdrawal can land before an add that is in backoff. This is the ordering
  `measurementWasWithdrawn` handles for readings.
- The adder's own contributions and photographs on the tree are **not** withdrawn with it.

### R??? — The operator takedown route for community trees

`POST /api/v1/operator/community-trees/{id}/take-down`. It sits behind `Server.operator`, the same
wrapper as `POST /operator/photos/{id}/reject`, with no new authentication scheme. It sets
`deleted_at` and writes a `taken_down` event with no actor. It is idempotent. An unknown id gets
`not_found`.

### R??? — `location_correction`: the details §3A left open

- A correction whose `id` is already a chain row **on the same tree** is the same act queued twice
  under two item keys. It gets `applied` and nothing changes. The same `id` on a **different** tree
  gets `validation_failed`.
- A late (older) correction is spliced into the chain between its neighbors, already superseded. Its
  predecessor now points at it, and it points at its successor. It skips the dedupe, and it writes a
  `location_corrected` event whose `before` is its predecessor's position.
- Authority is checked before existence for a live tree. The one exception is a withdrawn tree: it
  is `not_found` to its adder and `forbidden` to everybody else.

### R??? — Species arm 1: what "applies" means on the server

`species_claim` names the tree only while its species is NULL. `species_correction` applies unless
a species event newer than it (by `occurred_at`) has already been applied. In that case the
correction is recorded and changes nothing. A statement whose payload does not decode, names
another tree, or names no species is recorded exactly as before 007. None of these paths is ever
refused.

### R??? — Event kinds beyond the design's five

`community_tree_events.kind` also admits `unpublished` (R??? above), `withdrawn` and `taken_down`.
S2's `/history` decodes `kind` tolerantly (design §3E), so an old client meets these as `unknown`.
Which of them the history list shows is C3's question for the owner.

### R??? — The session's device: bound at `/auth/oidc`, not at `/devices/claim`

`sessions.device_id` is set only by `POST /auth/oidc` when the request names a `device_uuid`, and
`POST /auth/refresh` carries it to each successor session. `POST /devices/claim` does not rebind a
session. It claims the device named in the body, which the session has not proved, so a session
minted without a device stays unbound and its acts record no device. Signed-in acts record the
session's device, never the item's `device_id` claim.

### R??? — `add_tree` may carry the fix's accuracy

`TreeAddition` may add an optional `locationAccuracyM` (D6). The service stores it on the root
location and the tree's cache. When it is absent, both are NULL. A negative value gets
`validation_failed`. Nothing requires C1 to send it.
