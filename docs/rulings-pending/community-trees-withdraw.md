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

### R??? — The export keeps a withdrawn tree's rows (the orchestrator's choice, not the owner's)

Recorded as the orchestrator's choice, never as the owner's. The owner said the adder's rows "stay
saved" and named the Journal, My Grove and the Yours map as the places the tree leaves. The export
promises everything this person recorded on this phone, and nothing in it opens a profile. So the
CSV and the GeoJSON keep every visit, check-in, measurement, care event and pin move on a tree this
phone withdrew. The export reads the Journal's statement without its withdrawn-tree clauses
(`ContributionStore.exportJournalSQL`). A GeoJSON feature still has its position, because the
export resolves the tree through the community layer, which returns this phone's own row withdrawn
or not.

One change reaches past the adder's own withdrawal. Before this round the pin-move part of the
statement already left out a pin move on a tree a lead withdrew, in the Journal and in the export.
The export now lists that pin move too, because it reads every part without a withdrawn-tree
clause. The Journal still leaves it out. Found by the reviewer's re-check, 2026-11-16.

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
- **The erasing door of an account deletion puts the tree back before it discards the withdrawal**
  (`OutboxStore.forgetAccount`), when the service has not accepted the withdrawal yet. The service
  may keep the tree (another identity built on it), and the phone then keeps it too. A withdrawal
  the service already accepted leaves the tree withdrawn.
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
   else's on the service too. An account this phone made itself in builds 6 to 33
   (`CommunityTreeBackfill.phoneMadeAccounts`) does not count: it never reached the service, so
   neither did its rows, and the backfill moves them to the signed-in account.
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
local read, and the service's grove rows as the router resolves them. Two more lists on the You tab
open a tree's profile, and they drop the tree too: the private reminders, and a lead's review
queue. The adder's visits, photos, favorite and reminders stay saved, and the export keeps them
(the orchestrator's choice above). This also resolves the planner's finding (g)1 for community trees: the Journal
and My Grove ignored a lead's local withdrawal too, and they no longer do.

### R??? — After a withdrawal the profile closes

The screen leaves through the lead's `withdrewRecord` path. A `notFound` also leaves, because the tree
is already gone. Any other refusal (a sign-out between the read and the tap) reloads the profile, and
the reload draws the record controls as they now are. **No sentence is drawn for that refusal: the
owner has given none, and none was invented.** If the owner wants one, it is theirs to choose.

### R??? — Under the keep-records door, the queue goes before the account (the author's choice, not the owner's; ROADMAP 192)

The keep-records door makes the account's published trees anonymous on the service, and nobody may
withdraw an anonymous tree (`withdrawCommunityTree` answers `ErrNotTheAdder`, `forbidden`). A
withdrawal still queued at the deletion was therefore refused afterwards, its tree came back on the
phone, and nobody could withdraw it again. So, under the keep-records door only, and only when the
account has a withdrawal queued, `RoutedAPI.deleteAccount` sends the outbox before `DELETE /me`
(`OutboxQueue.sendBeforeAccountDeletion`):

- **Only when a withdrawal is queued** (the orchestrator's decision on the review, not the owner's).
  The step first reads the account's unsent withdrawals. With none, it does nothing: no drain, no row
  made due, and the deletion makes exactly the requests it made before. So a pin move queued by an
  account with no queued withdrawal is not sent first; that case stays with ROADMAP 164.
- **Every row the account queued that the service has not accepted is made due now**, then the
  queue runs its ordinary `drain()` up to eight times (25 rows in each first pass), with the wi-fi
  toggle honored, and stops at the first drain that finds nothing due while no other drain runs.
- **Each drain waits for one that is already running.** `drain()` returns at once when another
  drain runs, so calling it without the wait would not prove anything was sent, and a row the other
  drain holds `uploading` would be counted as unsent. Once the step runs, every kind goes, not only
  withdrawals: a pin move has the same problem (the service refuses a move on an anonymous tree), and
  an ordinary contribution loses nothing by going a little earlier. The 48-hour window and the fail
  count do not change.
- **The deletion goes ahead only if no withdrawal naming the account is left unsent.** A row the
  service settled for good does not hold it. An accepted withdrawal of a published tree keeps the
  tree withdrawn on the phone: the service's answer lists it as anonymized, and the phone's
  `deleted_at` stays. An unpublished tree is listed as deleted instead, and both sides remove it
  (`deleteAccountTrees`). A `conflict` brings the tree back with the owner's sentence, as it does on
  any other day.
- **A withdrawal the service keeps refusing with a retryable answer holds the deletion for up to 48
  hours, and then loses.** Each try shows `Your account was not deleted. Check your connection and
  try again.`, which is not accurate when the connection works and the service is the one
  refusing. When the row's 48-hour window runs out inside the send step, the row fails and its tree
  comes back, the count falls to zero, `DELETE /me` goes out, and the tree then stays public and
  anonymous: ROADMAP 192's outcome, 48 hours later. The Outbox row says the withdrawal failed.
- **If a withdrawal is still unsent** (no connection, or the service did not take it yet), the
  deletion throws before `DELETE /me`. Nothing is deleted on the service or on the phone, and the
  sheet draws its existing line, `Your account was not deleted. Check your connection and try
  again.` The withdrawal row stays in the Outbox with its own reason. No new sentence was needed.
- **Only withdrawals hold the deletion.** A pin move or any other row that did not go stays queued,
  is made anonymous by the door as before, and is sent afterwards. Holding the deletion for every
  kind would let one stuck row keep a person from deleting their account for up to 48 hours.
- **The erasing door is unchanged.** It discards the account's queued rows and puts back the tree
  of an unsent withdrawal (`OutboxStore.forgetAccount`), and the service deletes or anonymizes the
  account's trees itself, so sending first would change nothing it ends with. ROADMAP 188 (a row in
  `uploading` at an erasure) is not settled by this change: the erasing door does not wait for a
  running drain.
