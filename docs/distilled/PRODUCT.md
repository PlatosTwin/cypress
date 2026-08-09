# Cypress — Distilled Product Reference

Sources: `DESIGN.md` (v3) and `SPEC-PHASE1.md` (written against DESIGN v2; some points superseded — see §11 Conflicts).
DESIGN.md states that `BUILD-PLAN.md` is the implementation authority where documents disagree. Persona critiques live in `CRITIQUES.md`; adversarial findings and numbered decisions D1–D15 live in `ADVERSARIAL-REVIEW.md`.

---

## 1. What the product is

Mobile + web app for cataloging urban trees, tracking their health over time, and connecting the people who care about them: casual enthusiasts, volunteer stewards, city forestry staff.

Five pillars:

| Pillar | Content |
|---|---|
| Living catalog | Every tree has a profile: species, location, planting date, size, photo timeline across seasons/years |
| Learning surface | Every profile doubles as a field guide entry; "what tree is this?" answerable from day one using seeded city data |
| Two-speed contribution | Anyone logs a 10-second **Visit** (photo + optional note). Trained **Stewards** on assigned blocks do structured check-ins and care logs |
| Community layer | Favorite, adopt, share, report — with *honest routing* that never claims the city was notified when it wasn't |
| AI later | Photo timelines could eventually feed growth estimates and health flags. Out of scope now; design only avoids blocking it (original-resolution photos, standardized shot types, method-tagged measurements) |

**Sharpened positioning (v3):** the official city tree map will always win at being official. Cypress wins the **personal and temporal layer**: longitudinal, framing-consistent photo timelines of individual trees; growth records with method metadata; the relationship between a neighborhood and its trees. Positioning, screens, and copy must commit to that rather than gesture at civic reporting the app cannot yet deliver.

**Launch scope:** one city deep — San Francisco. NYC dataset stays import-ready as proof of generality. Org partnerships (e.g. Friends of the Urban Forest / FUF) are the Phase 2 engine and need depth, not breadth.

**Money:** consumer layer is free forever. The **org coordinator tier is the paid product**, priced for nonprofit budgets. The pilot org's willingness to convert is a design-stage experiment with a written outcome.

### Design principles

1. **Appreciation first, data second.** Phase 1 success metric is weekly enthusiast return rate, not observation counts.
2. **Never block a submission.** Every field beyond a photo is optional. Rough estimates always accepted, but every quantitative value carries a *required* method flag (measured vs estimated) — rigor recorded, not enforced.
3. **Honest routing.** Never display "sent to the city" unless a real integration confirmed receipt. Hazards redirect to 311.
4. **Cheap now, ruinous to retrofit → Phase 1:** data license, stable IDs, anchored rating rubrics, units, tree lifecycle states, export schema.
5. **Design to a time budget.** Visit ≤10 s. Care log ≤30 s. Full steward check-in on a healthy tree ≤90 s. (Light check-in target ≤60 s.)

### Non-goals / anti-patterns (explicitly NOT to build)

| Do not build | Rationale as stated |
|---|---|
| **Leaderboards or ranked counts** of photos/check-ins/care/favorites | Pays users to spam the record, poisons the health time series at the source. "The leaderboard is dead." |
| **Individual streaks** or any volume-incentivizing individual gamification | Same |
| Any gamification before Phase 3, and then only org-scoped crew totals ("your crew logged 214 trees this season") with scored contributions gated behind verification | — |
| **Fake "routed to the city" copy** | Never ships. |
| **Hazard/emergency reports accepted in-app** | Liability + false assurance. Hard redirect to 311 / emergency services. |
| **A raw staff inbox / parallel triage queue** | Nobody will watch it. Verification uses trust tiers, anomaly flags, sampling, batch verify. In-app staff triage exists *only* for onboarded departments. |
| **Dashboards as the city/researcher adoption path** | Export is the real adoption path; dashboards are not. |
| **Login walls on browse** | Browsing requires no account. |
| Community-added trees shown as official inventory | Community layer is visually distinct and never displays as official until verified. |
| Public user location history | Never. |
| Mixing estimated and taped values on one chart line | Never share a chart line. |
| Hazards becoming public notes | Hazards can never become public notes. |
| Six-screen-per-tree wizards | Check-ins are a single scrollable card, not a step wizard. |
| Unverified citizen rows silently entering city inventory | Open export stamps them unfit for inventory ingestion until the verification tier ships. |
| Step wizards / judgment on the Visit path | Visit is "no judgment required". |

---

## 2. Users and roles

