# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from branch `web/public-tree-read`, 2026-09-10, round W-G.

### What is publicly true about a tree: the public community read

*The owner ruled on 2026-09-10 that the public community read is built before the full W1 page. This
is that read's privacy contract — decided field by field, before the handler was written, because the
handler is where a decision like this stops being visible.*

The occasion is the web proposal's own amendment (`docs/design-proposals/2026-09-10-web-version.md`
§8a). `SCREENS.md` §W1 draws a page that is about half city record and half community layer, and the
published packs answer only the first half. The second half is in Postgres behind `cypress-sync`.

> **Corrected after the adversarial review of this round's PR, and the wrong sentence is kept so the
> correction is legible.** This paragraph read: *"whose entire read surface today is **Class R — the
> contributor's own data** (`server/internal/api/reads.go`). Nothing in this system has ever
> published one person's contribution to another person."* **The second sentence is false, and it was
> the organizing premise of everything below it.** `GET /api/v1/trees/{id}` → `treeProfile`, in that
> very file, returns other contributors' publicly-visible photographs to **any** authenticated caller
> for **any** tree, together with `photo_count` and `visit_count`. So this system already publishes
> one person's contribution to another person, and already ships a per-tree count of user actions —
> the two things §1 and §2 below argue from. The refusals still hold, but they hold on the narrower
> claim, not the sweeping one.

**The narrower claim, which is the true one and the one this ruling rests on: no existing surface
publishes a measurement or a rating to anybody but its own contributor, and no existing surface of
any kind answers somebody with no account at all.** Both halves of that matter and they are different
bars. `treeProfile` is behind a credential, which is a person who signed in with Apple and accepted a
licence; this page is behind nothing, on a URL a search engine will index and a stranger will find.
So this is not "the same data without the login" — for measurements it is a first, and for *anybody
without an account* it is a first twice over. That raises the bar rather than lowering it.

**And the shipped route's own two counts are a live question rather than a precedent.** They have
never been tested against D1, and this round is not the one to change a shipped route it did not
write; it filed the question instead (`docs/ROADMAP.md`, chip backlog). Nothing below may be read as
this ruling endorsing them.

---

#### The rule that decides most of the fields

**The page publishes the state of the tree. It never publishes anybody's activity.**

A vitality rating, a taped diameter, a height — these are properties of a tree that happen to have
been established by a person. (The rating turns out to fail a *second* test this ruling did not
originally have — §8 — and is not published; it is kept in this sentence because the sentence is
about what kind of fact a thing is, and on that question the rating still belongs here.) A visit, a photograph taken, a care event, a count of any of them —
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
| `Status` · `Thriving · vitality 4` | ~~**Returned** — the latest live rating, 1–5, month-dated~~ **Not returned** | **Changed after review.** It is a property of the tree and it passes the rule above — but it has no takedown route, so it fails the second rule §8 grew. |
| `Height` · `18 m` `est.` | **Returned** — latest live reading: value, entered unit, method, month | A property of the tree; D7 makes the method part of it. |
| `Trunk · DBH` · `64 cm` `taped` | **Returned**, same shape | Same. The *city's* DBH bucket is the pack's, not this. |
| *Beloved* — not drawn in §W1 | **Returned** as a boolean, at ≥3 distinct owners | Owner ruling, 2026-09-10: the beloved state ships, as a state and not a rank (§1a). |
| Caption · `214 PHOTOS SINCE 2019` | **Not returned** | A public count of photographs. |
| Foliage strip | **Not returned** | Species phenology; it comes from the pack. |
| `Recent visits` panel | **Not returned** | Three independent grounds, below. |
| Photographs themselves | **Not returned in v1** | W-7, and the auto-approve rule. |
| Eyebrow, Latin line, `In the city record since`, `City record`, `Data` | **Not this endpoint's** | The pack answers all five (§8a). |

Everything not on that list is not returned either, and the mechanism that makes that true rather
than aspirational is the allow-list at the end of this ruling.

---

#### 1 · The counts. This is the rule most at risk here, and it is not the rule it looks like

