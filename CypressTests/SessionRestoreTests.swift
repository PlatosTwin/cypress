//
//  SessionRestoreTests.swift
//  CypressTests
//
//  Owner ruling 5 of 2026-08-14, and the mirror rule it turned into. What these tests are about, in
//  one sentence:
//
//      **the Keychain and the database must not disagree about who is signed in, in either
//      direction.**
//
//  ── How a reinstall is staged here, and why that staging is the honest one ──────────────────────
//
//  Deleting an app on iOS takes the container — the SQLite database with it — and leaves the
//  Keychain. So a reinstall is staged as **a new database directory beside a credential store that
//  was carried over**, which is exactly what the device does. Nothing here mocks a reinstall; it
//  reproduces the pairing that makes one interesting. `InMemoryCredentialStore` stands in for the
//  Keychain, and `DataLayer.boot(credentials:)` exists so it can: seeding the *real* login Keychain
//  from a test would leave an item behind that a later run on the same machine would read as a
//  signed-in account.
//
//  ── What is deliberately not tested here, because it cannot be tested honestly ──────────────────
//
//  There is no UI-test coverage of the restore and there is no seam that would allow one.
//  `DebugAppleSignInOverride` has **no `success`** on purpose — "none of them mints a credential" —
//  so no launch environment can put a session on a simulator's Keychain, and adding one would be
//  building the seam that file was written to refuse. The composition root is therefore proved here,
//  over `DataLayer.boot` itself, which is the same standard `DataLayerWiringTests` sets: one omitted
//  argument in `boot` is the whole of the difference, and no test that assembles its own layer can
//  see it.
//

import Foundation
import Testing
@testable import Cypress

// MARK: - Fixtures

/// The two ids and the one clock every test here shares.
///
/// A file-scope enum for `AppleSignInFixture`'s reason: the suites below are `@MainActor`, so their
/// statics would be too, and these are read from inside `@Sendable` closures.
private enum RestoreFixture {

    /// The account `POST /auth/oidc` minted. Unlike anything a device could produce, so an assertion
    /// that the local half carries it cannot pass by coincidence.
    static let accountID = UUID(uuidString: "5E12E12E-0000-4000-8000-00000000FE02")!

    /// A second account, for the arm where the two halves name different people.
    static let otherAccountID = UUID(uuidString: "5E12E12E-0000-4000-8000-00000000FE03")!

    /// A capture time for the contributions these tests write. It is only ever a column value.
    static let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// A stored session, written into a credential store the way `AppSession.persist` writes one.
    ///
    /// `refreshLifetime` is a parameter because the refusal arm needs a session whose refresh token
    /// has expired — the state `AppSession.authorization()` discards on sight and `signedInUserID`
    /// reports as nobody.
    ///
    /// **Both lifetimes are relative to `Date()`, and that is not a detail.** `DataLayer.boot`
    /// constructs its `AppSession` with the shipping clock and there is no seam to pin it, so a
    /// fixture anchored to a fixed instant measures its expiries against the wrong now. The first cut
    /// of this file anchored them to `capturedAt` above — a date in **2027** — so a session written
    /// as "expired one second ago" was live for another five months, and the two refusal tests failed
    /// reporting the app had not signed anybody out. The app was right and the fixture was wrong;
    /// this comment is here because that failure reads exactly like a defect in the code under test.
    static func seedSession(
        _ credentials: InMemoryCredentialStore,
        userID: UUID = accountID,
        accessLifetime: TimeInterval = 15 * 60,
        refreshLifetime: TimeInterval = 60 * 24 * 60 * 60
    ) throws {
        let now = Date()
        let session = SessionCredentials(
            accessToken: "access-restored",
            refreshToken: "refresh-restored",
            expiresAt: now.addingTimeInterval(accessLifetime),
            refreshExpiresAt: now.addingTimeInterval(refreshLifetime),
            userID: userID
        )
        try credentials.setData(try AuthCoding.encoder.encode(session), forKey: CredentialKey.session)
    }

    /// A database directory per install. Not removed on the way out, for `DataLayerWiringTests`'
    /// stated reason: `DataLayer` holds the SQLite connection past the test's scope, and unlinking
    /// the file under an open handle prints `vnode unlinked while in use`.
    static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-session-restore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// `DataLayer.boot`, with the network scripted and the Keychain supplied.
    ///
    /// `seedURL: nil` — none of this is about the city inventory. `baseURL` is `.invalid` so that a
    /// request escaping the scripted wire could not reach anything, which is belt beside the braces
    /// of `remoteAccess: .disabled`.
    static func boot(
        databaseURL: URL,
        credentials: InMemoryCredentialStore,
        http: ScriptedAuthHTTP
    ) async throws -> DataLayer {
        try await DataLayer.boot(
            databaseURL: databaseURL,
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            authHTTP: http,
            remoteAccess: .disabled,
            credentials: credentials
        )
    }

