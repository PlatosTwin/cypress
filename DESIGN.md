# Cypress: design plan (v3)

A mobile and web app for cataloging urban trees, tracking their health over time, and connecting the people who care about them: casual enthusiasts, volunteer stewards, and city forestry staff.

> v2 was revised after review by four persona critics (a tree enthusiast, a weekend volunteer, a city forestry worker, and an urban forestry professor); their critiques are in [CRITIQUES.md](CRITIQUES.md), and section 10 summarizes what changed. v3 followed a second, adversarial review by five hostile reviewers; their findings and the resulting decisions are in [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md), section 11 summarizes the strategy changes, and [BUILD-PLAN.md](BUILD-PLAN.md) is now the implementation authority where documents disagree.

---

## 1. Product summary

Cities like San Francisco and New York plant and maintain hundreds of thousands of street and park trees. The data about them lives in aging municipal databases, and their care depends on stretched city crews and enthusiastic but under-tooled volunteers. Cypress is a shared ledger for urban trees:

- A living catalog. Every tree has a profile with species, location, planting date, size, and a photo timeline showing it across seasons and years.
- A learning surface. Every profile doubles as a field guide entry, and the app can answer "what tree is this?" from day one using seeded city data.
- Two-speed contribution. Anyone can log a ten-second "Visit" (a photo plus an optional note). Trained stewards working assigned blocks do structured health check-ins and care logs.
- A community layer. People can favorite, adopt, share, and report trees that need care, with honest routing that never pretends the city was notified when it wasn't.
- AI analysis, later. Photo timelines could eventually feed growth estimates and automatic health flags. This is out of scope for now; the design just avoids blocking it by keeping original-resolution photos, standardized shot types, and method-tagged measurements.

### Design principles (added in v2)

1. Appreciation first, data second. The Phase 1 success metric is weekly enthusiast return rate rather than observation counts. If people love visiting trees, the data follows.
2. Never block a submission. Every field beyond a photo is optional. Rough estimates are always accepted, but every quantitative value carries a required method flag (measured or estimated), so rigor is recorded instead of enforced.
3. Honest routing. The app never displays "sent to the city" unless a real integration confirmed receipt. Hazards redirect to 311.
4. Decisions that are cheap now and ruinously expensive to retrofit go in Phase 1: the data license, stable IDs, anchored rating rubrics, units, tree lifecycle states, and the export schema.
5. Design to a time budget. A visit takes ten seconds or less. A care log takes thirty. A full steward check-in on a healthy tree takes ninety.

## 2. Users and roles

| Role | Who | Primary actions |
|---|---|---|
| Explorer (no account) | Passerby, curious walker | Browse map, "what tree is this?", read profiles and photo timelines, species pages |
| Member | Registered enthusiast | Visits (photo plus note), favorites, adopt, species collections, share trees, care reports |
| Steward | Trained volunteer, org-affiliated | Assigned routes, batch check-ins, care logs, structured health observations |
| Org coordinator | Volunteer lead at a nonprofit (e.g., FUF) | Create assignments, run workdays, review crew activity, weekly digests, CSV export |
| City staff | Municipal forestry or public works | Inventory sync, verification triage, care request queue (if onboarded), data round trip |
| Admin | Cypress operators | Moderation, org onboarding, species DB, import pipelines |

Roles are per organization: a user can be a plain Member globally and a Steward within "Friends of the Urban Forest." The Org coordinator role is new in v2. A volunteer's lead usually works at a nonprofit rather than the city and needs a lighter dashboard of their own.

Observer competency (v2): beyond roles, each user carries per-protocol training records (for example, "completed DBH calibration" or "crown-rating trained") earned through in-app calibration tasks such as re-measuring reference trees and agreement checks. Researchers and staff can filter or weight data by observer competency rather than role alone.

## 3. Core concepts and data model (sketch)

