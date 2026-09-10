# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from branch `web/public-tree-read`, 2026-09-10, round W-G.

### What is publicly true about a tree: the public community read

*The owner ruled on 2026-09-10 that the public community read is built before the full W1 page. This
is that read's privacy contract — decided field by field, before the handler was written, because the
handler is where a decision like this stops being visible.*

The occasion is the web proposal's own amendment (`docs/design-proposals/2026-09-10-web-version.md`
§8a). `SCREENS.md` §W1 draws a page that is about half city record and half community layer, and the
published packs answer only the first half. The second half is in Postgres behind `cypress-sync`,
whose entire read surface today is **Class R — the contributor's own data**
(`server/internal/api/reads.go`). Nothing in this system has ever published one person's contribution
to another person, let alone to a page with no login that a search engine will index. So this is not
"the same data without the login"; for measurements and vitality **there is no existing surface at
all**, and that raises the bar rather than lowering it.

---

#### The rule that decides most of the fields

**The page publishes the state of the tree. It never publishes anybody's activity.**

A vitality rating, a taped diameter, a height — these are properties of a tree that happen to have
been established by a person. A visit, a photograph taken, a care event, a count of any of them —
these are accounts of what a person did, and where, and when. The first kind survives having its
author erased; the second kind *is* its author, wearing a tree's name.

Every refusal below is that sentence applied, and every publication is that sentence applied. It is
not new: it is what `Tree` and `TreeMeasurement` already are on the client, and it is why
`GroveRecord` counts on a private screen and `CypressAPI`'s public shapes count nowhere.

---

#### What the endpoint returns, field by field

`GET /api/v1/public/trees/{id}`, unauthenticated. `SCREENS.md` §W1's fact column is the checklist,
because it is the only drawn specification of this page that exists.

| §W1 element | Ruling | Why |
|---|---|---|
| H1 · `Grandmother Cypress` | **Not returned — unanswerable** | There is no tree name anywhere in this system. |
| `Status` · `Thriving · vitality 4` | **Returned** — the latest live rating, 1–5, month-dated | A rubric-scored property of the tree. |
| `Height` · `18 m` `est.` | **Returned** — latest live reading: value, entered unit, method, month | A property of the tree; D7 makes the method part of it. |
| `Trunk · DBH` · `64 cm` `taped` | **Returned**, same shape | Same. The *city's* DBH bucket is the pack's, not this. |
| Caption · `214 PHOTOS SINCE 2019` | **Not returned** | A public count of photographs. |
| Foliage strip | **Not returned** | Species phenology; it comes from the pack. |
| `Recent visits` panel | **Not returned** | Three independent grounds, below. |
| Photographs themselves | **Not returned in v1** | W-7, and the auto-approve rule. |
| Eyebrow, Latin line, `In the city record since`, `City record`, `Data` | **Not this endpoint's** | The pack answers all five (§8a). |

Everything not on that list is not returned either, and the mechanism that makes that true rather
than aspirational is the allow-list at the end of this ruling.

---

#### 1 · The counts. This is the rule most at risk here, and it is not the rule it looks like

`ARCHITECTURE.md:113` (§5 rule 1), which is DECISIONS §3.1's D1: *"No streaks, points, ranks, badges,
or public counts of user actions. If you find yourself writing `visitCount` into a user-visible
string, stop."* On 2026-08-31 the owner **refused** tester report F16 — trees-seen counters at 30 d,
year and lifetime — on exactly that rule, and the ROADMAP records the refusal rather than deleting it
*"because a refused report is a decision and the next person to have the idea should find the answer
instead of the idea."*

So the question has to be asked properly: **is a per-tree count the same thing as a per-user count?**

**No, and the project has already ruled so.** R27.1 overruled R27 for reading D1 too broadly:
*"D1 forbids ranking **people** … A ranked list of trees contains no person, exposes no person, and
rewards no person. R27 generalized a constraint on one noun to a different noun and called the result
principle."* R27 itself had put it the other way round in the same paragraph — *"D1 forbids counting a
person's actions; it does not forbid a tree having properties."* On the noun test alone, "214
photographs of this tree" is a fact about a tree and passes.

**It still does not ship, on three grounds that survive the noun test.**

