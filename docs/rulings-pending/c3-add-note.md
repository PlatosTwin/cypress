# Rulings pending: how round C3 builds the note under Add this tree and the two empty places (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. These are the author's build choices for the owner's rulings in
`community-trees-c3-answers.md` ("The note under the Add this tree button" and "Places with no city
inventory"), the last entry of `community-trees-answers-2026-11-15.md` ("Keep today's note"), and the
rulings-pending file `community-trees-only-you-can-see.md` ("Only you can see it"), which another
author of this round writes. None of these choices adds a string beyond the owner's.

---

### R??? — The note follows the account, read each time the add screen appears

1. **Where the state comes from.** The composition root builds a reader from `LocalAPI.userID` and
   `LocalAPI.accountLink()` (`ContributionSharing.reader(local:)` in `RootView.swift`) and passes it
   through `VisitFlowView` to `VisitAddTreeView` and its model. No `CypressAPI` requirement is
   added. The DEBUG `addTree` standalone gets the same reader.
2. **When it is read.** `VisitAddTreeModel.load()` reads it first, so it runs each time the screen
   appears (the flow builds a new add screen each time it reaches that step), and again when a listed
   tree's profile closes, because `closeListedTree` calls `load()`. A sign-in, or an agreement, made
   since the last appearance is seen.
3. **Before the read answers, no note is drawn.** The model holds `nil` until the first read. The
   alternative, drawing the `.unknown` note first, would show one account's sentence and then swap
   it for another's. The read is one hop to the local database.
4. **A read that fails counts as no answer.** A throwing `accountLink()` becomes a nil link, which
   `ContributionSharing(userID:link:)` makes `.unknown` for a signed-in account (the note as it was)
   and `.signedOut` with nobody signed in.
5. **Where it sits.** Below the accessibility sizes the note stays pinned under the button, centered,
   as before. At the accessibility sizes it is the last row of the scrolling form, after any blocking
   reason, and leading-aligned like the rows around it; only the button stays pinned
   (`VisitAddTreeLayout.footnotePlace(isAccessibilitySize:)`).

### R??? — The two empty places name both kinds, about the trees this phone holds

1. **The map card.** The new body is the owner's; where the phone has not asked for added trees the
   card keeps the first body (the next entry). The trigger did not change and did not need to:
   `MapInventoryNotice.isOwed` reads `MapContent.markerCount`, and `LocalAPI.mapContent` merges the
   community layer (this phone's trees and other people's cached ones) into the same content as the
   city's. So the card draws only where neither has a pin or cluster in view, unnarrowed. Measured at
   AX5 on the 393 pt phone `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` uses: 357.0 pt, against
   a budget of 402.7 pt (the tallest location notice in the same slot).
2. **The empty list.** The words moved into `VisitIdentifyCopy.emptyNeitherKind`, with the number
   taken from `VisitShortlist.searchRadiusM` (60 m). Where the phone has not asked for added trees
   the list keeps the old text (the last entry). The list is `LocalAPI.treesNear`, which reads the seed
   and the whole community layer, so it is empty only when neither kind is within 60 m.
3. **Both texts are about the trees this phone holds**: its own, and other people's in its cache.
   Other people's trees reach the cache only when `CommunityTileRefresher` fetches them, and the
   service may hold added trees that the phone never fetched. The phone asks for nothing in these
   cases, each checked in the code:
   - The map's viewport touches more than `Policy.maxTiles` (16) zoom-14 tiles, a zoomed-out map:
     `refresh(covering:)` returns `.tooManyTiles`.
   - The phone is offline, or a fetch fails: the pass stops, and a tile that was tried is not asked
     again until `Policy.minimumInterval` (120 s) has passed.
   - The remote gate is shut: `DataLayer.refreshCommunityTrees` is nil unless
     `RemoteAccess.allowsNetwork`. DEBUG builds are shut unless `CYPRESS_REMOTE` opens them; release
     builds are always open.
   - The time between a map read and the first fetch for its tiles.

   **The map card handles this** (the owner's answer below): where the phone has not asked, it shows
   the first body, which says only that the ground is not on the city inventory. "Neither has a tree
   here" is drawn only where every tile in view was fetched.

   **The "What tree is this?" list handles it the same way** (the owner's second answer, the last
   entry). It fetches nothing itself and reads the cache that map viewports have filled, so it says
   "No city tree and no added tree is within 60 m of you" only where every tile under those 60 m was
   fetched, and the old text everywhere else.

### R??? — The map card where the phone has not asked for added trees

**The question (AskUserQuestion, 2026-11-15).** The "No trees on record here" card now ends
"Neither has a tree here." In cases where the phone has not asked the service for added trees
(zoomed out past about 3 km, offline, or a failed download) the card can be wrong; what should it do
there?

**Offered:** "Show the old text there (Recommended)"; "Keep the new text everywhere"; "Show no card
there". **Chosen: "Show the old text there".**

**How it is built.**
1. **Asked, from the cache's tile table.** `CommunityTreeCacheStore.hasAsked(covering:maxTiles:connection:)`
   is true when the box touches at most `Policy.maxTiles` (16) zoom-14 tiles and a pass has
   followed every one of them to its last page at least once: each has a row in
   `community_tree_cache_tiles` **and** a complete mark in `app_state` (the next paragraph). What
   the writers leave, read from the code: `apply` writes the row with each page it applies, with
   trees or without. The refresher writes the mark only with a page whose `has_more` is false, in
   that page's transaction, so a tile the service answered with one empty page has both. A failed
   request writes nothing. A refused cursor deletes the row and the mark together (`dropTile`)
   until a snapshot reaches its last page again. A shut remote gate never runs the refresher and
   leaves neither. A mark from an earlier pass counts as asked however old it is. No migration.

   **The complete mark (ROADMAP 156, `fix/community-tile-complete`, 2026-11-16).** Before this,
   a row alone counted, and a row does not mean the tile was fetched to its end: the service serves
   at most 100 trees a page (`communityTileMaxLimit` in `server/internal/api/community_reads.go`),
   so in a tile with more than 100 added trees a request that failed after the first page, or a
   pass that stopped at `Policy.maxPagesPerTile` (10) pages, left a row for a tile only partly
   fetched, and the map card and the empty list could say their "neither" text while added trees
   on the missing pages stood there. The fix:
   - **Where the mark lives.** One `app_state` row per tile, key
     `community_tile_complete:<tile path>` (`CommunityTreeCacheStore.completeKey(tile:)`), value
     the moment the last page was applied (nothing reads the value). `app_state` needs no
     migration, and the key-per-thing shape is the one `photo_send_refused:` and
     `community_tree_queued_once:` already use. A column on the tile table was the other choice
     and needs a migration with a named author, which this round does not have.
   - **When it is written.** `CommunityTileRefresher` calls `markComplete` inside the same
     `queue.write` as the `apply` of a page whose `has_more` is false. The page and the mark land
     together or not at all.
   - **A delta after a complete pass never removes it.** Read from the code: a delta page is
     applied in one transaction with its cursor, and it carries both new trees and the removal list
     (`apply` drops withdrawn ids from the whole cache). So once a tile was complete as of cursor
     C, every delta page applied after C leaves the cache at least as current as it was at C. A
     delta that fails, or stops at the page limit, leaves the phone holding a full copy of the tile
     as of some cursor at or after C, which is exactly what "asked" claimed when the mark was
     written. Un-marking it there would turn the card back to the first body over ground the phone
     has fetched in full, on every flaky connection, which is less true, not more. The same holds
     while a delta is in flight: nothing is written until a page comes back. Only `dropTile` (a
     refused cursor) removes the mark, because it removes the trees the mark vouched for.
   - **What resets a tile.** Read from the code on 2026-11-16: `dropTile` is the only statement
     in the app that deletes tile rows. Sign-out (`LocalAPI.signOut`) and both account deletion
     doors (`AccountDeletion.delete`) do not touch the cache or its tile table (the trees are
     other people's, and no account owns a tile), and nothing else wipes the cache. Each is
     covered by `CommunityTileCompleteTests`, and a source guard there fails if a file deletes tile
     rows without clearing the mark.
   - **Rows written before this build** have no mark, so those tiles read as not asked (the first
     body) until the next pass for each reaches the last page, which a delta from the stored cursor
     usually does in one page. That is the honest reading for a row whose pass may have stopped
     part way.
   - **The DEBUG seam** `LocalAPI.debugSeedCommunityCache` writes no mark: one seeded tree is not a
     tile fetched to its end. No UI test reads either body.
2. **The card picks its body.** `MapModel` reads the answer for the settled viewport with each map
   read (before it publishes the content, so the body and the trigger change together) and again
   when a community refresh ends without changing the cache, because a tile served with no trees
   changes no pin but is now asked. `MapInventoryCopy.message(communityAsked:)` returns
   `neitherHasATree` when asked and `notOnTheCityInventory` when not. The title and `isOwed` did not
   change.
3. **The two bodies.** Asked: "Cypress draws a city street-tree inventory and trees people have
   added. Neither has a tree here." Not asked: "Cypress draws a city street-tree inventory, and this
   ground is not on it. Trees may stand here without being listed." (the body as it shipped before
   round C3, copied from main at `e5b11dba`).
4. **A second caller.** `CommunityTreeCacheStore.askedReader(queue:)` answers the same question
   for any box. The "What tree is this?" list uses it for the 60 m around the reader (the next
   entry).
5. **AX5.** On the 393 pt phone `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` uses, against a
   budget of 402.7 pt: the new body measures 357.0 pt and the first body 402.7 pt, which fits with
   no room to spare (the test allows equal). It is the same height it had when it shipped.

### R??? — The empty list where the phone has not asked for added trees

**The question (AskUserQuestion, 2026-11-15).** "The empty "What tree is this?" list has the same
gap as the map card, because it reads only the added trees the phone has already downloaded; where
the phone has not asked the service for added trees around you (offline or a failed download), what
should the empty list say?"

**Offered:** "Show the old text there (Recommended)"; "Keep the new text everywhere". **Chosen:
"Show the old text there".**

**How it is built.**
1. **The same function as the map card.** `VisitIdentifyModel` reads
   `CommunityTreeCacheStore.askedReader(queue:)` for the box of `VisitShortlist.searchRadiusM`
   (60 m) around the fix the list was read at. It reads it only when the list came back empty, and
   before it publishes the list, so the empty state and its message change together. The
   composition root passes the reader through `VisitFlowView`; a flow built without one answers
   "not asked".
2. **The list picks its message.** `VisitIdentifyCopy.emptyMessage(communityAsked:)` returns
   `emptyNeitherKind` when asked and `emptyNotOnTheCityInventory` when not. The title, "No trees on
   record here", did not change.
3. **The two messages.** Asked: "No city tree and no added tree is within 60 m of you. If there is a
   tree in front of you, it is not on the map yet." Not asked: "Nothing in the city inventory is
   within 60 m of you. If there is a tree in front of you, it is not on the map yet." (the message as
   it shipped before round C3, copied from main at `e5b11dba`). In both, the number is
   `VisitShortlist.searchRadiusM`.
4. **What counts as asked** is the map card's rule: every zoom-14 tile under the 60 m was fetched
   to its last page at least once (a row in `community_tree_cache_tiles` and the complete mark,
   above). At the default radius the area is one or, near a tile border, up to
   four tiles, far below the 16-tile limit.
