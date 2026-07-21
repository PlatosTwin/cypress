# Cypress — Persona Critiques of Design Plan v1

Four persona agents reviewed [DESIGN.md](DESIGN.md) (v1). Their critiques are preserved here verbatim; the refinements were folded into v2 of the plan.

---

## Persona 1: The Tree Enthusiast

*A city dweller who loves trees, photographs them on walks, is teaching themselves species ID, and visits favorite trees across seasons. Not a professional; allergic to long forms.*

### Top 3 concerns

**Concern 1: The check-in — supposedly a core Member action — is built around a health-inspection form, not around noticing a tree.**
The "basic check-in" in Phase 1 is "vitality rating, foliage condition, notes, photos." A vitality rating? I don't know how to rate a tree's vitality 1–5, and honestly I'd be scared of getting it wrong and polluting someone's data. When I visit my favorite ginkgo, what I actually want to do is take a photo and maybe say "leaves are turning!" The plan treats the photo as an attachment to an observation record; for me, the photo IS the visit. If the lightest-weight interaction still opens with sliders and condition ratings, I'll do it twice and then stop. There needs to be a zero-judgment "I was here, here's a photo" action that takes ten seconds, and everything else optional behind it.

**Concern 2: The whole plan's center of gravity is data collection for cities, and people like me are cast as free sensors.**
Reading the roles table, Members exist to "upload photos, submit care reports, light check-ins" — that's unpaid data entry with a friendly name. The words that would describe why *I* would open this app — learn, discover, wonder, seasons, beauty — barely appear. Species info is a data-model footnote ("care notes, ID tips") and there's no learning surface anywhere in Phase 1 or 2. If the app's implicit message is "help us maintain the municipal inventory," I'll bounce; if it's "here's a way to fall deeper in love with the trees on your block," I'll open it weekly and the city gets its data as a side effect.

**Concern 3: Help identifying trees — the single thing I most want — is parked in Phase 3 as "AI photo analysis."**
I am *teaching myself* species ID. That's the hook. The plan defers species suggestion to the last phase, alongside researcher APIs and canopy analytics. But here's the thing: in the launch cities, the species data is already seeded from city datasets! You don't even need AI for the magic moment — "point at a pin, learn that this is a Chinese elm, here's how to recognize one" is possible on day one. The plan never sketches a species page for mobile (species pages are listed only under *Web* Explore), and there's no "what tree is this?" flow at all until Phase 3. That's backwards for the audience most likely to show up first.

### Missing features (ranked)

1. **"What tree is this?" as a first-class mobile flow.** Stand next to a tree, tap one button, see the nearest cataloged trees with photos and names. Even without AI, GPS + the seeded city data gets you 90% there. This would be my #1 reason to pull the app out on a walk.
2. **Seasonal delight and return triggers.** "Your favorite cherry on 5th Ave bloomed last year around this week — go see it." "The ginkgos in your neighborhood are about to turn." Notifications tied to phenology, not to watering chores. This is what makes the app *weekly* instead of twice-ever, and the photo-timeline data to power it is already being collected.
3. **Learning built into every tree profile.** ID tips with photos ("look for the fan-shaped leaves"), fun facts, what to look for this month, "5 more of these within 3 blocks." Make each profile a tiny field guide entry, not a stats card of height/DBH/last-check-in.
4. **Sharing a tree.** A beautiful, shareable card or link for a tree — its best photo, name, a season strip. I follow remarkable-tree accounts; I want to *be* one. Nothing in the plan lets me show a tree to a friend who doesn't have the app, and that's also your growth loop.
5. **Personal journal / walk view.** All my photos and visits across all trees, as a chronological or map-based diary of my walks — "your year with the trees." My Grove is close but it's framed as adopted-tree management, not memory.

### What works

- **Seeding with city open data so the map is alive on day one.** This is genuinely great. Opening the app and seeing my actual street — every tree already named — would give me an instant "whoa" and immediately start teaching me species. Best decision in the plan.
- **The photo timeline as a core object.** Swiping through a tree across seasons and years is exactly the kind of thing I do manually in my camera roll now. The ghost-overlay to match the last photo's angle is a lovely touch — it makes taking a good photo feel like a fun little skill rather than a data requirement.
- **Browsing without an account.** No signup wall to explore the map is the right call. I'd have bounced off a login screen; instead I get to fall for the product first.

