# Ruling (pending number): no backfill of pre-sync-path local data

**Date:** 2026-08-15. **Decided by:** owner, via decision round (AskUserQuestion), option chosen: "No backfill."

## Question put to the owner

Local data that predates the sync path cannot reach the server today:

- **Measurements and vitality check-ins** captured on builds before the outbox send sink landed
  settled locally as `done` without ever being sent; the drain selects `pending` (and manual
  retry selects `failed`), so a never-sent `done` row is never retried and nothing today can
  push it (see E264's surrounding record of the send-sink gap and its consequence that every
  pre-sink outbox row is locally applied and unsent).
- **Photos** have no send path at all, old or new — the binary reaches only the local apply
  sink (E264); a future send path is additionally blocked on the server's missing idempotency
  key for the photo-begin endpoint.

Rows captured *after* the send sink landed already sync anonymously at capture time under the
device token, and sign-in claims them server-side; those need no backfill and are not covered
by this ruling.

Options offered: (1) one opt-in backfill round after photo sync lands, covering JSON rows and
photos; (2) JSON-only backfill now, photos later; (3) no backfill.

## Ruling

**No backfill.** Pre-sync-path local rows and pre-existing photo binaries stay on-device
permanently. Only data created going forward syncs. No opt-in backfill UI, no re-enqueue of
settled rows, no retroactive photo upload — not now and not as a later phase of the photo
send-path work.

## Consequences

- The hard requirement on the outbox-bypassing-mutations round (task158 live-layer §3.4 scope)
  — that pre-existing local rows must never be retroactively enqueued — is **permanent policy**,
  not a provisional safety measure awaiting a backfill design.
- Any future photo send-path round (closing E264) scopes to **new photos only**. Its design
  must not sweep existing local photo rows into upload.
- Agents proposing sync-coverage improvements should not re-raise backfill; the owner has
  decided it. (Re-raising a decided item is itself a documented failure mode here.)
