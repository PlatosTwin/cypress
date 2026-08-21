-- 002 — `contributions.kind` learns spec §3.4's nine mutations.
--
-- The client half is `AppSchema` v17, which widens `outbox.kind`'s CHECK by the same ten values.
-- Until both sides move, an item of one of these kinds is refused twice: the phone cannot store the
-- queue row and this table cannot store the contribution.
--
-- ── The ten values, and why nine mutations are ten ─────────────────────────────────────────────
--
-- §3.4 counts the review-dismissal *pair* as one entry in its list of nine. They stay two values
-- here because they close reports on two different seams under two different rules, and one value
-- for both would put that distinction inside the JSONB payload where a query cannot cheaply see it.
--
-- ── Recorded, not materialized, and that is the existing contract ──────────────────────────────
--
-- Five of the six kinds this table already accepts have no materialized table behind them: a visit,
-- an observation, a measurement, a care event and a private reminder are the `contributions` row and
-- nothing else. Only `favorite_toggle` has a second table, because `GET /me/grove/{tree}/favorite`
-- is a per-tree read (#167) that exists specifically not to be a scan.
--
-- Nine of the ten below are the same: the row is the record. The exception is `add_tree`, which
-- materializes into `community_trees` because the tree has to be *findable* — the 10 m proximity
-- dedupe reads that table, and a tree recorded only as a contribution is a tree the next
-- contributor standing under it would be invited to add again.
--
-- Materializing **eight** of the rest needs tables this service does not have and rules it cannot
-- evaluate: a species assertion chain with a supersession order, review flags with a status and an
-- author's arm, per-photograph vote tallies. Those are ARCHITECTURE §8's moderation deliverable, and
-- inventing a half of one here — a `species_id` moved on somebody's unadjudicated say-so — would be
-- this service deciding a question the design has not answered.
--
-- **`photo_withdrawal` is the ninth and its reason is a different one**, stated here because the
-- sentence above was written over it once already. This service can perform that deletion: `photos`
-- is in 001, `Store.DeletePhotoByContributor` takes the owner the sync handler already holds, and
-- `DELETE /photos/{id}` exists. It is deferred because **no photograph reaches this service yet** —
-- the outbox's send sink carries no photo method — so a withdrawal would name bytes nothing here
-- has ever held. The round that wires photo upload wires this deletion with it; see the long note
-- in `sync.go` beside `syncKinds`, and
-- `docs/errata-pending/outbox-kind-vocabulary-drift.md`.
--
-- ── Dropped and re-added, and the new constraint gets a new name ──────────────────────────────
--
-- Unlike SQLite this needs no table rebuild: a named constraint is dropped and another added, in
-- the one transaction the runner already wraps every file in, so there is no window in which the
-- column is unconstrained. The validating scan `ADD CONSTRAINT` performs is one pass over a table
-- of this size.
--
-- The original constraint was written inline on the column and therefore carries Postgres'
-- generated name, `contributions_kind_check`. **The replacement deliberately does not reuse that
-- name**, and the reason is 001's own rule rather than taste: migrations here are plain statements
-- that fail loudly if they are somehow applied twice, because "with migrations tracked and each one
-- applied inside a transaction, a second application cannot happen — and if it somehow did, failing
-- loudly is the behaviour worth having." Dropping and re-adding under one name is idempotent, so a
-- second application would succeed silently and `TestOnlyPendingMigrationsRun` — which detects a
-- broken pending-detection precisely by re-running the newest file and requiring it to fail — would
-- have nothing to observe. Under a new name the second `DROP` finds nothing and says so.

ALTER TABLE contributions DROP CONSTRAINT contributions_kind_check;

ALTER TABLE contributions ADD CONSTRAINT contributions_kind_is_known CHECK (kind IN (
    'visit', 'observation', 'measurement',
    'care_event', 'favorite_toggle', 'private_reminder',
    -- Spec §3.4's nine.
    'add_tree', 'species_claim', 'species_correction',
    'wrong_species_report', 'never_existed_report',
    'species_review_dismissal', 'record_review_dismissal',
    'photo_vote', 'photo_withdrawal', 'hazard_redirect'
));
