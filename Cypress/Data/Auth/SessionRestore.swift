//
//  SessionRestore.swift
//  Cypress — Data/Auth
//
//  What a launch does when the Keychain and the database disagree about who is signed in.
//
//  ── The state this exists for ──────────────────────────────────────────────────────────────────
//
//  **On iOS the Keychain survives app deletion; the database does not.** That one sentence produces
//  two different defects, and this file is the second one. `DeviceCredential`'s header has the first:
//  an anonymous installation's device token outlives the `app_state.device_uuid` it was minted for,
//  the phone authenticates as the old `devices` row, and every item it sends is refused forever. That
//  arm is closed at `AppSession.storedDeviceCredential`.
//
//  The account arm is not that defect and it is not fixed by that fix. `AppSession.authorization()`
//  consults `storedSession` **first**, so a reinstall on a phone holding a live account session never
//  reaches the device credential at all. Nothing is refused and nothing is lost — `applyOne`'s user
//  arm accepts an item carrying no `user_id` (`server/internal/api/sync.go`). What goes wrong is
//  quieter: `app_state.current_user_id` was in the database and is gone, so the app draws itself as
//  signed out **while every request it makes goes out with the account's bearer** and the service
//  attributes the work to that account. The person is signed in on the wire and signed out on the
//  screen.
//
//  ── The ruling ────────────────────────────────────────────────────────────────────────────────
//
//  The project owner ruled (2026-08-14, ruling 5) that a surviving signed-in session **restores,
//  silently**: the app boots signed in and the local account state is rebuilt. The
//  recommendation on the table was the opposite — discard the session — and it was not taken.
//
//  **This deliberately diverges from the device arm's ruling, and the divergence is the point.**
//  PR #81 settled that a surviving *device* credential reads as no credential at all, because a
//  device credential is per-installation: it is a fact about a copy of the app, and a copy of the app
//  that has been deleted has no facts left. An account session is not per-installation. It is the
//  person's, an account is supposed to be portable, and the same Apple identity signing in again
//  would resolve to the same `users` row through `apple_subject` anyway
//  (`server/internal/store/identity.go`). So the two arms answer the same question — "what does a
//  surviving Keychain item mean after a reinstall?" — with opposite answers, on purpose, because the
//  item means a different thing in each.
//
//  ── What "rebuilt from the server" turns out to mean, measured rather than assumed ──────────────
//
//  Very little travels, and that is a finding rather than a shortcut. Taking the local account state
//  a signed-in installation holds, one field at a time:
//
//  - **`current_user_id`** — the account id. It is *in the session*: `SessionCredentials.userID` is
//    the id `POST /auth/oidc` minted, stored in the Keychain beside the tokens. The one fact the
//    restore actually needs is the one fact that survived, so the restore needs **no round trip** and
//    reaches no network. That matters beyond tidiness: `AppSession.bootstrap()`'s header rules that a
//    launch must not reach the network, and a restore that had to would have been a launch-time
//    request for somebody who only wanted to look at a map.
//  - **the grove, the known species, the favorites, the map membership** — already live. `RoutedAPI`
//    joins `GET /me/grove`, `/me/grove/species`, `/me/grove/{id}/favorite` and `/me/map-membership`
//    onto the phone's own answer on **every** read (spec §4.3, R36). There is nothing to rebuild into
//    the database because these were never read out of it alone; the moment the app knows it is
//    signed in, those four surfaces answer with the account's rows.
//  - **`current_user_role`** — no route on this service returns it. It reads back as `.member`
//    (`AppStateKey.currentUserRole`: "absent means member"), which is the ground state and the safe
//    direction: a role is authority, and inventing one from a reinstall would grant it.
//  - **`account_provider` and `account_license_version`** — no route returns these either. They are
//    left **unwritten**, which is not a gap being papered over: `AccountLinkRecord`'s header already
//    names this exact shape — "a missing `provider` is an account claimed by something other than
//    screen 15" — and `AccountCopy.licenseLine(for:)` already returns nil for it, so the You tab
//    draws no license line rather than a wrong one. Writing `LicenseConsent.currentVersion` here
//    would be this app claiming somebody agreed to a license on the strength of a reinstall.
//
//    That is also the whole of the answer to DECISIONS constraint 21 for this round: **the restored
//    state needs no drawn state of its own.** It is the signed-in You tab, minus a line the mocks
//    already allow to be absent. No spinner, no partial-data state, nothing invented — and nothing
//    to invent one for, because the restore is synchronous, offline and finished before the first
//    frame.
//  - **the journal, and the photographs** — not rebuildable, and not faked. `RemoteAPI.journal`
//    throws `communityHalfOnly` because the service does not send the summary prose the rows draw,
//    and `RoutedAPI` routes the journal local and says so. A restored install's journal is empty
//    because its contributions are, which is the truth about that database.
//
//  So the restore is the **local half of a sign-in that already happened**, and it is performed with
//  the same verb: `LocalAPI.claimDevice`, which is what `linkAccount` calls and exactly the subset of
//  it that is knowable here.
//
//  ── Why this is a mirror and not a migration ──────────────────────────────────────────────────
//
//  The rule is stated as an equality rather than as a one-way repair:
//
//      **`app_state.current_user_id` mirrors the Keychain session, and the session is the
//      authority.**
//
//  Both directions are load-bearing. The forward direction is the restore. The reverse direction is
//  the refusal path: when the service refuses a surviving session — a revoked family, a deleted
//  account, sixty days without a launch — `AppSession` already discards it
//  (`performMint`'s `.user` arm removes the stored session on `unauthorized` or `forbidden`, and
//  `authorization()` removes one whose refresh token has expired). Without the reverse direction the
//  local half would stand there naming an account with no credential behind it, which is the same
//  defect as the forward one with the halves swapped.
//
//  An equality also answers the resumability question **by construction**, which is the reason it is
//  written this way rather than as a sequence of steps with a "restore in progress" flag. There is no
//  such flag and no new `AppStateKey`. Every launch reads both halves and applies whichever act makes
//  them agree; a launch killed halfway through leaves a state the next launch reads and converges
//  from. Nothing is half-applied that a re-read cannot see, because the only thing recorded is the
//  answer itself. A flag would have been a third fact that could disagree with the two it was about.
//