    /// A far side that answers nothing. Every test that uses it also asserts it was never called.
    static func silentHTTP() -> ScriptedAuthHTTP {
        ScriptedAuthHTTP { _ in (500, Data("{}".utf8)) }
    }
}

// MARK: - 1. The rule itself

/// `SessionRestore.reconcile` over every pairing of the two halves.
///
/// A value with no I/O in it, so the arms are enumerable rather than inferred from behavior. The
/// suites below prove that `DataLayer.boot` *acts* on this answer; this one proves the answer.
@Suite("The account mirror rule")
struct SessionReconcileTests {

    @Test("both halves empty is the ordinary anonymous launch and changes nothing")
    func neitherHalf() {
        #expect(SessionRestore.reconcile(storedUserID: nil, signedOutUserID: nil, sessionUserID: nil) == .unchanged)
    }

    @Test("a session with no local account restores it")
    func sessionOnly() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: nil,
                signedOutUserID: nil,
                sessionUserID: RestoreFixture.accountID
            )
                == .restore(userID: RestoreFixture.accountID)
        )
    }

    @Test("a local account with no session ends signed out")
    func storedOnly() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: RestoreFixture.accountID,
                signedOutUserID: nil,
                sessionUserID: nil
            )
                == .endSignedOut(userID: RestoreFixture.accountID)
        )
    }

    @Test("two halves naming the same account change nothing")
    func agreement() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: RestoreFixture.accountID,
                signedOutUserID: nil,
                sessionUserID: RestoreFixture.accountID
            ) == .unchanged
        )
    }

    /// **The upgrade population** (review of this PR, F1). A session that outlived a *deliberate*
    /// sign-out is not a session that outlived a reinstall, and the difference is a fact the app
    /// already wrote.
    @Test("a session for the account this device recorded leaving ends signed out, not restored")
    func aDeliberateSignOutIsRespected() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: nil,
                signedOutUserID: RestoreFixture.accountID,
                sessionUserID: RestoreFixture.accountID
            ) == .endSignedOut(userID: RestoreFixture.accountID),
            """
            the rule restored an account this device had recorded itself as having left. That is the \
            state the shipping build leaves on every install whose owner tapped Sign out, so this is \
            not a reinstall being read wrong — it is the first launch after the update, undoing a \
            deliberate act.
            """
        )
    }

    /// The control that keeps the discriminator from swallowing the ruling: a marker naming somebody
    /// *else* is not this session's departure, and the reinstall still restores.
    @Test("a signed-out marker for a different account does not block the restore")
    func aMarkerForAnotherAccountDoesNotBlockTheRestore() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: nil,
                signedOutUserID: RestoreFixture.otherAccountID,
                sessionUserID: RestoreFixture.accountID
            ) == .restore(userID: RestoreFixture.accountID),
            "a departure from one account was read as a departure from another, and the ruling lost"
        )
    }

    /// The marker speaks only when the database names nobody — `LocalAPI.resumableUserID()`'s own
    /// guard, and this is the second reader to honor it.
    @Test("a stale signed-out marker beside a live local account is not consulted")
    func aStaleMarkerBesideALiveAccountIsIgnored() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: RestoreFixture.accountID,
                signedOutUserID: RestoreFixture.accountID,
                sessionUserID: RestoreFixture.accountID
            ) == .unchanged,
            "a leftover marker signed out an account that is currently, actively signed in"
        )
    }

    /// The unreachable arm, written closed. See `reconcile`'s own documentation for why it fails
    /// toward the session rather than toward the database.
    @Test("two halves naming different accounts follow the session, which is the credential in use")
    func disagreement() {
        #expect(
            SessionRestore.reconcile(
                storedUserID: RestoreFixture.accountID,
                signedOutUserID: nil,
                sessionUserID: RestoreFixture.otherAccountID
            ) == .restore(userID: RestoreFixture.otherAccountID),
            """
            the reconciliation kept the database's account while the session named another. Every \
            request this app makes goes out with the session's bearer, so that draws one account and \
            sends as a different one.
            """
        )
    }
}

// MARK: - 2. The restore, through the real composition root

@MainActor
@Suite("Reinstall restores the surviving session")
struct SessionRestoreBootTests {

    /// The ruling, end to end: delete the app, reinstall it, and the person is signed in.
    ///
    /// The first install is booted for real and signed in through `app_state`, so the "before" state
    /// is one this app actually produces. The reinstall is a **new database directory** beside the
    /// **same credential store** — the pairing an app deletion leaves on the device.
    @Test("a reinstall with a surviving session boots signed in, without reaching the network")
    func reinstallRestores() async throws {
        let credentials = InMemoryCredentialStore()
        try RestoreFixture.seedSession(credentials)
        let http = RestoreFixture.silentHTTP()

        let reinstalled = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: http
        )

