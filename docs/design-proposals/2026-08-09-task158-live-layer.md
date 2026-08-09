# Ticket #158 — the live-layer sync API and account connectivity

**2026-08-09. A specification for the owner to rule on. Nothing here is built:** no production Swift,
no server implementation, no migration. Where a decision is the owner's I say so and stop rather than
picking for them.

This implements RULINGS **R36**'s split — local for the slow heavy layer, live for the fast thin
layer. It does not relitigate it. Every claim below was read out of the code in this repository at
`0e1df35`, not out of prose; where prose and code disagreed, §8 records which.

---

## The recommendation, first

| Question | Recommendation |
|---|---|
| **Stack** | **Node 22 + Fastify + Postgres**, one `shared-cpu-1x` machine on the existing `cypress-sync` Fly app. Not because Go is worse, but because BUILD-PLAN §3 already decided it, `docs/ARCHITECTURE.md` §1 is the register of sanctioned deviations from that table, and nothing this survey found is a written reason to add a fourth row. §5. |
| **Scope of #158** | **The write half and auth only.** R36's own sentence — the live layer "starts as the write-only contribution sync endpoint the outbox already expects, and grows read endpoints for the community delta when multi-user surfaces land." Every read stays local. §2, §6. |
| **Endpoint surface** | Four routes the protocol already names (`POST /sync`, `POST /photos/begin`, the photo `PUT`, `POST /devices/claim`), plus `POST /devices/register`, four `/auth/*`, and `DELETE /me`. Ten in total, none of them a query. §2. |
| **Auth** | **Device credential first, account credential second.** A device token is minted before any account exists, because D9 makes the anonymous queue the normal case. Sign in with Apple is the route that needs no new UI and should ship first; the email magic link needs a text field screen 15 does not draw. §3, §4. |
| **Writable schema** (`AppSchema.currentVersion`, **14** today) | **One migration is required and I have not written it.** The outbox row cannot distinguish "applied locally" from "accepted by the server" and today's `CHECK` forbids it from trying. Named in §7, handed back per CLAUDE.md's one-migration-author rule. |
| **Published city schema** (`SeedDatabase.newestKnownSchemaVersion`, **16** today) | **No change at all.** The community layer is live by R36; it never enters a city file. §7. |
| **The 48 h give-up** | Keep the number. What changes is that the state becomes *reachable for the first time*, and one sentence it prints can outrun the facts. §6.4. |

**Three things are stop-and-asks and the design cannot proceed past them without the owner.** They
are §4.5 (the email route has nowhere to type an email), §4.4 (a link opened on another device), and
§4.6 (re-consent when the license version moves). Each is a screen or state not in the mocks, which
DECISIONS constraint 21 makes a stop rather than an invention.

---

## 1. What is already true, stated once

Verified, not assumed. Each of these is load-bearing for something below.

- `CypressAPI` (`Cypress/Data/API/CypressAPI.swift`) carries **no `/auth/*` and no `DELETE /me`**,
  and its header says why: "there is no auth server and no local equivalent of a token exchange.
  Adding throwing stubs would suggest a sign-in flow exists."
- `BetaCapability.accountsAvailable` is **`true`** (ERRATA E124) and
  `BetaCapability.accountsAreLocalOnly` is **`true`** beside it
  (`Cypress/Core/BetaCapability.swift`). The second constant is #158's own tripwire: its header says
  the two "stop agreeing the day the magic-link service lands," and the constant is meant to be
  **deleted**, not flipped.
- Sign-in completes locally through `LocalAPI.linkAccount`, which calls the existing
  `claimDevice(deviceUUID:userID:)` seam and records the consent in `app_state`. There is no `users`
  table on device (ERRATA E86) and `AccountLinkRecord` (`Cypress/Core/AccountLinkRecord.swift`) is
  what stands in for two of its columns.
- The error taxonomy is `Cypress/Core/APIError.swift`, and **`unauthorized` is not retryable.**
  This single fact drives more of §3 and §6 than anything else in the file.
- The outbox is `Cypress/Data/Outbox/OutboxQueue.swift` over the `outbox` table in
  `Cypress/Data/Store/AppSchema.swift`. Its transport is a protocol, `OutboxTransport`, deliberately
  narrower than `CypressAPI`.
- `AccountDeletion` (`Cypress/Data/Store/AccountDeletion.swift`) implements RULINGS **R3** over the
  local tables, including `OutboxStore.forgetAccount`, which discards or anonymizes queued rows
  depending on which of `AccountDeletionChoice`'s two doors was taken.

### 1.1 The finding that shapes everything else: `sync` is doing two jobs

