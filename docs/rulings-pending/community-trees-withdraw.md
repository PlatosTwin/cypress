# Rulings pending — withdrawing a tree you added (the last piece of F31), 2026-11-16

Unnumbered, per CLAUDE.md "Numbering and shared files". The owner's answers are quoted from the
orchestrator's decisions file of 2026-11-16, section "Withdrawing a tree you added". One choice is
the orchestrator's and is marked as such. The design notes are the author's, for the orchestrator to
confirm or reverse. No code comment cites this filename.

This supersedes the first entry of `community-trees-core.md` ("`tree_withdrawal` is reserved … and
has no verb yet"), which left open whether the phone withdraws first or waits for the service.

---

### R??? — The owner's answers (2026-11-16)

1. Q: "…Where should it sit on the profile of a tree you added?"
   Chosen: **"In the record controls"**. Near the bottom of the profile, below "Report that there
   is no tree here".
   Not chosen: "Directly under "Move pin""; "Only on the Move pin screen".
2. Q: "What words should the withdraw-a-tree control, its confirmation alert, and its Outbox row
   use?"
   Chosen: **"Withdraw this tree"**. Control: `Withdraw this tree`. Alert title:
   `Withdraw this tree?`. Buttons: `Withdraw tree` and `Keep it`. Outbox row: `Tree withdrawn`.
3. Q: "What should the message inside the withdraw-a-tree confirmation alert say?"
   Chosen: **"Two messages"**. For a shared tree:
   `Everyone using Cypress stops seeing this tree once this is sent. If someone else has visited or photographed it, it stays. This cannot be undone.`
   For a tree only you can see:
   `Only you can see this tree. It comes off the map. This cannot be undone.`
4. Q: "You withdraw a tree, and the service refuses because someone else has visited or
   photographed it. What should the phone do?"
   Chosen: **"Comes back, with the reason"**. The tree leaves your phone at once. If the service
   refuses, the tree comes back on the map and the Outbox row says
   `Other people have added to this tree, so it stays on the map.`
5. Q: "After you withdraw a tree you added, what should happen to your own visits, photos, and
   favorite on that tree?"
   Chosen: **"Saved, but off the lists"**. They stay saved on the phone, and the tree leaves the
   Journal, My Grove, and the Yours map. Nothing is left on screen that opens to an empty page.
6. Q: "Your phone already knows that someone else visited or photographed a tree you added, so the
   service would refuse a withdrawal. What should that tree's profile show where the withdraw
   control would be?"
   Chosen: **"The reason line"**. In place of the control, the line
   `Other people have added to this tree, so it stays on the map.`

The planner's eight questions map onto these six answers: Q1 = 1, Q2 and Q5 = 2, Q3 = 3, Q4 = 4,
Q6 = 5, Q8 = 6. Q7 is the orchestrator's choice below.

### R??? — Withdrawing a tree makes no Journal row (the orchestrator's choice, not the owner's)

Recorded as the orchestrator's choice, never as the owner's: every Journal row opens a profile, and
a withdrawn tree's profile cannot open.

---

## Design notes (the author's)

### R??? — The phone withdraws first, and the service's answer settles it

`withdrawTree` sets `community_trees.deleted_at` and queues one `tree_withdrawal`, in one
transaction, at one instant. The queue row's `created_at` and the tombstone hold the same text.

- **When the row fails for good, the tree comes back** (`OutboxQueue.settle`), in the same write as
  the failure. Every terminal failure counts, not only `conflict`: a `forbidden`, or 48 hours without
  a connection, also leaves the tree on the service. Without this step the adder's phone would hide,
  for good, a tree everyone else still sees, because the phone's own row wins over the community
  cache, withdrawn or not.
- **Only that tombstone is undone.** The restore matches `deleted_at` against the row's
  `created_at`, so a tree a lead withdrew some other way (`withdrawRecord`) stays withdrawn.
- **Only `conflict` reads the owner's sentence.** Any other terminal refusal reads the shared
  `This couldn't be sent.`, because "other people have added to this tree" would be false for it.
- **A retry the service accepts takes the tree off again** (`withdrawAgain`, at the row's send).
- **The withdrawal waits for the tree's add** (`waitsForItsTreeAdd`), so the person's order holds:
  add, then any move, then the withdrawal. A move held behind an add that arrived withdrawn would
  fail `not_found`.
- **It is not gated on whether the service has the tree.** The service answers a withdrawal of a
  tree it never received with `applied`, and the add then arrives withdrawn.

### R??? — Who is offered the control

The adder, on this phone's own row, while the tree is live: `adder.isOwned(by: attribution)`, the
Move pin predicate. So a signed-out phone is offered nothing on a tree its account added (the
service treats the device's credential as a stranger to it after a claim, the S1 rule), nor on a
tree whose adder is nobody, a cached tree or a city tree. The verb refuses the same cases:
`forbidden` for a city, cached, somebody else's or nobody's tree, and `notFound` for an unknown or
already withdrawn one. A refusal queues nothing.

### R??? — What "the phone already knows" means (answer 6)

The reason line is drawn only on a fact the phone holds. There are three, and nothing else counts:

1. **A photograph the service served this reader as somebody else's** in its profile read
   (`RoutedAPI.withdrawalOffer`: a photo not in the read's `own_photo_ids`). The service serves
   another identity's photograph only when it is approved, not deleted and its bytes arrived, which
   is a photograph its own rule (`othersHaveBuiltOn`) counts. "Somebody else's" is the service's
   answer for the identity that will send the withdrawal.
2. **A visit, check-in, measurement or care event in this phone's own tables, not deleted, by
   another account** (a `user_id` that is set and is not the reader's), whose queue row no longer
   owes a send. The service never moves one account's rows to another, so such a row is somebody
   else's on the service too.
3. **A withdrawal of this tree that the service already refused with `conflict`.**

What the phone **cannot** know, and therefore never draws the line for:

- **Other people's visits.** The service's profile read carries no visits, and nothing syncs
  anybody else's contributions down. A tree somebody else only visited shows the control, and the
  service's refusal brings the tree back with the owner's sentence.
- **A row this device wrote signed out** (`user_id` empty). A sign-in claims those for the account,
  so the phone cannot tell whether the service counts it as the reader's.
- **A row an account deletion anonymized.** The phone cannot tell whether it reached the service.
- **A visit still in the queue.** The service has not seen it yet.

After a refusal for any reason other than `conflict`, the control is offered again.

### R??? — The alert's two messages follow the profile's own "only you can see" rule

The "only you" message is drawn exactly when the profile tells the reader that only they can see the
tree (`onlyYouCanSeeNote`, round C3); the shared message otherwise. One rule, so the alert can never
say "only you" about a tree the profile says everyone sees, or the reverse.

### R??? — The reads after a withdrawal (answer 5)

The tree leaves the map, the shortlist and the profile (they already filtered `deleted_at`), and
now also the Journal's four contribution arms, the Yours map's four contribution arms, My Grove's
local read, and the service's grove rows as the router resolves them. The adder's visits, photos and
favorite stay saved. This also resolves the planner's finding (g)1 for community trees: the Journal
and My Grove ignored a lead's local withdrawal too, and they no longer do.

### R??? — After a withdrawal the profile closes

The screen leaves through the lead's `withdrewRecord` path. A `notFound` also leaves, because the tree
is already gone. Any other refusal (a sign-out between the read and the tap) reloads the profile, and
the reload draws the record controls as they now are. **No sentence is drawn for that refusal: the
owner has given none, and none was invented.** If the owner wants one, it is theirs to choose.
