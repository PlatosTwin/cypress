# Unnumbered — the app goes live, and three sentences stop being true (task #158, the wiring round)

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `feat/158-wiring`, the round in which `DataLayer.boot`
stopped constructing a `LocalAPI` and started constructing a router with a server behind it.

Six findings. The first three are copy questions the owner has to answer and this branch
deliberately did not; the fourth is a defect in the service that only becomes reachable now; **the
fifth is blocking and is why this round does not work in production** — read it first.

---

## 1. Wiring the send sink makes screen 18's storage line false, and the mocks have no arm for the state it is now in

`Cypress/Features/Visit/VisitSaveLedger.swift`'s `storageLine` draws one of two sentences:

- ask resolved → **"Saving to this phone only. You can add an account any time."**
- otherwise → **"Saved to this phone. You can add an account later to back it up."**

Both were true while the outbox had one sink. They are not true now. `DataLayer.boot` wires
`APIOutboxSendSink` over `RemoteAPI`, and D9 makes the *anonymous* case the normal one rather than
the exception — `AppSession.authorization()` says why in one line: "a queue that could not drain
without an account is a queue that fills up." So an installation that has never opened screen 15 is
sending its visits to `cypress-sync` under a device credential, and the word "only" is a claim about
where somebody's work is that the app can no longer make.

**Why it was not simply rewritten.** PROTOTYPE-FLOW §1.4 gives three arms and every one of them keys
on `account`:

| arm | string |
| --- | --- |
| `linked` | `Backed up to your account · joins the public timeline when signal returns.` |
| `dismissed` | `Saving to this phone only. You can add an account any time.` |
| otherwise | `Saved to this phone. You can add an account later to back it up.` |

The brief for this round said both replacement strings already exist in the corpus and to use them
rather than invent any. **The strings do exist** — `AccountAskCopy.body` at
`Cypress/Features/AccountAsk/AccountAskPresentation.swift`, and the `linked` arm verbatim in
`docs/distilled/PROTOTYPE-FLOW.md` §1.4. What does not exist is the **state**. The `linked` arm needs
somebody signed in, and Sign in with Apple is blocked on an entitlement this repository cannot add
(`docs/errata-pending/158-the-session-lands-and-the-sign-in-sheet-cannot.md`, §2), so on every build
producible from this tree it is unreachable. The state the app is actually in is **anonymous, and
sent**, and the mocks enumerate four account states — `none`, `ask`, `linked`, `dismissed` — none of
which is it.

A fourth sentence is copy, and copy is not an engineer's to write (DECISIONS constraint 21). So the
line stands, wrong, with the reason written above it in the source, and this is the ask. Two prose
comments that asserted the opposite — `RootView.accountLink()`'s "screen 18's 'saving to this phone
only' stays true after it" and `VisitSavedView`'s "which stays true" — were corrected in the same
commit, because a confident comment is where bugs survive here.

## 2. Screen 15's copy went the other way, and that one *is* resolved — by deletion

`BetaCapability.accountsAreLocalOnly` and `AccountAskCopy.bodyLocalAccount` are gone.

ERRATA **E131** introduced them because SCREENS.md §2's drawn sentence — "An account backs them up
and lets them join each tree's public timeline" — made two promises a local account kept neither of,
and it substituted a sentence ending "**nothing is uploaded, and none of the services below has been
contacted**".

That substitute is the sentence this round makes false, and flatly: the outbox uploads, and
`cypress-sync` has been contacted before anybody reads the screen. Meanwhile both of §2's promises
became the service's actual behavior — `POST /devices/claim` re-homes this device's rows onto the
account, and `photos.go` auto-approves a photograph from a signed-in account where a device's stays
`pending`, which *is* joining the tree's timeline. So the constant ended the way `BetaCapability`'s
own header says a capability constant should end: **by deletion, with the drawn copy returning**, not
by a flip.

**The residual, stated rather than left to be found.** §2's first clause is "They live on this phone
right now", and after this round they live on this phone *and* on the service, unattributed to any
account. It is the mocks' own sentence and it is far closer to true than what it replaced, so it is
drawn; whether it wants a word changed is the same owner question as (1) and belongs with it.

## 3. Screen 17 says "No connection." to somebody with four bars, and SCREENS.md names no sentence that would fix it

Review of PR #77 flagged this and it becomes live here. `OutboxFailureReason.sentence(for:)`
(`Cypress/Data/Outbox/OutboxViewState.swift`) answers **"No connection."** for any error outside the
`APIError` taxonomy, and that fallback now catches two things it did not before:

