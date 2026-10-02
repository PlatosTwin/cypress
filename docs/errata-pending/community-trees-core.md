# Errata pending — community trees C1, found while building the client core (2026-10-01)

Unnumbered, per CLAUDE.md "Numbering and shared files". Found by `feat/community-trees-core`. No code
comment cites this filename.

---

### E??? — `RemoteAPI.addTree` would have keyed the tree on the act's `client_uuid`, not on `Tree.id`

`RemoteAPI.addTree` sent `POST /trees`, which stores the tree under the request's `client_uuid` and
answers `{id, status}`; the method then returned a `Tree` built from the draft with a **fresh**
`Tree.id`. Had anything called it, the phone's tree and the service's would have had two ids — the
one double the one-id rule (`CommunityLayer`'s header) exists to forbid. Nothing shipped reached it,
because §3.4 routes `addTree` local and the add reaches the account through `/sync` as `add_tree`,
carrying `treeID`. It was a trap, not a live defect.

Neutralized in C1: `RemoteAPI.addTree` throws `RemoteSurface.noRouteOnThisService`, and the allow-list
in `RemoteAPITests.theRemoteSurfaceIsConfinedToItsRefusals` names it. `AddTreeBody` and
`AddTreeResponse` are deleted with it. `RemoteAPITests.addTreeHasNoRoute` asserts no request is sent.

### E??? — Comments that said `community_trees` "records no author" were false after v23, and two were already narrower than the truth

R45 recorded that the table had no `user_id` or `device_id`; `AppSchema` v23 adds both. Re-verified one
by one rather than trusting the ROADMAP sentence: `TreeProfilePresentation` (two comments),
`RecordDefect.underReview`, `LocalAPI.withdrawRecord`, `SpeciesAssertion.isSupersedable`,
`AccountDeletion` (two comments), `AccountDeletionTests` and `SpeciesClaimTests` were rewritten. The
"a contributor, not the contributor" copy is still right, for a different reason: the species' namer
need not be the adder, and the service sends no actor on somebody else's tree (decision 4).
Left alone, deliberately: v12 and v14's historical migration comments (true when written, and `applyV23`
supersedes them in its own text), and every "nothing syncs anybody else's *photographs* down" comment —
`main.photos` is unchanged and that sentence is still true. The sentence that **was** false is "nothing
syncs anyone else's *trees* down", and the only place it was written is `CommunityTreeStore`'s old header.

### E??? — The leaving door anonymizes every community tree on the phone; the service deletes the unpublished ones (decision 12)

Decision 12: an unpublished tree is deleted and tombstoned under both doors, `leaveRecords` included.
Publication is the service's fact (it turns on the license the account held when the tree went live,
decisions 7 and 10), and the phone does not hold it this round. `AccountDeletion.forgetCommunityTrees`
therefore anonymizes every tree the account added under `leaveRecords` and the service deletes the
ones that were never public. The phone keeps a pin the service has dropped until the sync-down round
can tell it otherwise. Visible only to the account's own phone, and only after it has left. Closing it
is C2's: the tile's withdrawn-ids list is what would drop the stale row.

### E??? — `captured_on` is the date in the phone's zone when the begin is built, not when the shutter fired

Nothing on `photos` or the outbox records the zone of the capture, so `RemoteAPI.beginPhotoBody` reads
`TimeZone.current` at send time. A photograph queued in one zone and sent after a flight is dated in
the second. The service's one-day bound (`validCapturedOn`) holds for every civil zone either way.
Recording the capture zone is a schema change and was not made here.
