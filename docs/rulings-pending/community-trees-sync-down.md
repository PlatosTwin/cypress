# Rulings pending — community trees C2, the sync down (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". Each is the authoring agent's call under the
brief for `feat/community-trees-sync-down`, for the orchestrator or the owner to confirm or reverse,
except the three entries marked as the owner's ruling. No code comment cites this filename. Where an
earlier ruling already answered a question, the entry names that file and follows it.

---

### R??? — The phone downloads community trees from the first zoom that draws cluster badges (owner's ruling, 2026-11-15)

**Decided by:** the owner, in a question dialog on 2026-11-15.

- **The question:** from which zoom should the phone download other people's community trees?
- **The options offered:** "Neighborhood level (Recommended)": download when about a 2 km wide area
  is on screen, the first zoom that shows cluster badges; each settle may ask for up to 16 tiles,
  each tile at most once every 2 minutes. "Street level, as built": the round's first build, which
  asked for at most 9 tiles.
- **Chosen: Neighborhood level.**

**What was built.** `CommunityTileRefresher.Policy.maxTiles` is **16**. The first zoom that draws
cluster badges is **zoom 15**: `MapViewport.highestClusteringZoom` is 15, and `shouldCluster` is
`zoom <= 15`, so zoom 16 and closer draw single pins. The counts below use `MapZoom`'s formula, the
map's full screen (the map is full-bleed), `BoundingBox(MKCoordinateRegion)` and the 8 % margin that
`MapModel.cameraDidChange` adds. They cover the four agent screens (390 × 844, 402 × 874, 420 × 912
and 440 × 956 pt, portrait), at 0.3° N, 37.77° N and 64.1° N, with the map's center swept across one
tile so that every alignment is tried. Latitude changes nothing, because the tiles and the screen are
both Web Mercator.

| Map zoom (continuous) | Tiles touched | With 9 | With 16 |
|---|---|---|---|
| 15.0 (the widest zoom-15 map) | 2 to 8 | all fetch | all fetch |
| 14.75 | 6 to 12 | some fetch | all fetch |
| 14.25 | 8 to 15 | some fetch | all fetch |
| 14.0 (the widest zoom-14 map) | 8 to 18 (15 at most on 390 and 402 pt) | some fetch | most fetch; on 420 and 440 pt some do not |
| 13.0 | 32 to 50 | none | none |

The widest zoom-15 map is 1.5 to 1.7 km across in San Francisco, 1.9 to 2.1 km at the equator, and
0.8 to 0.9 km at 64° N. A zoom-14.25 map is about 1.7 times as wide.

**Why 16 and not 9.** Nine already covered every zoom-15 map (8 tiles at most), so the as-built
number met "the first zoom that shows cluster badges" on its own. The owner did not choose the
as-built option, though, and 16 is the number the chosen option names. A number high enough for
every zoom-14 map (18) would also take zoom-13 maps just wider than zoom 14.0, and was not offered.

**How wide a map fetches with 16, in full** (San Francisco, the four screens, every placement of
the map across a tile; the widths are the screen's, before the 8 % margin):
- **Every placement fetches** for a map up to about **3.1 km** wide: zoom 13.92 on the 390 pt
  screen, 13.97 on 402, 14.04 on 420 and 14.10 on 440.
- **Some placements fetch** up to about **3.8 km** wide (zoom 13.63 to 13.81, by screen); whether
  one does depends on where the tile edges fall.
- **No placement fetches** below zoom 13.63 to 13.81.

So "about 2 km" in the chosen option understates what was built: the download starts at zoom 15 and
reaches maps about 3 km wide, roughly twice the width of the widest zoom-15 map. The second review
measured the same range independently (3.06 to 3.09 km and 3.83 to 3.86 km).

**What 16 means for requests, a fact the option's wording did not carry.** "Each tile at most once
every 2 minutes" holds for attempts that finish, successful or not. A pass cancelled while its
request is in flight does not count as an attempt, so a reader who keeps panning before answers
come back can send one request per settle for the same tile. A refused cursor adds one request (the
fresh snapshot) beyond a pass's 10 pages. And a pass waits behind any pass still running (the next
entry), so passes do not overlap.

