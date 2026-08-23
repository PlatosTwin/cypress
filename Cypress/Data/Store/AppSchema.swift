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
/// - private reminders can only hold hazard categories, carry no `stale_at` at all, and have
///   exactly one owner — a user or a device, never both, never neither (v3);
/// - favorites have exactly one owner too (v5), and are tombstoned rather than hard-deleted — a
///   `BEFORE DELETE` trigger that raises everywhere except the two cases it exists to protect: the
///   adoption merge at sign-in (v5) and the erasure of the deleting account's own rows (v6, R3);
/// - one active name per tree (D15) — a partial unique index;
/// - an outbox row can only be `done` once its JSON *and* its photos have gone;
/// - and nothing can have been *sent* that was not *applied* first (v15).
public enum AppSchema {
    /// Every migration, in order. Checked in, never edited after shipping — a new step gets a new
    /// version number.
    public static let migrations: [Migration] = [
        Migration(version: 1, name: "contributions and outbox", sql: v1),
        Migration(version: 2, name: "outbox photos carry their shot type", sql: v2),
        Migration(version: 3, name: "a private reminder can be owned by a device", migrate: applyV3),
        Migration(version: 4, name: "the outbox carries private reminders", migrate: applyV4),
        Migration(version: 5, name: "a favorite can be owned by a device", migrate: applyV5),
        Migration(version: 6, name: "an account's own rows go with the account", migrate: applyV6),
        Migration(version: 7, name: "a lead can locally mark a tree removed", sql: v7),
        Migration(version: 8, name: "a photo can be voted up or down", sql: v8),
        Migration(version: 9, name: "a vote can outlive the voter", migrate: applyV9),
        Migration(version: 10, name: "a coordinate says how it was arrived at", migrate: applyV10),
        Migration(version: 11, name: "a new tree says what ground it stands on", migrate: applyV11),
        Migration(version: 12, name: "a photograph says whose it is", migrate: applyV12),
        Migration(version: 13, name: "anonymized means anonymous, permanently", sql: v13),
        Migration(version: 14, name: "a species claim can be corrected, and the correction keeps it", migrate: applyV14),
        Migration(version: 15, name: "applying a mutation locally and sending it are two facts", migrate: applyV15),
        Migration(version: 16, name: "a photograph remembers which installation took it", migrate: applyV16),
        Migration(version: 17, name: "the nine mutations that never left the phone can be queued", migrate: applyV17),
        Migration(version: 18, name: "a staged binary is a row, so applying it and sending it are two facts", migrate: applyV18)
    ]

    /// The version a freshly migrated database reports.
    public static var currentVersion: Int32 { migrations.map(\.version).max() ?? 0 }

    // MARK: - v1

