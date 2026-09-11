# Roadmap

Sequenced plan for everything after M0. Milestones follow ARCHITECTURE §8; this document is the
detail underneath them — what gets built, in what order, and why that order.

Screen numbers refer to `docs/distilled/SCREENS.md`. Where a decision here departs from a source
document, it cites the entry in `docs/ERRATA.md` that records the conflict.

---

## Status

**M0 through M4 are complete.** All nineteen screens are built, routed, tested and committed, with
the animation, Dynamic Type and VoiceOver passes behind them. What remains before the app installs on
a phone is M5, below.

**The five questions that were design's and had no answer are now ruled on** — see `docs/RULINGS.md`.
They were delegated explicitly by the project owner on 2026-07-21, and R1 is the only place in the
app where a transcribed hex has been overruled. That file, not this one, is where a designer arriving
later should start.

Three things learned along the way that outrank anything in the sequencing below.

**Confident comments are where bugs live.** Four defects survived because documentation asserted the
behavior: `SQLiteError.code` described as a primary result code when the connection returns extended
ones, `Photo` documented as EXIF-stripped when nothing stripped it, `awaitingWifiCount` describing a
predicate it did not implement, and `RootView` explaining that the location provider carried no
accuracy an hour after it started to. Each read as verified. None was. **When auditing, start with
the most confident comment in the file.**

**Fix the representation, not the instance.** The changes that will still be true in a year made the
bug unrepresentable: `Series` with no `count`, so a page cannot be printed as a total;
`ReportSelection` as one enum, so a hazard and a note cannot be held at once; `OutboxPhoto` with no
`[String]` overload left behind; `MonthRange.spanning`, so authoring order stops mattering;
`VitalityRow` with no initializer that accepts copy.

**A red test seen during concurrent work is not evidence.** See ARCHITECTURE §7. This produced one
wrong diagnosis already.

### The handoff is a set of screens, not an app — resolved, under an exception

It used to read: five of thirteen built screens have no way in — **05, 11, 12, 13 have no entrance
at all, and 07 has exactly one** — their exits drawn while nothing opens them, every route wired,
every destination tested, and each affordance a design decision that neither an agent nor I should
invent (DECISIONS constraint 21). By the time 16 and 17 landed the count was six.

**All six are reachable now.** I granted a one-time, explicit exception to constraint 21 covering
exactly these six entrances and nothing else. What was invented under it, what turned out to have
been specified all along, and what each of it can be overruled from is `docs/ERRATA.md` **E98**;
E24, E57, E63, E66, E74 and E75 each carry their own resolution. The `Journal` and `You` tabs were
built to hold two of them, minimally — E99 and E100 record what they deliberately do not contain.

The exception is spent. Constraint 21 stands for everything else.

---

## Ordering principle

Build outward from the loop a contributor actually walks, not inward from the data model. The
sequence below is roughly: finish the thing a person does on their first walk, then the thing they
do on their tenth, then the thing they do when something goes wrong.

Two rules hold throughout:

**No screen ships against a mock alone.** Every screen is implemented against `SCREENS.md`, which is
the transcription; the mock is the check, not the source. Where they disagree the disagreement is an
ERRATA entry before it is a code change.

**Nothing is invented.** DECISIONS constraint 21 — an unmocked destination is a question for the
design, not a case to make up. Where a state genuinely has no mock (vacant sites, error surfaces),
the resolution is written down here first and flagged for design review, rather than settled quietly
inside a view file.

---

## Now — correctness pass (resolved)

Ahead of new screens because both defects corrupt data that cannot be recovered afterwards.

- **Unknown leaf retention** (ERRATA E9, resolved). `leafRetention` becomes optional so the app stops asserting
  evergreen-or-deciduous for species nobody established. Carries through to the seed, the SQLite
  round trip, and every phenology and autumn-color surface. Loads `Fixtures/species/*.yaml` into the
  seed at the same time, and fixes two `sf_species_map.csv` defects: six non-taxa (`Shrub`, `Privet`,
  `To Be Determine`, …) mapped to real species ids, and `patanus racemosa ::` holding one species as
  two under different ids.
- **Outbox drops shot type** (resolved). The payload carries `photoPaths: [String]` with no shot type, so every
  synced photo is labeled `full_tree`. Fixed at the payload level, with migration for outbox rows
  already persisted on disk.

---

## M1 — finish the core loop (screens 05, 06)

**05 · Light check-in.** The five anchor rows, each a vitality judgment bound to its rubric
sentence verbatim (D3). This is the highest-frequency contribution in the app and the one most
exposed to the unresolved rubric question below, so it is built with the rubric text as data rather
than as string literals in a view.

**06 · Report an issue.** The 311 redirect. Cypress does not accept hazard reports itself — D4 keeps
`HazardCategory` and `CommunityNote.Category` disjoint precisely so that a safety issue cannot
degrade into a community note. This screen must hand off cleanly and record that it did.

Also in M1: permission-denied states for location and camera, which the design mocks and the current
build does not implement.

---

## M2 — one level deeper (screens 07–13)

Ordered by how much each depends on data the app already has.

| | Screen | Note |
|---|---|---|
| 1 | **07 Species page** | Unblocked by the correctness pass; renders the curated content and must render nothing where knowledge is absent. |
| 2 | **08 My Grove** | Species tab, C27 progress ring, C29 tiles. First screen keyed on the contributor rather than on a tree. |
| 3 | **13 Tree activity** | Reads timeline data the outbox already produces. |
| 4 | **09 Care log** | Bottom sheet over a dimmed profile. |
| 5 | **10 Share** | Public photo locations snap to the universal 25 m grid (DECISIONS §3). Non-negotiable and easy to get wrong. |
| 6 | **11 Growth history** | Only plots readings that pass `isEligibleForGrowthCharting` (D6). Sparse charts are correct output, not a bug. |
| 7 | **12 Neighborhood almanac** | Needs the neighborhood geometries from `j2bu-swwd` (ERRATA E2); the dataset the spec names serves empty polygons. |

---

## M3 — in the field (screens 14–19)

**14 Cold-start profile**, **15 the account ask** (third save; magic-link only, no passwords ever —
DECISIONS §3), **16 Measure**, **17 Outbox** (the queue made visible, including the 48 h give-up
state), **18 Next tree**, **19 Memorial**.

Plus the vacant-site screen decided below, which belongs with 14.

---

## M4 — dark mode and polish

D1–D3 are the only dark screens specified. The remaining coverage is resolved below. Then the
animation pass and an accessibility pass — Dynamic Type, VoiceOver labels on every C-component, and
contrast verification on the amber family, which is the palette most likely to fail.

---

## M5 — the thing installs on a phone

M4 was the last milestone about screens. M5 is about the difference between nineteen screens and an
app, which turns out to be short.

| | Work | Where it landed |
|---|---|---|
| 1 | **The vacant planting-site state** — 12,518 pins, 6.4% of the map (SF alone, as measured then; 24,200 / 12.2% across both cities today — E206), had been rendering as a stripped-down cold profile | E11 → **E107** |
| 2 | **The caption ramp** — `text.faint` failed AA in both appearances across 61 call sites | R1, R1a → **E108** |
| 3 | **Account deletion** — §3.12 and the exclusive-ownership CHECK could not both hold | R3 → **E109** |
| 4 | **Screen 01's navigation bar** — an opaque 91pt band on the one screen the spec calls full-bleed | **E110** |
| 5 | **Screen 15 gated** behind `BetaCapability.accountsAvailable` | R4 → **E111** |
| 6 | **The favorite comes off** — a tap that could be made and not taken back | R2 → **E112** |
| 7 | **A vacant site cannot open the tree profile** from any entrance | **E113** |
| 8 | **Icon, accent, launch screen** | — |

**M5 is complete.** Two of these were not on the list when M5 opened. E110 was found by photographing the
running app; E113 by noticing that E107 had fixed one entrance out of six.

Bundle identity was already set: `app.cypress.Cypress`, marketing version 0.1, portrait only, iPhone
only. **A local beta needs no Apple Developer Program membership** — a free Apple ID signs the app for
seven days at a time on the owner's own device, which is the right shape for this stage. A paid Team
ID buys a year instead of a week, TestFlight, and distribution to people who are not you; none of
that is needed until someone else is holding the phone.

### What M5 deliberately does not include

**A backend.** There is none and none is planned for the beta. Everything the app does is local: the
seed database ships in the bundle, contributions queue in the outbox and stay there, and no request
leaves the device. The outbox is not disabled for this — it runs, retries, and backs off exactly as
designed, against nothing. That is a better beta than a stubbed-out queue, because the thing being
exercised is the thing that will ship.

**Sign-in** — R4. **Moderation** — there is no moderator; E-numbered entries record what
`moderationState` means in the meantime. **iNaturalist licensing** — a position, not a permission,
and the owner has accepted it for the beta.

---

## W — the web version (opened 2026-09-10)

The owner opened this on 2026-09-10 and ruled its four forking questions the same day. The authority
is `docs/design-proposals/2026-09-10-web-version.md`; this section is the queue underneath it. **W1
below is the screen number from `SCREENS.md` §W1, not a milestone number** — the milestones here are
`W-A` through `W-E`, deliberately lettered so they cannot be read as M-numbers.

**The four rulings.** v1 is the **public read surface** (no login, no writes); it lives in **this
repository** at `web/`; the unspecified web pages are built under a **scoped constraint-21 exception**
in the shape of the one M5 was granted, with every invention written to `docs/rulings-pending/` for
ratification; and the runtime is **TypeScript + SSR self-hosted on Fly**. Vercel stays ruled out —
R36 / `RULINGS.md:2275`, the Hobby tier's non-commercial term against D14's paid org tier.

**Why this is ahead of the open tester items.** `SharePresentation.swift:245` ships
`https://cypress.app/sf/tree/` as the share-card prefix, and no such page exists. Every link screen 10
has ever produced is dead, which makes the growth loop `PRODUCT.md` names — "the share card *is* the
growth loop" — terminate at the moment of sharing. W1 is the page those links have always meant.

