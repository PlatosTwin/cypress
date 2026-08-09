# Ticket #158 — the live-layer sync API and account connectivity

**2026-08-09. A specification. No production Swift, no server implementation, no migration.**

> **Revised the same day, after the owner ruled on all four open questions.** The first draft asked
> four things and recommended answers to each. Three rulings took the recommendation; the fourth —
> scope — did not, and it is the one that changes the work. What follows is the specification as
> ruled, not the argument that preceded it. Where a recommendation was overruled the original
> reasoning is kept only where it is still load-bearing, and §1 is new: "full API surface" is
> readable two ways and this document says which one it builds before it builds anything.

Every claim below was read out of the code in this repository at `0e1df35`, not out of prose.

---

## The ruling, and what it makes this document

| Question | Ruled | What it means here |
|---|---|---|
| **Auth route** | **Sign in with Apple first.** Email magic-link becomes its own ticket. `AccountLinkRequest` is not widened. | §5.2, §5.3 |
| **Cross-device link** | **Refuse it.** | §5.4, and the rendezvous alternative is recorded as not-taken in §5.5 |
| **Scope** | **The full `CypressAPI` surface**, not the write half plus auth | §1, §3, §4 — this is the change |
| **Stack** | Argue it on trade-offs | §8 |

**One thing the owner should read before anything else: §1.** The scope ruling is compatible with
RULINGS **R36** under one reading of it and revises R36 under the other. I specify the first. If the
second was meant, §1 says so and stops rather than quietly overturning a ratified ruling.

---

## 1. "Full API surface" — which reading this specifies

R36 is owner-ratified: local for the slow heavy layer, live for the fast thin layer. "Full API
surface" can mean either of two things and they are not the same instruction.

**(a) Every method becomes remote-*capable*; R36's routing still decides what actually travels.**
`RemoteAPI` grows a real implementation of all 31 protocol requirements, so `CypressAPI` is provably
free of any local assumption — which is the stub's stated job today and has never been finished. What
each call *does* at run time is then a routing question, and R36 is the routing rule: city-layer reads
are answered from the installed city file, community and account reads prefer the server, writes go
through the outbox to both.

**(b) Reads genuinely travel.** The map's pan loop, the profile, species search and the almanac are
answered by the Fly machine over the merged corpus. This is shape B in
`docs/investigations/api-hosting.md`, which R36 explicitly names "the documented fallback, not the
plan," reached "only if cross-city queries outgrow what a phone can hold."

**This document specifies (a).** Three reasons, in order of weight:

1. **(b) revises R36 and #158 is not a ruling.** R36's own sentence names the trigger for shape B and
   it has not happened: the app installs one city at a time (`Cypress/Data/Cities/CityLibrary.swift`
   attaches exactly one) and the corpus is two cities.
2. **D16 and R36 are not in tension, so a complete protocol and a local-first routing are not
   either.** D16 says one database available over an API; R36 says which parts of it travel which
   way. (a) builds the API completely and keeps the answer R36 gave about traffic.
3. **(a) delivers the thing the scope ruling is plainly reaching for**, which the write-half proposal
   did not: `grove()`, `journal`, `isFavorite` and `mapMembership` answered remotely are what make an
   account mean something on a *second* device. Screen 15's drawn body copy promises exactly that —
   "An account backs them up and lets them join each tree's public timeline" — and
   `BetaCapability.accountsAreLocalOnly` exists solely to suppress that sentence because a local
   account delivers neither. Under (a) that constant can finally be deleted rather than merely
   flipped, which its own header says is the correct way for it to end.

**If the owner meant (b), stop here.** It is a defensible instruction — it is the honest way to make
one merged national corpus queryable before any phone can hold it — but it revises a ratified ruling,
it re-costs the machine (§4.1), and it requires a failure state on every screen in the app (§4.3).
Those are three separate decisions and none of them is a spec agent's. §4 gives the owner the numbers
either way, because the case against (b) is only worth anything if it is costed.

---

## 2. What is already true, stated once

- `CypressAPI` (`Cypress/Data/API/CypressAPI.swift`) declares **31 requirements** and carries no
  `/auth/*` and no `DELETE /me`, deliberately: "there is no auth server and no local equivalent of a
  token exchange."
- `RemoteAPI` (`Cypress/Data/API/RemoteAPI.swift`) implements **17** of them. The other 14 it inherits
  from protocol extensions — see §3.3, which is the hazard the full-surface ruling creates.
- `BetaCapability.accountsAvailable` is `true` (ERRATA E124); `accountsAreLocalOnly` is `true` beside
  it (`Cypress/Core/BetaCapability.swift`) and is meant to end by **deletion**, not by a flip.
- `APIError.unauthorized.retryable` is **`false`** (`Cypress/Core/APIError.swift`). This drives §5.8.
- Sign-in completes locally through `LocalAPI.linkAccount` → `claimDevice`; there is no `users` table
  on device (ERRATA E86) and `AccountLinkRecord` (`Cypress/Core/AccountLinkRecord.swift`) stands in
  for two of its columns.
- `AccountDeletion` (`Cypress/Data/Store/AccountDeletion.swift`) implements RULINGS **R3** locally,
  including `OutboxStore.forgetAccount` over queued rows.

