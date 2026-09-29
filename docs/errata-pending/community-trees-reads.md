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

### E??? — After two review rounds, S2 still dated a tree to its private add and drew hidden photographs as grove heroes

Found by the fresh verification of #190 (and of #187, for L1 and L2), fixed in the same PR, before
merge. None was live.

- **V1: `createdAt` was the private add.** A stranger's tile and profile dated a tree to the day it
  was added while private, next to a history that said it was added the day it went live. That
  told every stranger how long the adder had been signed out or declining. Now it is
  `published_at` for everyone but the adder (`TestAStrangerIsToldATreeWasAddedTheDayItWentLive`).
- **V2: the grove's hero had no visibility gate.** A stranger's withdrawal of a hidden id is
  answered like an unknown id's (F6), but their grove then drew the hidden tree's photograph for it,
  and a favorite on a withdrawn tree kept receiving its photograph's id. A photograph whose bytes
  never arrived could also be the hero. Both are gated now
  (`TestTheGroveHeroPassesThePhotographGate`, `TestAStrangersWithdrawalLeavesTheGroveAsAnUnknownIdWould`).
- **L1: a public event could be dated before "added".** A move queued while the tree was private
  and delivered after it went live was served on its private day, below "added". Now it is served
  at the later of the two (`TestNoPublicEventIsDatedBeforeTheTreeWentLive`).
- **L2: any string was an acceptance.** `license_version: ""` published an account's trees and
  wrote `""` into the `published` event as their license
  (`TestOnlyAKnownLicenseVersionIsAnAcceptance`).
- **V5: nothing planned the production tile texts.** An edit that made an arm unindexable would
  have passed every test. `TestTheProductionTileQueriesUseTheirIndexes` now runs
  `EXPLAIN (GENERIC_PLAN)` on `tileSnapshotQuery` and `tileDeltaQuery` themselves.

### E??? — Decision 14 (photo capture date only) cannot be served correctly by the service alone to the shipped client