- **`SessionError`.** `SessionTransport` deliberately converts every credential failure into a
  `SessionError` rather than `APIError.unauthorized`, because `unauthorized.retryable` is `false` and
  a lapsed session would otherwise move the whole queue to `.failed` in one pass and print "Sign in
  to send this." to somebody who is signed in (spec §5.8, ERRATA E261 §3). That design is right and
  this entry does not question it. Its leftover is the *sentence*: a refused refresh on a good
  connection renders as "No connection."
- **`SessionError.malformedResponse`.** A 2xx body this client cannot decode is a shape mismatch, and
  it also renders as "No connection." This is not hypothetical — it is how the first draft of
  `DataLayerWiringTests.theSendPathCannotProduceARemoteSurface` went red, with a fixture whose error
  envelope was the wrong shape.

**What SCREENS.md offers: nothing.** Screen 17's section (`docs/distilled/SCREENS.md`) names no
per-cause sentence at all. Its whole failure vocabulary is a row sub-label (`upload failed twice`), a
header pill already overruled by E81, and the footnote promise — *"Nothing here disappears silently.
An item that cannot sync says so, says why, and waits for you."* The eight per-code sentences the app
draws are engineer-authored against BUILD-PLAN §6's list of **codes**, which carries no copy.

So there is no honest sentence to pick, and the footnote is the thing being broken: the item does
wait, and it does say why, and the why is false. This is the ask. Note that the *retry* behavior is
correct in every case above — an item outside the taxonomy stays alive on the backoff, which is
exactly what a session failure should do — so this is a copy defect and not a queue defect.

## 4. The 72 h photo grace window is documented on both sides and swept by nothing, and `PhotosForTree` does not filter on it

Found while establishing whether the photo half of the outbox could be given its second sink this
round (it could not — see the PR body). It is a service defect independent of that question.

`POST /photos/begin` inserts a `photos` row and returns a presigned `PUT`.
`POST /photos/{id}/received` sets `bytes_received_at`, which `store.MarkPhotoBytesReceived`'s own
comment calls "closing the 72 h grace window", and `PhotoUploadTicket.binaryGracePeriod` says the
same on the client. **Nothing collects the rows where that window stays open.** There is no sweeper
anywhere in `server/` — no cron, no ticker, no `DeleteExpired` — and
`server/internal/store/photos.go`'s `PhotosForTree` selects every row for a tree with no predicate on
`bytes_received_at` at all.

The consequence: a `begin` whose `PUT` never lands leaves a **permanent phantom photograph** on that
tree for every reader. `GET /trees/{id}` returns it, `RoutedAPI.treeProfile` merges it into the
photo series, and `photoData(id:)` hands back a presigned GET for a storage key holding nothing —
which the client correctly turns into a failed read, on a photograph the profile said was there.

Two independent repairs, and it wants both: filter `PhotosForTree` (and `reads.go`'s hero-photo
query) on `bytes_received_at IS NOT NULL OR created_at > now() - 72h`, so an in-flight upload is
still its own contributor's and an abandoned one is nobody's; and sweep the abandoned rows and their
storage keys, because a row nothing will ever fetch is still a row.

**This is also the reason the photo send sink is not in this round.** Any retry of a failed binary
send must call `POST /photos/begin` again — the route mints a fresh id per call and takes no
idempotency key — so every retry leaves an abandoned row behind, and with no sweeper each one is a
phantom photograph rather than a row that quietly expires. The design ERRATA **E264** assigns to its
own ticket therefore has a server prerequisite that E264 did not know about.

## 5. **BLOCKING** — `POST /sync` refuses every anonymous item, because two different identifiers are both called "device id"

Found by running the wiring round's own client code against the deployed service. It is the reason
this round's deliverable does not work in production, and it is a server defect.

### What happens

Every item an anonymous installation sends comes back:

```
{"results":[{"client_uuid":"…","status":"failed","error":"forbidden",
             "message":"That item belongs to a different device."}]}
```

`APIError.forbidden.retryable` is `false`, so `OutboxRetryPolicy.nextState` moves the row straight to
`.failed` — not after 48 h, on the **first drain** — and screen 17 prints *"This account is not
allowed to send that."* to a phone doing exactly what D9 asks of it. Measured through the real
composition root: `DrainReport(attempted: 2, … failedTerminally: 2, sent: 0)`, both rows
`applied=true sent=false`.

### The mechanism, isolated with a control

Three probes against `https://cypress-sync.fly.dev`, one device token, same item shape:

| probe | `device_id` sent | answer |
| --- | --- | --- |
| A | the caller's own registered `device_uuid` | `forbidden` — "That item belongs to a different device." |
| B | some other UUID | `forbidden` — same message |
| C | **omitted** | `applied`, and `GET /me/grove` returns the row |

A and B answering identically is the finding. The comparison in `applyOne`
(`server/internal/api/sync.go`) is

