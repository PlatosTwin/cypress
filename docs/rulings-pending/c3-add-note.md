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

### R??? — The two empty places name both kinds, and both are true

1. **The map card.** The body is the owner's. The trigger did not change and did not need to:
   `MapInventoryNotice.isOwed` reads `MapContent.markerCount`, and `LocalAPI.mapContent` merges the
   community layer (this phone's trees and other people's cached ones) into the same content as the
   city's. So the card draws only where neither has a pin or cluster in view, unnarrowed. Measured at
   AX5 on the 393 pt phone `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` uses: 357.0 pt, against
   a budget of 402.7 pt (the tallest location notice in the same slot).
2. **The empty list.** The words moved into `VisitIdentifyCopy.emptyMessage`, with the number taken
   from `VisitShortlist.searchRadiusM` (60 m). The list is `LocalAPI.treesNear`, which reads the seed
   and the whole community layer, so it is empty only when neither kind is within 60 m.
3. **One limit, not a change.** Other people's trees reach the map and the list only after the tile
   refresher has cached them. Over ground the phone has never fetched, the card can show for the
   moment before the first fetch answers, and the map's read after the fetch takes it away.