- **How long it can take.** With no withdrawal queued, nothing is added: the deletion costs what it
  did before, one `DELETE /me`. With one queued, the step runs up to eight drains first, and each
  sends every identity's due rows and, on wi-fi with the toggle on, every owed photograph. Nothing
  sets a request timeout, so on a connection that reaches nothing each failed batch or photograph
  costs about 60 seconds, and the whole step can take several minutes. All that time the sheet only
  dims its buttons, Cancel is disabled, and nothing shows progress.

---

## Added after pull request 241 opened (branch `feat/withdraw-owner-answers`)

### R??? — The report link hides while the withdraw link shows (the owner's answer, 2026-11-16)

Q: "On a tree you added, the profile shows "Report that there is no tree here" directly above the
new "Withdraw this tree". Should the adder still see the report link on their own tree?"
Chosen: **"Hide it while withdraw shows"**. "The adder sees only "Withdraw this tree". When the tree
cannot be withdrawn because others added to it, the report link comes back as the adder's way to say
the tree is gone." Not chosen: "Keep both links"; "Always hide the report".

This replaces the placement in answer 1 above ("below "Report that there is no tree here"") for the
state in which the withdraw link is drawn.

### R??? — Where that rule lives (the author's design note)

- **In the presentation, over the final profile.** `TreeProfilePresentation.recordDefect` draws
  `.reportable` as nothing exactly while `treeWithdrawal` is `.available`. Every other offer passes
  through unchanged. The rule is not in `LocalAPI`'s offer, because the withdrawal offer is final
  only after `RoutedAPI.withdrawalOffer` has read the service's photographs, and that read can turn
  `.available` into the reason line. A rule in the local offer would hide the report on a tree whose
  profile then draws the reason line, which is the state the owner wants the report back in.
- **The verb `flagNeverExisted` does not refuse the adder.** A report is still a valid act on a
  community tree this phone added, and the verb cannot see the service's photographs, so a refusal
  there could refuse a report the screen offers. The screen simply does not offer it while the
  withdraw link shows.
- **A report the adder already raised is not lost.** It reads `.underReview`, which is not hidden,
  so the profile still draws `This record has been reported as never having held a tree.` beside
  the withdraw link. A queued report is a local flag, so it reads the same way before it is sent.
- A reader who did not add the tree, a signed-out reader on a tree their account added, and a city
  tree never have `.available`, so they see what they saw before.

### R??? — No Retry on a withdrawal refused because others added to the tree (the owner's answers, 2026-11-16)

