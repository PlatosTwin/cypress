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
/// - an outbox row can only be `done` once its JSON *and* its photos have gone.
public enum AppSchema {
    /// Every migration, in order. Checked in, never edited after shipping — a new step gets a new
    /// version number.
    public static let migrations: [Migration] = [
        Migration(version: 1, name: "contributions and outbox", sql: v1),
        Migration(version: 2, name: "outbox photos carry their shot type", sql: v2),
        Migration(version: 3, name: "a private reminder can be owned by a device", migrate: applyV3),
        Migration(version: 4, name: "the outbox carries private reminders", migrate: applyV4),
        Migration(version: 5, name: "a favourite can be owned by a device", migrate: applyV5),
        Migration(version: 6, name: "an account's own rows go with the account", migrate: applyV6)
    ]

    /// The version a freshly migrated database reports.
    public static var currentVersion: Int32 { migrations.map(\.version).max() ?? 0 }

    // MARK: - v1

    // Historical, and not edited: this is the schema as it shipped, comments included. Where a later
    // step changed it, that step says so — `private_reminders`' owner rule below, the `outbox`
    // `kind` vocabulary, and `favorites`' owner and uniqueness rules were all superseded (v3, v4
    // and v5).
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

    // MARK: - v2

    /// `outbox.photo_paths` goes from a list of paths to a list of `{path, shotType}` objects.
    ///
    /// v1 stored the path alone, so the upload had nothing to send and labelled every binary
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
    /// One owner cannot favourite a tree twice; two different owners can each favourite it. A single
    /// `UNIQUE (user_id, device_id, tree_uuid)` would have enforced *nothing* for device rows: SQL
    /// treats NULLs as distinct inside a unique index, so `(NULL, this device, this tree)` would be
    /// storable any number of times. A single expression index over `COALESCE(user_id, device_id)`
    /// would work, but it puts two id spaces in one comparison and re-introduces the coalesced owner
    /// v3 refused; two indexes say the two sentences separately.
    ///
    /// **The trigger keeps its job and gains one exception.** Its reason is stated in v1: a stray
    /// `DELETE` loses the un-favourite *event*, so the row comes back on the next sync from another
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
                -- Exactly one owner, always. A favourite nobody owns is in nobody's grove, and one
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
    /// trigger would permit every hard delete of a user-owned favourite on a database where nobody
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

    /// The `CREATE TABLE` text SQLite holds for `outbox`, which is where the `kind` vocabulary
    /// actually lives — `pragma_table_info` reports columns, not their CHECKs.
    private static func outboxDefinition(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'outbox'"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
    }
}
