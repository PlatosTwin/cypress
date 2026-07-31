# Cypress — distilled decisions, risks, constraints

Sources: ADVERSARIAL-REVIEW.md (D1–D15, round-2 five-reviewer panel), CRITIQUES.md (v1 four-persona critique). Resolution status cross-checked against DESIGN.md v3 and BUILD-PLAN.md. **D16 has a different provenance from the rest — it is the owner's own answer, given directly, and it settles what the other fifteen assumed.**
Document precedence when they disagree: BUILD-PLAN.md > SPEC-PHASE1.md > DESIGN.md. D-numbers are binding.

## 1. Binding decisions (D1–D16)

- **D1 — Kill the leaderboard.** Screen 12 becomes the Neighborhood almanac: non-ranked, no counts attached to countable actions (first bloom sightings, oldest tree, species mix, coverage panel: young trees unvisited since planting, blocks unseen for months). Coverage gaps are the only directed ask in the app. *Reason: every ranked metric is farmable in under 30 seconds, farmed check-ins are indistinguishable from honest ones forever, and ranking contradicted DESIGN.md's own "no streaks or leaderboards."*
- **D2 — Screen 13 gets honest.** Keep small multiples; cut the favorites series; the three remaining charts share one scale; trivia tiles become a moments list ("first spring flush noted", "watered through the dry weeks", "six people know this tree"). *Reason: unscaled small multiples made a 41-photo series and a 9-care series look identical, and favorites-per-month is nonsense for a one-time toggle.*
- **D3 — Vitality selector becomes five full-width anchored rows**, each with a reference photo, the label, and the anchor sentence always visible; color is secondary coding. *Reason: five flat paint chips are indistinguishable in sun glare and for ~8% of male volunteers with CVD, and the rubric's reference photos were absent at rating time.*
- **D4 — Hazard reporting is redirect-only.** The public community-note option disappears for hazard categories; after the 311 handoff only a private reminder on your own record remains, never public, never auto-staled. Non-safety note categories move to a wrapped grid, visually separated. *Reason: a public "hanging limb, the city has not been notified" note that auto-deletes on a 90-day timer is a discoverable liability record no city will tolerate.*
- **D5 — Phenology surfaces become species-aware.** Evergreens never show fall-color chips or autumn strip colors; the chip set is driven by a leaf-retention attribute on species. *Reason: the flagship Monterey Cypress (evergreen conifer) was showing "Fall color starting!"; spec section 6 species-awareness never reached the UI.*
- **D6 — Tree ID gets a confirmation step.** When candidates sit within GPS error of each other, show the two nearest with a distinguishing trait each and require a tap to confirm. Store per-contribution GPS accuracy; exclude low-accuracy contributions from growth charting. *Reason: urban-canyon GPS degrades to 20–50 m while street trees are 6–10 m apart, so misattribution to an append-only record is silent and permanent.*
- **D7 — Minimal measurement capture moves into Phase 1**: a measure sheet with a big keypad, mandatory unit and method chips, previous value shown for sanity checking. On charts, estimated and taped points render as separate series and are never connected. *Reason: screens 3 and 11 charted numbers no screen could enter, and one connecting line across estimated + taped values manufactures a trend that is not there.*
- **D8 — Mock five missing screens**: cold tree profile ("be the first to photograph this tree"), sign-in sheet with license consent and a decline path, measure sheet, outbox with per-item state and retry, post-check-in screen with "next nearest tree" and a visited-today map state. Remaining missing states are enumerated as build requirements in BUILD-PLAN.md §9. *Reason: the mock set depicted year three of a community that does not exist; the screen 100% of first users see was not in the set.*
- **D9 — Accounts come later in the funnel.** First saves are anonymous and local-first under a device ID, synced after account creation; the ask comes at the third save. *Reason: the signup wall landed the maximum-friction event (auth sheet + license consent checkbox) on second 8 of a ten-second street-corner visit.*
- **D10 — Phenology notifications move into Phase 1.** *Reason: they are the only mechanism that gives a tree a reason to summon a person back, and the species seasonal data they need is already in the schema.*
- **D11 — Privacy hardening.** Contribution feeds private by default with opt-in public attribution; adopter identity never public; age gate in onboarding; minors default to anonymous attribution. *Reason: public attributed visit timelines plus "adopted by you" reconstruct where a named person lives and stands, and volunteer programs include minors.*
- **D12 — The open export gets a `verification_state` stamp.** City inventory rows export clean; citizen observation rows carry a machine-readable unverified marker; the structured observation export holds until a verification tier ships. *Reason: a nightly open export of unverified citizen observations is exactly the pipe that has dumped garbage into real city inventories; UI provenance labels do not reach a downstream script.*
- **D13 — Invert the phases around the wedge.** The org steward loop (assignments, route view, batch check-in, coordinator export) moves from Phase 2 into a Phase 1.5 starting as soon as the walking skeleton stands, with one partner org; the enthusiast layer launches into a map already carrying fresh steward data. *Reason: the enthusiast layer needs thousands of users to feel alive; the steward loop works with ten.*
- **D14 — A revenue position exists.** Coordinator dashboard and org tooling are the paid tier at roughly $50–200 per org per month, priced for nonprofit budgets; consumer layer free forever; first pilot org free for a year in exchange for a case study. *Reason: there was no revenue line at all — a data-escrow exit clause existed before a pricing page; if no org will pay even that, learn it at design stage.*
- **D15 — BUILD-PLAN.md is the buildability contract**: field-level data model (incl. nicknames and their moderation), API contract, ingest spec with column mapping, sync/outbox design with an error taxonomy, species content pipeline, privacy spec, milestones with acceptance criteria, a test plan, and one-sentence resolutions for every listed ambiguity. *Reason: no API spec existed at all, ~15 load-bearing ambiguities and ~15 undefined entities meant mobile and web would invent different products.*
- **D16 — The destination is a merged national inventory, and nothing reaches a city until it exists.** *(Owner, 2026-07-31, answering the question three open tickets collapsed into.)* Every report in this app is a **community-review loop** — now and for the foreseeable future. No submission is routed to a municipal agency, no 311 ticket is filed, no city is notified. What a report reaches instead is the thing being built toward: **one database, available over an API, holding the latest tree information from around the country — every municipal inventory merged into a single normalized format, with community contributions layered on top of it.** So the merge target is the product, not a pipe to somebody else's work-order system. *Consequences that are binding, not commentary:* (a) §3 constraint 3 stands unchanged and is now permanent rather than provisional — no "sent to the city" copy without a real ticket id, which we will not have; (b) the honest empty state must say what a report *does* do (the community sees it and can confirm it), not merely what it does not, or it reads as a dead end — see E126; (c) the ingest contract (E169 / R18 / R20) is the spine of the product rather than a seed-building convenience, which is why identity is qualified by id space: two cities' numberings genuinely overlap and the merged table is the deliverable; (d) reaching the city is a later layer *over* this database, so design for it — but do not build copy, screens, or schema that presume it has arrived.