```
Organization -+- Membership(role, training_records[]) -- User
              +- Assignments[] -- (steward, tree_list/route, due_window)
              +- WorkSessions[] (group workdays: live claim/done per tree)
              +- manages -- Tree

Tree
  |- id: immutable UUID that persists through death, removal, and replanting
  |    (a replanted site links old tree to new tree via `site_lineage`)
  |- status: alive | declining | dead_standing | removed | stump | vacant_site
  |    (+ status_date, cause when known; enables survival analysis)
  |- provenance: city_inventory | community_added   (displayed distinctly)
  |- species_ids[]: versioned assertions rather than a flat pointer:
  |    (taxon at rank, genus-only and "unknown" allowed, confidence,
  |     identified_by, confirmed_by[], history preserved on correction)
  |- location (lat/lng + address + site: sidewalk cut, park, median)
  |- external_ref (city inventory ID) + last_synced_at
  |- Visits[]        (lightweight: photo + optional note, "I was here")
  |- Observations[]  (structured health check-ins)
  |- CareLogs[]      (care performed: watered, mulched, weeded, stake removed)
  |- CareRequests[]  (reported issues + honest routing state)
  |- Photos[], Adoptions[], Favorites[]

Observation (structured check-in, steward-oriented, 90-second target)
  |- observer (+ their training records at time of entry), timestamp
  |- every quantitative field carries: value, unit as entered
  |    (canonical SI stored), method: taped|caliper|laser|visual_estimate,
  |    and range validation on entry
  |- stems[]: diameter measurements per stem + measurement height
  |    (multi-stem convention documented; combined DBH derivable)
  |- height_est, canopy_spread
  |- crown: condition class per anchored rubric (see below), dieback %,
  |    foliage density/discoloration/damage
  |- structure: lean, broken limbs, trunk wounds, root heave
  |- site: soil compaction, mulch depth, water basin state,
  |    hardware (stake condition, tie girdling); the young-tree form
  |    surfaces these first (the form adapts to tree age)
  |- vitality: anchored 1-5 rubric aligned to established crown-condition
  |    protocols (USFS-style classes), reference photo per class,
  |    shown inline at rating time
  |- photos[], free-text notes

Photo
  |- original retained (EXIF timestamp/GPS with consent) + web sizes
  |- shot_type: full_tree | trunk_dbh | canopy_up | leaf_closeup | site
  |- phenology_tag: leaf_out | full_leaf | fall_color | bare | flowering | fruiting
  |- ghost-overlay capture aids angle and framing consistency over time

CareRequest
  |- type: watering / pruning / pest / disease / damage / hardware / vandalism
  |    hazard and emergency types are NOT accepted in-app: the user is
  |    redirected to call 311 or emergency services immediately
  |- severity, description, photos
  |- routing: unrouted ("visible to community and org only; the city has NOT
  |    been notified") | routed_311 (Open311 ticket # echoed back) |
  |    routed_org | acknowledged | scheduled | resolved | declined
  |- duplicate clustering: same-tree, same-type reports merge into one
       cluster; every reporter is notified on resolution
```

### Species (a field guide entry, not a footnote)

Common and scientific names, ID tips with photos ("look for the fan-shaped leaves"), seasonal highlights ("what to look for this month"), care notes, and a count of others nearby. This powers both the learning surfaces and species collections.

### City data: seed it, then keep it in sync (v2)

- Launch pre-loaded from the SF Street Tree List and NYC Forestry Tree Points, keyed on `external_ref`.
- Scheduled re-import from day one, with a documented merge policy:
  - A tree removed by the city gets status `removed`. Community photos and history stay on the profile, which becomes a memorial record rather than a 404.
  - New city plantings appear automatically. Species corrections create a new city-attributed species assertion instead of silently overwriting.
  - Conflicts (the city says removed, a volunteer checked in yesterday) surface in a review queue rather than auto-resolving.
- Community-added trees live in a visually distinct community layer and never display as part of the official city inventory until verified.

### Data governance and licensing (v2: decided now, not in Phase 3)

- The license is declared at launch: observations and tree data under an open license (ODbL or CC-BY), granted by contributors on upload; photos CC-BY with attribution.
- Tree UUIDs are stable and citable from day one.
- A documented export schema (CSV and GeoJSON keyed on `external_ref` plus UUID, with i-Tree-compatible field conventions) exists from Phase 1. Export is the real adoption path for cities and researchers; dashboards are not.
- Ownership, retention, FOIA posture, and an exit plan (full data escrow and export if Cypress folds) are written into org onboarding terms. Procurement will ask.