        let signedInAs = await reinstalled.local.userID
        #expect(
            signedInAs == RestoreFixture.accountID,
            """
            the reinstalled app booted as \(signedInAs?.uuidString ?? "nobody") rather than as the \
            account its surviving session belongs to. Every request it makes already goes out with \
            that account's bearer, so a signed-out screen over it is the app disagreeing with its \
            own wire.
            """
        )

        // Persisted, not only held in memory: the next launch reads `app_state` and must not need
        // the session a second time.
        let persisted = try await reinstalled.store.appState(.currentUserID)
        #expect(persisted == RestoreFixture.accountID.uuidString, "the restore never reached app_state")

        // What a contribution written right now would be attributed to — the reason the restore
        // matters at all, rather than a flag being observed.
        #expect(
            await reinstalled.local.attribution == Attribution(
                userID: RestoreFixture.accountID,
                deviceID: reinstalled.deviceID
            ),
            "a contribution written after the restore would still be attributed to the installation"
        )

        // **The launch reached no network.** `AppSession.bootstrap()` rules that a launch must not,
        // and the restore is written to need nothing the Keychain does not already hold. A boot that
        // dialled out would break that rule for every launch, not just this one.
        //
        // **What red-proving this assertion turned up, because it is worth knowing before trusting
        // it.** Two plausible mutations — a `bootstrap()` and a `reauthorize(after: .user(…))` added
        // to the restore — left it *green*, and correctly: `AppSession.authorization()` returns the
        // live stored access token without a round trip, and `mint`'s `stored(_:otherThan:)` branch
        // returns the same token to a caller holding a different one. So this assertion does not
        // catch every added call; it catches every added call that actually reaches the wire, which
        // is the property it names. `reauthorize(after: .device(…))` does reach it, and under that
        // mutation this line reports `…/devices/register`.
        let calls = await http.requests
        #expect(
            calls.isEmpty,
            "the restore made \(calls.count) request(s) at launch: \(calls.compactMap { $0.url?.path })"
        )
    }

    /// **What the restore may not invent** (DECISIONS constraint 21, and `AccountLinkRecord`).
    ///
    /// No route on this service reports a role, a provider or a license consent, so none of the three
    /// is written. The assertions are about what the You tab then *draws*, not about the table: a
    /// missing provider is a shape `AccountSection.licenseLine(for:)` already answers with nil, so
    /// the restored state needs no drawn state of its own and none is added.
    @Test("a restore writes no role, no provider and no consent it cannot know")
    func theRestoreInventsNothing() async throws {
        let credentials = InMemoryCredentialStore()
        try RestoreFixture.seedSession(credentials)

        let data = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )

        let record = try await data.local.accountLink()
        #expect(record != nil, "the restored account read back as no account at all")
        #expect(
            record?.provider == nil,
            """
            the restore claimed the account was linked through screen 15's \
            \(record?.provider ?? "?") button. Nothing on this device or this service records which \
            route the original sign-in took.
            """
        )
        #expect(
            record?.licenseVersion == nil,
            """
            the restore recorded a license consent nobody gave on this install. The service has no \
            route that reports one, so this is the app asserting an agreement on the strength of a \
            reinstall.
            """
        )
        #expect(
            AccountCopy.licenseLine(for: record) == nil,
            "the You tab drew a license sentence about a consent the restore could not know"
        )
        #expect(
            await data.local.userRole == .member,
            "the restore granted a role. A role is authority, and no route on this service reports one."
        )

        // The account is nonetheless drawn as signed in, which is the whole of what the ruling asks
        // the screen to do differently.
        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        #expect(account.isSignedIn, "the You tab drew a signed-out account over a restored session")
    }

    /// The device's own contributions come across, which is why the restore is performed with
    /// `claimDevice` rather than by writing the id.
    ///
    /// The window this covers is real: an install can be opened, used anonymously and only then reach
    /// its first boot with the session read — or a restore can be interrupted (see the resumption
    /// suite) leaving rows written under the installation. Either way the account gathers them, on
    /// exactly the terms D9 promises.
    @Test("a restore sweeps this installation's unattributed work onto the account")
    func theRestoreSweepsTheDeviceRows() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()

        // A first launch of the reinstalled app, before the session was ever read: anonymous.
        let anonymous = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: InMemoryCredentialStore(),
            http: RestoreFixture.silentHTTP()
        )
        #expect(await anonymous.local.userID == nil, "the control install was not anonymous")
        let tree = try await anonymous.local.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-session-restore.jpg",
            attribution: .anonymous(deviceID: anonymous.deviceID)
        ))
        _ = try await anonymous.outbox.enqueue(.visit(Visit(
            treeID: tree.id,
            attribution: .anonymous(deviceID: anonymous.deviceID),
            note: "written before the session was read",
            capturedAt: RestoreFixture.capturedAt
        )))
        _ = try await anonymous.outbox.drain()

        // The session arrives — the same database, now beside a carried-over credential store.
        try RestoreFixture.seedSession(credentials)
        let restored = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await restored.local.userID == RestoreFixture.accountID)

        let owner = try await restored.store.queue.read { connection -> String? in
            let statement = try connection.prepare("SELECT user_id FROM visits")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.stringIfPresent("user_id") }.first ?? nil
        }
        #expect(
            owner == RestoreFixture.accountID.uuidString,
            """
            the visit stayed the installation's after the restore. The restore is the local half of a \
            sign-in, and the half that moves the work across is the half D9's "keep your three \
            visits" is about.
            """
        )
    }
}