`CommunityFetchZoomTests` pins three facts against the number in `Policy`: every zoom-15.0 map and
every zoom-14.25 map touches no more tiles than the limit, and every zoom-13.0 map touches more. It
does not pin the ranges in the table or the zoom-14.0 row.

### R??? — The refresher runs when the map settles, for the tiles the viewport touches

**Decided by:** the C2 author. **Needs owner review:** no; it adds no surface.

- **Trigger.** `MapModel` starts a refresh after each settled read of the map (the 200 ms camera
  debounce already decides when a read happens). The map paints from the phone first, and the
  refresh runs behind it. A later settle cancels the refresh in flight.
- **The re-read.** If a refresh changed the cache, the map reads what the camera shows now, once,
  **whether or not the refresh was cancelled, and wherever the camera is.** Cancelling a refresh
  cannot undo a page it already wrote, and the read the camera scheduled may have run before that
  write. There is no test of where the camera is, because the refresher writes whole zoom-14 tiles,
  about 2.4 km across: a tree written for one screen can be on a later screen that does not overlap
  it (the second review's finding). Comparing against the refreshed tiles' bounds would also work;
  it was not chosen because it is a second geometry rule to keep right, and an unneeded re-read
  costs one map read and happens only after the cache changed. The re-read starts no refresh, so the two cannot loop. A camera change
  cancels the re-read like any other read, and the read that replaces it sees the same rows.
- **One pass at a time.** A pass that starts while another is running waits for it to end, then
  decides which tiles are due. A tile in flight is therefore never skipped by a second pass that only
  saw it marked. If the first pass was cancelled before its request came back, the tile is not
  marked, and the second pass asks for it.
  - **Known limit:** because passes queue, a pass stuck in a wait that cancellation does not stop
    delays every later pass. One such wait is `AppSession`'s shared credential-minting task during a
    phone's first registration (`AppSession.mintingInFlight`). For a stalled connection the delay
    ends at the 15-second request timeout (`AuthClient.requestTimeout`). That timeout is an idle
    timeout, not a deadline: it restarts whenever a byte arrives, so a slow answer that keeps
    trickling can hold the queue longer.
- **Which tiles.** The zoom-14 tiles (`CommunityTile`, the service's only zoom) that the read's
  viewport touches, and only when there are 16 or fewer (the owner's ruling above). A wider map
  fetches nothing; the reader zooms in to get the trees, and the cache keeps drawing what it holds.
- **How often.** A tile is asked at most once every **120 seconds**, counted from the last attempt
  that finished, successful or not. Panning back and forth over the same tiles does not repeat
  requests once they have answered. A refresh cancelled before its request came back does not count
  as an attempt, so a reader who keeps panning before answers arrive can send one request per
  settle for the same tile.
- **Pages.** `has_more` is followed up to 10 pages (1,000 trees) per tile per pass; the next pass
  continues from the stored cursor. A refused cursor costs one more request, the fresh snapshot.
- **No timer, no launch fetch, no foreground fetch.** The map is the only surface that draws other
  people's trees in bulk, so it is the only trigger. A profile opened from somewhere else reads what
  the cache already holds.

Why: the service's tile is built for "the tiles the viewport covers at 14" (§3C,
`community_reads.go`). The 120-second floor keeps the request rate low while still showing a new tree
"at the other phone's next refresh" (decision 1) within two minutes of a person looking.

### R??? — Offline or on an error, the refresher changes nothing and stops the pass

**Decided by:** the C2 author, implementing the service's contract (`server/testdata/README.md`).

- Each page is applied **in one transaction with its cursor** (`CommunityTreeCacheStore.apply`). The
  cursor moves only when its page was applied, so a failure leaves the cache and the cursor exactly
  as they were.
- **Any failure stops the pass** at that tile: offline, a timeout, a server error, a session that
  could not be refreshed, or a page this build cannot decode. The failed tile counts as attempted.
- **What an offline phone sends:** one request per settled map. Each pass skips the tiles tried in
  the last 120 seconds and asks for the next one, which fails and stops the pass. Once every tile in
  view has been tried, the phone sends nothing until the 120 seconds pass. A map that settles on
  16 tiles can therefore cost 16 failed requests over 16 settles, and no more within two minutes.
- **A page this build cannot decode fails whole.** Skipping one undecodable tree and storing the
  cursor past it would lose that tree for good. The page stays unread and is asked again at the
  tile's next attempt.
- **`validation_failed` on a cursor** drops that tile's cursor and the trees fetched through it
  together (`dropTile`), then asks for a fresh snapshot, once. A refused snapshot is not retried.
- **Nothing is drawn about any of this.** No screen, notice or string reports a failed refresh (that
  would be a state no mock draws, DECISIONS constraint 21). The map keeps drawing what the cache holds.

### R??? — Every phone downloads community trees, signed in or not, and registers its device to do so (owner's ruling, 2026-11-15)

**Decided by:** the owner, in a question dialog on 2026-11-15, for the last point. The rest follows
how `DataLayer` gates every other remote read.

- **The gate.** `DataLayer.refreshCommunityTrees` is nil when `RemoteAccess.allowsNetwork` is false,
  exactly as `refreshTreeProfile`, `refreshGrove` and the others are. So every DEBUG build without
  `CYPRESS_REMOTE=live`, and the whole UI suite, fetches nothing.
- **Sign-in.** The tile route takes the device credential and is caller-independent (§3C: "a phone
  that has never signed in still draws everybody's published trees"). So the refresher runs signed
  in and signed out alike, and a sign-in or sign-out changes nothing in the cache. The cache holds
  no fact about the viewer (`AppSchema` v23's note on the table).
- **Registration.** On a phone that has never needed a credential, its first map at zoom 15 or wider
  (out to the limit in the first entry) registers the device with the service
  (`POST /devices/register`), because the tile request needs a credential. Before C2, a phone that
  only looked at the map never talked to the service. The request runs behind a painted map and
  nothing waits for it.
  - **The question:** a never-registered phone registers its device when it first downloads
    community trees. Is that acceptable?
  - **The options offered:** "Yes, register (Recommended)" and "Only known phones".
  - **Chosen: Yes, register.** The owner's words: "Every phone sees community trees, signed in or
    not." The phone sends its random device ID and no account or personal data.

### R??? — No limit on the community cache for now (owner's ruling, 2026-11-15)

**Decided by:** round C1, in `AppSchema` v23's comment on `community_tree_cache` ("No eviction
except through the service's removal list, so a visit to a cached tree always finds its tree"), and
confirmed by the owner on 2026-11-15.

- **The question:** should the cache of other people's trees have a limit?
- **The options offered:** "No limit for now (Recommended)" and "Add a limit now".
- **Chosen: No limit for now.** C1's rule stands. It is to be revisited when the community layer
  grows; the ROADMAP's C2 entry carries that.

What the rule means:

- A withdrawn, taken-down or erased tree arrives in some tile's `withdrawn_tree_ids` and is dropped
  from the whole cache, whichever tile served it (`CommunityTreeCacheStore.remove`).
- A refused cursor drops its tile's trees (the error entry above).
- A tree is **never** evicted because the profile's `community_tree` came back null: null means "not
  one this caller may see", not "deleted" (`server/testdata/README.md`).
- **How the cache is bounded:** only by the tiles a reader has looked at closely, because those are
  the only tiles fetched. There is no count cap and no age limit. A tile is about 3.7 km² in San
  Francisco. A future limit must say what happens to a cached tree the reader has visited or
  favorited when its tile is evicted, because its profile would then answer "not found".
- **What it costs on the map**, stated for the revisit. Every map read narrows and counts the
  community trees in view in SQL (the next entry); a pin read decodes at most `pinLimit` (400) of
  them, and a cluster read decodes none. Measured by the C2 author with a probe test that was not
  committed: a Debug build on the iPhone 17 Pro Max simulator, `LocalAPI.mapContent` over one box
  holding N cached trees, the median of 7 reads after one warm-up.

  | Read | N = 5,000, before | N = 5,000, after | N = 50,000, before | N = 50,000, after |
  |---|---|---|---|---|
  | Pins, zoom 17 | 472 ms | 43 ms | 4,208 ms | 80 ms |
  | Clusters, zoom 14 | 525 ms | 1.9 ms | 4,244 ms | 23 ms |
  | Pins narrowed to a species with no match | 692 ms | 0.8 ms | 4,365 ms | 6.9 ms |
  | Clusters narrowed to a species that is a tenth of the trees | 751 ms | 0.8 ms | 4,151 ms | 7.8 ms |

  "Before" is the first review's fix (`f9a45689`), which decoded every tree in the box and narrowed
  in Swift. "After" is the narrowing in SQL. Each read holds the one database queue for its whole
  length, so the "before" column also blocked the refresher's writes and every other read. The pin
  read still sorts every match in the box to cut it by id, which is what is left of its cost.

### R??? — The community layer takes at most half the map's pin budget when the city layer can use the rest

**Decided by:** the C2 author, taking the ROADMAP's proposal ("half was proposed").

`LocalAPI.communityPinShare`: the community layer keeps
`min(communityPins, max(pinLimit / 2, pinLimit − cityPins))`.

- **Half, rounded down.** When both layers could fill the budget, the community layer gets half and
  the odd pin goes to the city layer. At the map's budget of 400 that is 200 community pins.
- **Unused budget is not withheld.** A park with 30 city trees and 300 added ones draws all 330
  under a budget of 400. The cap binds only where the city layer would otherwise be starved.
- **The narrowing runs before the cut, in SQL.** `LocalAPI.mapContent` resolves the map's
  narrowing (species, `In bloom`, `Needs care`, year, site, membership) into sets, and
  `CommunityLayer.pinsSQL` applies them in the `WHERE` of both arms, counts every match with
  `COUNT(*) OVER ()`, then sorts and cuts to `pinLimit`; the share is taken from those rows. Before
  the first review's fix the statement cut to `pinLimit` with no narrowing, so a species search over
  a box with more community trees than the budget could miss the only match. Every narrowing went
  into SQL; none had to stay in Swift.
- **The phone's own trees come first inside the share**, then other people's, each by id
  (`CommunityLayer.pinsSQL`'s `ORDER BY cached, id`). So ERRATA E36's rule holds (a contributor's
  own pin appears on the screen they added it from). Reading the same box twice cuts the same trees.
  A pan does not keep that promise: a pan that brings in a tree with a lower id can push out a tree
  still on screen.
- **Clustered zooms count every tree.** `CommunityLayer.cellsSQL` counts the narrowed community
  trees per cell in SQL, on the grid `LocalAPI.mapContent` keys its cells with, and each cell's
  count and mean position are added to its badge. Before the first review's fix, a box holding more
  than `pinLimit` (400) community trees counted only the first 400.

`MapContentBudgetTests.communityTreesCannotOverrunTheBudget` asserted the old rule (every pin a
community tree at a full seed block) and now asserts this one.

### R??? — Calendar days: a type in the data layer, and the photograph's date chosen at the merge

**Decided by:** the C2 author, implementing the S2 rulings in `community-trees-reads.md` ("dates
travel at day precision" and "decision 14a's served form", round 5).

- **Community-tree dates** (`createdAt`, `updatedAt`, a history event's `occurred_at`) are midnight
  UTC of a day on the wire. The history carries each event's date as a `CalendarDay`, read as the
  UTC day, so no surface can shift it into the reader's zone. The cache keeps `createdAt` and
  `updatedAt` as stored instants, and nothing in C2 draws them; C3 must format them with
  `CalendarDay(utcDayOf:)`, never in the reader's zone.
- **A photograph's `captured_on`**, when the service sends it, is shown as that calendar date in
  every zone. `RoutedAPI.refreshedTreeProfile(id:)` carries it to the screen through the service
  photograph's `capturedAt`: the photograph keeps its `captured_at` when the reader's zone already
  prints it as that day, and otherwise takes the nearest second of that day in the reader's zone
  (`CalendarDay.instant(nearest:in:)`). The copy test against the phone's own photographs (report
  F30) runs on the wire's instants first, so a display date never takes part in it. When
  `captured_on` is absent, the photograph keeps `captured_at`, formatted in the reader's zone as the
  shipped client always has.
- **Why the nearest second and not noon** (the review's finding): the profile sorts its photographs
  by `capturedAt`, newest first, and the hero's "since" year reads the earliest. The service serves a
  contributor their own rows at the exact time and other people's at noon UTC. A fixed noon in the
  reader's zone moved even the exact rows, so a photograph the reader took at 10:00 on another phone
  sorted after one they took at 11:00 on this phone. Now a photograph moves only when the reader's
  zone and `captured_on` disagree about the day, and then only to the edge of that day. Other
  people's photographs still sort by the noon-UTC time the service gives them, which says nothing
  about the hour; that was true before C2.
- Why the merge and not each surface: six surfaces read a refreshed profile's photographs
  (`refreshedTreeProfile`'s list), several of them format the date their own way, and changing each
  would put C2 into that many feature files to change one fact. The cost, stated: a service
  photograph's `capturedAt` in a refreshed profile can be moved by up to a day's edge from the time
  the service sent. The phone's own photographs keep theirs.

### R??? — `added_by_you` is adopted when the service says yes, and the history rides on the profile

**Decided by:** the C2 author, implementing the ROADMAP's "adopting the adder from the service".

- `TreeProfile.addedByYou` is the phone's answer (a tree this phone added whose adder is the reader)
  **or** the service's `added_by_you`. The service's yes covers a tree the reader's account added on
  another phone, which reaches this one only through the cache. Its no never overrides the phone's
  yes: the service says no for a tree it has not received yet, and one phone can get both answers for
  one tree (`server/testdata/README.md`).
- `canMovePin` is unchanged. A move is a write to this phone's own row, and a tree held only in the
  cache has none (`LocalAPI.correctLocation` refuses it, and that path is another author's this
  round). So C2 does not make the comment's suggestion that `added_by_you` replace the move gate.
- `TreeProfile.communityHistory` carries `GET /trees/{id}/history` for a community tree, asked beside
  the community half. A city tree asks nothing. The service's `not_found` and a failed read both give
  nil, and a failed history never costs the photographs.
- Nothing in C2 draws either field. C3 draws them, under the owner's answers in
  `community-trees-c3-answers.md`.

### R??? — The profile's `community_tree` and `is_published` are decoded and not used

**Decided by:** the C2 author, after the review found both decoded and never read.

- **What happens:** `TreeCommunityHalfResponse` decodes both keys, so the wire type stays a complete
  statement of what `GET /trees/{id}` sends (the pattern `visit_count` already follows), and
  `RemoteAPI.TreeCommunityDelta` carries neither. The profile shows the tree as the phone's cache
  holds it.
- **Why not refresh the cache row from it:** the cache has one writer, the tile refresher, and the
  tile's cursor orders its writes. A profile read is not ordered against a tile page. A profile answer
  fetched before a tile page and written after it would put the older tree back, and no `updatedAt`
  comparison can catch that, because the service sends dates at day precision.
- **The limit, stated:** the profile can show a cached tree that is older than the service's copy,
  until the reader's map next refreshes that tree's tile.
- **A second limit, from the same design:** a community tree that is in neither of the phone's
  tables (for example, a shared link to a tree whose tile the phone never fetched) makes
  `LocalAPI.treeProfile` throw `notFound` before the service is asked. The ROADMAP's C2 entry lists
  it as left to do.