## 4. Features by phase

### Phase 1: the living map and the ten-second visit

*Success metric: weekly return rate of enthusiasts, and zero data loss in the field.*

- Map-first browse (clustered pins, filters), no account needed
- Seeded city data with scheduled re-sync, a merge policy, and tree lifecycle states
- "What tree is this?": one tap shows a GPS-ranked list of nearby trees with photos and names
- Species pages on mobile; ID tips and seasonal notes on every tree profile
- Visit: photo plus optional note, ten seconds or less, no judgment required; photo timeline on every tree
- Favorites and species collections ("12 of 40 neighborhood species spotted"), which is learning disguised as collecting; no streaks or leaderboards
- Shareable tree card with the best photo, name, and season strip on a public link (the growth loop)
- Offline submission queue: visits, photos, and check-ins queue locally and sync, so field data is never lost (full area download waits for Phase 2)
- Quick care log ("watered, mulched") in thirty seconds or less, since adopters water too
- The anchored vitality rubric and tree status (including "this tree appears dead or removed") available even in light check-ins
- Data license, stable UUIDs, documented export schema
- Hazard reports are not accepted; the app redirects to 311 or emergency services with clear messaging
- Add-a-tree is allowed but fenced into the community layer pending verification

### Phase 2: stewardship and organizations

*Success metric: a volunteer completes a 20-tree Saturday route entirely in-app, and the org lead never asks for the spreadsheet again.*

- Org affiliation, the Steward role, and an Org coordinator dashboard (assignments, crew activity, weekly digest, CSV export)
- Assignments and routes ("18 trees, Oak St 400 to 600 block") walked top to bottom with checkmarks; the batch check-in flow is a single scrollable card with big tap targets, "same as last visit" defaults, skip-anything behavior, and a 90-second-per-tree budget
- Group workday mode: live claimed/done status per tree and same-day dedupe
- Full structured observation: multi-stem DBH with method metadata, measurement guidance, and age-adaptive forms that put young-tree hardware first
- Observer calibration tasks (measure the reference tree, agreement checks) feeding competency records
- Care requests with routing before queue: Open311/GeoReport integration where available, with the real ticket number echoed back; an explicit "the city has NOT been notified" state otherwise; duplicate clustering; reporter notifications on resolution. The in-app staff triage queue exists only for onboarded departments.
- Verification that scales: trust tiers (auto-accept from credentialed Stewards of partner orgs), anomaly flags (a DBH that shrank gets flagged), sampling, and batch verify. There is no raw inbox.
- Adoption ("my grove") with reminders, plus seasonal phenology notifications ("your cherry blooms around this week")
- A personal journal ("your year with the trees")
- Full offline field mode: download an area's tiles and tree data
- AI species suggestion from photos, pulled forward from Phase 3 because it is the well-understood, proven problem

### Phase 3: intelligence and openness

- AI photo analysis: health flags and growth estimation from the standardized photo timeline
- Trends and analytics: neighborhood canopy health and survival rates by species and site, enabled by lifecycle states and method-tagged data
- Public API and a researcher portal with competency-filtered datasets
- Gamification, carefully: org-scoped crew totals ("your crew logged 214 trees this season"), scored contributions gated behind verification, and no volume-incentivizing individual streaks
- Additional cities, and city-push delta sync for inventory

## 5. Platform and architecture

- Monorepo: an Expo/React Native app (iOS and Android) plus a Next.js web app, with a shared TypeScript core for types, validation with canonical units, and the API client.
- Mobile is the field and walk tool (map, visits, check-ins, offline). Web is the depth tool (rich profiles, species guide, coordinator and staff dashboards, import/export). One account works everywhere.
- Backend: Postgres with PostGIS for spatial queries and neighborhood rollups, object storage for photo originals and derived sizes, and background jobs for recurring city-dataset sync and Open311 submission and status polling.
- Auth: email plus Apple and Google sign-in. Browsing requires no account.
- Offline: a local queue for all submissions in Phase 1 (a SQLite outbox with retry on connectivity), and area download in Phase 2.
- Integrations: Open311 GeoReport v2 as the standard care-request rail, with per-city adapters (Cityworks or Cartegraph connectors) only for onboarded departments.

