-- 004 — `contributions.kind` learns `measurement_withdrawal`, and the two lookups it needs.
--
-- The client half is `AppSchema` v21 (report F27), which widens `outbox.kind`'s CHECK by the same
-- one value. Until both sides move, a withdrawal is refused twice: before v21 the phone cannot
-- store the queue row, and before this file the service cannot store the contribution. F27's author
-- found this gap, named it, and deliberately left it — `server/` has no CI and should not travel
-- with an app change — so this is the other half.
--
-- ── The shape is 002's, deliberately, including the part that looks like a wart ────────────────
--
-- 002 widened this same CHECK by ten values, and it is the precedent this file copies:
--
--   * a **named** constraint dropped and another added, in the one transaction the runner already
--     wraps every file in, so there is no window in which the column is unconstrained;
--   * and the replacement takes a **new name**, which is not taste. 001's rule is that a migration
--     is a plain statement that fails loudly if it is somehow applied twice. Dropping and re-adding
--     under one name is idempotent, so a second application would succeed silently and
--     `TestOnlyPendingMigrationsRun` — which detects broken pending-detection precisely by
--     re-running the newest file and requiring it to fail — would have nothing to observe. Under a
--     new name the second `DROP` finds nothing and says so.
--
-- ── This one materializes, which makes it the third ────────────────────────────────────────────
--
-- Of the sixteen kinds this table already accepted, two do something beyond being recorded:
-- `add_tree` inserts into `community_trees` because a tree has to be findable, and
-- `photo_withdrawal` tombstones `photos.deleted_at` because ERRATA E280 is about a service that
-- reports a removal and goes on serving the thing.
--
-- `measurement_withdrawal` is E280's argument on this table instead of that one. A reading is not
-- a file, so there is nothing here to destroy — but `contributions.deleted_at` already exists and
-- **every read this service answers already filters on it**: the grove tally, the journal, the
-- species-known list, the per-tree visit count. Nothing has ever written it. So the whole of
-- "the reading stops being served" is one `UPDATE`, and declining to make it would be answering
-- `applied` to a withdrawal while `GET /me/grove` goes on counting the number.
--
-- ── The two indexes, and why the expression is `upper(... ->> ...)` ────────────────────────────
--
-- Both lookups are by a UUID that lives **inside** a JSONB payload rather than in a column, and
-- that is not a shortcut: `contributions` is keyed on the outbox item's `client_uuid`, while a
-- withdrawal names the *reading's* id (`TreeMeasurement.id`), and the two are different values on
-- the client by construction. There is no column here that holds the second one.
--
-- Compared as **text under `upper()`**, not cast to `uuid`. Two reasons, and the second is the one
-- that decides it:
--
--   * the same value reaches this service in two spellings — `internal/uuid`'s own header records
--     that the client mints `SQLiteValue`'s uppercase and `JSONEncoder`'s lowercase, which is why
--     `Parse` is case-insensitive and why `AppSchema` v13 declares `COLLATE NOCASE`. A plain `=`
--     on the extracted text would therefore be a dedupe that works until it does not;
--   * and `(payload->>'id')::uuid` — the cast `GroveSpeciesKnown` uses, which handles the case
--     question by itself — can *error* here rather than merely miss. That query is filtered by a
--     column, this one is filtered by `kind`, and nothing in the standard promises Postgres
--     evaluates the `kind` qual before the cast. A payload of some other kind carrying a
--     non-UUID `id` would then fail the whole request. `upper()` on text has no such arm.
--
-- Partial, so each index holds only the rows its lookup can match, and the expression is written
-- **identically** to the one in `internal/store/measurements.go` — an index whose expression does
-- not match the query's is dead weight that looks like a plan.

ALTER TABLE contributions DROP CONSTRAINT contributions_kind_is_known;

ALTER TABLE contributions ADD CONSTRAINT contributions_kind_admits_a_withdrawn_reading CHECK (kind IN (
    'visit', 'observation', 'measurement',
    'care_event', 'favorite_toggle', 'private_reminder',
    -- Spec §3.4's nine, in ten values (002).
    'add_tree', 'species_claim', 'species_correction',
    'wrong_species_report', 'never_existed_report',
    'species_review_dismissal', 'record_review_dismissal',
    'photo_vote', 'photo_withdrawal', 'hazard_redirect',
    -- F27's one.
    'measurement_withdrawal'
));

-- The reading a withdrawal names.
CREATE INDEX contributions_measurement_reading_id
    ON contributions (upper(payload ->> 'id'))
 WHERE kind = 'measurement';

-- The withdrawal a late reading has to find. See `measurementWasWithdrawn` for why a reading looks
-- for its own withdrawal on the way in: the outbox drains due items `ORDER BY seq`, and an item in
-- backoff is not due — so a `measurement` that failed once can land *after* the withdrawal that
-- took it back, and without this lookup it would be served forever.
CREATE INDEX contributions_withdrawn_reading_id
    ON contributions (upper(payload ->> 'measurementID'))
 WHERE kind = 'measurement_withdrawal';
