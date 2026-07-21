# Cypress build plan

This is the document a future coding agent builds from. It exists because an adversarial buildability review found that DESIGN.md and SPEC-PHASE1.md, good as product documents, left too much for an implementer to invent: no API contract, no ingest mapping, undefined entities, and a stack of ambiguities where two reasonable engineers would build different things. Everything the review demanded is resolved here.

Precedence when documents disagree: BUILD-PLAN.md wins, then SPEC-PHASE1.md, then DESIGN.md. The decision numbers cited throughout (D1 to D15) are defined in ADVERSARIAL-REVIEW.md.

## 1. What we are building, in one paragraph

A mobile app (Expo, React Native, TypeScript) and a web app (Next.js) over one backend (Node, Postgres with PostGIS). The map is seeded with the full SF street tree inventory so day one is alive. Enthusiasts photograph and revisit individual trees, building longitudinal photo timelines; volunteers run light health check-ins and simple measurements with method metadata on every number; orgs get a steward loop (assignments, batch check-ins, export) early, because that is the wedge that works with ten users. There are no leaderboards (D1). Reports of hazards redirect to 311 and never pretend otherwise.

## 2. Sequencing and the wedge

Build order inverts the original phasing per D13. Each milestone in section 12 maps to this ladder.

1. Walking skeleton: real DataSF import runs end to end, map renders live clustered pins from it, one tree profile loads, one visit round-trips through the offline outbox to Postgres and appears on the public web tree page.
2. Phase 1 core: visits with photos, check-ins, measurements, favorites, outbox, cold profiles, account flow, species pages for the curated list, moderation basics, nightly export.
3. Phase 1.5 org loop, started as soon as the skeleton stands and piloted with one partner org: org entity, assignments, the next-tree flow (screen 18), coordinator CSV export. This is also the paid tier (D14).
4. Enthusiast layer polish: collections, almanac, journal, share cards, phenology notifications (D10).

## 3. Stack decisions

These are decided, not suggestions. Do not substitute without a written reason.

| Concern | Decision |
|---|---|
| Mobile | Expo (React Native), TypeScript, expo-router. Local store is SQLite via expo-sqlite. |
| Web | Next.js (app router), TypeScript. Public tree pages are server-rendered and need no login. |
| Backend | Node 22, Fastify, TypeScript. One service. Background jobs via pg-boss in the same Postgres. |
| Database | Postgres 16 + PostGIS. All schema changes via migrations checked into the repo. |
| Object storage | S3-compatible (R2 or S3). Originals bucket is private; served derivatives go through an image proxy with size variants. |
| Map | MapLibre GL on both clients. Tiles are self-built PMTiles: tippecanoe over the trees table, regenerated nightly after import and after community adds, served from object storage. Status and species attributes are baked into tiles; filters (status, in bloom, needs water) evaluate client-side from tile attributes. No Mapbox account, no per-seat licensing. |
| Auth | Sign in with Apple, Google, and email magic link (no passwords). Short-lived JWT access token plus rotating refresh token, identical for app and web. Account deletion is in scope from day one (App Store requires it): contributions are anonymized, not deleted, per the ODbL note in section 10. |
| Photo pipeline | Two-phase upload (section 6). EXIF GPS and all EXIF metadata stripped server-side on ingest; capture timestamp and the app's own fuzzed coordinates are stored in columns, never in the file. |

## 4. Data model

Field-level schema. Types abbreviated; every table gets id uuid primary key, created_at, updated_at unless noted. Every table that users touch gets soft delete via deleted_at.

users
- email text unique, display_name text, avatar_url text nullable
- role text: member, steward, coordinator, moderator, admin (default member)
- birth_year_bucket text: over_18, under_18, unknown. Under_18 forces anonymous public attribution (D11)
- public_attribution boolean default false: opt-in per D11
- license_version text and license_accepted_at timestamptz: consent is versioned; a license text change requires re-consent
- deleted_at timestamptz