### Priority changes

- **Pull species learning out of Phase 3/web-only and into Phase 1 mobile.** Species pages, ID tips on tree profiles, and a GPS-based "what tree is this?" using seeded data belong in the MVP. Even the AI species *suggestion* should be considered for Phase 2 — it's the enthusiast hook, and it's a much easier AI problem (and better understood, see every plant-ID app) than health flagging or growth estimation.
- **Split the Phase 1 check-in.** Ship "photo + optional note" as the Member check-in in Phase 1; move vitality/foliage ratings into the structured check-in that's already planned for Phase 2 Stewards. Don't make me grade a tree's health to say hello to it.
- **Pull one gamified collection mechanic — species "collections" — from Phase 3 into Phase 1 or 2, and leave streaks/leaderboards where they are.** "You've photographed 12 of the 40 species in your neighborhood" is learning disguised as collecting, and it's cheap to build. Streaks and leaderboards can wait; competitive pressure is exactly the wrong tone for tree appreciation.
- **Move seasonal/phenology notifications into Phase 2 alongside adoption reminders.** The plan already builds a reminder system there for watering; wire it to bloom/color moments too. Chore reminders are for stewards; season alerts are for me.
- **Deprioritize nothing for cities except tone:** the staff dashboard and care-request workflow can stay in Phase 2 as planned — but Phase 1's success metric should be "do enthusiasts come back weekly," not "how many observations were collected," and the screen designs should reflect that (Tree Profile leading with story and season strip, stats row demoted below it).

---

## Persona 2: The Weekend Volunteer

*Volunteers Saturday mornings with a city tree-planting org. Plants, waters, does care visits on assigned blocks. Gloves on, spotty cell coverage, currently uses paper forms. Time-boxed mornings: 15–25 trees per outing.*

### Top 3 concerns

**Concern 1: There's no concept of a route, block, or workday — the whole app assumes I care about one tree at a time.**
On a Saturday care visit I'm handed 15-25 trees on two or three blocks, and I walk them in order. The Check-in Wizard (screen 3) is built around "confirm tree → six steps → submit," which means every tree starts from scratch: find it on the map, tap it, walk the wizard. The plan mentions "batch field surveys" in the Steward role table (section 2) and then never designs it — it doesn't appear in any phase or any screen. That's the single most important flow for someone like me and it's vaporware in this document.

**Concern 2: Offline is Phase 2, which means Phase 1 is unusable for actual field work.**
Half my assigned blocks have one bar of LTE, and I'm not standing next to a ginkgo waiting for a photo upload spinner. If check-ins and photos can't queue locally on day one, volunteers will try the app once, lose a morning's data to a dead zone, and go straight back to the paper form — and they won't come back for Phase 2. Paper never fails to sync. For the stated "mobile = field tool" positioning (section 5), offline isn't a stewardship feature, it's table stakes.

**Concern 3: A six-step wizard per tree is too slow — 20 trees × 6 screens is my whole morning gone to tapping.**
The steps themselves are sensible (vitality sliders, site checklist, ghost-overlay photo — good), but step-per-screen navigation with gloves on, in sun glare, is death by transition animation. Our paper form is one sheet: I scan down it in 60 seconds per tree. I need a single scrollable card with big tap targets, smart defaults ("same as last visit"), and the ability to skip measurements entirely. Also nothing in the plan says how long a check-in should take — if the team isn't designing to a "under 90 seconds per healthy tree" budget, they'll ship a 5-minute form.

### Missing features (ranked)