### Explicitly rejected proposals (do not re-open)

- Cutting the Report screen from Phase 1 — rejected; all five reviewers praised the honest 311 redirect. The actual liability was the hazard-note branch, removed by D4.
- Deleting screens 11 and 13 as depicting an impossible future — rejected; fixed at the source by D7 (real data source) plus the D8 cold profile.
- Mocking all sixteen missing screens — rejected; five mocked (D8), the rest specified as build requirements. "A mock set is an argument, not an inventory."
- iNaturalist-style validation status in Phase 1 — rejected; needs the competency/verification machinery that is genuinely Phase 2. Almanac + coverage quests carry the loop until then.

### Survived all five hostile reads — do not regress

- The provenance spine: method and unit metadata on every number, versioned species assertions, stable citable tree UUIDs, lifecycle states.
- Honest routing: "the city has not been notified" as an explicit mocked state; hazards hard-redirected to 311.
- The photo timeline with ghost overlay and season strip — the one artifact the official city app will never have. If the product pivots, it pivots around this.

## 2. Findings from CRITIQUES.md, by theme

Status key: RESOLVED (decided and specified) · PARTIAL (decided in principle, mechanism incomplete) · DEFERRED (accepted, scheduled later) · OPEN (no resolution recorded).

### 2.1 Onboarding friction and the ten-second visit

