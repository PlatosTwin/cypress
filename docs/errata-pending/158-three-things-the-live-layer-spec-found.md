### Three things the #158 spec found that are true whatever the owner rules

Ticket #158, whose deliverable is `docs/design-proposals/2026-08-09-task158-live-layer.md` — a
proposal awaiting an owner ruling. These three are not part of what is being ruled on. They are facts
about the code and about CLAUDE.md, found while reading for that document, and they are recorded here
so they do not wait on a decision they are independent of.

Everything below was read from the declaration, not from a comment about it.

---

#### 1. The two schema-version spaces no longer collide at 14, and CLAUDE.md still says they do

CLAUDE.md's numbering section says: *"There are two schema-version spaces and they now genuinely
collide at 14."* Read from the code at `0e1df35`:

- `AppSchema.currentVersion` (`Cypress/Data/Store/AppSchema.swift`) is the maximum
  `Migration(version:)` in the table, and the newest entry is **14**, *"a species claim can be
  corrected, and the correction keeps it."*
- `SeedDatabase.newestKnownSchemaVersion` (`Cypress/Data/Store/SeedDatabase.swift`) is **16**, set by
  task #237 — `dim_city`, joined through `id_spaces.city_id`, and the drop of
  `id_spaces.short_name`.

They are 14 and 16. They collided when that bullet was written and they do not now.

The bullet is the one place in CLAUDE.md that documents its own failure mode — *"this bullet claimed
the writable one was 13 for a round after v14 landed, which is the confusion it exists to prevent"* —
so this is the second time the same sentence has gone stale, in the same direction, for the same
reason. The rule it states is what caught it: read both from the code, never from that file.

**Not fixed here.** CLAUDE.md is a shared root file and the correction is one line; it belongs to
whoever adjudicates that file rather than to a branch. The rule itself needs no change — only the
example.

#### 2. The outbox drain is what commits a contribution to the local database

`Cypress/Data/DataLayer.swift` wires the queue's transport to `LocalAPI`:
`OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))`. A visit reaches its tree
because a drain called `LocalAPI.sync`, which called `apply(_:)`, which called
`contributions.insert`. There is no other path: the six outbox writers enqueue and return, and every
read in the app is `LocalAPI` over the same local tables.

So `sync` is doing two jobs that look like one — *send* and *commit* — and they are indistinguishable
at the seam. Repointing the transport at `RemoteAPI` when the service lands does not add a network to
an existing local write; **it removes the local write**, and the person's own grove, journal and
profile timeline go empty for everything they contributed. Nothing in the app would report that as an
error, because every layer would be behaving exactly as written.

This is not a defect in the shipping build — today the transport cannot be anything but local — and
it is recorded because it is invisible precisely up to the moment somebody makes the one-line change
that looks like the whole job.

The `outbox` table cannot express the split as it stands: it carries one completion flag,
`json_synced`, under `CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))`.
Two sinks means a second flag and a rewritten table-level constraint — a migration in the
`AppSchema.currentVersion` space, named in the proposal's §7 and deliberately not written there.

#### 3. A lapsed session would convert the whole queue to terminal failures in one pass

`APIError.unauthorized.retryable` is **`false`** (`Cypress/Core/APIError.swift`), and
`OutboxRetryPolicy.nextState` (`Cypress/Core/Models/OutboxItem.swift`) reads exactly that: a
non-retryable code moves an item to `.failed` immediately, without touching the 48 h window.
`OutboxFailureReason`'s sentence for that code, in `Cypress/Data/Outbox/OutboxViewState.swift`, is
*"Sign in to send this."*

Both are correct as written. Together, against a real server, they mean that one expired access token
does not slow a drain down — it ends it, marking every item in the batch terminally failed and
telling a person who is signed in to sign in. Screen 17's promise ("an item that cannot sync says so,
says why, and waits for you") would be kept in form and broken in substance: the items are not
waiting, they have been given up on, and the reason given is false.

The fix is a client one and belongs to whoever builds #158: a 401 is a fact about the transport, not
about the item, so the session refreshes and the batch replays once, and a failed refresh fails the
batch as a transport failure — which `OutboxQueue.drain` already handles by keeping every item alive.
`unauthorized` should reach an item only when the item genuinely is not this identity's to send,
which is what the copy already means.

Recorded now rather than at build time because it is a two-line interaction between two files that
each read correctly on their own, and the failure it produces looks like a server outage.