devices
- device_uuid unique, user_id nullable. Anonymous contributions (D9) attach here and migrate to the user on account creation

trees
- external_ref text (DataSF TreeID) nullable unique, source text: city_import or community
- geom geometry(Point, 4326), address text, site_type text, neighborhood_id fk
- status text: alive, declining, dead_reported, removed, vacant_site
- species_current fk species (denormalized from latest accepted assertion)
- planted_year int nullable, dbh_city_cm_range int4range nullable (seed data is a range, never a point)
- site_lineage uuid nullable: links a replanted site to the removed tree that preceded it
- verification_state text: unverified, org_verified, city_record (D12)

tree_names (D15; nicknames existed only in the mocks before)
- tree_id fk, name text, given_by fk users, status text: active, retired, removed_by_moderation
- One active name per tree. First namer wins; renames go through the same moderation queue as photos. Species common name is the fallback display everywhere.

species
- scientific_name text, common_name text, family text
- leaf_retention text: evergreen, deciduous, semi_deciduous. Drives phenology chips and season strip rendering (D5)
- id_tips jsonb: array of {icon, text}
- seasonal jsonb: {bloom_months int[], fall_color_months int[], fruit_months int[], new_growth_months int[]}. Empty arrays are valid; fall_color_months must be empty when leaf_retention = evergreen
- care_notes jsonb: array of {month_range, text}
- curated boolean: true for the authored top list (section 8)

species_assertions
- tree_id fk, species_id fk, source text: city_import, community, org, ai_suggestion
- confidence numeric nullable, asserted_by fk nullable, superseded_by fk self nullable. Append-only

visits
- tree_id fk, user_id nullable fk, device_id fk, client_uuid unique (idempotency key)
- note text nullable, phenology_tags text[] (validated against the species seasonal vocabulary)
- gps_accuracy_m numeric nullable (D6), captured_at timestamptz

photos
- visit_id fk nullable, tree_id fk, storage_key text, shot_type text: full_tree, trunk, leaf, other
- moderation_state text: pending, approved, rejected
- blur_applied boolean, width int, height int, captured_at

observations (check-ins)
- tree_id, user_id nullable, device_id, client_uuid unique, captured_at, gps_accuracy_m
- status text nullable, vitality int 1 to 5 nullable, foliage text nullable, structure_flags text[] with the UI label "informal observations, not a risk assessment" carried into the export header
- verification_state text as on trees (D12)

measurements (D7; the capture UI is screen 16)
- tree_id, user_id nullable, device_id, client_uuid unique, captured_at, gps_accuracy_m
- kind text: dbh, height. value numeric, unit_entered text, si_value numeric, method text: tape, caliper, estimate, laser
- measurement_height_m numeric default 1.4 for dbh
- Charting rule: estimated and measured points are separate series, never connected (D7). Points with gps_accuracy_m above 15 are excluded from per-tree charts (D6)

care_events
- tree_id, user_id nullable, device_id, client_uuid unique, captured_at
- actions text[]: watered, mulched, weeded, litter_cleared, staked. Photo optional. Never publicly counted or ranked (D1)

favorites
- user_id, tree_id, unique pair, deleted_at as tombstone (sync needs the tombstone, not a hard delete)

private_reminders (D4; replaces public hazard notes)
- user_id, tree_id, category text, note text, photo_id nullable. Never public, never auto-staled

community_notes
- tree_id, user_id, category text: needs_water, pest, vandalism (hazard categories are rejected by a check constraint; hazards are 311 redirects only, D4)
- stale_at timestamptz: 90 days, non-safety categories only by construction

review_flags
- tree_id, kind text: appears_dead, appears_removed, duplicate_suspected, wrong_species
- raised_by, status text: open, confirmed, dismissed. Surfaced in the admin view from M2

orgs, org_members (role steward or coordinator), assignments (org_id, tree_id, steward fk, cadence text, active boolean): the Phase 1.5 loop

neighborhoods
- name text, geom geometry(MultiPolygon). Source: SF Analysis Neighborhoods dataset (the one official set, resolved ambiguity A4)