1. **Assignments / task lists from my org.** Nothing in the plan tells me which trees MY org wants checked THIS weekend. Adoption ("my grove") is a personal, self-selected list — that's not how org work happens. My lead assigns blocks. I need an "Assigned to you: 18 trees, Oak St 400-600 block" list that I can walk top to bottom, with checkmarks as I go.
2. **Group workday mode.** Ten of us descend on one block with shovels. Who's doing which tree? Right now two volunteers would double-enter tree #12 and nobody touches #15. Even something dumb-simple — a live "claimed/done" status per tree visible to everyone on site, plus dedupe of same-day observations — would fix Saturday chaos.
3. **A "did the basics" quick log distinct from a health check-in.** Most visits I water, mulch, weed the basin, maybe remove a stake. That's not an "observation" with DBH and foliage percentages — it's "watered ✓, mulched ✓, 30 seconds, next tree." The Observation model (section 3) has nowhere to record care performed, only conditions observed. Those are different things and my org lead needs both.
4. **Confirmation that my data reached my org lead.** The Staff Dashboard (screen 7) is for city staff. My volunteer coordinator at a nonprofit isn't "city forestry personnel" — does she get a dashboard? A weekly digest? CSV of this Saturday's visits? If my data goes into a database and my lead still asks me to fill in the spreadsheet Monday, I'm now doing the work twice, which is worse than paper.
5. **Young-tree-specific fields front and center.** Stakes/ties are buried under "site: hardware." For establishment-phase street trees (my entire job), stake condition, tie girdling, basin/berm state, and mulch depth ARE the check-in; DBH and canopy spread are almost irrelevant for a 2-year-old tree. The form should adapt to tree age.

### What works

- **Seeding with the city datasets** (section 3, "Seed data") is exactly right. Half my paper-form time is writing down which tree I'm even at. Pre-loaded trees with city IDs means I confirm instead of transcribe.
- **The ghost-overlay photo alignment** (screen 3, step 5) is genuinely clever. Matching last visit's angle is something we're told to do and never manage; this makes it automatic.
- **Care requests with a status workflow** (open → acknowledged → resolved) beats what I have now, which is telling my lead "the elm on 24th looks bad" and never hearing anything again. Screen 4 showing "routed to SF Public Works" — closing that loop is huge for volunteer morale, IF it's honest and not a fake promise (open question 2 worries me).

### Priority changes

- **Move offline queueing (check-ins + photos) from Phase 2 into Phase 1.** Ship with less — I'd trade the entire add-a-tree flow and favorites for offline. You can cut fancy area-download of map tiles to Phase 2; just never lose a submitted check-in to bad signal in Phase 1.
- **Move a basic version of Steward/org affiliation + assigned tree lists from Phase 2 into Phase 1, and actually design the "batch field survey" flow the roles table promises.** Without orgs, the launch audience is casual passersby, and casual passersby don't do 20 check-ins on a Saturday — volunteers do. We're the ones who'll generate the longitudinal data everything else (staff triage, Phase 3 AI) depends on.
- **Add a "care performed" quick log to the data model and put it in Phase 1.** It's simpler to build than the health observation and it's the highest-frequency event in the system.
- **Deprioritize within Phase 2:** adoption reminders and "my grove" polish can slide. Adoption is the hobbyist path; assignment is the workhorse path. Build the workhorse first.
- **Phase 3 gamification:** fine where it is, but make leaderboards org-scoped ("your crew logged 214 trees this season") rather than individual streaks — Saturday volunteering is a team sport, and individual streaks mean nothing to someone who shows up twice a month.
- **Answer open question 3 (measurement rigor) now, not later:** accept rough estimates, always. Any field that blocks submission because I didn't bring a DBH tape will get the whole form abandoned.

---

## Persona 3: The City Forestry Worker

*Parks/public-works urban forestry staff. Plants with volunteer orgs, maintains the official inventory, responds to service requests. Lives in work orders, 311 tickets, liability, procurement review, and existing asset-management systems.*

### Top 3 concerns

**Concern 1: The "staff triage queue" is a parallel work-order system, and we will not adopt it.**
My work lives in Cityworks (or Cartegraph, or whatever asset-management system the city already licenses and integrates with 311, payroll, and GIS). A second web dashboard I have to check separately is a duplicate inbox — and every duplicate inbox eventually goes unwatched. The plan's own Open Question #2 ("how do care requests reach cities that aren't onboarded — email digest or nothing?") is the tell: if the answer for non-onboarded cities is "nothing," you've built a place where residents *believe* they've reported a hazard to the city, and the city never sees it. The screen mock even says "routed to SF Public Works" — do NOT show that text unless there is an actual, contracted integration behind it. That's not a UX detail; that's a misrepresentation the city's attorneys will notice.