// MARK: - 3. The refusal

@MainActor
@Suite("A refused session ends signed out")
struct SessionRefusalTests {

    /// Sixty days without a launch: the refresh family has expired and there is nothing to rotate.
    ///
    /// No network is involved and none should be — the expiry is readable off the stored session, and
    /// `AppSession.authorization()` reaches the same verdict from the same fact. What this asserts is
    /// that the *local* half follows, which is the direction that had nothing behind it.
    @Test("an expired refresh family ends the local account, and the launch still succeeds")
    func expiredFamilyEndsSignedOut() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()

        // A signed-in install, made by the restore itself so the "before" state is one this code
        // really produces.
        try RestoreFixture.seedSession(credentials)
        let signedIn = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await signedIn.local.userID == RestoreFixture.accountID, "the fixture never signed in")

        // Sixty days pass. The stored session's refresh token is now behind us.
        try RestoreFixture.seedSession(credentials, accessLifetime: -1, refreshLifetime: -1)

        let relaunched = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(
            await relaunched.local.userID == nil,
            """
            the app booted signed in on a session it can no longer refresh. The next request rotates, \
            fails, and signs them out mid-use — which is the error theater on the screen that this \
            boot is supposed to make unnecessary.
            """
        )
        #expect(try await relaunched.store.appState(.currentUserID) == nil)

        // Signed out, not deleted. The id is remembered and the rows are untouched, which is
        // `LocalAPI.signOut()`'s whole distinction from `deleteAccount`.
        #expect(
            try await relaunched.local.resumableUserID() == RestoreFixture.accountID,
            "ending signed out stranded the account's rows instead of remembering the id (RULINGS R3)"
        )
    }

    /// The service refuses the surviving session — a revoked family, or an account that was deleted
    /// elsewhere. The refusal arrives at the first request that needs a token, not at boot.
    ///
    /// Two halves, in the order the device meets them. `AppSession` discards the session on
    /// `unauthorized` (it already did; that is `SessionTests`' subject and is re-read here only as the
    /// precondition for the second half). The **next launch** is this suite's subject: it must end
    /// signed out rather than draw an account with no credential left behind it.
    @Test("a service that refuses the session leaves the next launch signed out, silently")
    func aRefusedRefreshEndsSignedOut() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()

        // The access token is already dead, so the very first authorization attempt must refresh.
        try RestoreFixture.seedSession(credentials, accessLifetime: -1)
        let refusing = ScriptedAuthHTTP { _ in
            (401, ScriptedAuthHTTP.refusal("unauthorized", "Your session has expired."))
        }

        let signedIn = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: refusing
        )
        #expect(await signedIn.local.userID == RestoreFixture.accountID, "the restore never happened")

        // The first request that needs a credential. `.refreshFailed` is the taxonomy; what matters
        // here is the side effect it carries.
        await #expect(throws: SessionError.refreshFailed) {
            _ = try await signedIn.session.authorization()
        }
        #expect(
            await signedIn.session.storedSession == nil,
            "the refused session was kept, so this test's second half would prove nothing"
        )

        let relaunched = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: refusing
        )
        #expect(
            await relaunched.local.userID == nil,
            """
            the app booted signed in with no session behind it. Every account-scoped read then falls \
            back to a phone that holds none of the account's rows, and the screen says that is what \
            the person has.
            """
        )
    }
}

// MARK: - 4. Resumption

@MainActor
@Suite("An interrupted restore is finished by the next launch")
struct SessionRestoreResumptionTests {

