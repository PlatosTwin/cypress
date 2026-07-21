import Foundation

/// The app's own mutable schema — everything in BUILD-PLAN §4 that a phone writes.
///
/// **What lives where.** The bundled seed (`seed.*`) holds the read-only city inventory: `trees`,
/// `species`, `neighborhoods`, `species_assertions`. Nothing here duplicates those. The tables
/// below are `main.*` and hold only what the device produces.
///
/// **Why there are no foreign keys onto the inventory.** SQLite cannot declare a `REFERENCES`
/// across an attached database. Contributions therefore carry `tree_uuid TEXT`, matching
/// `seed.trees.uuid` — the stable, citable, deterministic identity the seed contract guarantees
/// survives a re-import. Referential integrity against the inventory is checked in `LocalAPI` at
/// write time, not by the engine. This is the one real cost of the ATTACH decision (see
/// `SeedDatabase`), and it is stated here rather than discovered later.
///
/// **Invariants as constraints.** BUILD-PLAN §13 asks for schema invariant tests. Where SQLite can
/// carry the invariant itself it does, so the rule holds against a hand-written `INSERT` in a
/// debugger as well as against the DAO:
/// - no numeric measurement without unit *and* method metadata (D7) — `measurements` CHECKs;
/// - `measurement_height_m` exists exactly for DBH and never for height (D7);
/// - hazard categories cannot be stored as public community notes (D4) — `community_notes` CHECK;
/// - private reminders can only hold hazard categories, and carry no `stale_at` at all;
/// - favorites are tombstoned, never hard-deleted — a `BEFORE DELETE` trigger that raises;
/// - one active name per tree (D15) — a partial unique index;
/// - an outbox row can only be `done` once its JSON *and* its photos have gone.
public enum AppSchema {
    /// Every migration, in order. Checked in, never edited after shipping — a new step gets a new
    /// version number.
    public static let migrations: [Migration] = [
        Migration(version: 1, name: "contributions and outbox", sql: v1)
    ]

    /// The version a freshly migrated database reports.
    public static var currentVersion: Int32 { migrations.map(\.version).max() ?? 0 }

    // MARK: - v1