notif_subscriptions (D10)
- user_id, tree_id nullable, species_id nullable, kind text: bloom_window, new_growth_window. Fired by a daily job reading species.seasonal

export_runs
- started_at, finished_at, row_counts jsonb, changelog_note text. Backs the public export page and its changelog

Client-side outbox (SQLite on device):
- outbox(id, kind text: visit, observation, measurement, care_event, favorite_toggle, payload json, photo_paths json, state text: pending, uploading, failed, done, fail_count int, last_error text, created_at)
- Retry policy: exponential backoff 30 s, 2 m, 10 m, 1 h, then hourly; cap 48 h then state failed with a visible retry button (screen 17). Wifi-only toggle applies to photo binaries only.

## 5. Verification and trust (D12)

verification_state meanings: city_record rows came from the city import untouched. org_verified rows were made or confirmed by an org member with the steward or coordinator role. Everything else is unverified. The nightly export includes observations and measurements only with a machine-readable verification_state column, and the export README states plainly that unverified rows are not fit for inventory ingestion. There is no UI-only provenance; every provenance fact is a queryable column.

## 6. API contract

One JSON API at /api/v1. Errors always {error: {code, message, retryable boolean}}. Codes: unauthorized, forbidden, not_found, validation_failed, conflict, moderation_rejected, rate_limited, server_error. Pagination is cursor-based (?cursor, ?limit max 100).

| Method and path | Purpose |
|---|---|
| POST /auth/apple, /auth/google, /auth/email/start, /auth/email/verify | Sign in; returns access + refresh tokens |
| POST /auth/refresh, POST /auth/logout, DELETE /me | Session management and account deletion (anonymize) |
| POST /devices/claim | Attach an anonymous device's contributions to the signed-in user (D9) |
| GET /tiles/{z}/{x}/{y} | PMTiles range reads, served from storage via CDN; not Fastify's job in production |
| GET /trees/{id} | Profile payload: tree, active name, species, latest observation summary, photo timeline page 1, measurement series |
| GET /trees?near=lng,lat&radius=m | The what-tree-is-this shortlist, ordered by distance, each row carrying one id_tip as its tell (D6) |
| POST /trees | Community add: requires photo, species optional; runs the proximity dedupe check (10 m, any species) and returns conflict with the candidate list when it trips |
| GET /species/{id}, GET /species?query= | Field guide and autocomplete (trigram index on both names) |
| POST /sync | The batch endpoint. Body: array of outbox items with client_uuids. Response: per-item {client_uuid, status: applied, duplicate, failed, error}. Server dedupes on client_uuid. Favorites sync as toggle events with tombstones |
| POST /photos/begin | Returns {photo_id, presigned_put_url}. Client PUTs the binary, then includes photo_id in the visit's sync item. A photo record with no arriving binary after 72 h is garbage-collected |
| GET /me/outbox-status | Server view of recent sync results, for the outbox screen's "says why" line |
| GET /me/grove, /me/journal, /me/collections | Private-by-default personal surfaces (D11) |
| POST /reports/hazard-redirect | Logs that a 311 redirect was shown (analytics only, no public record); private_reminders POST is separate |
| GET /export/latest.csv, .geojson | Nightly export with verification_state; changelog at /export/changelog |
| Admin: GET/POST /admin/moderation, /admin/review-flags, /admin/species | Moderator and admin role required |

Sync semantics that are not obvious: contributions are append-only except favorites (tombstone toggles) and tree status side-effects. An observation with status appears_removed does not mutate trees.status directly; it opens a review_flag, and only a moderator or an org coordinator confirms the transition. Two offline users flagging the same tree produce two flags on one thread, not a conflict.

## 7. Ingest spec (DataSF)

Source: DataSF Street Tree List (dataset tuvn-fjcn... use the current portal id at build time), CSV via the Socrata export URL, full snapshot weekly.