- E-C1 "The check-in is built around a health-inspection form, not around noticing a tree; a vitality rating is intimidating and I'd fear polluting the data. I'll do it twice and stop." — RESOLVED: Visit (photo + optional note, ≤10 s, zero judgment) split from the structured check-in; camera opens immediately.
- E-C2 "The center of gravity is data collection for cities; members are free sensors. Learn/discover/wonder/seasons/beauty barely appear." — RESOLVED: tree profile leads with story and season strip, stats demoted below the fold; Phase 1 success metric is weekly enthusiast return, not observation count.
- V-C3 "Six steps per tree × 20 trees is my whole morning; no time budget is stated." — RESOLVED: single scrollable card, big targets, "same as last visit" prefill, skip-anything, explicit 90-second-per-tree budget; M3 acceptance is a 10-tree morning in under 25 minutes.
- Investor: signup wall at second 8 — RESOLVED by D9 (anonymous device-local first saves, ask at third save).

### 2.2 Learning, discovery, retention

- E-C3 "Species ID — the thing I most want — is parked in Phase 3 as AI photo analysis, when seeded city data already gets you 90% there." — RESOLVED: "What tree is this?" GPS shortlist, mobile species pages, and ID tips on every profile are Phase 1; AI species suggestion pulled forward to Phase 2.
- E-M2 seasonal/phenology return triggers — RESOLVED, and escalated to Phase 1 by D10.
- E-M3 learning on every profile (ID tips with photos, what to look for this month, "5 more within 3 blocks") — RESOLVED for the curated ~100 species covering 90% of SF street trees; the long tail renders name, family, generic silhouette only. Constraint: no fabricated botany.
- E-M4 shareable tree card as growth loop — RESOLVED: public server-rendered tree pages, no login, share card with OpenGraph (photo-less variant uses the species reference image).
- E-M5 personal journal / walk view — DEFERRED to the enthusiast-polish milestone (M4), private by default.
- E-priority species collections pulled forward — PARTIAL: collections are in Phase 1 scope in DESIGN.md but land in M4; they must not become counts of user actions (D1).
- Investor: "nobody opens the app in month 3" — PARTIAL: D10 supplies the one recurring trigger; no evidence yet that it retains. OPEN risk.
- Investor: cold start is a map of gray rectangles; the seed fixes the empty map, nothing fixes the empty content — PARTIAL: commissioned/licensed species reference photos badged "reference photo" serve as fallback heroes; the D8 cold profile states the day-one truth. Residual risk accepted.

### 2.3 Field work, offline, org workflow

- V-C1 "No route, block, or workday; 'batch field surveys' is named in the roles table and never designed." — RESOLVED and promoted: assignments, route view, next-tree flow, group workday mode; D13 moves the loop into Phase 1.5. Group workday live claimed/done status and same-day dedupe remain Phase 2.
- V-C2 "Offline is Phase 2, so Phase 1 is unusable in the field; paper never fails to sync." — RESOLVED: SQLite outbox in Phase 1 with retry (30 s, 2 m, 10 m, 1 h, hourly; 48 h cap then a visible retry button), wifi-only applies to photo binaries only, screen 17 shows per-item state. Area tile download stays Phase 2.
- V-M1 assignments from my org — RESOLVED (Phase 1.5).
- V-M2 group workday mode — DEFERRED (Phase 2).
- V-M3 "did the basics" quick care log distinct from a health observation — RESOLVED: CareLog / care_event in the Phase 1 data model, ≤30 s.
- V-M4 "does my org lead get the data, or do I fill the spreadsheet again Monday?" — RESOLVED: coordinator dashboard, weekly digest, one-click CSV export — and this is the paid tier (D14).
- V-M5 young-tree-specific fields (stakes, ties, girdling, basin, mulch) front and center — DEFERRED: age-adaptive forms are specified but sit in the Phase 2 full structured observation.
- Designer: ten check-ins cost 5–6 taps of navigation each, no "next nearest", no visited-today pin state — RESOLVED by D8 (screen 18).
- Designer: spec demands 44 pt targets and a sun-readable palette while mocks ship sub-30 pt thumbnails and beige-on-cream chips — RESOLVED as a test-plan gate (design-system validator, dark mode).

### 2.4 City adoption, liability, routing

