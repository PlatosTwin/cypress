### Four things the #158 spec found that are true whatever was ruled

Ticket #158, whose deliverable is `docs/design-proposals/2026-08-09-task158-live-layer.md`. These four
are not part of what the owner ruled on. They are facts about the code, found while reading for that
document, and they are recorded here because they outlive the proposal.

Everything below was read from the declaration, not from a comment about it.

---

#### 1. The two schema-version spaces no longer collide at 14

CLAUDE.md's numbering section said: *"There are two schema-version spaces and they now genuinely
collide at 14."* Read from the code at `0e1df35`:

- `AppSchema.currentVersion` (`Cypress/Data/Store/AppSchema.swift`) is the maximum
  `Migration(version:)` in the table, and the newest entry is **14** — *"a species claim can be
  corrected, and the correction keeps it."*
- `SeedDatabase.newestKnownSchemaVersion` (`Cypress/Data/Store/SeedDatabase.swift`) is **16**, set by
  task #237: `dim_city`, joined through `id_spaces.city_id`, and the drop of `id_spaces.short_name`.

They are 14 and 16. They collided when that bullet was written and they do not now.

The bullet is the one place in CLAUDE.md documenting its own failure mode — *"this bullet claimed the
writable one was 13 for a round after v14 landed, which is the confusion it exists to prevent"* — so
this is the **second** time the same sentence has gone stale, in the same direction, for the same
reason. The rule the bullet states is what caught it: read both from the code, never from that file.

The correction to CLAUDE.md is landing separately (PR #65) rather than from this branch, because it is
a shared root file. **The rule needs no change — only its example, and the entry worth keeping is that
the example is what rots.** A version number written into prose is a number that will be wrong; the
two constants above are the only place either question has an answer.

#### 2. The outbox drain is what commits a contribution to the local database

`Cypress/Data/DataLayer.swift` wires the queue's transport to `LocalAPI`:
`OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))`. A visit reaches its tree
because a drain called `LocalAPI.sync`, which called `apply(_:)`, which called
`contributions.insert`. There is no other path: the six outbox writers enqueue and return, and every
read in the app is `LocalAPI` over the same local tables.

So `sync` is doing two jobs that look like one — *send* and *commit* — and they are indistinguishable
at the seam. Repointing the transport at `RemoteAPI` when the service lands does not add a network to
an existing local write; **it removes the local write**, and the person's own grove, journal and
profile timeline go empty for everything they contributed. Nothing would report it as an error,
because every layer would be behaving exactly as written.

Not a defect in the shipping build — today the transport cannot be anything but local. Recorded
because it is invisible right up to the moment somebody makes the one-line change that looks like the
whole job.

The `outbox` table cannot express the split as it stands: one completion flag, `json_synced`, under
`CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))`. Two sinks means
a second flag and a rewritten table-level constraint — a migration in the `AppSchema.currentVersion`
space, named in the proposal's §7 and deliberately not written there.

#### 3. A lapsed session would convert the whole queue to terminal failures in one pass

`APIError.unauthorized.retryable` is **`false`** (`Cypress/Core/APIError.swift`), and
`OutboxRetryPolicy.nextState` (`Cypress/Core/Models/OutboxItem.swift`) reads exactly that: a
non-retryable code moves an item to `.failed` immediately, without touching the 48 h window.
`OutboxFailureReason`'s sentence for that code, in `Cypress/Data/Outbox/OutboxViewState.swift`, is
*"Sign in to send this."*

Both are correct alone. Together, against a real server, one expired access token does not slow a
drain down — it ends it, marking every item in the batch terminally failed and telling a person who is
signed in to sign in. Screen 17's promise ("an item that cannot sync says so, says why, and waits for
you") would be kept in form and broken in substance: the items are not waiting, they have been given
up on, and the reason given is false.

The fix is at the transport and belongs to whoever builds #158: a 401 is a fact about the session, not
about the item, so it refreshes and replays the batch once, and a failed refresh fails the batch as a
transport failure — which `OutboxQueue.drain` already handles by keeping every item alive on the
backoff. `unauthorized` should reach an item only when the item genuinely is not this identity's to
send, which is what the copy already means.

Recorded now rather than at build time because it is a two-line interaction between two files that
each read correctly on their own, and the failure it produces looks like a server outage.

#### 4. `RemoteAPI` conforms to `CypressAPI` while implementing fewer than two thirds of it

`CypressAPI` declares **31** requirements. `RemoteAPI` (`Cypress/Data/API/RemoteAPI.swift`) declares
**17** methods. The other fourteen are satisfied by protocol-extension defaults, and the conformance
compiles either way.

Ten of the fourteen throw `.notFound` — the four species-claim methods
(`Cypress/Data/API/SpeciesClaim.swift`), the three record-defect methods
(`Cypress/Data/API/RecordDefect.swift`), and `photoData`, `setPhotoVote`, `deletePhoto`
(`Cypress/Data/API/PhotoAccess.swift`). Those are loud.

**Four return a value, and three of those four are the finding.** `speciesGuide`
(`Cypress/Data/API/SpeciesGuide.swift`) returns the field-guide entry with no population facts;
`mapMembership` (`Cypress/Data/API/MapMembership.swift`) returns the empty set; `deviceContributions`
(`Cypress/Data/API/DeviceContributions.swift`) returns `.none`; `isFavorite` derives from `grove()`.

Every one of those defaults is correct **for what it was written for** — an implementation with
nothing behind it, saying nothing rather than saying zero. What makes this an entry is that they are
also what a *finished* `RemoteAPI` would inherit if somebody forgot a method: a species guide with no
population line, a map on which nothing is yours or favorited, and a device that has contributed
nothing — rendered as answers, silently, with the conformance complete and the build green.

`deviceContributions` is the one that should stay inherited, and `RemoteAPI` says so in a comment
where the method would be. The other thirteen are places where "it compiles" is not evidence of an
implementation. The general form of the trap is already numbered — ERRATA **E125**, the day an
extension member's static dispatch made every photograph in the app fail to load on a build whose
tests all passed — and this is its other half: not a requirement that should have been in the
protocol, but a requirement that is in the protocol and whose default is comfortable enough to hide
a missing implementation.

The cheap guard, named rather than written: a test that holds `any CypressAPI` and asserts each
method reaches the concrete implementation rather than the extension.