### 2.1 The finding that shapes the client work: `sync` is doing two jobs

`Cypress/Data/DataLayer.swift` wires the queue's transport to `LocalAPI`:

```swift
let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
```

**The drain is what commits a contribution to the local database.** A visit is on its tree because a
later drain called `LocalAPI.sync` → `apply(_:)` → `contributions.insert`. There is no other path:
the outbox writers enqueue and return, and every read is `LocalAPI` over the same tables.

Repointing that transport at `RemoteAPI` does not turn on a server. It **removes the local write**,
and the person's own grove, journal and profile timeline go blank for everything they contributed,
with no layer reporting an error because every layer behaves as written.

So the first piece of client work is not a network call — it is separating *apply* from *send*. §7 is
the migration that separation needs, and it is the only migration #158 requires.

---

## 3. The complete surface

### 3.1 The three routing classes

Under §1(a) every method is implemented on both sides and the composition root wires a router that
decides which answer is authoritative. Three classes, and the class is a property of the *data*, not
of the method's shape.

**Class L — local-authoritative, the R36 base layer.** Answered from the installed city file; the
remote implementation exists, is tested, and is not on the hot path.

`mapContent(in:)`, `treesNear`, `species`, `searchSpecies`, `speciesGuide`, `almanac(near:)`,
`city(near:)`, `exportLatest`.

R36's argument applies unchanged: these change at ingest cadence, so a live query returns a row
exactly as old as a published file. §4.2 makes that concrete per method.

**Class R — remote-preferred, local fallback.** These are the community layer and the account's own
rows, and they are where liveness buys something real.

`treeProfile(id:)` (its community half), `grove()`, `groveSpecies()`, `journal`, `isFavorite`,
`mapMembership`, `photoData` for a photograph this device did not take.

The fallback is not a nicety: it is what keeps the app working in a park. A failed remote read falls
back to the local answer **and says that it did** — see §4.3, which is the part that cannot be
skipped.

**Class D — device-only, never remote.** `deviceContributions()`. `RemoteAPI` already declines to
override it with the right reason written down: "What a device is holding unattributed is a local
fact by definition — the rows have not been sent." Full surface does not change that; the method's
honest remote implementation *is* the inherited local answer, and §3.3 is why that has to be said out
loud rather than left as an accident.

**Writes** are their own path: outbox first, both sinks (§2.1, §6).

### 3.2 What is added to the protocol, and what stays off it

- **`deleteAccount(_ choice:)` becomes a protocol requirement.** It is `LocalAPI`-only today.
  `CypressAPI`'s header is right that "`DELETE /me`'s *local* half is not a stub" — under full
  surface the remote half exists too, so the method belongs on the boundary rather than on one
  implementation of it.
- **The four `/auth/*` routes and `POST /devices/register` stay off `CypressAPI`.** The protocol is
  "every read and write the UI performs" (ARCHITECTURE §4). A token exchange is not one of those; it
  is how the transport earns the right to perform any of them. It belongs to the type that owns the
  session, injected into `RemoteAPI`, with screen 15 continuing to reach it through the
  `AccountAskLink` closure it has taken since it was built. Adding five requirements would oblige
  fifteen preview doubles and five test doubles to answer questions about tokens — the exact tax
  `CypressAPI`'s own "two methods that were requirements and are not any more" note records paying
  once already.

### 3.3 The full-surface hazard: fourteen defaults that already look like answers

This is the piece of the scope ruling most likely to ship broken, because it fails green.

`RemoteAPI` implements 17 of 31 requirements. The other 14 are satisfied by protocol-extension
defaults, and **ten of them throw `.notFound`** — `claimSpecies`, `correctSpecies`,
`flagWrongSpecies`, `dismissSpeciesReview` (`Cypress/Data/API/SpeciesClaim.swift`),
`flagNeverExisted`, `withdrawRecord`, `dismissRecordReview` (`Cypress/Data/API/RecordDefect.swift`),
`photoData`, `setPhotoVote`, `deletePhoto` (`Cypress/Data/API/PhotoAccess.swift`).

**The other four return a value.** `speciesGuide` returns the entry with no population facts attached
(`Cypress/Data/API/SpeciesGuide.swift`); `mapMembership` returns the empty set
(`Cypress/Data/API/MapMembership.swift`); `deviceContributions` returns `.none`
(`Cypress/Data/API/DeviceContributions.swift`); `isFavorite` derives from `grove()`.

Each default is correct for what it was written for — an implementation with nothing behind it
telling the truth. Under a ruling that says `RemoteAPI` is complete, three of them become **a server
that answers a question it never asked**: a species guide with no population line, a map with no
`Yours` or `Favorites` members, and a heart that reads false. Nothing throws, nothing logs, and
`RemoteAPI` compiles as a complete conformance either way.

Two requirements follow and they are not optional:

1. **Every method `RemoteAPI` is declared to implement, it must implement — including the ones a
   default would satisfy.** "It compiles" is not evidence of a conformance here.
