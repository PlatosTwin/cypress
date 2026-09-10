-- 005 — `contributions.kind` learns `data_dispute` and `data_dispute_withdrawal`.
--
-- The client half is `AppSchema` v22 (R79, branch `feat/r79-city-disputes`), which adds the three
-- dispute tables and widens `outbox.kind`'s CHECK by these same two values. **Until both sides
-- move, a dispute is refused on whichever side has not moved**, and the two refusals are not the
-- same refusal:
--
--   * before v22 the phone cannot store the queue row at all. That is the **expectation**, not a
--     measurement: v22 does not exist on any branch this file can be tested against, so nothing
--     here has observed it and nothing here should be read as having done so;
--   * before this file the service refuses the contribution, and that half **is** measured —
--     `TestEveryKindTheHandlerAcceptsIsStorable` goes red on
--     `violates check constraint "contributions_kind_admits_a_withdrawn_reading"` with 005 removed.
--     Worth knowing operationally: the code that reaches the client is `server_error`, which **is
--     retryable**, so a v22 phone talking to a service without this file backs off and drains later
--     rather than failing terminally. A payload the handler refuses is the opposite —
--     `validation_failed` is not retried, so that row goes `.failed` on the first attempt and sits
--     red on screen 17 until the person clears it.
--
-- Either way this file exists as its own change for 004's reason: `server/` has no CI and should not
-- travel inside an app change.
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
-- No dispute table is created here and no row outside `contributions` is written by either kind:
-- the `contributions` row **is** the record, which is the contract five of BUILD-PLAN §4's six
-- kinds and eight of spec §3.4's ten already have.
--
-- The reason is the one 002 gives for the eight it could not evaluate, sharpened: adjudicating a
-- dispute means moving city inventory data — a coordinate, a species — on an unadjudicated say-so,
-- and the surface that adjudicates is a web deliverable (ARCHITECTURE §8's closing note: the
-- coordinator dashboard is not built here). Recording the act and refusing to guess at its effect
-- is the honest half.
--
-- **What the next round must not read past.** The badge round — the flag on the tree profile, the
-- "trees with data issues" filter — needs a *read* endpoint over these rows, and the moment one
-- serves a dispute to anybody but its raiser, a withdrawal that only records itself becomes a claim
-- somebody is shown. That is ERRATA E280, the same sentence 002 wrote about `photo_withdrawal` and
-- that 004 had to come back and correct. The round that serves a dispute back owes two things this
-- file does not write: a rule for **who may read** a dispute, and a **tombstone** so a withdrawn one
-- stops being served. Neither is speculative work this file could have done — a read gate against a
-- read that does not exist is a gate nothing can prove.
--
-- The **withdrawal's** ownership is a different question and it is answered here: see
-- `store.disputeIsThisIdentitys` and the index below. Recording "Bob withdrew Alice's dispute" as
-- `applied` writes a false statement into the record the moderation round reads, and that is true
-- whether or not any endpoint serves it back.

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

-- The dispute a withdrawal names.
--
-- One lookup, so one index, and it is 004's `contributions_measurement_reading_id` with a different
-- `kind` in the predicate: `store.disputeIsThisIdentitys` asks whether the dispute a
-- `data_dispute_withdrawal` names was raised by the identity now taking it back. 004's index cannot
-- serve it — a partial index only covers rows matching its own `WHERE`, and that one holds
-- `kind = 'measurement'` rows.
--
-- `upper(payload ->> 'id')`, matching the query character for character, and text rather than
-- `::uuid` for the two reasons 004 sets out: the same value reaches this service in two spellings
-- (`SQLiteValue`'s uppercase, `JSONEncoder`'s lowercase), and a cast can *error* rather than merely
-- miss on a payload of some other kind whose `id` is not a UUID. That second reason is not
-- theoretical here — `docs/errata-pending/grove-species-known-unscoped-cast.md` is exactly that
-- defect, live in this schema today, one file away.
CREATE INDEX contributions_disputed_record_id
    ON contributions (upper(payload ->> 'id'))
 WHERE kind = 'data_dispute';