`ARCHITECTURE.md:113` (§5 rule 1): *"No streaks, points, ranks, badges, or public counts of user
actions. If you find yourself writing `visitCount` into a user-visible string, stop."* That sentence
is **DECISIONS §3's constraint 1** in ARCHITECTURE's words (`DECISIONS.md:124`, which ends *"(D1)"*),
and it is the constraint form of decision **D1**, *"Kill the leaderboard"* — whose own wording is
*"non-ranked, no counts attached to countable actions"* (`DECISIONS.md:8`). Named that way here
because an earlier draft of this paragraph attributed the quoted string to D1 itself, and D1 does not
contain it. On 2026-08-31 the owner **refused** tester report F16 — trees-seen counters at 30 d, year
and lifetime — on exactly that rule, and the ROADMAP records the refusal rather than deleting it
*"because a refused report is a decision and the next person to have the idea should find the answer
instead of the idea."*

So the question has to be asked properly: **is a per-tree count the same thing as a per-user count?**

**No, and the project has already ruled so.** R27.1 overruled R27 for reading D1 too broadly:
*"D1 forbids ranking **people** … A ranked list of trees contains no person, exposes no person, and
rewards no person. R27 generalized a constraint on one noun to a different noun and called the result
principle."* R27 itself had put it the other way round in the same paragraph — *"D1 forbids counting a
person's actions; it does not forbid a tree having properties."* On the noun test alone, "214
photographs of this tree" is a fact about a tree and passes.

> **The three grounds below were rewritten after the adversarial review, which checked every
> citation in this ruling line by line and found that the load-bearing one did not say what this
> paragraph said it said.** The refusal stands; the argument for it was wrong in three places and the
> wrong versions are quoted here rather than deleted, because they were the version the owner would
> otherwise have ratified.
>
> 1. *"R27.1 §5 already answered this exact count, and answered it no … A photo count is the
>    composite-score shape the same section forbids, arriving on its own."* **R27.1 §5 does not rule
>    on a lone per-tree count.** It governs which signal the *beloved-trees ranking* uses, and what
>    it forbids is **blending**: *"Do not blend photographs, visits or care events into a composite
>    score — a composite is unreadable, unfalsifiable, and is the shape that eventually grows into a
>    leaderboard."* A lone count is by definition not a composite, so the gloss inverted the section.
>    What §5 does supply is narrower and is used below: an explicit statement of the owner's
>    disposition — *"The owner was explicit that photo counts are not wanted here"* — scoped to that
>    ranking.
> 2. *"E87 drew the line … the one count this project has ever permitted."* **It is not.** R27.1 §1:
>    *"Showing the number too is permitted and preferred."* E87's reasoning is still useful and is
>    kept below; the superlative was false.
> 3. *"at a count of one the surface publishes somebody's private **act**."* R27.1 §2's word is
>    **bookmark** — *"the surface publishes somebody's private bookmark"* — and the substitution is
>    what carried a k-anonymity argument about *favorites*, which are private by rule (D11), onto
>    *photographs*, which are not private at all: R72 §5 ships them to other people's screens on
>    upload. The floor argument survives, on a ground that does not depend on the swap.

**It still does not ship, on three grounds that survive the noun test.**

- **D1 forbids public counts of user actions, and nothing carves photographs out.** ARCHITECTURE §5
  rule 1 is unrestricted as to noun on the *count* side — *"no … public counts of user actions"* — and
  a photograph is a user action however the count is framed. **The honest shape of this argument is
  that it is about the scope of a carve-out rather than a blanket rule**, because R27.1 did carve one
  out: a per-tree count of distinct *favoriters* may be shown, above a floor. So the question is
  whether that carve-out reaches photographs, and the answer is that R27.1 declined to extend it —
  §5, *"Favorites only. The owner was explicit that photo counts are not wanted here."* That is an
  owner disposition inside a ranking rather than a general prohibition, so it is offered as what it
  is: the nearest thing to a ruling on photograph counts that exists, and it points away from
  shipping one.