2. **Anything added to the protocol goes in as a requirement, never as an extension member.** ERRATA
   **E125** is the day this cost the whole app: an extension member has no witness-table entry and
   dispatches statically, so `LocalAPI`'s real implementations were reached when the value was a
   `LocalAPI` and the extension's `throw .notFound` was reached the moment it was erased to
   `any CypressAPI` — which is what every screen holds. Every photograph failed to load and every
   vote failed to save, on a build whose tests all passed, because the tests held the concrete type.
   A full-surface round is thirty-one opportunities to repeat that.

A test that holds `any CypressAPI` and asserts each method reaches the remote implementation is the
cheap form of both. It is named here rather than written.

### 3.4 The nine mutations that never touch the outbox

Eleven mutating methods are called **directly** by feature models with no queue behind them; nine have
a shipping caller in `Cypress/Features`: `addTree`, `claimSpecies`, `correctSpecies`,
`flagWrongSpecies`, `flagNeverExisted`, `setPhotoVote`, `deletePhoto`, `logHazardRedirect`, and the
review-dismissal pair behind moderation.

Under the write-half scope these were out of scope. **Under full surface they are in it, and the
conclusion is unchanged: they stay Class L until they are queued.** Making them remote-routed without
a queue is what stops community add-a-tree working in a park — the primary use case
`docs/investigations/api-hosting.md` names for the entire architecture ("a volunteer standing under a
tree with one bar of signal").

Queueing them means widening `outbox.kind`, which is a `CHECK` constraint listing six values — schema
work in the same version space as §7, wanting its own ticket and its own migration author. `RemoteAPI`
implements all nine (§3.3 requires it); the router does not send them yet.

---

## 4. The read half: cost, freshness, and what happens with no signal

The scope ruling puts reads in scope, so they have to be costed rather than assumed. This section is
the case for §1(a)'s routing and the numbers the owner needs if they meant (b).

### 4.1 What a remote read costs against a local seed

**The map is the argument, because the map is the app.** `MapModel.cameraDebounce` is **200 ms**
(`Cypress/Features/Map/MapModel.swift`): a pan issues one read per 200 ms of settled camera, and
`thresholdDebounce` is 16 ms — one frame — for a pinch across the clustering boundary. That is a read
loop measured in frames.

Against that, three costs of putting a network in it:

- **Latency, per read.** The figure recorded beside `TreeCluster` in `Cypress/Data/API/CypressAPI.swift`
  for the whole-city clustered query is **104 ms** locally (and 355 ms with a representative tree id,
  which is why that field does not exist). A round trip to `sjc` from a phone on cellular is on the
  same order or worse before the query runs, so a remote read at least doubles the pan loop's
  response and does it on a variable rather than a constant.
- **Cold start.** `server/fly.toml` runs the machine `auto_stop_machines = 'stop'` with
  `min_machines_running = 0` — that is what makes it "a few cents/month" in `server/README.md`.
  `docs/investigations/api-hosting.md` §2 puts a Fly cold start at "hundreds of ms to a few seconds."
  A cold start in the pan loop is not a latency, it is a freeze. Reads-remote therefore forces
  `min_machines_running = 1`, and the README's own ceiling for an always-on `shared-cpu-1x/256MB` is
  **~$2.02/month**.
- **The tier it implies.** A machine answering viewport queries has to hold the corpus and its
  indexes. `docs/investigations/api-hosting.md` §3 costs exactly that shape: a 1 GB machine at
  **~$6/month**, growing to **$8–17/month at 1,000 users**, plus a volume at ~$0.30/month now and
  ~$1.50 at 10 GB — "and this line grows with corpus size, unlike shape A."

The local side of the comparison is not free either, and the honest version says so: the seed is
~103 MB bundled today and R36's own consequence (a) is that it becomes a download rather than the
distribution. But that cost is already paid, already built (`Cypress/Data/Cities/CityManifest.swift`,
`Cypress/Data/Cities/CityLibrary.swift`, `Tools/publish_cities.py`), and it is paid once per publish
rather than once per pan.

**And it is the read path two performance campaigns bought.** The `MapModel` header carries the
measurements from before the level-of-detail rule landed — 14.3 fps arriving at zoom 16, a 2,060.8 ms
worst frame in the window after it, 18.7 fps on one pan — taken with `MapFrameProbe` on the iPhone 16
Pro simulator. That defect was fixed by moving work *into* the local query. Moving the query off the
device spends that work again on a link that can vary by two orders of magnitude.

### 4.2 What freshness a remote read actually buys, per class

R36's claim is that the city layer gains nothing. Checked method by method, that holds — and the same
check finds the two places where it does not, which is what Class R is.

| Read | What a live query returns that the file does not |
|---|---|
| `mapContent`, `treesNear`, `species`, `searchSpecies` | **Nothing.** City-layer rows change when ingest runs. A published file is exactly as fresh. |
| `speciesGuide`, `city(near:)` | **Nothing** — both are aggregates over the installed inventory, and under D16 they are properties of *which cities are installed*, which the server does not know. |
| `exportLatest` | The server's is a different artifact (D12, the nightly open export over the merged corpus). Not a freshness gain over the local one; a different deliverable. |
| `almanac(near:)` | **Partly.** Its city aggregates gain nothing; its first-bloom sightings are community observations and go stale the moment somebody else records one. |
| `treeProfile` | **Yes.** Other people's photographs, visits and notes. This is the community-review loop D16 makes the product, and no file can carry an hour-old bloom sighting. |
| `grove`, `groveSpecies`, `journal`, `isFavorite`, `mapMembership` | **Yes, and it is the account's whole point.** These are this person's rows, and today they are this *device's* rows. A second device is where the difference shows. |

`almanac` is the one method that straddles, and it should be routed L with its community half arriving
from the same delta that feeds `treeProfile` — not routed R wholesale, which would put the city
aggregates on the network for the sake of the bloom line.

### 4.3 Offline, for a read path that currently cannot fail

This is the part of reads-remote that is not a performance question, and it is the largest piece of
work in the ruling.

**Today a read cannot meaningfully fail.** `LocalAPI` reads an attached file; the failure modes are
`notFound` and a SQLite error. Every screen in this app was written against that.

The codebase has already been bitten by the distinction this changes, and it wrote the lesson down.
`AccountModel.remindersFailed` exists because "two tab roots in this app once drew their empty state
on a failed read, and an empty state is a claim: 'you have not saved any reminders' is a sentence
about the person, and saying it when the database could not be opened is telling them their records
are gone." `RemoteAPI` overrides the `almanac` and `groveSpecies` defaults to *throw* rather than
return empty for the same reason: an empty almanac "would draw 'nothing is happening in your
neighborhood' over 'we could not ask'."

**So the rule already exists and is already argued; what the ruling changes is how many screens owe
it.** Under Class R, a read has three outcomes rather than two — answered, answered-from-the-local-
fallback, and could-not-ask — and a screen that collapses the third into an empty state is telling
somebody their work is gone. Under (b) that applies to every screen in the app, including the map,
where the empty state is a city with no trees in it.

Two things follow that #158 must carry:

- **Class R reads fall back to the local answer and mark it as such.** The local answer is complete
  for everything this device wrote, which is most of what these methods are about; what it is missing
  is other people and other devices. "Yours, as this phone knows them" is a true sentence. Whether
  the app draws one, and where, is a copy question and it is **not in the mocks** — named, not
  invented (DECISIONS constraint 21).
- **No Class L read is allowed to acquire a remote failure mode.** That is (a) restated as an
  invariant, and it is the one line that keeps the map's failure surface exactly where two
  performance campaigns left it.

---

## 5. Auth

### 5.1 What "magic-link only" constrains

DECISIONS constraint 9, verbatim: *"Never collect birthdates, passwords, or exact photo GPS. **Email
auth is magic link only.** Age gate is a single over/under-18 choice."*

It constrains the **email route**. SCREENS.md 15 draws three buttons — `Continue with Apple`,
`Continue with Google`, `Use email` — and `AccountAskProvider` carries all three with Apple as the
filled primary. RULINGS R4 and ERRATA E111 both summarize the rule as "auth is magic-link only"; the
mock and the code are the specific version, and both are compatible, since Apple and Google are OIDC
and neither collects a password.

`Cypress/Features/AccountAsk/AccountAskPresentation.swift` holds the strongest form of the password
rule in the app: `AccountLinkRequest` has two fields and `CypressTests/AccountAskTests.swift` pins its
shape **by reflection**, so adding a third fails a test rather than a code review. The ruling keeps it
that way.

### 5.2 Sign in with Apple — the route #158 builds

`ASAuthorizationAppleIDProvider` returns an identity token (a JWT) and, on first authorization only,
an email address. The app POSTs the token to `POST /api/v1/auth/oidc`; the server verifies it against
Apple's JWKS — issuer, audience, expiry, and the nonce the app generated — and mints a session.

- **No new UI, no text field, no password**, and no address typed into anything. That is the reason
  it was recommended and the reason it was ruled.
- **No third-party dependency on the client.** `AuthenticationServices` is a system framework, so the
  zero-external-dependency rule holds by construction rather than by care.
- Google, when it comes, is the same server route reached through `ASWebAuthenticationSession` —
  also a system framework, and specifically **not** a Google SDK.

### 5.3 The email magic link is deferred, and it is not an oversight

**Stated plainly because its absence is otherwise unreadable:** #158 does not build the email route,
and `Use email` continues to present the existing notice
(`AccountAskPresentation.Notice.unavailable`). This is a decision, taken by the owner, for a reason
that is a fact about the code rather than a preference:

**Screen 15 draws no text field, and a magic link needs an address.** The only ways to get one are a
field on 15 or a sheet after the tap — both screens or states not in the mocks (constraint 21) — and
the first also means widening `AccountLinkRequest`, which is the one type in this app whose narrowness
*is* the no-passwords assertion made structural. Doing that as a side effect of a sync-API ticket is
how a governance guarantee erodes.

So the email route gets its own ticket and its own design pass, in which the field, the
check-your-email state, the universal-link plumbing (§5.4) and the refusal page are designed together
rather than accreted. Until then screen 15 offers one working route and two honest "not yet" buttons,
which is the state ERRATA **E111** already designed for — one button instead of three.

### 5.4 A link opened on a different device: refuse it

**Ruled: refuse.** The argument is the one from the first draft and it survives: screen 15's headline
is `Keep your three visits`, and the visits are on that phone. A session minted on a laptop claims
nothing, carries nothing across, and leaves the person exactly where they were while telling them
they succeeded.

**This binds the deferred email ticket; nothing in #158 implements it.** It is recorded here so the
later round inherits the decision instead of rediscovering the question.

The refusal, specified:

- **What the link carries.** `POST /auth/email/start` binds the emailed token to the requesting
  installation's `device_uuid` (`app_state.deviceUUID`, minted once in
  `Cypress/Data/DataLayer.swift`). The token is single-use and short-lived (§5.8).