    private static let v1 = """
    -- ------------------------------------------------------------------ device --
    -- BUILD-PLAN §4 `devices`. One row. Anonymous contributions attach here and
    -- migrate to a user at POST /devices/claim (D9).
    CREATE TABLE IF NOT EXISTS device (
        id           TEXT PRIMARY KEY,
        device_uuid  TEXT NOT NULL UNIQUE,
        user_id      TEXT,
        created_at   TEXT NOT NULL,
        updated_at   TEXT NOT NULL
    );

    -- Key/value app state that is not a contribution: the wifi-only photo toggle
    -- (screen 17), the last sync cursor. Values are TEXT; callers own the parsing.
    CREATE TABLE IF NOT EXISTS app_state (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );

    -- --------------------------------------------------------- community_trees --
    -- `POST /trees` (BUILD-PLAN §6). The seed is read-only, so a tree the user
    -- adds cannot go into `seed.trees`; it lives here, with the same column
    -- vocabulary, and the read layer merges the two. It stays "in a visually
    -- distinct layer and never renders as part of the official city inventory
    -- until verified" (DECISIONS §3.16) — which `source = 'community'` and
    -- `verification_state = 'unverified'` already encode.
    --
    -- No R*Tree: this table holds tens of rows, not 195,309, and a bbox filter
    -- over `idx_community_trees_lat_lon` is already the cheapest thing available.
    CREATE TABLE IF NOT EXISTS community_trees (
        id                 TEXT PRIMARY KEY,
        client_uuid        TEXT NOT NULL UNIQUE,
        external_ref       TEXT,
        source             TEXT NOT NULL DEFAULT 'community' CHECK (source = 'community'),
        lat                REAL NOT NULL,
        lon                REAL NOT NULL,
        address            TEXT,
        site_type          TEXT,
        status             TEXT NOT NULL DEFAULT 'alive'
                           CHECK (status IN ('alive','declining','dead_reported','removed','vacant_site')),
        species_current    TEXT,
        planted_year       INTEGER,
        dbh_city_cm_min    INTEGER,
        dbh_city_cm_max    INTEGER,
        site_lineage       TEXT,
        verification_state TEXT NOT NULL DEFAULT 'unverified'
                           CHECK (verification_state IN ('unverified','org_verified','city_record')),
        created_at         TEXT NOT NULL,
        updated_at         TEXT NOT NULL,
        deleted_at         TEXT,
        CHECK ((dbh_city_cm_min IS NULL) = (dbh_city_cm_max IS NULL))
    );
    CREATE INDEX IF NOT EXISTS idx_community_trees_lat_lon ON community_trees(lat, lon, id);

    -- ------------------------------------------------------------------ visits --
    CREATE TABLE IF NOT EXISTS visits (
        id             TEXT PRIMARY KEY,
        tree_uuid      TEXT NOT NULL,
        user_id        TEXT,
        device_id      TEXT NOT NULL,
        client_uuid    TEXT NOT NULL UNIQUE,
        note           TEXT,
        phenology_tags TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(phenology_tags)),
        gps_accuracy_m REAL,
        captured_at    TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_visits_tree ON visits(tree_uuid, captured_at DESC);
    CREATE INDEX IF NOT EXISTS idx_visits_user ON visits(user_id, captured_at DESC);

    -- ------------------------------------------------------------------ photos --
    -- `local_path` is not in §4: it is where the binary sits on device until the
    -- upload is confirmed. The wifi-only toggle gates this binary, never the JSON
    -- that references it (BUILD-PLAN §4).
    CREATE TABLE IF NOT EXISTS photos (
        id               TEXT PRIMARY KEY,
        tree_uuid        TEXT NOT NULL,
        visit_id         TEXT REFERENCES visits(id),
        storage_key      TEXT,
        local_path       TEXT,
        shot_type        TEXT NOT NULL CHECK (shot_type IN ('full_tree','trunk','leaf','other')),
        moderation_state TEXT NOT NULL DEFAULT 'pending'
                         CHECK (moderation_state IN ('pending','approved','rejected')),
        blur_applied     INTEGER NOT NULL DEFAULT 0 CHECK (blur_applied IN (0,1)),
        width            INTEGER,
        height           INTEGER,
        captured_at      TEXT NOT NULL,
        -- Already snapped to the universal 25 m grid before it is written (A7,
        -- BUILD-PLAN §10). Exact photo GPS is never stored.
        public_lat       REAL,
        public_lon       REAL,
        created_at       TEXT NOT NULL,
        updated_at       TEXT NOT NULL,
        deleted_at       TEXT,
        CHECK ((public_lat IS NULL) = (public_lon IS NULL))
    );
    CREATE INDEX IF NOT EXISTS idx_photos_tree ON photos(tree_uuid, captured_at DESC);
    CREATE INDEX IF NOT EXISTS idx_photos_visit ON photos(visit_id);

    -- ------------------------------------------------------------ observations --
    -- The light check-in. There is deliberately no numeric column here other than
    -- the 1-5 rubric class and the GPS accuracy: quantities live in
    -- `measurements`, where method and unit are mandatory (D7). "No numeric
    -- observation without method metadata" is therefore structural, not a check.
    CREATE TABLE IF NOT EXISTS observations (
        id                 TEXT PRIMARY KEY,
        tree_uuid          TEXT NOT NULL,
        user_id            TEXT,
        device_id          TEXT NOT NULL,
        client_uuid        TEXT NOT NULL UNIQUE,
        captured_at        TEXT NOT NULL,
        gps_accuracy_m     REAL,
        status             TEXT CHECK (status IS NULL OR
                                       status IN ('alive','declining','appears_dead','appears_removed')),
        vitality           INTEGER CHECK (vitality IS NULL OR vitality BETWEEN 1 AND 5),
        foliage            TEXT CHECK (foliage IS NULL OR json_valid(foliage)),
        structure_flags    TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(structure_flags)),
        note               TEXT,
        verification_state TEXT NOT NULL DEFAULT 'unverified'
                           CHECK (verification_state IN ('unverified','org_verified','city_record')),
        created_at         TEXT NOT NULL,
        updated_at         TEXT NOT NULL,
        deleted_at         TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_observations_tree ON observations(tree_uuid, captured_at DESC);

    -- ----------------------------------------------------------- measurements --
    -- D7, enforced by the engine: a value cannot exist without the unit it was
    -- entered in, the canonical SI value, and the method that produced it. The
    -- last CHECK is the schema form of `TreeMeasurement.dbh` / `.height`:
    -- measurement height accompanies DBH and never accompanies a height.
    CREATE TABLE IF NOT EXISTS measurements (
        id                  TEXT PRIMARY KEY,
        tree_uuid           TEXT NOT NULL,
        user_id             TEXT,
        device_id           TEXT NOT NULL,
        client_uuid         TEXT NOT NULL UNIQUE,
        captured_at         TEXT NOT NULL,
        gps_accuracy_m      REAL,
        kind                TEXT NOT NULL CHECK (kind IN ('dbh','height')),
        value               REAL NOT NULL,
        unit_entered        TEXT NOT NULL CHECK (unit_entered IN ('mm','cm','m','in','ft')),
        si_value            REAL NOT NULL,
        method              TEXT NOT NULL CHECK (method IN ('tape','caliper','estimate','laser')),
        measurement_height_m REAL,
        verification_state  TEXT NOT NULL DEFAULT 'unverified'
                            CHECK (verification_state IN ('unverified','org_verified','city_record')),
        created_at          TEXT NOT NULL,
        updated_at          TEXT NOT NULL,
        deleted_at          TEXT,
        CHECK ((kind = 'dbh') = (measurement_height_m IS NOT NULL))
    );
    CREATE INDEX IF NOT EXISTS idx_measurements_tree ON measurements(tree_uuid, kind, captured_at);

    -- ------------------------------------------------------------ care_events --
    -- "Never publicly counted or ranked" (D1). Nothing in this schema aggregates
    -- them, and no index exists to make a leaderboard cheap.
    CREATE TABLE IF NOT EXISTS care_events (
        id             TEXT PRIMARY KEY,
        tree_uuid      TEXT NOT NULL,
        user_id        TEXT,
        device_id      TEXT NOT NULL,
        client_uuid    TEXT NOT NULL UNIQUE,
        captured_at    TEXT NOT NULL,
        gps_accuracy_m REAL,
        actions        TEXT NOT NULL CHECK (json_valid(actions) AND json_array_length(actions) > 0),
        note           TEXT,
        photo_id       TEXT REFERENCES photos(id),
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_care_events_tree ON care_events(tree_uuid, captured_at DESC);

    -- -------------------------------------------------------------- favorites --
    -- Tombstone toggles: sync needs the tombstone, not a hard delete (BUILD-PLAN
    -- §4). The unique pair is (user_id, tree_uuid); un-favouriting sets
    -- `deleted_at` and re-favouriting clears it, so one row carries the whole
    -- history of the toggle and `client_uuid` moves with each flip.
    CREATE TABLE IF NOT EXISTS favorites (
        id          TEXT PRIMARY KEY,
        user_id     TEXT NOT NULL,
        tree_uuid   TEXT NOT NULL,
        client_uuid TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL,
        deleted_at  TEXT,
        UNIQUE (user_id, tree_uuid)
    );

    -- The tombstone rule, enforced rather than documented. Without this a stray
    -- DELETE loses the un-favourite event and the row silently comes back on the
    -- next sync from another device.
    CREATE TRIGGER IF NOT EXISTS favorites_are_tombstoned
    BEFORE DELETE ON favorites
    BEGIN
        SELECT RAISE(ABORT, 'favorites are tombstoned via deleted_at, never hard-deleted');
    END;

    -- ------------------------------------------------------ private_reminders --
    -- D4. Only hazard categories, never public, never auto-staled: there is no
    -- `stale_at` column and no visibility flag a query could get wrong. `user_id`
    -- is NOT NULL — a private reminder belongs to an account, so there is no
    -- anonymous variant that could later be attributed to the wrong person.
    CREATE TABLE IF NOT EXISTS private_reminders (
        id         TEXT PRIMARY KEY,
        user_id    TEXT NOT NULL,
        tree_uuid  TEXT NOT NULL,
        category   TEXT NOT NULL CHECK (category IN (
                       'hanging_or_broken_limb','uprooted','struck_by_vehicle',
                       'blocking_signal_or_sightline')),
        note       TEXT,
        photo_id   TEXT REFERENCES photos(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_private_reminders_user ON private_reminders(user_id, created_at DESC);

    -- -------------------------------------------------------- community_notes --
    -- "hazard categories are rejected by a check constraint; hazards are 311
    -- redirects only" (BUILD-PLAN §4, D4). The CHECK below is that constraint.
    -- No public surface query can return a hazard-category note because no
    -- hazard-category note can be stored.
    CREATE TABLE IF NOT EXISTS community_notes (
        id         TEXT PRIMARY KEY,
        tree_uuid  TEXT NOT NULL,
        user_id    TEXT NOT NULL,
        category   TEXT NOT NULL CHECK (category IN ('needs_water','pest','vandalism')),
        note       TEXT,
        photo_id   TEXT REFERENCES photos(id),
        stale_at   TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_community_notes_tree ON community_notes(tree_uuid, created_at DESC);

    -- ------------------------------------------------------------ review_flags --
    -- An observation never mutates trees.status; it opens one of these, and a
    -- moderator or org coordinator confirms it (DECISIONS §3.7). Two offline
    -- users flagging the same tree produce two rows, which is why there is no
    -- unique constraint on (tree_uuid, kind).
    CREATE TABLE IF NOT EXISTS review_flags (
        id         TEXT PRIMARY KEY,
        tree_uuid  TEXT NOT NULL,
        kind       TEXT NOT NULL CHECK (kind IN (
                       'appears_dead','appears_removed','duplicate_suspected',
                       'wrong_species','removed_but_active')),
        raised_by  TEXT,
        status     TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','confirmed','dismissed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_review_flags_tree ON review_flags(tree_uuid, status);

    -- -------------------------------------------------------------- tree_names --
    CREATE TABLE IF NOT EXISTS tree_names (
        id         TEXT PRIMARY KEY,
        tree_uuid  TEXT NOT NULL,
        name       TEXT NOT NULL,
        given_by   TEXT,
        status     TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','retired','removed_by_moderation')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );
    -- "One active name per tree. First namer wins." (D15)
    CREATE UNIQUE INDEX IF NOT EXISTS idx_tree_names_one_active
        ON tree_names(tree_uuid) WHERE status = 'active' AND deleted_at IS NULL;

    -- ------------------------------------------------------------------ outbox --
    -- BUILD-PLAN §4, "Client-side outbox (SQLite on device)", column for column.
    --
    -- Three columns are additions, each earning its place:
    --   seq              monotonic FIFO order. `created_at` alone cannot order two
    --                    items captured in the same instant, and FIFO is part of
    --                    the spec.
    --   json_synced      the JSON item and its photo binaries drain separately,
    --                    because the wifi-only toggle applies to binaries only.
    --                    Without this the two phases would need a fifth state,
    --                    and §4's state vocabulary is exactly four.
    --   window_started_at the start of the 48 h cap window. Distinct from
    --                    `created_at` so the user-visible retry button restarts
    --                    the window without rewriting when the work happened.
    --
    -- `next_attempt_at` is the materialized form of OutboxRetryPolicy's backoff so
    -- the drain can ask the database for due items instead of loading all of them.
    CREATE TABLE IF NOT EXISTS outbox (
        seq               INTEGER PRIMARY KEY AUTOINCREMENT,
        id                TEXT NOT NULL UNIQUE,
        kind              TEXT NOT NULL CHECK (kind IN (
                              'visit','observation','measurement','care_event','favorite_toggle')),
        client_uuid       TEXT NOT NULL UNIQUE,
        payload           TEXT NOT NULL CHECK (json_valid(payload)),
        photo_paths       TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(photo_paths)),
        state             TEXT NOT NULL DEFAULT 'pending'
                          CHECK (state IN ('pending','uploading','failed','done')),
        fail_count        INTEGER NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
        last_error        TEXT,
        last_error_code   TEXT,
        json_synced       INTEGER NOT NULL DEFAULT 0 CHECK (json_synced IN (0,1)),
        window_started_at TEXT NOT NULL,
        next_attempt_at   TEXT,
        created_at        TEXT NOT NULL,
        updated_at        TEXT NOT NULL,
        -- `done` means everything went: the JSON was applied and no photo binary
        -- is still waiting. Zero loss is a schema invariant, not a convention.
        CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))
    );
    CREATE INDEX IF NOT EXISTS idx_outbox_drain ON outbox(state, next_attempt_at, seq);
    CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at);

    -- --------------------------------------------------- hazard redirect log --
    -- POST /reports/hazard-redirect (BUILD-PLAN §6): analytics only, no public
    -- record. No note, no photo, no free text — it cannot become a hazard record
    -- by accretion.
    CREATE TABLE IF NOT EXISTS hazard_redirects (
        id        TEXT PRIMARY KEY,
        tree_uuid TEXT NOT NULL,
        category  TEXT NOT NULL CHECK (category IN (
                      'hanging_or_broken_limb','uprooted','struck_by_vehicle',
                      'blocking_signal_or_sightline')),
        shown_at  TEXT NOT NULL
    );
    """
}