**Resolved by the owner's decision 14a (client-assisted), implemented in S2 round 4.** The phone
sends `captured_on`, its local date (S1's column and begin field). Other people are served noon UTC
of that date on both routes, and the owner keeps the exact time (`servedCapturedAt`). The table below
the options is the served form, measured the same way. What follows is the finding that led there.

**Originally: not implemented, needs a decision.** The owner's decision 14 says other people see a photograph's
capture **date**, never its time. `captured_at` reaches another person on two routes:
- `GET /trees/{id}`'s `photos[]`. The shipped client decodes it (`TreeCommunityHalfResponse`, `.iso8601`).
- `GET /photos/{id}`. The shipped client does not decode this one's `captured_at`.

**Every surface formats the decoded instant in the reader's own time zone, date only:**
- the photo timeline's caption, `capturedAt.formatted(date: .abbreviated, time: .omitted)`;
- screen 03's "Best photo · Oct 2025" and months-with-photos;
- the memorial's hero eyebrow and "First photo" milestone;
- the activity screen's month counts, first-photo date and week buckets;
- the share card's months.

None of them shows a time of day, so there is no fake "00:00" to worry about. **The day is the
problem.** The service does not know where or in which zone a photograph was taken:
- the client encodes `captured_at` in UTC, so its offset is lost;
- it never sends `public_lat`/`public_lon` (E42);
- for a city tree the service does not know where the tree stands.

So it cannot know the capture's local date. Measured through the client's own decoder and
formatters (`.iso8601`, then the three renderings above) for a photograph an SF owner sees as
**Mar 14**:

| Form served to others | Taken 10:00 PDT, read in LA / NY | Taken 19:30 PDT, read in LA / NY | Taken 18:00 PDT on Mar 31, read in LA |
|---|---|---|---|
| exact time (today) | Mar 14 / Mar 14 | Mar 14 / Mar 14 | Mar 31, Mar 2026 |
| midnight UTC of the UTC day | **Mar 13** / **Mar 13** | Mar 14 / Mar 14 | Mar 31, Mar 2026 |
| noon UTC of the UTC day | Mar 14 / Mar 14 | **Mar 15** / **Mar 15** | **Apr 1, Apr 2026** |
| noon UTC of the *local* date | Mar 14 / Mar 14 | Mar 14 / Mar 14 | Mar 31, Mar 2026 |

Midnight is wrong for every morning photograph read in the Americas. Noon is wrong for every evening
one, and moves month labels at a month's end. Only noon UTC of the capture's local date is right
(for readers within ±11 h of UTC). The service cannot compute that date for a city tree, and for a
community tree it could only estimate the zone from longitude, which is wrong within about an hour
of midnight.

**Options:**
1. **Client-assisted.** The client sends the capture's local date (`captured_on`, `YYYY-MM-DD`) with
   `POST /photos/begin`. Others get `captured_at` at noon UTC of that date, and the owner keeps the
   exact time. This needs a column (a migration) and a client release. Photographs from builds that
   do not send it need their own rule: keep the exact time until the build floor passes it, or
   accept the UTC-day risk for them.
2. **Server-only, UTC day at noon.** Implementable now, but it shows the wrong day for evening
   photographs in the Americas. That breaks the hard constraint, so it was not shipped.
3. **Defer decision 14** until option 1's client ships, keeping the exact time for now. This is
   what this PR does.

The evidence is the scratchpad's `d14/render.swift` and `d14/render-evidence.tsv`: the client's
decode and format calls, run per zone. It is outside the tree, like the other reproductions.

**The served form (round 4)**, as the server serves it, through the same decode and formatters.
The golden's photo is taken at 19:30 PDT on Sep 22, which is already the 23rd in UTC, and its
phone date is the 22nd:

| served to others | phone's day | LA | New York | London | Tokyo |
|---|---|---|---|---|---|
| `2026-03-14T12:00:00Z` (SF 10:00 or 19:30 PDT) | Mar 14 | Mar 14 | Mar 14 | Mar 14 | Mar 14 |
| `2026-03-31T12:00:00Z` (SF 18:00 PDT, already Apr 1 in UTC) | Mar 31 | Mar 31 · Mar 2026 | Mar 31 · Mar 2026 | Mar 31 · Mar 2026 | Mar 31 · Mar 2026 |
| `2026-09-22T12:00:00Z` (the golden's) | Sep 22 | Sep 22 | Sep 22 | Sep 22 | Sep 22 |

Honolulu shows the phone's day too. **Auckland shows the next day** (Mar 15, Sep 23): noon UTC is
already tomorrow at UTC+12 and beyond. It is the one residue on the shipped client, and the C2
contract closes it for new builds (format others' photograph dates with a UTC calendar). The
measurements are in `d14/render-14a.tsv`.

### E??? — Round 4's photograph dates leaked through their order, and its C2 note was wrong for older photographs

Found by the fresh verification of #190 at `0b631ce`, and fixed in round 5 before any client sent
`captured_on`. Until one does, every photograph is served its exact time, so nothing was live.

- **N1: the order gave away the hidden time.** The profile listed photographs by stored
  `captured_at`, and the grove's hero was the newest by it. Anybody can begin a photograph at a
  chosen time, so a prober could place their own photographs around another person's and read which
  side it fell on. An anonymous device that never uploaded bytes bisected a photograph served as
  noon to 17:41:43–17:42:25 in eleven begins. Both orders now use the served value, then the id
  (`TestTheProfilesOrderGivesAStrangerOnlyTheServedDate`, `TestTheGroveHeroGivesAStrangerOnlyTheServedDate`,
  and `TestPhotographsServedTheSameDateAreOrderedByIDNotByTime` for the tiebreak).
- **N2: the C2 note turned the UTC+12 residue into a bigger error.** "Format others' photograph
  dates with a UTC calendar" is wrong for a photograph from a build that sent no `captured_on`,
  which is served its exact time: an evening in San Francisco would read as the next day. The
  client could not tell the two forms apart. `captured_on` is now served as its own field
  (`TestAPhotographCarriesThePhonesDateWhenItSentOne`), and the note renders it when present.

**For the roadmap, not fixed here (N3, a hypothesis, not reproduced):** the presigned `GET` a
photograph read hands out goes to object storage, which normally answers with `Last-Modified`, the
upload time to the second. For a photograph uploaded while online that is close to the capture
time, which decision 14 hides from others. The test presigner is fake, so it was not measured
against Tigris. It predates this PR.

### E??? — Proximity candidates still carry another adder's address and to-the-second creation time

**Not fixed here; for the roadmap.** `candidateFrom` (`server/internal/api/sync.go`) builds the
conflict candidates of `POST /trees` and of a sync `add_tree`. It serves `address` and full-precision
`createdAt` / `updatedAt` for trees the caller did not add. S1 now scopes those candidates to
published trees, so what leaks is a published tree's adder-supplied address and the exact second
it was added. The tile and the profile withhold both (the rulings file).
`server/testdata/proximity_conflict.json` carries `"address": "1 Main St"` and second-precision
dates, and `GoldenWireFixtureTests` decodes it. The fix therefore moves that fixture and its Swift
test together, which is why it is not folded into this read-side PR.
