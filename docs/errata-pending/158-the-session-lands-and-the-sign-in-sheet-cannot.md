# Unnumbered — #158 step 3 landed; steps 5 and 6 are blocked on two things this branch cannot supply

Staged unnumbered per CLAUDE.md, "Numbering and shared files". Written while building #158 step 3
(the session) on `feat/158-session-auth`. Three findings, and the first two are refutations of
premises this ticket was briefed on.

## 1. E124's "nothing on the call path changes" is false, in three specific ways

ERRATA **E124** closes with: *"When the magic-link service lands, `accountLink()` swaps its body for
the client half of the token exchange and nothing on the call path changes."* `BetaCapability` and
`Cypress/App/RootView.swift` both repeat it. The #158 spec §10 step 5 already flagged it as a claim
to check rather than assume; checked, it does not hold.

- **The closure is `nonisolated` and captures nothing of the view — deliberately.** Its own comment
  says so: it "captures only two `Sendable` values … so it carries nothing of the view across the
  boundary it will be called on." Sign in with Apple needs an `ASPresentationAnchor`, which is a
  `UIWindow`, which is `@MainActor` state the composition root has to reach. Either the closure stops
  being `nonisolated` or something new is threaded to it. Either is a change on the call path.
- **`AccountLinkRequest` cannot carry what the exchange needs.** It has two fields — provider and
  license consent — and `CypressTests/AccountAskSheetTests.swift` pins that shape *by reflection*, on
  purpose: it is DECISIONS §3.9's no-passwords rule made structural. The identity token, the
  authorization code and the raw nonce therefore cannot travel on it, so the closure must acquire
  them itself, from a dependency the composition root constructs and does not construct today.
- **A cancelled sign-in has no state.** `AccountAskModel.link` turns *any* thrown error into
  `Notice.failed` — "that did not go through". Somebody who opens Apple's sheet and taps Cancel has
  not had anything go wrong, and SCREENS.md 15 draws no state for it. That is a copy question
  (DECISIONS constraint 21), not an implementation detail, and it did not exist while the sign-in was
  local and could not be cancelled.

None of the three is hard. The point is that "nothing on the call path changes" is the sentence that
would let a reader skip looking, and all three are on the call path.

## 2. Sign in with Apple needs an entitlement this repository does not have, and cannot add

`ASAuthorizationAppleIDProvider` requires the `com.apple.developer.applesignin` entitlement and the
matching capability on the App ID. What is in the tree, checked rather than assumed:

- there is no `.entitlements` file anywhere in the repository;
- `Cypress.xcodeproj/project.pbxproj` sets no `CODE_SIGN_ENTITLEMENTS` for any of the four
  configurations — `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM` are the whole of the signing
  configuration;
- there is no `.xcconfig` anywhere, so there is no way to set that build setting without editing
  `project.pbxproj`, which ARCHITECTURE §2 forbids in as many words ("If you believe you need a
  project change, stop and ask").

So the client half of step 5 is written and tested (`Cypress/Data/Auth/AppSession.swift`'s
`signInWithApple`, `CypressTests/SessionTests.swift`), and the sheet that would feed it cannot
succeed on any build produced from this tree. `server/README.md` already names the other half of the
same gap — "an Apple `.p8` key with Sign in with Apple enabled, and the Service ID / key configured
in the Apple Developer account. Nothing in this repository can create one."

**Not measured here:** that `performRequests()` fails without the entitlement is Apple's documented
behavior, not something this branch ran. What *was* checked is the three bullets above.

## 3. Step 6 has no true copy to move to until the send sink exists, and step 5 makes the current copy false

Spec §10 step 6 deletes `BetaCapability.accountsAreLocalOnly` and moves screen 18's storage line "on
the same commit". Both replacement strings exist in the corpus, so nothing would have to be invented:
screen 15 falls back to `AccountAskCopy.body`, the drawn sentence, and
`Cypress/Features/Visit/VisitSaveLedger.swift`'s `storageLine` gains PROTOTYPE-FLOW §1.4's `linked`
arm, `Backed up to your account · joins the public timeline when signal returns.`

What is not true is the timing, and it is false in both directions:

- **Keeping the flag after step 5 is a lie.** `AccountAskCopy.bodyLocalAccount` says the account "is
  made on this phone, nothing is uploaded, and none of the services below has been contacted." After
  a real `POST /auth/oidc`, Apple has been contacted and the account exists on `cypress-sync`. That
  is ERRATA **E131**'s defect with the sign reversed.
- **Deleting it before the send sink is also a lie.** Both replacement strings promise a backup.
  Nothing is uploaded until the outbox has a send sink, which `DataLayer` deliberately does not wire
  — `CypressTests/OutboxApplySendSplitTests.swift` pins that it does not — and wiring it is a later
  step than either 5 or 6.

So steps 5 and 6 belong on the same landing as the send sink, not before it. This is recorded rather
than resolved: which copy screen 15 draws in an intermediate state is the owner's, under DECISIONS
constraint 21, and the honest answer may be that there is no intermediate state to draw.

## 4. A guard that was green with the thing it guards deleted

Not an erratum about the app, but the shape this project keeps finding. The single-flight refresh
test — two concurrent 401s must cost one refresh, because the service revokes a session family when a
refresh token is presented twice — **passed with the single-flight slot deleted**. Two `async let`s
over a double that never suspends simply ran one after the other, and the second read the first's
stored result. It only became a measurement once the double could hold one route's answer long enough
for the two callers to overlap. Found by red-proofing, which is the only reason it is not still
green.
