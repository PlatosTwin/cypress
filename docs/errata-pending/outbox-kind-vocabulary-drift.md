### The `outbox.kind` vocabulary is written out by hand in six places, and one of them under-deleted

Found while landing spec §3.4's nine mutations into the queue (the round that adds `AppSchema` v17
and `server/migrations/002_community_mutation_kinds.sql`). Neither half of this shipped as a defect
— the kinds did not exist before the round — but the second half is a rule about a *shape*, and the
shape is still there for the next kind.

**Where the vocabulary lives.** `OutboxItem.Kind` is the only place a compiler can check it. The
same list is then restated, as SQL string literals with no link to the enum, in:

1. `AppSchema` v17's `CHECK (kind IN (…))` — the client's stored vocabulary;
2. `OutboxStore.forgetAccount`'s `kind IN (…)` — which kinds an account deletion sweeps;
3. `server/migrations/002_…sql` — the service's `contributions.kind` CHECK;
4. `sync.go`'s `syncKinds` map — which kinds `POST /sync` accepts;
5. `OutboxCopy.kindLabel` — the only one the compiler *does* check, because it switches on the enum.

Adding a case to the enum compiles against four of those five. `CommunityOutboxKindTests`'
`theStoredVocabularyCoversEveryKind` iterates `Kind.allCases` against the real table, which closes
(1); `TestEveryCommunityKindIsAcceptedAndRecorded` is a table of ten and closes (3) and (4) only for
the ten it lists. **(2) has no such test and is the one that was wrong.**

**The under-deletion.** `forgetAccount` matched a contribution to an account with
`json_extract(payload, '$.userID')`. That is right for the four original append-only kinds, whose
payloads flatten `Attribution` into top-level `userID` + `deviceID`. §3.4's ten carry the
`Attribution` as an **object**, so the account sits at `$.attribution.userID` and the old predicate
matched none of them — `json_extract` answers NULL for a path that is not there, so the rows were
silently skipped rather than erroring.

The consequence is RULINGS **R3**'s stated failure mode: a signed-in contributor's queued species
correction, photo withdrawal, review dismissal or hazard redirect would have survived their own
account deletion still naming the account, drained to the service afterwards, and been recorded
against an account that had asked to be gone. Under `leaveRecords` it would also have gone
untombstoned, so the service would have accepted it rather than answering `duplicate`. Every layer
reports success throughout.

**The rule.** A new `OutboxItem.Kind` is not landed until its row has been followed through
`forgetAccount` under **both** doors, with an assertion that reads the payload back. "It is a
contribution like a visit" is not enough — the payload shape is what the SQL matches on, and two
shapes are already in the table.

Fixed in the same round: `forgetAccount` names both shapes, and
`CommunityOutboxKindTests.deletionReachesTheNewKinds` reads the account back out of an anonymized
payload and checks the tombstone. Red-proved by restoring the single-shape predicate — the deletion
then reported 0 anonymized rows and the payload still named the account.

### `addTree` gives a community tree two different ids depending on which implementation runs

Latent, and found by the same round rather than caused by it.

`LocalAPI.addTree` mints a fresh `Tree` — so `tree.id` is a new UUID — and stores `TreeDraft.
clientUUID` beside it in `community_trees.client_uuid`. Every later record about the tree keys on
`tree.id`. `RemoteAPI.addTree` sends `draft.clientUUID` as `POST /trees`' `client_uuid`, and the
service uses that value **as the tree's primary key** (`community_trees.id` in `001_initial.sql`,
whose own comment argues at length that there must be exactly one identity for a community tree).
It then returns `Tree(id: response.id, …)`.

So one `TreeDraft` through the two implementations produces two `Tree.id`s, and the id the service
holds is not the id the phone holds. Nothing ships on that path today — `RoutedAPI.addTree` routes
to `local` and the shipping build never calls `POST /trees` — which is why this has cost nothing so
far.

The `add_tree` sync path added by this round deliberately keys on **`tree.id`**, carried in the
payload as `TreeAddition.treeID` and checked against the item's `tree_uuid`, so that
`contributions.tree_uuid`, `photos.tree_uuid` and `community_trees.id` all name the same tree. That
is the correct half. `POST /trees` and `RemoteAPI.addTree` are the half still to be reconciled, and
reconciling them is not this round's ticket: it changes a shipped route's contract.

