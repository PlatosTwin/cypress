# Unnumbered — signing out kept the credential, and deleting the account kept both

Staged unnumbered per CLAUDE.md's "Numbering and shared files". Found on `feat/session-restore`
while implementing owner ruling 5 of 2026-08-14; the ruling itself is staged in
`docs/rulings-pending/session-restore-on-reinstall.md`.

---

## The defect

`AccountModel.signOut()` called `LocalAPI.signOut()` and nothing else. The You tab's sign-out
therefore cleared `app_state.current_user_id` and **left the account's session in the Keychain**.

`AppSession.authorization()` reads `storedSession` before it looks at anything else, so from the tap
onward the app was in this state:

- every screen drew a signed-out installation;
- every request it made authenticated as the account that had just signed out;
- `applyOne`'s user arm accepted those items, so the service went on attributing the work to that
  account — including work the person did after leaving it.

`deleteAccount` had the same shape one step worse: `AppSession.forgetEverything()` exists, is
documented as the deletion's counterpart ("a device token minted under a deleted account's claim is
a pointer to it"), and had **no caller at all**. So RULINGS R3's promise held over the tables and not
over the Keychain.

## Why it stayed invisible

The same reason `LocalAPI.deleteAccount` was complete and uncalled before ERRATA E131: nothing on
screen reads a credential. `AccountModel.load()` asks `LocalAPI.userID`, which was correctly nil, so
the You tab drew exactly the right thing over exactly the wrong state. Every test of sign-out
asserted the local half, because the local half was the whole of what sign-out was written to do.

`AccountModel` holding only `LocalAPI` is the structural half of it, and that choice was argued and
correct when it was made — the model's own header explains it, and `/auth/*` is genuinely not on
`CypressAPI`. What changed is that a session now exists to forget.

## The population it had already reached