| | Milestone | Done when |
|---|---|---|
| **W-A** | Foundation | `web/` exists and builds; `testflight.yml` classifies it correctly so a web commit neither runs the iOS suite nor mints a TestFlight build; `web.yml` runs the web suite on ubuntu; `Tools/run_web_tests.sh` and `Tools/verify_web_test_log.sh` judge a log rather than an exit code. |
| **W-G** | The public community read | ~~`GET /api/v1/public/trees/{id}` answers the publicly visible community half of one tree with no credential, under a ruling that decides field by field what is publicly true about a tree.~~ **DONE** — the ruling is `docs/rulings-pending/public-tree-read.md` (unnumbered, awaiting the owner: it carries five questions), the endpoint and its golden fixtures are in `server/`. Ordered ahead of W-C by the owner on 2026-09-10, because §8a found that half of W1's fact column has no public read behind it. |
| **W-B** | The three portable assets | Design tokens exported from the Swift declarations to CSS custom properties, with a test that the export still matches its source; the domain rules (vitality rubric, `Quantity`, the 25 m grid, growth-charting eligibility, ID spaces) re-derived in TypeScript against ported Swift test cases; a read layer that opens a published city pack through the same schema the phone uses. |
| **W-C** | W1 · Public tree page | The page renders from a real pack at `/‹id-space›/tree/‹uuid›`, matching the `SCREENS.md` §W1 transcription, with the OpenGraph image its caption specifies rendered from the same ingredients. |
| **W-D** | The rest of the nav | `Explore`, `Species`, `Neighborhoods`, `Data & export` — designed under the W-3 exception, ruled, then built. |
| **W-E** | It is on the internet | Deployed to Fly against a volume holding the published packs; the share link resolves. |

### Decided in the proposal, not open

- **The read path is the published base layer**, mounted read-only. Not Postgres, not browser-side
  SQLite over range requests. This adds a second *consumer* of R36's base layer, not a second source
  of truth, and it is not R36's Shape B — nothing about the phone's read path changes.
- **No raster basemap in v1.** Explore draws pins over the neighborhood polygons already in the seed
  (`Fixtures/seed/schema.sql:129`). `DECISIONS.md:153` puts per-seat map licensing permanently out of
  scope; MapLibre over PMTiles on Tigris is the named path if a basemap is ever wanted.
- **No photos on the public surface in v1.** W1's specified hero is a gradient. `cypress-photos` is
  private by design and opening it is a D11 privacy decision with its own round.

### Corrected 2026-09-10, before any web code was written