Q: "When the service refuses a withdrawal because others added to the tree, the Outbox row shows
the reason and a Retry button. A retry is refused again unless those other records are gone. Should
that row keep Retry?"
Chosen: **"Remove Retry there"**. The row shows only the reason. The tree is back on the map, and
the profile shows the reason line where the withdraw link would be. Not chosen: "Keep Retry".

Q: "You chose to remove Retry on a withdrawal the service refused because others added to the
tree. A failed Outbox row has no other control and nothing ever removes one, so without Retry that
row stays in the Outbox for good, showing only the reason. What should happen to that row?"
Chosen: **"Row stays, reason only"**. The row stays in the Outbox with the reason and no button. It
is also what keeps the reason line on the tree's profile, so that line stays correct.
Not chosen: "Keep Retry after all"; "Add a way to clear it".

**The consequence, stated plainly: that row never leaves the Outbox.** Nothing sweeps a failed
row, and the row has no control. An account deletion that erases everything removes it
(`OutboxStore.forgetAccount`, `.eraseEverything`) **when the withdrawal's payload names that
account** (`$.attribution.userID`). A withdrawal can name no account: `LocalAPI.withdrawTree`
accepts the adder by device as well as by account (`ContributionOwner.isOwned(by:)`), so a person
who added a tree signed out can withdraw it signed out, and that payload carries only the device.
`forgetAccount` matches rows by account only, so no deletion ever matches such a row, and it stays
for the life of the install. The `withdrawTreeRefused` debug screen makes exactly such a row: it
signs out first (`DebugDeepLink`), so its withdrawal names only the device. While the row stays,
the tree's profile draws `Other people have added to this tree, so it stays on the map.`, because
`CommunityTreeStore.othersHaveAddedTo` reads that row.

**A deletion that keeps records keeps the row, for good.** With a `failed`/`conflict` withdrawal
present, a keep-records deletion sends only `DELETE /me`. `forgetAccount`'s `.leaveRecords` arm
treats a withdrawal as a contribution: it tombstones the payload's `clientUUID` and removes the
account from the payload (`json_remove` of `$.userID` and `$.attribution.userID`). The row keeps
its state, its `conflict` code and its reason, and its payload no longer names any account, so a
later deletion that erases everything never matches it either: it stays for the life of the
install. `AccountDeletion.forgetCommunityTrees` sets the tree's `user_id` to NULL, so the tree's
adder becomes nobody and the withdraw offer becomes `.unavailable`: the reason line goes away.
The tree is still this phone's own row, so `recordDefectOffer` answers `.reportable`, and the
profile offers `Report that there is no tree here`. The review of the assembled train ran this as
a probe; the author read each step in the code. No test in this branch covers it.

How the branch `feat/withdraw-owner-answers` built it (the author's notes):

- **One rule, in two places.** `OutboxRetryPolicy.acceptsRetry(kind:errorCode:)` refuses exactly a
  `tree_withdrawal` whose last failure code is `conflict`. The screen reads it
  (`OutboxPresentation.Row.showsRetryButton`, `OutboxItemSnapshot.showsRetryAffordance`), and the
  store applies the same rule in SQL (`OutboxStore.retryable`) in `retry` and `retryAllFailed`. A
  test checks the store against the policy for every kind and every code.
- **The row still looks like a failed row.** It keeps the amber card and the reason, and draws no
  state word, because on a failed row the word `retry` is the button. No new string.
- **Every caller of retry leaves the row as it is, and none shows an error.** `OutboxStore.retry`
  returns false, as it does for a row that is not failed. `OutboxQueue.retry` returns false and
  notifies nobody. `OutboxViewState.retry` stops at its guard and does not drain. `retryAll` and
  `retryAllFailed` move every other failed row and leave this one. `CommunityTreeBackfill` retries
  only `add_tree` rows.
- **This also keeps the reason line through a retry attempt.** A retry used to clear
  `last_error_code`, so the profile's reason line went away while the retried row waited.
- **A withdrawal refused for another reason keeps Retry** (`forbidden`, the 48-hour window), and a
  retry the service accepts still takes the tree off again (`withdrawAgain`).
- **Nothing else on screen counts this row.** The Outbox header counts only rows that are still
  trying (`waitingCount`), the app has no "Retry all" control (`OutboxViewState.retryAll` has no
  caller on screen), and the You tab shows no Outbox count.