| Role | Who | Primary actions |
|---|---|---|
| Explorer (no account) | Passerby, curious walker | Browse map, "what tree is this?", read profiles + photo timelines, species pages |
| Member | Registered enthusiast | Visits (photo + note), favorites, adopt, species collections, share trees, care reports |
| Steward | Trained volunteer, org-affiliated | Assigned routes, batch check-ins, care logs, structured health observations |
| Org coordinator | Volunteer lead at a nonprofit (e.g. FUF) | Create assignments, run workdays, review crew activity, weekly digests, CSV export |
| City staff | Municipal forestry / public works | Inventory sync, verification triage, care request queue (if onboarded), data round trip |
| Admin | Cypress operators | Moderation, org onboarding, species DB, import pipelines |

- Roles are **per organization**. A user can be a plain Member globally and a Steward within "Friends of the Urban Forest."
- **Observer competency:** beyond roles, each user carries per-protocol training records (e.g. "completed DBH calibration", "crown-rating trained") earned through in-app calibration tasks (re-measuring reference trees, agreement checks). Researchers and staff can filter or weight data by observer competency rather than role alone.

---

## 3. Domain concepts

### Tree

| Field | Definition / rules |
|---|---|
| `id` | Immutable UUID that persists through death, removal, and replanting. Stable and citable from day one. |
| `status` | Enum verbatim: `alive \| declining \| dead_standing \| removed \| stump \| vacant_site`. Plus `status_date`, `status_cause` (cause when known). Enables survival analysis. |
| `provenance` | `city_inventory \| community` — displayed distinctly. |
| `species_ids[]` | Versioned **assertions**, not a flat pointer. |
| `location` | lat/lng + address + site type (sidewalk cut, park, median). Postgres `geography(point)`. |
| `external_ref` | City inventory ID (+ `external_source`, e.g. `sf_dpw`) + `last_synced_at`. |
| `site_lineage` | UUID reference to the prior tree at a replanted site — links old tree to new tree. |
| Children | Visits[], Observations[], CareLogs[], CareRequests[], Photos[], Adoptions[], Favorites[] |

### Species assertion

Versioned assertion object: `taxon_rank ∈ ('species','genus','unknown')` (genus-only and "unknown" allowed), `species_id` nullable, `confidence ∈ ('certain','likely','guess')`, `source ∈ ('city_import','user','staff')`, `asserted_by`, `asserted_at`, `superseded_by`. Full ID history preserved on correction; corrections never silently overwrite. Consensus model referenced to iNaturalist's research-grade flow. Also carries `identified_by` / `confirmed_by[]` semantics.

### Visit

Lightweight "I was here": photo + optional note. ≤10 s. Fields: `tree_id`, `user_id`, `note`, optional `phenology_tag`, `created_at`, `client_created_at`. Offline-queueable. Appears in the tree timeline and the user's journal.

### Observation (structured check-in)

Steward-oriented, 90-second target (light member version targets 60 s). Carries observer + their training records *at time of entry*, timestamp.

- Every quantitative field carries: `value`, `unit_entered` (canonical SI stored), `method ∈ taped | caliper | laser | visual_estimate`, and range validation on entry.
- `stems[]`: diameter per stem + measurement height (multi-stem convention documented; combined DBH derivable).
- `height_est`, `canopy_spread`.
- Crown: condition class per anchored rubric, dieback %, foliage density / discoloration / damage.
- Structure: lean, broken limbs, trunk wounds, root heave.
- Site: soil compaction, mulch depth, water basin state, hardware (stake condition, tie girdling). The young-tree form surfaces these first — **the form adapts to tree age**.
- Vitality: anchored 1–5 rubric (see below), reference photo per class shown inline at rating time.
- `photos[]`, free-text notes.
- v3: **every observation carries a verification state.**

### Care log

Care performed. Chip toggles, ≤30 s, offline-capable. Phase 1 action set (verbatim): **watered, mulched, weeded basin, litter cleared, other (free text)**. Data-model wording elsewhere: "watered, mulched, weeded, stake removed". Optional photo, optional note.

### Care request / community note

