# Cypress: Phase 1 specification

A deeper spec for Phase 1 (the living map and the ten-second visit), per [DESIGN.md](DESIGN.md) v2. This is still design-stage work; no implementation decision is final until build kickoff.

The Phase 1 goal: an SF resident opens the app, learns what the tree outside their door is, starts visiting trees on walks, and comes back weekly. Meanwhile every byte collected stays clean enough for stewards, cities, and researchers later.

Success metrics:

- Week-4 retention of registered members at 25% or better, and a median of two or more visits per active member per week
- Zero field data loss: every queued submission eventually syncs or surfaces a recoverable error
- At least 60% of visits attach a photo, and at least 80% of "what tree is this?" sessions end on a tree profile

---

## 1. Scope

In: map browse, tree profiles, the species field guide, "what tree is this?", visits, favorites, species collections, shareable tree pages, the quick care log, the light check-in with an anchored rubric, the offline outbox, the SF data seed with recurring sync, add-a-tree (community layer), accounts, share cards, moderation basics, and a documented export.

Out (Phase 2 and later): orgs, assignments, routes, group workdays, full structured observations (multi-stem DBH and the rest), Open311 routing, staff and coordinator dashboards, verification workflows, adoption and reminders, area download, and anything AI.

Hazard reports are not accepted in Phase 1 at all. The Report entry point exists, but every path ends at either (a) a full-screen "Call 311 now" redirect for hazard and emergency categories, or (b) a community note pinned to the tree and labeled "the city has not been notified."

## 2. User stories (acceptance criteria abbreviated)

| # | Story | Key acceptance criteria |
|---|---|---|
| U1 | As an explorer, I open the app and see trees around me without an account | Map renders in under 2 s on cold start; clustered pins; locate me; no login wall |
| U2 | As an explorer, I stand next to a tree and ask "what tree is this?" | One tap from the map; a GPS-ranked list of up to 8 nearest trees with distance, thumbnail, and species; tapping opens the profile; works at roughly 10 m GPS accuracy; graceful "low GPS accuracy" state |
| U3 | As a member, I log a visit in 10 seconds or less | Camera-first sheet with a ghost overlay of the last photo (if any); the note is optional; submit works offline; the visit appears in the tree timeline and my journal |
| U4 | As a member, I favorite a tree and build a species collection | The collection view shows "N of M species in your area"; a new species gets a celebratory card |
| U5 | As a member, I share a tree | A public web page per tree with no login; a share card image is generated automatically (best photo, name, season strip) |
| U6 | As a member, I log care I performed | Toggle chips (watered, mulched, weeded, litter, other), 30 seconds or less, works offline |
| U7 | As a member, I do a light check-in | Vitality uses the anchored rubric with reference photos inline; foliage and structure are quick selects; every field can be skipped; status can be set to "appears dead/removed," which flags the tree for review |
| U8 | As a member, I add a missing tree | It lands in the community layer with a distinct pin style; a proximity and species duplicate check warns before creating |
| U9 | As anyone, I read a species page | ID tips with photos, seasonal notes, "what to look for this month," and a count and map of nearby individuals |
| U10 | As a data consumer, I export | A public, documented CSV and GeoJSON export per city, keyed on UUID and external_ref, with the license stamped in the file header |

## 3. Screen-by-screen (mobile)

### 3.1 Map home

- A full-bleed map. Pin color follows tree status (green for alive, amber for declining, gray for dead or removed, shown only when that filter is on). Community-layer trees get an outlined, dashed pin.
- Clustering above zoom 16, with a count badge on each cluster.
- Top: search by species, street, or neighborhood. Filter chips: species, in bloom (from species seasonal data), recently visited, community-added.
- The primary FAB is "What tree is this?". Long-pressing expands secondary actions: visit nearest, add a tree.
- Tapping a pin opens a bottom-sheet preview (photo, name, distance, last visit) that expands to the full profile.

### 3.2 What tree is this?

