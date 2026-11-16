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

**Known limit: ids from the local-account era stay behind.** Builds 6 to 33 (2026-08-03 to
2026-08-14) signed people in locally and minted the account id on the phone (`85467c18`; removed
by `ff7e19d1`, #158 step 5). E277 records that such an account can never be signed into again and
that `claimDevice` does not adopt its rows. On such a phone today, visits, check-ins,
measurements, care events and photographs carry that local id. A tree carries it only when the
phone went from build 35 or earlier straight to a build with migration v23 while signed in. These
rows and trees are never sent: once a real account has signed in, nothing on the phone tells the
local id apart from a real account another person signed out of, so sending them under the account
signed in now could hand one person's work to another. A tree that sends while some of its rows
carry such an id gets its key, and those rows are not tried again. Sending them needs an owner's
ruling that the phone's holder may claim them (E277's open question).

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