- C-C1 "The staff triage queue is a parallel work-order system and we will not adopt it; a duplicate inbox goes unwatched. Do not print 'routed to SF Public Works' without a contracted integration." — RESOLVED: routing before queue. Open311/GeoReport where available with the real ticket id echoed back; otherwise the explicit "the city has NOT been notified" state. The in-app triage queue exists only for onboarded departments.
- C-C2 "Hazard reports sitting in an app create liability with no owner: no SLA, no 2am answer, no disclaimer." — RESOLVED by D4 (redirect-only, private reminder, no public hazard note, no auto-staling).
- C-M1 311 / work-order integration as the primary triage path, two-way status sync — PARTIAL: Open311 is the standard rail, Cityworks/Cartegraph adapters only for onboarded departments; SF's practical rail may need an SF311 case-API adapter. OPEN per launch city.
- C-M2 duplicate-report clustering on care requests (30 reports on one hanging limb after a storm) — DEFERRED to Phase 2, with reporter notification on resolution.
- C-M4 data governance: who owns the data, FOIA, retention, exit plan — RESOLVED: open license (ODbL or CC-BY) declared at launch, photos CC-BY, stable citable UUIDs, documented export schema, ownership/retention/FOIA/escrow written into org onboarding terms.
- C-M5 verification triage that scales (trust tiers, sampling, anomaly flags, batch verify — "a verification inbox without a triage model is a backlog generator") — DEFERRED to Phase 2; until then D12's `verification_state` marks everything non-city, non-org as unverified. There is no raw inbox, ever.
- C-priority "defer or fence add-a-tree" — RESOLVED (fenced): community layer, visually distinct, never displayed as part of the city inventory until verified; 10 m any-species proximity dedupe returns a conflict with candidates. Whether to defer it entirely if verification slips is DESIGN open question 4 — OPEN, current call is keep-and-fence.
- Arborist: the nightly open export publishes unverified citizen observations as a citable dataset before any QA tier exists — RESOLVED by D12 (machine-readable column, export README states unverified rows are unfit for inventory ingestion, structured observation export withheld).

### 2.5 Data integrity and stale inventory

- C-C3 "One-time seed with no sync means the map rots; volunteers will water stumps." — RESOLVED: weekly full re-download diffed on `external_ref`; removed-from-source rows with no community activity in 12 months become `removed`, with activity they open a `removed_but_active` review flag and keep their timeline; community contributions are never deleted by sync; a golden-file test pins all of it.
- P-M1 mortality/removal/replacement lifecycle; ID must persist through removal and replant — RESOLVED: tree status lifecycle (alive → declining → dead-standing → removed → stump → vacant-site), lineage-linked UUIDs, removed trees become memorial profiles rather than 404s. Note: an observation of `appears_removed` never mutates `trees.status` directly; it opens a review flag a moderator or coordinator confirms.
- P-C1 "The 1–5 vitality rating is scientifically worthless without an anchored rubric." — PARTIAL: the anchored rubric with reference photos is Phase 1 and is an entry gate for milestone M2 (the check-in screen does not ship without the five anchor photos), and D3 makes anchors always visible. **Which rubric — USFS urban FIA crown classes wholesale, or a validated five-class derivative — is OPEN** and needs an urban forestry advisor before Phase 1 data collection. This is the single highest-value unresolved item: every observation collected before it exists is permanently un-normalizable.
- P-C2 "No observer competency model; a role badge is not a calibration record." — DEFERRED to Phase 2 (calibration tasks, agreement checks, competency records feeding trust tiers). Until then untrained-observer noise is only separable by `verification_state` and per-field method flags.
- P-M2 multi-stem DBH, measurement height, fork rules, lean, method (tape/caliper/estimate) — PARTIAL: D7 makes unit and method mandatory in Phase 1; the full multi-stem array and measurement-height convention are Phase 2.
- P-M3 species ID as versioned, attributed, confidence-scored assertions with correction history and genus-only/unknown options — RESOLVED in the data model (assertion + consensus model, iNaturalist as reference); the consensus/verification UI is Phase 2.
- P-M4 explicit units, canonical SI storage, range validation — RESOLVED: canonical units in the shared TypeScript core, entered unit captured, range validation on entry, and a schema invariant test that no observation carries a numeric without method metadata.
- P-M5 photo standardization beyond a ghost overlay (prescribed shot types, scale reference in frame, camera distance/height, phenology tag) — PARTIAL: shot types and phenology tags are specified; in-frame scale reference and capture distance/height are OPEN, which caps what growth estimation can do later.
- P-C3 licensing/export/stable IDs deferred to Phase 3 — RESOLVED, pulled to Phase 1 (license declaration, documented CSV/GeoJSON export keyed on `external_ref` + UUID with i-Tree-compatible conventions, immutable UUIDs).
- C-M3 data-standard alignment (DBH in inches at 4.5 ft, condition ratings compatible with inventory schemas, i-Tree/UFI species codes) — PARTIAL: i-Tree-compatible export conventions are committed; round-trip compatibility of condition ratings depends on the unresolved rubric choice above.
- Open Question #3 (enforce methodology or accept estimates) — RESOLVED: accept both, always; record which per field via a mandatory method flag; never block submission.

