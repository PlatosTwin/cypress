# Errata pending — community trees, found while writing the server reads (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". Found by PR S2
(`server/community-trees-reads`) while checking the round's design and PR S1 against the code.

---

### E??? — Three reads served a community tree's photographs and counts without asking whether the tree could be seen

`store.TreeCommunityHalf` (behind `GET /trees/{id}`), `store.PublicTreeCommunityHalf` (behind
`GET /public/trees/{id}`) and `GET /photos/{id}` never consulted `community_trees`. They answered any
id. For a community tree whose adder had withdrawn it, that an operator had taken down, that had
never been published, or whose account had erased it, they served the photographs, the visit count,
the public readings and the beloved state to anybody who asked by id. The photograph read went on
serving a withdrawn tree's pictures to anyone who had read their ids earlier.

PR S1 found the first two while writing migration 007. **It was not live before 007**: nothing could
be withdrawn or taken down, and nobody's community tree was visible to anybody else. 007 made every
one of those states reachable, so the reads had to learn them in the same round.

Fixed in S2 with one predicate for all four reads (`communityTreeFor`). A hidden tree is answered as
an id nobody sent. The ruling is `docs/rulings-pending/community-trees-reads.md`.
`TestAHiddenCommunityTreeAnswersAsAnUnknownId`, `TestAHiddenCommunityTreesPhotographIsNotServed` and
`TestTheHiddenCommunityTreeIsNotOnThePublicPage` compare bytes against an unknown id's answer in
each of the five hidden cases. Each has a control that proves the hidden photograph was really there.

### E??? — The design's tile delta, a keyset over `updated_at`, silently loses rows

The design (§3C) specifies `next_cursor` as a keyset over `(updated_at, id)`. Every writer stamps
`updated_at` from the store's clock at the start of its transaction and commits later. A reader can
pass a row stamped 12:00:05 before a row stamped 12:00:03 commits. A cursor that advanced to 12:00:05
never returns the second row, so that tree never reaches that phone and nothing says so. That is the
silent drop `Journal`'s own comment calls the failure this app's `Series` type exists to prevent.

S2 serves every committed row but never moves the cursor past `now − (requestTimeout + 5 s)`. That
horizon is the latest point at which a transaction could still commit. The ruling has the argument,
and `TestTheCursorNeverPassesARowThatMightStillCommit` stages the race.

### E??? — The design's tile scoped a tree by its current position, so a moved pin stayed behind

The design serves a tile's trees by where they stand now. A pin moved across a tile edge then
disappears from the old tile's delta without being reported. A phone that fetched only the old
tile keeps drawing it where it was, indefinitely. S2 serves such a tree in the tile it left, with
its new coordinate (`TestAPinMovedOutOfATileIsReportedInTheTileItLeft`).

### E??? — Proximity candidates still carry another adder's address and to-the-second creation time

**Not fixed here; for the roadmap.** `candidateFrom` (`server/internal/api/sync.go`) builds the
conflict candidates of `POST /trees` and of a sync `add_tree`. It serves `address` and full-precision
`createdAt` / `updatedAt` for trees the caller did not add. S1 now scopes those candidates to
published trees, so what leaks is a published tree's adder-supplied address and the exact second
it was added. The tile and the profile withhold both (the rulings file).
`server/testdata/proximity_conflict.json` carries `"address": "1 Main St"` and second-precision
dates, and `GoldenWireFixtureTests` decodes it. The fix therefore moves that fixture and its Swift
test together, which is why it is not folded into this read-side PR.