- **R27.1 §5 already answered this exact count, and answered it no.** *"Favorites only. The owner was
  explicit that photo counts are not wanted here."* One signal, one meaning. A photo count is the
  composite-score shape the same section forbids, arriving on its own.
- **The floor is a privacy mechanism and no floor can be put on this one.** R27.1 §2 keeps R27's
  k-anonymity threshold untouched and says why: at a count of one the surface publishes somebody's
  private act, and at two it is inferable to whoever knows they are the other. The precedent floor is
  ≥3 distinct people (DECISIONS' caretakers rule). A *photo* count cannot be floored this way,
  because the number itself is the headline fact §W1 draws — suppressing it below the floor and
  printing it above the floor publishes "fewer than three people have photographed this tree", which
  is the same disclosure with an extra step.
- **E87 drew the line and this falls on the far side of it.** The one count this project has ever
  permitted — `Keep your three visits` — was allowed because *"this count is not public — the rows
  exist on one phone and are attributed to nobody — it is never compared or ordered, and it is not a
  reward."* Every clause of that argument fails here. It is public, it is on a page built to be
  compared and shared, and PRODUCT's non-goals table names *"leaderboards or ranked counts of
  photos/check-ins/care/favorites"* as a thing not to build, with the rationale attached: *"pays users
  to spam the record, poisons the health time series at the source."*

**Ruling: the public read returns no count of anything.** Not photographs, not visits, not
contributors, not readings. Not a boolean standing in for a count either — "this tree has
photographs" is the same disclosure at one bit of resolution, and one bit is all it takes when a tree
has one contributor.

**What is deliberately left open rather than refused:** the *beloved* state of R27.1 — trees ordered
by how many distinct people favorited them, above the ≥3 floor — is a ruled and permitted mechanism.
It is not built here because §W1 does not draw it, because its floor is still explicitly open in
R27.1 ("count it, do not guess it"), and because the distribution of favorites per tree has still
never been measured. It is a question for the owner below, not a refusal.

---

#### 2 · The recent-visits panel is refused, and it takes three independent grounds to say so once

`SCREENS.md` §W1 draws it: three rows, each a coloured chip, a line of text — two of them **verbatim
quoted contributor prose**, `"Fog dripping off the crown"` and `"Cones everywhere this year"` — and a
trailing date, `Oct 12`, `Sep 28`, `Sep 14`.

1. **It is a public user location history, which PRODUCT's non-goals table answers in one word:
   "Never."** Unattributed does not rescue it. R26 §2 already settled the general form — *"a pseudonym
   plus a fixed location is an identity"* — and this is weaker than a pseudonym only in that the
   reader has to do one more step: three dated visits to one street corner, on a page indexed under
   that corner's address, is a movement record whether or not a name is printed beside it. On a tree
   with one contributor it is *that person's* movement record with no inference required at all.
2. **The prose is unmoderated and there is nowhere to moderate it.** `photos` has a moderation state
   machine, a CHECK forcing `approval_reason` before `approved`, and an operator takedown route
   (`server/migrations/001_initial.sql`, `POST /api/v1/operator/photos/{id}/reject`).
   `contributions` has **none of that** — no state, no reason, no takedown, only `deleted_at`, which
   only the contributor's own withdrawal writes. `TreeObservation.note` is free text with no length
   bound and no screening anywhere in the system. Publishing it to an indexed page is publishing
   unscreened user text with no way to take it down short of a hand-written `UPDATE`.
3. **The rows carry claims that are not adjudicated.** An observation also carries
   `ObservationStatus` — `appears_dead` and `appears_removed` *open review flags* rather than
   asserting anything (DECISIONS §3.7) — and `structureFlags`, which may not appear on any surface
   without their verbatim disclaimer, *"informal observations, not a risk assessment"*
   (`StructureFlag.disclaimer`, BUILD-PLAN §4). `Watered, mulched` is a care event, which is an
   account of a person's afternoon.

This is a deviation from a transcribed screen, so it is an ERRATA entry before it is a code
decision, and the round writes one: `docs/errata-pending/w1-contributed-half.md`.

---

#### 3 · Vitality, height and DBH are returned, as values and not as events

These are the fields the sentence at the top admits, and the shape they take is the whole of the
argument that they are safe.

- **The latest live value only.** No history, no series, no list. PRODUCT's data-quality rule already
  says the display rule: *"When data conflicts, the most recent trusted value wins for display; full
  history is always retained."* Retained is not published. One value per field is a state; a list of
  dated values is the visits panel wearing a number.
- **The value, its entered unit and its method — all three, always.** D7 is not negotiable and the
  method badge is the fact column's entire point: `est.` and `taped` are what separate a reading from
  a guess, and R1 spent a token retint on making the two distinguishable to somebody with low
  contrast vision. A value published without its method would be this service laundering an estimate
  into a measurement.
- **The server does not convert.** `Quantity` stores the number as typed in the unit it was typed in,
  and derives SI rather than storing both. The web re-derives it from the ported `Quantity` (W-B). A
  units table in Go would be a second implementation of a Core rule, which is the two-copies failure
  this repository's own schema-version bullet exists because of.
- **Never the payload.** `contributions.payload` for a `measurement` is the whole `TreeMeasurement`,
  which carries `userID`, `deviceID`, `clientUUID` and `gpsAccuracyM`. Echoing it would publish the
  contributor's identifiers and how accurately their phone believed it was standing there. The
  handler projects named fields and cannot be written any other way — see the allow-list.
- **A value whose method or unit is outside the Swift vocabulary is not published at all.** "Render
  nothing where knowledge is absent" is the house style; a public page is the worst place to start
  guessing. The vocabularies are read off `Quantity.swift` and `Vitality.swift` by the tests rather
  than restated, the way `golden_test.go` already reads `TreePlacement` off `Tree.swift`.

---

#### 4 · Dates are published at month precision, and that is the whole of what is published about time

`2026-09`, never `2026-09-14`, and never more than one per value.

The value's date is part of the value — a diameter with no date is not a reading, and a growth series
that could not be dated would be worthless. The *day* is not part of the value; the day is where the
contributor was. Month precision keeps every use the fact has and drops the use it should not have,
which is exactly the move the project already makes for photographs: `Coordinate
.snappedToPublicPhotoGrid()` blunts a public coordinate to 25 m rather than withholding it
(`publicPhotoGridM = 25`, A7, BUILD-PLAN §10).

This one is a genuine trade-off rather than a forced move, so it is also put to the owner below.

---

#### 5 · The 25 m grid does not apply here, and the reason matters for the next round

It applies to **photo** coordinates and to nothing else. `Coordinate.snappedToPublicPhotoGrid()`'s own
declaration says so — *"Tree pins themselves stay exact; this is only for photos"* — and DECISIONS
§3.10 agrees: *"Public photo locations snap to a universal 25 m grid. Tree pins themselves stay
exact."* Trees are public objects and their position is the city's published record, which arrives on
the web from the pack and not from this service.

**This response therefore carries no coordinate of any kind**, which is the strongest form of
compliance available: there is nothing here to snap. The standing obligation for the round that adds
photographs is stated now so it is not rediscovered: `photos.public_lat` / `public_lon` are snapped
before they are stored (001's own comment) and a public read may publish those columns and never any
other position.

---

#### 6 · No photographs, and not even their identifiers

W-7 deferred photographs on the public surface and this ruling agrees, with the reason sharpened.

`cypress-photos` is private by design and anonymous reads were verified to return 403. The moderation
state that would authorize publication is `approved`, and under R72 ruling 5 the launch rule writes
`approval_reason = 'auto_approved_launch'` — a value that exists precisely *"so the deviation stays
legible as one"*. So `approved` today means "a signed-in account uploaded this", not "somebody looked
at it". `blur_applied` is, in 001's own words, *"truthfully false on every row in existence"*; the
face and licence-plate screening D11 requires is a pipeline that does not exist. Publishing an
unscreened first-party photograph to an indexed page under that rule would be the version of the
auto-approve rule R72 says must not ship.

**Not even the ids.** A photo id is a handle, this service already exposes `GET /photos/{id}`, and
the deployment round puts the caller on the open internet. An id published today is an authorization
decision taken by whoever wires the next route.

---

#### 7 · Nobody is named, and this service could not name them if it were asked to

D11 is *"contribution feeds private by default with opt-in public attribution"*, and DECISIONS §3.11
gives the mechanism: *"public timelines say 'a visitor' unless `public_attribution` is opted into, and
always for under-18 accounts."* The flag is `User.publicAttribution`
(`Cypress/Core/Models/User.swift:53`), default `false`, gated by
`isPublicAttributionEffective` — which returns false for `.under18` whatever the stored preference
says — and ERRATA E100 records that **it cannot be turned on anywhere in the app**.

**And the server has neither column.** `users` in `001_initial.sql` is `id`, `apple_subject`, `email`,
`provider`, `role`, `license_version`, `license_accepted_at`, `apple_refresh_token` and timestamps.
There is no `public_attribution` and no `birth_year_bucket`, so this service cannot evaluate either
half of the predicate. A public read that named anybody would be doing it on an assumption.

**Ruling: the response carries no contributor identity in any form** — no name, no user id, no device
id, no stable pseudonym, no per-contributor grouping, and no field from which one contributor's
records could be told apart from another's. That last clause is the one that does the work: an
unattributed *list* still segments into people. Publishing one value per field means there is no list
to segment.

Adding the columns that would make attribution possible is a migration and its own ruling. R26 §2
binds whoever writes it: *"`User.publicAttribution` cannot be turned on anywhere today (E100), so
there is no path by which this leaks; the constraint is written down here so that whoever does build
attribution knows adoption is not covered by it."*

---

#### 8 · Moderation, withdrawal, and a page a search engine has already indexed

The proposal names this as open (§9.2, ROADMAP "Open, and named as open" item 2). It closes here.

**a. Every answer is computed from live rows at request time.** Nothing is materialized, nothing is
denormalized, and there is no second copy to forget to invalidate. A contributor's withdrawal
(`contributions.deleted_at`, which every read in this service already narrows on), an operator
takedown (`moderation_state = 'rejected'`) and the leaving door's anonymization (`anonymized_at`, both
owner columns cleared) each take effect on the next request with nothing to purge.

**b. Bounded staleness downstream, stated as a number.** The response carries
`Cache-Control: public, max-age=60`. Sixty seconds is the ceiling on how long a withdrawn value can
survive anywhere downstream, and it is chosen against the takedown route: an operator who removes
something expects minutes, not hours, and a public page that could not be cached at all would put
1.1 million URLs of crawler traffic onto one shared-cpu-1x machine. The round that renders the page
may not cache beyond this.

**c. A withdrawal removes a fact from a page. It does not remove a page.** This is the answer to the
indexed-page question, and it is available only because of how W-C is shaped: the page's spine is the
*city record* — address, city, species, planted year, external ref, inventory source — which is
public data under ODbL that no contributor can withdraw. Nothing user-contributed is load-bearing for
the URL's existence. So a withdrawal, a takedown or a deleted account leaves a page that still
resolves, still says what the city knows, and no longer says the withdrawn thing. There is no dead
URL, no removal request to file with a search engine, and no cached page asserting something that has
been taken back. Tree UUIDs stay *"stable and citable from day one"* (PRODUCT §Licensing), which they
could not be if a withdrawal could 404 a page.

**d. The one case that must 404 is not this endpoint's.** A URL naming a tree that is in no published
pack has no spine and no page. That is decided at the pack layer by W-C, and this endpoint is not
consulted.

---

#### 9 · Absent, empty and fully-private are one answer, and it is not `not_found`

The brief for this round asked that a missing or fully-private tree be indistinguishable from a
non-existent one, and pointed at the photo read, which answers `not_found` rather than confirming a
row exists (`DeletePhotoByContributor`: *"a refusal would confirm the row exists to somebody who is
not allowed to know that"*).

**The posture is right and `not_found` is the wrong instrument for it here**, because the two ids are
not alike. A photo id is a private handle. A **tree UUID is public by design** — it is in the packs,
and it is in every share link screen 10 has ever produced: `SharePresentation.swift:173` builds that
URL as `ShareCopy.publicURLPrefix + tree.id.uuidString.lowercased()`, so the share link's last path
segment *is* the tree UUID. PRODUCT commits to those ids being *"stable and citable from day one"*. There is no tree existence to protect. What must not be detectable is the state
of the *community half*: whether this tree has contributions that are all withdrawn, or none at all,
or is not a tree at all.

A 404 would answer that question rather than avoid it. So: **every syntactically valid UUID gets 200
and a body of the same shape**, and the body for a tree with nothing publishable is byte-identical to
the body for a UUID this database has never seen. A malformed id is `validation_failed`, matching
`parsePathUUID` and every other route — a syntax error is not an existence oracle.

The invariant is asserted on the bytes, in three directions at once, because an invariant of this
kind stated in prose is the kind of claim this project has repeatedly found to be false under a
passing test.

---

#### 10 · The allow-list, which is the mechanism the rest of this ruling rests on

`contributions.kind` is a closed CHECK vocabulary of seventeen values
(`004_measurement_withdrawal_kind.sql`). The public read classifies **every one of them** as published
or withheld, and a kind that is not classified is a build failure rather than a default.

**It is an allow-list because a deny-list on a public surface is how this repository's most recent
near-miss happened.** `testflight.yml`'s `plan` job classifies paths by deny-list, and a new
top-level `web/` matched neither list — so the safe-looking default was "run everything and ship a
TestFlight build" (proposal §7). The same structure here would mean the *next* contribution kind is
public the day it is added, decided by nobody. Under an allow-list a new kind is invisible until
somebody writes down why it should not be, which is the only ordering that survives an author who has
not read this file.

| kind | | why |
|---|---|---|
| `measurement` | **published**, projected | a property of the tree (§3) |
| `observation` | **published**, `vitality` only | the rating is a property; the note, status and flags are not (§2, §3) |
| `visit` | withheld | location history (§2) |
| `care_event` | withheld | an account of a person's actions at a place |
| `favorite_toggle` | withheld | private (R2, D11); the beloved state is R27.1's and is open |
| `private_reminder` | withheld | private by name and by D4 |
| `add_tree` | withheld | a community tree has no page in v1; the pack is the spine |
| `species_claim`, `species_correction` | withheld | unadjudicated assertions; 002 declines to materialize the chain, and *"never displays as official until verified"* |
| `wrong_species_report`, `never_existed_report` | withheld | unadjudicated accusations |
| `species_review_dismissal`, `record_review_dismissal` | withheld | moderation bookkeeping |
| `photo_vote` | withheld | a count of user actions, and R72: a vote is not a report |
| `photo_withdrawal`, `measurement_withdrawal` | withheld | removals; the effect is visible, the act is not |
| `hazard_redirect` | **withheld, absolutely** | see below |

**`hazard_redirect` is the one with a pre-existing invariant attached to it.** DECISIONS §3.4:
*"Hazard categories never produce a public note, never produce a community-visible record, and never
auto-stale. **No public surface query may be able to return a hazard-category note (enforced by a
schema invariant test).**"* PRODUCT's non-goals table says the same in three words: *"Hazards
becoming public notes | Never."* Until this round there was no public surface query in the system, so
that invariant test had no subject. It has one now, and the round writes it.

---

#### 11 · Rate limiting

A public unauthenticated read is the most exposed thing this service has, and the existing limiter is
not shaped for it. `ratelimit` is an in-memory per-key token bucket at burst 60, one token per second,
keyed by `Fly-Client-IP` — sized for one phone draining an outbox, and its own header says the
sizing out loud: *"a normal minute for one phone is single digits."*

**The caller here is not a phone, and the naive reuse would be a self-inflicted denial of service.**
The web is server-side rendered and calls this server-to-server, so *every reader in the world
arrives from one address* — the SSR machine's. A 60-burst, 1-per-second bucket on that key throttles
the entire site to one page per second, which is the exact failure `clientKey`'s own comment warns
about from the other direction: *"getting this wrong would put every request in one bucket and
rate-limit the whole app as if it were one phone, which is a denial of service written by hand."*

**Ruling: its own limiter, its own budget — burst 120, one token per 50 ms (20/s sustained).** Sized
against what the endpoint costs (indexed reads on `idx_contributions_tree`, no writes, bounded output)
rather than against what a phone does, and separate from the app's limiter so a flood on either cannot
spend the other's budget. It is generous for a browser and cheap for Postgres, and it holds the line
that matters — one address cannot monopolize the single machine R72 sizes this service to.

**It is the right instrument only until the caller has an address.** Once the SSR machine exists, the
honest control is that this route is reachable *only* from it — a Fly private-network address rather
than a per-IP bucket over the public internet. That is W-E's to decide with the deployment in front of
it, and it is named in the questions below rather than assumed here.

---

#### What this ruling does not decide

- **Whether W1's H1 exists at all.** There is no tree name in either half of the system: no column in
  the seed contract (§8a), and no naming mutation in `contributions.kind`'s seventeen values.
  `community_trees` records having *removed* a `display_name` on purpose. A named tree is a feature
  nobody has designed, and it would be the highest-risk free-text field on a public page.
- **The beloved state** (R27.1), including its floor, which R27.1 leaves open and asks to be measured.
- **Community-added trees.** They are in `community_trees` and in no pack, so they have no spine and
  no page in v1. Whether they get one is W-C's.
- **CORS.** Not needed: the caller is the SSR server, not a browser. A later round that serves this
  endpoint to browser JavaScript needs it, and needs a fresh look at §11.
- **Anything about a surface that accepts a contribution.** This is a read.

---

#### Questions for the owner

Each is a specific choice with a recommendation and the trade-off it costs.

**Q1 · Date precision on a published value — month, year, or the exact day?**
*Recommended: month* (`2026-09`), as ruled in §4. Year loses real information — a reading from
January and one from December of the same year are a growing season apart, and the growth-charting
work depends on the interval. The exact day is the contributor's whereabouts, and on a tree with one
contributor it is a movement record with no inference needed. **Trade-off:** month precision makes
same-season readings unorderable on the public surface, so a public growth chart built later would
have month-resolution x-values. The alternative worth considering is *day precision above a
contributor floor* — exact dates only where three or more distinct people have contributed to the
tree — which keeps precision where it is anonymous. That is more machinery than v1 needs and it is
offered rather than recommended.

**Q2 · Does the beloved state ship on the public tree page?**
*Recommended: not in v1.* R27.1 authorizes the mechanism — trees ordered by distinct favoriters,
floor ≥3 — and it is the one count this project has ruled publishable. But §W1 does not draw it, its
floor is explicitly open pending a measurement of the real distribution, and R27.1's own closing
paragraph warns that at beta volumes an order that reshuffles on one tap is worse than no order.
**Trade-off:** the page ships without the single signal that would make it a discovery surface rather
than a record, which is the purpose the owner gave R27.1 in the first place — *"part of the point of
the app is to bring people TO trees."* If the answer is yes, the floor has to be chosen from real data
first, and the tree page is a per-tree surface where a rank has no meaning; the honest per-tree form is
the state (*beloved* / not) rather than a position.

**Q3 · Is a contributed tree name a thing that will exist?**
*Recommended: not now, and not without its own design.* §W1's H1 is `Grandmother Cypress` and nothing
in the system can produce it, so W-C's H1 falls back to the species name from the pack — which is
itself thin, because `common_name` is null on real rows (§8a). **Trade-off:** the page loses the line
that makes it worth sending to a friend, which is what the caption says the page is for. Against
that: a public, indexed, contributor-set H1 is unmoderated free text in 42px serif, and this system
has no moderation machinery for text at all. If the answer is yes it needs a naming design, a
moderation path, and a migration — not a column added quietly to make a headline render.

**Q4 · Should the public read be reachable from the open internet at all, or only from the SSR
machine?**
*Recommended: open, with §11's limiter, for v1; revisit at W-E with the deployment in front of you.*
An open endpoint is independently useful — it is the beginning of the API a researcher would cite,
which PRODUCT names as the real adoption path — and it is testable from anywhere. **Trade-off:** it is
also the only unauthenticated surface this service has, and locking it to the Fly private network
would make its attack surface zero at the cost of making it invisible to everyone except our own web
page. The choice is between "this is an API" and "this is an internal detail of the web app", and it
should be made deliberately rather than by whichever deployment lands first.

**Q5 · Ratify the refusal of §W1's recent-visits panel and photo count.**
*Recommended: refuse, as ruled in §1 and §2.* These are drawn in a transcribed screen and in the mock,
so refusing them is a deviation the errata entry records, and a deviation on the owner's own
specification deserves an explicit ratification rather than an author's judgment.
**Trade-off, stated honestly:** the panel is the warmest thing on the page. Without it the fact
column is six rows of numbers, and the human evidence that anyone loves this tree — the thing that
makes W1 a page about a *tree* rather than a database row — is gone. If the owner wants that warmth
back, the shapes that could carry it without publishing a movement record are worth putting to
design: a single undated line of the most recent contributed *state* change, or the beloved state of
Q2. Both are more honest than a dated feed and neither is drawn anywhere yet.