### `photo_withdrawal` is the one deferral in this round the service could have honored, and the deferral is invisible from the client

Raised by the adversarial review of the round above, and correcting a comment that had already been
written three times over.

The justification given for recording nine of the ten new kinds without materializing them was
"tables this service does not have and moderation rules it cannot evaluate." That is true of eight.
It is **false for `photo_withdrawal`**, and the service has every piece:

- the table — `photos`, in `server/migrations/001_initial.sql`, read by `store.PhotosForTree` into
  every `GET /trees/{id}`;
- the store method — `Store.DeletePhotoByContributor(ctx, id, owner)`, which takes exactly the
  `owner` the sync handler already holds;
- the route — `DELETE /photos/{id}`, whose own header cites RULINGS **R72** ruling 5 and ERRATA
  **E147**: *"the person who took it has to be able to take it back."*

**The real reason it is deferred is that no photograph reaches the service at all.**
`OutboxSendSink` carries no photo method, by an argument stated on that protocol, and the apply
sink's `uploadPhoto` is `APIOutboxTransport` over `LocalAPI` — a move inside the app container. A
withdrawal sent today would name bytes this service has never held. Wiring the upload and wiring
this deletion are one round.

**The risk this leaves, which is why it is written down rather than left in a comment.** The moment
photo upload is wired, this path is *already wrong and already says otherwise*. A `photo_withdrawal`
item drains, is inserted into `contributions`, is answered `applied`, reaches `done`, and screen 17
draws "Photo removed" in the synced section — while `GET /photos/{id}` keeps serving the bytes and
every other device on the account keeps drawing the photograph. This project's signature failure
mode, applied to a deletion, on a surface that has already told the person it is gone.

What makes it likely to be missed is that **no test asserts anything about a `photo_withdrawal`
reaching the service, in either direction** — not that it deletes, and not that it deliberately does
not. A round that wires photo upload will be reading `syncKinds`' comment, not this file, which is
why the comment now names the route that will perform it instead of claiming the service could not.

**The rule.** The round that gives the send sink a photo method wires `DeletePhotoByContributor`
into the `add_tree`-style arm in the same change, with a test in each direction. Until then,
`photo_withdrawal` is a recorded act and the client must not be read as claiming the photograph is
gone anywhere but on the phone.

### A sync-path `add_tree` refused by the proximity dedupe is lossy, not merely unresolvable

Sharpened by the same review, against the round's own open question.

`applyOne` answers `failed(apierr.Conflict, …)` **before** `Store.Apply` runs, so a refused
`add_tree` leaves **no `contributions` row at all** — the service has no record that anybody tried
to add a tree there. `conflict` is non-retryable, so `OutboxRetryPolicy` moves the row straight to
`failed` and screen 17 shows a terminal red row. The tree stays on the contributor's phone, local
only, for ever, and there is nothing server-side to reconcile it against later.

This is a stronger statement than "the candidate list has nowhere to travel in a per-item verdict",
which was the round's original framing. The candidate list is a UI problem. The missing row is a
data-loss shape: the option "accept the duplicate and reconcile in moderation" cannot be taken later
by a service that never recorded the attempt.

The three options, for whoever rules on this:

1. carry the candidates in the item verdict, so screen 17 can offer the resolution sheet `POST /trees`
   offers;
2. record the contribution **even on the refusal path**, so a later moderation pass has something to
   reconcile, and answer `conflict` beside it;
3. leave it, and accept that a tree added within 10 m of somebody else's is a phone-only tree.

Related and separate: `CommunityTreeExists` and `TreesWithin` run on the pool, outside the `Apply`
transaction, so the dedupe is **advisory under concurrency** — two requests carrying `add_tree`
items within 10 m of each other can both read "no candidates" and both materialize. That is
`POST /trees`' own shape reproduced faithfully rather than something new, and within one batch it
cannot happen, because `applyOne` is sequential and each `Apply` commits before the next item's
proximity read. `TestAddTreeThroughSyncStillRunsTheProximityDedupe` is a real guard and must not be
read as proof of an invariant it does not hold.
