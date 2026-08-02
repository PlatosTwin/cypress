# The favorite that reverted only on the owner's phone (#174; supersedes the readings of #139, #153, #167)

**UNNUMBERED — orchestrator splices under the real next number at merge.**

## The defect

Tapping Favorite on a tree profile flashed dark green for about half a second and went back to
white — on the owner's physical iPhone, on every build since the feature shipped, through four
fixes, and never once on a fresh simulator.

## The root cause

`LocalAPI.signOut()` keeps `device.user_id` — deliberately, so the account can be resumed — but
`LocalAPI.sync` ran `adoptRowsWrittenAfterTheClaim` after **every batch that applied anything**,
gated only on that claim row existing. On a device that had ever signed in and signed out (E124
signs the owner in at the third visit save; the You tab's Sign out is one tap), the sequence on
every favorite tap was:

1. The tap enqueues a **device-owned** toggle (D9: nobody is signed in) and awaits the drain.
2. The drain applies it: a `favorites` row with `device_id` set, `deleted_at NULL`. So far correct.
3. The same `sync` call re-runs `claimDevice` for the account the stale claim row names.
   `claimFavorites` adopts the row it just applied: `user_id` set to the signed-out account,
   `device_id` cleared.
4. The write path's re-read asks `holdsFavorite(userID: nil, deviceID: D)`. The row now matches
   neither arm. The heart goes back to white, in exactly the time one awaited drain takes.

The same sweep silently re-attributes every device-owned visit, photo, reminder and photo vote
written after sign-out to the signed-out account — the favorite was only the visible symptom,
because it is the one control that re-reads its own write. That is also a privacy defect of the
E157 family: sign-out promises "attribution goes back to the device," and the post-batch re-claim
was quietly un-promising it one batch later.

## Why four fixes missed it

- **#139** joined the write and the read through the real store — on a store with no claim row.
- **#153** and **#167** each widened the *read* (outbox `pendingFavoriteState` first, applied rows
  second). But the toggle here syncs successfully and lands `done` — `done` is skipped by design,
  and the applied row itself was being moved out from under every read there is.
- **#167's outbox-read patch** covered the skipped-drain/full-batch window only; this drain was
  not skipped and the batch was not full.
- Every verification ran on a fresh simulator, which has no `device.user_id` row. The one row of
  device history that mattered was the one no fixture wrote. Screen 17 could not help the owner
  either: the sync genuinely succeeded, so there was no failed item to show a reason for.

## The fix

`adoptRowsWrittenAfterTheClaim` now requires the claimed account to be the currently signed-in
one (`claimedUser == self.userID`, plus `userID != nil`). The straddle the method exists for —
queued before sign-in, drained after — has the person signed in at drain time, so that case is
unchanged; a tail drained while signed out stays the device's and is adopted by the first
re-claim after the account is resumed, which is when the promise "your work comes with you" is
back in force.

## The test

`FavoriteRoundTripTests.aFavoriteSavedAfterSignOutSurvivesTheStaleClaim` — real seed, real store:
claim, sign out, tap, and assert the applied row still answers the device on all three reads
(`TreeProfileModel.isFavorite`, `mapMembership(.favorites)`, `ProfileFavoriteWriter.storedState`).
Proven red on the unfixed tree (all three lost the row while `pendingFavoriteState` was `nil` —
the toggle had applied) and green on the fix.
