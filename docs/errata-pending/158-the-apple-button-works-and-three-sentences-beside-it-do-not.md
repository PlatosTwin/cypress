# Unnumbered — #158 step 5: the Apple button signs people in, and three drawn sentences around it stopped being true

Staged unnumbered per CLAUDE.md, "Numbering and shared files". Written while building #158 step 5
(screen 15's `Continue with Apple`) on `feat/158-siwa-button`. Everything below was checked against
the code, the seed, the deployed service or the running screen; nothing is inferred from prose.

It follows `158-the-session-lands-and-the-sign-in-sheet-cannot.md`, and §5 says which of that entry's
findings this round discharged and which it did not.

---

## 1. Two of the three findings this round produced are copy questions, and both are the owner's

Neither is invented an answer to here (DECISIONS constraint 21). Both are drawn on a phone today.

### 1a. `AccountAskCopy.noticeUnavailable` — screen 15

> *"Accounts are not ready yet. Everything you have saved stays on this phone."*

Written when no route on screen 15 worked, and true then. It is now the line drawn when somebody
taps **`Continue with Google`** or **`Use email`**, standing beside a `Continue with Apple` that
completes a real sign-in. *Accounts* are ready; that **route** is not. Spec §5.3 and RULINGS **R72**
ruling 2 both say those two buttons should present "the existing 'not yet' notice", so the behavior
is ruled — what is not ruled is that the existing notice's first sentence has aged out from under
it.

The alternative was leaving both buttons as they were, which is worse and is why the change was made
anyway: until this round they **minted a local account**. After #158's wiring round put a send sink
behind the outbox, that told somebody their work was backed up while no session existed to back it
up with — ERRATA **E131**'s defect with the sign reversed. A one-word imprecision replaced a
substantive false promise; it is still an imprecision.

### 1b. `AccountCopy.signedInBody` — screen 18, and the brief named this one in advance

> *"This account gathers what you save here under one name on this device. **Nothing is uploaded**,
> and nothing about you is public."*

The middle clause is false, in two independent ways, and neither of them is this round's doing
alone:

- `DataLayer.boot` wires the outbox's send sink over `RemoteAPI` whenever the remote gate allows
  network, so an **anonymous** installation's contributions already leave the phone. That landed in
  #158's wiring round, before this branch existed.
- After this round, a signed-in account is a row on `cypress-sync` with a session in the Keychain,
  and `photos.go` auto-approves a photograph from one where a device's stays `pending`.

The third clause still holds — `User.publicAttribution` cannot be turned on anywhere in the app
(ERRATA E100) — so "nothing about you is public" is true.

Left standing, deliberately. Screen 17/18 copy is the owner's, this round's brief names it as a
stop-and-ask by name, and it is the same open question PROTOTYPE-FLOW §1.4's storage line already
has: its three arms key on `account ∈ none | ask | linked | dismissed` and there is no arm for
*anonymous-and-sent*. What was done instead is that `AccountSection.swift`'s header and
`signedInBody`'s own doc comment now say the sentence is false and why — a comment nobody corrected
is how a false promise survives a review.

---

## 2. The cancel path had no drawn state, and silence is the only answer that invents nothing

New with this round: until it, screen 15's sign-in was local and could not be cancelled. With
Apple's sheet in front of the tap it can be, and `AccountAskModel.link` turned *every* throw into
`Notice.failed` — *"That did not go through."*

Three answers were available and two of them invent:

- **`.failed`** is a claim that something went wrong about somebody who dismissed a sheet. False.
- **A fourth sentence** is copy no mock draws (constraint 21).
- **Nothing** is what SCREENS.md 15 draws — the sheet, unchanged — and what a dismissed system sheet
  leaves behind in every other iOS app.

The third is what ships (`AccountLinkRefusal.cancelled`). Recorded here rather than merely done,
because it is the one place this feature answers a copy question by declining to write copy, and a
later reader should find the reasoning rather than an unexplained empty `catch`.

It is proved on a device as well as in a unit test, and the two assertions are deliberately opposite:
`AppleSignInUITests.testACancelledSheetLeavesScreenFifteenExactlyAsDrawn` asserts the sheet is intact
**and** that neither notice sentence is present, and
`testAFailedAuthorizationDrawsTheNoticeThatCancellingDoesNot` is its control — without it, a build
that drew no notice for any outcome would pass the first while swallowing every real failure.

---

## 3. Screen 15's `Continue with Apple` is not Apple's button, and that is an App Review question

SCREENS.md 15 §3 draws the control itself: fill `#1C2A21`, `#fff`, radius 14px, `padding:14px`,
15px/700, label `Continue with Apple`. It is built from tokens as `AccountProviderButton` and this
round did not change a pixel of it, because the brief and constraint 21 both say the button appears
as the mock draws it.

What is worth an owner's eye before submission: Apple's guidelines for Sign in with Apple ask that
the button use their supplied control or match their published design, and the mock's version
carries **no Apple mark**. The colour and the label are within Apple's own vocabulary — `Continue
with Apple` is one of the approved wordings, and black is one of the approved appearances — so the
gap is the glyph, not the styling.

Two things that are *not* the problem, checked rather than assumed:

- **R57 does not trip.** The drawn-glyph policy is about SF Symbols, and
  `DrawnGlyphGuardTests.BorrowedGlyphAPI.tokens` is `["systemName:", "systemImage:"]`. Nothing this
  round added spells either. The suite is green with `AppleSignIn.swift` in the target.
- **The entitlement is present.** `Cypress/Cypress.entitlements` carries
  `com.apple.developer.applesignin = [Default]` and both configurations set
  `CODE_SIGN_ENTITLEMENTS` (PR #82, now on main).

Not resolved here: swapping in `ASAuthorizationAppleIDButton` would change a drawn screen, which is
the owner's call, and doing it as a side effect of a sync-API round is the thing constraint 21
exists to stop.

---

## 4. Two smaller findings

**`LocalAPI.resumableUserID()` has no shipping caller any more.** It existed so that signing back in
did not mint a rival id beside the one this device signed out of. The id is the service's now — the
same Apple account resolves to the same `users` row through `apple_subject` — so resumption is
answered on the far side, and a value this device remembered could only disagree with it. It is not
deleted: `AccountDeletionTests` and `AccountSurfaceTests` read it to prove that a **deletion** leaves
nothing resumable, which is RULINGS R3's promise and unaffected. Its doc comment now says so.

**`DebugDeepLink.Screen`'s note on screen 15 was false.** It read that 15 is absent "because it is
not a `Route`… The harness drives `AppRouter`, which has no case that opens it."
`AppRouter.Route.accountAsk` has existed since ERRATA **E131** gave the You tab a way back in after a
sign-out. The comment outlived the route by a whole ticket. There is a `.accountAsk` case now.

Worth one line on *why* the deep link rather than the You tab's own `Sign in` row, which was the
first attempt: whether that row draws at all depends on whether this device is signed in, and
`DebugDeepLink`'s `.moderationReview` case **promotes the account**. A UI test taking that door reads
whichever run went before it — ERRATA **E216**'s family, arrived at from a direction E216 does not
cover.

---

## 5. What the earlier pending entry got right, and the two parts of it that are now discharged

`158-the-session-lands-and-the-sign-in-sheet-cannot.md` was written on `feat/158-session-auth`. Read
against this round:

- **§1 holds, all three bullets.** E124's *"nothing on the call path changes"* is false.
  `AccountLinkRequest` really could not carry the exchange, so the credential is acquired by a
  dependency the composition root now constructs (`AppleSignIn`); a cancelled sign-in really had no
  state, and §2 above is what it became. On the first bullet the entry offered a fork — *either* the
  closure stops being `nonisolated` *or* something new is threaded to it — and it is the second: the
  window is resolved inside `AppleSignInController` at presentation time, so `accountLink()` stays
  `nonisolated` and still carries nothing of the view.
- **§2 is discharged.** "Sign in with Apple needs an entitlement this repository does not have, and
  cannot add" was true when written and is not now: the owner added the capability in Xcode and PR
  #82 carries the `.entitlements` file and `CODE_SIGN_ENTITLEMENTS` in both configurations.
- **§3 is half discharged and half open.** Its timing argument — that steps 5 and 6 belong on the
  same landing as the send sink — was taken: the wiring round landed the sink and deleted
  `BetaCapability.accountsAreLocalOnly`, so **step 6 was already done before this branch started**
  and this round is step 5 alone. What it did not anticipate is that finishing the sequence in that
  order leaves screen 18's line false in the *other* direction, which is §1b above.
- **One citation in it is wrong**, already noted in PR #77's review and repeated here so it is fixed
  at splice time: the reflection pin on `AccountLinkRequest` is
  `CypressTests/AccountAskSheetTests.swift`, not `AccountAskTests.swift`.

---

## 6. What was measured against the live service, and what was created there

`POST https://cypress-sync.fly.dev/api/v1/auth/oidc`, twice, with obviously fake tokens. Recorded
because the client's own fixtures assert these exact envelopes decode:

```
{"identity_token":"obviously.fake.token","authorization_code":"obviously-fake-code","nonce":"obviously-fake-nonce"}
  → HTTP 401 {"error":{"code":"unauthorized","message":"That sign-in could not be verified.","retryable":false}}

{"identity_token":"obviously.fake.token"}
  → HTTP 400 {"error":{"code":"validation_failed","message":"That sign-in was incomplete. Please try signing in again.","retryable":false}}
```

Both are the contract behaving correctly — Apple verification failing on a fake token is the expected
result, not a defect — and both refuse before any write. **Nothing was created on the production
database by this branch: no `users` row, no `devices` row, no session, no `device_uuid` and no
`client_uuid`.** The residue list for this round is empty.

The real end-to-end tap remains the owner's, on a device, after merge. No test in this repository
uses an Apple credential, and `DebugAppleSignInOverride` has no value that pins a *success* precisely
so that no mutated build can reach the service — asserted by a test rather than written down as a
rule.
