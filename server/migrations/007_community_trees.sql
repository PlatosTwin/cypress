-- 007 — community trees become public: publication, the location chain, the audit log, the
-- erase door's tombstone, the session's device, and two new contribution kinds.
--
-- The design is the community-trees round's (2026-09-28), as amended by the owner's decisions of
-- the same day. The client half is `AppSchema` v23 (PR C1); the reads are PR S2, which adds no
-- migration and reads what this file creates.
--
-- ── Publication, and the invariant it keeps ────────────────────────────────────────────────────
--
-- A tree is served to people other than its adder only while `published_at` is set. Decision 7
-- (an account that declined the open license does not publish its trees) breaks the design's
-- one-line rule "live iff not device-owned": an account-owned tree can now be unpublished. What
-- holds instead, and who holds it:
--
--   1. `published_at IS NOT NULL` implies `device_id IS NULL` — a CHECK, below. A tree added signed
--      out stays on the adder's phone until sign-in (decision 1).
--   2. A tree is published only at a moment its owning account had accepted the license
--      (decisions 7 and 10). **The license is one-way** (decision 10): a later decline does not
--      unpublish anything, it only keeps trees added after it private — so this is a fact about the
--      moment of publication, not about the account's current answer, and `users` keeps only the
--      current answer. Every publication therefore writes a `published` event whose `after` carries
--      `license_version`, the version accepted at that moment, and `published_at` equals that
--      event's `occurred_at`. No CHECK can state it. After this file's own backfill it is kept by
--      the three writers of `published_at` in `internal/store/community_trees.go` —
--      `publicationStamp` (a signed-in insert), `claimCommunityTrees` (the claim) and
--      `publishAccountTrees` (`RecordLicenseConsent` accepting), each reading the answer under
--      `FOR SHARE` — and pinned by `TestEveryPublicationHappenedUnderAnAcceptedLicense`, which checks
--      the whole table after every path that can move either side.
--
-- ── What the public may know: history starts at going live (decision 13) ──────────────────────
--
-- A tree's life before publication is its adder's. Others see it as added where it stood when it
-- went public; positions it held and moves made while it was private are never served, and a
-- tile it left while private never reports it. Three columns carry this, each written once, when
-- the fact it records happens, and never rewritten from something the public saw back to something
-- it did not:
--
--   * `community_tree_locations.was_public` — this row was, at some moment, the tree's public
--     position: the head at the moment of publication, or a row that became the head while the tree
--     was published. A row superseded while private, and a late correction spliced in already
--     superseded, are not. The only UPDATE is the publication's, false to true on the head it
--     publishes, the same set-once shape as `superseded_by`; no position, time or actor is ever
--     rewritten, and nothing is deleted, so the chain stays the adder's complete record (DECISIONS
--     constraint 7: append-only). Collapsing the private chain at publication was the alternative,
--     and it would delete the adder's own acts.
--   * `community_tree_events.in_public_history` — this event is part of the public history. The
--     `published` event is, and it carries the position at publication; it is the public record's
--     "added". An `added` event never is. Every other event is when it was written while the tree
--     was published, except a `location_corrected` that did not move the public pin.
--   * `withdrawn_community_trees.was_public` — the erased tree had been published. A tree that
--     never was must never be reported to anybody, not even as an id.
--
-- `published_at IS NOT NULL` is the soft-removal half of the same question: a withdrawn or
-- taken-down tree was once public exactly when it is set (nothing unpublishes, decision 10, and a
-- tree born withdrawn is never published).
--
-- `users.license_version` is the record of acceptance: NULL is a *declined* consent (001's
-- comment and `users_license_pair`), a string is the version accepted, and
-- `RecordLicenseConsent` writes it from `POST /auth/oidc` and `POST /devices/claim` only when the
-- request carried the key.
--
-- ── The backfill ───────────────────────────────────────────────────────────────────────────────
--
-- Before this file the only writers of `community_trees` were the two INSERTs (sync `add_tree` and
-- `POST /trees`) and `ClaimDevice`'s adoption, and nothing wrote `deleted_at`. Account deletion
-- never touched the table; `users`' `ON DELETE SET NULL` left a deleted account's trees standing
-- with both owner columns NULL under **both** doors.
--
--   * A tree with both owners NULL is such an orphan. It is marked anonymized (it has nobody to
--     answer for it) and left **unpublished**: its account is gone, whether that account accepted
--     the license cannot be known, and it may have chosen to erase everything. Publishing it now
--     would decide both questions for somebody who can no longer be asked.
--   * An account-owned tree is published if its account has accepted the license, and left
--     unpublished otherwise, which is decision 7 applied to rows that already exist. It is published
--     at `updated_at` — the moment of its insert or its claim, the only two writers of that column —
--     **or at the acceptance, whichever is later**: a tree claimed on 1 September by an account that
--     accepted on 20 September went live on the 20th, not the 1st (review of #187, F2). The event
--     records the version accepted, as every `published` event does.
--   * A device-owned tree stays unpublished (decision 1).
--
-- One root location per tree (id = the tree's id, the rule both halves share) and an `added`
-- event per tree (id = the tree's id), and a `published` event for every tree this file publishes,
-- because every publication writes one. Before this file no tree had moved, so the root is the head
-- at publication: it is `was_public` exactly when its tree is published, and the `published` event
-- carries its position.
--
-- ── Why this file fails if it is applied twice ─────────────────────────────────────────────────
--
-- 001's rule. `ADD COLUMN`, `CREATE TABLE` and `ADD CONSTRAINT` all fail on a second application,
-- which is what `TestOnlyPendingMigrationsRun` observes; the kind constraint takes a new name for
-- the reason 002 gives.

-- ── community_trees ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE community_trees
    ADD COLUMN published_at        TIMESTAMPTZ,
    ADD COLUMN anonymized_at       TIMESTAMPTZ,
    -- The head location's accuracy (D6), a read cache of `community_tree_locations` exactly as
    -- `lat`, `lon` and `placement` now are. NULL is "the phone did not say".
    ADD COLUMN location_accuracy_m DOUBLE PRECISION
        CONSTRAINT community_trees_accuracy_is_a_distance
        CHECK (location_accuracy_m IS NULL OR location_accuracy_m >= 0);

UPDATE community_trees
   SET anonymized_at = updated_at
 WHERE user_id IS NULL AND device_id IS NULL;

UPDATE community_trees AS t
   SET published_at = GREATEST(t.updated_at, u.license_accepted_at)
  FROM users AS u
 WHERE t.user_id = u.id
   AND t.device_id IS NULL
   AND u.license_version IS NOT NULL;

-- Exactly one owner, or none with the reason stated. This is `contributions_owner` from 001, and it
-- is what makes a forgotten step in account deletion loud: `users`' `ON DELETE SET NULL` on a tree
-- nobody anonymized first would leave it ownerless and unanonymized, which this refuses, so the
-- whole deletion rolls back instead of leaving a tree nobody can move, withdraw or erase.
ALTER TABLE community_trees ADD CONSTRAINT community_trees_owner CHECK (
    (anonymized_at IS NOT NULL AND user_id IS NULL AND device_id IS NULL)
    OR (anonymized_at IS NULL AND ((user_id IS NULL) <> (device_id IS NULL)))
);

-- Half one of the publication invariant; half two is in code (see the header).
ALTER TABLE community_trees ADD CONSTRAINT community_trees_published_is_not_device_owned CHECK (
    published_at IS NULL OR device_id IS NULL
);

-- The keyset S2's tile delta pages over. Created here because S2 carries no migration.
CREATE INDEX idx_community_trees_updated ON community_trees (updated_at, id);

-- The tile's position arm: trees that are, or were, public, by where they stand now. Live ones are
-- the snapshot; soft-removed ones are the delta's removals. 001's `idx_community_trees_position`
-- stays for the 10 m dedupe, which also sees the caller's own unpublished trees.
CREATE INDEX idx_community_trees_public_position ON community_trees (lat, lon)
    WHERE published_at IS NOT NULL;

-- ── The location chain ─────────────────────────────────────────────────────────────────────────

-- Append-only, like the client's `species_assertions`: a correction supersedes the head rather than
-- overwriting it (decision 2). `community_trees.lat/lon/placement/location_accuracy_m` are the
-- head's read cache, moved in the same transaction.
CREATE TABLE community_tree_locations (
    -- The root row's id is the tree's id; a correction's is `TreeLocationCorrection.id`, which the
    -- client mints and also uses as its own `tree_locations.id`.
    id                       UUID PRIMARY KEY,
    tree_id                  UUID NOT NULL REFERENCES community_trees(id) ON DELETE CASCADE,
    lat                      DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon                      DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180 AND 180),
    placement                TEXT NOT NULL CHECK (placement IN ('gps', 'contributor_placed')),
    location_accuracy_m      DOUBLE PRECISION CHECK (location_accuracy_m IS NULL OR location_accuracy_m >= 0),
    -- The outbox item that carried it. NULL for a root written by `POST /trees` or by this file.
    contribution_client_uuid UUID,
    -- Who did it, on the server only (decision 4). Nulled by either deletion door.
    actor_user_id            UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_device_id          UUID REFERENCES devices(id) ON DELETE SET NULL,
    occurred_at              TIMESTAMPTZ NOT NULL,
    recorded_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- The next row in the chain. Deferred, because a new head is linked from the old one before the
    -- new row exists — the partial unique index below is not deferrable, so the old head has to
    -- stop being a head first.
    superseded_by            UUID REFERENCES community_tree_locations(id)
                             DEFERRABLE INITIALLY DEFERRED,
    anonymized_at            TIMESTAMPTZ,
    -- Decision 13; see the header. No default: every writer says which.
    was_public               BOOLEAN NOT NULL
);

-- One head per tree.
CREATE UNIQUE INDEX idx_community_tree_locations_head
    ON community_tree_locations (tree_id) WHERE superseded_by IS NULL;
CREATE INDEX idx_community_tree_locations_order
    ON community_tree_locations (tree_id, occurred_at, id);
CREATE INDEX idx_community_tree_locations_actor_user ON community_tree_locations (actor_user_id);
CREATE INDEX idx_community_tree_locations_actor_device ON community_tree_locations (actor_device_id);
-- The tile's chain arm: a tree that has left a tile is still reported to it, but only from a
-- position the public saw (decision 13).
CREATE INDEX idx_community_tree_locations_public_position ON community_tree_locations (lat, lon)
    WHERE was_public;

INSERT INTO community_tree_locations
    (id, tree_id, lat, lon, placement, location_accuracy_m, contribution_client_uuid,
     actor_user_id, actor_device_id, occurred_at, recorded_at, anonymized_at, was_public)
SELECT t.id, t.id, t.lat, t.lon, t.placement, t.location_accuracy_m,
       (SELECT c.client_uuid FROM contributions c
         WHERE c.kind = 'add_tree' AND c.tree_uuid = t.id
         ORDER BY c.occurred_at, c.client_uuid LIMIT 1),
       t.user_id, t.device_id, t.created_at, t.created_at, t.anonymized_at,
       t.published_at IS NOT NULL
  FROM community_trees t;

-- ── The audit log ──────────────────────────────────────────────────────────────────────────────

-- Every act on a community tree, with who did it and from which device (decision 4: full detail on
-- the server only). A table of its own because `contributions` has an XOR owner and cannot hold
-- both "which account" and "which device", and because the erase door deletes contributions.
CREATE TABLE community_tree_events (
    id                       UUID PRIMARY KEY,
    tree_id                  UUID NOT NULL REFERENCES community_trees(id) ON DELETE CASCADE,
    -- Spelled `= ANY (ARRAY[…])` rather than `IN (…)` on purpose: the api tests read
    -- `contributions.kind`'s vocabulary out of every migration by matching `CHECK (kind IN (`, and
    -- this column is a different vocabulary that happens to share the name.
    kind                     TEXT NOT NULL CONSTRAINT community_tree_events_kind_is_known CHECK (kind = ANY (ARRAY[
                                 'added', 'published', 'location_corrected',
                                 'species_named', 'species_corrected', 'withdrawn', 'taken_down'])),
    contribution_client_uuid UUID,
    actor_user_id            UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_device_id          UUID REFERENCES devices(id) ON DELETE SET NULL,
    occurred_at              TIMESTAMPTZ NOT NULL,
    recorded_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    before                   JSONB,
    after                    JSONB,
    anonymized_at            TIMESTAMPTZ,
    -- Decision 13; see the header. No default: every writer says which.
    in_public_history        BOOLEAN NOT NULL
);

CREATE INDEX idx_community_tree_events_tree ON community_tree_events (tree_id, occurred_at DESC, id DESC);
CREATE INDEX idx_community_tree_events_actor_user ON community_tree_events (actor_user_id);
CREATE INDEX idx_community_tree_events_actor_device ON community_tree_events (actor_device_id);

INSERT INTO community_tree_events
    (id, tree_id, kind, contribution_client_uuid, actor_user_id, actor_device_id,
     occurred_at, recorded_at, after, anonymized_at, in_public_history)
SELECT l.id, l.tree_id, 'added', l.contribution_client_uuid, l.actor_user_id, l.actor_device_id,
       l.occurred_at, l.recorded_at,
       jsonb_build_object('lat', l.lat, 'lon', l.lon, 'placement', l.placement,
                          'species_id', t.species_id),
       l.anonymized_at, false
  FROM community_tree_locations l
  JOIN community_trees t ON t.id = l.tree_id;

INSERT INTO community_tree_events
    (id, tree_id, kind, actor_user_id, occurred_at, recorded_at, after, in_public_history)
SELECT gen_random_uuid(), t.id, 'published', t.user_id, t.published_at, t.published_at,
       jsonb_strip_nulls(jsonb_build_object(
           'license_version', u.license_version,
           'lat', l.lat, 'lon', l.lon, 'placement', l.placement,
           'location_accuracy_m', l.location_accuracy_m)),
       true
  FROM community_trees t
  JOIN users u ON u.id = t.user_id
  JOIN community_tree_locations l ON l.id = t.id
 WHERE t.published_at IS NOT NULL;

-- ── The erase door's tombstone ─────────────────────────────────────────────────────────────────

-- A tree a deletion door hard-deleted (decisions 6 and 12). It mirrors `anonymized_contributions`: an
-- id, a time and whether the tree had ever been public — nothing that could say whose it was. A
-- late `add_tree` or `POST /trees` naming the id finds it and does not resurrect the tree, whatever
-- `was_public` says. Caches learn about the deletion from it (S2's `withdrawn_tree_ids`), but **only
-- where `was_public`**: an unpublished tree deleted under decision 12 was never shown to anybody,
-- and reporting its id would tell every stranger that a private tree existed and when its account
-- went (review of #190, F2). Nothing is ever removed from here.
--
-- The table is new in this file, so there are no rows to backfill; `was_public` has no default so
-- that no future writer can leave the question unanswered.
CREATE TABLE withdrawn_community_trees (
    id           UUID PRIMARY KEY,
    withdrawn_at TIMESTAMPTZ NOT NULL,
    was_public   BOOLEAN NOT NULL
);

-- The only read by time is S2's removal list, and it may only ever read once-public rows.
CREATE INDEX idx_withdrawn_community_trees_public ON withdrawn_community_trees (withdrawn_at, id)
    WHERE was_public;

-- ── The session's device ───────────────────────────────────────────────────────────────────────

-- The orchestrator's ruling of 2026-09-28: `POST /auth/oidc` binds the device it registered and
-- claimed to the session it mints, and `POST /auth/refresh` carries it to the successor, so the
-- audit log records the device a signed-in act really came from rather than the item's unverified
-- claim. NULL for a session signed in with no `device_uuid`, and for every session minted before
-- this file.
ALTER TABLE sessions ADD COLUMN device_id UUID REFERENCES devices(id) ON DELETE SET NULL;

-- ── contributions.kind ─────────────────────────────────────────────────────────────────────────

-- 002's drop-and-re-add, under a new name for 002's reason.
ALTER TABLE contributions DROP CONSTRAINT contributions_kind_admits_a_disputed_record;

ALTER TABLE contributions ADD CONSTRAINT contributions_kind_admits_a_community_tree_act CHECK (kind IN (
    'visit', 'observation', 'measurement',
    'care_event', 'favorite_toggle', 'private_reminder',
    -- Spec §3.4's nine, in ten values (002).
    'add_tree', 'species_claim', 'species_correction',
    'wrong_species_report', 'never_existed_report',
    'species_review_dismissal', 'record_review_dismissal',
    'photo_vote', 'photo_withdrawal', 'hazard_redirect',
    -- F27's one (004).
    'measurement_withdrawal',
    -- R79's two (005).
    'data_dispute', 'data_dispute_withdrawal',
    -- This round's two: the adder moves the pin (decision 5), and the adder withdraws the tree for
    -- everyone (decision 8).
    'location_correction', 'tree_withdrawal'
));

-- The withdrawal an `add_tree` has to find when it arrives after it (`treeWasWithdrawnBy`).
CREATE INDEX contributions_tree_withdrawal
    ON contributions (tree_uuid)
 WHERE kind = 'tree_withdrawal';
