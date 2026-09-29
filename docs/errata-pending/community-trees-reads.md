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

### E??? — S2's first draft leaked stamps through its cursor, reported private trees, and scanned every tree per tile

Found by the adversarial review of #190 and fixed in the same PR, before merge. None was live.

- **The cursor gave away exact times (F1).** It was base64 JSON of `(updated_at, id)`, and the
  server accepted any well-formed one. A cursor forged at `T − 1µs` served a tree and one at `T` did
  not, so a binary search recovered each tree's exact stamp: when an adder stood at it, when they
  signed in, when an account was erased. That undid the day-precision ruling. The cursor is now
  sealed (the rulings file). `TestTheReviewersBinarySearchFindsNothing` runs the review's attack,
  and `TestATamperedMovedOrForeignCursorIsRefused` covers the other forgeries.
- **A never-public tree was reported (F2, F3).** Every erase-door tombstone went into every
  stranger's delta, including a declining account's unpublished tree in another city. A tree born
  withdrawn was inferred public from the event log. The tile now reads S1's `was_public` columns
  (`TestANeverPublishedTreeIsNeverReportedWhenItsAccountGoes`, `TestATreeBornWithdrawnIsNeverReported`).
- **A position held while private was served (decision 13).** The tile placed a tree in every tile
  of its location chain, and the history served its first position, including positions from
  before it went live. Both now read only public rows (`TestPositionsHeldWhilePrivateStayPrivate`).
- **Each tile request cost O(all community trees) (F5).** One query text with `($1 IS NULL OR …)`
  arms cannot use an index in a generic plan. Now there are two texts on S1's partial indexes.
  Measured with `EXPLAIN ANALYZE` on Postgres 18 in local Docker, 100,000 trees (10,000 of them
  moved once), 1,000 tombstones, a 45-tree tile:

  | query | warm | cold | review's measure of the old text |
  |---|---|---|---|
  | snapshot, custom plan | 0.28–0.41 ms (2.6 ms on the first execution) | 2.9 ms | 320–480 ms warm, 2.1 s cold |
  | snapshot, generic plan | 0.27–0.44 ms | 3.2–4.2 ms | (the same seq scans) |
  | delta, custom plan (cursor 5 min / 1 h / 1 day old) | 0.20–0.43 ms (1.3 ms on one first execution) | — | 8 ms |
  | delta, generic plan | 0.22–0.33 ms | 1.6 ms | 403 ms, seq scans |

  pgx's default mode (`auto`) measured 0.25–0.37 ms for the snapshot and 0.20–0.49 ms for the delta. No
  sequential scan in any plan. "Cold" is the first execution after a server restart: shared
  buffers empty, the Docker VM's page cache not dropped. The review's text, run on the same
  database as a control, measured 128–660 ms for the snapshot and 159–277 ms for the generic delta,
  with seq scans throughout. So the instrument reproduces the finding.

### E??? — Proximity candidates still carry another adder's address and to-the-second creation time

**Not fixed here; for the roadmap.** `candidateFrom` (`server/internal/api/sync.go`) builds the
conflict candidates of `POST /trees` and of a sync `add_tree`. It serves `address` and full-precision
`createdAt` / `updatedAt` for trees the caller did not add. S1 now scopes those candidates to
published trees, so what leaks is a published tree's adder-supplied address and the exact second
it was added. The tile and the profile withhold both (the rulings file).
`server/testdata/proximity_conflict.json` carries `"address": "1 Main St"` and second-precision
dates, and `GoldenWireFixtureTests` decodes it. The fix therefore moves that fixture and its Swift
test together, which is why it is not folded into this read-side PR.
