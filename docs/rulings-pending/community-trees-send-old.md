# Rulings pending: how the phone sends the community trees that predate syncing (ROADMAP 139, phone piece)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

This entry is the author's reading of the owner's rulings, within delegated authority, logged for
review. It applies `community-trees-old-trees.md` (2026-11-14), the first entry of
`community-trees-answers-2026-11-15.md`, and `community-trees-added-day.md`. It records every place
where the phone could not know a fact and a narrow rule was chosen. The code is
`Cypress/Data/Outbox/CommunityTreeBackfill.swift`; its header carries the same reading.

---

### R??? — The one-time send: which trees, which rows, which photographs

**When it runs.** In `DataLayer.boot`, after the identity is reconciled and before the first
drain, and again after every claim of the device by an account (`LocalAPI.claimDevice`). Only when
the send sink is wired: with no sink a queued row settles `done` without being sent, and the record
below would claim a send that never happened. The UI suite runs with the sink off, so the backfill
never runs there.

**The record that it ran.** One `app_state` key per tree, `community_tree_queued_once:<tree id>`
(`CommunityTreeStore.queuedOnceKey`), written last, in the same transaction as the tree's rows. No
phone migration: `app_state` is the existing key/value table, and the refused-photo keys are the
precedent. The outbox cannot be the record, because `pruneCompleted` deletes a `done` row a day
later. `LocalAPI.addTree` writes the key for every new tree too, so a new tree is never swept again.

**Which trees.** Live rows of `community_trees` (trees this phone added) with an adder and no key.
The latest `add_tree` outbox row for the tree decides:

| The add row | What the tree gets |
|---|---|
| none, tree added before `CommunityTreeStore.firstQueuedAddsAt` (an old tree) | a new add, its add photo, every live row on it, and its old photographs |
| none, tree added later (its add went and was pruned) | a new add with the same `client_uuid`, which the service answers `duplicate`, so the add photo has an item to ride on; nothing else |
| `failed` with `conflict` | the row retried once, with `addedOn` added; the tree then treated as an old tree |
| `pending` or `uploading` (queued by an earlier build) | its add photo staged on that row, and `addedOn` set on it when it has none (owner's decision of 2026-11-15) |
| `done`, or `failed` with any other code | left alone and not recorded; a `done` row is looked at again once it is pruned |

**Narrow rule: a refused add is recognized by `conflict` alone.** Under every version of the
service an `add_tree` was answered `conflict` only by the 10 m rule (checked in the history of
`server/internal/api/sync.go`: commits `fe1ff4ab`, `7f9d40ec`, `f68214cd` and `bd8a35af~1`). The
phone stores the code on the row (`last_error_code`). So a failed add with `conflict` is a
proximity refusal, and a failed add with any other code is left for the person, because sending it
again would be refused again. The retry happens once: if the service still refuses it, the row
stays failed and nothing retries it automatically again.

**What rows go.** For an old or refused tree: every live visit, check-in, measurement and care event
on it, each queued already applied under its own `client_uuid`. A row the service holds is answered
`duplicate`. A withdrawn row (`deleted_at` set) does not go. Species statements, favorites, reminders,
reports and votes do not go: the owner's list names visits, measurements, care and photographs, and
the species travels in the add. Rows on a city tree do not go (R77 stands for them).

**The add.** Built from the tree's row: the head position, the current species, the stated land
context, and the adder. `occurredAt` is the tree's `created_at`, the instant of the add, and
`addedOn` is that instant's date in the phone's current calendar and time zone. The service keeps
`addedOn` only within a day of `occurredAt`'s UTC date, so `occurredAt` is never the time of the
resend.

**Known limit: the time zone is the one at the time of the run.** The phone did not record the zone
an add was made in. A phone that has changed zones since can state a day one off from the day the
person saw. The service's one-day window accepts it, so the tree shows that day.

**Anonymized rows never go.** The leaving door of an account deletion keeps a row's `device_id` on
the four contribution tables and records its `client_uuid` in `anonymized_contributions` (E157).
Such a row reads as this device's own work, so the backfill reads every row through
`ContributionStore.notAnonymized`. Without it, the row would go out under whoever is signed in now,
and the service would store it as theirs. An anonymized tree or photograph has no owner at all, and
is refused twice: the candidate query skips a tree with no owner, and `Identity.maySend` refuses an
owner of nobody.

**One tree's failure stops nothing else.** Each tree's transaction is caught in the run. A tree
that throws rolls back, keeps no key, and is tried again at the next launch; the trees after it
still go. There is no limit on the tries: each is one rolled-back transaction at launch, and a
limit would need a second record and would leave the tree behind for good.

### R??? — Which photographs are sent, and how the phone knows

A photograph may be sent only if the service cannot already hold it. The service matches a begin on
its key, and the phone's key for a photograph is `photos.id`. Builds from the first photo send path
until report F30's fix keyed a begin by the queue row's id, and that row is deleted once the send
completes, so the phone cannot tell whether such a photograph reached the service, and sending it
again under `photos.id` would make a second copy. So exactly two kinds go:

- **The add photo** of every tree (`visit_id` NULL, `storage_key` NULL, `local_path` set). No build
  ever staged it for a send (`LocalAPI.addTree` ingested it and queued no binary), so the service
  has none. From this build on, `addTree` stages it on the add row itself.
- **A photograph created before 2026-08-23 05:57:21 UTC** on an old or refused tree. That is the
  date of commit `79f983b1`, the first commit with a photo send path; no build could send anything
  earlier. `build-55`, the first build tag that contains it, is later, so the earlier date is the
  safe one.

**Not sent:** any other photograph on these trees (one a build may have sent, keyed by a row id the
phone no longer holds); any photograph a queue row or a refusal record names; a missing file; a
file that is not a JPEG (the service stores every photograph as `photos/<id>.jpg`); and a
photograph whose owner this phone cannot send for now (below). A file that is an image but not a
JPEG (a HEIC or PNG picked from the library, which the ingest keeps in its own container) is sent as
a JPEG copy, encoded fresh with only the orientation tag; the person's own file is not changed.
**Known limit:** a photograph taken
after that date on a build that could not send yet, and never sent, stays on the phone. The phone
holds nothing that tells it apart from one that was sent.

**Where a photograph rides.** The add photo, and an old photograph with no visit, ride on the add
row; an old visit photograph rides on its visit's row, and only on a row this run wrote, so a
photograph is never staged twice. Each is staged already applied, with its row id equal to
`photos.id`, so the begin's key is `photos.id`.

**What leaves the phone.** The send sink strips location and time data from every file it sends,
new or old, right before the bytes go (`APIOutboxSendSink.uploadPhoto`), and keeps the orientation
tag. A file that still carries them after the repair, or an image that cannot be made a JPEG, is
refused for good and recorded as refused: the person sees a failed Outbox row with the reason, and
tapping retry settles it. The repair replaces the file in one `rename`, so a process killed during
it leaves either the old file or the clean one, never neither.
The begin is dated by the photograph's own `captured_at`; it used to be dated by the queue row's
creation time, which is months off for an old photograph. Others are served the date and never the
time (decision 14a).

### R??? — Who may be sent for (the signed-out phone)

A new tree is attributed to whoever is signed in when it is added, and is sent under whoever is
signed in when the queue drains. Signed out, that is this device: the service keeps the tree
unpublished and publishes it when the device is claimed at sign-in (if the account accepted the
license). An old tree whose adder is this device follows exactly that.

**Narrow rule: an account's tree waits for that account.** A tree, row or photograph whose owner is
an account cannot be sent while that account is not signed in: the service refuses an item naming an
account under the device credential with `forbidden`, for good, and sending it as the device instead
would let the next account to sign in on this phone claim it. A new tree never reaches this state
(it is queued with the identity of the moment). So such a tree is skipped with nothing queued and no
key written, and the run after that account signs in on this phone sends it. A row on a sent tree
whose owner is another account, or another device, is left behind. A tree with no adder (anonymized
by an account deletion) is never sent.

### R??? — The accounts the phone made itself (owner's ruling, 2026-11-16)

**The case.** Builds 6 to 33 (2026-08-03 to 2026-08-14) signed people in on the phone alone and
minted the account id there (`85467c18`; removed by `ff7e19d1`, #158 step 5). E277 records that
such an account can never be signed into again and that `claimDevice` does not adopt its rows. On
such a phone today, visits, check-ins, measurements, care events and photographs carry that id. A
tree carries it only when the phone went from build 35 or earlier straight to a build with
migration v23 while signed in.

**The question, as put to the owner (AskUserQuestion, 2026-11-16).** "Chip 139 sends old community
trees with everything recorded on them. One case cannot be sent safely: builds 6 to 33 (August 3 to
14) created accounts on the phone itself, and such an account can never sign in again. On a phone
from that time, visits, check-ins, measurements, care, and photos recorded under that old account
stay behind; the tree itself is still sent. Your own phone is the likeliest to hold such records.
The phone cannot tell that old account from another real person's account, so sending those
records under the account signed in now could put one person's work under another's name on a
shared phone. What should the next build do?"

- "Leave those records" (recommended).
- **"Send them under the current account"** (chosen): "Records under any account that is not the
  one signed in now, and that the phone made itself, go out under the account signed in now. On a
  phone two people used, this can mislabel records."
- "Send them with no name".

The owner chose "Send them under the current account", accepting that on a shared phone this can
mislabel records.

**The rule built.** A phone-made account is an id that appears as `user_id` on a row this phone
made before 2026-08-14 07:27:48 UTC (`CommunityTreeBackfill.serviceSignInExisted`), other than the
account signed in now. That instant is the commit time of `64a8d1e3` (#158 step 3), the first commit
with any code that reaches the service's sign-in (`/auth/oidc`). The Apple button reached it later
that day (`ff7e19d1`, first in `build-34`, tagged 2026-08-15 03:26 UTC). So no build before that
instant could hold a service account's id, and an id on an earlier row was minted on the phone. The
rows read to learn the ids are visits, check-ins, measurements and care events whose `device_id` is
this device, photographs whose `taken_on_device` is this device, and this phone's own
`community_trees`, city trees included. Other people's trees live in the community cache and are not
read. A row of any later date counts once its owner is in the set.

While an account is signed in, the tree of such an account, and such an account's live rows and
photographs on an old community tree, become the signed-in account's on the phone in the same
transaction that queues them, and go under it. On a signed-out phone they wait. On a tree that went
before they could (a signed-out run, or a build of this branch before this ruling), a second pass
in the same run sends exactly those rows and photographs: a visit's photograph on its visit's row,
and a photograph with no visit on the tree's add (the one still queued, or a new one under the
tree's own key, which the service answers `duplicate`). Moving a row to the signed-in account is
what marks it done, so nothing goes twice. City-tree rows stay on the phone (R77), with their owner
unchanged. An anonymized row has no owner and is never one of these.

**Why the rows change owner on the phone, rather than only being sent.** The service stores a
synced row as the sender's. A row sent as B but still owned by the old id here would be B's on the
service and nobody's to edit or withdraw on the phone (E277), and the two deletion doors would
disagree: erasing B would delete it on the service and keep it here. Changed here, it is B's on both
sides.
- **"Delete my records"** (`eraseEverything`) deletes these rows and photographs on the phone with
  B's other rows, and the service's `DELETE /me` deletes them there, because the service holds them
  as B's.
- **"Leave my records"** (`leaveRecords`) un-names them on both sides: the phone sets `user_id` to
  NULL and tombstones each row (E157), and the photographs become nobody's.

**Limits.**
- On a phone two people used in the local-account era, one person's work goes out under whoever
  signs in. The owner accepted this.
- A phone whose clock was set before 2026-08-14 while a real account was signed in would count that
  account as phone-made. Its rows would then go under whoever signs in next on that phone.
- A phone-made account with no row before that instant is not found. Such an account would have
  had to be made on 2026-08-14 between 07:27 and the phone's update to build 34. Its later rows,
  from builds 34 and 35, count when the account has any earlier row, because the set is of ids.
  Build 36 signs a stored local account out at launch (`SessionRestore.reconcile`), so no later
  build made rows under one.
- Only old community trees (added before adds were queued) are covered. A phone-made account's row
  on a tree that is not old is not sent. No build could make one, because the local-account era
  ended before adds were queued.

**A limit, not a ruling: a tree whose adder deleted their account.** Such a tree has no owner on
the phone, so it is never sent. The rows that a different account, the one signed in now, made on
that tree are not sent either, because they go only with their tree. The review measured it: one
run over such a tree reported `Report(trees: 0, rows: 0)`.

### R??? — Move pin, and the deletion doors

- **Move pin** (`CommunityTreeStore.mayHaveReachedService`): an existing add row still decides
  (a failed one says no); with no row, the key says yes; with neither, the date decides as before.
  Without the key, an old tree lost the offer again a day after it was sent.
- **Deletion.** The queued rows are ordinary kinds, so `OutboxStore.forgetAccount` treats them as
  contributions under both doors. Both doors delete the keys of trees that are gone
  (`AccountDeletion.forgetCommunityTrees`).

### R??? — The Outbox screen, and the volume

Each queued item is an ordinary row with today's labels (the owner's answer of 2026-11-15). No
string was added. The rows are timed by when they were queued, which is the update day. On the
owner's phone the volume is dozens to a few hundred rows; the drain sends 25 per batch, and
photographs obey the Wi-Fi-only toggle.

### Ordering with the service

The build that carries this should ship only after `cypress-sync` runs the 10 m change
(`bd8a35af`) and migration 008. Before the 10 m change, an old tree near another tree comes back
`conflict` and a refused add's one retry is spent. Before 008, the service ignores `addedOn`, and the
tree's day is the UTC date of `occurredAt` once 008's backfill runs.
