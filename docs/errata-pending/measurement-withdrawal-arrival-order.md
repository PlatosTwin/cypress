# Errata pending — a withdrawal that arrives before the thing it withdraws (server, 2026-09-10)

Unnumbered, per CLAUDE.md "Numbering and shared files". One entry, found while wiring
`measurement_withdrawal` into `POST /sync` (`server/`, pairs with PR #154). It is not a defect that
shipped — nothing in `server/` has ever accepted this kind — but it is the trap the obvious
implementation walks into, and the obvious implementation is the one the existing precedent hands
you.

---

### E??? — `photo_withdrawal`'s "names something this service never held" is a **success that stays**
### true; the same sentence about a measurement is a success that expires

`store.withdrawPhoto` has three answers and the first is *no row → success, changing nothing*. Its
comment justifies that with ERRATA E264: the client has no send path for binaries, so a photo
withdrawal names bytes this service has never held and never will. That reasoning is sound and it is
**specific to photographs**.

Copying the three answers to a reading looks free and is not. `measurement` is one of the six kinds
`POST /sync` has accepted since 001, so it drains through this same handler — "the reading is not
here yet" is a state that **ends**, and the way it ends decides whether the withdrawal was true.

**The bad order is reachable, not theoretical, and the client's own queue is what makes it so.**
`OutboxStore.dueItems` is

    WHERE state = 'pending' AND (next_attempt_at IS NULL OR next_attempt_at <= :now)
    ORDER BY seq

— the ordering is over what is **due**, not over the queue. A `measurement` that failed once is in
backoff and is not due. A `measurement_withdrawal` enqueued afterwards has `next_attempt_at` NULL
and is. So:

1. the withdrawal drains first, finds no reading, answers `applied`;
2. screen 17 settles the row `done` and reads `Trunk · DBH withdrawn`;
3. the backoff expires, the reading drains, and `GET /me/grove` counts it — from then on, forever.

Nothing errors anywhere. The person is told the number is gone on the same screen that is about to
put it back on every other device they own. That is E280's sentence — a service reporting a removal
it did not perform — arriving by the clock rather than by the code, which is why no ownership bug or
missing `UPDATE` would have shown it.

**The fix is the mechanism `anonymized_contributions` already is**, and it needs no new table. The
withdrawal is recorded as an ordinary `contributions` row whose payload names the reading, so a
`measurement` looks for its own withdrawal on the way in and is born tombstoned if it finds one
(`store.measurementWasWithdrawn`, `004_measurement_withdrawal_kind.sql`). Same argument `Apply`
makes for consulting the tombstone before the insert: an item written on Wednesday and drained on
Thursday cannot be stopped by a column on a row that does not exist yet, so the mark has to be
waiting for it.

**What that fix covers, stated exactly — and what it leaves open.** It covers the ordering above:
the withdrawal **committed in an earlier drain** than the reading it withdraws, whether that is an
earlier `POST /sync` or an earlier position in the same batch (the handler's loop applies one item
per transaction, sequentially, so both orderings inside one batch are the committed-first case).
It does **not** cover two drains overlapping in time. The guard is a lookup, not a lock, and a
lookup can only find a row that has committed: `Apply` runs at READ COMMITTED — `Store.Tx` calls
`pool.Begin` with no `TxOptions`, so the isolation is the server's default — and there is **no
unique key on the reading id** anywhere in this schema (both indexes 004 adds are plain), so
nothing makes two transactions about one reading block each other. Reading in transaction A,
withdrawal in transaction B: B counts `matched == 0` and answers `applied`, A's arrival check finds
no committed withdrawal and the reading is born live, both commit, and the grove counts it. That is
this entry's own sentence at millisecond scale rather than at backoff scale, and it is reachable in
the multi-device case — one device draining the reading while another drains the withdrawal.

It is not a regression (before this round the kind was refused outright) and it is not fixed here.
The direction on file, **unverified**, is a transaction-scoped advisory lock keyed on the reading id
taken at the top of both `withdrawMeasurement` and `measurementWasWithdrawn`, which would serialise
only same-reading pairs; it is the top server item in `docs/ROADMAP.md`'s chip backlog. **The
distinction is the point of writing it down**: a mark that waits closes the clock-scale race, and a
mark that waits is not a lock.

**The lookup is scoped to the same owner, and that is the whole safety argument rather than a
detail.** Reading ids travel in every `GET /me/journal` payload. Unscoped, a stranger could file a
withdrawal naming somebody else's reading id and have that person's next drain arrive already
tombstoned — silencing a number by getting there first, with a `applied` on both items and no error
anywhere. `TestAStrangersWithdrawalDoesNotSilenceALaterReading` is the control, and it was
red-proved by deleting the owner clause: the author's tree left the grove entirely.

**What to carry forward — and the property that actually separates the two cases.** It is not
"photographs are further behind". It is **who mints the id**. `beginPhoto` does `photoID :=
uuid.New()` server-side and hands it back, so a `photo_withdrawal` can only ever name an id this
service issued, which means the row exists (or has been deleted) before the withdrawal can be
written. A reading's id is `TreeMeasurement.id`, minted on the phone when the shutter of the measure
sheet closes, so a withdrawal naming it can be composed — and drained — before this service has ever
heard of the reading.

So the question to ask of the next withdrawable thing is not "does it reach us yet" but "**can the
client name it before we know it**". Where the answer is yes, a withdrawal that finds nothing is not
the end of the story and needs a mark that waits.
