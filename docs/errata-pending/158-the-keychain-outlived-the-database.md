# Unnumbered — the Keychain outlived the database, and the queue could never recover (task #158)

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under
the real next number at merge. Written on `fix/158-reinstall-credential`, after the wiring round put
a live service behind the app and end-to-end verification took the merged client through an app
deletion.

---

## The defect

**Delete the app, reinstall it, and the phone can never sync again.** Every item it sends is refused
with `forbidden` — *"That item belongs to a different device."* — and nothing the person can do from
inside the app changes that.

## The mechanism, which is a pairing nobody stored

Two facts, each correct on its own:

- **The Keychain survives app deletion on iOS.** `KeychainCredentialStore` holds the anonymous
  installation's device token, and deleting the app does not take it.
- **`app_state.device_uuid` does not survive.** D9's installation id lives in the SQLite database
  inside the app container, so deleting the app takes it, and `DataLayer.boot` mints a fresh one on
  the next launch — exactly as it is written to.

Together they produce a state neither of them describes: a credential minted for installation **A**,
presented by installation **B**. The service resolves the token to A's `devices` row; every item
names B; `applyOne` compares the two and refuses all of them.

Note what is *not* wrong. The token is live, well-formed, and accepted. The database is correct. The
registration was correct when it happened. Only the **pairing** between them is wrong, and nothing
in the client recorded a pairing to check — `DeviceCredential` stored `deviceToken` and `expiresAt`
and nothing else. The mismatch was not undetected; it was **inexpressible**.

## Why it never healed, which is what made it a blocker rather than a bug

Four independent reasons, and every one of them has to hold for the state to be permanent:

1. **The refusal is a per-item verdict inside a `200 OK`.** `POST /sync` answers a batch with one
   status per item, so a refused item is a field in a successful response.
2. **`SessionTransport` rotates on a 401 and there is no 401.** Refresh-and-replay (spec §5.8) is the
   client's whole answer to "the credential is wrong", and it is wired to a status code this failure
   never produces.
3. **`forbidden` is not retryable**, so `OutboxRetryPolicy` settles each item `.failed` on the first
   drain rather than leaving it on the 48 h backoff.
4. **The act that causes it is deleting the app** — the first thing anybody tries when something
   looks wrong, and the one action guaranteed to reproduce it.

The type's own header is where this reads most sharply. It said:

> It is **not an attestation**: a reinstall mints a new one and the server cannot tell the
> difference.

The second clause is true. The first is false — a reinstall mints a new one only if something told
it to, and nothing did. A confident comment describing the behaviour its author assumed.

## The fix

`DeviceCredential` carries the `device_uuid` it was minted for, and `AppSession
.storedDeviceCredential` reads a credential minted for another installation as **no credential at
all** — which routes it into the ordinary lazy registration and mints a fresh one through the
existing single-flight door. The check sits at the single door to the stored value rather than at its
two call sites, because both readers must agree what "this installation has a credential" means and a
rule stated twice can disagree with itself.

**The enabling change is a split, and it is the part worth remembering.** `DeviceCredential` was both
the wire shape (decoded off `POST /devices/register`) and the storage shape (encoded into the
Keychain). A type that is both cannot carry a field the wire does not send — so the missing field was
not an oversight, it was *unwritable* while the conflation stood. `DeviceRegistration` is now the
wire answer; `DeviceCredential` is what is stored; and `SessionCredentials.swift`'s header states the
persistence rule that only the storage half has: a non-optional key discards what is already stored,
which is right when the missing fact makes the stored value untrustworthy and wrong when it would
throw away a usable credential — because re-registering retires the previous token server-side.

No migration: the app is unreleased, and the discard-and-re-register path is the desired outcome for
a pre-pairing payload anyway.

## The control that killed the impostor fix

The obvious repair — re-register on every launch — passes the reinstall test and is its own defect:
`POST /devices/register` calls `RevokeDeviceTokens` on **every** call (`server/README.md`), so a
phone that re-registered per launch would retire the credential it was about to drain with. Every
launch would sign out the queue it was trying to send.

So the reinstall assertion ships with a control asserting the opposite case — a credential minted for
*this* installation is reused and **nothing** registers. Under the mutation that removes the pairing
check, the reinstall test goes red and the control stays green, which is what attributes the failure
to the check rather than to the fixture. Same discipline as `registersOnceAndReuses`, which is the
test that already existed for the same reason on the empty-store path.

Two smaller guards ride along: that the pairing survives encoding (a `deviceUUID` lost in the coder
would restore the defect while every in-process test still passed, because they hold one process),
and that a pre-pairing payload reads as absent.

**Four existing fixtures were seeding the Keychain with the wire payload.** Two went red under the
split. **Two stayed green while seeding nothing readable** — the rotation tests, which then silently
measured a path that begins with an empty store. A fixture that decodes to nothing is a test that has
quietly changed subject, and it is the reason the split's fallout was worth reading test by test
rather than fixing until the suite was green.

## Still open: the user arm

`AppSession.authorization()` consults `storedSession` **first** and returns `.user(…)` before it ever
reaches the device credential. So a reinstall on a phone whose Keychain still holds a live account
session takes a different branch, and the fix above does not touch it.

That branch does not have this defect — `applyOne`'s user arm accepts items carrying no `user_id`, so
nothing is refused and nothing is lost. It has a different one: the session survives while
`app_state.currentUserID` does not, and nothing re-hydrates it (`DataLayer.boot` reads `app_state`
and never consults `AppSession`). The result is an installation that shows itself as signed out while
its bearer is the account's and the service attributes the work to that account.

Whether a reinstall should restore the account from the surviving session or discard the session is a
**product question**, not an engineering one — an account is supposed to be portable, which is the
argument for restoring it, and a phone that silently resumes somebody's account after a delete-and-
reinstall is the argument against. It is recorded here rather than decided.

## The two screen 17 sentences, and why they are not in this entry's fix

The field verification saw *"This account is not allowed to send that."* on an anonymous
installation, and a `stopped` row under a footnote promising the item "waits for you" with no retry
affordance reachable. **Both were this defect's symptoms** and both are gone at the fixed head.

Neither sentence was changed, and neither could be without inventing copy:

- The forbidden sentence is the **client's own** (`OutboxFailureReason.sentence(for:)`), not the
  service's message — the service's `message` is never rendered. It assumes an account where D9 makes
  anonymous the normal case. `docs/distilled/SCREENS.md` names **no** per-code sentence for screen 17
  at all; the eight are engineer-authored against BUILD-PLAN §6's list of *codes*, which carries no
  copy.
- `stopped` is not a drawn state. SCREENS.md draws `waiting`, `retry` and `synced`; the app invented
  the fourth, and `OutboxPreviews` marks it "NOT SPECIFIED". Its lack of a retry control is argued in
  `OutboxView` — retrying a non-retryable code promises an outcome the taxonomy says will not change
  — and that argument is sound. What is unresolved is that SCREENS.md also says "a failure asks for a
  retry instead of vanishing", so the invented state sits against the mocks' own sentence.

Both are copy and design questions for the owner (DECISIONS constraint 21).