Two decisions in the proposal were refuted by opening a real published pack (`us-ca-sj`, hash-verified
against the manifest, `count(*)` matching the manifest's tree count as the control). The amendment is
§8a of the proposal.

- **W1's fact column is about half contributed data.** Name, vitality, height, the taped DBH reading,
  the photo count and the recent-visits panel all live in the *writable* database and reach the
  server as contributions; the packs carry the city record. The API's public read surface is Class R
  — the contributor's own data — so v1 has no public read for any of it. W-C's scope is therefore an
  owner decision, not an implementation detail. The pack *does* answer the page's spine: address,
  city, species (though `common_name` is null on real rows), `planted_year`, `external_ref`,
  `inventory_source`, status, and the city's published DBH bucket.
  **Answered by W-G, in part, and the part moved twice — after its adversarial review and again
  after the delta review of the fixes.** The owner ordered the public community read built first, and
  it exists: **height and trunk DBH** each reach W1 as a value, its method and the month it was
  taken, and a **beloved** boolean reaches it too — a state and not a rank, per the owner's ruling of
  2026-09-10, true only above R27.1 §2's ≥3 floor. §W1 does not draw that one; it is the fact column
  being *longer* than its transcription in one place while being shorter in three.
  **Two further owner rulings of 2026-09-10 changed what that boolean means.** It counts only
  **account-backed** favorites — the delta review showed the old count was farmable at three
  unauthenticated `POST /devices/register` calls, which is D1's own stated reason for refusing public
  counts — and the **number rides along above the floor** (`beloved_by`), per R27.1 §1. W1 must
  therefore be prepared to draw "beloved by 7" as well as the bare state, and to draw nothing at all
  below the floor: the floor may well be unreachable in the beta, which the ruling says plainly
  rather than dressing up.
  **Vitality does not reach it**, though an earlier version of this bullet said it did: a published
  rating has no takedown route in this system, so it is deferred rather than refused (item 2 above).
  The recent-visits panel and the `214 PHOTOS SINCE 2019` count are refusals on the merits — things
  a public page may not carry (see `docs/errata-pending/w1-contributed-half.md`, whose photo-count
  argument was rebuilt after the review found its cited authority did not carry it). The H1 has no
  source anywhere in the system and is Q3 of the ruling's questions for the owner.
- **W-6 is withdrawn as a general answer.** "Explore draws pins over the neighborhood polygons already
  in the seed" holds for San Francisco and nowhere else: `Tools/build_seed.py:2105` loads exactly one
  polygon file, DataSF's SF-only `j2bu-swwd`, and `neighborhoods` is **0 rows** in the San Jose pack.
  Six of seven packs have no neighborhoods, which hits the `Neighborhoods` nav destination hardest.

### Open, and named as open

1. **`cypress.app` is registered, and it expires 2026-11-03.** Measured by RDAP on 2026-09-10,
   calibrated against controls (a known-registered `.app` returns 200, an unregistered one 404):
   registered 2024-11-03 through **2026-11-03**, registrar Spaceship, status
   `client transfer prohibited`, nameservers `launch1/launch2.spaceship.net` plus a
   `verify.hn` verification record, **no A record and nothing served**. Registrant is redacted, so
   whether it is the owner's is not answerable from outside. W-E cannot finish without knowing, and
   the expiry is eight weeks out. Until then the site lives at its `.fly.dev` hostname and
   `ShareCopy.publicURLPrefix` does not move.
2. **What a withdrawn or moderated record does to an indexed public page. STILL OPEN — answered for
   what ships, not as a general rule.**

   ~~Not v1 — v1 renders city-record facts only — but it lands the moment anything contributed
   reaches W1.~~ **That scoping is dead**: W-G's endpoint ships contributed readings and a
   contributed state, so anything contributed *has* reached W1 and this is a live question rather
   than a future one.

   ~~**CLOSED by W-G**, in `docs/rulings-pending/public-tree-read.md` §8. The answer in one line: **a
   withdrawal removes a fact from a page, it does not remove a page.**~~ **Struck: W-G closed this
   and its adversarial review reopened it.** The claim was true of two of the three values that
   endpoint then published and false of the third. There is **no observation withdrawal anywhere in
   this system** — `contributions.kind` carries `measurement_withdrawal` and `photo_withdrawal` and
   no counterpart for the `observation` that holds a vitality rating — `contributions` has no
   `moderation_state` and no operator takedown, and a withdrawal aimed at a rating answers `applied`
   and changes nothing. The §8 bullet had listed an operator takedown among its three levers; that
   column is on `photos`, not on `contributions`.

   **What is settled, and it is most of it.** For the two readings and the beloved state: every
   answer is computed from live rows at request time, so a contributor's withdrawal, an
   un-favoriting and an anonymization each take effect on the next request with nothing to purge;
   `Cache-Control: public, max-age=60` is the ceiling on downstream staleness, and the round that
   renders the page may not cache beyond it. There is no dead URL to file a removal request for,
   because the page's spine is the *city record* — public data under ODbL that no contributor can
   withdraw — so nothing contributed is load-bearing for the URL's existence, and tree UUIDs stay
   "stable and citable from day one".

   **What is not settled, and closes this question when it is:** (a) an observation-withdrawal kind,
   which is a **migration** and therefore a round with a migration author — W-G had none and
   correctly did not take a seat, narrowing the endpoint instead so that the rating is not published
   at all; (b) an **operator** route on `contributions`, which does not exist in any form, so a
   reading that is wrong or malicious has no removal path but its own author's; and (c) the standing
   rule this produced, which should be written down when it is true: **this endpoint publishes
   nothing it cannot also un-publish.** Today it is true by subtraction.

   Restoring the `Status` row on W1 depends on (a). Bring back with it the three guards W-G removed
   with the field — `TestVitalityRatingsMatchTheSwiftRubric`,
   `TestSwiftIntEnumExtractorIsCalibrated` and their `swiftIntEnumRawValues` reader — **before** the
   projection, not after.
3. **Server CORS and Sign in with Apple JS**, both prerequisites for any web surface that *writes*.
   **W-G confirmed the read half needs neither** and deliberately built no CORS: the web renders
   server-side and calls `GET /api/v1/public/trees/{id}` server-to-server. A later surface that calls
   this service from browser JavaScript needs CORS *and* a fresh look at the public read's rate-limit
   budget, which is sized for one rendering machine's address rather than for many browsers'.
   v1 needs neither. `authOIDC` requires a nonce and fails closed, and the web flow's nonce is not the
   native flow's; that is an integration change, not a client rewrite.
4. **The Coordinator dashboard** (`PROTOTYPE-FLOW` PART 2, the paid org tier under D14). Fully drawn,
   but workdays, routes, claim/progress and the live feed exist in neither the server nor the app.
   A product round, not a port.
5. **The moderation console.** `ARCHITECTURE.md` §8 and `CypressAPI.swift:22` already assign
   `/admin/*` to web and declare it out of scope for iOS. No mock exists anywhere in the handoff.


---

## Resolutions on the three open questions

These were escalated and handed back. Each is a decision I am taking, with the reasoning, so it can
be overturned on the merits rather than rediscovered.

### 1. Vacant sites (ERRATA E11)

**24,200 pins — 12.2% of the map — are planting basins with no tree in them.** No mock covers this.
(The figure was 12,518 / 6.4% when this was written; that was San Francisco alone, and San Jose has
since landed. Re-measured on the shipped two-city seed 2026-08-02 — ERRATA E206.)
Screen 14 currently offers "be the first to photograph this tree," which asserts a tree that is not
there.

**Decision: a distinct planting-site state, not a variant of the tree profile.** A site is not a
tree with missing fields; it is a different kind of thing, and modeling it as a degraded tree is
what produced the wrong copy in the first place. It shows what the city recorded about the site,
and its actions are *"report what's here"* and *"flag this as planted"* — both of which are claims
about the site, not about a tree.

**Why not just hide them:** 24,200 sites are the single best answer to "where could a tree go,"
which is close to the point of the app. Hiding them is a larger loss than an unmocked screen.

**Flagged for design.** This is new surface, and the decision above is the honest minimum rather
than a design.

### 2. Clustering versus SF's actual density (A1)

A1 says individual pins at zoom ≥ 16. At zoom 16 the median screen holds **1,899 trees and 98.6% of
pins overlap a neighbor**. 18 pt pins only separate at zoom 18.63 — a non-integer, so **no zoom
level satisfies both A1 and the city**.

**Decision: cluster until pins genuinely separate, and treat A1's threshold as an erratum.** A1 was
written without SF's density in front of it; honoring it literally produces an unreadable screen,
which cannot be what it was for. The map opens closer than the spec implies and transitions to
individual pins where they actually resolve.

Recorded as an ERRATA entry proposing the change rather than silently violated — the number in A1 is
wrong, and the document should say so.

### 3. Dark mode for the 59 unspecified tokens (ERRATA E8)

78 of 137 tokens have a documented dark value; 59 do not. Bottom sheets and the entire amber family
would glare.

**Decision: derive the missing values from the documented pairs, then mark every derived token as
derived.** The 78 specified pairs are a sample of a transform the designer applied consistently;
fitting that transform and applying it to the remaining 59 is a far better guess than either
per-token invention or leaving the app broken in the dark.

The critical part is the second half: derived tokens are **labeled as derived in TokenGallery**, so
review is one screen showing exactly the 59 values that were guessed, rather than an audit of the
whole palette. Any token a designer corrects stops being derived and becomes specified.

**Not derived, escalated instead:** any token where the transform disagrees with a documented pair by
more than a small tolerance. That is a sign the transform does not apply there — as with the taped
badge, where the dark pair was documented in prose and initially transcribed as light-only.

---

## Also outstanding

### Tester feedback, reconciled against main 2026-08-28

The 20 re-queued reports from PR #118's verbatim table, audited item by item against origin/main
with receipts. Nine were already shipped (1, 2, 3, 5, 6, 7, 8, 10, 11 — all but the first two in
PR #102's beta-polish, which merged the day build 49 was cut, so the tester reported against fixes
that had not yet reached a build). What remains OPEN:

- **F4 — a time filter** (today / this week / this month / last 30 days / past year). No period
  selector exists on any screen; which screen the tester meant is itself unconfirmed. **See the
  determination below** — the spec's only time vocabulary is binary and lives on another screen.
- **F15 — enrich the tree profile**: ID help, history/etymology, usage/edibility. Content work;
  pairs with the parked seed-prose pass, and invented botanical content is forbidden (DECISIONS
  constraint 15) — sourcing is the work.
- ~~**F16 — trees-seen counters (30d / year / lifetime).**~~ **REFUSED by the owner, 2026-08-31.**
  The counters stay unbuilt and the rule stands as written: ARCHITECTURE §5 rule 1 — "No streaks,
  points, ranks, badges, or public counts of user actions. If you find yourself writing
  `visitCount` into a user-visible string, stop" — which is D1 in DECISIONS §3. The report asked
  for the one thing that rule names, so there was nothing to build that would not have been the
  rule being set aside. Recorded rather than deleted, because a refused report is a decision and
  the next person to have the idea should find the answer instead of the idea.
- **F22 — species distribution as a static city map** (one point per tree) on the field guide's
  §5; today it is two stat cards. **See the determination below** — unspecified, but the reduced
  map component it would use is not.
- ~~**F23 — "See them all on the map"** link from Grove/Journal into the map filtered to yours; the
  target filter exists (`MapFilter.membership`, chip "Yours"), nothing routes into it.~~
  **DONE — the link ships on the Journal tab's `Yours` segment.** `AppRouter.goToMap(showing:)` arms
  a one-shot narrowing that screen 01 applies on arrival; the chip reads selected and `Clear
  filters` is in the row from the first frame. **The placement is the owner's to ratify** — no mock
  draws this link (DECISIONS constraint 21) — and the PR asks. It is deliberately **not** on My
  Grove's `Trees` pill, which is where the sentence reads most naturally and where it cannot keep
  its promise: the grove's list includes trees you have only favorited and the map's `Yours` filter
  deliberately does not (R23), so the same link there would silently drop rows the reader can still
  see. See **ERRATA E287**, and
  `CypressTests/SeeAllOnMapTests`, which pins both halves.
- **F25 — Account/You page UI/UX pass.** **See the determination below** — there is no You screen
  in the spec at all, only its tab-bar icon.
- ~~**F26 — Measure: unit switch clears the entered value.**~~ **RULED keep-the-digits-and-annotate
  by the owner, 2026-08-31, and shipped here.** The flip keeps the typed digits untouched (5 stays
  5, never converted) and the screen says what changed under them: `Typed in centimeters, now read
  as inches.` The annotation withdraws itself when the digits are cleared, or when a second flip
  returns them to the unit they were typed in.
  **The premise this entry carried was wrong and is corrected here rather than deleted**: keeping
  the digits does *not* falsify `Quantity.value`. That invariant is about the stored record, and a
  `Quantity` is only ever built at save out of whatever digits and unit the pad holds then — so
  typing 5, flipping to feet and saving stores `value: 5, unitEntered: ft`, which is exactly "the
  number as the human typed it, in the unit it was typed in". Converting on the flip is what would
  break it, and nothing converts. The field's own doc comment now records this.
  The copy and its placement are **NOT SPECIFIED** by SCREENS.md and go to the owner under
  DECISIONS constraint 21; see `docs/rulings-pending/measurements-round.md`.
- **F27 — measurements can be neither edited nor deleted. BLOCKED ON A SCHEMA MIGRATION**, and the
  premise needs splitting in two.
  **"Edited" is already answered and needs nothing built.** This app has no edit verb for any
  contributed record, by design: `CypressAPI`'s whole write surface is append-or-withdraw, species
  corrections supersede rather than overwrite (`superseded_by`), and every capture screen carries
  the burden in its confirmation because nothing can be amended afterwards. Changing a reading is
  adding a reading, which screen 16 already does — and F28's link, shipped here, is what makes that
  reachable in one tap on the tree where it was hardest.
  **"Deleted" is real, designed, and stops at a migration.** The `measurements.deleted_at` tombstone
  exists; what does not is an `OutboxItem.Kind` to sync a withdrawal under. `outbox.kind` is a
  closed `CHECK` vocabulary that SQLite cannot widen in place, so a `measurement_withdrawal` kind is
  a table rebuild — the writable schema's next migration, exactly as v4 and v17 were.
  `CommunityOutboxKindTests`' "every kind the app can build is one the outbox can store" is the
  guard that makes this unavoidable rather than optional. **One migration author per round and this
  round had none**, so the design is written down and the code is not: see
  `docs/rulings-pending/measurements-round.md`. The two rejected shortcuts are recorded there too —
  riding the existing `measurement` kind with a payload discriminator (which `OutboxItem.Kind`'s own
  comment forbids: it would put the distinction "inside a payload field where `outbox.kind` cannot
  see it"), and shipping the UI local-only, which would re-create the Class L debt spec §3.4's nine
  mutations were queued to pay off — a delete the reader believes is everywhere and that never
  leaves the phone.
- ~~**F28 — adding a reading on a tree holding both height and DBH** is two small-text taps deep;
  the add-a-reading card only exists while its own measurement is missing.~~ **SHIPPED.** Screen 03
  now draws an `Add a reading` link — `See every reading`'s twin, same tokens, one block down —
  in exactly the state where no stat card is a door. The rule it restores: **while a tree accepts
  contributions the profile always offers a way into screen 16, and never two.** That covers the
  city-bucket tree as well as the fully measured one, which a "both measurements present" fix would
  have missed: a published DBH range suppresses the empty slot just as a reading does.
  `MeasureEntranceKindTests` asserts it over the state space and `AddReadingReachabilityTests` walks
  the tap. **The affordance is NOT SPECIFIED** — no mock draws it — so it goes to the owner under
  DECISIONS constraint 21, by ARCHITECTURE §5 rule 8's practice of taking the nearest specified
  thing; the PR asks.
- ~~**F17 — neighborhood stats far from home.**~~ **SHIPPED** by the neighborhood/city picker
  round (`feat/stats-picker`). Both halves: the two stats segments now state where their area came
  from and offer a picker, and — the mechanism the report actually came from — a location fix whose
  own accuracy is wider than the 400 m search that names a neighborhood is no longer used to name
  one (`AlmanacLimits.fixCanResolveAnArea(accuracyM:)`). **The premise this entry carried was
  wrong and is corrected here rather than deleted**: "the nearest tree is very far away" is not a
  state the shipped code could reach — `resolveNeighborhood` is bounded at 400 m and
  `resolveIDSpace` at 1,200 m, so a distant reader already got the out-of-range screen. An
  approximate-location fix is what put a confidently named neighborhood in front of a reader who
  was nowhere near it.

### The three open tester items share one root cause, determined 2026-09-09

F4, F22 and F25 were each carrying a different-sounding blocker ("which screen", "content work",
"UI/UX pass"). Read against `docs/distilled/SCREENS.md` they are the same blocker: **the mocks never
drew the thing**. None is a fix; each is a design round under DECISIONS constraint 21, and each is
one owner sentence away from being schedulable. The evidence, so that round starts from facts:

- **F4 — a time filter.** No period selector is specified on any screen. The only time vocabulary in
  the entire spec is screen 17's Outbox line — `this week · 14 synced · 0 lost` with a trailing
  `full history` link — which is **binary**, not the five-way selector (today / this week / this
  month / last 30 days / past year) the report asked for. So the request has no spec support
  anywhere, and the nearest specified thing is a two-state toggle on a different screen.
  **The owner's sentence:** which screen, and is the vocabulary the Outbox's two states or a new one?
- **F22 — species distribution as a static city map.** The word "distribution" does not appear in
  `SCREENS.md`. Screen 07 §5 is the two count cards, exactly as shipped. A reduced map component
  does exist and is reused — `C18 · MapCanvas`, "the reduced version on 15/18" — so the raw material
  is specified even though the section is not.
  **The owner's sentence:** does screen 07 gain a C18-reduced band, and where relative to §5/§6?
- **F25 — Account/You pass.** There is no You screen in the spec at all. `C16 · BottomTabBar` names
  the tab and draws its icon (a 20x20 circle, letter `N`), and that is the whole of it: screens
  15-19 are the account ask, Measure, Outbox, Next tree and Memorial. Every surface the You tab has
  today was assembled from the nearest specified thing — the practice is visible in the tab's own
  empty state, which borrows screen 17's phrasing for the same fact.
  **The owner's sentence:** is F25 a mock round (draw the screen) or a consistency pass against the
  screens it borrows from?

### Follow-up tickets from the 2026-08-30 rounds

- **`cypressHitArea` overhangs whatever sits above it, everywhere it is used — audit the call
  sites.** Raised by PR #139's delta review, deferred out of that PR deliberately.
  `cypressHitArea` is a `background`, so its 44 pt rect never enters layout: a 13 pt text link
  carries a target that reaches ~17 pt past its own label in each direction, invisibly, and the
  later view in a `VStack` wins the overlap. PR #139 fixed the instance it created (F28's link
  swallowing `See every reading`) but the mechanism is general. The known remaining case is
  `TreeProfileMetrics.activityLinkTop = 8`, shared by `growthLink` and `activityLink`: on the
  arithmetic the link's rect reaches ~6-9 pt into the stat grid above it, so the bottom sliver of an
  empty measurement card would route to screen 11 instead of screen 16. **That figure is derived,
  not measured on screen**, and confirming it is the first step of this ticket.
  Deferred rather than folded into #139 for three reasons: it predates that PR on both links;
  the token fix (8 → 44) adds 36 pt of whitespace above two links on every profile, which is a
  larger user-visible change than the defect and is unratified; and the real repair is probably
  structural — a `cypressHitArea` variant that enters layout — which touches every call site in the
  app and deserves its own measurement round.

- ~~**The splice backlog (orchestrator-only).**~~ **DONE, 2026-09-09** — sixteen files spliced in
  one sitting: **E288-E321** (s17 region generation, the seed case-normalisation off-by-one, the
  NYC ingest and publish rounds, the photo storage/provenance facts, the journal tie-pagination
  defect) and **R89-R112** (s17 shape decisions, the seed pin and bundle scope, format-1
  retirement, the NYC publish owner decisions, the Cities-screen amendments, the picker header,
  the two perf-tab-load rulings, the favorites amendment to R2, and the two Grove-paging rulings).
  The E250 pan-probe amendment was folded into E250 itself rather than numbered separately.
  Citations were rewritten with it, including two that had moved *into* `RULINGS.md` as danglers —
  the failure that made splice #134 go red — and one stale pointer in `Tools/publish_cities.py`
  that had been deferring to `docs/rulings-pending/` for a rule numbered **R83** weeks ago.
  **One file is deliberately held**: `docs/rulings-pending/measurements-round.md`, whose third
  entry is the withdrawal design the live F27 round is building; it splices when that round lands,
  so the numbered entry records the outcome instead of "proposed, blocked".


- ~~**Map camera fits the filtered set.**~~ **SHIPPED** (`feat/see-all-camera`). The owner ruled
  the behavior on 2026-08-31 while trying build 63, and the ruling is narrower than this entry's
  title: the link opens on **the city where the reader has the most trees**, fitted to their trees
  in that city. The chip on screen 01 still moves nothing — the camera rides the link's own
  one-shot narrowing, so it cannot fire on a plain tab switch either. This closes the first of
  ERRATA E287's two axes; the second, the installed inventory, is still open. The three decisions
  under the ruling — fit rather than centroid, most-recent-contribution as the tie rule, and the
  next city winning when the winning city's pack has been removed — are in
  **RULINGS R87/R88** and were **ratified by the owner on 2026-08-31**, via
  the orchestrator, after the adversarial review.
- ~~**Screen 12's `COLLATE NOCASE` joins.**~~ **SHIPPED, one of the two**
  (`perf/almanac-nocase-joins`). `firstBloom`'s join took PR #131's `lower()` shape and both of
  R29's arms stopped building a transient index per execution — 4.5 → 0.02 ms by polygon, 33.7 →
  0.13 ms by radius. `AlmanacQueryPlanTests`, `AlmanacStatementCensusTests` and
  `AlmanacCollationEquivalenceTests` are the gates.

  **The entry's other half was refuted as stated, then closed by the next round.**
  `youngTreesWithoutVisits`' collation was never "the same class of full-inventory walk" — its plan
  was `SEARCH t USING INDEX idx_trees_neighborhood_planted | CORRELATED SCALAR SUBQUERY 1 | SCAN v`,
  a walk of the contributor's own visits per candidate tree, never of the inventory — and this round
  declined the only fix available to it, normalizing the *seed* side up
  (`v.tree_uuid = upper(t.uuid)`), because that is sound only while every `visits` row spells its
  uuid upper case, a property nothing asserts and whose violation returns visited trees as
  unvisited, silently. **`AppSchema` v19 (`perf/v19-index-round`) closed it the other way**, by
  recollating `idx_visits_tree` to `NOCASE` so the statement seeks it unchanged: 0.319 → 0.008 ms
  per candidate tree, 64 → 1.5 ms for a 200-tree card. The pin was rewritten with it —
  `AlmanacQueryPlanTests.theYoungTreeSubquerySeeksTheRecollatedIndex` now requires the seek, and
  proves that neither the `upper()` rewrite nor a bare comparison can reach it.

- ~~**`visits.tree_uuid` has no case contract, and that is what a seek there costs.**~~
  **SHIPPED for the contribution tables** (`AppSchema` v19). The entry proposed
  `anonymized_contributions`' answer — `COLLATE NOCASE` **on the column** — for whichever round held
  the migration seat. v19 took the cheaper half of it: the collation on the *leading column of the
  index*, which the same predicates can seek and which needs no backfill, applied to
  `idx_visits_tree`, `idx_observations_tree`, `idx_measurements_tree`, `idx_care_events_tree` and
  `idx_photos_tree`. That reaches both readers this entry named on the contribution side —
  `youngTreesWithoutVisits` and `ContributionStore.visits(treeID:)` (0.299 → 0.009 ms).

  ~~**Still open, and the two halves are not the same size.**~~ **SHIPPED, both halves**
  (`AppSchema` v20, `perf/v20-index-round`). `idx_species_assertions_tree` recollated the v19 way;
  `idx_species_assertions_head` deliberately stays BINARY — it is a partial UNIQUE index, and
  recollating it changes which rows the schema calls a conflict (the review constructed the
  two-case pair that would refuse to migrate). The community half turned out **not** to need the
  table rebuild this entry proposed: an *added* secondary index,
  `idx_community_trees_id ON community_trees(id COLLATE NOCASE)`, gives every
  `id = :id COLLATE NOCASE` read a seek without touching the PK. `SpeciesAccessPlanTests` and
  `SchemaV20Tests` are the gates. Two readers in the same family were out of v20's declared scope
  and still walk: `SpeciesAssertionStore.assertion(id:)` and `.supersede(id:)` predicate
  `id = :id COLLATE NOCASE` against `species_assertions`' BINARY autoindex — one more added-index
  fix, unmeasured, migration seat required.

- ~~**`species.uuid` is compared `COLLATE NOCASE` and has no lowercase gate.**~~ **SHIPPED**
  (`AppSchema` v20 round, `perf/v20-index-round`). Both checks the entry asked for were run and
  both broke the way it suspected: the seed's `species.uuid` is lower case per arm (0 of 731
  uppercase; `verify_seed.py` check 16d already enforces it for packs at publish time), and
  `SpeciesQueries.species(id:)`'s doc comment was indeed false — the real plan was
  `SCAN s USING COVERING INDEX`, a 731-row walk per lookup. The contract gate now covers
  `species.uuid` per arm (red-proved against a pack), the five readers moved to `lower(:uuid)`,
  and `SpeciesAccessPlanTests` pins the seeks — including a probe-bound test that goes red on the
  exact one-line BINARY-literal revert (the review found the first version of that test did not).

