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
  unpublished otherwise. "Accepted" means `license_version = 'odbl-1.0'`, the only version the
  client has ever sent (the orchestrator's L2 ruling). Before this round any string was stored as a
  consent, so a pre-007 row may hold `''`, and that is not an acceptance.
  `TestTheBackfillsAcceptedVersionIsOneTheLivePathAccepts` reads the literal out of the migration
  and requires a live acceptance of it to publish. So once S2's `knownLicenseVersions` is merged,
  the backfill and the live path cannot disagree. This is decision 7 applied to rows that already exist. It is published at
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
- Every published tree gets a `published` event, carrying its root's position, and every tree gets
  an `added` event and a root location. No tree had moved before 007, so the root is the head at
  publication: it is `was_public` exactly when the tree is published. The design wrote a `published` event only where `published_at > created_at`. This PR
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
- **The answers.** The adder, with nobody else's visit or photo on the tree, gets `applied`. The
  adder, with somebody else's on it, gets `conflict`. The adder's own already withdrawn or
  taken-down tree gets `applied` and nothing changes. Anybody else gets `forbidden` for a tree they
  can see (published and not removed, including an anonymized one). A tree they cannot see gets the
  answer an unknown id gets (see "No existence oracle" below).
- **A tree born withdrawn is never published.** When the withdrawal lands first, the late
  `add_tree` stores the tree with no `published_at`, no `published` event, and nothing public in its
  chain or history. It was never visible, so nothing may report it as a removal (review of #190,
  F3).
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
  under the device's credential, because the phone has since signed out, is a stranger's act:
  - if the account published the tree, it gets `forbidden`, which does not retry;
  - if the account declined, the tree is hidden from that credential, so the move gets `not_found`
    and the withdrawal gets `applied` and **changes nothing**.

  So C1 must not queue those acts on a signed-out phone for a tree its account owns.
- A late (older) correction is spliced into the chain between its neighbors, already superseded. Its
  predecessor now points at it, and it points at its successor. It skips the dedupe, and it writes a
  `location_corrected` event whose `before` is its predecessor's position.
- For the adder, a withdrawn or taken-down tree is `not_found`. For anybody else, see "No existence
  oracle" below.

### R??? — No existence oracle in the sync answers

**Decided by:** the orchestrator, after #190's review (F6). A stranger may not learn from an answer
that a tree they cannot see exists. "Cannot see" means: somebody else's tree that is withdrawn,
taken down, or unpublished (a declined account's, or another device's), or one a deletion door
tombstoned. Its account is gone, so nobody is its adder.

A stranger's act on such a tree gets exactly the answer the same act gets on an id this service
never held, with the same status, code and message, and it changes nothing:
- `location_correction` gets `not_found`;
- `tree_withdrawal` gets **`applied`**. The brief said `not_found` here, but an unknown id's
  withdrawal answers `applied`, and it must: that is how a withdrawal that drains before its own
  add is honoured (the arrival-order rule above). A hidden tree answering `not_found` would itself
  be the oracle. So the uniform answer is the unknown id's answer, and for a withdrawal that is
  `applied`.

`add_tree` and the species kinds were already uniform. A tree anybody can see still answers a
stranger `forbidden`.

### R??? — History starts at going live (decision 13), and how it is stored

The owner ruled after #190's review. Others see the tree as added where it stood when it went
public. Positions it held and moves made while it was private stay private: they are never in the
public history, and a tile the tree left while private never reports it. Moves made after it is
public are public (decision 4).

**Representation.** Three columns, each answering a question once, when the fact happens:
- `community_tree_locations.was_public`. The row was, at some moment, the tree's public position.
  That means the head at the moment of publication, or a row that became the head while the tree
  was published. Rows superseded while private are not, and neither is a late correction spliced in
  already superseded, which never moved the pin anybody saw.
- `community_tree_events.in_public_history`. The event is part of the public history.
  - A `published` event always is. It carries the position at publication (`lat`, `lon`,
    `placement`, `location_accuracy_m`) beside `license_version`, and **it is the public record's
    "added"**.
  - An `added` event never is.
  - Every other event is public when it was written while the tree was published, except a
    `location_corrected` that did not move the public pin.
- `withdrawn_community_trees.was_public`. See the tombstone ruling below.

**Why not collapse the private chain at publication.** Collapsing would delete or rewrite the
adder's own acts. The chain is the materialization of contributions, which are append-only
(DECISIONS constraint 7). Under this representation no position, time or actor is ever rewritten,
and nothing is deleted. The one UPDATE is publication turning `was_public` on for the head it
publishes, false to true, once. That is the same set-once shape as `superseded_by`. The adder's
chain stays complete, and the adder's phone keeps its own moves.

**What S2 must serve:**
- **History.** Only events with `in_public_history`. The `published` event is presented as the
  tree's "added", at its `after` position and dated by the day of `published_at`. `added` events
  are never served. Every served `location_corrected` has a `before` and an `after` that were public
  positions.
- **Tile.** The chain arm reads only `community_tree_locations` rows with `was_public`. The position
  arm reads `community_trees` with `published_at IS NOT NULL`: live trees for the snapshot, and
  soft-removed ones for the delta's removals.

**What the tests pin:** `assertPublicationInvariant` checks all of this over the whole database
after every step of every publication test. `TestHistoryStartsAtGoingLive` walks the claim, the
acceptance, the signed-in insert, a public move and a late splice.

### R??? — A tombstone says whether the tree was ever public

**Decided by:** the orchestrator, after #190's review (F2). Decision 12 tombstones an unpublished
tree under both doors. `withdrawn_community_trees.was_public` is written from the tree's own
`published_at`. Nothing unpublishes (decision 10), so a set `published_at` means "was ever public".

**S2 reports a tombstone in `withdrawn_tree_ids` only where `was_public`.** An unpublished tree
removed by either door is never reported to anybody, not even as an id. The tombstone still guards
the id against a late `add_tree`, whatever `was_public` says. A soft-removed tree (withdrawn or
taken down) is once-public exactly when its `published_at` is set, and a tree born withdrawn has
none. The table is new in 007, so there are no rows to backfill. The column has no default, so no
future writer can leave the question unanswered.

### R??? — The tile's indexes (performance precedence)

007 creates one partial index per arm of S2's tile, each on the predicate that arm must carry:

| Arm | Index | Predicate |
|---|---|---|
| Position | `idx_community_trees_public_position` on `community_trees (lat, lon)` | `published_at IS NOT NULL` |
| Chain | `idx_community_tree_locations_public_position` on `community_tree_locations (lat, lon)` | `was_public` |
| Removal list | `idx_withdrawn_community_trees_public` on `withdrawn_community_trees (withdrawn_at, id)` | `was_public` |

The removal list's index replaces the earlier unfiltered time index. The delta's keyset stays
`idx_community_trees_updated (updated_at, id)`. 001's `idx_community_trees_position` stays for the
10 m dedupe, which also sees the caller's own unpublished trees.

`TestTheTileIndexesServeTheirQueries` checks each index against the **generic** plan
(`EXPLAIN (GENERIC_PLAN)`) of its arm's query shape. So S2 writes one query text per arm, with the
arm's predicate spelled literally and no `($n IS NULL OR …)` around the indexed columns.

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

### R??? — A photograph's local capture date (decision 14a, the server's half)

**Decided by:** the owner, decisions 14 and 14a. Other people see a photograph's capture **date**,
never its time. The date is client-assisted, because the server cannot know the phone's time zone,
and the UTC date would put an evening photograph on the wrong day.

- **Column.** 007 adds `photos.captured_on DATE`, nullable.
- **Request.** `POST /photos/begin` accepts an optional **`captured_on`**: the photograph's
  **local** date, exactly `YYYY-MM-DD`.
  - Absent or `null` stores NULL. That is every older build, and it keeps today's behaviour.
  - Anything else must be a real calendar date **within one day of `captured_at`'s UTC date**. UTC
    offsets run from -12 to +14 hours, so a local date is never further off than that. Otherwise the
    answer is `validation_failed`.
  - On an idempotent replay the first begin's value stands, as for every other column.
- **Database backstop.** `photos_captured_on_is_the_captured_day` restates the one-day bound, so no
  writer can skip it.
- **The fixture.** The wire name is pinned by `server/testdata/photos_begin.json`. The Go test posts
  that fixture's bytes unchanged. The fixture is the east-of-UTC case: `captured_at` is
  2026-09-28T23:30:00Z, and `captured_on` is 2026-09-29.

**What C1 must match:**
- Send `captured_on` in the begin body as the photograph's local calendar date, `YYYY-MM-DD`, with
  the key spelled exactly that.
- Encode through production code, and compare against `server/testdata/photos_begin.json`, value
  included.
- **Do not ship it before 007 is deployed.** `decodeBody` refuses unknown fields, so a server
  without this change answers the whole begin `validation_failed`.

**What S2 must match:**
- Serve non-owners the date from `captured_on` where it is set, in the form S2 pins, and never
  `captured_at`'s time.
- Where it is NULL, keep today's behaviour.
- The owner keeps `captured_at`.