## 6. Key screens (mock sketches)

Mobile:

1. Map Home. A full-bleed map with cluster pins colored by status, search, and filter chips (species, in bloom, needs care). The primary FAB is "What tree is this?" with Visit and Report behind a long press.
2. Tree Profile. The hero photo and season strip come first (story before stats), then species with ID tips ("fan-shaped leaves"), a health badge, the photo timeline, and actions: Favorite, Adopt, Share, Report. The stats row (height, DBH, last check-in) sits below the fold. Tabs: Story, Details, Care history.
3. Visit sheet. The camera opens immediately with a ghost overlay and shot-type hint, an optional note, done. Ten seconds.
4. Route view (Steward). The assigned list ordered by walk, with checkmarks and a per-tree single-card check-in: care-performed toggles up top, rubric-anchored condition ratings with reference photos inline, optional measurements with a method picker, big glove-friendly targets, and "same as last visit" prefill.
5. Report Issue. A type picker where hazard types redirect to a full-screen "Call 311 now," then severity, photo, and a routing status shown honestly: "Open311 ticket #4711" or "Visible to community and Friends of the Urban Forest; the city has not been notified."
6. My Grove and Journal. Adopted and favorited trees, care reminders, species collection progress, and "your year with the trees."

Web:

7. Explore: the map plus a species field guide, neighborhood pages, photo galleries, and shareable public tree pages with no login.
8. Coordinator dashboard (org): create assignments, watch workdays live, review crew activity, set weekly digests, and export the weekend's CSV in one click.
9. Staff dashboard (city, onboarded): care-request clusters rather than raw reports, verification triage with anomaly flags, batch verify, trust tiers, inventory sync conflict review, and export keyed on external_ref.
10. Tree Profile (web): the full observation history with method and observer filters, plus side-by-side photo comparison across time.

## 7. Data quality and moderation

- Per-field attribution and timestamps (kept from v1) are now the substrate for competency-weighted trust rather than a lone verified flag.
- Species IDs use an assertion and consensus model, with iNaturalist's research-grade flow as the reference.
- Duplicate detection runs on add-a-tree (proximity plus species) and duplicate clustering runs on care requests.
- Photo moderation combines reports with automated screening. For privacy, faces and license plates are blurred on public photos, and GPS precision is reduced near residential addresses for public display.
- When data conflicts, the most recent trusted value wins for display, and the full history is always retained.

## 8. Decisions made (formerly open questions)

1. Adoption is symbolic, with gentle reminders. Obligations live in org Assignments. The hobbyist path and the workhorse path are different paths.
2. Care-request routing uses Open311 where available and explicit "city not notified" labeling otherwise. Hazards always redirect to 311. Fake "routed to the city" copy never ships.
3. Measurement rigor: rough estimates are always accepted, the method flag is required per field, and consumers can filter. Submission is never blocked.
4. Privacy: reduced-precision public GPS near homes, EXIF consent at upload, and no public user location history.
5. Launch: one city deep (SF). Org partnerships like FUF are the Phase 2 engine and require depth rather than breadth. The NYC dataset stays import-ready as proof of generality.

## 9. Remaining open questions

1. Which anchored crown and vitality rubric, exactly? Adopt USFS urban FIA crown classes wholesale, or a simplified five-class derivative validated against them? This needs an urban forestry advisor and must be decided before Phase 1 data collection.
2. Open311 coverage and quality vary by city. SF's practical rail may be an SF311 case API adapter rather than generic GeoReport. Scope this per launch city.
3. How much of the species field guide content can be licensed or sourced openly (from existing flora databases, for example) versus authored?
4. Community-layer add-a-tree in Phase 1: keep it, or defer to Phase 2 if the verification machinery slips? The current call is to keep it, fenced.

## 10. What changed in v2 (critique to revision)