### Perf campaign close, 2026-09-04

The 2026-09-01 owner directive ("the app highly performant; that takes precedence") closed with
seven merged PRs — #143 Journal, #144 Grove paint, #145 Almanac, #146 v19, #147 Class-R
local-first, #148 v20, #149 Grove Trees paging — plus three rulings (local-first paint; tab models
keep state; favorites local-first amending R2) and two ruled in-round (Grove > Trees pages at 50
like the Journal; every phase draws, superseding the 26 ms decision whose small-grove premise broke
at 1,027 trees). Leftovers the reviews surfaced, none scheduled:

- **The post-drain favorite reconcile is exposed to read-replica lag.** Toggle drains, the queue
  empties, a stale server answer lands with the tap counter unmoved, and the reconcile assigns the
  pre-tap value. Pre-existing (remote-first `isFavorite` had the same exposure); documented in
  `ProfileFavoriteWriter.reconciledState`, not closed. Needs a server-side read-your-writes answer
  or a version/timestamp on the favorite row.
- ~~**Hoist the remaining grove SQL literals to named properties** (`groveTreeIDs`, `groveRecords`,
  `CommunityTreeStore.trees(ids:)`) so `GroveStatementCensusTests` can pin by property the way the
  almanac census does, instead of deriving five of seven expected texts by probe. The tallies
  literal was already collapsed onto `scopedHeroPhotoTalliesSQL` in #147.~~
  **SHIPPED** (`tools/shot-dir-and-sql-properties`). `ContributionStore.groveRecordsSQL`,
  `ContributionStore.ownHeroPhotoCandidatesSQL` and `CommunityTreeStore.treesSQL` are the hoists;
  the census pins all seven statements by property, per text, and the probe is gone.
  **Two claims in this entry were wrong, corrected here rather than left to mislead.**
  `groveTreeIDs` already had a property — `ContributionStore.groveTreeIDsSQL`, which
  `GrovePagedStatementCensusTests` reads — so the probe covered four of seven, not five. And the
  tallies literal was **not** collapsed in #147: that PR's review identified the duplicate and the
  test header it wrote says in as many words that it does not fix it. The second, byte-identical
  copy was still inside `heroPhotoIDs(treeIDs:connection:)` at `b5a929c`; it is removed here.
