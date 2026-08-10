-- The sync service's Postgres schema.
--
-- ── Which version space this is, and which two it is not ──────────────────────────────────────
-- Neither. CLAUDE.md names two schema-version spaces — `AppSchema.currentVersion`, the writable
-- SQLite database's `PRAGMA user_version`, and `SeedDatabase.newestKnownSchemaVersion`, the
-- published city file's `s<n>`. This file is in neither. It is the server's own space, it advances
-- on its own, and nothing here is a migration in either app-side counter. #158 needs exactly one
-- app-side migration and this branch is not where it is authored (R72's closing note).
--
-- ── What this schema is a mirror of, and where it deliberately differs ─────────────────────────
-- The client's tables are the reference: same idempotency key, same ownership rule, same tombstone.
-- Three differences are forced by Postgres rather than chosen:
--
--   1. `client_uuid` is a real `uuid` column, not `TEXT COLLATE NOCASE`. `AppSchema` v13 declares
--      the collation because a UUID reaches SQLite by two routes — `SQLiteValue`'s uppercase
--      `uuidString` and `JSONEncoder`'s lowercase — and the guarantee would otherwise turn on those
--      agreeing about case for ever. Postgres parses both spellings to the same 16 bytes, so the
--      hazard the collation exists for cannot arise here.
--   2. Timestamps are `timestamptz`. The client writes fixed-width UTC ISO-8601 strings and relies
--      on lexicographic order being chronological; this side has a type that means it.
--   3. No PostGIS. R72 declines it: no server-side spatial query exists under R36's local read
--      path. The one distance question in the service — the 10 m proximity dedupe on `POST /trees`
--      — is a bounding-box prefilter over a btree index plus a haversine, which is what a query run
--      a few times a day is worth.

CREATE TABLE IF NOT EXISTS schema_meta (
    version     INTEGER NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Identity ───────────────────────────────────────────────────────────────────────────────────

-- The account. There is no `users` table on device (ERRATA E86) and #158 does not add one: this is
-- where that row belongs.
CREATE TABLE IF NOT EXISTS users (
    id                  UUID PRIMARY KEY,

    -- Apple's `sub`, stable per user per team. The account's identity here, rather than the email:
    -- an address can change and, under Hide My Email, was never the person's to begin with.
    apple_subject       TEXT NOT NULL UNIQUE,
    email               TEXT,
    provider            TEXT NOT NULL DEFAULT 'apple' CHECK (provider IN ('apple')),
    role                TEXT NOT NULL DEFAULT 'contributor'
                        CHECK (role IN ('contributor', 'lead', 'operator')),

    -- What this account agreed to, written from `POST /devices/claim`'s `license_version`
    -- (spec §5.6). NULL is a *declined* consent and is a real value, not a missing one — the client
    -- derives `acceptsLicense` from nil precisely so a Bool and a version string cannot disagree,
    -- and that property has to survive the wire. The CHECK keeps the pair from drifting apart.
    license_version     TEXT,
    license_accepted_at TIMESTAMPTZ,

    -- R72 ruling 2, and the only reason `POST /auth/oidc` exchanges the authorization code at all:
    -- Apple's revocation endpoint needs a token, and `DELETE /me` must call it. Cleared by the
    -- deletion that spends it.
    apple_refresh_token TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT users_license_pair CHECK ((license_version IS NULL) = (license_accepted_at IS NULL))
);

-- The installation. D9's anonymous handle: it identifies a phone, never a person.
CREATE TABLE IF NOT EXISTS devices (
    id          UUID PRIMARY KEY,
    device_uuid UUID NOT NULL UNIQUE,
    -- Set by `POST /devices/claim`, and it outlives a sign-out exactly as `device.user_id` does on
    -- the client. That is what makes the #174 guard necessary rather than decorative: this column
    -- alone is history, not authority.
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id);

-- A signed-in session. One row per refresh token, and rotation inserts rather than updates so the
-- chain is auditable and a replayed old token is a row that exists and is spent, not a row missing.
CREATE TABLE IF NOT EXISTS sessions (
    id                 UUID PRIMARY KEY,
    user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- SHA-256 of the presented secret. The secret itself is returned once and never stored, so a
    -- copy of this database is not a set of live sessions.
    refresh_token_hash BYTEA NOT NULL UNIQUE,
    issued_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ NOT NULL,
    -- Set when this token was exchanged for its successor. A second presentation of a rotated
    -- token is a replay.
    rotated_at         TIMESTAMPTZ,
    revoked_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);

-- The device credential of spec §5.8. It authorizes `POST /sync` for items carrying a deviceID and
-- no userID, and nothing else. It is not an attestation: a reinstall mints a new one and nothing
-- here pretends otherwise. The defense against a flood is the rate limiter.
CREATE TABLE IF NOT EXISTS device_tokens (
    id         UUID PRIMARY KEY,
    device_id  UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    token_hash BYTEA NOT NULL UNIQUE,
    issued_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_device ON device_tokens (device_id);

-- ── Contributions ──────────────────────────────────────────────────────────────────────────────

-- Everything that travels through the outbox, keyed on the idempotency key the client already
-- mints. `client_uuid` is the PRIMARY KEY rather than a unique index beside a surrogate id, because
-- dedupe is this table's whole job on the write path: `ON CONFLICT (client_uuid) DO NOTHING` is
-- what makes a replay a `duplicate` — a success that changes nothing.
CREATE TABLE IF NOT EXISTS contributions (
    client_uuid   UUID PRIMARY KEY,
    kind          TEXT NOT NULL CHECK (kind IN (
                      'visit', 'observation', 'measurement',
                      'care_event', 'favorite_toggle', 'private_reminder')),
    tree_uuid     UUID NOT NULL,

    user_id       UUID REFERENCES users(id) ON DELETE SET NULL,
    device_id     UUID REFERENCES devices(id) ON DELETE SET NULL,

    payload       JSONB NOT NULL,
    occurred_at   TIMESTAMPTZ NOT NULL,

    -- A row a deletion unlinked from its author, through `AccountDeletionChoice.leaveRecords`.
    anonymized_at TIMESTAMPTZ,
    deleted_at    TIMESTAMPTZ,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Exactly one owner, always — except after anonymization, when there is deliberately none.
    -- The client's tables state the first half as `CHECK ((user_id IS NULL) <> (device_id IS NULL))`
    -- and reach the ownerless state by tombstone rather than by a column, because on that side the
    -- row may not exist yet when the deletion runs. Here the row does exist, so the state is
    -- storable and the CHECK admits it under one condition: `anonymized_at` says why.
    CONSTRAINT contributions_owner CHECK (
        (anonymized_at IS NOT NULL AND user_id IS NULL AND device_id IS NULL)
        OR (anonymized_at IS NULL AND ((user_id IS NULL) <> (device_id IS NULL)))
    )
);

CREATE INDEX IF NOT EXISTS idx_contributions_user ON contributions (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_contributions_device ON contributions (device_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_contributions_tree ON contributions (tree_uuid, occurred_at DESC);

-- The tombstone, mirroring `AppSchema` v13 column for column.
--
-- A row here means the contribution belongs to nobody — not to the account that is going, and not
-- to the phone it was made on. It holds a `client_uuid` and a timestamp and nothing else: storing
-- the account it came from would re-create the joining key `AccountDeletionChoice` refuses a
-- sentinel id for.
--
-- **Its server-side job is the one the client's has**: an item accepted *after* the deletion must
-- not resurrect the account. The deletion writes tombstones for keys it has never seen as well as
-- for rows it is unlinking, so a queued item that drains on Thursday against a Wednesday deletion
-- hits a mark that was waiting for it and comes back `duplicate`.
--
-- Nothing is ever removed from here. "Permanently" is the ruling.
CREATE TABLE IF NOT EXISTS anonymized_contributions (
    client_uuid   UUID PRIMARY KEY,
    anonymized_at TIMESTAMPTZ NOT NULL
);

-- The heart on screen 03, and the one contribution that is not append-only: a toggle event with a
-- tombstone, resolved by time. Materialized rather than derived from `contributions`, because
-- `isFavorite` is a per-tree read (#167) that exists specifically to stop being a whole-list scan.
CREATE TABLE IF NOT EXISTS favorites (
    id          UUID PRIMARY KEY,
    tree_uuid   UUID NOT NULL,
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id   UUID REFERENCES devices(id) ON DELETE CASCADE,
    client_uuid UUID NOT NULL,
    is_favorite BOOLEAN NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- The client's constraint verbatim. An ownerless favorite is a row no query returns and no
    -- person can remove, which is the argument `AccountDeletionChoice` makes for deleting favorites
    -- unconditionally under both doors rather than offering to keep them.
    CONSTRAINT favorites_owner CHECK ((user_id IS NULL) <> (device_id IS NULL))
);

-- The collision ERRATA E89 records, made unstorable on this side too: one row per owner per tree.
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_user_tree
    ON favorites (user_id, tree_uuid) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_device_tree
    ON favorites (device_id, tree_uuid) WHERE device_id IS NOT NULL;

-- A tree somebody added. `POST /trees`' 10 m proximity dedupe reads this and the seed inventory;
-- only this half is writable.
CREATE TABLE IF NOT EXISTS community_trees (
    -- **The client's own tree UUID, and the idempotency key, and the id every other table means.**
    --
    -- There was briefly a server-minted `id` beside a `client_uuid`, and it gave a community tree
    -- two identities that the reads then disagreed about: `contributions.tree_uuid`,
    -- `photos.tree_uuid`, `GET /trees/{id}` and `IsFavorite` all key on the client's UUID, while
    -- `MapMembership` returned the server's — so a tree somebody added appeared on screen 01 under
    -- an id that named nothing in any other route. A tree must be addable offline and carry visits
    -- before it ever syncs, so the client necessarily knows the id first; there is no second
    -- identity for the server to contribute.
    id           UUID PRIMARY KEY,
    lat          DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon          DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
    display_name TEXT,
    species_id   UUID,
    placement    TEXT,
    user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
    device_id    UUID REFERENCES devices(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ
);

-- The prefilter's index. A btree on the pair is enough for a bounding box a few metres across; this
-- is the query PostGIS was declined for and it is one index and one haversine.
CREATE INDEX IF NOT EXISTS idx_community_trees_position ON community_trees (lat, lon);

-- ── Photographs ────────────────────────────────────────────────────────────────────────────────

-- The record. The bytes live in the Tigris bucket; `storage_key` is where.
CREATE TABLE IF NOT EXISTS photos (
    id                UUID PRIMARY KEY,
    tree_uuid         UUID NOT NULL,
    visit_client_uuid UUID,

    user_id           UUID REFERENCES users(id) ON DELETE SET NULL,
    device_id         UUID REFERENCES devices(id) ON DELETE SET NULL,

    shot_type         TEXT NOT NULL CHECK (shot_type IN ('full_tree', 'trunk', 'leaf', 'other')),

    moderation_state  TEXT NOT NULL DEFAULT 'pending'
                      CHECK (moderation_state IN ('pending', 'approved', 'rejected')),

    -- R72 ruling 5, and the obligation the ruling calls unrecoverable after the fact.
    --
    -- `.approved` alone cannot distinguish "screened and passed" from "auto-approved under the
    -- launch rule", and a state you cannot distinguish is a backlog you cannot re-run. The column
    -- ships *before* the pipeline for exactly that reason. The client never reads it;
    -- `isPubliclyVisible` is unchanged and there is no client migration in it.
    approval_reason   TEXT CHECK (approval_reason IS NULL OR approval_reason IN (
                          'auto_approved_launch', 'screened_and_passed')),

    -- Truthfully false on every row in existence, and therefore already the re-screen backlog
    -- cursor: the queue is "every photograph with blur_applied = false". Nothing in this service
    -- raises it; the pipeline DECISIONS §4 asks for is what will.
    blur_applied      BOOLEAN NOT NULL DEFAULT false,

    captured_at       TIMESTAMPTZ NOT NULL,
    width             INTEGER,
    height            INTEGER,
    -- Snapped to the 25 m public grid before it ever reaches here (A7, BUILD-PLAN §10).
    public_lat        DOUBLE PRECISION,
    public_lon        DOUBLE PRECISION,

    storage_key       TEXT NOT NULL UNIQUE,
    -- NULL until the binary lands. "A photo record with no arriving binary after 72 h is
    -- garbage-collected server-side" (BUILD-PLAN §6, `PhotoUploadTicket.binaryGracePeriod`), and
    -- this column plus `created_at` is that cursor.
    bytes_received_at TIMESTAMPTZ,

    deleted_at        TIMESTAMPTZ,
    anonymized_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT photos_public_position CHECK ((public_lat IS NULL) = (public_lon IS NULL)),

    -- The obligation made structural rather than remembered. A photograph cannot reach `.approved`
    -- without recording why it did, so the auto-approve backlog is identifiable by construction and
    -- an approval path added later cannot forget to say which rule approved it.
    CONSTRAINT photos_approval_reason CHECK (
        moderation_state <> 'approved' OR approval_reason IS NOT NULL),

    -- The client's own rule, in the client's own vocabulary: at most one owner, so a photograph
    -- never says both whose account it is and which phone took it (`AppSchema` v12, ERRATA E136).
    CONSTRAINT photos_owner CHECK (NOT (user_id IS NOT NULL AND device_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_photos_tree ON photos (tree_uuid, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_photos_user ON photos (user_id);
CREATE INDEX IF NOT EXISTS idx_photos_device ON photos (device_id);
-- The re-screen backlog, as a partial index so the cursor stays cheap once the pipeline is running
-- through it.
CREATE INDEX IF NOT EXISTS idx_photos_rescreen_backlog
    ON photos (created_at) WHERE blur_applied = false AND deleted_at IS NULL;

-- ── The revocation Apple would not take ────────────────────────────────────────────────────────

-- A refresh token whose revocation failed, kept so it can be retried.
--
-- R72 ruling 2 makes the revocation call a compliance obligation: Apple requires it at deletion,
-- and the authorization-code exchange exists for no other reason. `DELETE FROM users` therefore
-- cannot be the end of the story on the outage path — it would discard the only credential that
-- could ever satisfy the obligation, which is worse than the outage.
--
-- **It holds a token and nothing else.** No user id, no email, no device: a joining key here would
-- re-create exactly what `AccountDeletionChoice` refuses a sentinel id for, and would turn a
-- compliance queue into a record of who deleted their account. What a row says is "this credential
-- is owed a revocation", which is all a retry needs.
CREATE TABLE IF NOT EXISTS pending_apple_revocations (
    -- The hash, not the token, would be useless: revoking needs the token itself.
    refresh_token TEXT PRIMARY KEY,
    first_failed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts INTEGER NOT NULL DEFAULT 1
);
