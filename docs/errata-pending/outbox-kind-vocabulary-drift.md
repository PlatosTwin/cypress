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
