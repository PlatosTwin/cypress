### The live-layer sync API and account connectivity: scope, auth, stack, and how a photograph publishes

*Project owner, 2026-08-09, on ticket #158, ruling on the four questions
`docs/design-proposals/2026-08-09-task158-live-layer.md` put and on a fifth the spec surfaced while
answering them. The spec is the argument; this is what was decided.*

RULINGS **R36** settled which layer travels which way. This settles what gets built on top of it,
and it does not reopen R36.

---

#### 1 — The full `CypressAPI` surface becomes remote-capable; R36 still decides what travels

**Ruled: the whole protocol, not the write half.** "Full API surface" is readable two ways and the
spec refused to choose silently: **(a)** every method gains a real `RemoteAPI` implementation while
R36's routing decides what actually goes over the network, or **(b)** reads genuinely travel, which
would revise R36 and adopt shape B from `docs/investigations/api-hosting.md`.

**Reading (a) is what is built.** D16 says one database available over an API; R36 says which parts
of it travel which way; a complete protocol and a local-first routing are therefore not in tension.
(b) is not reached: R36 names its own trigger — cross-city queries outgrowing what a phone can hold —
and the app installs one city at a time.

**The acceptance criterion, in the owner's words:** *"we need to be in a spot where when I add a
photo on my device, the photo propagates to all other users."* It is a community-layer requirement
throughout, and R36 already rules the community layer live, so it is satisfied inside (a).

**What (a) costs and buys, decided with it:**

- Reads split three ways. City-layer reads stay local — the map's pan loop is a read every 200 ms and
  two performance campaigns bought it. Community and account reads go to the server. A read that
  falls back to the local answer must say that it did; an empty state is a claim, and this project
  has already drawn one over a failed read.
- `treeProfile`'s community half is **required**, not preferred: the criterion *is* somebody else's
  profile returning a photograph their device never wrote. The community delta therefore ships in
  #158 rather than in R36's later round.
- Writes keep the outbox and gain a second sink. The drain currently *is* the local commit, so
  "apply" and "send" must separate before anything is repointed at a server.

#### 2 — Sign in with Apple ships first; the email magic link is deferred to its own ticket

**Ruled: Apple first.** It is the only one of screen 15's three routes that needs no new UI — the
identity token arrives from a system framework, no field, no password, no address typed into
anything, and no third-party dependency on the client.

**The email magic link is deferred, and the reason is a fact rather than a preference:** screen 15
draws no text field, and a magic link needs an address. Supplying one means either a field on 15 —
which widens `AccountLinkRequest`, the one type in this app whose narrowness *is* the no-passwords
assertion, pinned by reflection — or a new sheet. Both are screens or states not in the mocks
(DECISIONS constraint 21), and neither should happen as a side effect of a sync-API ticket. Until
that ticket, `Use email` presents the existing "not yet" notice, which is the state ERRATA **E111**
already designed for.

**One consequence that is not optional.** Apple's account-deletion requirement means `DELETE /me`
must call Apple's revocation endpoint, which needs a token that exists only if the authorization code
was exchanged at sign-in. So the client sends the authorization code and the server stores the
refresh token. RULINGS **R3** already ships account deletion; without this it cannot keep the promise
Apple requires of it.

#### 3 — A magic link opened on a device other than the one that asked is refused

**Ruled: refuse.** Screen 15's headline is `Keep your three visits`, and the visits are on that
phone. A session minted on a laptop claims nothing and carries nothing across, while telling the
person they succeeded.

The link is bound to the requesting installation's device id and is single-use. Presented from
anywhere else the exchange returns `forbidden`, and the refusal is a **server-rendered page rather
than an app screen** — a browser is not the app, so the app cannot draw it. The requesting phone
changes no state and waits; there is no polling and no timeout to design.

**The rendezvous code was considered and declined**, priced at two new screens — a page that issues
and displays a code, and an in-app waiting state with a code field — plus a polling endpoint and a
second credential. Recorded so a later round starts from the price rather than from scratch. This
ruling binds the deferred email ticket; nothing in #158 implements it.

#### 4 — The service is written in Go, and this is a sanctioned deviation from BUILD-PLAN §3

**Ruled: Go + Postgres, one machine on `cypress-sync`.**