- **What the server returns.** The link is a universal link on the app's own domain. Opened on the
  phone that asked, iOS hands it to the app, which calls `POST /api/v1/auth/email/complete`
  presenting the same `device_uuid`; the server verifies the binding and returns a session. Presented
  with any other `device_uuid`, or opened in a browser rather than the app, the exchange returns
  **`403` with `{error: {code: "forbidden", …, retryable: false}}`** — a code `APIError` already
  carries and `APIError.Envelope` already decodes.
- **What a person sees, and it is a web page rather than an app screen.** A browser that opened the
  link is not the app, so the refusal cannot be drawn by the app. The server renders one static page:
  the link was meant for the phone that asked for it, open it there, and the link is still good until
  it expires. That page is the email ticket's one piece of non-app UI and it should be designed with
  the rest of that flow, not improvised at build time.
- **What the requesting phone does meanwhile.** Nothing changes state: it sits in the
  check-your-email notice until a link is exchanged or the person dismisses it. There is no polling
  and no timeout to design, because the refusal path never reaches the app.
- **Infrastructure this needs.** A universal link means an `apple-app-site-association` file on the
  domain and an associated-domains entitlement. The app already names `cypress.app` in its own share
  copy (ERRATA E60), so the domain exists as a product fact; the file and the entitlement do not.
  Named here so the email ticket budgets them.