| Persona | Their core complaint | Change made |
|---|---|---|
| Enthusiast | "You're treating me as a free sensor, and learning is buried in Phase 3." | Split the ten-second, no-judgment Visit from the structured check-in. Moved "What tree is this?", species pages, ID tips, collections, and shareable cards to Phase 1. Phenology notifications in Phase 2. The profile leads with story and demotes stats. The success metric is weekly return rather than observation count. |
| Volunteer | "No routes, assignments, or workdays; offline in Phase 2; six screens per tree." | Moved the offline submission queue to Phase 1. Designed Assignments, the route view, the single-card 90-second check-in, and group workday mode into Phase 2 explicitly. Added CareLog ("watered") to the Phase 1 data model. Added the Org coordinator role and dashboard. Made forms age-adaptive with young-tree hardware first. Adopted the never-block-submission principle. |
| City worker | "A parallel triage queue nobody will watch, hazard liability, and seed data that rots." | Routing before queue: Open311 integration, honest "city not notified" labeling, and a hard hazard redirect to 311. Scheduled re-import with a merge policy and a removed-tree state in Phase 1. Care-request duplicate clustering with reporter notifications. Trust-tiered verification with auto-accept, anomaly flags, and batch operations. Export keyed on external_ref pulled to Phase 1. A data governance, FOIA, and exit-plan section. Add-a-tree fenced in the community layer. Gamification gated and org-scoped. |
| Professor | "Unanchored ratings, no lifecycle, no method metadata, licensing as an afterthought." | An anchored vitality rubric with reference photos in Phase 1. A tree status lifecycle (alive through removed and replanted, with lineage-linked UUIDs). Per-field method and unit metadata with canonical SI and range validation. Multi-stem DBH. Species IDs as versioned, confidence-scored assertions. Observer competency and calibration tasks. Photo shot types and phenology tags. License, stable IDs, and the export schema declared in Phase 1. |

## 11. What changed in v3 (adversarial review to revision)

Five reviewers were briefed to attack rather than advise: a bearish seed investor, a jaded principal designer, a city arborist on a data governance board, a gamification skeptic, and a staff engineer told an LLM would build the app from these documents. The full findings and the numbered decisions (D1 to D15) are in ADVERSARIAL-REVIEW.md. The strategy-level changes:

The value proposition sharpened to the thing no city app will ever build. The official city tree map will always win at being official. Cypress wins at the personal and temporal layer: longitudinal, framing-consistent photo timelines of individual trees, growth records with method metadata, and the relationship between a neighborhood and its trees. Positioning, screens, and copy now commit to that instead of gesturing at civic reporting the app cannot yet deliver.

The wedge moved up. The org steward loop (assignments, batch check-ins, the next-tree flow, coordinator export) is the one use case that works with ten users, so it moved from Phase 2 into a Phase 1.5 that starts as soon as the walking skeleton stands, piloted with one partner org. The enthusiast layer launches into a map already carrying fresh steward data.

The leaderboard is dead. Ranked counts of photos, check-ins, care, and favorites paid users to spam the record and would have poisoned the health time series at the source. Its replacement, the neighborhood almanac, notices trees instead of scoring people, and the only directed ask in the app points at coverage gaps: young trees nobody has visited.

Retention got a mechanism instead of a hope. Phenology notifications (your tree's bloom window, the spring flush) moved into Phase 1, because they are the one trigger that gives a tree a reason to summon a person back.

The funnel stopped fighting itself. First saves are anonymous and local to the device; the account ask, with a one-sentence license consent, waits for the third save when there is something to lose.

Money has a position. The consumer layer is free forever. The org coordinator tier is the paid product, priced for nonprofit budgets, and the pilot org's willingness to convert is treated as a design-stage experiment with a written outcome.

Data trust got teeth. Every observation carries a verification state; the open export stamps unverified citizen rows as unfit for inventory ingestion until the verification tier ships; hazards can never become public notes; and estimated versus taped values never share a chart line.

The mock set now tells the truth. The day-one cold profile, the account ask, the measure sheet, the outbox, and the next-tree flow are mocked (screens 14 to 18), the vitality scale shows its anchor photos, phenology surfaces are species-aware so an evergreen never shows fall color, and BUILD-PLAN.md enumerates every remaining screen state as a build requirement.