`Cypress/Data/DataLayer.swift` wires the queue like this:

```swift
let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
```

where `api` is `LocalAPI`. So **the drain is what commits a contribution to the local database.** A
visit is not on its tree because it was saved; it is on its tree because a later drain called
`LocalAPI.sync`, which called `apply(_:)`, which called `contributions.insert`.

Repointing that transport at `RemoteAPI` therefore does not "turn on the server." It removes the
local write. Every read in the app — grove, journal, the profile's own timeline — is `LocalAPI` over
local tables, and they would go blank for the person's own contributions.

**So the first piece of #158's client work is not a network call. It is separating "apply locally"
from "send."** Everything in §2 and §6 assumes that separation; §7 is the migration it needs.

---

## 2. The endpoint surface, and how it maps onto `CypressAPI`

`RemoteAPI` (`Cypress/Data/API/RemoteAPI.swift`) already stubs one method per anticipated endpoint,
and its header states the invariant this section must not break: it "imports nothing from `Store` or
`Outbox`, and holds no database handle."

### 2.1 What becomes remote

Four of these are already methods on the protocol. Six are new and only four of the six belong on
`CypressAPI` at all.

| Route | Protocol method | Status |
|---|---|---|
| `POST /api/v1/sync` | `sync(_:)` | exists; **splits**, see §2.3 |
| `POST /api/v1/photos/begin` | `beginPhotoUpload(_:)` | exists; becomes a presigned Tigris `PUT` destination |
| `PUT <presigned>` | `uploadPhoto(at:ticket:)` | exists; goes straight to storage, not through Fastify |
| `POST /api/v1/devices/claim` | `claimDevice(deviceUUID:userID:)` | exists |
| `POST /api/v1/devices/register` | **new**, and **not** on `CypressAPI` | §3.1 |
| `POST /api/v1/auth/email/start` | **new**, not on `CypressAPI` | §4.1 |
| `POST /api/v1/auth/email/complete` | **new**, not on `CypressAPI` | §4.1 |
| `POST /api/v1/auth/oidc` | **new**, not on `CypressAPI` | §4.2 |
| `POST /api/v1/auth/refresh` | **new**, not on `CypressAPI` | §3.3 |
| `DELETE /api/v1/me` | **new**, and it **splits**, see §2.4 | §6.3 |

**The four `/auth/*` routes and `/devices/register` stay off `CypressAPI`, and that is deliberate.**
The protocol's own header gives the reason in the negative — it omits `/auth/*` because a stub would
"suggest a sign-in flow exists" — and the positive form is the same argument: a token exchange is not
a read or a write the UI performs, it is how the transport is authorized to perform any of them. It
belongs to whatever type owns the session, injected into `RemoteAPI`, and screen 15 keeps reaching it
through the `AccountAskLink` closure it has taken since it was built
(`Cypress/Features/AccountAsk/AccountAskModel.swift`). Adding five requirements to `CypressAPI` would
oblige fifteen preview doubles and five test doubles to answer questions about tokens, which is
exactly the tax the file's own "two methods that were requirements and are not any more" note
records paying once already.

### 2.2 What stays local, and why (R36's freshness split, applied method by method)

Every read below stays on `LocalAPI` against the attached city file. R36's argument is that the city
layer "changes at ingest cadence so a published file is as fresh as a live query," and the machinery
that keeps it fresh already exists: `Cypress/Data/Cities/CityManifest.swift` and
`Cypress/Data/Cities/CityLibrary.swift`, published by `Tools/publish_cities.py`.

| Stays local | Why, beyond "it is a read" |
|---|---|
| `mapContent(in:)` | The hot path. Two performance campaigns (E130, E139) bought it; a server cannot match it and R36 says so outright. |
| `treesNear`, `treeProfile`, `species`, `searchSpecies`, `speciesGuide` | City-layer facts. Ingest cadence. |
| `almanac(near:)`, `city(near:)` | Aggregates over the installed inventory. Under D16 they are a property of *which cities are installed*, which the server does not know. |
| `grove()`, `isFavorite`, `groveSpecies()`, `journal`, `mapMembership` | Facts about `main`, not about the inventory. `CypressAPI` already argues each: the seed "cannot answer it — what this device has visited, measured or hearted is in `main`." |
| `deviceContributions()` | `RemoteAPI` already declines to override this, with the right reason written down: "What a device is holding unattributed is a local fact by definition — the rows have not been sent." |
| `photoData(id:)` | Own photographs are bytes in the container. Other people's arrive with the community delta, which is not #158. |
| `exportLatest(_:)` | D12's export is a server deliverable over the merged corpus; the local implementation is over this device's rows and is not the same artifact. Out of scope, unchanged. |
| `savePrivateReminder`, `privateReminders`, `accountLink`, `resumableUserID`, `signOut`, `setRole`, `openReviews` | `LocalAPI`-only methods today. D4 makes a private reminder never leave the device by design; the rest are `app_state`. Only `setRole` eventually moves (PRODUCT §2 grants a role server-side), and it is not #158's. |

