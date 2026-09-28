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
and the operator's reject, so nothing ever revisited the row: **a photograph taken signed out
stayed private for good, even after sign-in**. Screen 15 promises the opposite: an account "backs
them up and lets them join each tree's public timeline".

#### Ruling

**"Fix the sign-in approval gap now."** In full:

1. **From now on, the claim approves what it adopts.** In the same statement that adopts it,
   `ClaimDevice` approves a photograph that is `pending`, not withdrawn and not anonymized, with
   `approval_reason = 'auto_approved_launch'`. A `rejected` photograph stays rejected: an
   operator's takedown is not undone by a sign-in. An already-approved photograph keeps its reason.
2. **People who already signed in are included.** Server migration 006
   (`server/migrations/006_approve_adopted_photos.sql`) approves the photographs that claims
   already adopted while `pending`: rows with an owning account, `pending`, not withdrawn and not
   anonymized. The migration's header proves from the code that this predicate selects exactly
   that set.
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
