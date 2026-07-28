### deleting your account did not stop the next one adopting your records

Account deletion offers two doors and the default is the kind one: *leave my records, unattributed*.
It nulls `user_id` on the four contribution tables and leaves `device_id` alone, which is the correct
thing to do with `device_id` — it is `NOT NULL` there, it is D9's anonymous installation handle, and
the row carried it before there was an account and would carry it if there had never been one.

D9 also says what a row in that shape *is*. `user_id IS NULL AND device_id = this phone` is the
definition of **this device's unclaimed work**, and `claimDevice` moves such rows onto the account
that signs in. So the leaving door produced rows that were, by every predicate in the app, the
phone's to give away, and the next account signed in on that phone took them. The journal, the grove
and screen 15's count read the same predicate and showed them for the same reason. Records a person
deliberately unlinked from themselves became linked to whoever came next: on a shared or handed-down
phone, a re-identification of somebody who had asked not to be identifiable.

The behaviour is older than the two-door deletion — it is D9's, and E136 recorded it as a known hole
and left it to the owner. What made it a defect rather than a quirk is that E136 also put the promise
on screen in words. `AccountDeletionCopy.leaveRecordsBody` said the records stay "with nothing left
on them saying they were yours", and that was true until somebody signed in. A promise on screen that
the database does not keep is not a backlog item.

The project owner ruled: *"Yes, anonymize with tombstone."* Rows anonymised by a deletion are marked,
and are skipped for ever.

**The shape, and the two obvious alternatives that are wrong.**

*Clearing `device_id` instead* is one `UPDATE` and it fails twice over. The column is `NOT NULL` on
all four tables, so the state does not exist; and if it did, it would erase the distinction the whole
fix rests on. **Anonymised by a deletion** and **never had an account** currently look identical, and
they are not the same thing: the second is D9's own case, an unsigned-in contributor keeping their own
work on their own phone, and it must go on being claimed. A fix that made those two states equally
unclaimable would trade one broken promise for another.

*A column on each of the four tables* — `anonymized_at`, in `deleted_at`'s shape — is the house's
usual move, and it closes the four tables while leaving the hole that matters open. A contribution
lives in the outbox between being written and being applied: `OutboxStore.forgetAccount` strips
`$.userID` out of the queued payload and the row is **inserted for the first time after the deletion
has already run**. A column-based tombstone has nothing to write on, because at deletion time the row
does not exist, and by the time it does the deletion is long over. It would be born unmarked and
adopted by the next account — the original defect with one extra step in front of it, under a
mechanism that looked complete.

So the tombstone is `AppSchema` **v13**, a side table keyed on the one identity a contribution has
*before* it is stored as well as after:

```sql
CREATE TABLE IF NOT EXISTS anonymized_contributions (
    client_uuid   TEXT PRIMARY KEY COLLATE NOCASE,
    anonymized_at TEXT NOT NULL
);
```

`client_uuid` is the idempotency key (BUILD-PLAN §4, DECISIONS §3.8). It is `NOT NULL UNIQUE` on all
four tables and a top-level key on all four payloads, so a deletion can tombstone a record that has
not been stored yet and the mark is waiting when the queue drains. That is the property a column
cannot have, and it is the whole reason for the shape.

`COLLATE NOCASE` sits on the key rather than on every reader because a UUID reaches this table by two
routes — `SQLiteValue`'s uppercase `uuidString` from a stored row, `JSONEncoder`'s from a queued
payload — and a guarantee should not turn on those two agreeing about case for ever.

The table holds a `client_uuid` and a timestamp and nothing else: no `user_id`, no `device_id`, no
tree. It says *this record is nobody's*, which is all that is needed. Storing the account it came from
would rebuild exactly the joining key `AccountDeletionChoice` refuses a sentinel id for — a stable
handle relinking one person's whole history of trees, dates and times.

**Which tables.** The four with `device_id NOT NULL`: `visits`, `observations`, `measurements`,
`care_events`. The anonymising path also names `photos` and `photo_votes`, and neither needs a
tombstone, for a reason worth writing down rather than assuming: both carry **at most one** owner
(v12 and v9), so an account-owned row has `device_id IS NULL`, and anonymising leaves both columns
NULL. `claimDevice`'s `device_id = :device` cannot match it. `tree_names`, `review_flags` and
`tree_status_overrides` are anonymised too and have no device column at all, so no claim path reaches
them. `private_reminders` and `favorites` are deleted with the account under both doors. The
tombstone lands on exactly the tables that can be re-adopted, and on all of them — a tombstone on
three of four would have been worse than none, because it would have made the guarantee look kept.

**Where the mark is read, and why it is five places and not one.** `claimDevice` is the only writer
that re-adopts, and it is called from two places (`LocalAPI.claimDevice` and the per-batch re-claim
`adoptRowsWrittenAfterTheClaim`), so guarding the function guards both. But `user_id IS NULL AND
device_id = :device` means *the work of the phone in your hand* in four more queries —
`deviceContributions`, `journal`, `groveTreeIDs`, `groveRecords` — and a tombstone applied to the
claim alone would have stopped the rows moving while going on displaying them. The next person to
sign in would read a stranger's visits in their own journal, and screen 15 would offer to keep a
count of records the claim then declined to move: the promise visibly broken in the one place a
person can see it. The clause is named once, as `ContributionStore.notAnonymized(_:)`, so that "all
five" is checkable rather than remembered.

That helper takes a table qualifier and it is not decoration. Written `WHERE t.client_uuid =
client_uuid`, SQLite resolves the bare name in the *inner* scope and the condition becomes a
tautology, so `NOT EXISTS` is false for every candidate row and the claim silently adopts nothing at
all. A guarantee that inverts on a name-resolution rule is not one.

**What it costs, stated because the owner weighed it and chose it.** Someone who deletes their
account and signs back in on their own phone does not get their own work back. There is no escape
hatch and one was not built: any mechanism that could return the records to the right person is a
mechanism that returns them to the wrong one, since nothing in the database distinguishes the two.
The copy on screen now says so, in the same breath as the promise rather than as a separate warning:

> Nobody can tell afterwards that they were all one person's, and that includes this phone: if you
> make a new account here, they do not come back to you.

It is written as a consequence of the promise, not as a caveat to it, because it is the same fact
seen from the other side — and a person who reads the first sentence and believes it should not need
a second paragraph to learn what believing it costs.

**Not changed, deliberately.** The records stay on their trees and are still read by every
tree-scoped query, which is the entire point of the door: `treeProfile` returns the visit, the
photograph keeps its place, the vote still counts toward the hero. What the tombstone removes is
ownership, not existence. And `AccountDeletion.Outcome` gained no counter for it — the number of
tombstones is the number of anonymised contributions, already reported, and a second field carrying
the same total is a field that will one day disagree with the first.
