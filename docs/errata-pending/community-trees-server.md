# Errata pending — community trees, found while writing the server half (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". Found by PR S1 (`server/community-trees-007`)
while checking the round's design against the code.

---

### E??? — `RemoteAPI.addTree` would key a community tree on the add's `client_uuid`

`RemoteAPI.addTree` (`Cypress/Data/API/RemoteAPI.swift`) sends `client_uuid: draft.clientUUID`, and
`POST /api/v1/trees` stores that value **as the tree's id** (`addTreeRequest.ClientUUID` becomes
`NewCommunityTree.ID` in `server/internal/api/sync.go`). On the phone, `TreeDraft.clientUUID` is the
key of the *add act*, not the tree. The tree's id is `Tree.id`, which is what `add_tree` sends as
`treeID` and `tree_uuid`. If this path were ever routed, the phone and the service would hold one
tree under two ids, which is the two-identity defect behind F30.

It is not live. `RoutedAPI.addTree` goes to `local`, and nothing calls `RemoteAPI.addTree`
(verified at `bb4d08f`). The design assigns the fix to C1, which should make the method refuse
(`RemoteSurface.noRouteOnThisService`). `POST /trees` itself stays working and is now scoped (below).

### E??? — Account deletion never touched `community_trees`, so the erasing door kept the trees

Before migration 007, `store.DeleteAccount` did not mention `community_trees`. The `users` foreign
key's `ON DELETE SET NULL` therefore left a deleted account's trees standing, with both owner
columns NULL, under **both** doors. That includes `eraseEverything`, which R3 promises deletes
outright. The trees were never served to anybody (no read of other people's community trees
existed), so nothing was shown that should not have been. They were still kept.

007 applies the doors (decision 6). Trees orphaned before 007 are anonymized and left unpublished
(see the rulings file). They are invisible to everybody, and deleting them now is an owner call.
The new `community_trees_owner` CHECK makes the mistake unrepeatable. A deletion that reaches
`DELETE FROM users` without first handling the account's trees is refused, and
`TestDeletingAnAccountTheCodeForgotIsRefused` pins that.

### E??? — The 10 m dedupe saw everybody's unpublished trees, and told strangers where they were

`TreesWithin` read every live `community_trees` row. That had two consequences:

- `POST /trees` returned, as conflict candidates, the exact positions of other devices' trees that
  had never been published.
- A sync `add_tree` could be refused with a bare, non-retryable `conflict` against a tree its sender
  could not see.

Both dedupes are now scoped to trees that are published or owned by the caller (§3F), and
`TestTheDedupeNoLongerSeesAnotherDevicesUnpublishedTree` pins it through both doors.

### E??? — The design's backfill would have published declined accounts' trees

The round's design (§2) gave the backfill as `published_at = updated_at WHERE device_id IS NULL`.
Under decision 7, which came after the design, that publishes every tree whose account declined the
open license. It also publishes the orphans above, whose accounts' consent can no longer be known.
007 publishes only where the owning account has accepted.

The design's `published_at = updated_at` was also wrong about **when**. A tree claimed before its
account accepted would be stamped published before the acceptance, and so would its `published`
event. Under decision 10 that event is the record that the tree was published under an accepted
license. S1's first draft kept `updated_at` and #187's review caught it. 007 now stamps the later of
`updated_at` and `license_accepted_at`.
`TestMigration007BackfillsTheTreesThatAlreadyExist` runs 007 over rows written at 006 and pins all
five cases, including an account that accepted nineteen days after its tree.
`TestMigration007RunsOverEveryKindOfRowProductionHolds` runs it over every contribution kind 005
admits and checks that no publication predates its acceptance.

### E??? — The contribution-kind extractor reads **any** `CHECK (kind IN (` as the contributions vocabulary

`contributionKindsFromMigrations` (`server/internal/api/public_test.go`) takes the last
`CHECK (kind IN (…))` block in the last migration that has one. Nothing ties that block to
`contributions`. 007 creates `community_tree_events`, which has its own `kind` column. A migration
that declared such a CHECK with `IN (…)` **after** the contributions constraint would have the
event vocabulary read as the contribution vocabulary. Nothing would be silently wrong: the guards
would go red (`TestTheLiveSchemaAgreesWithTheMigrationFiles` compares against the live
`contributions` constraint). They would go red about the wrong thing, though, and the next author
would chase a classification that does not exist.

007 spells the event CHECK `= ANY (ARRAY[…])` and says why. The extractor is unchanged; anchoring it
to `contributions` is a roadmap item, not this PR's.
