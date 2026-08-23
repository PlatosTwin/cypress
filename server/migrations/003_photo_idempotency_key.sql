-- 003 — `photos` learns the client-minted key that makes `POST /photos/begin` retryable.
--
-- The client half is `AppSchema` v18, which gives every staged binary a row and an `id`; this is the
-- column that id lands in.
--
-- ── The defect this closes, which is why a photo send path could not be built ──────────────────
--
-- `beginPhoto` did `photoID := uuid.New()` unconditionally. Every call therefore created a
-- photograph, and a call is not a promise that the caller heard the answer: a phone that begins an
-- upload and loses the connection before the response arrives has no way to ask "did that land?".
-- Its only options were to give up on the binary or to begin again, and beginning again made a
-- second `photos` row for one photograph — visible twice on the tree, counted twice in the grove,
-- and impossible to tell apart afterwards because nothing on either row said they were the same
-- picture.
--
-- ERRATA **E264** names this as one of the three things a send path needs and does not have. It is
-- the reason the retry could not simply be "call begin again", and therefore the reason the outbox's
-- 48 h backoff — which retries everything else exactly that way — had nothing it could do with a
-- photograph.
--
-- ── Why the key is the client's and not this service's ─────────────────────────────────────────
--
-- The same argument `community_trees.client_uuid` makes, and `add_tree` before it: an idempotency
-- key has to exist *before* the first attempt, because the failure it protects against is the first
-- attempt's answer going missing. A key this service mints is minted too late to be one. The client
-- has had a stable id for the binary since the shutter closed (`OutboxPhoto.id`), so the key is
-- simply that.
--
-- ── Nullable, and scoped to the owner ──────────────────────────────────────────────────────────
--
-- **Nullable** because every photograph already in this table was created without one and there is
-- no honest value to invent for them. A `NOT NULL` with a backfilled default would be claiming that
-- rows which were never deduped had been.
--
-- **Unique per owner rather than globally**, via the two partial indexes below. A client mints these
-- as UUIDs so a cross-account collision is not a practical concern; the reason to scope it anyway is
-- that a global unique key would let one account's begin be *refused* by another account's row —
-- turning somebody else's key into a denial of service against a photograph, and leaking that the
-- key exists. Scoping makes "already begun" a question only ever asked within one owner.
--
-- Partial (`WHERE client_uuid IS NOT NULL`) so the pre-existing rows, which all have NULL, do not
-- collide with each other. Two indexes rather than one over `COALESCE(user_id, device_id)` because
-- `photos` has exactly one owner by CHECK and the two arms are separate columns; a coalesced index
-- would also make a user id and a device id that happened to be equal into the same key.

ALTER TABLE photos ADD COLUMN client_uuid UUID;

CREATE UNIQUE INDEX photos_client_uuid_per_user
    ON photos (user_id, client_uuid)
    WHERE client_uuid IS NOT NULL AND user_id IS NOT NULL;

CREATE UNIQUE INDEX photos_client_uuid_per_device
    ON photos (device_id, client_uuid)
    WHERE client_uuid IS NOT NULL AND device_id IS NOT NULL;