- A full-screen list, nearest first, with big thumbnails, species and common name, and distance ("6 m NE").
- Confidence hinting: if the top candidate is within 3 m and the next is 10 m or more away, the top card is highlighted automatically.
- Footer: "None of these? Add this tree."
- Empty and low-GPS states are specified (prompt to step away from buildings, or browse the map instead).

### 3.3 Tree profile

Order matters here: story before stats.

1. Hero: the best photo plus a season strip (12 thumbnails, one per month where photos exist).
2. Identity: common name (big), scientific name, an ID tips accordion ("How to recognize it"), status badge.
3. Actions: Favorite, Share, Visit, Care log, Report.
4. Timeline: a reverse-chronological feed of visits, photos, care logs, and check-ins, filterable.
5. Details (below the fold): height, DBH (with its method badge), planting date, site type, city ID, and a provenance label ("SF city inventory" versus "community-added, unverified").
6. A "nearby of the same species" strip that links to the species page.

### 3.4 Visit sheet

- Launching opens the camera immediately (with graceful permission handling). The ghost overlay shows the last full-tree photo at 30% opacity plus a shot-type hint chip.
- After the shutter: photo preview, an optional one-line note, an optional phenology quick-tag (suggested from the month and species), submit.
- Offline: submit always succeeds locally, and the card shows a "will sync" glyph.

### 3.5 Care log

- Chip toggles: watered, mulched, weeded basin, litter cleared, other (free text).
- Optional photo, optional note, submit.

### 3.6 Light check-in

One scrollable card, not a step wizard:

1. Status: alive, declining, appears dead, appears removed. The last two trigger a review flag and a confirmation.
2. Vitality: five anchored classes, each with a reference photo and a one-line anchor (see section 6). Tap to select.
3. Foliage: density (full, thinning, sparse, bare in season), discoloration (none, some, severe), damage (none, chewed, spotted, scorched).
4. Structure quick-flags: lean, broken limb, trunk wound, root heave, hardware issue.
5. Photos and a note.

Everything can be skipped; only status has a default (alive). The target is 60 seconds or less.

### 3.7 Report (community note)

- A category picker. Hazard categories (hanging or broken limb over a path, uprooted, struck by vehicle, blocking a signal or sightline) go to a full screen that says "This may be a public-safety hazard. Call 311." with tap-to-call and a secondary "also pin a community note."
- Non-hazard categories (needs water, pest suspected, hardware, vandalism) take severity, a photo, and a note, then post as a pinned community note labeled: "Community-reported. The city has not been notified."

### 3.8 My grove and journal

- Tabs: Trees (a favorites grid with last photo and species), Journal (a chronological photo diary of all my visits with monthly headers), and Collections (a species progress ring, with per-species tiles showing seen or not seen and the first-seen date).

### 3.9 Onboarding and account

- First launch: a location permission prompt with purpose copy, then straight to the map. No account is required until the first save action (favorite or visit), which opens a sheet with Apple, Google, and email options. Display name plus optional avatar, and contribution license consent (a checkbox with a plain-language summary and a link).

## 4. Web (the Phase 1 surface)

- Explore: map plus browse, a species field guide index, and neighborhood pages (canopy stats, top species, recent photos).
- Tree page (public, shareable): hero, season strip, timeline, details, map inset, and an automatically rendered OpenGraph share-card image.
- Species page: the full field guide entry plus a city map of individuals.
- Account pages: journal and collections mirror the app.
- Export page: per-city dataset downloads (CSV and GeoJSON), schema docs, license text, and a changelog.

## 5. Data schema (Postgres and PostGIS sketch)

```sql
-- Identity & taxonomy
users(id uuid pk, auth_provider, display_name, created_at, license_consent_at)
species(id pk, scientific_name, common_name, genus, family,
        id_tips jsonb, seasonal jsonb, care_notes jsonb)

-- Trees
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

-- Contributions (all offline-queueable, all attributed)
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

-- Sync & review
import_runs(id pk, source, started_at, finished_at, stats jsonb)
sync_conflicts(id pk, tree_id fk, kind enum('removed_but_active',
       'species_mismatch','location_moved'), city_payload jsonb,
       state enum('open','resolved'), resolved_by, resolved_at)
review_flags(id pk, tree_id fk, kind enum('reported_dead','duplicate_suspect',
       'photo_moderation'), source_id, state, created_at)
```

