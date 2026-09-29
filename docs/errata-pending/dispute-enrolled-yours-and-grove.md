# Errata pending — a dispute enrolled its tree in Yours and the Grove (server, 2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". One entry, fixed in the same round that
found it (`server/disputes-dont-enroll`). Found by PR #185's adversarial reviewer against the
dispute-sheet client, finding 1 of `review-185-comment.md`, and confirmed on a Go harness.

---

### E??? — Reporting a mistake in a tree's record enrolled that tree as "yours," and stayed enrolled after the report was withdrawn

`store.Grove`'s `mine` CTE and `store.MapMembership`'s `yours` arm
(`server/internal/store/reads.go`) filtered `contributions` on `kind <> 'private_reminder'` and
nothing else. `data_dispute` and `data_dispute_withdrawal` are ordinary kinds in that table (R79,
`005_data_dispute_kinds.sql`), so neither filter excluded them:

- Raising a dispute against a city tree put that tree into `GET /me/grove` (with an all-zero
  tally) and into `GET /me/map-membership?kind=yours` the moment the item synced.
- Withdrawing the dispute did not remove it — the withdrawal is itself a `contributions` row of a
  different kind, and nothing tombstones the raise (by design; see the `data_dispute` paragraph
  beside `syncKinds` in `server/internal/api/sync.go` — there is no dispute table, so the
  `contributions` row is the whole record).

**Why this is a defect and not a judgment call.** R79's dispute sheet ships the sentence "Nothing
on the map changes" as its own disclosure. A reader who reports a tree's species as wrong, then
watches that tree join their map's *Yours* filter — having never visited it, added it, or done
anything else the product calls meeting a tree — is being told something false by the client on
the strength of a server contract nobody had checked against that sentence. Owner ruling,
2026-09-28: a report is not meeting the tree.

**Reproduced against a throwaway Postgres 18, before the fix, on the harness in
`server/internal/api/dispute_enrollment_test.go`:** a lone `data_dispute` item, with no other
contribution on the tree, produced a non-empty `GET /me/map-membership?kind=yours` and a
one-entry `GET /me/grove` for that tree; a `data_dispute_withdrawal` following it changed neither
answer.

**The fix is `store.TreeMembershipKinds`**, an explicit allow-list of the kinds that count as
having met a tree — everything `syncKinds` accepts except `private_reminder`, `data_dispute` and
`data_dispute_withdrawal` — read by both `Grove` and `MapMembership` in place of the old
deny-list. A kind added to `syncKinds` in the future is out of both reads by default rather than
in, which is the shape `MetSpeciesKinds` (`GroveSpeciesKnown`, PR #184) already uses for a
different question one read over; the two lists are deliberately independent, since "met the
species" and "met the tree" are different-sized sets — see the comment beside
`TreeMembershipKinds` for why sharing one list would starve or flood the other.

**What this does not touch.** `GET /me/journal` is unaffected and unchanged — it is a personal
history, has no `kind` filter, and still serves a dispute back after its own withdrawal applies.
That is a separate, already-open question (`docs/ROADMAP.md`'s chip backlog item "Answer what a
withdrawn-to-empty tree should look like"), which also covers `photo_withdrawal` and
`measurement_withdrawal` residue in `Grove`/`MapMembership` — unaffected by this fix, since those
two kinds were never excluded and still are not.

**Client side, checked by reading code only, not changed here — and it is already correct.**
`ContributionStore.contributedRowsSQL` (`Cypress/Data/Store/ContributionStore.swift`, backing the
local "Yours" filter) and both local Grove queries (`groveOwnedTreesSQL` in the same file, and
`GroveQueries.ownContributions`) union `visits`, `observations`, `measurements`, `care_events`,
`favorites` and self-added `community_trees` — never `tree_data_disputes`. Every read of
`tree_data_disputes` in `Cypress/` is in `DataDisputeStore.swift`, scoped to one tree or one
dispute for the dispute UI and the journal, never joined into a membership or grove query.
`DataDispute.raiseDataDispute` only inserts into `tree_data_disputes` and its two children
(`Cypress/Data/API/DataDispute.swift`'s own header: "Nothing in this file writes `trees`,
`tree_status_overrides` or `species_assertions`" — and, provably from the queries above, nothing
it writes is read by "yours" or grove either). So this defect was server-only:
`RoutedAPI.refreshedMapMembership` (`Cypress/Data/API/RoutedAPI.swift` ~834–844) unions the
phone's clean local set with whatever the server answered, and the server was the one answering
wrong.
