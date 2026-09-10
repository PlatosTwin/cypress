-- 005 — `contributions.kind` learns `data_dispute` and `data_dispute_withdrawal`.
--
-- The client half is `AppSchema` v22 (R79, branch `feat/r79-city-disputes`), which adds the three
-- dispute tables and widens `outbox.kind`'s CHECK by these same two values. **Until both sides
-- move, a dispute is refused twice**: before v22 the phone cannot store the queue row, and before
-- this file the service cannot store the contribution. That is 004's sentence about v21 and it is
-- repeated here because it is still the whole reason this file exists as its own change — `server/`
-- has no CI and should not travel inside an app change.
--
-- Two values rather than one because a dispute can be **taken back by the person who raised it**.
-- The standing complaint about the community flagging flow is that a flag cannot be retracted by
-- its author; shipping a new dispute surface with the same defect would repeat it. A withdrawal
-- costs a verb and a payload here, not a second migration.
--
-- ── The shape is 004's, including the two parts that look like warts ───────────────────────────
--
--   * a **named** constraint dropped and another added, inside the one transaction the runner
--     already wraps every file in, so there is no window in which the column is unconstrained;
--   * and the replacement takes a **new name**. 001's rule is that a migration is a plain statement
--     that fails loudly if it is somehow applied twice. Dropping and re-adding under one name is
--     idempotent, so a second application would succeed silently and `TestOnlyPendingMigrationsRun`
--     — which detects broken pending-detection precisely by re-running the newest file and
--     requiring it to fail — would have nothing to observe. Under a new name the second `DROP`
--     finds nothing and says so.
--
-- ── Neither of these materializes, and that is a decision rather than a shortfall ──────────────
--
-- 004 added two indexes because it had two lookups to serve. This file adds none, because nothing
-- here looks anything up: no dispute table exists server-side and no read endpoint serves one. The
-- `contributions` row **is** the record, which is the contract five of BUILD-PLAN §4's six kinds
-- and eight of spec §3.4's ten already have.
--
-- The reason is the one 002 gives for the eight it could not evaluate, sharpened: adjudicating a
-- dispute means moving city inventory data — a coordinate, a species — on an unadjudicated say-so,
-- and the surface that adjudicates is a web deliverable (ARCHITECTURE §8's closing note: the
-- coordinator dashboard is not built here). Recording the act and refusing to guess at its effect
-- is the honest half.
--
-- **What the next round must not read past.** The badge round — the flag on the tree profile, the
-- "trees with data issues" filter — needs a *read* endpoint over these rows, and the moment one
-- exists a withdrawal that only records itself becomes a claim somebody is shown. That is ERRATA
-- E280, and it is the same sentence 002 wrote about `photo_withdrawal` and that 004 had to come
-- back and correct. The round that serves a dispute back is the round that owes it an ownership
-- gate and a tombstone; see the note beside `syncKinds` in `internal/api/sync.go`.

ALTER TABLE contributions DROP CONSTRAINT contributions_kind_admits_a_withdrawn_reading;

ALTER TABLE contributions ADD CONSTRAINT contributions_kind_admits_a_disputed_record CHECK (kind IN (
    'visit', 'observation', 'measurement',
    'care_event', 'favorite_toggle', 'private_reminder',
    -- Spec §3.4's nine, in ten values (002).
    'add_tree', 'species_claim', 'species_correction',
    'wrong_species_report', 'never_existed_report',
    'species_review_dismissal', 'record_review_dismissal',
    'photo_vote', 'photo_withdrawal', 'hazard_redirect',
    -- F27's one (004).
    'measurement_withdrawal',
    -- R79's two.
    'data_dispute', 'data_dispute_withdrawal'
));
