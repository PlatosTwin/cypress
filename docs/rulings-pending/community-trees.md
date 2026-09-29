# Rulings pending — community trees, the server half (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. No code comment cites this filename: the server comments name the owner's
decisions by number and date ("decision 7", "the orchestrator's ruling of 2026-09-28") and the
migration by its file.

The owner's decisions 1–12 and the orchestrator's rulings of 2026-09-28 are the round's; this file
records what **PR S1** (`server/community-trees-007`, migration 007) decided in applying them, where
the decisions and the design left a choice. Each is a ruling within delegated authority and is
logged for review; none reverses an existing ruling. Decision 10 (the license is one-way) was the
owner's answer to the question S1's first draft raised here, and the entries below are written to
it.

---

### R??? — A community tree is published only at a moment its account had accepted the license

**Decided by:** PR S1, applying decisions 7 and 10. **Replaces** the design's constraint
`community_trees_live_iff_not_device_owned`, which decision 7 makes false (an account-owned tree can
now be unpublished).

1. `published_at IS NOT NULL` implies `device_id IS NULL`. A CHECK
   (`community_trees_published_is_not_device_owned`).
2. A tree is published only at a moment its owning account had accepted the license. Decision 10
   makes this a fact about the moment of publication, not about the account's current answer, and
   `users` keeps only the current answer. So **every `published` event records the version
   accepted at that moment** in `after.license_version`, and `published_at` equals that event's
   `occurred_at`. It is kept in code by the only three writers of `published_at` (a signed-in
   insert, the claim, and license acceptance). Each reads the account's answer with `FOR SHARE`, so
   an acceptance cannot commit between an insert's read of "declined" and its commit: the
   acceptance waits, and its publish sweep then sees the tree. The test
   `TestEveryPublicationHappenedUnderAnAcceptedLicense` walks every path. After each step it checks
   the record, and it checks a model of its own that knows from the outside when the account had
   accepted.
3. The owner rule is `contributions_owner`'s: exactly one owner, or none with `anonymized_at` set
   (`community_trees_owner`). This makes a forgotten step in account deletion fail loudly: the
   `users` foreign key's `ON DELETE SET NULL` on a tree nobody anonymized first is refused, and the
   whole deletion rolls back.

### R??? — A later decline leaves published trees published (decision 10, applied)

**Decided by:** the owner's decision 10, which answered the question S1's first draft left here.
The case is reachable: screen 15 sends the license answer on every sign-in, so signing out and back
in with the box clear records a decline.

**Ruling:** a decline changes no tree. Trees published under the earlier acceptance stay published
and their history gains nothing. A tree added while the decline stands stays private, and the next
acceptance publishes it. Nothing ever unpublishes a tree now. So the event kind `unpublished` has
no writer, and 007 does not admit it (see "Event kinds" below).

### R??? — What 007 does with trees that already exist

- **An account's tree** is published if the account has accepted the license, and is left
  unpublished otherwise. This is decision 7 applied to rows that already exist. It is published at
  the **later** of its `updated_at` and the account's `license_accepted_at`. `updated_at` is the
  moment the tree became the account's: before 007, the only writers of that column were insert and
  claim. A tree claimed on 1 September by an account that accepted on 20 September went live on the
  20th. `license_accepted_at` is the most recent acceptance, which can only make the stamp later
  than the true first one, never earlier. Its `published` event carries the account's current
  version, as every `published` event carries the version accepted.
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
  unless another identity has met it (a visit or a photo, as defined below), in which case it is
  anonymized.
- **An unpublished tree** (its account declined the license) is **deleted and tombstoned under
  both doors.** Nobody but its adder ever saw it. Anonymized, it would be a row that no account
  could ever publish, move, withdraw or erase.
- Actor columns on the location chain and the audit log are nulled for the account **and for
  every device it claimed** before `devices.user_id` is cleared.

### R??? — "Somebody else has built on it" means a visit or a photo (decisions 6 and 8)

**Decided by:** the orchestrator, after #187's fix round. It **supersedes** S1's first definition,
which counted every live contribution except the withdrawal kinds. The owner's own words for
decisions 6 and 8 were "if anyone else has a visit or photo on the tree", and the code now holds
to them. A tree counts as built on when another identity has either of these:

- a live contribution of a **met kind**: `visit`, `observation`, `measurement` or `care_event`.
  This is the set #184 names `MetSpeciesKinds`, and S1 keeps its own copy (`builtOnKinds`) until
  the two unify at merge. "Live" means not deleted, so a measurement its taker withdrew does not
  count;
- a live photograph: not deleted, not `rejected`, and **its bytes have arrived**
  (`bytes_received_at` set). A begun upload with no bytes is a reservation nobody can see (the
  orchestrator's ruling after #187's review).

Favorites, photo votes, private reminders, species claims and corrections, reports, disputes, and
review dismissals do **not** count, and neither does a hazard redirect. The first definition
needed extra rules to pair a dispute with its withdrawal and to handle toggles that had been turned
off. Those rules go with it.

An anonymized row still counts. It is somebody's visit or photo with the name taken off.

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
- A correction whose `id` **is its `treeID`** gets `validation_failed`. The chain's root row
  carries the tree's id, so without this check it would read as the replay above and answer
  `applied` for a move that never happened. This is the drift §3A warns against: the tree pointer
  sent as `id`.
- **After a claim, the device's own credential is a stranger to the device's trees.** A tree a
  device added signed out becomes the account's at the claim. A move or a withdrawal of it sent
  under the device's credential (the phone has since signed out) gets `forbidden`, which does not
  retry. So C1 must not queue those acts on a signed-out phone for a tree its account owns.
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

`community_tree_events.kind` also admits `withdrawn` and `taken_down`. The first draft also admitted
`unpublished`. Decision 10 left it with no writer, so it is gone from the CHECK and no row carries
it. S2 need not handle it.
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