`treeProfile(id:)` is the one read that will eventually split, and **not in #158**: its
`ownPhotoIDs` / `deletablePhotoIDs` / `anonymizedPhotoIDs` sets and its `visits`/`photos` series are
where somebody else's contributions arrive. That is the community delta R36 defers, and the payload
was built to receive it — `TreeProfile.isPhotoVisible(_:own:)` exists precisely so a stranger's
unmoderated photograph cannot be shown when that day comes (ERRATA E215).

### 2.3 `sync(_:)` — the split, in detail

Today `LocalAPI.sync` is documented as "`POST /sync`, locally" and does three things: decode each
payload, apply it to the local store, and re-run the device claim. Under a server, only the first and
third are still the client's, and the second must happen **whether or not the network exists.**

Recommended shape, and it is the smallest one that preserves the outbox's two acceptance criteria
(zero loss, zero duplicates, `CypressTests/OutboxChaosTests`):

- The queue gains a second sink rather than a second transport. `OutboxTransport` stays the narrow
  protocol it is; a new conformance wraps both — apply through `LocalAPI`, then send through
  `RemoteAPI` — and reports per-item results that distinguish the two.
- **Local apply happens first and unconditionally.** A contribution is on its tree the moment the
  drain runs, offline or not. This is what today's behavior already is, and losing it would be a
  regression dressed as a feature.
- **Remote send is the retryable half.** Its failures drive the backoff schedule, which is what
  `OutboxRetryPolicy` was written for and has never had a real reason to run.
- `duplicate` stays a success on both sides. The server dedupes on `client_uuid`, exactly as the
  local unique index does — `Cypress/Core/Models/OutboxItem.swift` already states this is the
  contract, and it is why a replayed batch after a flap is not a defect.

**Consequence the owner should see:** an item is then `done` only when both sinks have taken it, and
today the `outbox` table has one flag (`json_synced`) and a `CHECK` that ties `done` to it. That is
the migration in §7.

### 2.4 `DELETE /me` — the half that is not a stub

`CypressAPI`'s header is careful about this one and it stays correct: "`DELETE /me`'s *local* half is
not a stub and is not omitted." `LocalAPI.deleteAccount(_:)` implements R3 over the device's rows and
files. What #158 adds is the *other* half — a server call that carries `AccountDeletionChoice` and
does the same thing to the server's rows — and the ordering between them, which is §6.3.

### 2.5 The nine mutations that never touch the outbox

This is the piece of #158 most likely to be underestimated, so it is stated separately. Nine mutating
methods on `CypressAPI` are called **directly** by feature models, with no queue behind them:

`addTree`, `claimSpecies`, `correctSpecies`, `flagWrongSpecies`, `flagNeverExisted`,
`dismissSpeciesReview`, `withdrawRecord`, `dismissRecordReview`, `setPhotoVote`, `deletePhoto`,
`logHazardRedirect`. (Eleven methods; nine have a shipping caller in `Cypress/Features`.)