import Foundation

/// What a launch must do to make the database agree with the Keychain about who is signed in.
///
/// Deliberately a value with no I/O in it, so the rule can be tested without a store, a Keychain or a
/// network, and so the four arms are enumerable rather than buried in `DataLayer.boot`'s straight
/// line. `SessionRestore.reconcile` is the only thing that produces one.
public enum AccountReconciliation: Equatable, Sendable {

    /// The two halves already agree — including the ordinary case where both say nobody.
    case unchanged

    /// The session names an account the database does not. Sign in locally, as that account.
    ///
    /// This is the reinstall the ruling is about. It also covers the case where the database names a
    /// *different* account, which see `SessionRestore.reconcile`.
    case restore(userID: UUID)

    /// This installation is to stop acting as this account: **both halves of it.**
    ///
    /// Two states reach here. The database names an account and no live session is left — sixty days
    /// without a launch, or a refusal the session layer already acted on. Or the database names
    /// nobody, a session survives, and `signed_out_user_id` says the person left that very account on
    /// purpose (see `SessionRestore.reconcile`); the second is why this act drops the *session* as
    /// well as the local half, and not only for tidiness — a session left standing is the bearer
    /// every later request goes out with.
    ///
    /// Not a deletion: `LocalAPI.signOut()` keeps every row the account wrote and remembers the id
    /// under `AppStateKey.signedOutUserID`, which is what "signing out is not a quiet, unlabeled
    /// deletion" means one layer down.
    case endSignedOut(userID: UUID)
}

/// The mirror rule, in one place.
///
/// A caseless enum rather than a type with state: there is nothing to hold. The inputs are read by
/// `DataLayer.boot` from the two places that own them and handed here, so this function can be
/// exercised over every pairing of the two halves — which is what
/// `CypressTests/SessionRestoreTests.swift` does.
public enum SessionRestore {