### 5.5 The rendezvous code — considered, not taken

The honest cross-device flow: the link opens a page showing a short code; the phone that asked polls
and picks it up, or the person types the code into the app. It is the standard device-authorization
shape and it genuinely solves the case where somebody's email is only on a laptop.

**Its cost is two new screens** — a server-rendered page that issues and displays the code, and an
in-app waiting state with a code field and a resend affordance — plus a polling endpoint and a second
short-lived credential. SCREENS.md draws neither. Under DECISIONS constraint 21 that is a
stop-and-ask, and the owner has stopped it here.

Recorded so a future round starts from "this was priced at two screens and declined" rather than from
scratch.

### 5.6 What `AccountLinkRecord` was built to hold, and what it does next

Two things, in `app_state`, because there is no `users` table (E86): the provider raw value and the
license version consented to. Its header names its own destination — "When the magic-link service
lands, `User.licenseVersion` and `User.licenseAcceptedAt` are the columns this becomes and nothing
about the screen changes" — and `Cypress/Core/Models/User.swift` already declares both.

Under #158 it acquires a third job: **it is what the claim sends.** `POST /devices/claim` carries
`{device_uuid, license_version}` and the server writes the `users` row's consent from it. A missing
`licenseVersion` is a *declined* consent and must arrive as an explicit null rather than an omitted
field the server defaults — `acceptsLicense` is derived from nil precisely so a `Bool` and a version
string cannot disagree, and that property has to survive the wire.

The record stays on device afterwards: it is the local, network-free answer to "what did this account
agree to," and `AccountModel` reads it on every appearance of the You tab.

### 5.7 Re-consent when the license version moves — still open, still the owner's

`LicenseConsent.currentVersion` is `"odbl-1.0"`. BUILD-PLAN §4 requires a text change to force
re-consent, and `AccountLinkRecord`'s header states the mechanism: the constant moves and
`User.hasAcceptedLicense(version:)` "starts returning false for everyone who agreed to this one,
which is precisely what versioning it is for."