### 2.6 Incentives and community health

- All four v1 personas plus the round-2 skeptic converged: leaderboards/streaks on infrastructure data buy volume over accuracy ("500 drive-by vitality-3 check-ins"), farmed records poison the health time series at the source and are indistinguishable forever, extrinsic rewards crowd out the intrinsic users Phase 1 depends on, favorites stop being a private bookmark and become a vote, and ranked attention routes toward Grandmother Cypress and away from the young street trees that most need eyes. — RESOLVED by D1 plus the adopted replacement loop: recognition through knowing trees over time, streaks that belong to the tree and its caretaker group rather than a person, status through validation by others, and coverage gaps as the only directed incentive (chasing coverage produces exactly the data you want).
- V-priority "make leaderboards org-scoped, not individual" — DEFERRED to Phase 3 and constrained: org-scoped crew totals only, scored contributions gated behind verification, no individual streaks.
- Cold-start thresholds guard the replacement loop: "caretakers" = distinct users with ≥2 care events or observations in 24 months, shown only at ≥3.

### 2.7 Round-2 findings not closed by a D-decision

- "The Report screen is a strictly worse 311: on the official city app, reporting does something; ours ends in 'the city has not been notified'." — accepted as true for Phase 1. Mitigated only by honesty (D4) until Open311 lands in Phase 2.
- Photo storage costs scale with the most engaged users while revenue scales with nothing. D14 prices orgs, not photo volume; the cost curve is unaddressed. OPEN.
- Tree nicknames existed only in the mocks (no field, no naming flow, no moderation path for the inevitable abuse case) — RESOLVED by D15: nicknames and their moderation are field-level in the data model, with an active-name concept on the profile payload.
- Ingest was named but unspecified (no column mapping, no null-coordinate or non-tree row rules, no diff algorithm) — RESOLVED by D15/BUILD-PLAN §7 plus the golden-file test.
- Milestones were grocery lists and the word "test" appeared nowhere — RESOLVED by D15: M0–M4 with acceptance criteria and a test plan (golden-file ingest, outbox chaos, E2E U1–U10, schema invariants, export contract, design-system validator).
- Roughly fifteen load-bearing ambiguities (clustering direction, "best photo", "recently visited", "your area", season strip, caretakers count, moderation scope, photo fuzzing, threshold rendering, auth method) — RESOLVED one sentence each as A1–A10 in BUILD-PLAN §11. Do not re-litigate them in code review.

### 2.8 Still open

- Which anchored crown/vitality rubric (see 2.5) — blocks Phase 1 data collection.
- Open311 coverage and quality per launch city; SF may need a case-API adapter rather than generic GeoReport.
- How much species field-guide content can be openly licensed versus authored/commissioned.
- Whether community add-a-tree survives in Phase 1 if verification machinery slips.
- Retention beyond phenology notifications is unproven; day-30 behavior is untested.
- Photo scale-reference capture, without which growth estimation has no scale invariance.
- Whether any org converts at the $50–200/month price point (D14 makes this a design-stage experiment with a written outcome).

## 3. Constraints an implementer must not violate