`tree_status`: `alive | declining | dead_standing | removed | stump | vacant_site`.

## 6. Vitality rubric (draft v0; needs urban forestry advisor sign-off before launch)

Five classes, each with reference photos shown inline at rating time. This is a simplified derivative of USFS urban crown-condition classes, and the mapping to the source protocol is documented in the export schema.

| Class | Label | Anchor (plain language) |
|---|---|---|
| 5 | Thriving | Full, dense canopy for the season; vigorous new growth; no visible dieback |
| 4 | Good | Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback) |
| 3 | Fair | Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable |
| 2 | Poor | Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious |
| 1 | Severe decline | Mostly bare in season; over 50% dieback; survival doubtful |

Deciduous species are rated only in leaf-on season. The app suppresses the vitality UI off-season using species leaf phenology, while structure flags stay available year-round.

## 7. SF data seed and recurring sync

- Source: the DataSF Street Tree List, which DPW updates regularly. The initial import of roughly 190k rows creates `trees` with `provenance='city_inventory'`, `external_source='sf_dpw'`, and `external_ref=TreeID`. Species map through a curated `sf_species_map` table (city species strings to `species.id`); unmapped rows get a genus or unknown assertion and enter a curation queue.
- Recurring: a weekly diff import with this merge policy:
  - New city rows create trees.
  - A city row that disappears or is marked removed sets `status='removed'`, but only if the tree has no community activity in the last 30 days. Otherwise it opens a `sync_conflict('removed_but_active')`.
  - A city species change creates a new `species_assertion(source='city_import')` and supersedes the prior one, keeping history.
  - A location delta over 5 m opens a `sync_conflict('location_moved')`.
- Sync never deletes community photos or visits. A removed tree's profile becomes read-only with a memorial banner.

## 8. Offline outbox

- Local SQLite (Expo) holds a bounded map-region browsing cache and an outbox table. Every mutation (visit, photo, care log, check-in, favorite) is written locally first with `client_created_at` and a client UUID, then synced FIFO with retry and backoff.
- Photos stay on the device until upload is confirmed, with a wifi-only upload toggle.
- Conflict rule: contributions are append-only, so there are no merge conflicts. The server dedupes on client UUID, making sync idempotent.
- The outbox is visible in the UI ("3 items waiting to sync") and never gets silently stuck.

## 9. Export and licensing

- License: ODbL for the database and CC-BY 4.0 for photos, granted by contributors at signup. The final call awaits legal review, but the license is declared before any data is collected.
- Export: nightly per-city CSV and GeoJSON covering trees (UUID, external_ref, current species assertion with confidence, status, location, provenance) and observations (method- and unit-tagged). The schema is versioned and documented on the export page, with i-Tree-compatible field naming where a mapping exists.

## 10. Non-functional requirements

- Performance: map cold start under 2 s; tile and pin fetch via vector tiles or a clustered GeoJSON endpoint; photo upload backgrounded.
- Privacy: public GPS precision reduced to roughly 25 m for photos near residential parcels; EXIF GPS stored only with consent; no public user location history; display names only.
- Accessibility: WCAG AA; all field UI usable one-handed; tap targets 44 pt or larger; a high-contrast map style option for bright sunlight.
- Moderation: a photo report flow plus an automated screening queue; community notes go stale automatically after 90 days without activity.

## 11. Milestones (design-stage estimate)

| Milestone | Contents |
|---|---|
| M0: Foundations | Schema, SF import and species mapping, map pipeline, auth |
| M1: Explore | Map home, tree profile, species pages, "what tree is this?", public web tree pages |
| M2: Contribute | Visits (camera and ghost overlay), care logs, light check-in and rubric, offline outbox |
| M3: Belong | Favorites, collections, journal, share cards |
| M4: Trust | Recurring sync and the conflict queue, moderation, export page, fenced add-a-tree |

The launch bar: M0 through M4 complete, the rubric advisor-approved, and the license finalized.