Today that is harmless — the callee is `LocalAPI` and cannot be offline. The day the callee is a
network, **community add-a-tree stops working in a park**, which is the primary use case
`docs/investigations/api-hosting.md` names for the whole architecture ("a volunteer standing under a
tree with one bar of signal").

**Recommendation: they are out of #158's scope, and #158 must say so rather than leave it implied.**
Each needs an outbox kind, and `outbox.kind` is a `CHECK` constraint listing six values — so this is
schema work in the same version space as §7 and it wants its own ticket and its own migration author.
Until then `RemoteAPI` throws for them, which is the shipped stub's behavior, and the composition
root keeps answering them from `LocalAPI`. That is a correct interim answer for a device whose
community layer is not yet shared.

---

## 3. The session, before any account exists

D9 is the constraint that makes this section necessary: "First saves are anonymous and local-first
under a device ID, synced after account creation; the ask comes at the third save." So the normal
state of a Cypress installation is **a full outbox and no account.** If the queue cannot drain
without one, D9's whole funnel is a queue that fills up and expires.

### 3.1 `POST /devices/register`

The device already has a stable identity: `app_state.deviceUUID`, minted once in
`Cypress/Data/DataLayer.swift` and never regenerated ("regenerating it would orphan them (D9)").
Registration exchanges it for a long-lived device token which authorizes exactly one thing: `POST
/sync` for items whose payload carries `deviceID` and no `userID`.

- The token goes in the **Keychain**, never in `app_state`. A credential inside the SQLite file is a
  credential inside every backup of it, and `AccountDeletion`'s erasing door reasons about rows and
  files, not about a copy in iCloud. `kSecAttrAccessibleAfterFirstUnlock`, because a background drain
  runs on a locked phone.
- It is not an attestation and does not claim to be. Anyone can mint a device id; the server's
  defense against a flood is rate limiting (`rate_limited` is already in the taxonomy and is already
  retryable), not a proof of hardware.
- **No migration:** the Keychain is not the database.

### 3.2 What an account adds

A session token, obtained by §4, which authorizes items carrying a `userID` and authorizes
`POST /devices/claim` and `DELETE /me`. The device token does not go away when somebody signs in —
`signOut()` exists, `resumableUserID()` exists, and the device keeps writing device-owned rows
between accounts.

### 3.3 Token lifetimes, and why the magic-link constraint sets them

A magic link is a bearer credential delivered over email: an unencrypted, forwardable, indefinitely
retained channel. Two consequences that are not negotiable:

- **The link token is single-use, 10 minutes, and is never the session.** It buys one exchange and
  nothing else. A link that logged you in every time it was opened is a password that lives in an
  inbox — which is the thing DECISIONS constraint 9 refuses under a different name.
- **The refresh token must outlive any plausible offline stretch.** 60 days, rotating on use, is the
  recommendation. The reason is specific to this app rather than generic hygiene, and it is in the
  next paragraph.

### 3.4 The defect to design out, stated as a number

`APIError.unauthorized.retryable` is **`false`** (`Cypress/Core/APIError.swift`), and
`OutboxRetryPolicy.nextState` reads exactly that: a non-retryable error moves an item to `.failed`
**immediately**, not after 48 h. Screen 17 then prints `OutboxFailureReason`'s sentence for
`unauthorized`, which is already written: *"Sign in to send this."*

So an expired session does not degrade a drain. It converts the entire queue to terminal failures in
one pass, each of them telling a person who is signed in to sign in.

**The design answer, and it is a client answer rather than a server one:** a 401 is a fact about the
*transport*, not about the item. `RemoteAPI` refreshes once and replays the batch; if the refresh
fails, the drain fails as a transport failure — which `OutboxQueue.drain` already handles, keeping
every item alive on the backoff — and the app presents the sign-in state on the screen that owns it,
not one line per queued row. `unauthorized` should reach an outbox item only when the item is
genuinely not this identity's to send, which is what the copy actually means.

Recommended: **access token 15 minutes, refresh 60 days rotating, refresh-on-401-then-replay-once.**

---

## 4. Auth under magic-link-only

### 4.1 What "magic-link only" actually constrains

DECISIONS constraint 9, verbatim: *"Never collect birthdates, passwords, or exact photo GPS. **Email
auth is magic link only.** Age gate is a single over/under-18 choice."*

It constrains the **email route**. It is not a statement that email is the only route: SCREENS.md 15
draws three buttons — `Continue with Apple`, `Continue with Google`, `Use email` — and
`AccountAskProvider` carries all three, with Apple as the filled primary. RULINGS **R4** and ERRATA
**E111** both summarize the rule as "auth is magic-link only," and that summary is what a reader
carries away; the mock and the code are the specific version. Both are compatible — Apple and Google
are OIDC, and neither collects a password — but the difference decides what #158 builds first, so it
is worth saying out loud.

`Cypress/Features/AccountAsk/AccountAskPresentation.swift` already holds the strongest form of the
password rule anywhere in the app: `AccountLinkRequest` has two fields, and `AccountAskTests` pins
its shape **by reflection**, so adding a third fails a test rather than a code review. Nothing in
#158 may relax that. §4.5 is where it bites.

### 4.2 The three routes, concretely

- **Apple** — `ASAuthorizationAppleIDProvider` yields an identity token (a JWT) and, on first
  authorization only, an email. The app POSTs the token to `POST /auth/oidc`; the server verifies it
  against Apple's JWKS and mints a session. **No new UI, no text field, no password, and the address
  never passes through a field somebody types into.** This is why it should ship first.
- **Google** — the same route, reached through `ASWebAuthenticationSession`. Both are system
  frameworks, so the zero-external-dependency rule (`docs/ARCHITECTURE.md`, CLAUDE.md) is kept; there
  is no Google SDK in this app and #158 must not add one.
- **Email** — `POST /auth/email/start` takes an address, the server mails a link,
  `POST /auth/email/complete` takes the link's token. Blocked on §4.5.

### 4.3 What `AccountLinkRecord` was built to hold, and what it does next

It holds two things, in `app_state`, because there is no `users` table (E86): the provider raw value
and the license version consented to. Its header names its own destination: *"When the magic-link
service lands, `User.licenseVersion` and `User.licenseAcceptedAt` are the columns this becomes and
nothing about the screen changes."* `Cypress/Core/Models/User.swift` already declares both.

Under #158 the record acquires a third job it does not have today: **it is what the claim sends.**
`POST /devices/claim` carries `{device_uuid, license_version}`; the server writes the `users` row's
consent from it. A missing `licenseVersion` is a declined consent and must arrive as a null, not as
an omitted field the server defaults — `AccountLinkRecord.acceptsLicense` is derived from nil
precisely so a `Bool` and a version string cannot disagree, and that property has to survive the
wire.

The record stays on device afterwards. It is the local answer to "what did this account agree to,"
readable with no network, and `AccountModel` reads it on every appearance of the You tab.

### 4.4 A link opened on a different device from the one that asked — **stop-and-ask**

Three answers exist and only two are buildable inside the mocks.

- **(a) Refuse, and say so.** The link carries the requesting installation's device id; opening it
  elsewhere returns a page saying to open it on the phone that asked. **This is the recommendation.**
  It is not merely the safe answer — it is the *correct* one for what sign-in means here. Screen 15's
  headline is `Keep your three visits`, and the visits are on that phone. A session minted on a
  laptop claims nothing, carries nothing across, and leaves the person exactly where they were while
  telling them they succeeded.
- **(b) Accept anywhere.** Cheapest, and it produces the outcome above: signed in somewhere useless,
  three visits still unclaimed on the phone.
- **(c) A rendezvous — the link shows a short code, the phone picks it up.** This is the honest
  cross-device flow and it is **a new screen twice over**: a web page, and an in-app waiting state
  with a code field. DECISIONS constraint 21 makes that a stop-and-ask, and I am not proposing a form
  for it.

Even (a) needs one thing the mocks do not draw: after tapping `Use email`, screen 15 must say a link
was sent. SCREENS.md 15 draws three buttons and nothing after them.
`AccountAskPresentation.Notice` already exists for exactly this problem, with the argument written
into it — "a control that acts and says nothing is the same dishonesty as one that claims something
it did not do" — and carries two NOT SPECIFIED sentences under that authority. **A third `Notice`
case is the smallest honest answer and is within the precedent.** A full check-your-email screen with
a resend timer is not, and is the owner's.

### 4.5 The email route has nowhere to type an email — **stop-and-ask, and it is the blocking one**

Screen 15 draws no text field. `AccountLinkRequest` has two fields and a reflection test pinning
that. `AccountAskProvider.email`'s title is `Use email` and its own comment says the case "is named
for the button, and the mechanism behind it is a decision the constraint has already taken" — the
mechanism, yes; the input, no.

So the email magic link cannot be built without one of:

1. **A field on screen 15.** A screen state not in the mocks (constraint 21), and it means widening
   `AccountLinkRequest`, which means changing the one type in this app whose narrowness is the
   §3.9 assertion made structural. Doable, and it should be a deliberate act with the reflection test
   updated in the same commit, not a side effect.
2. **A sheet after the tap.** A new screen. Same constraint.
3. **Ship Apple (and Google) first and leave `Use email` presenting the existing "not yet" notice.**
   No new UI at all, and the button is honest — it is the state E111 already designed for, one
   button instead of three.

**Recommendation: 3 now, 1 when the owner rules.** It is the only option that gets a real server, a
real claim and a real drain in front of a person this round.

### 4.6 Re-consent when the license version moves — **stop-and-ask**

`LicenseConsent.currentVersion` is `"odbl-1.0"`, and `AccountLinkRecord`'s header states the point of
versioning it: when legal review lands, "the constant moves and `User.hasAcceptedLicense(version:)`
starts returning false for everyone who agreed to this one, which is precisely what versioning it is
for." BUILD-PLAN §4 requires a text change to force re-consent.

Today nothing acts on that false. With a server there is a real answer to compute and no screen to
put it on: re-consent is neither the account ask (that is D9's third-save moment, spent) nor a
setting. Named here, not invented.

---

## 5. Stack: the argument

### 5.1 The premise in the brief needs correcting first

`server/README.md` says the stack decision "is still open — this Go file was chosen because it is
boring and disposable, not because it is the answer." That is true of the *placeholder's* Go, and it
is not the whole record.

DECISIONS constraint 20: *"Stack decisions in BUILD-PLAN §3 are decided, not suggestions; do not
substitute without a written reason."* `docs/ARCHITECTURE.md` §1 is that written reason, and it is a
four-row table titled **"The one sanctioned deviation from BUILD-PLAN §3."** Its backend row reads:

| BUILD-PLAN §3 | What we build | Why |
|---|---|---|
| Fastify + Postgres/PostGIS backend | **Local-first, behind a protocol** (§4) | No backend exists yet. |

The deviation taken was *not having a backend*. The stack for the backend, when one exists, was never
substituted — `docs/ARCHITECTURE.md` §4 still says "When the **Fastify** service exists," `RemoteAPI`
is documented as "The Fastify service, when it exists," and `docs/investigations/api-hosting.md` §4
reasons the same way: a Node/Fastify service "continues rather than invents a direction."

**So the question is not "which stack" on a blank sheet. It is "is there a written reason to add a
fifth row to that table."** I did not find one.

### 5.2 The alternatives, and their costs

- **Node 22 + Fastify + Postgres (recommended).** Zero deviation, so no ARCHITECTURE §1 row and no
  owner ruling required beyond this document. Postgres is what `docs/investigations/api-hosting.md`
  §7 leaves open against SQLite-on-a-volume, and it is the right side of that open question for
  #158 specifically: `POST /devices/claim` is a multi-statement re-attribution under concurrency, and
  D14's coordinator dashboard is the next thing that lands on this store. Cost: a Node runtime is a
  larger image and a busier dependency surface than Go's, on a 256 MB machine.
- **Go (what the placeholder is).** One static binary, trivial image, no dependency churn, and it is
  already deployed and healthy — `server/main.go`, `server/fly.toml`. It would be a fourth deviation
  row and it needs a written reason. "The placeholder was written in it" is not one.
  **What would make me wrong:** if the owner's own maintenance preference is a single static binary,
  that is a legitimate written reason and it outranks continuity with a document about a React Native
  codebase we are not building. This is the owner's to say; I do not have their preference.
- **Cloudflare Workers + D1** — R36 names it the fallback, not the plan. It is a second platform to
  learn and it moves the write store off the machine that already holds the bucket credentials.
  **What would make me wrong:** if the Fly machine's cold start under `auto_stop_machines = 'stop'`
  turns out to hurt a field drain badly enough to matter.
- **Anything with a query surface (shape B).** Ruled out by R36 and by the survey it ratified. Not
  reopened here.

### 5.3 What the recommendation does not decide

The service is stateless and small. Whether Postgres is Fly Managed Postgres or an unmanaged
single-node instance is a cost and operations question `docs/investigations/api-hosting.md` §7
already flagged as unresolved, and #158's design does not depend on the answer.

---

## 6. Offline, conflict, and the account changing under a full queue

### 6.1 What the Outbox is queuing against

Today: `LocalAPI`. After #158: `LocalAPI` **and** the Fly service, in that order, per §2.3. Screen 17
is the visible half of that and its footnote is the promise being kept — *"Nothing here disappears
silently. An item that cannot sync says so, says why, and waits for you."*

### 6.2 Sign-in with items already queued

The local half is solved and its reasoning is worth reading before extending it:
`LocalAPI.adoptRowsWrittenAfterTheClaim` re-runs the device claim after every batch that applied
anything, because "a mutation lives in the outbox between being written and being applied, and that
gap can straddle a sign-in: queued in a dead zone on Tuesday, account linked on Wednesday, drained on
Thursday." Payloads are immutable and carry the anonymous `Attribution` they were built with, so the
row lands device-owned and a sweep re-homes it.

**The server needs the identical rule, and it needs it to be idempotent**, because the client
re-invokes the local one after every batch. `POST /devices/claim` is a sweep keyed on device id whose
`WHERE` clauses stop matching once they have run — the same shape `ContributionStore.claimDevice`
already has. An item that arrives on a device token *after* the claim must be re-homed by the next
claim, not refused.

Note the guard #174 put on the local version: the re-claim only runs "while that account is the one
signed in," because the claim row outlives the sign-in and re-claiming against it while signed out
adopted rows it should not have. The server has the same trap and should take the same guard.

### 6.3 Sign-out, and deletion, with items in flight

- **Sign-out.** `LocalAPI.signOut()` deletes nothing: rows keep the account's id, and the id is
  remembered under `signedOutUserID` so the account can be resumed. The queue still holds items whose
  payload names that account, and after #158 sending one needs a token the app no longer holds.
  **Recommendation: account-owned items are simply not due while nobody is signed in** — they wait,
  which is what the queue is for and what its footnote promises — rather than being attempted and
  failing `unauthorized`, which is terminal (§3.4). This is a `dueItems` predicate, not a new state.
- **Deletion.** `OutboxStore.forgetAccount` already discards the two exclusively-owned kinds and
  either anonymizes or deletes the four contribution kinds, per the door taken. Two server-side
  requirements follow, and both are new:
  1. `DELETE /me` must apply the same `AccountDeletionChoice` to rows the server already accepted.
     The choice travels on the wire; it is not a server default.
  2. An item accepted **after** the deletion must not resurrect the account. The client already has
     the mechanism to copy: `anonymized_contributions` (`AppSchema` v13) is a tombstone table keyed
     on `client_uuid`, written *before* the payload stops naming the account. The server needs the
     mirror, and a replayed item that hits it comes back `duplicate`, which is a success and changes
     nothing — the same answer the dedupe already gives.

  R3's own words are the acceptance criterion here: deleting *more* than somebody expected is the
  failure mode, and `AccountDeletionCopy` is the whole defense. A server that keeps a copy of what
  the copy said was gone breaks the promise the app already makes on screen.

### 6.4 The 48 h give-up, once there is a real server

`OutboxRetryPolicy.cap` is 48 h and `OutboxFailureReason.expired` is the sentence: *"Tried for 48
hours without getting through. Tap retry when you have a connection."*

**The state has never been reachable in the field.** Its only transport is `LocalAPI`, which either
succeeds or fails non-retryably; the expiry arm is exercised by tests and previews
(`OutboxPreviewFixtures.expiredMeasurement`) and by nothing a person has done. #158 makes it live.
Two things follow.

- **The number should stay.** It is BUILD-PLAN §4 verbatim, DECISIONS §2.3 restates it, and screen 17
  is built around it. Nothing found here argues against it.
- **One sentence can outrun the facts, and this is an owner question.** The cap measures wall-clock
  from `windowStartedAt`, and `drain()` checks expiry **before** attempting: an item queued Friday in
  a park, attempted once, then sitting in a phone that is not opened until Monday, is marked `failed`
  on the first Monday drain with "Tried for 48 hours without getting through" — having been tried
  once. Today that is invisible because the local transport does not fail. With a server it is a
  sentence a person can catch being wrong, and this project's rule is that a confident sentence
  nobody verified is where the bugs are. The alternatives are: keep it (simplest, and "48 hours"
  is arguably about the window rather than the attempts); count attempts alongside the clock; or
  reword. **I recommend rewording over re-engineering** — but the words are the owner's, and I have
  not written a candidate.

### 6.5 Conflict, and what is genuinely new

Most of the taxonomy is unchanged, because `client_uuid` idempotency was designed for exactly this.
Two cases are new with a shared corpus:

- **`conflict` from `POST /trees`'s 10 m proximity dedupe** becomes reachable against *somebody
  else's* tree rather than only this device's. `ProximityConflict` already carries the candidate
  list and `conflict` is already non-retryable, "so the item fails immediately instead of spending
  48 h on an answer only the user can give." No change; it starts happening.
- **`moderation_rejected`** is in the taxonomy, has a sentence in `OutboxFailureReason`, and has
  never been thrown. It becomes reachable when the community layer is shared. Also not #158 —
  moderation surfaces are a web deliverable (ARCHITECTURE §8) — but the client is already correct
  for it.

---

## 7. Schema, in both version spaces, named separately

Both numbers were read out of the code, not out of prose, as CLAUDE.md requires.

### 7.1 `AppSchema.currentVersion` — the writable database's migration counter (`PRAGMA user_version`)

**It is 14**, the maximum `Migration(version:)` in `Cypress/Data/Store/AppSchema.swift`, whose newest
entry is *"a species claim can be corrected, and the correction keeps it."*

**#158 needs exactly one migration, and I have not written it.** CLAUDE.md: one migration author per
round, named explicitly; if a task turns out to need one, stop and report. This is the report.

What it must do, so whoever writes it is not guessing:

- The `outbox` table carries one completion flag, `json_synced INTEGER NOT NULL DEFAULT 0`, and the
  table-level constraint `CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))`.
  Two sinks (§2.3) means two flags, and the `CHECK` has to name both — so this is an added column
  **and** a rewritten constraint, which in SQLite is the twelve-step table rebuild the v3/v4/v5
  migrations in this file already do several times over. It is not an `ALTER TABLE ADD COLUMN`.
- Existing rows migrate as **locally applied, not remotely sent**, which is what they truthfully are.
- If §2.5's nine direct mutations are ever brought into the queue, `outbox.kind`'s `CHECK` list grows
  too. Same version space, and an argument for doing both in one migration if the owner wants them
  in one round — but that is a scope decision, not mine.

**Nothing else in #158 touches this space.** Tokens are Keychain (§3.1). The account id, role,
provider and license version are already `app_state` keys. There is still no `users` table and #158
does not add one — E86's reasoning holds, and the server is where that row belongs.

### 7.2 `SeedDatabase.newestKnownSchemaVersion` — the published seed/city file version (R37's `s<n>`)

**It is 16**, in `Cypress/Data/Store/SeedDatabase.swift`, added by task #237 (`dim_city`, and the drop
of `id_spaces.short_name`).

**#158 changes it not at all.** R36 puts the community layer on the live side precisely because it
cannot wait for a publish, so nothing #158 writes ever enters a city file. The manifest contract
(`Cypress/Data/Cities/CityManifest.swift`), the install-state comparison and the publish tooling are
untouched.

The two spaces are unrelated, and **they no longer collide** — see §8.

---

## 8. Two premises I was given that the code refutes

**1 · "The two schema-version spaces genuinely collide at 14."** They did. They do not now: the
writable counter is 14 and the published-file version is **16**. CLAUDE.md's own bullet carries the
stale claim, and it is the bullet that exists to prevent exactly this ("this bullet claimed the
writable one was 13 for a round after v14 landed, which is the confusion it exists to prevent"). The
rule it states — read both from the code, never from that file — is what caught it. Worth an errata
entry and a one-line correction to CLAUDE.md by whoever owns that file; I have not edited it.

**2 · "The stack decision is explicitly open."** Open in `server/README.md`, decided in BUILD-PLAN §3
and unrevoked by `docs/ARCHITECTURE.md` §1. §5 is the whole argument. This does not make the owner's
ruling unnecessary — it changes what they are ruling on, from "pick a stack" to "is there a written
reason to deviate again."

A third, smaller: the brief describes screen 17 as showing "the 48 h give-up state." SCREENS.md 17's
drawn states are `waiting`, `retry` and `synced`; the give-up state is the `retry` row's copy, driven
by `OutboxFailureReason.expired`, and the in-progress state is explicitly NOT SPECIFIED. The
distinction matters only in that there is no separate expired *design* to build against.

---

## 9. What #158 delivers, in order

1. **Server:** Fastify on `cypress-sync`, replacing the `501` placeholder. `POST /devices/register`,
   `POST /sync`, `POST /photos/begin`, `POST /devices/claim`, `POST /auth/oidc`,
   `POST /auth/refresh`, `DELETE /me`. Errors as `{error: {code, message, retryable}}` — the shape
   `APIError.Envelope` already decodes.
2. **Client, the part with no server in it:** split apply from send (§1.1, §2.3). This is where the
   migration lands and it is the only part that can be done wrong quietly.
3. **Client, the session:** Keychain storage, device registration, refresh-on-401-replay-once.
4. **Client, the account:** `RootView.accountLink()`'s body swaps for the real exchange — E124 says
   "nothing on the call path changes," and that should be verified rather than assumed. Sign in with
   Apple only, until §4.5 is answered.
5. **Delete `BetaCapability.accountsAreLocalOnly`.** Its header says "true by deletion," and screen
   15's drawn body sentence — *"An account backs them up and lets them join each tree's public
   timeline"* — returns when the deletion makes it true. Screen 18's storage line ("saving to this
   phone only") stops being honest on the same commit and must move with it.

Steps 1–3 are the ticket. Steps 4–5 are gated on §4.5, which is the owner's.

---

## Method

Every file cited above was read at `0e1df35` on a worktree branched from main. Where this document
states what a constant is — `AppSchema.currentVersion`, `SeedDatabase.newestKnownSchemaVersion`,
`APIError.unauthorized.retryable`, `OutboxRetryPolicy.cap`, `BetaCapability`'s two flags — it was
read from the declaration and not from a comment about it, which is this project's standing rule and
the reason §8 has two entries in it.

No test was run and no simulator was used: this change is prose. CI will take the prose path and skip
`unit` and `ui` deliberately, so **a green `gate` on this PR is evidence about the diff and not about
the code.** The one guard that does apply is `CypressTests/DocumentCitationGuardTests`, which
requires every backticked repo-relative path and relative link above to resolve on disk — it is not
run here, and every path was checked by hand against the worktree instead.