**Concern 2: Hazard reports sitting in an app create liability with no owner.**
A CareRequest of type "damage" with severity "high" — a cracked leader over a sidewalk — that sits "open" in Cypress for three weeks before a limb drops on someone is a discoverable record showing the hazard was reported and nobody acted. The plan has a status workflow (open → acknowledged → scheduled → resolved) but no answer to: who is legally on the hook for the queue, what's the SLA, what happens to a severity-critical report at 2am on a Saturday, and how does the app disclaim (or not) that it is a substitute for calling 311. This alone would stop procurement review at my city. Hazard/emergency report types should either hard-route into the official channel (311 API, with the city's ticket number echoed back) or be redirected out of the app entirely ("Call 311 now"), and the plan needs that decision in Phase 2, not as open question #2.

**Concern 3: One-time seed import with no sync plan means the map rots immediately.**
The plan says "launch with SF/NYC open data pre-loaded" and `external_ref` "keeps sync possible" — possible isn't a design. Our inventory changes weekly: removals, stump grinds, new plantings, species corrections, address fixes. Within six months the Cypress map will show trees we removed (and volunteers will file check-ins and water requests on stumps — I already get 311 tickets like this), and it will miss everything we planted. The published open dataset also lags our internal system by weeks or months. You need, minimum: scheduled re-import with a documented merge/conflict policy (what happens to 40 volunteer photos attached to a tree the city record says was removed?), a "removed/retired" tree state, and ideally a path for the city to push deltas. Background jobs for "city-dataset imports" is mentioned in architecture but the merge semantics are the whole problem, and they're absent.

### Missing features (ranked)

1. **311 / work-order system integration as the primary triage path** — Cityworks/Cartegraph/Salesforce-311 connectors or at least an Open311 GeoReport v2 endpoint, with two-way status sync so the app shows the city's real ticket status. Without this, the "triage queue" should not exist as a destination for hazard reports.
2. **Duplicate-report clustering on CareRequests, not just add-a-tree.** After a storm I get 30 reports on the same hanging limb. The plan detects duplicate *trees* but says nothing about deduping *requests*. Group reports on the same tree/type, roll them into one ticket, and notify all reporters on resolution — this is the single biggest thing that would make volunteer reporting a gift instead of a burden.
3. **Data standard alignment and a real species authority.** If volunteer observations don't map to what we use (DBH in inches at 4.5 ft, condition ratings compatible with our inventory schema, species codes matching our list — ideally i-Tree/Urban Forest Inventory conventions), I can't import them into the system of record and the data is a curiosity. Also: bulk export keyed on `external_ref` so I can round-trip.
4. **A public-records / data-governance answer.** Who owns the observation data — Cypress the vendor, or the city? If a resident FOIAs "all hazard reports about trees on Elm St," can the city produce Cypress records? What's the retention policy? What's the exit plan if Cypress folds (civic apps fold)? Procurement and city IT security review will ask all of this on day one; a plan that wants "org staff" as a role needs a data-processing/ownership section.
5. **Verification triage that scales, with trust tiers.** Phase 2 says "staff verify member-submitted data" — I do not have hours to review thousands of check-ins. I need: auto-accept from credentialed Stewards of a partner org, sampling/spot-check tooling, anomaly flags only (DBH shrank 6 inches? flag it), and batch verify. "Verification inbox" as a screen without a triage model is a backlog generator.

### What works

- **`external_ref` to city tree IDs from day one.** This is the thing most civic tree apps skip, and it's the only reason any of the volunteer data could ever flow back into my inventory. Keeping it in the core data model, not bolted on, is correct.
- **The check-in wizard's measurement guidance and photo ghost-overlay.** DBH-at-4.5-ft illustrations and angle-matched repeat photos are exactly how you get volunteer data that's actually usable longitudinally instead of noise. Whoever specced screen 3 has done field work or talked to someone who has. Same for retaining original-resolution photos and EXIF.
- **Offline field mode in Phase 2.** Park interiors and street canyons kill signal; every field tool that ignores this dies in the field. Download-an-area + queued sync is the right shape, and honestly it's something the city's own contractor tools do badly.