- **A floor is what makes the favorites carve-out safe, and no floor can be put on this one.** R27.1
  §2 keeps R27's k-anonymity threshold untouched and says why: at a count of one the surface
  publishes *"somebody's private bookmark"*, and at two it is inferable to whoever knows they are the
  other. The precedent floor is ≥3 distinct people (DECISIONS' caretakers rule). A *photo* count
  cannot be floored this way, because the number itself is the headline fact §W1 draws — suppressing
  it below the floor and printing it above the floor publishes "fewer than three people have
  photographed this tree", which is the same disclosure with an extra step. A favorites *state* has
  no such problem, which is exactly why it can ship (§1a) and this cannot.
- **E87's reasoning, applied here, fails on every clause.** E87 permitted `Keep your three visits`
  because *"this count is not public — the rows exist on one phone and are attributed to nobody — it
  is never compared or ordered, and it is not a reward."* Not one of those is true of a photograph
  count on an indexed page: it is public, it is on a page built to be compared and shared, and
  PRODUCT's non-goals table names *"**Leaderboards or ranked counts** of photos/check-ins/care/
  favorites"* as a thing not to build, with the rationale attached: *"Pays users to spam the record,
  poisons the health time series at the source."*

**Ruling: the public read returns no count of anything.** Not photographs, not visits, not
contributors, not readings. Not a boolean standing in for a count either — "this tree has
photographs" is the same disclosure at one bit of resolution, and one bit is all it takes when a tree
has one contributor. **The one boolean that does ship carries a floor, which is the difference; §1a
argues it rather than assuming this sentence does not reach it.**

---

#### 1a · The beloved state ships, and it is the one thing on this page that survives every test at once

**Ruled by the owner on 2026-09-10, after this ruling was written and against its own Q2
recommendation:** the beloved state ships on the public tree page — **as a state, not a rank.** Q2
below is left standing with its recommendation and is marked answered, because a recommendation the
owner overruled is a decision and deleting it would hide one.

The shape, and every clause of it is load-bearing:

- **A boolean, never the number.** R27.1 §1 permits the number — *"Showing the number too is
  permitted and preferred"* — and this publishes less than permitted. Two reasons. §1's permission is
  reasoning about a **ranking**, where showing an order while hiding the count is the worst of both
  because the reader infers a number anyway and cannot tell how thin the margin is; there is no
  ranking on a single tree's page and therefore no margin to misjudge. And this ruling's §1 refuses
  every count on this page, so publishing one here would need §1 rewritten rather than read around.
  Whether the number should ride along after all is **Q6** below.
- **True only at three or more distinct favorite owners.** R27.1 §2's floor, unchanged and not
  negotiable downward.
- **It is a state, so PRODUCT's non-goal is not merely dodged but unmet.** The non-goals table
  forbids *"**Leaderboards or ranked counts** of photos/check-ins/care/favorites"* by name, and that
  row has never been struck or annotated for R27.1 — the tension between it and R27.1 §1's ordered
  list is real and is not this round's to resolve. A per-tree boolean is neither a leaderboard nor a
  ranked count: nothing is ordered, nothing is compared, and no number exists to farm.

**Why §1's own objection to booleans does not reach this one.** §1 refuses "not a boolean standing in
for a count either — 'this tree has photographs' is the same disclosure at one bit of resolution, and
one bit is all it takes when a tree has one contributor." That is right about photographs, and the
reason is in the bullet above: no floor can be put on a photo count, because the count is the drawn
headline fact. A favorites boolean has a floor, and the floor is the whole mechanism — `true` cannot
occur below three distinct owners, so it never publishes one person's private bookmark, and `false`
covers nought, one and two indistinguishably.

**The floor is R27.1's provisional ≥3 and this round did not measure the distribution.** R27.1 asks
for the real one — *"the numeric floor, which wants the real distribution of favorites per tree
before it is chosen — count it, do not guess it"* — and the attempt to read it off the production
database was refused before any query ran. So this ships R27.1's own figure, inherited from
DECISIONS' caretakers precedent, and says so rather than presenting an unchanged default as a
finding. **The round that measures it may raise the floor; it may not lower it.** R27.1's other
closing warning applies to a *ranking* at beta volumes and not to a state, which does not reshuffle.

**One honest limitation, because the count is what the floor is made of.** `favorites` is keyed one
row per **owner** per tree, and an owner is a user *or* a device (`favorites_owner`). One person
holding a tree on a signed-out phone and a signed-in one is two owners. That makes the floor slightly
weaker than three *people*, never stronger. Raising it is a data question and is part of what the
measuring round should answer.

**And it is the only publishable fact here whose way down is complete**, which is why it survived the
narrowing §8 forced on the vitality rating. Un-favoriting is an ordinary toggle with a real off state
(R2), and account deletion runs `DELETE FROM favorites` under **both** doors — the leaving door
included, because 001's own comment says an ownerless favorite is *"a row no query returns and no
person can remove"*. There is no state in which a beloved tree cannot stop being one.

---

#### 2 · The recent-visits panel is refused, and it takes three independent grounds to say so once

`SCREENS.md` §W1 draws it: three rows, each a coloured chip, a line of text — two of them **verbatim
quoted contributor prose**, `"Fog dripping off the crown"` and `"Cones everywhere this year"` — and a
trailing date, `Oct 12`, `Sep 28`, `Sep 14`.

1. **It is a public user location history, which PRODUCT's non-goals table answers in one word.**
   `PRODUCT.md:49`, the whole row: `| Public user location history | Never. |` The rationale cell is
   the single word *"Never."* and there is nothing to interpret. Three dated visits to one street
   corner, on a page indexed under that corner's address, is a movement record whether or not a name
   is printed beside it; on a tree with one contributor it is *that person's* movement record with no
   inference required at all.

   > **Corrected after review.** This ground read: *"Unattributed does not rescue it. R26 §2 already
   > settled the general form — 'a pseudonym plus a fixed location is an identity'."* **R26 §2 holds
   > the opposite of what it was cited for.** Its ruling is that adoption updates *must* arrive
   > **unattributed** — *"'someone recorded a watering', never a name and never a stable pseudonym,
   > since a pseudonym plus a fixed location is an identity"* — so unattributed is R26's *remedy*,
   > not a thing it rejects. The quoted sub-clause is accurate and R26 §2 does establish that a
   > pseudonym plus a fixed place is an identity; what it does not establish is that stripping the
   > pseudonym leaves something publishable. This panel does not need it to. PRODUCT's row above is
   > unconditional as to attribution: it forbids the *history*, not the byline.
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

#### 3 · Height and DBH are returned, as values and not as events

~~Vitality, height and DBH~~ — **the rating is no longer returned; see §8.** It passed everything in
this section and failed the takedown test, which is the rule §8 grew after the review. The section is
otherwise unchanged, and it is written to apply to the rating too, so that the round which restores
it has the argument already made rather than having to remake it.

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
- **"Latest" means latest per measurement kind, and a newer estimate does supersede an older taped
  reading.** The review found this endpoint doing it and found the code claiming otherwise; the claim
  came down rather than the behavior, and the reason is that **no rule in this repository states a
  precedence between an estimate and a measurement.** D7, DECISIONS constraint 2, ARCHITECTURE §5
  rule 3 and PRODUCT's non-goal are rules about a *chart line* — the non-goal's rationale cell reads
  *"Never share a chart line"* — and E103 extends them to a spoken summary. None of them is about
  which single number is current. The client has no such rule either:
  `TreeProfilePresentation.latestMeasurement` is `filter { kind }.max { capturedAt }` with no method
  term, `MeasureModel.previousMeasurement` is a verbatim second copy, and
  `GrowthHistoryPresentation.chart(for:)` re-merges both series for its own labels. Authoring one
  here would make the page print `64 cm taped` where the phone prints `90 cm est.` for the same tree.
  What keeps it honest is the bullet above: the superseding value arrives carrying `est.`, which is
  the whole of what D7 requires. The product question — *one tree, one current height: should the
  method count?* — is real, has four call sites, and is filed on the roadmap rather than answered by
  one endpoint.
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

The proposal names this as open (§9.2, ROADMAP "Open, and named as open" item 2).

> **This section claimed to close it and it closed two-thirds of it. Corrected after the adversarial
> review, with the overclaim quoted.** The headline was and is *"a withdrawal removes a fact from a
> page, it does not remove a page"*, and the review proved it false for one of the three values then
> published. **There is no observation withdrawal anywhere in this system**: `contributions.kind`'s
> seventeen values carry `measurement_withdrawal` and `photo_withdrawal` and no counterpart for the
> `observation` that holds the rating, `contributions` has no `moderation_state` and no operator
> takedown — which **c** below listed as one of its three levers, and only two of the three reach
> this response. A withdrawal aimed at a rating answers `applied` and the rating stays on an indexed
> page, for its contributor and for an operator alike.
>
> **The rule this produced, which is a second rule and not a refinement of the first: this endpoint
> publishes nothing it cannot also un-publish.** What a page may say and what a page can stop saying
> are two questions and this ruling had answered only the first.
>
> **So the response narrows rather than the claim widening.** `vitality` is removed. Making it
> publishable means adding an observation-withdrawal kind, which is a **migration**, and CLAUDE.md
> gives one migration author per round — this round has none, and taking a seat that was not assigned
> is how two schema versions have collided here before. The roadmap carries the item.
>
> The question therefore **does not close**. It is answered for the two readings and the beloved
> state, and it stays open as the general rule until every published field has a route down. That is
> written into `docs/ROADMAP.md` in this PR rather than left as a strike-through that says CLOSED.

**a. Every answer is computed from live rows at request time.** Nothing is materialized, nothing is
denormalized, and there is no second copy to forget to invalidate. A contributor's withdrawal
(`contributions.deleted_at`, which every read in this service already narrows on) and the leaving
door's anonymization (`anonymized_at`, both owner columns cleared) each take effect on the next
request with nothing to purge.

~~an operator takedown (`moderation_state = 'rejected'`)~~ — **struck: that column exists on
`photos` and not on `contributions`.** §2 of this same ruling says so two sections earlier
(*"`contributions` has **none of that** — no state, no reason, no takedown, only `deleted_at`"*) and
this bullet listed it anyway. Nothing this endpoint publishes has an operator route today.

**a-bis. Two limits on "a contributor's withdrawal", both stated rather than implied.**

- **An anonymized reading is beyond withdrawal, and that is the leaving door working.**
  `withdrawMeasurement` refuses a row owned by nobody — its own comment: *"An anonymized row …
  is owned by nobody and therefore refused"* — while this endpoint deliberately keeps reading
  anonymized rows, because `AccountDeletionChoice.leaveRecords` promises the record stays. The person
  who could have withdrawn it chose to leave it. That is consent, not a gap, and it is why the
  behavior is kept; it does mean "a withdrawal removes a fact" is a claim about a *live-owned* row.
- **There is no third party who can remove anything.** With no `moderation_state` on
  `contributions`, a reading that is wrong, or malicious, or simply unwanted by everyone but its
  author has no removal route but its author's. That is a real limit of what ships, and the round
  that adds the observation-withdrawal kind is the natural place to add an operator one beside it.

**b. Bounded staleness downstream, stated as a number.** The response carries
`Cache-Control: public, max-age=60`. Sixty seconds is the ceiling on how long a withdrawn value can
survive anywhere downstream, and it is chosen against the takedown route: an operator who removes
something expects minutes, not hours, and a public page that could not be cached at all would put
1.1 million URLs of crawler traffic onto one shared-cpu-1x machine. The round that renders the page
may not cache beyond this.

**c. A contributor's withdrawal removes their reading from a page. It does not remove a page.** —
narrowed from *"A withdrawal removes a fact from a page"*, per the correction above: it is true of
the two readings and of the beloved state, and it was not true of the rating, which is why the rating
is not published. This is the answer to the indexed-page question **for what this endpoint publishes**,
and it is available only because of how W-C is shaped: the page's spine is the
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

`contributions.kind` is a closed CHECK vocabulary of seventeen values, declared across the migrations
with the last declaration winning — as of this round, `004_measurement_withdrawal_kind.sql`. The
public read classifies **every one of them** as published or withheld, and a kind that is not
classified is a build failure rather than a default.

> **The mechanism was real and its guard was not, and the guard is the part this section claims.**
> The review added an eighteenth kind as `005_*.sql` — the only way one can arrive, since an applied
> migration is frozen and this vocabulary has grown twice already by way of a new file — and
> `TestEveryContributionKindIsClassified` stayed **green with an unclassified kind live in the
> schema**, because it read one hardcoded path while `loadMigrations` applies every `.sql` in the
> directory. The allow-list in `publicKinds` did hold: the new kind was not published. What did not
> hold was the ordering this section credits it with, which is that *somebody is forced to decide*.
>
> Fixed in this PR: the guard reads the whole directory in version order, a second guard asks the
> running database through `pg_constraint` so a spelling the regexp cannot parse is still caught, and
> a third holds `syncKinds` — a third restatement of the same seventeen values that nothing had ever
> forced to move — against the same source.

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
| `observation` | ~~**published**, `vitality` only~~ **withheld** | the rating is a property and the note, status and flags are not — but the rating has no takedown route, so nothing from this kind is published (§8) |
| `visit` | withheld | location history (§2) |
| `care_event` | withheld | an account of a person's actions at a place |
| `favorite_toggle` | withheld as a **record**; the derived state is published | the individual toggle is private (D11) and is never read. The *beloved* boolean is computed from the `favorites` table above a ≥3 floor and names nobody (§1a) |
| `private_reminder` | withheld | private by name and by D4 |
| `add_tree` | withheld | a community tree has no page in v1; the pack is the spine |
| `species_claim`, `species_correction` | withheld | unadjudicated assertions; 002 declines to materialize the chain, and *"never displays as official until verified"* |
| `wrong_species_report`, `never_existed_report` | withheld | unadjudicated accusations |
| `species_review_dismissal`, `record_review_dismissal` | withheld | moderation bookkeeping |
| `photo_vote` | withheld | a count of user actions. (R72 §5's *"a photo vote is not a report"* is about hero selection versus safety reporting and is **not** authority for withholding it here; cited earlier for a proposition it does not carry, corrected after review.) |
| `photo_withdrawal`, `measurement_withdrawal` | withheld | removals; the effect is visible, the act is not |
| `hazard_redirect` | **withheld, absolutely** | see below |

**`hazard_redirect` is the one with a pre-existing invariant attached to it.** DECISIONS §3.4:
*"Hazard categories never produce a public note, never produce a community-visible record, and never
auto-stale. **No public surface query may be able to return a hazard-category note (enforced by a
schema invariant test).**"* — that is DECISIONS §3's **constraint 4** (`DECISIONS.md:127`); §3 is a
flat numbered list, so "§3.4" is the house shorthand for it and not a heading. PRODUCT's non-goals
table says the same at `PRODUCT.md:51`, and the row reads
`| Hazards becoming public notes | Hazards can never become public notes. |` — quoted exactly here
and corrected in `public.go`, which had rendered the rationale cell as *"Never."*, three words the
document does not have. (PRODUCT has a **second** hazard row at `:44`, about reports being accepted
in-app; they are different rules and "the hazard row" names neither on its own.)

Until this round there was no public surface query in the system, so that invariant test had no
subject. It has one now, and the round writes it — and re-proved it after `vitality` left the
response, because the payload the guard leans on had been given a rating *and* a quantity precisely
so the widening would be observable, and removing one of the two could have reopened the
green-with-the-defect-present hole. It did not: the quantity half still goes red.

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

**And the key the bucket hangs on is supplied by the request, which this ruling should have said.**
`clientKey` returns `Fly-Client-IP` when present, and the only thing that makes that trustworthy is
Fly's proxy overwriting the header before the app sees it. The review measured the consequence
directly — after exhausting a bucket, 25 of 25 requests carrying a self-chosen `Fly-Client-IP` were
served. It is pre-existing and it is not a live exploit, but **until this round every route behind it
also required a credential**, and this one requires none: the protection is now entirely "the proxy
rewrote it", which is a thing to write down rather than to be true by luck.

Two narrowings ship, and neither is claimed to be the fix: a value that is not an IP address is no
longer used as a key at all, and the bucket map is now bounded (`ratelimit.maxBuckets`), so the
memory a forger can hold is capped on a 256 MB machine. **The fix is to stop trusting the header
unless the connection came from the proxy**, which is a trust-boundary change to a deployed service
that nothing in this round can verify against a request it watched arrive — the review could not
confirm the proxy's rewrite either, only from documentation. It also becomes moot if **Q4** is
answered "SSR-only", so it is filed on the roadmap tied to that question rather than guessed at
here.

---

#### What this ruling does not decide

- **Whether W1's H1 exists at all.** There is no tree name in either half of the system: no column in
  the seed contract (§8a), and no naming mutation in `contributions.kind`'s seventeen values.
  `community_trees` records having *removed* a `display_name` on purpose. A named tree is a feature
  nobody has designed, and it would be the highest-risk free-text field on a public page.
- ~~**The beloved state** (R27.1), including its floor, which R27.1 leaves open and asks to be
  measured.~~ **Decided by the owner on 2026-09-10 and built — §1a.** The floor is still R27.1's
  provisional ≥3 and is still unmeasured; that half stays open and is Q7.
- **Whether an estimate should ever be superseded by, or supersede, a measurement** when one number
  has to be chosen. Nothing in the corpus rules on it, the client picks the most recent regardless of
  method in three places, and this endpoint matches the client rather than inventing a fourth answer
  (§3). Filed on the roadmap because it is four call sites' question.
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

**Q2 · Does the beloved state ship on the public tree page? — ANSWERED: yes, as a state, not a
rank** (owner, 2026-09-10). Built as §1a describes: a boolean, true only at ≥3 distinct favorite
owners, no number. **The recommendation below was the opposite and is left standing rather than
edited away**, because a recommendation the owner overruled is a decision and rewriting it to agree
would hide one. Note in passing that the owner's "state, not a rank" is the form this recommendation
itself named as the honest one for a per-tree surface, in its own last sentence.

*Recommended (not taken): not in v1.* R27.1 authorizes the mechanism — trees ordered by distinct favoriters,
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
so refusing them is a deviation, and a deviation on the owner's own specification deserves an
explicit ratification rather than an author's judgment.

> **Read this before ratifying, because the last version of this question was put to you on citations
> that do not hold.** The review checked every one. The visits-panel refusal is solid and was always
> solid — `PRODUCT.md:49`'s `| Public user location history | Never. |` plus the plain absence of any
> moderation machinery on `contributions` — but the **photo-count** refusal was argued mainly from
> R27.1 §5, which governs blending signals into a composite score in a ranking and does not rule on a
> lone count; and from E87 as *"the one count this project has ever permitted"*, which R27.1 §1
> contradicts in as many words. §1 above is rewritten on grounds that check out, and the honest shape
> of the surviving argument is weaker than the old one: it is about **whether R27.1's favorites
> carve-out reaches photographs**, not about a blanket rule. If you ratify, ratify that.
>
> **And this ruling asserted a procedure that does not exist.** It said a deviation from a
> transcribed screen "is an ERRATA entry before it is a code decision". No rule in this repository
> says so. `ROADMAP.md:65` covers **SCREENS-versus-mock disagreement**, where the two sources conflict
> — here they agree — and DECISIONS constraint 21 covers **inventing** an unmocked screen. The
> errata file admits as much itself. The entry was still the right instrument and is kept; what is
> withdrawn is the claim that writing it followed a documented rule. It created one. **If you ratify
> Q5, saying so makes it a rule** — which is Q8.
**Trade-off, stated honestly:** the panel is the warmest thing on the page. Without it the fact
column is rows of numbers, and the human evidence that anyone loves this tree — the thing that makes
W1 a page about a *tree* rather than a database row — is gone. Part of that is now answered: **the
beloved state ships** (§1a), which is one of the two shapes this trade-off named as the honest
alternatives. The other — a single undated line of the most recent contributed *state* change — is
still undrawn and still worth putting to design.

---

*The three questions below arrived with the adversarial review and did not exist when this ruling was
first written.*

**Q6 · Does the beloved *count* ride along with the state?**
*Recommended: no, ship the boolean alone.* R27.1 §1 permits the number and prefers it — but it is
reasoning about a ranking, where an order without a count is the worst of both, and there is no
ranking on one tree's page. §1 of this ruling refuses every count on this page, and publishing one
would need §1 rewritten rather than read around. **Trade-off:** "beloved" is a coarser fact than "11
people keep this tree", and the number is the more interesting sentence to read. Against that, a
number is farmable in a way a floored boolean is not, which is D1's whole reason, and the floor is
currently a guess (Q7) — a number resting on an unmeasured threshold overstates its own precision.

**Q7 · Choose the beloved floor from measured data, or keep R27.1's ≥3?**
*Recommended: ship ≥3 now, measure before raising, never lower.* R27.1 asks for the real distribution
and **this round did not get it** — the attempt to read it off the production database was refused
before a query ran, so the number in the code is R27.1's own inherited figure and nothing more. That
is said in the code and in §1a rather than left to be assumed. **Trade-off:** at real beta volumes ≥3
may turn out to be either far too permissive (if a handful of people favorite nearly everything) or
so strict that no tree is ever beloved. Both are bad, and neither is knowable from here. The
measuring round is small — one aggregate query — and it should happen before this state is anything
but decorative.

**Q8 · Is "a refusal of a transcribed element is an ERRATA entry" a rule?**
*Recommended: yes, write it down.* This round behaved as though it were, the review found no such
rule, and the practice observed elsewhere is different again — a refused element is struck through in
`SCREENS.md` itself with the authority annotated in place (two worked examples at `SCREENS.md:1129`
and `:1276`). Three conventions for one situation is how a corpus starts disagreeing with itself.
**Trade-off:** writing it down adds a step to every screen deviation, and most deviations are small.
The alternative is that the next author picks whichever of the three they find first.