- Types: `watering / pruning / pest / disease / damage / hardware / vandalism`.
- **Hazard and emergency types are NOT accepted in-app** — user is redirected to call 311 or emergency services immediately.
- Fields: severity, description, photos.
- Routing states verbatim: `unrouted` ("visible to community and org only; the city has NOT been notified") | `routed_311` (Open311 ticket # echoed back) | `routed_org` | `acknowledged` | `scheduled` | `resolved` | `declined`.
- **Duplicate clustering:** same-tree, same-type reports merge into one cluster; every reporter is notified on resolution.
- Phase 1 storage is `community_notes` with `status ∈ ('open','resolved','stale')`; notes go **stale automatically after 90 days without activity**.

### Photo

- Original retained (EXIF timestamp/GPS with consent) + derived web sizes.
- `shot_type`: `full_tree | trunk_dbh | canopy_up | leaf_closeup | site`.
- `phenology_tag`: `leaf_out | full_leaf | fall_color | bare | flowering | fruiting`.
- **Ghost-overlay capture** aids angle/framing consistency over time (last full-tree photo at 30% opacity).
- `moderation_state`, `gps_consent`.

### Vitality scale (anchored rubric, draft v0 — needs urban forestry advisor sign-off before launch)

Five classes, each with reference photos shown inline at rating time. Simplified derivative of USFS urban crown-condition classes; mapping to the source protocol documented in the export schema.

**These five anchor sentences are not the handoff transcription — they are the owner's decision on ticket #261**, and they are the one place this document departs from `SPEC-PHASE1.md` §6 deliberately (§11 conflict 23). The sentences below, the identical table in `SCREENS.md` 05 §3 and `Vitality.anchor` were landed together, closing a fork that had stood since both documents were distilled: `SPEC-PHASE1.md` §6 and the design export stated the rubric copy differently, and neither distilled document was wrong. **RULINGS R70, the #261 ruling on the vitality rubric, quotes both superseded tables verbatim in its §0**, so a transcription check that finds `SPEC-PHASE1.md` §6 disagreeing with the table below has found the intended state rather than drift. `CypressTests/VitalityRubricTests.swift` asserts that this table, `SCREENS.md` 05 §3 and `Vitality.anchor` still state the same five sentences, so the agreement is enforced rather than merely recorded. RULINGS R13's split stands — `SCREENS.md` owns screen copy, this document owns a class's meaning, and a dieback band is meaning.

| Class | Label | Anchor (plain language) | Dieback band |
|---|---|---|---|
| 5 | Thriving | No dead wood visible; canopy full for the season | 0% |
| 4 | Good | 1 to 10% of the crown is dead wood; canopy otherwise full | 1–10% |
| 3 | Fair | 11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf | 11–25% |
| 2 | Poor | 26 to 50% of the crown is dead wood or bare; large dead sections | 26–50% |
| 1 | Severe decline | Over half the crown is dead wood or bare in season; major limbs dead | 51–100% |

The bands partition the whole percents 0–100 exactly once, which the draft-v0 table did not: 0% and 25% each named two rows. The scale is a documented collapse of the seven i-Tree / Nowak classes (excellent → 5, good → 4, fair → 3, poor → 2, critical + dying → 1); their `dead` class is not a vitality class here but the `Appears dead` status segment.

**Still draft v0.** The decision did not discharge this section's own "needs urban forestry advisor sign-off before launch", did not close §2.5 P-C1 in `DECISIONS.md`, and did not move ERRATA E30 — the five per-class reference photographs remain the M2 entry gate and do not exist. What the advisor is being asked to underwrite is listed in RULINGS R69 §5, restated in R70 §3.

**Seasonality rule:** deciduous species are rated only in leaf-on season. The app suppresses the vitality UI off-season using species leaf phenology; structure flags remain available year-round. Phenology surfaces are species-aware — an evergreen never shows fall color.

### Species (field guide entry, not a footnote)

Common + scientific names, ID tips with photos ("look for the fan-shaped leaves"), seasonal highlights ("what to look for this month"), care notes, count (and map) of others nearby. Powers learning surfaces and species collections. Schema: `id_tips jsonb`, `seasonal jsonb`, `care_notes jsonb`, genus, family.

### Grove / favorites / collections / journal

- **My Grove**: adopted + favorited trees, care reminders, species collection progress, "your year with the trees."
- **Adoption is symbolic**, with gentle reminders. Obligations live in org Assignments. Hobbyist path ≠ workhorse path. (Adoption itself is Phase 2.)
- **Collections**: species progress — "N of M species in your area", per-species tiles with seen/not-seen and first-seen date, progress ring. New species → celebratory card. Learning disguised as collecting. Framed as "12 of 40 neighborhood species spotted".
- **Journal**: chronological photo diary of all my visits with monthly headers.

### Org concepts (Phase 1.5 / 2)

- **Organization** → `Membership(role, training_records[])` → User; owns `Assignments[]`, `WorkSessions[]`, manages Trees.
- **Assignment**: (steward, tree_list/route, due_window) — e.g. "18 trees, Oak St 400 to 600 block", walked top to bottom with checkmarks.
- **Workday / WorkSession**: group mode with live claimed/done status per tree and same-day dedupe.
- **Trust tiers**: auto-accept from credentialed Stewards of partner orgs; anomaly flags (a DBH that shrank gets flagged); sampling; batch verify.

### Memorial record / site lineage

A city-removed tree gets `status='removed'`; community photos and history stay on the profile, which becomes a **memorial record rather than a 404**. A removed tree's profile becomes **read-only with a memorial banner**. Replanting at the same site creates a new tree UUID linked to the old via `site_lineage`.

### Outbox

Local SQLite (Expo) holds a bounded map-region browsing cache plus an outbox table. Every mutation (visit, photo, care log, check-in, favorite) is written locally first with `client_created_at` + client UUID, then synced FIFO with retry and backoff. Photos stay on device until upload confirmed; **wifi-only upload toggle**. Contributions are append-only → no merge conflicts; the server dedupes on client UUID, making sync idempotent. The outbox is **visible in the UI ("3 items waiting to sync") and never gets silently stuck**.

### Neighborhood almanac

Replacement for the killed leaderboard. **Notices trees instead of scoring people.** The only directed ask in the app points at coverage gaps: **young trees nobody has visited.**

---

## 4. Phasing

### Phase 1 — "the living map and the ten-second visit"

Success metric: weekly return rate of enthusiasts, and zero data loss in the field.

In scope: map browse; tree profiles; species field guide; "what tree is this?"; visits; favorites; species collections; shareable tree pages; quick care log; light check-in with anchored rubric; offline outbox; SF data seed with recurring sync + merge policy + lifecycle states; add-a-tree (community layer, fenced pending verification); accounts; share cards; moderation basics; documented export; data license + stable UUIDs; hazard redirect. Phenology notifications pulled into Phase 1 in v3 (see Conflicts).

Out (Phase 2+): orgs, assignments, routes, group workdays, full structured observations (multi-stem DBH etc.), Open311 routing, staff and coordinator dashboards, verification workflows, adoption and reminders, area download, anything AI.

Phase 1 success metrics (SPEC):
- Week-4 retention of registered members ≥25%; median ≥2 visits per active member per week.
- Zero field data loss: every queued submission eventually syncs or surfaces a recoverable error.
- ≥60% of visits attach a photo; ≥80% of "what tree is this?" sessions end on a tree profile.

### Phase 1.5 (v3 addition)

The **org steward loop** (assignments, batch check-ins, next-tree flow, coordinator export) is the one use case that works with ten users. It moved out of Phase 2 into a Phase 1.5 starting as soon as the walking skeleton stands, piloted with one partner org. The enthusiast layer launches into a map already carrying fresh steward data.

### Phase 2 — stewardship and organizations

Success metric: a volunteer completes a 20-tree Saturday route entirely in-app, and the org lead never asks for the spreadsheet again.

Org affiliation + Steward role + Org coordinator dashboard; assignments and routes; single-scrollable-card batch check-in (big tap targets, "same as last visit" defaults, skip-anything, 90 s/tree); group workday mode; full structured observation (multi-stem DBH with method metadata, measurement guidance, age-adaptive forms); observer calibration tasks; care requests with routing-before-queue (Open311/GeoReport where available, real ticket echoed back, explicit "city has NOT been notified" otherwise, duplicate clustering, reporter notification on resolution; in-app staff triage only for onboarded departments); verification that scales (trust tiers, anomaly flags, sampling, batch verify — no raw inbox); adoption ("my grove") with reminders + seasonal phenology notifications; personal journal; full offline field mode (area tiles + tree data download); AI species suggestion from photos (pulled forward from Phase 3 as the well-understood, proven problem).

### Phase 3 — intelligence and openness

AI photo analysis (health flags, growth estimation from standardized timelines); trends/analytics (neighborhood canopy health, survival rates by species and site); public API + researcher portal with competency-filtered datasets; gamification carefully (org-scoped crew totals only, gated behind verification, no individual streaks); additional cities and city-push delta sync.

---

## 5. Screens and behavior rules

### Mobile

#### M1. Map home
- Full-bleed map. **Pin color follows tree status**: green = alive, amber = declining, gray = dead or removed (gray shown *only when that filter is on*). Community-layer trees get an **outlined, dashed pin**.
- **Clustering above zoom 16**, count badge per cluster.
- Top bar: search by species, street, or neighborhood. Filter chips: species, in bloom (from species seasonal data), recently visited, community-added. (DESIGN also lists "needs care".)
- Primary FAB: **"What tree is this?"**. Long press expands secondary actions: visit nearest, add a tree. (DESIGN wording: Visit and Report behind a long press.)
- Tapping a pin → bottom-sheet preview (photo, name, distance, last visit) that expands to full profile.
- Cold start under 2 s; locate-me; no login wall.

#### M2. "What tree is this?"
- One tap from the map. Full-screen list, **nearest first, up to 8 trees**, with big thumbnails, species + common name, and distance ("6 m NE").
- **Confidence hinting:** if the top candidate is within 3 m and the next is ≥10 m away, the top card is highlighted automatically.
- Works at roughly 10 m GPS accuracy; graceful **low-GPS-accuracy state** (prompt to step away from buildings, or browse the map instead). Empty state specified.
- Footer: **"None of these? Add this tree."**
- Tapping a row opens the profile.

#### M3. Tree profile (mobile) — story before stats
1. **Hero**: best photo + season strip (12 thumbnails, one per month where photos exist).
2. **Identity**: common name (large), scientific name, ID-tips accordion ("How to recognize it"), status badge.
3. **Actions**: Favorite, Share, Visit, Care log, Report. (DESIGN also lists Adopt — Phase 2.)
4. **Timeline**: reverse-chronological feed of visits, photos, care logs, check-ins; filterable.
5. **Details (below the fold)**: height, DBH with its **method badge**, planting date, site type, city ID, provenance label ("SF city inventory" vs "community-added, unverified"). Health badge, last check-in.
6. **"Nearby of the same species"** strip linking to the species page.
- Tabs (DESIGN): Story, Details, Care history.
- Day-one **cold profile** state (a tree with no photos/visits yet) is an explicit mocked state.

#### M4. Visit sheet (≤10 s)
- Launch opens the **camera immediately**, with graceful permission handling.
- **Ghost overlay**: last full-tree photo at 30% opacity + shot-type hint chip.
- After shutter: photo preview → optional one-line note → optional **phenology quick-tag suggested from month + species** → submit.
- Offline: **submit always succeeds locally**; the card shows a "will sync" glyph.

#### M5. Care log (≤30 s)
- Chip toggles: watered, mulched, weeded basin, litter cleared, other (free text). Optional photo, optional note, submit. Works offline.

#### M6. Light check-in (one scrollable card, not a step wizard; ≤60 s)
1. **Status**: alive, declining, appears dead, appears removed. The last two **trigger a review flag and a confirmation dialog**.
2. **Vitality**: five anchored classes, each with reference photo + one-line anchor, tap to select. Suppressed off-season for deciduous species.
3. **Foliage**: density (full, thinning, sparse, bare in season); discoloration (none, some, severe); damage (none, chewed, spotted, scorched).
4. **Structure quick-flags**: lean, broken limb, trunk wound, root heave, hardware issue.
5. Photos and a note.
- **Everything can be skipped; only status has a default (alive).**

#### M7. Report (community note)
- **Category picker.** Hazard categories — *hanging or broken limb over a path, uprooted, struck by vehicle, blocking a signal or sightline* — route to a full screen: **"This may be a public-safety hazard. Call 311."** with tap-to-call and a secondary "also pin a community note."
- Non-hazard categories (needs water, pest suspected, hardware, vandalism) collect severity, photo, note → post as a pinned community note labeled: **"Community-reported. The city has not been notified."**
- Hazard content can never become a public note.

#### M8. My Grove and Journal
- Tabs: **Trees** (favorites grid with last photo + species), **Journal** (chronological photo diary of my visits, monthly headers), **Collections** (species progress ring; per-species tiles showing seen/not-seen and first-seen date).

#### M9. Onboarding and account
- First launch: **location permission prompt with purpose copy**, then straight to the map.
- Account required at the first save action (favorite or visit) per SPEC; v3 moves the ask to the **third save** with first saves anonymous and local to the device (see Conflicts).
- Account sheet: Apple, Google, email. Display name + optional avatar. **Contribution license consent**: checkbox with a plain-language summary and a link (v3: a one-sentence license consent).

#### M10. Route view (Steward — Phase 1.5/2)
Assigned list ordered by walk with checkmarks; per-tree single-card check-in: care-performed toggles at top, rubric-anchored condition ratings with reference photos inline, optional measurements with a **method picker**, big glove-friendly targets, "same as last visit" prefill. Includes an explicit **next-tree flow** and a **measure sheet**.

### Web

| # | Screen | Content |
|---|---|---|
| W1 | Explore | Map + browse, species field guide index, neighborhood pages (canopy stats, top species, recent photos), photo galleries |
| W2 | Tree page (public, shareable, no login) | Hero, season strip, timeline, details, map inset, auto-rendered OpenGraph share-card image |
| W3 | Species page | Full field-guide entry + city map of individuals |
| W4 | Account pages | Journal and collections mirroring the app |
| W5 | Export page | Per-city dataset downloads (CSV + GeoJSON), schema docs, license text, changelog |
| W6 | Coordinator dashboard (org, Phase 1.5/2) | Create assignments, watch workdays live, review crew activity, set weekly digests, one-click weekend CSV export |
| W7 | Staff dashboard (city, onboarded only, Phase 2) | Care-request **clusters** rather than raw reports, verification triage with anomaly flags, batch verify, trust tiers, inventory sync conflict review, export keyed on `external_ref` |
| W8 | Tree profile (web) | Full observation history with **method and observer filters**, side-by-side photo comparison across time |

Mocked screens 14–18 (per v3): day-one cold profile, the account ask, the measure sheet, the outbox, the next-tree flow. `BUILD-PLAN.md` enumerates every remaining screen state as a build requirement.

---

## 6. Data schema (Phase 1, Postgres + PostGIS sketch)

```sql
users(id uuid pk, auth_provider, display_name, created_at, license_consent_at)
species(id pk, scientific_name, common_name, genus, family,
        id_tips jsonb, seasonal jsonb, care_notes jsonb)

trees(id uuid pk,                      -- immutable, citable
      status tree_status not null default 'alive',
      status_date, status_cause,
      provenance enum('city_inventory','community') not null,
      location geography(point) not null,
      address text, site_type enum(...),
      external_ref text, external_source text,  -- e.g. 'sf_dpw'
      last_synced_at timestamptz,
      site_lineage uuid references trees(id),   -- replanted-site link
      created_by uuid, created_at)

species_assertions(id pk, tree_id fk, taxon_rank enum('species','genus','unknown'),
      species_id fk null, confidence enum('certain','likely','guess'),
      source enum('city_import','user','staff'), asserted_by uuid null,
      asserted_at, superseded_by fk null)        -- full ID history

visits(id uuid pk, tree_id fk, user_id fk, note text,
       phenology_tag enum null, created_at, client_created_at)
photos(id uuid pk, tree_id fk, visit_id fk null, user_id fk,
       original_key, sizes jsonb, exif_taken_at, exif_gps geography null,
       gps_consent bool, shot_type enum, phenology_tag enum,
       moderation_state enum, created_at)
care_logs(id uuid pk, tree_id fk, user_id fk,
       actions text[] check (...), note, photo_id null, created_at, client_created_at)
observations(id uuid pk, tree_id fk, user_id fk,
       status_report tree_status null,          -- "appears dead" etc: review flag
       vitality_class smallint null check (1..5),
       foliage jsonb, structure_flags text[], site jsonb,
       note text, created_at, client_created_at)
-- every numeric in jsonb carries {value, unit_entered, si_value, method}

community_notes(id pk, tree_id fk, user_id fk, category enum, severity,
       note, photo_id, status enum('open','resolved','stale'), created_at)

favorites(user_id, tree_id, created_at, pk(user_id, tree_id))
collections_progress(user_id, species_id, first_seen_at)   -- materialized

import_runs(id pk, source, started_at, finished_at, stats jsonb)
sync_conflicts(id pk, tree_id fk, kind enum('removed_but_active',
       'species_mismatch','location_moved'), city_payload jsonb,
       state enum('open','resolved'), resolved_by, resolved_at)
review_flags(id pk, tree_id fk, kind enum('reported_dead','duplicate_suspect',
       'photo_moderation'), source_id, state, created_at)
```

`tree_status`: `alive | declining | dead_standing | removed | stump | vacant_site`.

All contributions are offline-queueable and attributed per field with timestamps.

---

## 7. SF data seed and recurring sync

- **Source:** DataSF Street Tree List (DPW updates regularly). Initial import ≈190k rows → `trees` with `provenance='city_inventory'`, `external_source='sf_dpw'`, `external_ref=TreeID`.
- Species map through a curated `sf_species_map` table (city species strings → `species.id`). **Unmapped rows get a genus or unknown assertion and enter a curation queue.**
- **Weekly diff import** merge policy:
  - New city rows create trees. (New city plantings appear automatically.)
  - A city row that disappears or is marked removed sets `status='removed'` **only if the tree has no community activity in the last 30 days**; otherwise it opens `sync_conflict('removed_but_active')`.
  - A city species change creates a new `species_assertion(source='city_import')` and supersedes the prior one, keeping history. Never silently overwrites.
  - A **location delta over 5 m** opens `sync_conflict('location_moved')`.
  - Conflicts surface in a review queue rather than auto-resolving.
- **Sync never deletes community photos or visits.** A removed tree's profile becomes read-only with a memorial banner.
- Also launch-seeded/import-ready: NYC Forestry Tree Points, keyed on `external_ref`.
- Community-added trees live in a visually distinct community layer, never displayed as official city inventory until verified.

---

## 8. Offline, privacy, licensing, moderation, accounts, platform

### Offline (Phase 1)
- SQLite outbox (see §3 Outbox). Local-first writes; FIFO sync with retry + backoff; idempotent via client UUID; append-only so no merge conflicts.
- Photos stay on device until upload confirmed; wifi-only toggle.
- Outbox surfaced in UI; visits show a "will sync" glyph.
- **Area/tile download is Phase 2**, not Phase 1. Phase 1 has only a bounded map-region browsing cache.

### Privacy
- Public GPS precision reduced to roughly **25 m** for photos near residential parcels (DESIGN: "reduced precision near residential addresses for public display").
- **EXIF GPS stored only with consent** at upload.
- **No public user location history.** Display names only.
- Faces and license plates blurred on public photos.

### Licensing and export
- **License: ODbL for the database, CC-BY 4.0 for photos**, granted by contributors at signup. (DESIGN phrases it as "ODbL or CC-BY"; SPEC pins ODbL + CC-BY 4.0.) Final call awaits legal review, but the license is **declared before any data is collected**.
- Tree UUIDs stable and citable from day one.
- **Export**: nightly per-city CSV + GeoJSON. Trees: UUID, `external_ref`, current species assertion with confidence, status, location, provenance. Observations: method- and unit-tagged. Schema is versioned and documented on the export page; **i-Tree-compatible field naming where a mapping exists**; license stamped in the file header; changelog published.
- v3: export **stamps unverified citizen rows as unfit for inventory ingestion** until the verification tier ships.
- Ownership, retention, FOIA posture, and an **exit plan (full data escrow and export if Cypress folds)** are written into org onboarding terms. "Procurement will ask."

### Moderation and data quality
- Photo report flow + automated screening queue.
- Community notes go **stale automatically after 90 days without activity**.
- Duplicate detection on add-a-tree (**proximity + species**), with a warning before creating. Duplicate clustering on care requests.
- Per-field attribution and timestamps are the substrate for competency-weighted trust (not a lone verified flag).
- **When data conflicts, the most recent trusted value wins for display; full history is always retained.**
- Species IDs use assertion + consensus (iNaturalist research-grade flow as reference).
- Anomaly flags, e.g. a DBH that shrank (Phase 2 verification).

### Accounts and auth
- Email + Apple + Google sign-in. One account works everywhere. Browsing requires no account.
- Account ask deferred to a save action (first per SPEC / third per v3), carrying license consent.

### Platform / architecture
- Monorepo: Expo/React Native app (iOS + Android) + Next.js web, with a shared TypeScript core (types, validation with canonical units, API client).
- Mobile = field/walk tool (map, visits, check-ins, offline). Web = depth tool (rich profiles, species guide, coordinator/staff dashboards, import/export).
- Backend: Postgres + PostGIS (spatial queries, neighborhood rollups), object storage for photo originals and derived sizes, background jobs for city-dataset sync and Open311 submission/status polling.
- Integrations: **Open311 GeoReport v2** as the standard care-request rail; per-city adapters (Cityworks, Cartegraph) only for onboarded departments.

### Non-functional requirements
- **Performance**: map cold start <2 s; pins via vector tiles or a clustered GeoJSON endpoint; photo upload backgrounded.
- **Accessibility**: WCAG AA; all field UI usable one-handed; tap targets ≥44 pt; high-contrast map style option for bright sunlight.

---

## 9. Copy and voice rules

- Story before stats: profiles lead with photo + season strip; stats sit below the fold.
- No judgment on the Visit path; "no judgment required."
- Never imply city notification without confirmed receipt.
- Phenology copy is species-aware (never offer fall color for an evergreen).
- Plain-language license summary at the account ask (v3: one sentence).
- Location permission prompt carries purpose copy.

Exact user-facing strings given in the docs:

| String | Where |
|---|---|
| "What tree is this?" | Primary FAB / screen title |
| "None of these? Add this tree." | Footer of the "what tree is this?" list |
| "How to recognize it" | ID-tips accordion on tree profile |
| "6 m NE" | Distance format on nearby list |
| "This may be a public-safety hazard. Call 311." | Full-screen hazard interstitial |
| "also pin a community note" | Secondary action on hazard screen |
| "Community-reported. The city has not been notified." | Label on pinned non-hazard community notes |
| "Visible to community and Friends of the Urban Forest; the city has not been notified." | Report routing status, unrouted |
| "visible to community and org only; the city has NOT been notified" | `unrouted` routing state definition |
| "Open311 ticket #4711" | Report routing status, routed (example ticket number) |
| "3 items waiting to sync" | Outbox indicator |
| "will sync" glyph | Offline-submitted card |
| "N of M species in your area" / "12 of 40 neighborhood species spotted" | Collections |
| "your year with the trees" | Journal |
| "my grove" | Adopted + favorited trees |
| "this tree appears dead or removed" | Status option in light check-in |
| "appears dead" / "appears removed" | Check-in status choices |
| "SF city inventory" vs "community-added, unverified" | Provenance label on profile |
| "look for the fan-shaped leaves" / "fan-shaped leaves" | Species ID-tip example |
| "what to look for this month" | Species page seasonal section |
| "18 trees, Oak St 400 to 600 block" | Assignment label example |
| "same as last visit" | Prefill control on steward check-in |
| "your cherry blooms around this week" | Phenology notification example |
| "your crew logged 214 trees this season" | Org-scoped crew total (Phase 3) |
| "low GPS accuracy" | Degraded-state label |

---

## 10. Decisions already made (do not relitigate)

1. Adoption is symbolic with gentle reminders; obligations live in org Assignments.
2. Care-request routing: Open311 where available; explicit "city not notified" otherwise; hazards always redirect to 311; fake routing copy never ships.
3. Measurement rigor: rough estimates always accepted; method flag required per field; consumers can filter; submission never blocked.
4. Privacy: reduced-precision public GPS near homes; EXIF consent at upload; no public user location history.
5. Launch one city deep (SF); FUF-style org partnerships are the Phase 2 engine; NYC stays import-ready.
6. Leaderboards killed; neighborhood almanac replaces them.
7. Phenology notifications are the retention mechanism.
8. Consumer free forever; org coordinator tier is paid.

---

## 11. Open questions / underspecified

From the docs' own open-questions list:

1. **Which anchored crown/vitality rubric exactly** — adopt USFS urban FIA crown classes wholesale, or the simplified five-class derivative validated against them? Needs an urban forestry advisor; must be decided before Phase 1 data collection. The five-class table in §3 is explicitly "draft v0, needs sign-off."
2. **Open311 coverage/quality varies by city.** SF's practical rail may be an SF311 case API adapter rather than generic GeoReport. Scope per launch city.
3. **Species field-guide content sourcing** — how much can be licensed/sourced openly (existing flora databases) vs authored?
4. **Community-layer add-a-tree in Phase 1** — keep, or defer to Phase 2 if verification machinery slips? Current call: keep, fenced.

Conflicts and gaps found between the two documents (SPEC-PHASE1 was written against DESIGN v2; DESIGN v3 supersedes in several places; `BUILD-PLAN.md` is the stated tiebreaker):

5. **Account-ask timing.** SPEC §3.9: account required at the *first* save action. DESIGN §11: first saves are anonymous and local to the device, account ask waits for the *third* save. Unresolved: how anonymous local contributions are attributed/migrated on eventual signup.
6. **Phenology notifications phase.** DESIGN §4 lists them in Phase 2; DESIGN §11 moves them into Phase 1; SPEC lists "adoption and reminders" as out of scope. Notification delivery mechanics, opt-in, and per-species bloom-window data source are unspecified.
7. **Phase 1.5 contents vs SPEC "Out" list.** SPEC excludes orgs/assignments/routes/workdays/coordinator export; DESIGN v3 pulls exactly those into Phase 1.5. Milestones M0–M4 do not include Phase 1.5.
8. **Neighborhood almanac is named but never specified** — no screen, data model, or placement.
9. **Verification state on every observation** (v3) has no enum, no schema field in the SPEC `observations` table, and no defined transitions; the export "unfit for inventory ingestion" stamp has no defined field name.
10. **Care-log action vocabulary differs**: DESIGN "watered, mulched, weeded, stake removed" vs SPEC "watered, mulched, weeded basin, litter cleared, other".
11. **Map filter chips differ**: DESIGN adds "needs care"; SPEC lists species / in bloom / recently visited / community-added. With no Phase 1 care-request queue, the meaning of "needs care" is undefined.
12. **Tree profile actions differ**: DESIGN includes Adopt in Phase 1 screen sketch; SPEC omits it and puts adoption in Phase 2.
13. **License**: DESIGN says "ODbL or CC-BY" for data; SPEC pins ODbL for data + CC-BY 4.0 for photos; both flag pending legal review. Which applies to derived/aggregate exports is unstated.
14. **`sync_conflicts.kind` includes `species_mismatch`** but the merge policy never describes when it is raised (species changes are said to supersede automatically).
15. **Site lineage semantics** are unspecified beyond the FK: who creates the link, whether it is manual or import-driven, and how it displays.
16. **Light check-in vs Observation**: whether the Phase 1 light check-in writes to the same `observations` table as the Phase 2 structured observation (schema suggests yes) and how partial rows are distinguished.
17. **Review flags** (`reported_dead`, `duplicate_suspect`, `photo_moderation`) have no Phase 1 reviewer UI — no admin surface is specified, though moderation is in Phase 1 scope.
18. **Species collection scope** ("in your area") is undefined — no radius, neighborhood, or city boundary rule for M in "N of M".
19. **Gray pins for dead/removed are shown only when that filter is on**, but no such filter chip is listed in the filter set.
20. **Observer competency / training records** are declared as a core concept but have no Phase 1 schema (`users` has no training records) and no calibration UI before Phase 2.
21. **Photo `shot_type` selection** is never specified as a user action in the Visit flow (only a "shot-type hint chip"), so how shot_type gets set is undefined.
22. **Offline favorites** are listed as outbox mutations, but favoriting is also the account-gate trigger — behavior for an anonymous offline favorite is undefined.
23. **The rubric's anchor sentences differed between the two handoff artifacts, and no longer follow either.** `SPEC-PHASE1.md` §6 and the `Cypress Screens.dc.html` design export stated all five differently, from the day both were distilled; §3 here transcribed the first and `SCREENS.md` 05 §3 the second, both faithfully. Resolved on ticket #261: the owner's approved sentences replace both, in §3, in `SCREENS.md` 05 §3 and in `Vitality.anchor` together, and RULINGS R70 quotes both superseded tables. This is a resolved conflict, recorded here because §3 is now the only section of this document that departs from its source on purpose. Item 1 above — *which* rubric — is a different question and stays open.