    /// The half state a launch killed mid-restore leaves, staged exactly.
    ///
    /// `LocalAPI.claimDevice` sweeps the rows first and writes `app_state.current_user_id` second, so
    /// the reachable interruption is **rows already the account's, database still saying nobody**.
    /// That is what is built here, by hand, and then booted.
    ///
    /// The assertion is convergence rather than repair: nothing recorded the restore as being in
    /// progress, so nothing has to be found and resumed. The next launch reads the same two halves
    /// and reaches the same verdict.
    @Test("a launch killed between the sweep and the write finishes the restore next time")
    func anInterruptedRestoreConverges() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()

        // Reach the half state through the real code: restore once, then remove only the row a
        // crash before `setAppState` would have left unwritten.
        try RestoreFixture.seedSession(credentials)
        let interrupted = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await interrupted.local.userID == RestoreFixture.accountID, "the fixture never restored")
        try await interrupted.store.clearAppState(.currentUserID)

        // Calibration: the half state really is half. Without this the boot below could be asserting
        // convergence from a state that never needed any.
        #expect(
            try await interrupted.store.appState(.currentUserID) == nil,
            "the half state was not staged, so the launch below converges from nowhere"
        )

        let resumed = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(
            await resumed.local.userID == RestoreFixture.accountID,
            """
            a launch interrupted mid-restore left the account half-written and the next launch did \
            not finish it. The reconciliation is an equality precisely so that no launch has to \
            remember what a previous one was doing.
            """
        )
        #expect(try await resumed.store.appState(.currentUserID) == RestoreFixture.accountID.uuidString)
    }

    /// Booting the restored install again changes nothing.
    ///
    /// Idempotence is what makes "kill it anywhere" safe, and it is asserted against the rows rather
    /// than against the flag: a second sweep that re-adopted or re-dated anything would be a restore
    /// that costs something every launch.
    @Test("relaunching a restored install is a no-op, rows included")
    func relaunchingChangesNothing() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        try RestoreFixture.seedSession(credentials)

        let first = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        let tree = try await first.local.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-session-restore-idempotent.jpg",
            attribution: first.local.attribution
        ))
        _ = try await first.outbox.enqueue(.visit(Visit(
            treeID: tree.id,
            attribution: await first.local.attribution,
            note: "after the restore",
            capturedAt: RestoreFixture.capturedAt
        )))
        _ = try await first.outbox.drain()

        let before = try await Self.visitOwnership(first.store)
        #expect(!before.isEmpty, "no visit was written, so the comparison below compares nothing")

        let second = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await second.local.userID == RestoreFixture.accountID)
        #expect(
            try await Self.visitOwnership(second.store) == before,
            "a relaunch of a restored install rewrote the ownership of rows that were already correct"
        )
    }

    /// `(user_id, device_id, updated_at)` per visit, in a stable order.
    private static func visitOwnership(_ store: CypressStore) async throws -> [String] {
        try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare(
                "SELECT client_uuid, user_id, device_id, updated_at FROM visits ORDER BY client_uuid"
            )
            defer { statement.finalize() }
            return try statement.fetchAll { row in
                [
                    try row.string("client_uuid"),
                    try row.stringIfPresent("user_id") ?? "-",
                    try row.stringIfPresent("device_id") ?? "-",
                    try row.stringIfPresent("updated_at") ?? "-",
                ].joined(separator: "|")
            }
        }
    }
}

// MARK: - 5. The boundaries the restore must not break

@MainActor
@Suite("What the restore must not resurrect")
struct SessionRestoreBoundaryTests {

    /// **The F4 boundary** (review of PR #84).
    ///
    /// `RootView.accountLink()` rolls the session back when the local half fails, so that the phone is
    /// not left holding a live account session over an unset `app_state.current_user_id`. That is the
    /// **exact state** `SessionRestore` now reads as "restore this account" — so if the rollback ever
    /// stopped removing the session, the next launch would sign the person into an account screen 15
    /// had just told them they were not signed into.
    ///
    /// This is why the boundary is asserted from this side as well as from `AccountLinkTests`: that
    /// suite proves the rollback happens, and this one proves what the restore does with the state the
    /// rollback leaves.
    @Test("a rolled-back sign-in does not become a restore on the next launch")
    func aRolledBackSignInIsNotRestored() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        let http = ScriptedAuthHTTP { _ in
            (200, ScriptedAuthHTTP.session(userID: RestoreFixture.accountID))
        }