Column mapping (DataSF name, ours): TreeID to external_ref; qSpecies to sf_species_map lookup; qAddress to address; Latitude/Longitude to geom; PlantDate to planted_year (year part; null when absent); DBH to dbh_city_cm_range (DataSF DBH is inches, convert, bucket into 5 cm ranges); qSiteInfo to site_type; qLegalStatus kept as raw jsonb along with all unmapped columns in city_raw jsonb.

Row rules: drop rows with null coordinates or coordinates outside SF bounds. qSpecies values that are site placeholders ("Tree(s) ::", "::", empty) become status vacant_site with species_current null. Everything else gets a species_assertion with source city_import.

sf_species_map is a checked-in CSV (qSpecies string, species_id, confidence) authored once for the roughly 570 distinct strings, highest-frequency first; unmapped strings fall back to a species stub with curated false and the raw string as scientific_name. The import fails loudly if more than 2 percent of rows hit the stub path.

Weekly diff: full re-download, match on external_ref. New rows insert. Removed-from-source rows with no community activity in 12 months become status removed; with activity, they open a review_flag (removed_but_active) and keep their timeline. Changed species strings append a superseding city_import assertion. Community contributions are never deleted by sync. A golden-file test (section 13) pins all of this.

## 8. Species content pipeline

The curated list is the roughly 100 species covering 90 percent of SF street trees. For each, an authored record: id_tips (2 to 4 entries), seasonal months, care_notes, leaf_retention, and licensed or commissioned reference photos used as profile fallback heroes on photo-less trees, badged "reference photo" (cold-start content, investor attack 6). The long tail renders name, family, and a generic silhouette; no fabricated botany. The five vitality anchor photos per class ship as app assets and are an entry gate for M2: the check-in screen does not ship without them (screen 5 shows them inline). Authoring lives in the admin surface; content is versioned in the repo as YAML and loaded by migration, not hand-edited in production.

## 9. Screens and states that must exist

Screens 1 to 18 are mocked. The following are unmocked but required, with their milestone:

M1: location permission ask with purpose copy and denied state; map without location; camera permission ask and denied fallback (photo library); map loading skeleton; search results and no-results; low-GPS state of what-tree-is-this.
M2: sign-in decline path; empty grove, journal, collections; first-visit camera without ghost overlay; visit save confirmation; duplicate-proximity warning on add-a-tree; appears-dead confirmation dialog; vitality suppressed leaf-off state for deciduous species; photo moderation report flow; the You tab (profile, settings, outbox entry point, privacy toggles).
M3: removed tree memorial profile; conflict view for removed_but_active; share card photo-less variant (species reference image fallback); OpenGraph render.

## 10. Privacy spec

Public photo locations snap to a 25 m grid everywhere (not "near residential parcels"; parcel proximity is unknowable at the precision that matters, so the rule is universal, resolving ambiguity A7). Tree pins themselves are exact; trees are public objects. Per-user contribution feeds are private by default; public tree timelines show "a visitor" unless the user opted into public_attribution, and always for under-18 accounts (D11). Face and license plate blurring runs at upload in the moderation job using an open-source detector; detections blur automatically, low-confidence frames queue for human review before approval. Account deletion anonymizes attributed rows (user_id nulled, device link severed) and removes the profile; ODbL-published aggregates are unaffected. Age gate at onboarding is a single over-or-under-18 choice, no birthdate collected.

## 11. Resolved ambiguities

Each of these burned a review finding; the resolution is one sentence so nobody re-litigates them in code review.