Today nothing acts on that false. With a server there is a real answer to compute and no surface to
put it on — re-consent is neither the account ask (D9's third-save moment, spent) nor a setting.
Carried forward unchanged: named, not invented.

### 5.8 The session, and the defect to design out

**A device credential comes first.** D9 makes the anonymous queue the normal case — "first saves are
anonymous and local-first under a device ID… the ask comes at the third save" — so a queue that
cannot drain without an account is a queue that fills up. `POST /api/v1/devices/register` exchanges
the existing `app_state.deviceUUID` for a device token authorizing `POST /sync` for items carrying a
`deviceID` and no `userID`. It is not an attestation and does not claim to be; the defense against a
flood is rate limiting, and `rate_limited` is already in the taxonomy and already retryable.

**Tokens live in the Keychain, not in `app_state`.** A credential inside the SQLite file is a
credential inside every backup of it, and `AccountDeletion` reasons about rows and files rather than
about copies elsewhere. `kSecAttrAccessibleAfterFirstUnlock`, because a background drain runs on a
locked phone. **No migration** — the Keychain is not the database.

**Lifetimes, and why magic-link-only sets them.** A magic link is a bearer credential delivered over
an unencrypted, forwardable, indefinitely retained channel. So the link token buys **one exchange,
once, within 10 minutes**, and is never the session; a link that logged you in every time it was
opened is a password living in an inbox. The session is a **15-minute access token and a 60-day
rotating refresh token**, and the refresh is long for a reason specific to this app:

**`APIError.unauthorized.retryable` is `false`, and `OutboxRetryPolicy.nextState` reads exactly
that** — a non-retryable code moves an item to `.failed` **immediately**, not after 48 h. The
sentence screen 17 then prints is already written in
`Cypress/Data/Outbox/OutboxViewState.swift`: *"Sign in to send this."*

So one expired access token does not slow a drain down. It **ends** it, marking every item in the
batch terminally failed and telling a person who is signed in to sign in.

Both files are correct alone. The fix is at the transport: a 401 is a fact about the session, not
about the item, so `RemoteAPI` refreshes once and replays the batch; a failed refresh fails the batch
as a transport failure, which `OutboxQueue.drain` already handles by keeping every item alive on the
backoff. `unauthorized` should reach an outbox item only when the item genuinely is not this
identity's to send, which is what the copy already means.

---

## 6. Offline and conflict on the write path

### 6.1 What the outbox is queuing against

Today `LocalAPI`. After #158, `LocalAPI` **and** the Fly service, in that order (§2.1). Local apply
happens first and unconditionally — a contribution is on its tree the moment the drain runs, offline
or not, which is today's behavior and losing it would be a regression dressed as a feature. Remote
send is the retryable half, and it is what `OutboxRetryPolicy` was written for and has never had a
real reason to run. `duplicate` stays a success on both sides: the server dedupes on `client_uuid`
exactly as the local unique index does, which is what makes `CypressTests/OutboxChaosTests`'s zero-
duplicates assertion hold across a flap.

### 6.2 Sign-in with items already queued

The local half is solved: `LocalAPI.adoptRowsWrittenAfterTheClaim` re-runs the device claim after
every batch that applied anything, because a mutation "lives in the outbox between being written and
being applied, and that gap can straddle a sign-in: queued in a dead zone on Tuesday, account linked
on Wednesday, drained on Thursday."

**The server needs the identical rule and it must be idempotent**, because the client re-invokes the
local one after every batch. `POST /devices/claim` is a sweep keyed on device id whose `WHERE`
clauses stop matching once they have run — the shape `ContributionStore.claimDevice` already has. An
item arriving on a device token *after* the claim is re-homed by the next claim, not refused.

Note the guard #174 put on the local version: the re-claim runs only while that account is the one
signed in, because the claim row outlives the sign-in and re-claiming against it while signed out
adopted rows it should not have. The server has the same trap and takes the same guard.

### 6.3 Sign-out and deletion with items in flight

- **Sign-out** deletes nothing: rows keep the account's id and `signedOutUserID` remembers it so the
  account resumes. But the queue still holds items naming that account, and sending one now needs a
  token the app no longer holds. **Account-owned items are simply not due while nobody is signed
  in** — a `dueItems` predicate, not a new state. They wait, which is what the queue is for; the
  alternative is attempting them and taking the terminal `unauthorized` of §5.8.
- **Deletion.** `OutboxStore.forgetAccount` already discards the two exclusively-owned kinds and
  either anonymizes or deletes the four contribution kinds per the door taken. Two new server-side
  requirements follow:
  1. `DELETE /me` applies the same `AccountDeletionChoice` to rows the server already accepted. The
     choice travels on the wire; it is not a server default.
  2. An item accepted **after** the deletion must not resurrect the account. The client already has
     the mechanism to mirror: `anonymized_contributions` (`AppSchema` v13), a tombstone keyed on
     `client_uuid` and written *before* the payload stops naming the account. A replayed item that
     hits the server's mirror comes back `duplicate` — a success that changes nothing, the same
     answer the dedupe already gives.

  R3's own acceptance criterion applies: deleting *more* than somebody expected is the failure mode
  and the copy is the whole defense. A server keeping a copy of what that copy said was gone breaks a
  promise the app already makes on screen.

### 6.4 The 48 h give-up, once there is a real server

`OutboxRetryPolicy.cap` is 48 h; `OutboxFailureReason.expired` is *"Tried for 48 hours without
getting through. Tap retry when you have a connection."*

**The state has never been reachable in the field.** Its only transport is `LocalAPI`, which either
succeeds or fails non-retryably; the expiry arm is exercised by tests and by
`OutboxPreviewFixtures.expiredMeasurement` and by nothing a person has done. #158 makes it live.

- **The number stays.** BUILD-PLAN §4 verbatim, restated by DECISIONS §2.3, and screen 17 is built
  around it. Nothing found here argues against it.
- **One sentence can outrun the facts, and this is the owner's.** The cap measures wall-clock from
  `windowStartedAt` and `drain()` checks expiry **before** attempting. An item queued Friday in a
  park, attempted once, in a phone not opened until Monday, is marked `failed` on the first Monday
  drain saying it was tried for 48 hours — having been tried once. Invisible today because the local
  transport does not fail; catchable by a person once a server exists. Options: keep it (arguably the
  sentence is about the window, not the attempts), count attempts alongside the clock, or reword. **I
  recommend rewording over re-engineering**, and the words are the owner's — I have not written a
  candidate.

### 6.5 Two taxonomy codes that become reachable

`conflict` from `POST /trees`'s 10 m proximity dedupe starts happening against *somebody else's*
tree. No change needed: `ProximityConflict` carries the candidate list and `conflict` is
non-retryable, "so the item fails immediately instead of spending 48 h on an answer only the user can
give." `moderation_rejected` has a sentence and has never been thrown; it becomes reachable when the
community layer is shared, and the client is already correct for it.

---

## 7. Schema, in both version spaces, named separately

Both numbers read out of the code, as CLAUDE.md requires.

### 7.1 `AppSchema.currentVersion` — the writable database's counter (`PRAGMA user_version`)

**It is 14**, the maximum `Migration(version:)` in `Cypress/Data/Store/AppSchema.swift` — *"a species
claim can be corrected, and the correction keeps it."*

**#158 needs exactly one migration and I have not written it.** CLAUDE.md: one migration author per
round, named explicitly; if a task needs one, stop and report. This is the report. What it must do:

- The `outbox` table carries one completion flag, `json_synced INTEGER NOT NULL DEFAULT 0`, under the
  table-level constraint
  `CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))`. Two sinks
  (§2.1, §6.1) means a second flag **and** a rewritten constraint — in SQLite the twelve-step table
  rebuild the v3/v4/v5 migrations in that file already perform several times over, not an
  `ALTER TABLE ADD COLUMN`.
- Existing rows migrate as **locally applied, not remotely sent**, which is what they truthfully are.
- If §3.4's nine mutations are brought into the queue, `outbox.kind`'s `CHECK` list grows too. Same
  version space; whether to do both in one migration is a scope decision, not mine.

**The full-surface ruling adds nothing else to this space.** Tokens are Keychain (§5.8); account id,
role, provider and license version are already `app_state` keys; there is still no `users` table and
#158 does not add one — E86's reasoning holds and the server is where that row belongs. Class R's
remote reads are reads: they cache in memory for a screen's lifetime and persist nothing.

### 7.2 `SeedDatabase.newestKnownSchemaVersion` — the published city file (R37's `s<n>`)

**It is 16**, in `Cypress/Data/Store/SeedDatabase.swift`, set by task #237 — `dim_city` joined through
`id_spaces.city_id`, and the drop of `id_spaces.short_name`.

**#158 changes it not at all**, and the full-surface ruling does not change that answer: R36 puts the
community layer on the live side precisely because it cannot wait for a publish, so nothing #158
writes ever enters a city file. The manifest contract, the install-state comparison and the publish
tooling are untouched.

The two spaces are unrelated and they no longer collide — see §9.

---

## 8. Stack

The constraints, stated first because they are what the comparison is against: **one
`shared-cpu-1x`/256 MB machine**, **Postgres**, **one maintainer**, a client held to **zero external
dependencies**, and a workload that is **mostly small writes plus an auth path** — with reads staying
local under §1(a), so nothing here is sized for a query tier.

### 8.1 The constraint on the decision, not the decision

DECISIONS constraint 20 makes BUILD-PLAN §3's stack table binding "without a written reason," and
`docs/ARCHITECTURE.md` §1 is the register of those reasons — a four-row table titled "The one
sanctioned deviation from BUILD-PLAN §3." Its backend row deviates on **not having a backend**
("Local-first, behind a protocol"), not on the stack, and §4 still reads "When the Fastify service
exists."

So: **Fastify is the incumbent, and anything else needs a fifth row with an argument in it.** That
raises the bar for the alternatives; it does not decide between them, and the rest of this section is
the actual comparison.

### 8.2 Node 22 + Fastify — recommended

**For.** The deciding factor is the auth path, not continuity. #158's hardest correctness surface is
OIDC verification: Apple's JWKS, key rotation, `iss`/`aud`/`exp` checks, nonce binding, replay. It is
security-critical, it is easy to get subtly wrong, and it is exactly the place where a widely-audited
library beats anything written for one project. Node has the most trodden path there, plus a mature
Postgres driver and the JSON-shaped ergonomics this API is entirely made of — the wire format is
`{error: {code, message, retryable}}` and per-item `{client_uuid, status, error}`, and nothing in it
wants a type system that a schema validator does not already give.

**Against, honestly.** It is the largest baseline of the three on a 256 MB machine, and the biggest
transitive dependency tree to keep patched — for a maintainer who holds the *client* to zero external
dependencies. That tension is real and it is the strongest argument the other two have.

**What would make this wrong:** if the owner's actual maintenance cost is dependency upkeep rather
than auth correctness — one person, occasional attention, a machine that must not need weekly patch
runs. That is a legitimate written reason and it points at Go.

### 8.3 Go — the placeholder's language, and the runner-up

**For.** One static binary, a small image, the lowest memory floor, no runtime to keep current, and
it is already deployed and healthy (`server/main.go`, `server/fly.toml`). On a 256 MB machine with
one maintainer that is not a small thing, and it is the closest a server gets to the client's
zero-dependency discipline: `net/http`, `database/sql` and stdlib crypto cover most of this API
without a third party.

**Against.** "Most" is not "all", and the exception is the one that matters. Verifying an Apple
identity token by hand — fetching and caching JWKS, handling rotation, checking every claim — is
where the stdlib argument stops paying and starts costing, because hand-rolled token verification is
a classic source of authentication bugs. Reach for a JWT library and the dependency-count argument
evaporates while the ecosystem is thinner. Plus the fifth deviation row.

**What would make this wrong:** if a well-regarded Go JWKS/OIDC library is judged as trustworthy as
the Node equivalents, Go's case is strictly better than Fastify's on every remaining axis and it
should win. That judgment is not mine to make on the owner's behalf; it is one afternoon of reading.

### 8.4 Swift on the server (Hummingbird or Vapor) — the third live option

**Worth stating because it has a genuine project-specific argument, not just novelty.** The wire types
already exist and are already `Codable`: `OutboxItem`, `SyncResult`, `APIError.Envelope`,
`AccountLinkRecord`. `Core` is pure Foundation by rule (ARCHITECTURE §2), so it is the half of this
app that could compile on Linux unchanged. Sharing those types would make the envelope contract
**compile-checked rather than test-checked**, on both ends, by one maintainer in one language.

**Against, and it is what sinks it for #158.** `Core` is not a package — it is files in an Xcode
synchronized root group — so "sharing" means either extracting a SwiftPM package (real work, and it
restructures the app's source tree) or copying the types, which is precisely the drift the idea was
meant to prevent. It also adds a second toolchain to CI and a Linux Foundation surface to test
against, for a service whose entire job is small JSON writes.

**What would make this wrong:** if the client and server envelope definitions ever drift in a way a
test does not catch, the compile-checked contract is worth the toolchain. Revisit then, not now.

### 8.5 What the recommendation does not decide

Whether Postgres is Fly Managed Postgres or an unmanaged single-node instance —
`docs/investigations/api-hosting.md` §7 already flags it unresolved, and nothing in this design
depends on the answer.

---

## 9. Premises checked

The first draft refuted three premises in its brief. All three were verified by the coordinator and
stand; the CLAUDE.md correction is landing separately.

- **The two schema-version spaces no longer collide at 14** — they are 14 and 16 (§7).
- **The stack decision was decided, not open** — open in `server/README.md`, binding via BUILD-PLAN §3
  and unrevoked by `docs/ARCHITECTURE.md` §1. §8.1 keeps the finding and demotes it from decision to
  constraint, which is what it is.
- **Screen 17 has no separate "give-up" design** — its drawn states are `waiting`, `retry` and
  `synced`; the give-up state is the `retry` row's copy driven by `OutboxFailureReason.expired`.

A fourth, from this round: **`RemoteAPI` implements 17 of 31 protocol requirements** and inherits the
rest as defaults, three of which return plausible-looking answers rather than errors (§3.3). Under the
previous scope that was background; under full surface it is the main hazard.

---

## 10. What #158 delivers, in order

1. **Client, with no server in it: split apply from send** (§2.1). This is where the migration lands
   and it is the only part that can be done wrong quietly.
2. **Server:** Fastify on `cypress-sync`, replacing the `501` placeholder — `POST /devices/register`,
   `POST /sync`, `POST /photos/begin`, `POST /devices/claim`, `POST /auth/oidc`,
   `POST /auth/refresh`, `DELETE /me`, and the Class R read routes. Errors as
   `{error: {code, message, retryable}}`, the shape `APIError.Envelope` already decodes.
3. **Client, the session:** Keychain storage, device registration, refresh-on-401-replay-once (§5.8).
4. **Client, the full conformance:** all 31 requirements implemented on `RemoteAPI` — including the
   fourteen a default would satisfy — plus the router of §3.1 and the `any CypressAPI` test that
   proves each method reaches the implementation rather than the extension (§3.3).
5. **Client, the account:** `RootView.accountLink()`'s body swaps for the real exchange. E124 says
   "nothing on the call path changes"; that should be verified rather than assumed.
6. **Delete `BetaCapability.accountsAreLocalOnly`.** Its header says "true by deletion," and screen
   15's drawn body sentence — *"An account backs them up and lets them join each tree's public
   timeline"* — becomes true when Class R lands. Screen 18's storage line ("saving to this phone
   only") stops being honest on the same commit and must move with it.

Step 4 is where the scope ruling's weight actually sits. Steps 5–6 depend on it, not on the email
route.

---

## Method

Every file cited was read at `0e1df35` in a worktree branched from main. Where this document states
what a constant is — the two schema versions, `APIError.unauthorized.retryable`,
`OutboxRetryPolicy.cap`, `MapModel.cameraDebounce`, `BetaCapability`'s two flags, the 17-of-31 count
— it was read from the declaration, not from a comment about it. The two performance figures in §4.1
(104 ms for the whole-city cluster query; the `MapFrameProbe` table) are quoted **as recorded** in
`Cypress/Data/API/CypressAPI.swift` and `Cypress/Features/Map/MapModel.swift` respectively and were
not re-measured for this document — they are cited as the order of magnitude the local read path
operates at, which is all the argument needs.

No test was run and no simulator was used: this change is prose. CI takes the prose path and skips
`unit` and `ui` deliberately, so **a green `gate` is evidence about the diff and not about the code.**
The guard that does apply to the content is `CypressTests/DocumentCitationGuardTests`, which requires
every backticked repo-relative path and relative link under `docs/` to resolve on disk; it was not run
here, and every citation was checked against the worktree with a reimplementation of its own
extractors, calibrated first against a known-clean document and a planted dangling one.