    // Historical, and not edited: this is the schema as it shipped, comments included. Where a later
    // step changed it, that step says so — `private_reminders`' owner rule below, the `outbox`
    // `kind` vocabulary, and `favorites`' owner and uniqueness rules were all superseded (v3, v4
    // and v5), and `outbox.json_synced` became `local_applied` beside a `remote_sent` (v15).
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
    -- §4). The unique pair is (user_id, tree_uuid); un-favoriting sets
    -- `deleted_at` and re-favoriting clears it, so one row carries the whole
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
    -- DELETE loses the un-favorite event and the row silently comes back on the
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

    // MARK: - v2

    /// `outbox.photo_paths` goes from a list of paths to a list of `{path, shotType}` objects.
    ///
    /// v1 stored the path alone, so the upload had nothing to send and labeled every binary
    /// `full_tree`. Whichever chip the contributor tapped on screen 04, the photo record came out a
    /// full-tree shot, which is what the ghost overlay lines the next visit up against and what A3
    /// picks as a tree's best photo. `photos.shot_type` is append-only: nothing recovers the truth
    /// afterwards, so the shot type has to travel with the binary from the outbox onwards.
    ///
    /// **Rows already on disk become `.other`, not `.full_tree`.** The outbox is durable across
    /// launches, so an upgrade meets pending rows written by the old build, and their real framing
    /// is not recorded anywhere. `full_tree` is the guess that caused the bug, and it is the one
    /// label that makes a photo eligible to become a ghost reference and a best photo — carrying it
    /// forward would keep a leaf close-up in that role forever. `other` is the stored vocabulary's
    /// unclassified value (BUILD-PLAN §4): the photo still uploads and still reaches the timeline,
    /// it is simply not promoted on a label nobody chose. `OutboxPhoto`'s decoder makes the same
    /// choice for the same reason.
    ///
    /// The column keeps its name. Renaming it would rewrite the table's CHECK constraints for a
    /// cosmetic gain, and the outbox is the one table that must not be rebuilt under a pending
    /// contributor's feet.
    ///
    /// Idempotent, per `Migration`: after the rewrite no element is a JSON text node, so a replay
    /// matches nothing. The guard reads `json_each`'s own `type` column rather than calling
    /// `json_type(value)`, which would re-parse a bare path as JSON and abort the whole migration.
    private static let v2 = """
    UPDATE outbox
       SET photo_paths = (
             SELECT COALESCE(json_group_array(json_object('path', value, 'shotType', 'other')), json('[]'))
               FROM json_each(outbox.photo_paths)
           )
     WHERE EXISTS (
             SELECT 1 FROM json_each(outbox.photo_paths) WHERE type = 'text'
           );
    """

    // MARK: - v3

    /// `private_reminders` gains a device owner, so D4's reminder can be written before there is an
    /// account (ERRATA E23).
    ///
    /// **What v1 got wrong.** v1 made `user_id` NOT NULL and said why: "a private reminder belongs
    /// to an account, so there is no anonymous variant that could later be attributed to the wrong
    /// person." D9 then keeps the device anonymous until the account ask at the third save, which is
    /// screen 15 and is not built — so the row was unwritable on every device the app runs on, and
    /// screen 06's "Save a private reminder for yourself" could not save. A sign-in wall inside a
    /// safety flow was the alternative, and standing under a broken limb is the worst moment in the
    /// product to ask someone to make an account.
    ///
    /// **The shape.** `user_id` becomes nullable, `device_id` appears beside it, and a CHECK makes
    /// exactly one of them non-null:
    ///
    /// ```sql
    /// CHECK ((user_id IS NULL) <> (device_id IS NULL))
    /// ```
    ///
    /// Not "nullable user_id plus a NOT NULL device_id". That shape leaves both columns populated
    /// after sign-in, which means the owner is whatever a query decides to COALESCE first, and it
    /// keeps a permanent device↔account link on a table whose entire purpose is privacy. Exclusive
    /// ownership makes the invariant the engine's job — a reminder can never be ownerless and never
    /// have two owners — and makes adoption a move rather than an addition: `POST /devices/claim`
    /// sets `user_id` and clears `device_id`, so the account gains a record and the device link
    /// disappears. Strictly less data after sign-in than before, which is the direction DECISIONS §3
    /// requires this to move in.
    ///
    /// The column is `device_id` rather than `device_uuid` because it holds exactly the value
    /// `visits.device_id`, `observations.device_id`, `measurements.device_id` and
    /// `care_events.device_id` hold, and one value should not have two names in one schema. It is
    /// D9's anonymous handle and nothing else: it identifies an installation, never a person.
    ///
    /// **One consequence, stated rather than discovered later.** DECISIONS §3.12 has account
    /// deletion anonymize attributed rows — "user_id nulled, device link severed" — and a private
    /// reminder cannot survive both of those, because it would then be owned by nobody. So when that
    /// path is built it has to choose, explicitly, between deleting reminders with the account and
    /// re-homing them onto the device. The CHECK is what forces the choice to be made rather than
    /// leaving behind a hazard note no query can ever return.
    ///
    /// **Existing rows survive.** Every row in a v1/v2 database is user-owned by construction, so
    /// the copy carries `user_id` across and leaves `device_id` NULL — which the new CHECK already
    /// accepts. SQLite cannot drop a NOT NULL or add a CHECK in place, so this is the documented
    /// 12-step table rebuild; nothing references `private_reminders`, so the drop is safe and the
    /// index is recreated afterwards.
    ///
    /// Idempotent by guard rather than by `IF NOT EXISTS`: a rebuild replayed against an
    /// already-rebuilt table would copy and re-drop live rows for no reason, so it asks the schema
    /// whether it has already run.
    private static func applyV3(_ connection: SQLiteConnection) throws {
        guard try !connection.columnNames(ofTable: "private_reminders").contains("device_id") else { return }
        try connection.execute("""
            CREATE TABLE private_reminders_owned (
                id         TEXT PRIMARY KEY,
                user_id    TEXT,
                device_id  TEXT,
                tree_uuid  TEXT NOT NULL,
                category   TEXT NOT NULL CHECK (category IN (
                               'hanging_or_broken_limb','uprooted','struck_by_vehicle',
                               'blocking_signal_or_sightline')),
                note       TEXT,
                photo_id   TEXT REFERENCES photos(id),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                -- Exactly one owner, always. A reminder nobody owns is a reminder nobody can read
                -- back, and one owned twice needs a precedence rule somewhere a query can get wrong.
                CHECK ((user_id IS NULL) <> (device_id IS NULL))
            );

            INSERT INTO private_reminders_owned
                (id, user_id, device_id, tree_uuid, category, note, photo_id,
                 created_at, updated_at, deleted_at)
            SELECT id, user_id, NULL, tree_uuid, category, note, photo_id,
                   created_at, updated_at, deleted_at
              FROM private_reminders;

            DROP TABLE private_reminders;
            ALTER TABLE private_reminders_owned RENAME TO private_reminders;

            CREATE INDEX IF NOT EXISTS idx_private_reminders_user
                ON private_reminders(user_id, created_at DESC);
            -- The pre-sign-in read, and the one `POST /devices/claim` drives.
            CREATE INDEX IF NOT EXISTS idx_private_reminders_device
                ON private_reminders(device_id, created_at DESC);
            """)
    }

    // MARK: - v4

    /// `outbox.kind` learns `private_reminder`.
    ///
    /// The reminder is a mutation, so it goes through the outbox like every other one: written to
    /// disk first, attempted after (ARCHITECTURE §4). v1's `kind` CHECK is a closed vocabulary of
    /// five and SQLite cannot widen a CHECK in place, so the table is rebuilt.
    ///
    /// **This is the rebuild v2 declined to do, and the reason it declined does not apply.** v2 kept
    /// `photo_paths` under its old name rather than rebuild "the one table that must not be rebuilt
    /// under a pending contributor's feet" — for a *cosmetic* gain. Here the alternative is that the
    /// row cannot be written at all. The copy is column for column and carries `seq`, so FIFO order,
    /// retry counts, error text, the 48 h window and the photo lists all come across untouched; a
    /// contributor with a queued visit sees the same queue in the same order afterwards. `seq` is
    /// copied explicitly, which is also what re-seeds `sqlite_sequence` for the AUTOINCREMENT
    /// column, so no id is ever reused.
    ///
    /// Idempotent by guard, for the reason v3 gives.
    private static func applyV4(_ connection: SQLiteConnection) throws {
        let existing = try outboxDefinition(connection: connection)
        guard !existing.contains("private_reminder") else { return }
        try connection.execute("""
            CREATE TABLE outbox_with_reminders (
                seq               INTEGER PRIMARY KEY AUTOINCREMENT,
                id                TEXT NOT NULL UNIQUE,
                kind              TEXT NOT NULL CHECK (kind IN (
                                      'visit','observation','measurement','care_event',
                                      'favorite_toggle','private_reminder')),
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
                CHECK (state <> 'done' OR (json_synced = 1 AND json_array_length(photo_paths) = 0))
            );

            INSERT INTO outbox_with_reminders
                (seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                 last_error, last_error_code, json_synced, window_started_at,
                 next_attempt_at, created_at, updated_at)
            SELECT seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                   last_error, last_error_code, json_synced, window_started_at,
                   next_attempt_at, created_at, updated_at
              FROM outbox;

            DROP TABLE outbox;
            ALTER TABLE outbox_with_reminders RENAME TO outbox;

            CREATE INDEX IF NOT EXISTS idx_outbox_drain ON outbox(state, next_attempt_at, seq);
            CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at);
            """)
    }

    // MARK: - v5

    /// `favorites` gains a device owner, so the heart on screen 03 has somewhere to write (E89).
    ///
    /// **The same decision E23 took for private reminders, taken deliberately a second time rather
    /// than by precedent.** v1 made `favorites.user_id` NOT NULL with no device column, and D9 keeps
    /// every device anonymous until the account ask at the third save — so the row was unwritable on
    /// every device the app runs on, and `RootView` no-opped the heart because there was nothing
    /// honest for it to do. PRODUCT §Conflicts 22 names this exact hole: "offline favorites are
    /// listed as outbox mutations, but favoriting is also the account-gate trigger — behavior for an
    /// anonymous offline favorite is undefined". D9 defines it: the device holds it until an account
    /// arrives.
    ///
    /// **The shape**, identical to v3's: `user_id` becomes nullable, `device_id` appears beside it,
    /// and `CHECK ((user_id IS NULL) <> (device_id IS NULL))` makes exactly one of them non-null.
    /// Nullable user beside a NOT NULL device was rejected there for reasons that hold here too — it
    /// leaves both columns populated after sign-in, so the owner becomes whichever column a query
    /// coalesces first, and it keeps a permanent device↔account link. Exclusive ownership makes
    /// adoption a *move*: the row carries strictly less about the device afterwards than before.
    ///
    /// **What the UNIQUE constraint became, which is the part v3 did not have to answer.** v1 carried
    /// `UNIQUE (user_id, tree_uuid)`, and the pair has to survive becoming an ownership pair. Two
    /// partial unique indexes replace it:
    ///
    /// ```sql
    /// CREATE UNIQUE INDEX … ON favorites(user_id, tree_uuid)   WHERE user_id   IS NOT NULL;
    /// CREATE UNIQUE INDEX … ON favorites(device_id, tree_uuid) WHERE device_id IS NOT NULL;
    /// ```
    ///
    /// One owner cannot favorite a tree twice; two different owners can each favorite it. A single
    /// `UNIQUE (user_id, device_id, tree_uuid)` would have enforced *nothing* for device rows: SQL
    /// treats NULLs as distinct inside a unique index, so `(NULL, this device, this tree)` would be
    /// storable any number of times. A single expression index over `COALESCE(user_id, device_id)`
    /// would work, but it puts two id spaces in one comparison and re-introduces the coalesced owner
    /// v3 refused; two indexes say the two sentences separately.
    ///
    /// **The trigger keeps its job and gains one exception.** Its reason is stated in v1: a stray
    /// `DELETE` loses the un-favorite *event*, so the row comes back on the next sync from another
    /// device. Adoption is the one delete that loses no event, because the event has already been
    /// folded onto the surviving row for the same tree in the same transaction (see
    /// `ContributionStore.claimDevice`). The `WHEN` clause permits exactly that case — a device-owned
    /// row for a tree an account already holds — and refuses everything else, including a
    /// device-owned row with no account row beside it.
    ///
    /// **Existing rows survive.** Every row in a v1–v4 database is user-owned by construction, so the
    /// copy carries `user_id` across and leaves `device_id` NULL, which the new CHECK accepts; and
    /// the old `UNIQUE (user_id, tree_uuid)` already guaranteed what the new user index requires, so
    /// the copy cannot collide. SQLite cannot drop a NOT NULL or replace a UNIQUE in place, so this
    /// is the documented table rebuild; nothing references `favorites`, and dropping the table drops
    /// its trigger, which is recreated below in its new form.
    ///
    /// Idempotent by guard rather than by `IF NOT EXISTS`, for the reason v3 gives.
    private static func applyV5(_ connection: SQLiteConnection) throws {
        guard try !connection.columnNames(ofTable: "favorites").contains("device_id") else { return }
        try connection.execute("""
            CREATE TABLE favorites_owned (
                id          TEXT PRIMARY KEY,
                user_id     TEXT,
                device_id   TEXT,
                tree_uuid   TEXT NOT NULL,
                client_uuid TEXT NOT NULL,
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL,
                deleted_at  TEXT,
                -- Exactly one owner, always. A favorite nobody owns is in nobody's grove, and one
                -- owned twice needs a precedence rule somewhere a query can get wrong.
                CHECK ((user_id IS NULL) <> (device_id IS NULL))
            );

            INSERT INTO favorites_owned
                (id, user_id, device_id, tree_uuid, client_uuid, created_at, updated_at, deleted_at)
            SELECT id, user_id, NULL, tree_uuid, client_uuid, created_at, updated_at, deleted_at
              FROM favorites;

            DROP TABLE favorites;
            ALTER TABLE favorites_owned RENAME TO favorites;

            CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_user_tree
                ON favorites(user_id, tree_uuid) WHERE user_id IS NOT NULL;
            CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_device_tree
                ON favorites(device_id, tree_uuid) WHERE device_id IS NOT NULL;

            CREATE TRIGGER IF NOT EXISTS favorites_are_tombstoned
            BEFORE DELETE ON favorites
            WHEN OLD.device_id IS NULL
              OR NOT EXISTS (SELECT 1 FROM favorites other
                              WHERE other.tree_uuid = OLD.tree_uuid AND other.user_id IS NOT NULL)
            BEGIN
                SELECT RAISE(ABORT, 'favorites are tombstoned via deleted_at, never hard-deleted');
            END;
            """)
    }

    // MARK: - v6

    /// The tombstone trigger gains its second exception, so account deletion can delete the rows
    /// only that account could ever read (RULINGS R3, closing the question E23 and E89 left OPEN).
    ///
    /// **The conflict this closes.** DECISIONS §3.12 says deletion anonymizes attributed rows —
    /// `user_id` nulled, the device link severed — rather than removing them. v3 and v5 then gave
    /// `private_reminders` and `favorites` a `CHECK ((user_id IS NULL) <> (device_id IS NULL))`, so
    /// an exclusively-owned row cannot survive being anonymized: nulling its `user_id` leaves it
    /// owned by nobody, which the engine refuses, and re-homing it onto the device would hand one
    /// person's private records to whoever holds the phone next. R3 rules that these rows are
    /// deleted, because §3.12 anonymizes *contributions* — things the forest keeps, whose value does
    /// not depend on who made them — and a reminder nobody but its owner can read is not one.
    ///
    /// **Why the schema has to change at all.** v5's trigger refuses every `DELETE FROM favorites`
    /// except the adoption merge, and it refuses a user-owned row first of all (`OLD.device_id IS
    /// NULL` is the leading arm). So the erasure R3 orders is, today, unwritable — the same shape of
    /// bug E89 fixed in the other direction, where the row could not be created.
    ///
    /// **The exception is a sentinel, not a hole.** A row may be deleted when a row in `app_state`
    /// names its owner as the account currently being erased. `AccountDeletion` writes that key,
    /// deletes, and clears the key, all inside one transaction — so the permission exists only for
    /// the statements that need it, only for one named account, and cannot outlive the transaction
    /// even if the process dies mid-way, because the rollback takes the sentinel with it. A trigger
    /// cannot read a `temp` table (SQLite forbids a trigger referencing another database), which is
    /// why the sentinel lives in `main.app_state` beside the settings rather than in a scratch table.
    ///
    /// The comparison is written as `EXISTS`, deliberately. `OLD.user_id = (SELECT value …)` reads
    /// naturally and is **wrong**: with no sentinel row the subquery is NULL, the comparison is NULL,
    /// `NOT (0 OR NULL)` is NULL, and a `WHEN` clause that evaluates to NULL does not fire — so the
    /// trigger would permit every hard delete of a user-owned favorite on a database where nobody
    /// is being deleted at all. `EXISTS` is 0 or 1 and never NULL. `DataGates` asserts the
    /// no-sentinel case for exactly this reason.
    ///
    /// The key is spelled out here rather than interpolated from `AccountDeletion.erasureSentinelKey`
    /// because a migration is frozen text: interpolating a Swift constant would let a later rename
    /// silently change what new databases get while leaving upgraded ones on the old string.
    /// `AccountDeletionTests` pins that the constant and this text still agree.
    ///
    /// **No table is rebuilt and nothing is copied**, so this needs no `applyV3`-style guard: `DROP
    /// TRIGGER IF EXISTS` followed by `CREATE TRIGGER` is idempotent by construction, and a replay
    /// after an interrupted run lands on the same definition.
    private static func applyV6(_ connection: SQLiteConnection) throws {
        try connection.execute("""
            DROP TRIGGER IF EXISTS favorites_are_tombstoned;

            CREATE TRIGGER favorites_are_tombstoned
            BEFORE DELETE ON favorites
            WHEN NOT (
                    -- v5: the adoption merge. A device-owned row whose event has just been folded
                    -- onto the account's row for the same tree, in the same transaction.
                    (OLD.device_id IS NOT NULL
                     AND EXISTS (SELECT 1 FROM favorites other
                                  WHERE other.tree_uuid = OLD.tree_uuid
                                    AND other.user_id IS NOT NULL))
                    -- v6: account erasure (R3). Only rows owned by the account named in the
                    -- sentinel, and only while that sentinel is set.
                 OR (OLD.user_id IS NOT NULL
                     AND EXISTS (SELECT 1 FROM app_state
                                  WHERE key = 'account_deletion_user_id'
                                    AND value = OLD.user_id COLLATE NOCASE))
                )
            BEGIN
                SELECT RAISE(ABORT, 'favorites are tombstoned via deleted_at, never hard-deleted');
            END;
            """)
    }

    // MARK: - v7

    /// A device-side layer of tree-status overrides — the first place in the iOS app that can make a
    /// tree's status differ from the inventory's (ERRATA E124-B).
    ///
    /// **Why this table exists, and why it is a separate layer rather than an UPDATE.** The seed's
    /// `trees` are read-only by construction (they live in an ATTACHed database), and `community_trees`
    /// is insert-only — nothing in the app has ever transitioned a tree's status, because a status
    /// transition was a *moderator* action and moderator surfaces were scoped to the web
    /// (`CypressAPI`'s header omits `/admin/*`; `TreeStatus` says "a moderator or org coordinator
    /// confirms"; DECISIONS §3.7). The local beta brings that confirmation on-device (the project
    /// owner's moderation route), and this is how it stays honest: a confirmation records an *override*
    /// keyed on the tree's stable UUID rather than mutating an inventory row that the weekly city diff
    /// still owns. `LocalAPI` reads the tree, then layers the override on top — the same shape the
    /// future `removed_but_active` reconciliation would take. When a real diff or a real moderator
    /// service lands, this table is what it writes through, unchanged.
    ///
    /// `set_by` is the account that confirmed it (a lead), for the same reason `review_flags.raised_by`
    /// records who raised one. One row per tree — a second confirmation replaces the first — because a
    /// tree has one current status, whatever the history of flags behind it.
    private static let v7 = """
    CREATE TABLE IF NOT EXISTS tree_status_overrides (
        tree_uuid  TEXT PRIMARY KEY,
        status     TEXT NOT NULL CHECK (status IN (
                       'alive','declining','dead_reported','removed','vacant_site')),
        set_by     TEXT,
        created_at TEXT NOT NULL
    );
    """

    // MARK: - v8

    /// A thumbs up or down on one photograph — the mechanism that decides which photo is a tree's
    /// hero (ERRATA E125).
    ///
    /// **Why a vote and not a favorite.** D1 removed the version of `favorites` that was a public
    /// vote, and `ContributionStore.isFavorite` says why: a favorite is a private bookmark, and
    /// there is deliberately no "is anybody's favorite" query. This is the opposite kind of thing.
    /// A vote here is a *contribution* in DECISIONS §3.12's sense — a judgment about the record
    /// that the forest keeps and that other people read off — because what it decides, the hero, is
    /// the photograph everybody looking at that tree sees. So it aggregates: `PhotoHero` sums the
    /// column across contributors rather than reading one person's row.
    ///
    /// **The owner columns are `favorites`' (v5), for `favorites`' reason.** A vote is cast before
    /// there is an account as often as after — D9's whole shape — so exactly one owner, a user or a
    /// device, enforced by the same `CHECK` and the same pair of partial unique indexes. One vote
    /// per owner per photo; changing your mind is an upsert, and taking it back is a `DELETE`.
    ///
    /// **No tombstone trigger, unlike `favorites`.** A withdrawn favorite has to leave a trace,
    /// because v5's adoption merge and R3's erasure both need to find the row. A withdrawn vote does
    /// not: an un-vote is the absence of a judgment, and a zero score and no row are the same fact.
    /// Account erasure therefore just deletes, with no sentinel to open the gate.
    ///
    /// `tree_uuid` is denormalized out of `photos` so the profile can read a whole tree's tally in
    /// one indexed scan; it is written from the photo's own row and never from a caller's argument.
    private static let v8 = """
    CREATE TABLE IF NOT EXISTS photo_votes (
        id         TEXT PRIMARY KEY,
        photo_id   TEXT NOT NULL REFERENCES photos(id),
        tree_uuid  TEXT NOT NULL,
        user_id    TEXT,
        device_id  TEXT,
        vote       INTEGER NOT NULL CHECK (vote IN (-1, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK ((user_id IS NULL) <> (device_id IS NULL))
    );

    CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_votes_user
        ON photo_votes(user_id, photo_id) WHERE user_id IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_votes_device
        ON photo_votes(device_id, photo_id) WHERE device_id IS NOT NULL;
    CREATE INDEX IF NOT EXISTS idx_photo_votes_tree ON photo_votes(tree_uuid);
    """

    // MARK: - v9

    /// `photo_votes` gains the one state v8 forbade: a vote with no owner at all, which is what a
    /// vote becomes when the person who cast it deletes their account and asks for their
    /// contributions to be left where they are (the project owner's two-door ruling; see
    /// `AccountDeletionChoice`).
    ///
    /// **Why the schema has to change.** v8 wrote `CHECK ((user_id IS NULL) <> (device_id IS NULL))`
    /// — exactly one owner — copying `favorites`, and gave the reason: one vote per owner per photo
    /// is the whole of a ballot's integrity. That reasoning is about a *live* vote, and it is right
    /// about live votes. It has one consequence nobody costed at the time: an account's vote cannot
    /// be anonymized. Nulling `user_id` leaves a row the engine refuses, and re-homing it onto
    /// `device_id` would hand one person's ballot to whoever picks the phone up next — and worse
    /// here than for a favorite, because the next person could then *change* it. So R3's deletion
    /// deleted votes, and `AccountDeletion` documented that as a ruling ("it goes with the account")
    /// when it was really a constraint wearing a ruling's clothes.
    ///
    /// **What the two doors need.** The default door leaves contributions in place, and a vote is a
    /// contribution in DECISIONS §3.12's sense — v8 says so itself, at length, and it is the whole
    /// reason `photo_votes` is not `favorites`. What it decides, the hero, is the photograph
    /// everybody looking at that tree sees. Deleting it silently changes what strangers see, which is
    /// the opposite of leaving contributions where they are.
    ///
    /// **The new CHECK: at most one owner, rather than exactly one.**
    ///
    /// ```sql
    /// CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL))
    /// ```
    ///
    /// An ownerless vote is not a hole in v8's integrity rule, it is that rule's terminal state. Both
    /// unique indexes are already partial — `WHERE user_id IS NOT NULL`, `WHERE device_id IS NOT
    /// NULL` — so an ownerless row is in neither, and "one vote per owner per photo" still binds
    /// every owner there is. `setPhotoVote`'s `ON CONFLICT` targets those same partial indexes, so an
    /// ownerless row can never be the conflict target of somebody else's vote and can never be
    /// upserted over. `clearPhotoVote` matches on an owner and so can never match one either.
    /// `photoTallies` sums `vote` across the whole photo without looking at the owner, so the score
    /// is unchanged, and its `own` column is guarded by `:user IS NOT NULL AND user_id = :user`, so
    /// an ownerless row contributes zero to everybody's own-vote and never lights up somebody else's
    /// thumb. The row is, exactly, frozen: it counts, it cannot be changed, and it cannot be
    /// withdrawn. That is the correct set of powers for a judgment whose author is gone — you do
    /// not get to change your mind after you have left.
    ///
    /// **Why not a sentinel owner instead.** A "deleted account" id would satisfy v8's CHECK with no
    /// migration, and it was rejected on privacy grounds that `AccountDeletionChoice` argues in full:
    /// a stable id across every row one person wrote is a pseudonym, and a pseudonym over dated,
    /// located field records in one city re-identifies. A single shared sentinel would additionally
    /// collide on `idx_photo_votes_user` the moment two deleted accounts had voted on the same
    /// photograph, and the collision would surface as a *deletion that fails*, which is the worst
    /// place in this app for a UNIQUE violation to appear.
    ///
    /// **Existing rows survive unchanged and cannot collide.** Every row in a v8 database satisfies
    /// exactly-one-owner, which implies at-most-one-owner, so the copy is column-for-column and the
    /// new CHECK accepts all of it; the two indexes are recreated with the same definitions, and the
    /// old ones guaranteed what the new ones require. SQLite cannot alter a CHECK in place, so this
    /// is the documented table rebuild v3 and v5 both used. `photo_votes` has no trigger and nothing
    /// references it, so dropping it drops nothing else.
    ///
    /// **Idempotent by guard**, and the guard reads `sqlite_master` rather than `pragma_table_info`
    /// for `outboxDefinition`'s reason: a CHECK is not a column, so the only place the old constraint
    /// is visible is the stored `CREATE TABLE` text.
    private static func applyV9(_ connection: SQLiteConnection) throws {
        let existing = try tableDefinition(named: "photo_votes", connection: connection)
        guard existing.contains("(user_id IS NULL) <> (device_id IS NULL)") else { return }
        try connection.execute("""
            CREATE TABLE photo_votes_unowned (
                id         TEXT PRIMARY KEY,
                photo_id   TEXT NOT NULL REFERENCES photos(id),
                tree_uuid  TEXT NOT NULL,
                user_id    TEXT,
                device_id  TEXT,
                vote       INTEGER NOT NULL CHECK (vote IN (-1, 1)),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                -- At most one owner. A vote owned twice still needs a precedence rule somewhere a
                -- query could get wrong, so that half of v8's CHECK stays. A vote owned by nobody is
                -- now reachable, and only one thing reaches it: an account deletion whose owner
                -- chose to leave their contributions on the trees.
                CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL))
            );

            INSERT INTO photo_votes_unowned
                (id, photo_id, tree_uuid, user_id, device_id, vote, created_at, updated_at)
            SELECT id, photo_id, tree_uuid, user_id, device_id, vote, created_at, updated_at
              FROM photo_votes;

            DROP TABLE photo_votes;
            ALTER TABLE photo_votes_unowned RENAME TO photo_votes;

            CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_votes_user
                ON photo_votes(user_id, photo_id) WHERE user_id IS NOT NULL;
            CREATE UNIQUE INDEX IF NOT EXISTS idx_photo_votes_device
                ON photo_votes(device_id, photo_id) WHERE device_id IS NOT NULL;
            CREATE INDEX IF NOT EXISTS idx_photo_votes_tree ON photo_votes(tree_uuid);
            """)
    }

    // MARK: - v10

    /// `community_trees` learns where its coordinate came from: the phone's fix, or a pin the
    /// contributor placed by hand.
    ///
    /// **The hole this closes.** The add screen has been able to move the pin since the movable-pin
    /// round, and it models the distinction — `VisitAddTreeModel.Placement` — and states it on screen.
    /// The row did not carry it. That round declined to invent a migration and wrote down exactly why
    /// the fact had nowhere to go: `lat` and `lon` are the pair, `address` is a street address,
    /// `external_ref` is the city's own identifier for an inventory row, and `site_type` is where a
    /// tree is planted. Writing a flag into any of those makes a column mean two things, and the next
    /// reader finds out the hard way. So it needs its own column, and the project owner has now ruled
    /// that it gets one.
    ///
    /// **This is provenance, and it is filed with the provenance the table already keeps.** `source`
    /// says who put the record here and `verification_state` says who has stood behind it; BUILD-PLAN
    /// §5 requires that every provenance fact be a queryable column rather than something a screen
    /// knows. `placement` is the third sentence of the same paragraph, and deliberately not a fourth
    /// vocabulary of trustworthiness — a hand-placed pin is not a lesser coordinate, and is very often
    /// the better one. See `TreePlacement`, which carries that argument in full.
    ///
    /// **The shape, and why it is not quite the one that was proposed.** The earlier note proposed
    /// `placement TEXT NOT NULL DEFAULT 'gps'`. Every other closed vocabulary in this schema also
    /// carries its vocabulary in a CHECK — `source`, `status`, `verification_state`, `shot_type`,
    /// `moderation_state`, `kind`, `category`, `unit_entered`, `method` — because the invariant is
    /// meant to hold against a hand-written `INSERT` in a debugger as well as against the DAO, which
    /// is what this file's own header promises. A bare TEXT column would accept `'GPS'`, `'true'` and
    /// `''`, and `CommunityTreeStore.decode` would then throw on a row the engine had accepted. So:
    ///
    /// ```sql
    /// placement TEXT NOT NULL DEFAULT 'gps' CHECK (placement IN ('gps','contributor_placed'))
    /// ```
    ///
    /// **`ALTER TABLE ADD COLUMN`, not a table rebuild.** v3, v5 and v9 each rebuilt their table
    /// because SQLite cannot drop a NOT NULL, replace a UNIQUE or widen a CHECK in place. None of
    /// those apply here: nothing existing changes, and SQLite does accept a CHECK on an added column
    /// (it declines only PRIMARY KEY and UNIQUE), and enforces it from that moment on. A rebuild would
    /// copy every community tree in the database to gain nothing, and copying rows is the one thing in
    /// a migration that can lose them.
    ///
    /// **The default is `'gps'`, and it is a true statement about every row it touches.** Every
    /// community tree written before this column existed was written at `location.fix.coordinate`
    /// verbatim — the add screen had no other behavior — so backfilling them as `gps` records what
    /// actually happened rather than guessing. This is the opposite of v2's situation, where the old
    /// rows' real value was unrecorded and the plausible guess was the harmful one; here the history
    /// is known. It is also the direction that fails safe if it is ever wrong: a row mislabeled `gps`
    /// under-claims, and the failure this column must never have is a coordinate silently claiming to
    /// have been placed by somebody who never touched it.
    ///
    /// **No distance column, and that was argued rather than skipped.** A pin dropped 3 m from the fix
    /// and one dropped 74 m away are different claims, and storing the offset was on the table. Three
    /// things decided against it. It is measured from an anchor whose own error is the reason the pin
    /// exists — a 40 m street-canyon fix — so "74 m" is 74 ± 40, and `community_trees` is the one
    /// contribution table with no `gps_accuracy_m` column to say so; storing a REAL to millimeters
    /// against an anchor that vague dresses an estimate as a measurement, which is precisely what D7
    /// refuses for the city's DBH buckets. It would be the only continuous quantity in a provenance
    /// vocabulary that is otherwise categorical, and a number invites ranking in a way a category does
    /// not — 74 m starts looking like a worse tree. And it re-introduces the contributor's own
    /// position: the coordinate plus the offset puts the person who added the tree on a circle of
    /// known radius around it, which is the fact A7 fuzzes photo coordinates to a 25 m grid to avoid.
    /// Doing it honestly would need the accuracy and the anchor as well, and the anchor is a record of
    /// where somebody stood. If a moderator surface later shows it needs the distance, that is the
    /// migration to write, with those columns and that argument.
    ///
    /// **Idempotent by guard**, in v3's shape: `ALTER TABLE ADD COLUMN` has no `IF NOT EXISTS`, so a
    /// replay after an interrupted run would fail on "duplicate column name" and strand the database
    /// one version short.
    private static func applyV10(_ connection: SQLiteConnection) throws {
        guard try !connection.columnNames(ofTable: "community_trees").contains("placement") else { return }
        try connection.execute("""
            ALTER TABLE community_trees
                ADD COLUMN placement TEXT NOT NULL DEFAULT 'gps'
                CHECK (placement IN ('gps','contributor_placed'));
            """)
    }

    // MARK: - v11

    /// `community_trees` learns what ground the tree stands on: a street, a city park, private
    /// property, or other public land.
    ///
    /// **Only the app database moves, and establishing that was the first job.** The six DataSF
    /// columns this round ingests — `legal_status`, `caretaker`, `care_assistant`, `plant_type`,
    /// `plot_size`, `permit_notes` — all land on `seed.trees`, and the seed is a *bundled, read-only*
    /// database ATTACHed beside `main`. It ships as a build product of `Tools/build_seed.py` and is
    /// replaced wholesale on install, so a schema change there needs no migration at all and cannot
    /// have one: there is no user data in it to carry forward. Every one of those six columns
    /// therefore arrives with the new binary and this file is silent about them. What is *not*
    /// covered by that is a fact a contributor states about a tree they are adding, which has to be
    /// written, has to survive an upgrade, and has nowhere in the seed to live. That is this column,
    /// and it is the only reason v11 exists.
    ///
    /// **Why it is not `site_type`.** `community_trees.site_type` already exists and already carries
    /// the city's `qSiteInfo` vocabulary as free text — "Sidewalk: Curb side : Cutout", "Front Yard :
    /// Yard", "Median : Cutout". It describes the *planting site*: what the tree is growing in and
    /// where on the frontage. It is not a statement about whose ground that is, and reusing it would
    /// make one column mean two things, which v10 refused for exactly the same reason one round ago.
    ///
    /// **The vocabulary is four values and the owner asked for three, deliberately.** The ask was
    /// "street / city park / private property". The city's own inventory contains 956 rows that are
    /// none of the three: trees whose caretaker is SFUSD, the Port, the PUC, the Housing Authority,
    /// the Fire Department, the Arts Commission — public land that is neither a street nor a park. A
    /// CHECK pinned to three would have made those unstorable the moment anything tried to record
    /// one, which is precisely E136's `photo_votes` failure repeated: a constraint wearing a ruling's
    /// clothes, forbidding a state the product turns out to need and costing a migration to relax.
    /// The asymmetry decides it. A permitted value that no screen offers costs nothing — there is no
    /// way to reach it and nothing renders it. A forbidden value the data contains costs a migration.
    /// So the column permits four and #69's picker is free to offer three.
    ///
    /// What the CHECK does forbid, and it is meant to: any string outside the four. `''`, `'Street'`,
    /// `'private'`, `'park'` and a typo'd `'city-park'` are all rejected by the engine rather than
    /// accepted by it and then thrown on by `CommunityTreeStore.decode`, which is this file's
    /// standing promise — the invariant holds against a hand-written `INSERT` in a debugger, not only
    /// against the DAO. The same promise is deliberately *not* extended to the six seed columns, for
    /// reasons `Tools/build_seed.py` carries in full: those hold San Francisco's vocabulary rather
    /// than Cypress's, the city may add to it any week, and a CHECK over 27 department names is a
    /// build failure waiting for a reorganization.
    ///
    /// **NULL is a value here, and it is "not stated".** The column is nullable with no default,
    /// unlike v10's `placement`, and the two situations are genuinely different. Every community tree
    /// written before v10 *had* a placement — `gps`, because the screen had no other behavior — so
    /// backfilling it recorded what actually happened. No tree written before v11 has ever been asked
    /// what ground it stands on, so there is no true value to backfill and any default would be
    /// Cypress putting words in a contributor's mouth. `'street'` would be the plausible guess and
    /// the harmful one: it is the answer that makes a tree look like the city's business, and a wrong
    /// `'street'` on a tree in somebody's front yard is the direction that ends in a 311 call about a
    /// tree 311 does not handle. Absent stays absent. BUILD-PLAN §6 already makes the field optional
    /// at the boundary, and `LandContext.inferred(from:)` can still read a city row's context from
    /// the city's record without this column existing for it.
    ///
    /// **`ALTER TABLE ADD COLUMN`, not a table rebuild**, on v10's argument: nothing existing
    /// changes, SQLite accepts a CHECK on an added column and enforces it from that moment, and
    /// copying rows is the one thing in a migration that can lose them.
    ///
    /// **Idempotent by guard**, in v3's and v10's shape: `ALTER TABLE ADD COLUMN` has no
    /// `IF NOT EXISTS`, so a replay after an interrupted run would fail on "duplicate column name"
    /// and strand the database one version short.
    private static func applyV11(_ connection: SQLiteConnection) throws {
        guard try !connection.columnNames(ofTable: "community_trees").contains("land_context") else { return }
        try connection.execute("""
            ALTER TABLE community_trees
                ADD COLUMN land_context TEXT
                CHECK (land_context IS NULL
                       OR land_context IN ('street','city_park','private_property','other_public'));
            """)
    }

    // MARK: - v12

    /// `photos` learns whose it is, which is the column ERRATA **E136** left open and the column
    /// "delete your own photograph" cannot be built without.
    ///
    /// **The hole, restated.** A photograph's only tie to a person was `visit_id`, and from there
    /// `visits.user_id`. `LocalAPI.addTree` writes a photograph with **no visit** — a community add
    /// requires a photograph (BUILD-PLAN §6) and there is no visit to hang it on — and
    /// `community_trees` records no author either. So the photograph on a tree you added was
    /// attributable to nobody, and neither door of account deletion could reach it: "erase
    /// everything I contributed" left a JPEG on disk that no query could name as yours. That is a
    /// broken promise rather than a missing feature, which is why it is a migration and not a
    /// backlog item.
    ///
    /// **Why the owner goes on `photos` and not on `community_trees`.** E136 and
    /// `AccountDeletion.photoBytes` both wrote "closing it needs an owner on `community_trees`", and
    /// this is a deliberate departure from that sentence. An owner on the tree only answers the
    /// question by *derivation* — "the photographs of a tree you added, that have no visit" — and
    /// `photoBytes` already records why a derived predicate is the wrong instrument here: widen it
    /// by one clause and it starts deleting other people's work. It also stops being true the day
    /// anything else writes a visitless photograph (a care event may already carry one), and it
    /// cannot answer the question for the *ordinary* case at all — a photograph taken on a visit to
    /// a city tree, which is most photographs in the app and which "delete your own photograph"
    /// must also cover. One column pair on the row that is being deleted answers all of it with one
    /// predicate. The tree row still records no author, deliberately: it is a public object, no
    /// screen names its contributor (screen 03 says "a contributor"), and neither deletion door
    /// needs it — a community tree survives both doors today and still does, because "everything I
    /// have added" is the person's rows and not the forest.
    ///
    /// **The CHECK is at most one owner, not exactly one, and that is the whole lesson of E136.**
    ///
    /// ```sql
    /// CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL))
    /// ```
    ///
    /// `private_reminders` (v3) and `favorites` (v5) are `(user_id IS NULL) <> (device_id IS NULL)`
    /// — exactly one owner — and copying that here would have been the obvious move and a bug with
    /// a migration already scheduled behind it. Those two tables are *deleted* with their account
    /// under both doors, so an ownerless row is a state they never need. A photograph is not: the
    /// default door's entire promise is that the work stays and the name comes off, so an ownerless
    /// photograph is not a hole in the rule, it is the rule's terminal state — exactly the argument
    /// v9 had to make for `photo_votes` after v8 forbade it. Ask what a constraint forbids, not only
    /// what it permits: exactly-one-owner would have forbidden anonymization, so the anonymizing
    /// door would have had to choose between deleting the photograph (breaking its own promise) and
    /// re-homing it onto the device (handing one person's photograph to whoever picks the phone up
    /// next). Both are worse than the constraint being one clause weaker.
    ///
    /// What it still forbids, and means to: a photograph owned twice. Two owners need a precedence
    /// rule somewhere a query can get it wrong, and adoption at sign-in stays a *move* — the account
    /// gains the row and the device link is dropped in the same statement, so the row carries
    /// strictly less about the device afterwards than before (E23's reason, restated).
    ///
    /// **The backfill, and what it assumes.** Every row in `main.photos` was written by this
    /// installation: `beginPhotoUpload` and `addTree` are the only writers, both run in `LocalAPI`,
    /// and nothing syncs anybody else's photographs down (`LocalAPI.treeProfile` states the same
    /// fact where it fills `ownPhotoIDs`). So:
    ///
    /// 1. A photograph with a visit takes the visit's owner — `user_id` when the visit has one, and
    ///    the visit's `device_id` otherwise. A visit carries both columns and always has a device;
    ///    a photograph carries at most one, so the copy collapses to whichever the visit's owner
    ///    actually is.
    /// 2. A photograph with no visit takes this installation's own identity — the signed-in account
    ///    if there is one, `app_state.device_uuid` if there is not. That is precisely what
    ///    `FavoriteOwner(_ attribution:)` would have written at the time, applied retroactively,
    ///    and it is what makes an already-added tree's photograph erasable by the person who added
    ///    it instead of stranded for the life of the install. It can over-attribute in one case — a
    ///    photograph taken on this phone before a *different* person signed in — and that is the
    ///    same over-attribution `claimDevice` already performs on every visit, recorded in E136 as
    ///    the owner's to rule on, not a new hole opened here.
    /// 3. Anything left over stays ownerless, which the CHECK permits: a database with no
    ///    `device_uuid` has never contributed anything.
    ///
    /// **`ALTER TABLE ADD COLUMN`, not a rebuild**, on v10's and v11's argument: nothing existing
    /// changes, SQLite enforces a CHECK on an added column from the moment it is added, and copying
    /// rows is the one thing in a migration that can lose them. A CHECK in an added column's
    /// definition may reference other columns of the table — SQLite does not distinguish column
    /// constraints from table constraints — so the pair rule is expressible without a rebuild.
    ///
    /// **No index.** `photos` holds tens of rows per install, `idx_photos_tree` already serves the
    /// timeline, and the two owner queries are an account deletion (once, ever) and "is this one
    /// mine" (by primary key). An index here would be a line of DDL that never changes a plan.
    ///
    /// **Idempotent by guard**, in v3's, v10's and v11's shape: `ALTER TABLE ADD COLUMN` has no
    /// `IF NOT EXISTS`, so a replay after an interrupted run would fail on "duplicate column name"
    /// and strand the database one version short.
    private static func applyV12(_ connection: SQLiteConnection) throws {
        guard try !connection.columnNames(ofTable: "photos").contains("user_id") else { return }
        try connection.execute("""
            ALTER TABLE photos ADD COLUMN user_id TEXT;
            ALTER TABLE photos ADD COLUMN device_id TEXT
                CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL));

            -- 1. The photographs of a visit follow the visit.
            UPDATE photos
               SET user_id = (SELECT v.user_id FROM visits v WHERE v.id = photos.visit_id)
             WHERE visit_id IS NOT NULL;
            UPDATE photos
               SET device_id = (SELECT v.device_id FROM visits v WHERE v.id = photos.visit_id)
             WHERE visit_id IS NOT NULL AND user_id IS NULL;

            -- 2. The visitless ones — every one of them written by this installation — take this
            --    installation's identity, account first.
            UPDATE photos
               SET user_id = (SELECT value FROM app_state WHERE key = 'current_user_id')
             WHERE visit_id IS NULL;
            UPDATE photos
               SET device_id = (SELECT value FROM app_state WHERE key = 'device_uuid')
             WHERE visit_id IS NULL AND user_id IS NULL;
            """)
    }

    // MARK: - v13

    /// The tombstone that makes the leaving door's promise permanent (ERRATA — see
    /// E157).
    ///
    /// **The hole.** `leaveRecords` nulls `user_id` on the four contribution tables and leaves
    /// `device_id`, which is correct — `device_id` is `NOT NULL` there and always was — but it
    /// leaves the row in exactly the state D9 defines as *this device's unclaimed work*.
    /// `claimDevice` then adopts it onto the **next** account signed in on the phone, and the same
    /// shape appears in every device-scoped read: the journal, the grove, and the count screen 15
    /// states. A person deliberately unlinked their records from themselves and the phone relinked
    /// them to whoever came next. On a shared or handed-down device that is a re-identification, and
    /// nothing on screen said it could happen.
    ///
    /// The project owner ruled for a tombstone (RULINGS, "the owner's own decisions", 2026-07-26):
    /// rows anonymized by a deletion are marked and are skipped for ever.
    ///
    /// **Why not clear `device_id` instead.** It is one `UPDATE` and it is wrong. `device_id IS NULL
    /// AND user_id IS NULL` is not a state those tables can hold (`device_id` is `NOT NULL`), and
    /// even if it were, it destroys the distinction the whole fix rests on: *anonymized by a
    /// deletion* and *never had an account* look identical afterwards, so the legitimate D9 case —
    /// an unsigned-in contributor keeping their own work on their own phone — becomes
    /// indistinguishable from a stranger's withdrawn records. The tombstone is the only thing that
    /// tells those two apart.
    ///
    /// **Why a side table keyed on `client_uuid`, rather than a column on each table.** A column
    /// would have been the house's usual move (`deleted_at` is exactly that), and it closes the
    /// four tables. It does not close the outbox, and the outbox is where a partial tombstone would
    /// have shipped looking finished. A contribution lives in the queue between being written and
    /// being applied: `OutboxStore.forgetAccount` strips `$.userID` from the queued payload, and the
    /// row is *inserted* — for the first time — after the deletion has already run. A column-based
    /// tombstone has nothing to write on, because the row does not exist yet; it would be born
    /// unmarked and adopted by the next account, which is the original defect with one extra step in
    /// front of it.
    ///
    /// `client_uuid` is the key both halves already share. It is the idempotency key (BUILD-PLAN §4,
    /// DECISIONS §3.8), it is `NOT NULL UNIQUE` on all four tables, and it is a top-level key on all
    /// four payloads — so a deletion can tombstone a record that has not been stored yet, and the
    /// mark is waiting when the queue drains. That is the property a column cannot have.
    ///
    /// **Nothing is ever removed from here.** "Permanently" is the ruling, so this table only grows,
    /// and it grows by the number of contributions one deleted account made — tens of rows on a real
    /// install. It holds no `user_id`, no `device_id` and no tree: a `client_uuid` and a timestamp,
    /// which says *this record is nobody's* and nothing else. Storing the account it came from would
    /// re-create the joining key `AccountDeletionChoice` refuses a sentinel id for.
    ///
    /// **`PRIMARY KEY` and `INSERT OR IGNORE`.** A deletion that runs twice, or a queued row whose
    /// stored twin was already tombstoned, must be a no-op rather than a constraint failure inside a
    /// deletion transaction.
    ///
    /// **Idempotent** in v1's shape — `CREATE TABLE IF NOT EXISTS` — so a run interrupted between
    /// the DDL and the version bump replays cleanly.
    private static let v13 = """
    -- The records an account deletion unlinked from their author, named by the one key that
    -- identifies a contribution before and after it is stored.
    --
    -- Read by `ContributionStore.claimDevice` and by every device-scoped read beside it; written by
    -- `AccountDeletion.anonymizeContributions` and `OutboxStore.forgetAccount`. A row here means the
    -- contribution belongs to nobody — not to the account that is going, and not to the phone it
    -- was made on.
    --
    -- `COLLATE NOCASE` on the key rather than on every reader: a UUID reaches this table by two
    -- routes — `SQLiteValue`'s uppercase `uuidString` from a stored row, and `JSONEncoder`'s from a
    -- queued payload — and the whole guarantee would turn on those two agreeing about case for ever.
    -- Declared on the column, the index itself is case-insensitive, so `INSERT OR IGNORE` deduplicates
    -- and every lookup matches without a reader having to remember.
    CREATE TABLE IF NOT EXISTS anonymized_contributions (
        client_uuid   TEXT PRIMARY KEY COLLATE NOCASE,
        anonymized_at TEXT NOT NULL
    );
    """

    // MARK: - v14

    /// `main` gains the species assertion chain, so a species claim can be **corrected** instead of
    /// only made — tickets #86 and #124, and the table `SpeciesClaim`'s header was waiting for.
    ///
    /// **The hole.** `species_assertions` exists only in the read-only bundled seed, holding the
    /// city's `city_import` row per tree. `main` had no copy, so the only writable species anywhere
    /// in the app was the bare `community_trees.species_current` column, and the only edit to it
    /// that needs no history is the one where there is nothing to supersede. Hence the two refusals
    /// `LocalAPI.claimSpecies` enforces today — community rows only, first claim wins — and hence a
    /// contributor who names a species wrongly is stuck with it for ever, with no route back and
    /// nothing on screen offering one. `Tree.speciesCurrentID` has described itself as "denormalized
    /// from the latest accepted assertion … a read cache" since it was written, and there has been
    /// no chain for it to be a cache *of*.
    ///
    /// **The shape follows the seed's, in `main`'s vocabulary.** Same four `source` values, same
    /// nullable `confidence`, same forward-pointing `superseded_by`, same append-only rule. Two
    /// differences, both forced:
    ///
    /// 1. **UUID keys, not the seed's INTEGER ones.** `main` has no foreign key onto the inventory
    ///    at all — SQLite cannot declare `REFERENCES` across an attached database — so contributions
    ///    carry `tree_uuid TEXT` against `seed.trees.uuid`, exactly as every other table here does.
    ///    The self-reference `superseded_by` *is* a real foreign key, because both ends are in
    ///    `main`.
    /// 2. **Authorship is `user_id`/`device_id`, not the seed's single `asserted_by`.** BUILD-PLAN
    ///    §4 writes `asserted_by fk users`, which is right for a server where every claim arrives
    ///    with a session and wrong on a phone whose first saves are anonymous under a device id
    ///    (D9). The pair is `photos`' (v12), with `photos`' CHECK, so *nobody* is a reachable owner
    ///    and means what it means everywhere else.
    ///
    /// **The partial unique index is the invariant, not decoration.**
    ///
    /// ```sql
    /// CREATE UNIQUE INDEX … ON species_assertions(tree_uuid) WHERE superseded_by IS NULL
    /// ```
    ///
    /// A tree has exactly one *current* claim, and it is the one nothing supersedes — the same
    /// instrument, for the same reason, as `idx_tree_names_one_active` (D15's "one active name per
    /// tree"). Without it, an append that forgot to stamp the old head leaves two heads and every
    /// reader picks one by accident; with it, the engine refuses. It is what lets
    /// `community_trees.species_current` be an honest read cache rather than a second opinion.
    ///
    /// **The backfill records that the author is unknown, and declines to guess one.** Every row in
    /// `community_trees` with a `species_current` gets an assertion, because a species with no
    /// assertion behind it is a head-less chain that no correction can append to — the invariant
    /// above would be false for exactly the rows the feature is about. What it cannot supply is who
    /// made the claim: `community_trees` has never had an author column, `claimSpecies` recorded
    /// none, and neither did the add screen. So the row is written `.nobody` — both owner columns
    /// null — and that is a statement rather than a shrug.
    ///
    /// v12's backfill reasoned in the other direction, and the difference is the point. There, "this
    /// installation wrote every photograph" was checkable from the writers, and the harm of being
    /// wrong was over-attribution of a JPEG nobody else could see. Here the fact being written is
    /// *who may overwrite somebody's statement without asking*, and an assertion attributed to this
    /// device by assumption hands that authority to whoever holds the phone. The honest value is the
    /// one the database can support. Its consequence is stated rather than hidden: a species claimed
    /// before v14 is nobody's, so nobody may correct it silently, and it is corrected through the
    /// review route like a stranger's — see `RULINGS R45`.
    ///
    /// `updated_at` is the assertion's `created_at`, and it is chosen as the tightest *true* bound
    /// rather than the likeliest guess: the claim was written at or before the row's last write, and
    /// `created_at` would assert the tree was named when it was added, which is false for every row
    /// named afterwards through `claimSpecies`.
    ///
    /// **`review_flags` is rebuilt to widen one CHECK, for #125.** "This tree does not exist at all"
    /// is a *record defect*, not a lifecycle event, and it must not be reported as `appears_removed`:
    /// confirming that writes `TreeStatus.removed`, which this product has settled as a memorial —
    /// gray pin spoken as "Removed tree, memorial", screen 19, `acceptsNewContributions == false`
    /// (E170, R19). A record that never had a tree would get a memorial for a tree that never lived,
    /// which is the map asserting something untrue: R7's argument for the vacant-site pin, verbatim.
    /// The two also mean different things to the merged national inventory the product is being
    /// built toward (D16) — a lifecycle event with a date, against a row that should not be there —
    /// and a consumer that cannot tell them apart mis-states a city's history.
    ///
    /// **Only the CHECK value, deliberately.** `ReviewFlag.Kind` gains no case here: #125 owns what
    /// the kind means, what surface raises it and what confirming it writes, and that lands in a
    /// later round. Until it does, nothing can write `never_existed` — the store binds
    /// `Kind.rawValue` and there is no case to bind — so the widened CHECK is a reservation, not a
    /// reachable state. What it buys is the rebuild: SQLite cannot widen a CHECK in place, so the
    /// alternative was a whole migration of its own for one string.
    ///
    /// **Idempotent by guard, per half**, in v9's shape — read the stored `CREATE TABLE` text, which
    /// is the only place a CHECK is visible from SQL. A run interrupted between either half and the
    /// version bump replays cleanly, and the two halves are independent.
    private static func applyV14(_ connection: SQLiteConnection) throws {
        if try tableDefinition(named: "species_assertions", connection: connection).isEmpty {
            try connection.execute(v14Assertions)
            try backfillSpeciesAssertions(connection)
        }
        if try !tableDefinition(named: "review_flags", connection: connection).contains("never_existed") {
            try connection.execute(v14ReviewFlags)
        }
    }

    private static let v14Assertions = """
    -- --------------------------------------------------- species_assertions --
    -- The device's half of BUILD-PLAN §4 `species_assertions`. The seed holds the
    -- city's `city_import` rows in its own copy of this table, keyed by INTEGER;
    -- this one is keyed by UUID and references the inventory by `tree_uuid`, like
    -- every other contribution table here.
    --
    -- Append-only. A correction inserts a row and stamps the row it replaces with
    -- `superseded_by`; nothing is ever updated in place and nothing is deleted.
    -- There is no `deleted_at` for that reason: the history is the point.
    CREATE TABLE IF NOT EXISTS species_assertions (
        id            TEXT PRIMARY KEY,
        tree_uuid     TEXT NOT NULL,
        -- Nullable: a genus-only or explicitly unknown claim (PRODUCT §3).
        species_uuid  TEXT,
        source        TEXT NOT NULL CHECK (source IN
                          ('city_import','community','org','ai_suggestion')),
        confidence    REAL CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 1)),
        user_id       TEXT,
        device_id     TEXT,
        -- DEFERRED, and it has to be. A correction stamps the head and inserts its
        -- successor in one transaction, and the two orders are both refused if the
        -- constraint is immediate: insert-first breaks the one-head index below,
        -- stamp-first points at a row that does not exist yet. Deferring to COMMIT
        -- is the shape the invariant actually has — mid-transaction the chain is
        -- allowed to be inconsistent, at the end of it never.
        superseded_by TEXT REFERENCES species_assertions(id) DEFERRABLE INITIALLY DEFERRED,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        -- At most one owner, and nobody is reachable: `photos`' rule (v12), for
        -- `photos`' reason. An assertion whose author is unknown belongs to no
        -- one, which is a fact this table must be able to hold.
        CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL))
    );
    CREATE INDEX IF NOT EXISTS idx_species_assertions_tree
        ON species_assertions(tree_uuid, created_at DESC);
    -- One current claim per tree: the head of the chain. D15's instrument for
    -- `tree_names`, applied to the same kind of invariant.
    CREATE UNIQUE INDEX IF NOT EXISTS idx_species_assertions_head
        ON species_assertions(tree_uuid) WHERE superseded_by IS NULL;
    """

    /// Every already-claimed species gets the chain head it never had, owned by nobody.
    ///
    /// Swift rather than one `INSERT … SELECT` because each row needs its own UUID and SQLite has no
    /// generator for one; `lower(hex(randomblob(16)))` produces a string `UUID(uuidString:)` accepts
    /// but that is not a UUID, and this file does not write values it would not write from Swift.
    private static func backfillSpeciesAssertions(_ connection: SQLiteConnection) throws {
        let read = try connection.prepare("""
            SELECT id, species_current, updated_at FROM community_trees
             WHERE species_current IS NOT NULL AND deleted_at IS NULL
            """)
        defer { read.finalize() }
        let claimed = try read.fetchAll { row in
            (tree: try row.string("id"), species: try row.string("species_current"), moment: try row.string("updated_at"))
        }
        guard !claimed.isEmpty else { return }

        let write = try connection.prepare("""
            INSERT INTO species_assertions
                (id, tree_uuid, species_uuid, source, user_id, device_id, created_at, updated_at)
            VALUES (:id, :tree, :species, 'community', NULL, NULL, :moment, :moment)
            """)
        defer { write.finalize() }
        for claim in claimed {
            _ = try write.bind([
                ":id": UUID().uuidString,
                ":tree": claim.tree,
                ":species": claim.species,
                ":moment": claim.moment
            ])
            try write.run()
            _ = try write.reset()
        }
    }

    private static let v14ReviewFlags = """
    CREATE TABLE review_flags_widened (
        id         TEXT PRIMARY KEY,
        tree_uuid  TEXT NOT NULL,
        -- `never_existed` is reserved by #125 and unreachable until it lands:
        -- `ReviewFlag.Kind` has no case for it, and the store binds that enum.
        -- It is here because SQLite cannot widen a CHECK in place, and this
        -- rebuild was already being written.
        kind       TEXT NOT NULL CHECK (kind IN (
                       'appears_dead','appears_removed','duplicate_suspected',
                       'wrong_species','removed_but_active','never_existed')),
        raised_by  TEXT,
        status     TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','confirmed','dismissed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
    );

    INSERT INTO review_flags_widened
        (id, tree_uuid, kind, raised_by, status, created_at, updated_at, deleted_at)
    SELECT id, tree_uuid, kind, raised_by, status, created_at, updated_at, deleted_at
      FROM review_flags;

    DROP TABLE review_flags;
    ALTER TABLE review_flags_widened RENAME TO review_flags;

    CREATE INDEX IF NOT EXISTS idx_review_flags_tree ON review_flags(tree_uuid, status);
    """

    // MARK: - v15

    /// The outbox learns that *applying* a mutation and *sending* it are two different facts.
    ///
    /// **What was wrong, and it was never a bug in the shipping build.** `DataLayer` wires the
    /// queue's only transport to `LocalAPI`, so the drain *is* the local commit: a visit reaches its
    /// tree because a drain called `LocalAPI.sync` → `apply(_:)` → `contributions.insert`, and there
    /// is no other path (ERRATA E261 §2). The table recorded that with one flag, `json_synced`,
    /// whose name says "sent" and whose meaning is "committed here". Repointing the transport at a
    /// server would therefore not add a network to an existing local write — it would *remove* the
    /// local write, with no layer reporting an error, because every layer would behave as written.
    ///
    /// **The shape.** `json_synced` becomes `local_applied`, which is what it has always held, and
    /// `remote_sent` appears beside it. RULINGS R72 §1 orders the two: local apply is first and
    /// unconditional — a contribution is on its tree the moment the drain runs, offline or not —
    /// and the remote send is the retryable half, which is what `OutboxRetryPolicy` was written for
    /// and has never had a real reason to run. That ordering is a table-level CHECK rather than a
    /// convention:
    ///
    /// ```sql
    /// CHECK (remote_sent = 0 OR local_applied = 1)
    /// ```
    ///
    /// **`done` deliberately does not require `remote_sent`, and that is not an oversight.** Every
    /// row already on a phone is locally applied and has never been sent anywhere — there is nowhere
    /// to send it — so a `done` predicate naming `remote_sent` would make this migration reject the
    /// very rows it is migrating, and would strand every queued contribution on every installed
    /// build until a server exists. Whether a send is owed is a property of the *composition root*,
    /// not of the row: `OutboxQueue` passes `requiringRemoteSend:` to `markDoneIfComplete` and the
    /// answer is "is a send sink wired". With none wired the observable behavior is exactly what it
    /// was before this migration.
    ///
    /// SQLite cannot rename a column *and* rewrite a table-level CHECK in place, so this is the
    /// twelve-step rebuild v4 already performs on this table, for the reason v4 gives: the copy is
    /// column for column and carries `seq`, so FIFO order, retry counts, error text, the 48 h window
    /// and the photo lists all come across untouched. A contributor with a queued visit sees the
    /// same queue in the same order afterwards.
    ///
    /// **What copying `seq` does and does not buy.** It preserves the FIFO order of the rows that
    /// exist, and it carries `sqlite_sequence` forward *when there are rows*. On an outbox that is
    /// **empty** at upgrade time — the ordinary state of a phone that has drained everything and let
    /// `pruneCompleted` sweep the receipts — the `INSERT … SELECT` writes nothing, `DROP TABLE` takes
    /// the counter with it, and the new table starts from 1 again. Measured, not assumed
    /// (`OutboxApplySendSplitTests`). It is harmless: `seq` only orders rows that are live at the
    /// same time, and a row's identity is `id` and `client_uuid`, both uniquely indexed and both
    /// copied verbatim. The stronger claim — "so no id is ever reused" — is what v4's comment says
    /// at the same spot, and it is wrong there in the same way; that is shipped history and is not
    /// edited from this migration.
    ///
    /// Idempotent by guard, for the reason v3 gives.
    private static func applyV15(_ connection: SQLiteConnection) throws {
        let existing = try outboxDefinition(connection: connection)
        guard !existing.contains("remote_sent") else { return }
        try connection.execute("""
            CREATE TABLE outbox_two_sinks (
                seq               INTEGER PRIMARY KEY AUTOINCREMENT,
                id                TEXT NOT NULL UNIQUE,
                kind              TEXT NOT NULL CHECK (kind IN (
                                      'visit','observation','measurement','care_event',
                                      'favorite_toggle','private_reminder')),
                client_uuid       TEXT NOT NULL UNIQUE,
                payload           TEXT NOT NULL CHECK (json_valid(payload)),
                photo_paths       TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(photo_paths)),
                state             TEXT NOT NULL DEFAULT 'pending'
                                  CHECK (state IN ('pending','uploading','failed','done')),
                fail_count        INTEGER NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
                last_error        TEXT,
                last_error_code   TEXT,
                -- The mutation is committed to this device's own tables. This is what
                -- `json_synced` always meant; the name said the other thing.
                local_applied     INTEGER NOT NULL DEFAULT 0 CHECK (local_applied IN (0,1)),
                -- The mutation has been accepted by a server. Never 1 on any database this
                -- migration has ever met: every row it rewrites was written by a build with no
                -- send sink wired. #158's wiring round wires one, so rows written after it can
                -- carry a 1 — which is why the `done` CHECK below still does not name this column.
                -- See its comment.
                remote_sent       INTEGER NOT NULL DEFAULT 0 CHECK (remote_sent IN (0,1)),
                window_started_at TEXT NOT NULL,
                next_attempt_at   TEXT,
                created_at        TEXT NOT NULL,
                updated_at        TEXT NOT NULL,
                CHECK (state <> 'done' OR (local_applied = 1 AND json_array_length(photo_paths) = 0)),
                -- Apply is first and unconditional (RULINGS R72 §1). A row that claims to
                -- have been sent without having been applied is a lost contribution.
                CHECK (remote_sent = 0 OR local_applied = 1)
            );

            INSERT INTO outbox_two_sinks
                (seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                 last_error, last_error_code, local_applied, remote_sent, window_started_at,
                 next_attempt_at, created_at, updated_at)
            SELECT seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                   last_error, last_error_code, json_synced, 0, window_started_at,
                   next_attempt_at, created_at, updated_at
              FROM outbox;

            DROP TABLE outbox;
            ALTER TABLE outbox_two_sinks RENAME TO outbox;

            CREATE INDEX IF NOT EXISTS idx_outbox_drain ON outbox(state, next_attempt_at, seq);
            CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at);
            """)
    }

    // MARK: - v16

    /// `photos` learns **which installation took it**, which is not the same question as whose it is
    /// — the column the owner ruled for on 2026-08-15, against a report from their own phone that
    /// photographs taken before photo deletion existed could not be deleted.
    ///
    /// **The defect, in one sentence.** `PhotoOwner` has three arms and only one of them survives a
    /// change of account: `.device` is compared against `app_state.device_uuid`, which lives in the
    /// same file as the photographs and therefore cannot stop matching; `.nobody` is refused on
    /// purpose (R3, E157); and `.user` matches only while this installation is signed in as exactly
    /// that account. Two changes then composed. v12's backfill handed every visitless photograph to
    /// whatever account happened to be signed in during an app update — the one attribution in this
    /// app that corresponds to no act by the person. E270 removed the way back: the only sign-in
    /// that succeeds now is Apple's, the id is the service's, and `claimDevice` clears
    /// `signed_out_user_id` on its way past (E272). An account minted in the local-account era can
    /// never be signed into again, so the photographs it holds are on the screen, drawn, with no
    /// delete control and — unlike an anonymized row, which task #131 gave a sentence — nothing
    /// saying why.
    ///
    /// **Provenance, not a second owner.** `taken_on_device` is never consulted to answer *whose*
    /// a photograph is: no query reads it for attribution, `claimDevice` does not touch it, and v12's
    /// "at most one owner" CHECK is untouched, so nothing gains a precedence rule that a reader
    /// could get wrong. It answers one narrower question — did this installation write this row —
    /// and `PhotoOwner.permitsRemoval(by:takenOnDevice:)` is where that answer meets the other two.
    ///
    /// **The backfill is a weaker claim than v12's, deliberately.** Every row in `main.photos` was
    /// written by this installation: `beginPhotoUpload` and `addTree` are the only writers, both run
    /// in `LocalAPI`, and nothing syncs anybody else's photographs down — the same standing fact v12
    /// reasoned from and that `LocalAPI.treeProfile` restates where it fills `ownPhotoIDs`. v12 used
    /// it to name a *person*, which is what over-attributed. This uses it to name a *machine*, which
    /// is the thing it actually establishes.
    ///
    /// **Not the backfill the owner ruled against on 2026-08-15 (RULINGS R77)**, which is worth
    /// saying because the word is the same. That one is about *sync*: pre-sync-path rows
    /// and pre-existing photo binaries stay on the device permanently, nothing is re-enqueued, and
    /// no future send path sweeps them up. This writes one local column in the app's own database,
    /// enqueues nothing, uploads nothing, and leaves the outbox untouched.
    ///
    /// **An anonymized photograph is skipped, and that is the whole of R3 in this migration.** A row
    /// with neither owner is one whose contributor deleted their account through the door that
    /// leaves the work in place, and it is nobody's to take back — for ever, which is the ruling
    /// E157 records. Backfilling provenance onto those rows would hand them to whoever holds the
    /// phone and quietly repeal it. `AccountDeletion.anonymizeContributions` clears the column for
    /// the same reason on every future deletion.
    ///
    /// **`ALTER TABLE ADD COLUMN`, not a rebuild**, on v10's, v11's and v12's argument. The
    /// column-absence guard covers **the `ALTER` only**, and the reason is narrower than the one
    /// v10, v11 and v12 inherited from each other: `ADD COLUMN` has no `IF NOT EXISTS` and throws
    /// "duplicate column name" on a table that already has it, so a replay needs the DDL skipped.
    /// It is not protection against a run interrupted between the DDL and the version bump —
    /// `SchemaMigrator.migrate` runs `migrate(connection)` and `setUserVersion` inside one
    /// transaction and SQLite's `ADD COLUMN` is transactional, so that half-state does not exist.
    ///
    /// **The backfill runs unconditionally, and is idempotent by construction**: an owned row is
    /// rewritten with the same `device_uuid`, an ownerless row is skipped by the `WHERE`, and a row
    /// anonymized after v16 stays skipped. Gating it on the column being absent would have been the
    /// dangerous half of one guard — any database in which the column exists and the backfill has
    /// not run (hand-repaired, a future partial fix, an abandoned experiment) would take v16 as a
    /// silent no-op and keep exactly the stranded rows this migration was written for.
    ///
    /// **When `app_state` has no `device_uuid` the backfill writes NULL**, because the subquery
    /// yields NULL rather than no row — the whole statement is then a no-op in the only situation
    /// that produces it, a fresh install, where migrations run before `DataLayer.boot` mints the key
    /// and there are no photographs yet to attribute.
    ///
    /// **No index.** `photos` holds tens of rows per install and the column is read by the deletion
    /// gate — once per profile read, on a statement already narrowed by `tree_uuid`, which
    /// `idx_photos_tree` serves.
    private static func applyV16(_ connection: SQLiteConnection) throws {
        if try !connection.columnNames(ofTable: "photos").contains("taken_on_device") {
            try connection.execute("ALTER TABLE photos ADD COLUMN taken_on_device TEXT")
        }
        try connection.execute("""
            -- Every row this installation still holds an owner for, it also wrote. A row with
            -- neither owner is an anonymized one and is skipped: see the header.
            UPDATE photos
               SET taken_on_device = (SELECT value FROM app_state WHERE key = 'device_uuid')
             WHERE NOT (user_id IS NULL AND device_id IS NULL);
            """)
    }

    // MARK: - v17

    /// `outbox.kind` learns spec §3.4's nine mutations, so they can stop being written to this phone
    /// and nowhere else.
    ///
    /// **What was wrong, and it is a live loss rather than a latent one.** `RoutedAPI` routes
    /// `addTree`, `claimSpecies`, `correctSpecies`, `flagWrongSpecies`, `flagNeverExisted`,
    /// `setPhotoVote`, `deletePhoto`, `logHazardRedirect` and the two review dismissals to `local`,
    /// and its own comment says why: "they have no queue behind them at all". That was a scope
    /// statement while nothing had a server to reach. Since #158's wiring round wired a send sink it
    /// is a signed-in contributor's work reaching their phone and no account, with every layer
    /// reporting success — which is the shape of failure this project keeps paying for.
    ///
    /// A row cannot be queued for a kind the `CHECK` refuses, and SQLite cannot widen a `CHECK` in
    /// place, so this is the twelve-step rebuild v4 and v15 already perform on this table. The copy
    /// is column for column and carries `seq`, so FIFO order, retry counts, error text, the 48 h
    /// window and the photo lists all come across untouched — v15's paragraph on what copying `seq`
    /// does and does not buy applies verbatim and is not repeated.
    ///
    /// ── **Nothing is enqueued by this migration, and that is the ruling, not a scope note** ────
    ///
    /// The widened vocabulary is a permission to write *future* rows. Every mutation of these nine
    /// that this device has already performed stays exactly where it is: applied locally, in the
    /// tables, unqueued, for ever. There is no sweep, no backfill, no `INSERT … SELECT` from
    /// `community_trees` or `review_flags` or `photo_votes` into this table, and there must never be
    /// one — the owner ruled it, and the reason is that a phone carrying local test data would
    /// silently publish all of it the first time a build with a send sink drained. The
    /// `INSERT … SELECT` below reads `outbox` and only `outbox`.
    ///
    /// **Idempotent by guard, for the reason v3 gives.** The guard reads the stored `CREATE TABLE`
    /// text rather than a column list, because what changed here is a `CHECK` and
    /// `pragma_table_info` cannot see one (`outboxDefinition`).
    private static func applyV17(_ connection: SQLiteConnection) throws {
        let existing = try outboxDefinition(connection: connection)
        guard !existing.contains("'add_tree'") else { return }
        try connection.execute("""
            CREATE TABLE outbox_community_kinds (
                seq               INTEGER PRIMARY KEY AUTOINCREMENT,
                id                TEXT NOT NULL UNIQUE,
                kind              TEXT NOT NULL CHECK (kind IN (
                                      'visit','observation','measurement','care_event',
                                      'favorite_toggle','private_reminder',
                                      -- Spec §3.4's nine, in ten values: the review-dismissal pair
                                      -- is one mutation in that list and two seams here
                                      -- (`ReviewFlag.Kind.Resolution`, ERRATA E170).
                                      'add_tree','species_claim','species_correction',
                                      'wrong_species_report','never_existed_report',
                                      'species_review_dismissal','record_review_dismissal',
                                      'photo_vote','photo_withdrawal','hazard_redirect')),
                client_uuid       TEXT NOT NULL UNIQUE,
                payload           TEXT NOT NULL CHECK (json_valid(payload)),
                photo_paths       TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(photo_paths)),
                state             TEXT NOT NULL DEFAULT 'pending'
                                  CHECK (state IN ('pending','uploading','failed','done')),
                fail_count        INTEGER NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
                last_error        TEXT,
                last_error_code   TEXT,
                -- v15's two sinks, unchanged. The ten new kinds are born with `local_applied = 1`
                -- because `LocalAPI` writes the row inside the transaction that performs the
                -- mutation, so a drain owes them the send and nothing else. See
                -- `OutboxPayload.isAppliedBeforeItIsQueued`.
                local_applied     INTEGER NOT NULL DEFAULT 0 CHECK (local_applied IN (0,1)),
                remote_sent       INTEGER NOT NULL DEFAULT 0 CHECK (remote_sent IN (0,1)),
                window_started_at TEXT NOT NULL,
                next_attempt_at   TEXT,
                created_at        TEXT NOT NULL,
                updated_at        TEXT NOT NULL,
                CHECK (state <> 'done' OR (local_applied = 1 AND json_array_length(photo_paths) = 0)),
                -- Apply is first and unconditional (RULINGS R72 §1). A row that claims to
                -- have been sent without having been applied is a lost contribution.
                CHECK (remote_sent = 0 OR local_applied = 1)
            );

            INSERT INTO outbox_community_kinds
                (seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                 last_error, last_error_code, local_applied, remote_sent, window_started_at,
                 next_attempt_at, created_at, updated_at)
            SELECT seq, id, kind, client_uuid, payload, photo_paths, state, fail_count,
                   last_error, last_error_code, local_applied, remote_sent, window_started_at,
                   next_attempt_at, created_at, updated_at
              FROM outbox;

            DROP TABLE outbox;
            ALTER TABLE outbox_community_kinds RENAME TO outbox;

            CREATE INDEX IF NOT EXISTS idx_outbox_drain ON outbox(state, next_attempt_at, seq);
            CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at);
            """)
    }

    // MARK: - v18

    /// A staged binary stops being an element of a JSON array and becomes a row, because applying it
    /// and sending it are two facts and an array element can only hold one (ERRATA **E264**).
    ///
    /// ── What was wrong with the column ─────────────────────────────────────────────────────────
    ///
    /// `outbox.photo_paths` held the binaries a row still owed, and the drain's only verb was
    /// *remove*: `apply.uploadPhoto` ingested the file into the app container and the path came out
    /// of the array. That is a complete description of a world with one sink. With two it loses the
    /// photograph — by the time a send could run there is nothing at the path, because the apply
    /// consumed it, and re-running the apply to get it back writes the `photos` row a second time.
    /// E264 names the three things a send needs that the array cannot carry: a source the remote can
    /// still read after ingest, per-photo completion rather than the row-wide flag pair v15 added,
    /// and somewhere to say whether a failed send holds the row out of `done`.
    ///
    /// A row per binary carries all three. `photo_id` is the local `photos.id` the apply minted,
    /// which is how the send finds bytes that are no longer at `path`; `state` is that photograph's
    /// own progress and not its item's; and the item's `done` still cannot be reached while any of
    /// its binaries is outstanding, because `photos_outstanding` says so in a CHECK.
    ///
    /// ── Why a counter column and two triggers rather than a subquery ───────────────────────────
    ///
    /// `CHECK (state <> 'done' OR (local_applied = 1 AND json_array_length(photo_paths) = 0))` is
    /// v1's, and its comment is "zero loss is a schema invariant, not a convention". SQLite CHECK
    /// constraints cannot contain a subquery, so the same sentence about a *table* has to be written
    /// against a column: `photos_outstanding` is that column, and the two triggers are what make it
    /// true rather than merely maintained. Moving the invariant into `markDoneIfComplete`'s `WHERE`
    /// instead would have demoted it to exactly the convention that comment refuses.
    ///
    /// ── `sendable = 0` on every row this migration writes, which is RULINGS R77 ────────────────
    ///
    /// The binaries already in the queue when this runs were staged by a build with no send path.
    /// R77 is explicit that pre-existing photo binaries stay on device — "no retroactive photo
    /// upload, not now and not as a later phase of the photo send-path work" — and a migration that
    /// carried them over as sendable would be exactly the backfill it forbids, performed silently,
    /// on rows the contributor cannot see. They are migrated (dropping them would lose a
    /// contribution) and they are migrated **local-only**: still applied, never sent, and deleted on
    /// apply like they are today. Only binaries staged after this migration carry `sendable = 1`.
    private static func applyV18(_ connection: SQLiteConnection) throws {
        guard try tableDefinition(named: "outbox_photos", connection: connection).isEmpty else { return }

        // ── Refuse before moving anything, rather than dropping what will not parse ────────────
        //
        // The first version of this migration filtered unrecoverable elements out with a
        // `WHERE … IS NOT NULL`, and computed `photos_outstanding` from the survivors — so an item
        // carrying one good binary and one malformed one migrated to a single row, settled `done`,
        // and satisfied "zero loss is a schema invariant" by forgetting the loss. #116's review
        // measured five shapes that vanished: an object with no `path`, `path: null`, a JSON null,
        // a number, and the mixed row that is the frightening one because it looks fine afterwards.
        //
        // Not reachable through the app today — `OutboxPhoto.path` is non-optional — and that is
        // deliberately not the defense. A migration runs once, unattended, on somebody's own phone;
        // what it discards is gone with nothing left to notice it by. Refusing turns a silent
        // contribution loss into a crash that names the row, and the data is still on the device
        // for the build that fixes it.
        let malformed = try connection.prepare("""
            SELECT COUNT(*) AS n,
                   COALESCE(group_concat(DISTINCT outbox_id), '') AS items
              FROM (
                    SELECT outbox.id AS outbox_id
                      FROM outbox, json_each(outbox.photo_paths)
                     WHERE COALESCE(json_extract(value, '$.path'),
                                    CASE WHEN json_type(value) = 'text' THEN value END) IS NULL
                   )
            """)
        defer { malformed.finalize() }
        if let found = try malformed.fetchOne({ row in
            (count: try row.int("n"), items: try row.string("items"))
        }), found.count > 0 {
            throw MigrationError.unmigratableData(
                migration: 18,
                detail: """
                    \(found.count) queued photo element(s) carry no recoverable path, on outbox \
                    row(s) \(found.items). Each is a contribution's photograph; dropping them \
                    would settle those items `done` with the binaries gone and nothing recording \
                    that they were lost. Repair the rows and re-run.
                    """
            )
        }

        try connection.execute("""
            -- ── Order matters here, and getting it wrong silently empties the queue ───────────
            --
            -- `outbox_photos.outbox_id` is `ON DELETE CASCADE` against `outbox`, and this migration
            -- **drops** `outbox` as part of rebuilding it. Under `PRAGMA foreign_keys = ON` that
            -- drop performs an implicit delete of every row first, so a child table populated
            -- before the drop has its rows cascaded away by it — the binaries are migrated
            -- perfectly and then deleted, and the only symptom is an empty `photos` list on every
            -- queued item. Measured, not theorised: it is exactly how this migration first failed.
            --
            -- So the binaries are parked in a table with no foreign key, the rebuild happens, and
            -- `outbox_photos` is created and filled afterwards — by which time its parent is the
            -- final `outbox` and the cascade has nothing to fire on.
            CREATE TABLE outbox_photos_staged (
                outbox_id  TEXT NOT NULL,
                path       TEXT,
                shot_type  TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE outbox_photos (
                -- Client-minted and stable for the life of the binary. It is also the idempotency
                -- key `POST /photos/begin` dedupes on, which is why it is minted here rather than
                -- server-side: a begin that is retried after a flap must land on the row it already
                -- created instead of a second one (E264).
                id              TEXT PRIMARY KEY,
                outbox_id       TEXT NOT NULL REFERENCES outbox(id) ON DELETE CASCADE,
                -- Where the binary is staged. NULL the moment the apply consumes the file, which is
                -- the fact that made a path-keyed array unable to describe a sent photograph.
                path            TEXT,
                shot_type       TEXT NOT NULL
                                CHECK (shot_type IN ('full_tree','trunk','leaf','other')),
                -- The local `photos.id` the apply minted. This is the source a send reads: the
                -- container copy outlives the staged file, and this column is what names it.
                --
                -- **Deliberately not a foreign key**, which is the opposite of what the rest of this
                -- schema does and needs its reason stated. `photos` is not this column's parent in
                -- the sense a FK means: a queued binary's whole purpose is to survive independently
                -- of the row it points at, and the two ways that row can go are both ordinary.
                -- `ContributionStore.deletePhoto` tombstones it, and `AccountDeletion`'s erasing
                -- door removes rows around it, and under `PRAGMA foreign_keys = ON` a RESTRICT
                -- reference would turn either of those into a failure whose cause is a *queue* row.
                -- A deletion refusing because something has not synced yet is precisely the coupling
                -- an outbox exists to avoid.
                --
                -- The reference is validated where it is used instead: `sendablePhotos` joins
                -- `photos` and requires `deleted_at IS NULL AND local_path IS NOT NULL`, so a binary
                -- whose photograph has gone is simply not sendable. That is a stronger gate than a
                -- FK — it also refuses a row that still exists but has been withdrawn, which a FK
                -- would happily keep.
                photo_id        TEXT,
                -- Where the apply put the binary inside the app container, which is the source a
                -- send reads. Recorded here rather than looked up through `photos.local_path`
                -- because the queue's own source should not depend on another table's shape — and
                -- because the apply sink already knows it: it is the destination its ticket named.
                container_path  TEXT,
                state           TEXT NOT NULL DEFAULT 'pending'
                                CHECK (state IN ('pending','applied')),
                -- R77. Set to 0 by this migration for everything already queued; 1 for everything
                -- staged after it. A local-only binary is deleted when it is applied.
                sendable        INTEGER NOT NULL DEFAULT 1 CHECK (sendable IN (0,1)),
                fail_count      INTEGER NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
                last_error      TEXT,
                last_error_code TEXT,
                created_at      TEXT NOT NULL,
                updated_at      TEXT NOT NULL,
                -- A binary nobody has applied yet must still be somewhere on disk.
                CHECK (state <> 'pending' OR path IS NOT NULL),
                -- An applied binary must name the row the apply wrote, or the send has no source.
                CHECK (state <> 'applied' OR (photo_id IS NOT NULL AND container_path IS NOT NULL))
            );
            CREATE INDEX IF NOT EXISTS idx_outbox_photos_item ON outbox_photos(outbox_id);
            CREATE INDEX IF NOT EXISTS idx_outbox_photos_state ON outbox_photos(state, sendable);

            CREATE TABLE outbox_per_photo (
                seq               INTEGER PRIMARY KEY AUTOINCREMENT,
                id                TEXT NOT NULL UNIQUE,
                kind              TEXT NOT NULL CHECK (kind IN (
                                      'visit','observation','measurement','care_event',
                                      'favorite_toggle','private_reminder',
                                      'add_tree','species_claim','species_correction',
                                      'wrong_species_report','never_existed_report',
                                      'species_review_dismissal','record_review_dismissal',
                                      'photo_vote','photo_withdrawal','hazard_redirect')),
                client_uuid       TEXT NOT NULL UNIQUE,
                payload           TEXT NOT NULL CHECK (json_valid(payload)),
                -- ── `photo_paths` is dead and cannot be dropped ────────────────────────────────
                --
                -- Nothing reads or writes it after this migration; the binaries live in
                -- `outbox_photos` now. It survives because **earlier migrations still name it**, and
                -- a migration is frozen once it has run anywhere. v2's body is
                -- `UPDATE outbox SET photo_paths = … WHERE EXISTS (… json_each(outbox.photo_paths) …)`,
                -- and SQLite resolves that column at prepare time, so against a table without it the
                -- statement fails outright — its `WHERE EXISTS` guard never gets the chance to
                -- decide there is nothing to do.
                --
                -- That is not hypothetical, and `DataGates` is what proves it: the migration gate
                -- sets `user_version = 0` on a fully migrated database and replays every step,
                -- because a run interrupted between a migration's DDL and its version bump has to
                -- replay cleanly. For this migration that interruption leaves v18's tables in place
                -- and the counter at 17, and the replay then runs v2 against them. Dropping the
                -- column turns that recovery into a database nobody can open.
                --
                -- v18 blanks it to `'[]'` rather than leaving stale JSON, so a replayed v2 finds no
                -- bare-string element and correctly does nothing.
                photo_paths       TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(photo_paths)),
                -- v1's `json_array_length(photo_paths)`, as a number a CHECK can read. Maintained by
                -- the two triggers below; never written by hand.
                photos_outstanding INTEGER NOT NULL DEFAULT 0 CHECK (photos_outstanding >= 0),
                state             TEXT NOT NULL DEFAULT 'pending'
                                  CHECK (state IN ('pending','uploading','failed','done')),
                fail_count        INTEGER NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
                last_error        TEXT,
                last_error_code   TEXT,
                local_applied     INTEGER NOT NULL DEFAULT 0 CHECK (local_applied IN (0,1)),
                remote_sent       INTEGER NOT NULL DEFAULT 0 CHECK (remote_sent IN (0,1)),
                window_started_at TEXT NOT NULL,
                next_attempt_at   TEXT,
                created_at        TEXT NOT NULL,
                updated_at        TEXT NOT NULL,
                -- v1's sentence, against the counter instead of the array. Zero loss is still a
                -- schema invariant.
                CHECK (state <> 'done' OR (local_applied = 1 AND photos_outstanding = 0)),
                CHECK (remote_sent = 0 OR local_applied = 1)
            );

            INSERT INTO outbox_per_photo
                (seq, id, kind, client_uuid, payload, photo_paths, photos_outstanding, state,
                 fail_count, last_error, last_error_code, local_applied, remote_sent,
                 window_started_at, next_attempt_at, created_at, updated_at)
            SELECT seq, id, kind, client_uuid, payload, '[]', 0, state,
                   fail_count, last_error, last_error_code, local_applied, remote_sent,
                   window_started_at, next_attempt_at, created_at, updated_at
              FROM outbox;

            -- Every staged binary in the queue becomes a row, local-only per R77.
            --
            -- **The id is punctuated into UUID form rather than left as bare hex** — the same trap
            -- `backfillSpeciesAssertions` above avoids by dropping into Swift. `hex(randomblob(16))`
            -- is 32 hex characters with no dashes, `UUID(uuidString:)` refuses that, and so
            -- `SQLiteRow.uuid("id")` throws on every row this migration writes: the queue stops
            -- being readable at all. Measured rather than reasoned about — it failed in exactly that
            -- way, "column 'id' held 'a787d66c…', which is not a UUID". The value only has to be
            -- unique, but it also has to be the shape every reader already expects.
            INSERT INTO outbox_photos_staged (outbox_id, path, shot_type, created_at, updated_at)
            SELECT outbox.id,
                   -- A bare-string element is a path; v2 rewrote those into objects, and this reads
                   -- both rather than trusting the rewrite reached every row.
                   COALESCE(json_extract(value, '$.path'),
                            CASE WHEN json_type(value) = 'text' THEN value END),
                   COALESCE(json_extract(value, '$.shotType'), 'other'),
                   outbox.created_at, outbox.updated_at
              FROM outbox, json_each(outbox.photo_paths);

            UPDATE outbox_per_photo
               SET photos_outstanding = (
                     SELECT COUNT(*) FROM outbox_photos_staged
                      WHERE outbox_photos_staged.outbox_id = outbox_per_photo.id
                   );

            DROP TABLE outbox;
            ALTER TABLE outbox_per_photo RENAME TO outbox;

            CREATE INDEX IF NOT EXISTS idx_outbox_drain ON outbox(state, next_attempt_at, seq);
            CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at);

            -- Now that `outbox` is the rebuilt table, the parked binaries can take their real rows:
            -- the cascade above has already happened and has nothing left to fire on.
            --
            -- **The id is punctuated into UUID form rather than left as bare hex** — the same trap
            -- `backfillSpeciesAssertions` avoids by dropping into Swift. `hex(randomblob(16))` is 32
            -- hex characters with no dashes, `UUID(uuidString:)` refuses that, and so
            -- `SQLiteRow.uuid("id")` throws on every row this migration writes: the queue stops
            -- being readable at all. Measured — it failed in exactly that way, "column 'id' held
            -- 'a787d66c…', which is not a UUID".
            INSERT INTO outbox_photos
                (id, outbox_id, path, shot_type, photo_id, container_path, state, sendable,
                 created_at, updated_at)
            SELECT substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-' || substr(h, 13, 4) || '-'
                       || substr(h, 17, 4) || '-' || substr(h, 21, 12),
                   outbox_id, path, shot_type, NULL, NULL, 'pending', 0, created_at, updated_at
              FROM (SELECT hex(randomblob(16)) AS h, * FROM outbox_photos_staged);

            DROP TABLE outbox_photos_staged;

            -- The counter's two halves. Written as triggers rather than kept in step by the store so
            -- that a future writer cannot add a third insertion site and forget one, which is the
            -- failure mode a denormalized count exists to have.
            CREATE TRIGGER outbox_photos_counted_in
            AFTER INSERT ON outbox_photos
            BEGIN
                UPDATE outbox SET photos_outstanding = photos_outstanding + 1
                 WHERE id = NEW.outbox_id;
            END;

            CREATE TRIGGER outbox_photos_counted_out
            AFTER DELETE ON outbox_photos
            BEGIN
                UPDATE outbox SET photos_outstanding = photos_outstanding - 1
                 WHERE id = OLD.outbox_id;
            END;

            -- The third case, which the first two do not cover and which #116's review measured:
            -- `UPDATE outbox_photos SET outbox_id = …` moved a row between items and left **both**
            -- counters wrong, silently. One item could then settle `done` with a binary
            -- outstanding, and the other could never settle at all.
            --
            -- **Forbidden rather than counted.** Maintaining the counter across a move would be
            -- three more lines and would make reassignment look supported; nothing in this codebase
            -- moves a binary between mutations, and there is no reading of the queue in which that
            -- is a sensible thing to do — a photograph belongs to the mutation it was taken for. A
            -- future author who needs it gets a loud, specific error rather than a drifting count,
            -- which is the failure mode a denormalized counter exists to prevent in the first
            -- place. The comment above says the triggers make the invariant true rather than merely
            -- maintained; this is the trigger that makes that claim honest.
            CREATE TRIGGER outbox_photos_never_reassigned
            BEFORE UPDATE OF outbox_id ON outbox_photos
            WHEN NEW.outbox_id <> OLD.outbox_id
            BEGIN
                SELECT RAISE(ABORT, 'outbox_photos.outbox_id is immutable: moving a binary would drift outbox.photos_outstanding on both sides');
            END;
            """)
    }

    /// The `CREATE TABLE` text SQLite holds for `outbox`, which is where the `kind` vocabulary
    /// actually lives — `pragma_table_info` reports columns, not their CHECKs.
    private static func outboxDefinition(connection: SQLiteConnection) throws -> String {
        try tableDefinition(named: "outbox", connection: connection)
    }

    /// The stored `CREATE TABLE` text for any table, empty when there is no such table.
    ///
    /// The only place a CHECK constraint is visible from SQL, which is why v9's idempotence guard
    /// reads this rather than the column list a `pragma_table_info` guard would give it.
    private static func tableDefinition(named table: String, connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = :name"
        )
        defer { statement.finalize() }
        _ = try statement.bind([":name": table])
        return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
    }
}