### Priority changes

- **Move re-import/sync of city data from "implied someday" into Phase 1.** If you seed from open data in Phase 1, you must ship scheduled refresh + a removed-tree state + merge rules in Phase 1. A stale map is worse than an empty one because it generates false work.
- **Split care requests in Phase 2: routing before queue.** Ship the 311/Open311 routing (or an explicit "this does NOT notify the city — call 311 for hazards" disclaimer plus emergency-type redirect) *before* the in-app staff triage dashboard. The dashboard is the part least likely to be adopted; the routing is the part that protects everyone. As written, Phase 2 builds the queue first and leaves routing as an open question — backwards.
- **Pull the CSV/GeoJSON export (currently a bullet on the Phase 2 staff dashboard) forward and make it first-class, keyed on `external_ref` with a documented schema.** Export-to-my-system is my actual adoption path; the dashboard is not. Conversely, the "public data export / API" in Phase 3 is fine where it is.
- **Push gamification (Phase 3) further back or rethink it.** Leaderboards and streaks on infrastructure data incentivize volume over accuracy — I'll get 500 drive-by "vitality 3" check-ins that tell me nothing and still land in my verification inbox. If you keep it, gate scored contributions behind Steward verification.
- **Defer add-a-tree, or fence it harder.** Phase 1's add-a-tree flow will flood the verification pipeline before the Steward/verification machinery exists (that's Phase 2). Either move add-a-tree to Phase 2 alongside verification, or keep Phase 1 additions in a clearly separate "unverified community layer" that never displays as part of the city inventory.
- **On measurement rigor (Open Question #3):** don't *enforce* methodology for Members, but *record* method and confidence with every measurement and let me filter on it. A rough estimate labeled as a rough estimate is useful; a rough estimate indistinguishable from a taped DBH poisons the whole column.

---

## Persona 4: The University Professor

*Urban forestry / dendrology professor. Studies urban tree growth, survival, and ecosystem services. Knows measurement protocols (DBH at 1.37 m, USFS crown ratings, i-Tree Eco) and has published on citizen-science data quality.*

### Top 3 concerns

**Concern 1: The 1–5 vitality rating is scientifically worthless without an anchored rubric.**
The plan lists "vitality rating (1–5 scale) + free-text notes" with zero definition of what each value means. A "3" from a weekend Member and a "3" from a trained Steward are not the same measurement, and neither maps to anything in the literature. I need explicit anchors tied to an established protocol — USFS crown dieback classes, crown vigor/condition ratings, live crown ratio, foliage transparency percentages — with reference photos per class. Without that, you are generating subjective ordinal noise that I cannot pool across observers, cities, or years, and no amount of longitudinal volume rescues it.

**Concern 2: No observer competency model — you cannot separate signal from training-level noise.**
The plan attributes every field to an observer and distinguishes "Member" vs "Steward" roles, but a role badge is not a calibration record. There is no notion of observer training level per protocol, no calibration/QA task (re-measure a reference tree, agreement checks against a known-standard observer), and no per-field method flag beyond a single tree-level "visual/measured." My published work on citizen-science quality lives or dies on exactly this: I need to filter or weight by observer skill, and detect drift. As designed, one enthusiastic but untrained Member misreading DBH propagates into the "verified most-recent" record and I have no way to quarantine it.

**Concern 3: Open export/API and licensing are deferred to Phase 3 — data usability is an afterthought, and there's no licensing clarity at all.**
"Public data export / API; researcher access" sits in the last phase, and the document never states a data license, ownership terms for contributor photos/observations, or a stable persistent tree identifier scheme. That is the classic proprietary silo that makes me refuse to invest field-campaign effort. If I can't know on day one that the data is CC-licensed (or similar), exportable in an open schema, with citable stable IDs, then everything collected in Phases 1–2 accretes inside a black box I can't publish from.

### Missing features (ranked)

1. **Mortality / removal / replacement lifecycle.** The Observation schema records living-tree condition but has no way to record that a tree is dead, dead-standing, removed (stump), or replaced. Survival analysis is the single most valuable output of a longitudinal urban-tree dataset, and this schema literally cannot express the end state. I need a status field (alive / declining / dead-standing / removed / stump / vacant-site) with date and cause, and the tree ID must persist through removal and replanting.
2. **Multi-stem / measurement-method specification for DBH.** "dbh" is a single scalar with no rule for the 1.37 m (4.5 ft) height, no handling of forks below breast height, no multi-stem convention (record each stem, or compute combined-DBH via sqrt of sum of squares), no lean/slope adjustment, and no note of whether it was tape-measured, caliper, or estimated. Multi-stem trees are ubiquitous in urban plantings; a single DBH number silently corrupts basal-area and biomass math. I want an array of stem diameters plus the measurement-height and method per measurement.
3. **Species ID confidence + correction/verification workflow with history.** Species is modeled as a flat pointer to a Species record. There is no confidence level on an identification, no "identified by / confirmed by," no genus-only or "unknown" option, and no audit trail when an ID is corrected. Misidentifications will propagate and there's no way to see that a tree was reclassified from *Prunus* to *Pyrus* last spring, or who vouched for it. Model ID as a versioned, attributed, confidence-scored assertion — iNaturalist's research-grade consensus model is the reference to steal from.
4. **Explicit units and a validated schema on every quantitative field.** Nothing in the model states units (cm vs in for DBH, m vs ft for height, % scales). "height_est," "canopy_spread," "density %" will collect mixed units the moment you have international or mixed-crew use. Store canonical SI internally, capture the entered unit, and range-validate on entry. Unit chaos is unrecoverable after the fact.
5. **Photo standardization beyond a ghost overlay.** The ghost overlay for angle-matching is a good start but insufficient for future AI or phenology work. I want prescribed shot types (full-tree from a fixed cardinal direction, trunk/DBH point, canopy-up, leaf/bud close-up, whole-site), a scale reference in frame (a marked stake or the DBH tape), capture of camera distance/height, and a leaf-phenology/season tag. Angle consistency alone doesn't give you the scale invariance growth-estimation needs.

### What works

- **`external_ref` to city inventory IDs and seeding from SF/NYC open datasets.** This is the right instinct for interoperability and for not reinventing an inventory. Keeping a link back to the municipal record means my data can round-trip against the authoritative city schema, and starting from real datasets avoids the empty-map cold-start that kills field engagement.
- **Originals retained with EXIF timestamp/GPS, explicitly as future AI substrate.** Deciding up front to keep full-resolution originals with date/location metadata (with consent) is exactly the non-blocking decision that preserves scientific option value. Most consumer apps destroy this by re-compressing; not doing so is genuinely forward-looking.
- **Attribution + timestamping of every contributed field, with a verification flag.** Per-field provenance is the correct foundation. It's the necessary substrate that a proper observer-competency and confidence model can be built on top of — the plumbing is right even though the QA model above it is missing.

### Priority changes

- **Pull data licensing + open export schema + stable persistent tree IDs from Phase 3 into Phase 1.** Not the full public API — just the license declaration, a documented open export (CSV/GeoJSON already exists in the Phase 2 staff dashboard, so formalize its schema now), and immutable tree UUIDs that survive removal/replant. These are cheap to decide early and ruinously expensive to retrofit.
- **Move mortality/removal status and the anchored vitality rubric into Phase 1's "basic check-in."** The rubric costs design effort, not engineering effort, and every observation collected before it exists is permanently un-normalizable. Same for a status field — you're collecting check-ins from day one, so they must be able to say "this tree is dead."
- **Move DBH method/multi-stem/units specification up from Phase 2 into whenever measurements are first collectible, and pair the Phase 2 "measurement guidance" with a mandatory observer calibration task.** Don't ship measurable fields without the method metadata that makes them poolable.
- **Answer Open Question #3 ("enforce methodology or accept rough estimates?") before Phase 1 ships, not after.** The answer should be: accept both, but *record which one it was per field* via a mandatory method/estimated flag. That single decision is the difference between a filterable research dataset and unusable mush — it cannot be deferred.