- ~~**`Tools/run_tests.sh` hardening, one sitting:** (a) a wedged `simctl bootstatus -b` is
  indistinguishable from a slow preflight and silently blocks every later run on that device;
  (b) the collision guard can self-match the *caller's own command line* when the wrapper
  invocation embeds both `xcodebuild` and the UDID (three refusals against a dead pid, 2026-09-02);
  (c) the guard's leftover-build refusal fires for ~1–2 minutes after a `-only-testing` run's
  wrapper exits, which the merge train should expect; (d) at the sanctioned three-concurrent-build
  cap the UI phase flakes with "Timed out while synthesizing event" — either lower the effective
  cap during UI phases or teach the harness to tell an event-synthesis timeout from an
  assertion.~~ **SHIPPED** (`tools/harness-hardening`). (a) `bootstatus` runs under a bound
  (`CYPRESS_BOOTSTATUS_TIMEOUT_S`, default 180 s) whose refusal names what it was waiting for, and
  another run's leftover `bootstatus` against the same device is refused rather than joined.
  (b) the collision guard skips this process's whole ancestor chain, which is the fix **E283**
  itself proposed, and re-checks liveness before refusing. (c) the refusal prints each pid's age
  and says which of the two things it is looking at — the tail of a wrapper that just returned, or
  a stray. (d) the **classification** option was taken, not the concurrency one:
  `verify_test_log.sh` answers `VERIFY-ENV-REFUSED` with exit **2** when every failure in a log is
  an event-synthesis timeout **and no counter in the log reports a failure beyond them** — no
  crash marker, no Swift Testing aggregate, no XCTest count larger than the timeouts classified —
  distinct from a pass (0) and a red (1); `run_tests.sh` stamps the concurrent xcodebuild count,
  counted the same way the collision guard counts, so the verdict is checkable against the
  condition that produced it. Lowering the cap was rejected on the record: three is CLAUDE.md's number and the
  orchestrator's to set, a lock inside the script would serialize agents invisibly, and it would
  still not classify what got through. `Tools/test_harness_guards.sh` is the calibration — 37
  checks, each paired with its control, no simulator and no network.
  **Left open, deliberately: the exit-code taxonomy is half-applied.** (d) invents "the
  environment refused this run = exit 2", and this round's own most environment-shaped refusals —
  a `bootstatus` that did not return inside the bound, another run's leftover `bootstatus`, a
  collision with somebody else's build — all still exit 1 and get filed as reds. They are facts
  about the machine, which is the distinction exit 2 exists to draw. Not widened here on purpose:
  expanding a brand-new taxonomy inside the review that is judging it is how it ships applied to
  some of its cases and not others. A round that can weigh it should decide whether the three
  refusals move to 2 — and what that does to every caller that reads a nonzero as a red.
- ~~**The Activity list shows Photos / Check-ins / Care rows but no Visits row**~~
  **ANSWERED BY THE SPEC, 2026-09-09 — nothing to fix.** The observation was filed against "screen
  14"; the screen it describes is **13 · Tree activity** (§14 is the cold-start profile, which has
  no activity feed at all). `docs/distilled/SCREENS.md` §"13 · Tree activity" says "Three series"
  and tables them exhaustively — Photos, Check-ins and Care, each with its swatch, its total and
  its twelve bar heights. Visits are a distinct record kind and no Visits row is specified, so the
  screen is conformant and constraint 21 never engaged: the feel check read a correct screen as a
  gap. The spec does not say *why* visits are absent, and this entry does not guess. Recorded
  rather than deleted so the next person to notice the absence finds the answer.
- **Flake-watch sightings from the campaign** (all cleared by evidence, kept for the aggregate):
  `CityDownloadTests.swift:504` time-limit (60 s trait, 109 s under load; run 33586187828 — fourth
  in the family chip 4 tracks); `DeepLinkSweepTests` a11y check stalled 1,043 s under three
  concurrent builds (#145 review, solo re-run green); `PrimaryCTAReachabilityTests.testReportCTA`
  AX5 miss on main run 33676401718, red-then-green on a **byte-identical tree** (the PR run had
  passed the same tree minutes earlier); three `MapSearchTests` `TestWait.ceiling` timeouts on
  #149's first CI (E222 liveness bound, re-run green);
  `MapFilterAccessibilityTests.testTurningAChipOnIsAnnouncedInBothChannels` red only on a stale
  merge ref that no longer exists (run 33663399211, green on the true merged tree).

### Owner backlog additions, 2026-08-28

Three items queued by the owner, recorded verbatim in intent; none is scheduled yet.

- **A tree's photos through the seasons.** A screen showing one tree's photographs as a grid,
  browsable by season or by year, with a toggle between only this device's photos and all photos.
  No mock exists — the round that builds it starts as a design round under DECISIONS constraint 21
  (screen and states proposed to the owner before code), and its all-photos half must respect the
  photo-visibility rules (D11 privacy defaults, R82 hero provenance).
- ~~**Journal: stats for a chosen neighborhood, and a chosen city.**~~ **SHIPPED**
  (`feat/stats-picker`). Both segments carry a picker over the **live** inventories — the bundled
  seed plus every downloaded pack, R84 decision 1's union — which is the answer to "which
  inventories a non-local pick may draw from". Supersedes R84 **D4** for the Journal: the
  nearest-tree resolution is still the default and is now one of two states rather than the only
  one. The design decisions taken under DECISIONS constraint 21 are in
  **RULINGS R85** and are **awaiting the owner's ratification**.
- **Update the repo README.** The README predates most of what shipped; bring it current with the
  app as it stands (cumulative inventories, the publish pipeline, the beta process).

### Chip backlog (this file is the only queue — session chips are banned)

Follow-up tasks used to be surfaced as one-click session chips; several disappeared from the
pending list without being run, and the work was lost until re-logged here. The owner ruled on
2026-09-01: no session chips in this project — a follow-up that deserves its own task is written
into this section in the round that finds it, and nowhere else. Each item stands alone.

1. **Close the citation guards' blind spots.** The guard that keeps code comments from
   citing pending errata/rulings filenames has known gaps in what it scans; enumerate the blind
   spots and cover them, with a planted-citation calibration per shape. **Two were exercised for
   real by the 2026-09-09 splice and are the starting set**: `DocumentCitationGuardTests` only
   checks a citation that carries at least one `/`, so five **bare-filename** citations
   (`` `s17-region-generation.md` ``) survived into `RULINGS.md` as danglers and no guard saw them;
   and `PendingCitationGuardTests`' roots are the three Swift targets, so `server/*.go` and
   `Tools/*.py` are unscanned — a `server/internal/store/photos.go` comment deferring to
   `docs/errata-pending/` sat there through the whole photo round. Both were found by an adversarial
   reviewer sweeping basenames, which is the cheap check: **a splice-time sweep for the deleted
   files' basenames across the whole tree would have caught all five for free**, and is worth
   building into the splice protocol rather than only into the guards.
2. **Rebuild `Tools/ui-test-shards.txt` from live CI data.** The shard assignments have drifted
   from the suites' actual durations (shard runtimes are visibly unbalanced in recent runs);
   regenerate from measured per-class times and re-prove `UITestShardCoverageTests` still covers
   every class.
3. **Fix `Tools/fetch_seed.sh`'s silent scope-check death under `pipefail`.** A failure inside the
   scope-check pipeline can kill the script without a diagnostic; make every exit path name itself,
   with a calibrated failure case. **Written, and deliberately not merged with the rest of the
   harness round.** `Tools/fetch_seed.sh` runs in every CI job (`.github/actions/prepare`, the
   `release` job included) and places the seed the app bundles, so it is a genuine build input:
   merging it mints a TestFlight build. The fix and its two calibrations sit on
   `tools/fetch-seed-diagnostics`, to land in a round that is shipping a build anyway.
4. ~~**Redesign `CityDownloadsFeedbackTests`' perf-margin test.** The "transfer beats a per-byte
   walk by an order of magnitude" test (`CityDownloadsFeedbackTests.swift:920`-era) compares two
   wall-clock timings with a hard margin and flaked on CI with no concurrent load (8.5x against a
   10x threshold, 2026-08-23). PR #123's fix round narrowed a sibling window the same way and the
   review flagged the class again — rebuild these guards load-independent (count work, or assert
   the mechanism), keeping the regression they guard: a per-byte walk reappearing must fail.~~
   **SHIPPED** (`test/perf-margin-redesign`). A third flake — run 33430972054, the build-65 main
   run, `elapsed × 6 = 37.698` against an `11.744` control — closed the argument. The guard now
   counts the path's work through `CityTransferCensus` instead of racing it: the transfer must hand
   over a finished **file** (so the response cannot be a byte stream this app consumes), and the
   app's own reads over the payload must average at least 64 KiB (so the verification cannot walk
   it a byte at a time). A marginal-rate test pins the slope at two payload sizes, and a source gate
   over `Data/Cities/` refuses the byte-stream API outright. No clock is read anywhere. The census's
   own blind spot — `FileManager` work, which is `moveItem` today and reads no bytes — is written
   down beside the assertions.
5. **Harden `MapPanTabSwitchUITests` against slow runners.** Six CI sightings by 2026-09-01
   (fourth: run 33208371211; fifth: run 33352801695, PR #132; sixth: run 33469599808, the
   post-build-68 main run — each on code a rerun then passed byte-identical), always the same
   shape: the probe records `panBegan=3 panEnded=3` yet the test ends on "Centered on you". The
   fifth and sixth probe lines are recorded verbatim in E250's pending amendment
   (the amendment inside **ERRATA E250**) — near-identical to
   each other and to the first instrumented occurrence, with `settles=3` against the red-proof's
   no-pan baseline of 2; the rework starts from those three lines, not from the failure
   sentence. Rework the test's gesture (or its precondition) so a delivered-but-unregistered pan
   retries or fails as an environment refusal rather than a red; keep the regression it guards
   (a deliberate pan surviving a tab switch must still fail if the camera resets).