        let data = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: http
        )
        #expect(await data.local.userID == nil, "the install was not anonymous before the tap")

        // The local half is made to fail the way `AccountLinkTests` makes it fail: the writer
        // connection refuses every write from here on. A real refusal from the real database.
        try await data.store.queue.write { connection in
            try connection.execute("PRAGMA query_only = 1")
        }
        var storeRefusesWrites = false
        do {
            try await data.store.setAppState(.accountProvider, to: "probe")
        } catch {
            storeRefusesWrites = true
        }
        guard storeRefusesWrites else {
            Issue.record("""
                the store still accepts writes, so the sign-in below would succeed and this test \
                would assert a rollback nothing needed. Nothing is proved by what follows.
                """)
            return
        }

        let link = RootView(data: data, appleSignIn: AppleSignIn { AppleSignInFixture.credential })
            .accountLink()
        await #expect(throws: (any Error).self, "a failed local link reported success") {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }
        #expect(
            await data.session.storedSession == nil,
            "the rollback kept the session, so the launch below would prove nothing about the restore"
        )

        let relaunched = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: http
        )
        #expect(
            await relaunched.local.userID == nil,
            """
            the next launch signed the person into the account screen 15 had just told them did not \
            go through. F4's rollback and this restore read the same state; the rollback's job is to \
            leave a state this one does not act on.
            """
        )
    }

    /// A sign-out has to survive a relaunch, and before this round it did not have to try.
    ///
    /// `AccountModel.signOut()` called `LocalAPI.signOut()` and nothing else, so the Keychain session
    /// stood. That was already wrong — the bearer stayed the account's after the tap — and the restore
    /// makes it visible: the database says nobody, the Keychain says somebody, and the mirror rule
    /// correctly believes the Keychain.
    @Test("signing out in the You tab survives a relaunch")
    func aSignOutIsNotUndoneByTheRestore() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        try RestoreFixture.seedSession(credentials)

        let data = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await data.local.userID == RestoreFixture.accountID, "the fixture never signed in")

        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        await account.signOut()
        #expect(!account.isSignedIn, "the tap did not sign out at all, which is a different finding")

        let relaunched = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(
            await relaunched.local.userID == nil,
            """
            the next launch signed the person back into the account they had just left. A sign-out \
            that forgets only the database leaves the credential that the restore reads as authority.
            """
        )
        #expect(
            await relaunched.session.storedSession == nil,
            "the sign-out left the session in the Keychain, so the bearer is still the account's"
        )
    }

    /// **The upgrade population, staged through the real pre-#87 path** (review of this PR, F1).
    ///
    /// The shipping build's sign-out is `LocalAPI.signOut()` alone — that is literally what
    /// `AccountModel.signOut()` did on `main`, and it is what this test calls, deliberately, rather
    /// than the fixed `AccountModel`. So the state booted below is the one on a real device that has
    /// been updated: `current_user_id` cleared, `signed_out_user_id` written, and a **live session
    /// still in the Keychain**. No reinstall is involved.
    ///
    /// Without the discriminator this is indistinguishable from the reinstall the ruling is about, and
    /// the first launch after the update signs the person back into the account they left.
    @Test("a sign-out performed by the shipping build is respected by the first launch after the update")
    func theUpgradePopulationIsNotSignedBackIn() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        try RestoreFixture.seedSession(credentials)

        let beforeTheUpdate = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await beforeTheUpdate.local.userID == RestoreFixture.accountID, "the fixture never signed in")

        // The shipping build's sign-out: the local half and nothing else. `AccountModel` is
        // deliberately not used — the point is the state a *previous version* of this app left.
        try await beforeTheUpdate.local.signOut()

        // Calibration: the staged state really is the one under test — local half gone, marker
        // written, session alive. Without this the boot below could be converging from anything.
        #expect(try await beforeTheUpdate.store.appState(.currentUserID) == nil, "the local half did not clear")
        #expect(
            try await beforeTheUpdate.store.appState(.signedOutUserID) == RestoreFixture.accountID.uuidString,
            "no signed-out marker was written, so there is no discriminator to read and nothing is staged"
        )
        #expect(
            await beforeTheUpdate.session.signedInUserID == RestoreFixture.accountID,
            "the session was not left alive, so this stages the fixed sign-out rather than the shipping one"
        )

        let firstLaunchAfterTheUpdate = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(
            await firstLaunchAfterTheUpdate.local.userID == nil,
            """
            the update signed the person back into the account they had deliberately left. This needs \
            no reinstall — it is every beta install whose owner ever tapped Sign out, on its first \
            launch after the update.
            """
        )
        #expect(
            await firstLaunchAfterTheUpdate.session.storedSession == nil,
            """
            the launch respected the sign-out on screen and left the session in the Keychain, so the \
            bearer is still the account's — the ending has to take both halves.
            """
        )
        // The marker survives, because the account is still resumable by signing in again. It is the
        // `claimDevice` sweep that erases it, and that sweep is what did not run.
        #expect(
            try await firstLaunchAfterTheUpdate.local.resumableUserID() == RestoreFixture.accountID,
            "ending signed out erased the record of which account this device had left"
        )
    }

    /// **The mismatch arm's authority grant** (review of this PR, F3).
    ///
    /// `theRestoreInventsNothing` asserts over an *empty* database, where role, provider and consent
    /// are absent whatever the restore does — the assertions were true of the fixture rather than of
    /// the code. This is the same claim over a database that already names another account, with the
    /// three facts deliberately set first, which is the only staging that can tell the two apart.
    @Test("a restore over a database naming another account inherits none of its role, provider or consent")
    func theMismatchArmInheritsNothing() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()

        // Account A, signed in and promoted, with a consent on record.
        try RestoreFixture.seedSession(credentials, userID: RestoreFixture.otherAccountID)
        let asOther = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await asOther.local.userID == RestoreFixture.otherAccountID, "account A never signed in")
        try await asOther.local.setRole(.moderator)
        try await asOther.store.setAppState(.accountProvider, to: "apple")
        try await asOther.store.setAppState(.accountLicenseVersion, to: LicenseConsent.currentVersion)

        // Calibration: the three facts really are on the database, so their absence below is the
        // restore clearing them rather than the fixture never having written them.
        #expect(await asOther.local.userRole == .moderator, "the role was not staged")
        #expect(try await asOther.store.appState(.accountProvider) == "apple", "the provider was not staged")
        #expect(
            try await asOther.store.appState(.accountLicenseVersion) == LicenseConsent.currentVersion,
            "the consent was not staged"
        )

        // The session now names account B. `reconcile` answers `.restore(B)`.
        try RestoreFixture.seedSession(credentials, userID: RestoreFixture.accountID)
        let asAccount = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )

        #expect(await asAccount.local.userID == RestoreFixture.accountID, "the session's account did not win")
        #expect(
            await asAccount.local.userRole == .member,
            """
            the incoming account inherited the outgoing one's role. A role is authority and no route \
            on this service reports one, so this is the app granting authority on the strength of a \
            row the previous account left behind.
            """
        )
        let record = try await asAccount.local.accountLink()
        #expect(record?.provider == nil, "the incoming account inherited the outgoing one's provider")
        #expect(
            record?.licenseVersion == nil,
            "the incoming account inherited a license consent the outgoing account gave"
        )
        #expect(
            AccountCopy.licenseLine(for: record) == nil,
            "the You tab drew a license sentence about a consent another account gave"
        )
    }

    /// **The local half follows the credential within the run** (review of this PR, F4a).
    ///
    /// The mirror rule used to be re-evaluated only at launch, so a session the service refused
    /// mid-use left the app drawing a signed-in account with no credential behind it until the next
    /// relaunch — the same disagreement as a reinstall, in the other direction, with the rule that
    /// exists to stop it asleep.
    @Test("a session refused mid-run ends the local account in the same run")
    func aRefusalEndsTheLocalAccountWithoutARelaunch() async throws {
        let credentials = InMemoryCredentialStore()
        // The access token is already dead, so the first authorization must refresh — and be refused.
        try RestoreFixture.seedSession(credentials, accessLifetime: -1)
        let refusing = ScriptedAuthHTTP { _ in
            (401, ScriptedAuthHTTP.refusal("unauthorized", "Your session has expired."))
        }

        let data = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: refusing
        )
        #expect(await data.local.userID == RestoreFixture.accountID, "the restore never happened")

        await #expect(throws: SessionError.refreshFailed) {
            _ = try await data.session.authorization()
        }

        // No relaunch. Same `DataLayer`, same actors.
        #expect(
            await data.local.userID == nil,
            """
            the service refused the session and the app went on naming that account for the rest of \
            the run — drawing it, and attributing every contribution to it, with no credential left \
            to send as it.
            """
        )
        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        #expect(!account.isSignedIn, "the You tab drew a signed-in account whose session had been refused")
    }

    /// The device credential is **kept** by a sign-out, and the anonymous queue goes on draining
    /// (D9). The control that stops the assertion above from being satisfied by a sign-out that
    /// simply threw both credentials away.
    @Test("signing out keeps the device credential, so the anonymous queue still drains")
    func aSignOutKeepsTheDeviceCredential() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        try RestoreFixture.seedSession(credentials)

        let data = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        let device = DeviceCredential(
            deviceToken: "device-token-1",
            expiresAt: RestoreFixture.capturedAt.addingTimeInterval(365 * 24 * 60 * 60),
            deviceUUID: data.deviceID
        )
        try credentials.setData(try AuthCoding.encoder.encode(device), forKey: CredentialKey.device)

        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        await account.signOut()

        #expect(
            try credentials.data(forKey: CredentialKey.device) != nil,
            """
            signing out threw the device credential away. Re-registering retires the previous token \
            server-side, so an unnecessary one signs out a queue that was draining (D9).
            """
        )
    }

    /// **A sign-out whose local half fails changes nothing** (review of this PR, F2).
    ///
    /// The measured failure of the first ordering was `sessionGone=true localStillSignedIn=true
    /// drawnSignedIn=true`: the credential thrown away and the app still drawing the account, for the
    /// rest of the run. The local half goes first now, so a store that refuses writes leaves the two
    /// halves exactly as they were and the person can tap again.
    @Test("a sign-out whose local half fails leaves both halves signed in")
    func aFailedLocalSignOutChangesNothing() async throws {
        let credentials = InMemoryCredentialStore()
        try RestoreFixture.seedSession(credentials)
        let data = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await data.local.userID == RestoreFixture.accountID, "the fixture never signed in")

        try await Self.refuseWrites(data)

        let account = AccountModel(api: data.local, session: data.session)
        await account.signOut()

        #expect(
            await data.session.storedSession != nil,
            """
            the sign-out threw the credential away over a local half that could not be written. The \
            app then draws the account — `isSignedIn` reads `LocalAPI.userID`, which is untouched — \
            with no credential left to be it, for the rest of the run.
            """
        )
        #expect(await data.local.userID == RestoreFixture.accountID, "the local half half-succeeded")
    }

    /// **A deletion that deleted nothing destroys no credentials** (review of this PR, F2b).
    ///
    /// Measured on the first ordering: `outcome=nil sessionGone=true deviceGone=true
    /// localStillSignedIn=true` — both credentials gone on a deletion that did not happen, silently,
    /// because `YouTabView` discards the outcome.
    @Test("a deletion that fails destroys neither credential")
    func aFailedDeletionKeepsTheCredentials() async throws {
        let credentials = InMemoryCredentialStore()
        try RestoreFixture.seedSession(credentials)
        let data = try await RestoreFixture.boot(
            databaseURL: try RestoreFixture.databaseURL(),
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        let device = DeviceCredential(
            deviceToken: "device-token-1",
            expiresAt: RestoreFixture.capturedAt.addingTimeInterval(365 * 24 * 60 * 60),
            deviceUUID: data.deviceID
        )
        try credentials.setData(try AuthCoding.encoder.encode(device), forKey: CredentialKey.device)

        try await Self.refuseWrites(data)

        let account = AccountModel(api: data.local, session: data.session)
        let outcome = await account.deleteAccount(.eraseEverything)

        #expect(outcome == nil, "the deletion succeeded, so this test is not about a failed one")
        #expect(
            await data.session.storedSession != nil,
            "a deletion that deleted nothing threw the account's session away"
        )
        #expect(
            try credentials.data(forKey: CredentialKey.device) != nil,
            """
            a deletion that deleted nothing threw the device credential away. Re-registering retires \
            the previous token server-side, so the anonymous queue this installation was draining is \
            signed out by a tap that did nothing.
            """
        )
    }

    /// Put the store's writer connection into `PRAGMA query_only`, and **prove it took**.
    ///
    /// `AccountLinkTests` established both the technique and the calibration: making the file
    /// read-only does not work, because POSIX permissions are checked at `open(2)` and the store
    /// already holds a writable descriptor. Without the probe, "nothing changed" would be reported
    /// just as happily by a run in which nothing needed to change.
    private static func refuseWrites(_ data: DataLayer) async throws {
        try await data.store.queue.write { connection in
            try connection.execute("PRAGMA query_only = 1")
        }
        var refuses = false
        do {
            try await data.store.setAppState(.accountProvider, to: "probe")
        } catch {
            refuses = true
        }
        #expect(refuses, "the store still accepts writes, so nothing below is about a failed local half")
    }

    /// Deleting the account must not leave a session that signs the person back into it.
    ///
    /// `AppSession.forgetEverything()` is what RULINGS **R3** needs of the Keychain, and it had no
    /// caller before this round. Both credentials go: a device token minted under a deleted account's
    /// claim is a pointer to it.
    @Test("a deleted account is not restored on the next launch")
    func aDeletedAccountIsNotRestored() async throws {
        let credentials = InMemoryCredentialStore()
        let databaseURL = try RestoreFixture.databaseURL()
        try RestoreFixture.seedSession(credentials)

        let data = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(await data.local.userID == RestoreFixture.accountID, "the fixture never signed in")

        let account = AccountModel(api: data.local, session: data.session)
        await account.load()
        let outcome = await account.deleteAccount(.eraseEverything)
        #expect(outcome != nil, "the deletion did not run, so nothing below is about a deletion")

        #expect(
            await data.session.storedSession == nil,
            "the deletion left the account's session in the Keychain"
        )

        let relaunched = try await RestoreFixture.boot(
            databaseURL: databaseURL,
            credentials: credentials,
            http: RestoreFixture.silentHTTP()
        )
        #expect(
            await relaunched.local.userID == nil,
            """
            the next launch signed the person back into the account they deleted. R3's promise is \
            about the Keychain as well as the tables.
            """
        )
    }
}
