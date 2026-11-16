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
2. **The empty list.** The words moved into `VisitIdentifyCopy.emptyMessage`, with the number taken
   from `VisitShortlist.searchRadiusM` (60 m). The list is `LocalAPI.treesNear`, which reads the seed
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

   **The "What tree is this?" list does not, yet.** It fetches nothing itself and reads the cache
   that map viewports have filled, so over ground the map has not fetched it can say "No city tree
   and no added tree is within 60 m of you" while the service holds an added tree there. Whether it
   gets the map card's rule is a question for the owner.

### R??? — The map card where the phone has not asked for added trees

**The question (AskUserQuestion, 2026-11-15).** The "No trees on record here" card now ends
"Neither has a tree here." In cases where the phone has not asked the service for added trees
(zoomed out past about 3 km, offline, or a failed download) the card can be wrong; what should it do
there?

**Offered:** "Show the old text there (Recommended)"; "Keep the new text everywhere"; "Show no card
there". **Chosen: "Show the old text there".**

**How it is built.**
1. **Asked, from the cache's tile table.** `CommunityTreeCacheStore.hasAsked(covering:maxTiles:connection:)`
   is true when the box touches at most `Policy.maxTiles` (16) zoom-14 tiles and every one of them
   has a row in `community_tree_cache_tiles`. What a row means, read from the code: `apply` writes
   it with each page it applies, with trees or without, so a tile the service answered empty has
   one. A failed request writes nothing. A refused cursor deletes the row (`dropTile`) until the
   snapshot after it is applied. A shut remote gate never runs the refresher and leaves no rows. A
   row from an earlier fetch counts as asked however old it is. No migration.
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
4. **For a second caller.** `CommunityTreeCacheStore.askedReader(queue:)` answers the same question
   for any box, so the "What tree is this?" list can use it for the 60 m around the reader if the
   owner gives it the same rule.
5. **AX5.** On the 393 pt phone `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` uses, against a
   budget of 402.7 pt: the new body measures 357.0 pt and the first body 402.7 pt, which fits with
   no room to spare (the test allows equal). It is the same height it had when it shipped.