6. **Sweep `library.stagingURL`'s lifecycle for leaks** (chip still pending as of this note). The
   #123 reviewer left it deliberately unfiled: can a process death, failed verification, cancelled
   transfer, or refused install leave orphans in the staging directory, and does anything clean
   them? Happy path verified empty on device; the sweep is every unhappy path, pinned with
   red-proved tests.
7. ~~**Make `CYPRESS_SHOT_DIR` reachable for UI tests, or correct the instructions.** The unit-side
   shot suites (`ScreenSweepShots`, `DynamicTypeScreenshotTests`) provably honor the variable
   when `TEST_RUNNER_CYPRESS_SHOT_DIR` is **exported** before `Tools/run_tests.sh` — several
   errata carry the receipts. The UI-test files (`AreaPickerUITests.swift:13`,
   `AlmanacGroupTapTests.swift:14`) instruct passing it "on the `xcodebuild` command line", and
   that spelling silently did nothing in the 2026-08-31 picker round: the shots landed in
   `NSTemporaryDirectory()` inside the simulator container, and the round fell back to reading
   the `CYPRESS-SHOT:` paths the tests print into the captured log (which works, and is the
   interim instruction). Find the spelling that actually reaches a UI-test runner's environment,
   prove it both ways (set → shot lands in the chosen directory; unset → falls back), and fix
   the doc comments in all the files that state the convention (the two UI-test files, plus the
   cross-references in `ScreenSweepShots.swift`, `DynamicTypeScreenshotTests.swift`,
   `DebugDeepLink.swift`). A confident doc comment asserting an unverified invariant is this
   repo's signature bug shape.~~
   **SHIPPED, and the answer is that the variable was always reachable** — the exported spelling
   the unit side uses reaches a UI-test runner too, because `xcodebuild` forwards a
   `TEST_RUNNER_`-prefixed **environment** variable to whichever process hosts the test bundle,
   which is the app under test for `CypressTests` and the XCTRunner app for `CypressUITests`. What
   never worked is the *argument* spelling those two files prescribed: written after the script's
   own arguments it is a build-setting override and reaches no process at all. Three runs on
   iPhone 16e (`3A1F212D`) on 2026-09-09, one `-only-testing` UI test each, each against a
   directory listed empty first: exported → the PNG in the chosen directory; unset → the runner's
   own container tmp; argument → the same container tmp and the chosen directory still empty.
   Receipts in `docs/errata-pending/shot-dir-runner-forwarding.md`. The convention is now argued
   once, in `Tools/run_tests.sh`'s header, and the four files that stated it point there (a fifth,
   `DebugDeepLink.swift`, named the key only as a naming example and now separates key from
   channel); `CypressTests/ShotDirectoryConventionTests` keeps the key the writers read and the
   name the prose tells an operator to export from drifting apart.

   **Two gaps this left open, both deliberate, both unguarded — read them before touching these
   files again.**
   (a) *The original defect has no regression guard.* `ShotDirectoryConventionTests` pins the key
   and the forwarded name, not the prose that says how to set the variable, because a gate matching
   "command line" would go green on the same false instruction reworded — the worst shape a guard
   takes here. #152's reviewer confirmed it by planting a fresh false instruction that avoids the
   phrase entirely ("hand `TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` to xcodebuild after the script's own
   arguments") and watching all three tests pass. The decision stands; what is filed here is that
   the exact class of defect this round cured can recur silently, so a *reader* is the only check.
   (b) *The gate does not sweep `docs/`.* It reads `Cypress/`, `CypressTests/`, `CypressUITests/`
   and `Tools/run_tests.sh`. That is why `docs/ERRATA.md` carried the unprefixed spelling in its own
   reproduction instructions until #152's review found it by hand (corrected in place there, not
   renumbered). Widening the sweep to `docs/` is the obvious move and was not taken in that round:
   the errata shelf discusses these names as text far more often than it instructs them, so the
   gate would need a notion of "instructing" it does not have — which is gap (a), one directory
   over.