DECISIONS constraint 20 makes BUILD-PLAN §3's stack table binding without a written reason, and
`docs/ARCHITECTURE.md` §1 is the register of those reasons. Its backend row deviates on *not having a
backend*, not on the stack, so Fastify was the incumbent and Go owes a fifth row. The spec carries
that row for splicing; PostGIS is declined with it, because no server-side spatial query exists under
R36's local read path and carrying an extension for a query nothing makes is not continuity.

**The evidence, because the recommendation reversed on it.** The spec's first draft recommended
Fastify on the grounds that the riskiest surface in the ticket — verifying Apple's identity tokens —
had a more trodden path in Node, and it named its own tipping point: Go wins if a Go JWKS library
proves trustworthy. The survey found that `coreos/go-oidc` refetches on an unknown key id behind a
single flight (rotation with no cron) and checks algorithm, issuer, audience and expiry, with its
algorithm default already matching the only algorithm Apple signs with; that the widely-cited
alternative's advisory history lies entirely in encryption machinery this project never touches; and
that **neither ecosystem mints Apple's client secret**, so the hand-written residue is identical in
both. The delta the Fastify recommendation rested on does not exist. With auth a wash, two direct
dependencies, no runtime to patch, a static binary and a machine already deployed decide it.

**Where this ruling overrides the spec's own first recommendation, that is recorded rather than
tidied away**, and the same evidence names what would overturn it: the owner's own fluency. One
maintainer who reads TypeScript daily and Go rarely outweighs a smaller dependency tree, and that is
the single input the survey could not supply.

#### 5 — First-party photographs publish without screening at launch: a deliberate deviation

**Ruled by the owner, having been shown the cost in the same sentence, and recorded here as a
deviation rather than as a design that skips a step.**

**What the corpus asks for.** DECISIONS §4 puts nudity/person-safety screening and the face/plate
blur pipeline inside Phase 1 — they are its stated exception to what is not built — and BUILD-PLAN
§10 puts the blur at upload. **Neither exists.** Nothing in this repository raises
`Photo.blurApplied` or writes `.approved`.

**What was ruled.** A photograph from a signed-in account is approved on upload, unscreened and
unblurred, at launch. **The accepted cost:** an unscreened photograph can carry a face, a licence
plate, or the inside of somebody's front garden, and under this rule it reaches other people's
screens — the exact harm ERRATA **E147** cites as the reason a contributor may delete their own
photograph.

**First-party means the signed-in account, not the device.** The device credential is not an
attestation and a reinstall mints a new one, so a device-scoped rule gives a takedown nothing that
survives; an account carries Apple's verification and can have it withdrawn. It also makes screen
15's drawn sentence — *"An account backs them up and lets them join each tree's public timeline"* —
literally true, and leaves an anonymous contributor's photographs visible to them alone, which is
`isVisibleToItsContributor` behaving as ERRATA **E37** designed it. No screen changes.

**The way down ships with the way up.** `deletePhoto` already exists and is argued as a privacy
control in these very terms; under this rule it stops being a convenience and becomes the first line,
so it must be reachable wherever a photograph is shown. `Photo.moderationState` can move backwards
and `isPubliclyVisible` is evaluated at render time, so an operator takedown removes a photograph
from every other device at its next read with no app change, no new screen and no migration.
**Auto-approve without a takedown is the version of this rule that must not ship.**

**What does not exist, and #158 does not invent:** an in-app report-this-photograph control. No
`ReviewFlag` kind is about a photograph; adding one is a migration and the control is a screen not in
the mocks. And a photo **vote is not a report** — it feeds the hero selection, and reading a downvote
as a takedown request would let a popularity mechanism decide a safety question.

**The rule expires against the pipeline it stands in for.** The server records *why* a photograph is
approved, so "auto-approved at launch" and "screened and passed" stay distinguishable and the backlog
is re-runnable; `blur_applied = 0` is already a truthful cursor over every row in existence. When the
§4 pipeline lands it runs over that backlog and anything it fails moves to `.rejected`, which the
client already honors. **A photograph approved under this rule is not permanently exempt from the
mechanism DECISIONS §4 asks for.**

---

**One thing is named and still open**, and it is not part of this ruling: re-consent when the license
version moves. BUILD-PLAN §4 requires a text change to force it, the mechanism exists in
`User.hasAcceptedLicense(version:)`, and there is no surface to put it on — re-consent is neither the
account ask nor a setting. Named, not invented.

**No migration was authored.** #158 needs exactly one, in the writable database's counter, to let an
outbox row distinguish "applied locally" from "accepted by the server"; the spec names what it must
do and stops. The published city-file version is untouched.