```go
if item.DeviceID != nil && *item.DeviceID != *who.DeviceID {
    return failed(apierr.Forbidden, "That item belongs to a different device.")
}
```

and the two sides are in different vocabularies:

- `item.DeviceID` is the **client's** installation id — `app_state.device_uuid` (D9), the value the
  phone registers with and sends to `POST /devices/claim` as `device_uuid`.
- `who.DeviceID` is `devices.id`, a **server-minted row key**:
  `store.RegisterDevice` inserts `devices (id, device_uuid) VALUES (uuid.New(), $deviceUUID)` and
  `DeviceTokenOwner` returns `device_tokens.device_id`, which is that row key.

They can never be equal, so the predicate is `true` for every item that carries a `device_id` at
all. `claimDevice` gets this right — it resolves `device_uuid` through `RegisterDevice` before using
it — so the translation exists in the codebase; `applyOne` is the one place that skipped it.

### Why nothing caught it

`server/internal/api/api_test.go` has no test that sends the caller's own `device_uuid` and expects
success. Every green sync test **omits** `device_id` (probe C's shape), and the single test that
sends one sends `uuid.New()` — a stranger's — and asserts the refusal. So the happy path of the
anonymous client is the one path the server's own suite does not cover, and the defect is invisible
from inside it. This is the project's dominant failure family again: a guard green with its defect
present, because the case that would fail it was never written.

### The fix, written out but **not applied — it is unverified and must not be taken on trust**

There is no Go toolchain on this machine and no container runtime running, and `server/` has no CI
(the workflows build the app only; `server/README.md` says the suite is run by hand against a
Postgres). So this was written, found to be uncompilable here, and **reverted** rather than landed:
this repository does not accept a change nobody watched build.

Three edits:

1. `store.DeviceTokenOwner` returns both identifiers, joining `devices` on `device_tokens.device_id`
   and selecting `d.device_uuid` beside `t.device_id`.
2. `api.caller` gains `DeviceUUID *uuid.UUID` — the same installation in the client's vocabulary —
   set on the opaque-token path beside `DeviceID`. (The `tokens.SubjectDevice` JWT branch needs the
   same treatment if it is ever reached; nothing mints such a token today.)
3. `applyOne` compares against it:
   `if item.DeviceID != nil && (who.DeviceUUID == nil || *item.DeviceID != *who.DeviceUUID)`.

And a Go test that goes red on the current code: register a device, sync one item carrying **that
device's own `device_uuid`**, assert `applied`. Probe A above is that test, already written in
`curl`.

### What must not happen before it lands

**This client change must not reach TestFlight while the service is unfixed.** Before the wiring
round, an anonymous queue drained locally and settled `done`; after it, and against the service as
deployed today, every item settles `failed` with a sentence that is both wrong and non-retryable.
The client is correct in what it sends — `device_id` is exactly what `syncItem` declares and what
the server's own comment says a device credential authorizes — so the repair belongs on the server,
followed by a deploy.

### One thing the same probes prove, and it is the round's good news

With `device_id` omitted (probe C) the whole path works end to end against the deployed service:
`POST /devices/register` → `POST /sync` → `200 applied` → `GET /me/grove` returns the row with its
`record` counts and `last_visited_at`. The routes, the wire shapes, the taxonomy and the session are
all correct. One comparison stands between this round's client and a working live path.

## 6. Four more comments that stopped being true, corrected in the same branch

Swept for on the way out, because "a confident comment is where bugs have survived here" and this
round falsifies a whole family of them at once. Each said, in its own words, *there is no server*:

- `RootView.accountLink()` — "screen 18's 'saving to this phone only' stays true after it".
- `VisitSavedView` — the same claim, about the same line, in the sheet that presents screen 15.
- `AccountDeletionChoice.eraseEverything` — "there is no server and nothing has been uploaded … so
  on this app as it stands it is a complete erasure and the copy is allowed to say so plainly".
  **This one is load-bearing**: it is the justification for what the erasing door promises. The
  erasure is still complete over everything the app can reach, because `DELETE /me` erases the
  service's rows too — but "nobody has already seen them" is no longer true by construction, and
  whether the drawn copy wants a word about that belongs with the copy questions above.
- `LocalAPI.uploadPhoto` — "§3.10 says server-side, and there is no server" as the reason EXIF is
  stripped on the phone. The behavior is right and the reason has changed: stripping at the boundary
  beats stripping at the far end, and now that binaries can travel it is the only version that works.

`AppSchema` v15's `remote_sent` comment ("Never 1 on any database this migration has ever met,
because there is no server yet") was narrowed rather than corrected — the claim is about rows the
*migration* rewrites, which is still true, and the sentence now says which rows it means and why the
`done` CHECK still does not name the column.