8. **Make `DebugDeepLink.fullyMeasured` pick a tree that device state cannot move.** Raised by
   PR #154's adversarial review; it is the half of that finding the PR did **not** close. (What it
   did close: withdrawing the seeded reading made `debugSeedMeasurement` throw `notFound` on that
   container for good, so `AddReadingReachabilityTests` failed on that simulator ever after.) The
   case pins `candidates[candidates.count * 5 / 8]`, and `fullyMeasuredTree`'s comment says
   `candidates` "keeps the seed's own length and ordering whatever this device has been through".
   That is true of the thing it was written against — status overrides, applied with a `map` — and
   **not true in general**: `LocalAPI.treesNear` merges locally added community trees into the seed
   rows, re-sorts by distance and truncates to `limit`, so one community add inside the 3 km radius
   changes `count`, shifts the 5/8 index, and silently re-points the case at a different record.
   Nothing fails loudly when it does — the harness seeds two readings onto whichever tree it lands
   on, so the failure surfaces somewhere else, on a tree nobody chose. Pick an identity local
   writes cannot move (the record's own id, or an index into a set no device write can enlarge),
   correct the comment to say what it actually survives, and red-prove it by adding a community
   tree inside the radius before the case resolves.

8. **Serialise a reading against its own withdrawal across two concurrent drains** (top server
   item). PR #156's arrival-order guard closes the withdrawal-committed-in-an-earlier-drain
   ordering and **only** that one; two `Apply` transactions overlapping in time are still mutually
   blind. Mechanism: `Apply` runs at READ COMMITTED (`Store.Tx` calls `pool.Begin` with no
   `TxOptions`, so the isolation is the server's default) and there is no unique key on the reading
   id — the two indexes `004_measurement_withdrawal_kind.sql` adds are plain — so nothing makes two
   transactions about one reading block each other. #156's reviewer built the interleaving against
   the branch's own store functions and it reproduced: `withdrawMeasurement` sees `matched == 0`
   and answers `applied`, `measurementWasWithdrawn` sees no committed withdrawal and the reading is
   born live, both commit, `live=1` — ERRATA E280's sentence ("a service reporting a removal it did
   not perform") at millisecond scale, reachable in the multi-device case
   `Mutation.WithdrawnMeasurementID`'s comment invokes. Not a regression: before #156 the kind was
   refused outright. **Suggested direction, explicitly unverified** — a transaction-scoped advisory
   lock keyed on the reading id (`pg_advisory_xact_lock(hashtextextended(upper($1), 0))`) taken at
   the top of **both** `withdrawMeasurement` and `measurementWasWithdrawn`, which serialises only
   same-reading pairs. Nobody has built or red-proved that shape; treat it as a direction, not a
   recipe, and red-prove the race itself first so the fix has a witness. `server/` has no CI, so
   whatever lands here needs its own throwaway-Postgres run with stated pass/skip/fail counts.
9. **Decide what a signed-out phone can take back — the shared ownership rule costs more for
   readings than for photographs.** Signed out on the same phone, withdrawing a reading belonging
   to that phone's own account comes back `forbidden`, non-retryable, and screen 17 gives the user
   no way to clear the red row. This is not a `measurement_withdrawal` defect: #156's reviewer
   compared the ownership rules to `photo_withdrawal`'s line by line and they are **identical**
   (`user_id` match OR `device_id` match; anonymised rows owned by nobody and therefore refused),
   because `ClaimDevice` moves a contribution's `device_id` to a `user_id` and nothing server-side
   remembers which installation recorded it — the client's own gate has an installation arm and
   this one cannot. So the divergence is `withdrawMeasurement`'s documented one, hit through a
   second kind. Readings are recorded far more often than photographs, which is why the shared
   rule's user-visible cost lands here first. Two halves to answer: whether the service should gain
   an installation arm at all, and — independently — what screen 17 offers for a permanent
   non-retryable failure on a mutation the phone has already applied locally.
10. **Answer what a withdrawn-to-empty tree should look like, before `GET /me/journal` goes
    remote.** Withdrawing the only reading on a tree leaves that tree in `GET /me/grove` with all
    four tallies zero and in `GET /me/map-membership?kind=yours`, and the `measurement_withdrawal`
    contribution row itself surfaces as a journal entry. Measured by #156's reviewer
    (`treeInGrove=true counted=0`, the tree id still in `yours`, a `measurement_withdrawal` item in
    the journal response). The cause is that the withdrawal's own row is live and no reader filters
    on kind, so it keeps the tree in `Grove`'s `mine` CTE and in `MapMembership`. Identical to
    `photo_withdrawal` today and **nothing is tester-visible**, because `RoutedAPI` routes the
    journal local — which is exactly why it needs answering on a schedule rather than on a bug
    report. Check against PR #154 what a `measurement_withdrawal` journal row renders as when the
    journal goes remote, and decide whether an emptied tree should leave the grove and the `yours`
    filter or stay with zeroes.
11. **Prose pass over `server/README.md`'s Deploy section — it is stale in a way that reads as a
    blocker.** It still says the `cypress-sync` machine "needs secrets and a Postgres that do not
    exist yet". Both #156's author and its reviewer checked: `fly secrets list --app cypress-sync`
    returns sixteen secrets, all `Deployed`, including `DATABASE_URL`, `SESSION_SIGNING_KEY`,
    `OPERATOR_TOKEN`, the three `APPLE_*` and the five `PHOTOS_*`. While that section is open, the
    neighbouring facts worth stating correctly: the app is at release v7 with its machine
    auto-stopped (`min_machines_running = 0`), nothing in `.github/workflows/` touches `server/` or
    Fly, and so a migration only runs at the next boot of a **redeployed** image — merging server
    work changes nothing in production. Prose only; no code.
12. **`GET /api/v1/trees/{id}` publishes two per-tree counts of user actions to any signed-in
    caller, and nobody has ever tested that against D1.** Found by W-G while ruling on what the
    *public* read may say, so it is filed rather than fixed — the shipped route is not this round's
    to change. `treeProfile` returns `photo_count` and `visit_count` for **any** tree to **any**
    authenticated caller, which is cross-user rather than private: it is not the E87 case (that
    count was "not public — the rows exist on one phone and are attributed to nobody"), and it is
    not obviously the F16 case either, because the noun is a tree. R27.1 is the ruling that decides
    it — *"trees may be ranked; people may not"* — and under R27.1 §2 a per-tree count of somebody's
    acts still wants the ≥3-distinct-people floor, because at one contributor the number is one
    person's activity at a fixed location and at two it is inferable to the other. R27.1 §5 says
    photograph counts specifically are not wanted. **What to do is a ruling, not a patch**: decide
    whether these two counts stay, gain a floor, or go, and check what the client draws from them
    before removing anything. `visit_count` is `TreeCommunityHalf`'s second query;
    `photo_count` is `len(photos)` after the visibility filter, and screen 15's promise may rest on
    one of them.
13. **`server/` has no CI, and this round added twenty-three tests to a suite nothing runs.** The
    proposal's §7 records the gap; W-A's `web.yml` is for `web/`, not for this. A `server.yml` on
    `ubuntu-latest` with a `postgres:16` service container and `CYPRESS_TEST_DATABASE_URL` set would
    run the whole suite in about a minute, and — this is the part that matters here — it must
    **assert the skip count is zero**, because `go test ./...` prints `ok` per package and exits 0
    with every SQL test skipped. ~~Measured 2026-09-10: 60 pass / 108 skip with no database, 191 pass
    / 0 skip with one.~~ **Those no-database numbers were the baseline tree's, mislabelled**; at
    W-G's head after its review fixes, it is **67 pass / 131 skip / 0 fail** with no database and
    **198 pass / 0 skip / 0 fail** with one (66 / 125 and 191 / 0 at the PR head before them). `testflight.yml` already excludes `server/`
    from the archive, so a server-only workflow cannot mint a build.

14. **One tree, one current height: should the method count?** Nothing in this corpus rules on
    whether an estimate may supersede a measurement when a single number has to be chosen. D7,
    DECISIONS constraint 2, ARCHITECTURE §5 rule 3 and PRODUCT's non-goal (*"Never share a chart
    line"*) are all rules about a **chart line**, and E103 extends them to a spoken summary; none is
    about which number is current. The client picks the most recent regardless of method in three
    places — `TreeProfilePresentation.latestMeasurement` (`Cypress/Features/TreeProfile/
    TreeProfilePresentation.swift:1189`), `MeasureModel.previousMeasurement` (a verbatim second copy
    of it) and `GrowthHistoryPresentation.chart(for:)`, which re-merges both series for its newest
    and oldest labels — so a 90 cm estimate displaces a 64 cm taped reading on screen 03 today.
    W-G's public read matches that deliberately rather than authoring a fourth answer, and pins it
    in `TestANewerEstimateSupersedesAnOlderTapedReading`. **Answer it once, for all four sites**, and
    note the two duplicated copies of the selection rule are their own small cleanup. Found by the
    adversarial review of #163, which found the code claiming the opposite in a comment.

15. **`clientKey` trusts a request-supplied header, on a route that now has no credential.**
    `internal/api/server.go` returns `Fly-Client-IP` when the request supplies one, and the only
    thing making that trustworthy is Fly's proxy overwriting it. The review measured it: after
    exhausting a bucket, 25 of 25 requests carrying a self-chosen `Fly-Client-IP` were served, each
    allocating its own bucket. Pre-existing and not a live exploit — but until W-G every route behind
    it also required a credential, and `GET /public/trees/{id}` requires none. W-G narrowed it (a
    value that is not an IP is not used as a key; `ratelimit.maxBuckets` bounds the map) and
    deliberately did **not** fix it: the fix is to stop honoring the header unless the connection
    came from the proxy, which is a trust-boundary change nothing in that round could verify against
    a request it watched arrive. **It is moot if the answer to the ruling's Q4 is "SSR-only"**, so
    do them together: decide Q4 first, and if the endpoint stays internet-facing, make the trust
    explicit and prove it against a real Fly request rather than from documentation.
16. **A `/* … */` decoy after the real declaration defeats the migration-file kind extractor.**
    Raised by the delta review of PR #163. `contributionKindsFromMigrations` strips only lines that
    *begin* with `--`, so a migration whose real `ADD CONSTRAINT` is followed by a block-commented
    older draft yields the **draft's** vocabulary — measured as `[visit never_a_kind]` where the
    answer is `[visit the_real_answer]`. Not a hole today: `TestTheLiveSchemaAgreesWithTheMigrationFiles`
    catches it loudly, because the live schema and the file reader stop agreeing. But
    `TestContributionKindExtractorIsCalibrated`'s specimens cover only `--` prose, so the shape is
    untested, and the round that fixes it should add a `/* … */` specimen rather than only the strip.
17. **Delete `kindsAwaitingTheirMigration` when PR #159's `005_data_dispute_kinds.sql` lands.**
    PR #163 classifies `data_dispute` and `data_dispute_withdrawal` before their migration exists,
    so neither PR's merge order breaks the other's guard. The map in `server/internal/api/public.go`
    exempts them from "a classified kind must be a declared kind" until 005 arrives. It cannot hide
    an unclassified kind — the safety-critical direction never reads it — so its expiry is a
    **`t.Logf`, not a failure**, deliberately: failing would trade one red-on-main for another.
    That is why this item exists rather than a test. One deletion, two entries, in the round that
    merges 005 or the one after it.
18. **Measure the real distribution of favorites per tree, and set the beloved floor from it.**
    R27.1 asks for it in as many words — *"count it, do not guess it"* — and PR #163 shipped
    R27.1's inherited ≥3 because the attempt to read the production distribution was refused before
    a query ran. The floor may be raised by a measuring round and may not be lowered. Pair it with
    the observation that since the 2026-09-10 ruling only **account-backed** favorites count, so the
    distribution to measure is over `favorites.user_id`, not over all owners — and the answer may
    well be that no tree in the beta reaches any floor at all, which is a finding rather than a
    failure.


**Retire the format-1 manifest — DONE, 2026-08-23.** The owner overrode the trigger the day after
setting it: rather than firing at the publish *after* New York, format 1 retired immediately. Full
reasoning, and what it supersedes, in **RULINGS R99**.

`Tools/publish_cities.py` no longer writes `manifest.json` and `dist/upload.sh` no longer uploads
or verifies it, so the NYC publish of 2026-08-23 is the last format-1 object there will ever be.
**The published object is frozen, not deleted** — it still names two immutable city packs that are
still served (checked anonymously, with a 404 control), so an install that never updated past build
47 keeps a working Cities screen and simply stops receiving anything newer.

Two departures from the enumeration this entry previously carried, both deliberate:
`CityDownloader.fetchManifest`'s fallback to the legacy name is **kept** rather than removed — its
remaining job is any base URL that is not the live bucket (an archived mirror, a fixture directory),
and every shipped build 48–55 has it compiled in regardless. And the publisher gained a guard it did
not have: it refuses a `--out` still holding a format-1 manifest from a dual-publish round, because
`--out` only clears `cities/` and that leftover file is the one artifact an operator could upload
over the frozen object. **`CityManifest.knownFormats` keeps `1`**, as previously planned — what
retired is writing a format-1 manifest, never reading one.

**City-inventory disputes.** Owner ruling, 2026-08-21, refined the same day (both in RULINGS
**R79**, which carries the full spec): city data must be
disputable from the UI, and city-tree disputes are richer than the community-tree flags. City
trees: checkboxes for nature of issue (pin in wrong location; wrong species; wrong other metadata
— e.g. a clearly wrong planted year, or a recorded tree whose plot is empty), suggested values,
and a notes field; plus a missing-tree defect for a tree that is on city property but absent from
the city database, whose entry point cannot be a tree profile. Flagged trees get a small badge
showing their flags, and the filters box gains a "trees with data issues" filter. Community trees:
location and species disputes only — and the existing community flagging view is itself not
quality (owner, same day: bad copy throughout, and a flag cannot be retracted by its author),
so the round gives community flagging a detailed design pass with owner decision rounds rather
than inheriting the shipped flow. Disputes are stored app-side in the writable database; the
city inventory stays read-only, and sync-back to the city is explicitly deferred. Reverses the
"community rows only" deferral in `SpeciesClaim.swift`'s header. Needs the writable-schema
migration seat after the §3.4 round's. Sequenced after §3.4 lands; exact slot at scheduling.

**Copy audit: remove demo-era narrative holdovers.** Owner instruction, 2026-08-21: every piece of
user-facing copy gets screened for usefulness and appropriateness. Lines narrating the app to
itself — "This is that almanac's 'walk the nine' list, one tree at a time" (screen 14) and its
kin — are holdovers from a demo-era voice and come out. The audit enumerates every candidate line
with its screen and source location, then brings them to the owner as batched decision rounds
(copy on mock-specified screens is constraint-21 territory); nothing is reworded silently. Not
scheduled.

**Seed inventory expansion beyond NYC.** Owner requests, 2026-08-21: add street trees to the data
seed for **Oakland and Los Angeles**, and then also **Dallas, Phoenix, Philadelphia, San Antonio,
San Diego, Jacksonville, Austin, Charlotte, Columbus, Seattle, Denver, and Nashville**. Each city
is the NYC shape again — source the inventory, read its license, ingest, validate species
coverage, cut packs — and the s17 region dimension is the prerequisite, so all of it queues behind
NYC's first publish. Whether each city publishes an open street-tree inventory at all, and under
what terms, is unresearched: the first step per city is the sourcing-and-license pass, and a city
with no usable inventory comes back to the owner as a finding, not a silent drop. A tester asked
for Marin/Sausalito/Mill Valley coverage the same day (RULINGS **R80**, the deferral "Coverage
outside San Francisco: Marin, Sausalito, Mill Valley", which reframes it as an inventory question
for the distribution plan); when this is scheduled, evaluate the whole list together against the
distribution plan's
per-inventory machinery rather than one city at a time. Not scheduled.

**iNaturalist licensing.** Content is CC BY-NC and Cypress has a paid organizational tier. We store
aggregate integers, which is defensible, but it is a position rather than a permission. The
dependency is kept removable: dropping it costs 11 bloom arrays, 8 fruit arrays and one fall-color
array, and should remain a configuration change rather than a refactor. **Needs a human answer
before launch, not before the next screen.**

**The vitality rubric.** The source documents themselves flag this as the highest-value unresolved
question. Screen 05 is built with rubric text as data specifically so that answering it later is a
content change.

**The MapKit road-color inversion.** The mock draws streets lighter than blocks; MapKit renders
roads darker and exposes no way to recolor them independently. `MapCanvas(basemap:overlay:)` is
kept as the seam for a vector basemap. Not scheduled — it is a real visual departure from the mock,
and worth doing only if the map's look is judged to matter more than the work.

**`assertEveryControlIsLabeled` asserts over a screen it does not own.** `DeepLinkHarness
.assertEveryControlIsLabeled` walks `app.buttons`, `app.staticTexts` and five more queries — *every
element in the app*, not the screen under test. Screens 09, 10 and 18 are presented over the map tab
root rather than pushed, so screen 01's MapKit annotations stay in the accessibility tree behind
them and are read as part of that screen's audit. `DeepLinkSweepTests.testNothingIsAnnouncedTwice`
does the same thing one query wider.

Everything that has gone wrong with this is a consequence of the scope, and each fix so far has
treated a consequence:

- an annotation whose frame XCUITest can resolve no activation point inside makes `isHittable`
  **raise** — fixed at the read (`XCUIElement.isHittableWithoutRaising`, `CypressUITests/UIWait.swift`);
- which annotations land in that state depends on where the camera was left — fixed at the state
  (`CYPRESS_MAP_CAMERA`, `Cypress/Features/Map/DebugMapCameraOverride.swift`);
- enumerating that many elements against a live tree is itself a race — an index that stopped
  resolving mid-walk failed CI three times with both of the above in place (indexes 25, 3 and 17,
  the last on a tree byte-identical to a passing run). Fixed at the binding for
  `testNothingIsAnnouncedTwice`: `allElementsBoundByAccessibilityElement` and one read of each
  value into a plain `(String, CGRect)`, so nothing re-resolves a proxy mid-comparison.
  `assertEveryControlIsLabeled` still walks by index and has not been seen to lose one. The reason
  is worth a clause rather than being left as luck: it makes one pass and re-resolves no ordinal
  *between two reads that have to agree with each other*, which is exactly the property
  `testNothingIsAnnouncedTwice`'s pair-wise comparison did not have. That is not immunity, only a
  smaller window — it still reads `.label` after `.exists`, and PR #66 measured on a device that the
  sibling pair `.exists` then `.frame` **raises** rather than answering when the query stops
  resolving in between.

**The scope itself is untouched, and it is the actual defect**: a labeling audit of screen 18 that
passes or fails on the contents of screen 01 is not an audit of screen 18. The shape of the repair is
to scope the walk to the presented screen's own subtree — but that changes what the helper *claims*,
and the claim is load-bearing: the helper's own comment records that it is scoped to what is hittable
"for the same reason E116's version is", and four files depend on it. It needs its own red-proof
(a genuinely unlabeled control on the screen under test must still be caught) and an argument about
what happens to the elements that stop being examined.

Not scheduled, deliberately, and the reason is the size and shape of the work rather than the state
of any one run. The symptoms are each guarded — `HittabilityFilterGateTests`,
`ContainerSpellingGateTests`, `FrameFinitenessGateTests`, `DebugMapCameraOverrideTests` — so what is
left is a question about what the helper *claims* to examine, which no failure will report. The full
history is in the errata entry for the hittability round.

*This paragraph used to open "The suite is green", and that is why it does not now.* It was false at
the head it was written on — CI run 31347748098 had `ui (3)` red on the very repair the third bullet
above describes — and a decision not to schedule work should not rest on a sentence that has to be
re-checked every time the tree moves. Two of the gates named here were widened on PR #66 after a
reviewer red-proved that `if x.isHittable` and `descendants(matching: .scrollView)` walked straight
past them, which is the other half of the same lesson: "guarded" is a claim about an instrument, and
an instrument has a calibration.

**Five UI test classes still inherit the opening camera, and still write one.** PR #66 gave the
tests a way to pin screen 01's opening camera (`CYPRESS_MAP_CAMERA`) and applied it to four launch
helpers: `DeepLinkHarness.launch`, `DeepLinkOverrideReset`, `PrimaryCTAReachabilityTests
.launchAtAX5` and `IdentifyFABReachabilityTests.launchAtAX5Denied`. `AccessibilityTreeTests`,
`MapFilterAccessibilityTests`, `MapRecenterUITests`, `MapPanTabSwitchUITests` and
`AlmanacGroupTapTests` were deliberately left alone, and they still open on whatever the previous
launch left in `map.lastCamera` — and still write one on the way out, which is what the next
unpinned class inherits.

That is a gap the harness cannot close on its own: `Tools/run_tests.sh` normalizes the stored camera
**once, before `xcodebuild` starts**, and can say nothing about what the twentieth launch inside a
run inherits from the nineteenth.

Three sightings so far, none of them reproduced, all in unpinned classes:

- `AlmanacGroupTapTests.testWalkTheNineOpensAMapOfThemAll` — one CI failure on `94b1d81`, green on
  the next run.
- `MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` — timed out waiting on
  the recenter control through three retries on a local merged-tree run.
- `MapPanTabSwitchUITests.testAnUntouchedCameraStillCentersOnTheReaderAfterTheRoundTrip` — a cascade
  from the previous one, the app wedged and would not terminate.

**The second and third are not attributable, and that matters more than the count.** That run took
3,289 s against a normal ~1,580, `run_tests.sh` had already refused one launch on a competing
`xcodebuild`, and CI then passed the byte-identical tree on the shard carrying that class. So those
two are at least as likely to be the simulator degradation CLAUDE.md describes as anything about the
camera. They are recorded here because the class is unpinned, not because the camera was shown to be
the cause.

The work is not "pin the other five" — `MapPanTabSwitchUITests` deliberately pans and
`AlmanacGroupTapTests` pins its own location fix, so a pin could quietly change what either one
asserts. It is to decide, per class, whether the camera it opens on is something the test means to
control, and to give the ones that do the seam that already exists.

*(The "structural VoiceOver is not machine-checked" entry that stood here is resolved. `CypressUITests`
is a black-box XCUITest target (E116), and `DebugDeepLink`'s `CYPRESS_SCREEN` environment variable
opens any screen for it (E117), so fifteen structural tests now read the accessibility tree of the map
plus fourteen screens behind it. Every one of the 188 interactive elements found was labeled; the
suite additionally pins that no modal leaks the screen behind it to assistive technology, and that
every pushed screen has a reachable Back. **Screen 19 remains unread, and the reason is the data**: the
seed holds only `alive` and `vacant_site`, so no `removed` tree exists to open a memorial with, and
faking one would be the exact class of lie the suite exists to catch. **Reading order and grouping
have partial coverage now (task #221).** `ReadingOrderAccessibilityTests` asserts composition order
on six screens chosen because a wrong order there is a real usability failure: the map's field →
suggestions → filter chips, screen 05's five vitality rows in rubric order (worst to best, never
phrasing-dependent), screen 03's identity block before the primary CTA before the secondary quad
actions, and — added since — the three screens that WRITE: screen 06's two chip vocabularies each
kept under its own heading (the boundary E131 rests on), screen 16's kind and method controls before
the keypad before `Save measurement`, and screen 09's four care toggles before the optional
photo/note well before `Done`. `testAStatCardIsOneStop` (E118) already asserted the narrower
grouping claim — a caption and its value arrive as one stop. **What this does not close**: several
screens' order is still unasserted, and three were examined and deliberately left out because their
order is a property of seed or device state rather than of the code (11 growth history and 13
activity resolve to trees with no rows at all; 17 outbox reads a device-local queue). **The
`accessibilitySortPriority` question is settled for one whole class of API, in the negative and for
a structural reason**: not only `debugDescription` but the query engine under both binding
strategies, the snapshot's own `children` arrays and `.children(matching:)` all report raw
view-composition order — a purely geometric inversion of two elements moves none of them. Those five
are *traversals of one `XCUIElementSnapshot`*, not five independent instruments, and that is exactly
why the result generalises the way it does: **no traversal of that snapshot can observe a sort
priority**, so reaching for a sixth traversal is not worth anyone's time. **What is NOT closed** —
this sentence over-claimed it before PR #54's review — is focus-driven or
assistive-technology-driven order, a different mechanism that does not read the snapshot at all.
That reviewer tried a focus-engine probe (`typeKey(.tab)` then a `hasFocus` sweep) and got no
element reporting focus on a simulator without Full Keyboard Access: **no counterexample and no
working probe — untried, not refuted**, and the place for the next attempt to start. See ERRATA
**E230** and its amendment. What replaces the search is `CypressTests/MapSwipeOrderDeclarationTests`, which
pins that screen 01's declared priorities descend in the same order the block composes its children,
since that agreement is what makes a composition-order assertion mean anything at all. Verifying the
mechanism itself on the glass is still a physical-phone VoiceOver pass — the debt E192 recorded, and
unchanged.)

*(The "Two contrast pairs are still failing" entry that stood here is resolved. E120 fixed the C10 locked glyph via lightness-only OKLCh (3.06:1/3.05:1), and E122 fixed the C23 chart series via the same method — chartSeriesPrimary 2.53→3.05, chartSeriesTertiary 2.27→3.06, both moved from `knownFailures` to `retinted`.)*

*(The "no test target" entry that stood here is resolved: `CypressTests` is a hosted swift-testing
bundle and has been since M2. It found two shipped bugs on the day it was wired.)*