- A1 clustering: pins cluster at zoom 15 and below; individual pins at zoom 16 and above (the spec sentence was backwards).
- A2 "recently visited" filter chip: visited by me, within 30 days.
- A3 "best photo": most recent approved full_tree photo; ties broken by resolution; manual pin by any org member overrides.
- A4 "your area" and neighborhood names: SF Analysis Neighborhoods polygons, resident neighborhood inferred from most-visited, overridable in settings.
- A5 season strip: the most recent photo per calendar month across all years, so a strip fills over time.
- A6 automated moderation screening: a vision safety model for nudity and people, plus the blur pipeline; no other content AI in Phase 1.
- A7 photo location fuzzing: universal 25 m snap-to-grid, section 10.
- A8 "caretakers" count: distinct users with 2 or more care_events or observations on the tree in 24 months; shown only when 3 or more (cold-start threshold, D-skeptic attack 7).
- A9 aggregate surfaces below threshold do not render: leaderless almanac cards need their data (bloom sightings need 1, species mix always renders from city data, coverage panel always renders).
- A10 email auth is magic link; there are no passwords anywhere.

## 12. Milestones with acceptance criteria

M0 walking skeleton, 4 to 6 weeks of agent time equivalent. Accepts when: fresh clone, one command brings up Postgres + API + web; ingest runs against a checked-in 5,000-row DataSF fixture and the real feed; map shows clustered pins from tiles built by the pipeline; a visit created in the app with airplane mode on syncs when connectivity returns and appears on the public web tree page; CI runs the golden-file ingest test and an outbox round-trip test green.

M1 field capture. Accepts when: check-in, measurement, care log, favorites, and add-a-tree all round-trip through the outbox; the E2E scripts for stories U1, U2, U3, U6, U8 pass on device farm iOS and Android; permission denial paths all render designed states; measurement entry rejects unit-less or method-less submissions at the type level.

M2 accounts, moderation, species. Accepts when: anonymous-to-account migration works (three visits on device, sign in, all three attributed); consent version bump forces re-consent; vitality reference photos ship; curated species content loads by migration; photo moderation queue functions end to end including blur; U4, U5, U9 E2E pass; account deletion passes App Store review checklist.

M3 org loop and public web. Accepts when: a coordinator creates assignments, a steward completes a 10-tree morning using the next-tree flow in under 25 minutes in a scripted field test, and the coordinator exports a CSV that opens in Excel with method and verification columns intact; public tree pages render with OpenGraph cards in under 2 s TTFB from cache; nightly export publishes with changelog.

M4 enthusiast polish. Accepts when: collections, almanac, journal, phenology notifications, and share cards pass their E2E scripts; a notification fires for a subscribed species entering its bloom window in a seeded test clock; the almanac renders correctly against an empty city (thresholds hold).

## 13. Test plan

- Golden-file ingest test: the 5,000-row fixture plus a mutated second snapshot (adds, removals, species changes, a removed_but_active case); assert exact resulting table states.
- Outbox chaos test: scripted network flaps during a 20-item sync; assert zero loss, zero duplicates (client_uuid), correct per-item statuses.
- E2E per user story U1 to U10 (Maestro on mobile, Playwright on web), run in CI on every merge.
- Schema invariant tests: no observation without method metadata on numerics; no evergreen species with fall_color_months; no public surface query that can return a hazard-category note.
- Export contract test: published CSV headers and verification_state values are pinned; a diff fails CI.
- The palette and dark mode run the design-system validator; charts follow the one-scale rule from screen 13.

## 14. Who pays (D14)

The consumer layer is free, forever, including the export. Orgs pay for the coordinator tier (assignments, dashboards, exports, verification workflows) at 50 to 200 dollars per org per month depending on size, first partner org free for the pilot year in exchange for feedback and a case study. Cities are a Phase 2 conversation once org-verified data exists; the pitch is the verified layer plus Open311 round-trip, not the raw citizen feed. If the pilot org will not convert at even the low price point, that finding goes back into this document before more org features are built.

## 15. What a coding agent should not do

Do not invent botanical content; the curated YAML is the only source. Do not add streaks, points, ranks, or public counts of user actions anywhere (D1); recency and identity phrasing only. Do not connect estimated and measured points in one chart series (D7). Do not write "sent to the city" copy anywhere without a real 311 ticket id in hand. Do not collect birthdates, passwords, or exact photo GPS. When a screen or state is not in the mocks or section 9, stop and ask rather than inventing it.
