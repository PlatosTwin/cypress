# Rulings pending — community trees C2, the sync down (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". Each is the authoring agent's call under the
brief for `feat/community-trees-sync-down`, for the orchestrator or the owner to confirm or reverse.
No code comment cites this filename. Where an earlier ruling already answered a question, the entry
names that file and follows it.

---

### R??? — The refresher runs when the map settles, for the tiles the viewport touches

**Decided by:** the C2 author. **Needs owner review:** no; it adds no surface.

- **Trigger.** `MapModel` starts a refresh after each settled read of the map (the 200 ms camera
  debounce already decides when a read happens). The map paints from the phone first, and the
  refresh runs behind it. If the refresh changed the cache, the map reads again, once, and only if
  the camera is still on the viewport that was refreshed. That re-read does not start another
  refresh.
- **Which tiles.** The zoom-14 tiles (`CommunityTile`, the service's only zoom) that the read's
  viewport touches, and **only when there are nine or fewer**. Nine tiles is a 3 × 3 block, about
  5.8 km across in San Francisco, which is the map at zoom 13 or closer. A wider map fetches nothing;
  the reader zooms in to get the trees, and the cache keeps drawing what it holds.
- **How often.** A tile is asked at most once every **120 seconds**, counted from the last attempt,
  successful or not. Panning back and forth does not repeat requests, and an offline phone does not
  retry on every pan. A refresh cancelled because the map moved on does not count as an attempt.
- **Pages.** `has_more` is followed up to 10 pages (1,000 trees) per tile per pass; the next pass
  continues from the stored cursor.
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
  could not be refreshed, or a page this build cannot decode. The other tiles wait for the next pass.
  So an offline phone spends one request per pass, not one per tile.
- **A page this build cannot decode fails whole.** Skipping one undecodable tree and storing the
  cursor past it would lose that tree for good. The page stays unread and is asked again.
- **`validation_failed` on a cursor** drops that tile's cursor and the trees fetched through it
  together (`dropTile`), then asks for a fresh snapshot, once. A refused snapshot is not retried.
- **Nothing is drawn about any of this.** No screen, notice or string reports a failed refresh (that
  would be a state no mock draws, DECISIONS constraint 21). The map keeps drawing what the cache holds.

### R??? — The refresher follows the remote gate, and runs signed in and signed out

**Decided by:** the C2 author, following how `DataLayer` gates every other remote read.
**Needs owner review:** yes, for the last point only.

- **The gate.** `DataLayer.refreshCommunityTrees` is nil when `RemoteAccess.allowsNetwork` is false,
  exactly as `refreshTreeProfile`, `refreshGrove` and the others are. So every DEBUG build without
  `CYPRESS_REMOTE=live`, and the whole UI suite, fetches nothing.
- **Sign-in.** The tile route takes the device credential and is caller-independent (§3C: "a phone
  that has never signed in still draws everybody's published trees"). So the refresher runs signed
  in and signed out alike, and a sign-in or sign-out changes nothing in the cache. The cache holds
  no fact about the viewer (`AppSchema` v23's note on the table).
- **The owner should know this:** on a phone that has never needed a credential, its first look at
  the map at zoom 13 or closer now registers the device with the service (`POST /devices/register`),
  because the tile request needs a credential. `AppSession.bootstrap()` keeps registration lazy so
  that "a person who only wanted to look at a map" is not slowed or failed by it. That reason still
  holds here, because the request runs behind a painted map and nothing waits for it, but it is a
  new moment at which an install first talks to the service. Before C2 a phone that only looked at
  the map never did.

### R??? — A tree leaves the cache only through the service's removal list or a refused cursor

**Decided by:** round C1, in `AppSchema` v23's comment on `community_tree_cache` ("No eviction
except through the service's removal list, so a visit to a cached tree always finds its tree").
C2 follows it and adds nothing.

- A withdrawn, taken-down or erased tree arrives in some tile's `withdrawn_tree_ids` and is dropped
  from the whole cache, whichever tile served it (`CommunityTreeCacheStore.remove`).
- A tree is **never** evicted because the profile's `community_tree` came back null: null means "not
  one this caller may see", not "deleted" (`server/testdata/README.md`).
- **How the cache is bounded:** by the tiles a reader looks at closely, because those are the only
  tiles fetched. There is no count cap and no age limit. A tile is about 3.7 km² in San Francisco;
  even a few hundred tiles of dense community trees is a few thousand rows. If the owner wants a cap,
  it must say what happens to a cached tree the reader has visited or favorited when its tile is
  evicted, because its profile would then answer "not found".

### R??? — The community layer takes at most half the map's pin budget when the city layer can use the rest

**Decided by:** the C2 author, taking the ROADMAP's proposal ("half was proposed").

`LocalAPI.communityPinShare`: the community layer keeps
`min(communityPins, max(pinLimit / 2, pinLimit − cityPins))`.

- **Half, rounded down.** When both layers could fill the budget, the community layer gets half and
  the odd pin goes to the city layer. At the map's budget of 400 that is 200 community pins.
- **Unused budget is not withheld.** A park with 30 city trees and 300 added ones draws all 330
  under a budget of 400. The cap binds only where the city layer would otherwise be starved.
- **The phone's own trees come first inside the share**, then other people's, each by id
  (`CommunityLayer.inBoundsSQL`'s `ORDER BY cached, id`). So ERRATA E36's rule holds (a contributor's
  own pin appears on the screen they added it from), and the same trees are cut on every read, so a
  pan does not swap which ones are drawn.
- Clustered zooms are unchanged: a community tree adds one to its cell's badge, as before.

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
  every zone. `RoutedAPI.refreshedTreeProfile(id:)` carries it to the screen by setting the service
  photograph's `capturedAt` to **noon of that day in the reader's zone**, which every existing
  photograph surface formats as exactly that day. The copy test against the phone's own photographs
  (report F30) runs on the wire's instants first, so a display date never takes part in it. When
  `captured_on` is absent, the photograph keeps `captured_at`, formatted in the reader's zone as the
  shipped client always has.
- Why the merge and not each surface: six surfaces read a refreshed profile's photographs
  (`refreshedTreeProfile`'s list), several of them format the date their own way, and changing each
  would put C2 into that many feature files to change one fact. The cost, stated: a service photograph's `capturedAt` in a refreshed profile is a display
  instant, not the time the shutter fired. Nothing reads it as the shutter time; the phone's own
  photographs keep theirs.

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