1. No streaks, points, ranks, badges, or public counts of user actions anywhere. Recency and identity phrasing only (D1). Aggregate surfaces below their cold-start threshold do not render.
2. Never connect estimated and measured points in one chart series; they are separate series (D7). Charts in a small-multiple set share one scale (D2).
3. Never write "sent to the city" / "routed to <agency>" copy without a real 311 ticket id in hand. The honest "the city has not been notified" state is required otherwise.
4. Hazard categories never produce a public note, never produce a community-visible record, and never auto-stale. No public surface query may be able to return a hazard-category note (enforced by a schema invariant test).
5. Every numeric observation carries method and unit metadata; submissions without them fail at the type level. Submission is otherwise never blocked for lack of rigor.
6. Canonical SI internally, entered unit captured, range validation on entry.
7. Contributions are append-only, except favorites (tombstone toggles) and tree-status side effects. A tree status transition requires a moderator or org coordinator confirming a review flag — an observation never mutates status directly.
8. Sync dedupes on `client_uuid`; zero loss and zero duplicates across network flaps is a CI-enforced acceptance criterion.
9. Never collect birthdates, passwords, or exact photo GPS. Email auth is magic link only. Age gate is a single over/under-18 choice.
10. Strip all EXIF server-side on ingest; store capture timestamp and the app's own fuzzed coordinates in columns. Public photo locations snap to a universal 25 m grid. Tree pins themselves stay exact.
11. Contribution feeds are private by default; public timelines say "a visitor" unless `public_attribution` is opted into, and always for under-18 accounts. Adopter identity is never public.
12. Account deletion anonymizes attributed rows (user_id nulled, device link severed) rather than deleting them; it ships from day one.
13. Every provenance fact is a queryable column. No UI-only provenance. The export carries `verification_state`; its headers and values are pinned by a contract test that fails CI on diff.
14. Evergreen species never get fall-color chips or autumn strip colors; the chip set derives from the species leaf-retention attribute (enforced by a schema invariant test: no evergreen with `fall_color_months`).
15. Do not invent botanical content. The curated YAML in the repo is the only source; it is loaded by migration, never hand-edited in production. The long tail gets name, family, and a silhouette.
16. Community-added trees stay in a visually distinct community layer and never render as part of the official city inventory until verified. Add-a-tree requires a photo and runs the 10 m proximity dedupe.
17. City sync never deletes community contributions. A removed city record becomes a memorial profile, not a 404.
18. Tree-ID candidate lists within GPS error require an explicit confirmation tap with a distinguishing trait shown per candidate; store per-contribution GPS accuracy and exclude low-accuracy contributions from growth charting (D6).
19. The five vitality anchor photos are an M2 entry gate: the check-in screen does not ship without them, and the anchor sentence is always visible, with color as secondary coding only (D3).
20. Stack decisions in BUILD-PLAN §3 are decided, not suggestions; do not substitute without a written reason. All schema changes via checked-in migrations.
21. When a screen or state is not in the mocks or BUILD-PLAN §9, stop and ask rather than inventing it.
22. Ingest fails loudly if more than 2% of DataSF rows fall through to a species stub.

## 4. Deferred / out of scope

**Phase 2** — full structured observation (multi-stem DBH, measurement height, age-adaptive young-tree forms); observer calibration tasks and competency records; verification trust tiers, anomaly flags, sampling, batch verify; care-request duplicate clustering and reporter notification; Open311 integration and per-city Cityworks/Cartegraph adapters; the in-app staff triage queue (onboarded departments only); group workday mode with live claimed/done status and same-day dedupe; adoption reminders and "my grove" polish; full offline area/tile download; AI species suggestion from photos (pulled forward from Phase 3); species consensus/validation UI.

**Phase 3** — AI photo analysis for health flags and growth estimation; neighborhood canopy trends and survival analytics; public API and researcher portal with competency-filtered datasets; org-scoped crew totals as the only permitted gamification, gated behind verification; additional cities; city-push delta sync.

**Explicitly not built** — individual leaderboards, ranks, streaks, and public action counts (permanently out, D1); public hazard notes (permanently out, D4); a raw verification inbox; iNaturalist-style research-grade status in Phase 1; fabricated species content for the long tail; a second work-order system competing with Cityworks; content AI in Phase 1 beyond nudity/person safety screening and the face/plate blur pipeline; Mapbox or any per-seat map licensing; passwords.

**Scope boundaries** — one city deep at launch (SF); NYC stays import-ready as proof of generality, not shipped. Eleven of sixteen missing screens identified by the designer are build requirements in BUILD-PLAN §9, not mocks. Cities are a Phase 2 commercial conversation; the pitch is the org-verified layer plus Open311 round-trip, never the raw citizen feed.
