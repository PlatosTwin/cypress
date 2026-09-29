# Rulings pending — a photograph taken signed out joins the public timeline at sign-in (2026-09-28)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge. No code comment cites this filename: the server comments name the ruling by its
date ("owner ruling 2026-09-28") and migration 006 by its file.

---

### R??? — Approve the photographs an account adopts, and never upload anything to do it

**Date:** 2026-09-28. **Decided by:** the owner. **Recorded by:** branch
`server/approve-adopted-photos`.

#### The gap

R72 ruling 5 approves a photograph at upload only when the caller is a signed-in account
(`store.BeginPhoto`: `moderation_state = 'approved'`, `approval_reason = 'auto_approved_launch'`).
A photograph an anonymous device uploads is `pending`: shown to its contributor and nobody else.

When that person signs in, `store.ClaimDevice` adopts the photograph onto the account. Until this
ruling it did not approve it. The only writers of `moderation_state` were that begin-time approval
and the operator's reject, and the reject never approves, so nothing ever approved the row: **a
photograph taken signed out stayed private for good, even after sign-in**. Screen 15 promises the
opposite: an account "backs them up and lets them join each tree's public timeline".

#### Ruling

**"Fix the sign-in approval gap now."** In full:

1. **From now on, the claim approves what it adopts.** In the same statement that adopts it,
   `ClaimDevice` approves a photograph that is `pending`, not withdrawn and not anonymized, with
   `approval_reason = 'auto_approved_launch'`. A `rejected` photograph stays rejected: an
   operator's takedown is not undone by a sign-in. An already-approved photograph keeps its reason.
2. **People who already signed in are included.** The owner decided this from a count; see below.
   Server migration 006 (`server/migrations/006_approve_adopted_photos.sql`) approves the
   photographs that claims already adopted while `pending`: rows with an owning account,
   `pending`, not withdrawn and not anonymized. The migration's header proves from the code that
   this predicate selects exactly that set. "Not withdrawn" means not withdrawn *on the server*,
   which is not the same thing; see "What 006 publishes that nobody can filter out".
3. **The invariant is enforced by the database.** 006 adds
   `photos_owned_live_photograph_is_not_pending`: a live photograph an account owns cannot be
   stored `pending`. A future adoption path that forgets to approve is then refused outright,
   where before it would have left the photograph private with no error.

#### The R77 boundary — explicitly not reversed

**R77 stands unchanged.** It forbids any backfill of local data that predates the sync path, and
photographs that never left the phone stay on the phone. This ruling uploads nothing and nothing
built under it can cause an upload. It changes only the **visibility of photographs already on the
server**, meaning rows already in `photos` that an anonymous device sent under the device token.
Nothing on the phone changes, and no photograph is queued, re-queued or re-sent.

#### Why `auto_approved_launch` and not a new reason

`approval_reason` is CHECK-constrained in `001_initial.sql`, so a new value would need a migration,
and the existing one already describes this case: a first-party photograph, published unscreened and
unblurred, from a signed-in account. The column exists to keep *screened* apart from *unscreened*
for a future pipeline, and that distinction survives. No consumer in the service or the app needs
"approved at upload" told apart from "approved at sign-in". The only response that carries
the column is `POST /photos/begin`'s, and the client does not decode it (`RemoteAPI.beginPhotoUpload`).
If such a consumer ever appears, adding the value is the round that owns it.

#### What the constraint commits the screening round to

`photos_owned_live_photograph_is_not_pending` encodes R72 ruling 5's launch rule. The round that
ends auto-approval (the one that will write `screened_and_passed` and will want an account's upload
to wait in `pending`) has to drop it. That is deliberate: ending the launch rule should be a
decision somebody records, not a side effect.

#### What 006 publishes that nobody can filter out, and what the owner decided

Raised by the adversarial review of PR #182 (F1) and reproduced there. The sequence, on the code
before this round:

1. The phone begins a photograph while signed out: device-owned, `pending`.
2. The contributor signs in, and the claim adopts it onto the account, still `pending`.
3. The contributor signs out and deletes the photograph on the phone. RULINGS R82 lets the phone do
   that for a photograph this installation took, whatever account holds it, and the phone sends a
   `photo_withdrawal` under its device token.
4. The server refuses it. `withdrawPhoto` knows only the row's `user_id` and `device_id`, the row
   is the account's and the caller is the device, so the answer is `ErrNotOwned` (`forbidden`).
   `withdrawPhoto`'s own comment calls this divergence real and reachable.
5. The row stays live, account-owned and `pending`, and 006 approves it. A photograph its
   contributor deleted becomes visible to everyone.

**006's predicate cannot exclude these rows, and no predicate could.** The server keeps no record
of a refused withdrawal: the refusal is an error inside `Store.Apply`'s transaction, which rolls
back the `photo_withdrawal` contribution row that would have recorded the attempt, and `photos` is
not written. On the server such a row looks exactly like an adopted photograph its contributor
still wants.

The forward half widens the same divergence. From this deploy on, a signed-out photograph adopted
by a claim is approved at step 2, so a withdrawal refused at step 4 leaves it public where before it
stayed private. That was already the case for a photograph an account began while signed in; the
claim adds the signed-out ones to that set. Closing it for good needs the server to know which
device took a photograph, which is the provenance column `withdrawPhoto`'s comment declines to
invent without a ruling.

**Decided: 006 ships as it stands (owner, 2026-09-28).** The owner authorized one read-only count
on production of the rows 006's UPDATE would write, and ruled in advance: if it is zero or a
handful, ship as is; otherwise cut back to forward-only. The count, run on 2026-09-28 inside a
READ ONLY transaction, found **0** such rows. Production then held 3 photographs, all
account-owned, live and already `approved`. The count is one moment's reading: a claim served by
the previous binary between the count and the deploy can still add a row.

#### Deploying 006: when the constraint breaks sign-in, and when it cannot

With `photos_owned_live_photograph_is_not_pending` in place, a binary from before this round fails
any claim for a device holding a live `pending` photograph: its adoption leaves the row `pending`,
Postgres refuses the row, and the request answers 500. That includes `POST /auth/oidc` with a
`device_uuid`, which is the sign-in itself, as well as `POST /devices/claim`. An old binary cannot
*boot* against a database at 006 (`Migrate` refuses a rollback onto a newer schema), so the window
exists only while an old binary that is already running shares the database with a new one that
has applied 006.

- **Where it is closed: `cypress-sync` as configured today.** One machine; `server/fly.toml` has no
  `[deploy]` strategy and no `release_command`; the migration runs in `store.Open` when the new
  binary boots. The old and new binaries never serve at the same time.
- **Where it opens:** scaling the app to two or more machines, or deploying with a canary or
  bluegreen strategy. An old machine keeps serving, and failing sign-ins, until it is replaced.
  Deploy 006 only on one machine with the default strategy.

#### Out of scope here, recorded for the roadmap

The same review (F3) found that the claim asks for no proof that the caller holds the device:
an account that knows a device UUID can claim it, and since this ruling the claim also publishes
that device's `pending` photographs, under the claiming account. The #174 guard protects only a
device that is already claimed. Proof of possession at claim is not built in this round.