    /// Which act makes the two halves agree.
    ///
    /// - Parameters:
    ///   - storedUserID: `app_state.current_user_id`, the database's half.
    ///   - signedOutUserID: `app_state.signed_out_user_id` — the account somebody **left on
    ///     purpose**. See the discriminator section below; it is read only when `storedUserID` is
    ///     nil.
    ///   - sessionUserID: `AppSession.signedInUserID`, the Keychain's half. **Already liveness-tested
    ///     by that property**, so a session whose refresh token has expired arrives here as nil and
    ///     is answered `.endSignedOut` — which is the same verdict `authorization()` reaches on the
    ///     same session, arrived at from the other side.
    ///
    /// ── The discriminator, and the population it exists for (review of this PR, F1) ─────────────
    ///
    /// "No local account beside a live session" is **not** only the reinstall this ruling is about.
    /// It is also what the *shipping* build leaves on every device whose owner tapped `Sign out`:
    /// before this round `AccountModel.signOut()` called `LocalAPI.signOut()` alone, which clears
    /// `current_user_id` and leaves the Keychain untouched (the errata entry
    /// `session-restore-the-sign-out-that-kept-the-credential.md` is that defect). Those installs do
    /// not need to be reinstalled to reach this function — they reach it on the **first launch after
    /// the update**, and a rule reading only two inputs restores them: the person is silently signed
    /// back into the account they deliberately left.
    ///
    /// The reviewer staged exactly that path and measured it, including the part that makes it
    /// unrecoverable — `claimDevice` clears `signed_out_user_id` on its way past, so the evidence of
    /// the deliberate sign-out is destroyed by the act that ignores it.
    ///
    /// So the marker is read. `signed_out_user_id == sessionUserID` means *this person left this
    /// account on purpose*, and the answer is `.endSignedOut`, which takes the session with it. It is
    /// not a new key and not a progress flag: it is a fact `LocalAPI.signOut()` already writes, for
    /// its own stated reason, and this is the second reader of it.
    ///
    /// **It is consulted only when `storedUserID` is nil, and that is the marker's own meaning rather
    /// than a convenience.** `AppStateKey.signedOutUserID` is "the account this device was signed in
    /// as *before somebody signed out*", and `LocalAPI.resumableUserID()` already guards on exactly
    /// this — "the question only means anything when there is no current account". A marker consulted
    /// beside a live local account would be answering a question nobody asked.
    ///
    /// ── The mismatch arm, which should be unreachable and is written closed anyway ──────────────
    ///
    /// `storedUserID` and `sessionUserID` both present and **different** is a state nothing in this
    /// app produces: the two halves are written together at sign-in (`RootView.accountLink()`, whose
    /// F4 rollback exists precisely so a failure cannot leave one without the other) and cleared
    /// together at sign-out. It is answered `.restore(sessionUserID)` rather than left alone, on the
    /// authority stated in this file's header: the session is the credential every request already
    /// goes out with, so it is the original and the `app_state` row is the copy. Failing the other
    /// way — keeping the local id — would draw one account while sending as another, which is the
    /// exact disagreement `AppSession.signInWithApple`'s return value exists to prevent.
    ///
    /// The alternative reading of an unreachable arm is "do nothing", and doing nothing here means
    /// the two halves stay in disagreement for the life of the install. `applyOne`'s nil-`DeviceUUID`
    /// branch is the same shape and settled the same way: an unreachable arm is still written to fail
    /// in the safe direction.
    public static func reconcile(
        storedUserID: UUID?,
        signedOutUserID: UUID?,
        sessionUserID: UUID?
    ) -> AccountReconciliation {
        switch (storedUserID, sessionUserID) {
        case (nil, nil):
            return .unchanged
        case let (nil, .some(session)):
            // The discriminator. A session for the account this device recorded itself as having
            // left is a session that outlived a deliberate act, not one that outlived a reinstall.
            return signedOutUserID == session ? .endSignedOut(userID: session) : .restore(userID: session)
        case let (.some(stored), nil):
            return .endSignedOut(userID: stored)
        case let (.some(stored), .some(session)):
            return stored == session ? .unchanged : .restore(userID: session)
        }
    }
}