This is not only a defect going forward. **Every beta install whose owner has tapped `Sign out` is
already in this state** — `current_user_id` cleared, a live session in the Keychain — and has been
since the sign-out was written. They do not need to reinstall to meet the mirror rule; they meet it on
the first launch after the update that carries it, which is what made the discriminator in
`SessionRestore.reconcile` a merge blocker rather than a refinement (review of PR #87, F1).

The reviewer staged the pre-fix path and measured both halves of it, including the part that makes it
unrecoverable — the restore's own `claimDevice` erases the evidence on its way past:

```
PROBE signedOutUserID BEFORE the update boot: 5E12E12E-…-A1
PROBE signedOutUserID after:                  nil     # claimDevice cleared it
```

`signed_out_user_id` is the discriminator, and it is a fact `LocalAPI.signOut()` already writes for
its own stated reason. Reading it is what tells "this database was deleted" from "this person left".

## What made it load-bearing

Ruling 5 makes `DataLayer.boot` read the Keychain as the authority on who is signed in. Under that
rule the surviving item is not merely wrong, it is *believed*: the database says nobody, the Keychain
says somebody, and the next launch signs the person back into the account they left. A restore that
undid every deliberate sign-out would have been a worse defect than the one the ruling was written to
close — so the restore could not ship without this.

That is the general lesson rather than the specific fix. **A rule that resolves a disagreement
between two stores turns every place that updates one of them into a correctness requirement.**
Before the mirror rule, forgetting the Keychain on sign-out was a leak. After it, it is a loop.

## The fix

`AccountModel` takes the `AppSession` beside the `LocalAPI`. Sign-out forgets the session and keeps
the device credential — the anonymous queue was draining before the tap and goes on draining after it
(D9). Deletion calls `forgetEverything()`, which drops both.

Both drop the credential **first** and refuse if that throws, and the two orderings are one rule:
*never leave this app holding a credential for an account it has stopped having.* The failures are
not symmetric, which is what settles it. Dropping the credentials and then failing to delete leaves
an intact account this phone is signed out of, and signing in again resolves to the same `users` row.
Deleting and then failing to drop leaves a session whose account's records are gone — and the next
launch's reconciliation would sign the person straight back into it.

## The control that keeps the fix honest

The sign-out assertion — "the session is gone after the tap" — is satisfied just as well by a
sign-out that threw *both* credentials away, and that would be its own defect: `POST
/devices/register` retires the previous token on every call, so an unnecessary re-registration signs
out a queue that was draining. So the fix ships with a control asserting the opposite case: after a
sign-out the **device** credential is still there. Under the mutation that swaps `signOut()` for
`forgetEverything()`, the control goes red and the sign-out assertion stays green, which is what
attributes each failure to the right rule. Same discipline as the reinstall/no-re-register pair in
`158-the-keychain-outlived-the-database.md`.

## Ruled by the owner, 2026-08-15: an automatic sign-out does not re-home the account's rows

**The question.** Ending signed out leaves every account-owned private reminder and favorite
attributed to the account (`user_id = A, device_id = NULL`), and the reads that answer "mine" ask for
the *current* user or this device — so on a device with nobody signed in they are visible to nobody.
Measured during review of PR #87:

```
user_id=A  device_id=NULL  visible=0
```

That is not new to this round; it is what `LocalAPI.signOut()` has always done, and RULINGS **R3**
argues for keeping the rows rather than deleting them. What the mirror rule raised is whether an
*involuntary* ending — an expired family, a refused session, an upgrade honoring an old sign-out —
should re-home those rows to the device so the person can still see their own reminders.

**The ruling (owner, 2026-08-15): it should not.** The rows stay the account's and stay invisible
while nobody is signed in, and **they reappear on the next successful sign-in**. No re-homing, on
either the deliberate or the automatic path.

The reasoning to carry forward: re-homing would be the app deciding, without being asked, that
somebody's account records are now this phone's. Invisibility is recoverable by signing in — the same
Apple identity resolves to the same `users` row — and a re-attribution is not recoverable at all. An
automatic ending is also the case where the person has expressed no intent whatever, which is the
worst moment to infer one. So the two paths stay identical, which is also why no code changed for this
ruling: `signOut()` already does exactly what was ruled.

## Ruled by the owner, 2026-08-15: the interrupted-deletion residual closes by wiring `DELETE /me`

**The residual.** If a deletion succeeds and `AppSession.forgetEverything()` then throws, this app
holds credentials for an account whose local records are gone, and the next launch's reconciliation
restores it — the deletion cleared `signed_out_user_id`, so the discriminator has nothing to read.
Writing that marker back is the obvious repair and it is refused: R3 requires that a deleted account
is not resumable, and `AccountDeletionTests` asserts exactly that.

**The ruling (owner, 2026-08-15): it is accepted and documented, and it closes in a follow-up round
by wiring `DELETE /me`** — not by adding a mechanism to the client's local path. The blocker that
route was left on has expired (see the section below), so the repair is a route to wire rather than a
rule to invent.

**Why wiring the route closes it, rather than merely narrowing it.** Once the deletion reaches the
service, the account is gone on the far side, so the surviving session is one the service will refuse
the first time anything presents it. That refusal already runs `AppSession`'s involuntary-discard path,
which since this round tells the local half within the same run (`onSessionEnded`). So a restore that
happened because a Keychain removal failed is undone by the first request that needs a credential —
**the race becomes self-correcting**, and it corrects in the direction of the deletion. Until that
round lands, the residue is an account restored with none of its rows, re-deletable from the same
screen.

## Adjacent, and not fixed here

`DELETE /me` still has no shipping caller. `AccountModel` deletes through `LocalAPI.deleteAccount`,
and `RoutedAPI.deleteAccount` routes local as well, so an account deleted in the You tab is deleted
on the phone and left standing on the service.

The routing is documented as deliberate, and the reason it gives has since stopped being true.
`RoutedAPI.deleteAccount` says the remote half needs the client's still-queued `client_uuid`s, that
this router holds no queue to read them from, and that `RemoteAPI.pendingOutboxKeys` "is the seam for
that and the composition root is what fills it". The composition root **does** fill it —
`DataLayer.boot` passes a provider that reads the outbox table — so the stated blocker was removed by
the wiring round and the routing did not follow. That is a separate finding from this one, about a
route rather than a credential, and it is recorded here because the two were found in the same read.

Its interaction with this round is worth one line, though: because deletion is local-only, the
`forgetEverything()` added above throws away credentials for an account that still exists on the
service. That is the safe direction — the phone stops acting as an account whose records it has
destroyed — and it is not the end state R3 describes.
