import Foundation

/// Everything `App/` needs from `Data`, assembled in one call.
///
/// ARCHITECTURE §3: shared services are "passed through the SwiftUI environment from a single
/// composition root in `App/`. No singletons, no `.shared`." This type is not that root — it is
/// what the root constructs, so the wiring order (open the database, migrate, attach the seed, mint
/// or read the device id, build the API, point the outbox at it) lives beside the code it wires
/// rather than in a view file.
///
/// ```swift
/// // in App/CypressApp.swift
/// let data = try await DataLayer.boot()
/// ```
public struct DataLayer: Sendable {
    public let store: CypressStore

    /// **The router** (spec §3.1), and what every screen holds.
    ///
    /// It was a `LocalAPI` on every build before #158's wiring round. It is now a `RoutedAPI` over
    /// the phone and the service, so a Class R read reaches `cypress-sync` and a Class L read does
    /// not — "No Class L read is allowed to acquire a remote failure mode" (§4.3), which is a
    /// property of `RoutedAPI` and is tested there.
    public let api: any CypressAPI

    /// **The phone's half, named separately because four things only it can answer.**
    ///
    /// `linkAccount`, `resumableUserID`, `attribution` and `debugClearStatusOverrides` are on
    /// `LocalAPI` and not on `CypressAPI` — they are about *this installation's* account row and
    /// this installation's debug state, and a protocol requirement for them would oblige every
    /// preview double to answer a question about a local table. `RootView.accountLink()` is the
    /// caller that matters.
    ///
    /// It is also the **apply sink's** API, and that is the load-bearing use: it is named here so
    /// the wiring below can say `APIOutboxTransport(api: local)` in as many words rather than
    /// leaning on `RoutedAPI` happening to route `sync` local. Swapping a remote implementation into
    /// that position "does not add a network to a local write, it removes the local write"
    /// (ERRATA **E261** §2).
    public let local: LocalAPI

    public let outbox: OutboxQueue
    /// This installation's device id (D9). Stable across launches; minted on first run.
    public let deviceID: UUID

    /// The session behind every authenticated call: the device credential on an anonymous
    /// installation, the account's when there is one (spec §5.8).
    public let session: AppSession

    /// Whether the remote half is wired, and why not when it is not.
    ///
    /// **It is the gate's answer, or `.live` when a caller passed its own transport** — see `boot`.
    /// A test that supplies a scripted wire reads `.live` here, which is the honest reading: the
    /// remote half *is* wired, to the thing that caller chose. What the gate protects against is a
    /// caller that chose nothing.
    ///
    /// Held so the composition root can draw `RemoteAccess.complaint` — a mistyped `CYPRESS_REMOTE`
    /// must be visible rather than silently safe (`DebugLocationOverride`'s rule) — and so a test
    /// can assert what `boot` actually decided instead of inferring it from behaviour.
    ///
    /// `RootView.runDebugEntryPoints()` is where it is drawn, first of the three launch-gate
    /// complaints. That sentence was a promise with nothing behind it until round-4 review pointed
    /// out that the precedent it cited was drawn and this was not.
    public let remoteAccess: RemoteAccess

    /// Which Class R reads answered live and which fell back to the phone (spec §4.3).
    ///
    /// Nothing in `Features` reads it yet, on purpose — §4.3 rules that the *sentence* a screen
    /// draws about a degraded read "is a copy question and it is **not in the mocks**". It is held
    /// here so that the round which draws that copy has one log to read rather than one per screen.
    public let readLog: RemoteReadLog

    /// Opens the store, runs migrations, attaches the seed, and wires the router and both outbox
    /// sinks.
    ///
    /// - Parameters:
    ///   - databaseURL: defaults to Application Support.
    ///   - seedURL: defaults to the bundled seed. A `nil` seed is survivable — see `CypressStore.open`.
    ///   - baseURL: the service. `SyncService.defaultBaseURL` is `cypress-sync`.
    ///   - transport: the authorized wire. **Nil means "whatever `remoteAccess` says"** —
    ///     `SessionTransport` when it is `.live`, `RefusingTransport` otherwise. It is a parameter so
    ///     a test can wire the real composition root against a scripted transport and assert what it
    ///     wired, which is the only way to test this function at all: `DataLayerWiringTests` boots
    ///     the same code path the app runs and never touches the network. Passing one **overrides
    ///     the gate**, because a caller holding a transport has already decided what it is.
    ///   - remoteAccess: whether this process may reach the service at all. Defaults to
    ///     `RemoteAccess.resolved`, which is `.live` in a release build and — in DEBUG, where the
    ///     test targets live — `.disabled` unless `CYPRESS_REMOTE=live` says otherwise. See
    ///     `RemoteAccess` for why the default is off rather than on; in one line, the UI suite boots
    ///     this function and a missing environment variable must not be the thing that points it at
    ///     production.
    ///   - authHTTP: the `/auth/*` and `/devices/register` wire. **Nil means "whatever
    ///     `remoteAccess` says"**, exactly as `transport` does — `URLSession.shared` when it is
    ///     `.live`, `OfflineSession.make()` otherwise.
    ///
    ///     It is a **separate** parameter from `transport`, and separate on purpose: passing a
    ///     `transport` overrides the gate for `RemoteAPI`'s wire, and it says nothing whatever about
    ///     `/auth/*`. Letting that override extend here would have put every test that scripts a
    ///     transport back on a live `AuthClient`, which is the defect this parameter exists to close
    ///     rather than move (review of PR #84, F1).
    ///   - credentials: where the session and device credentials live. Defaults to the Keychain,
    ///     which is what ships.
    ///
    ///     It is a parameter for one reason and it is not tidiness: the account reconciliation below
    ///     reads this store, so a test of it that could not supply one would have to seed the
    ///     **real** login Keychain of whoever ran the suite — leaving an item behind that a later run
    ///     on the same machine would find and read as a signed-in account. `SessionTests` already
    ///     names that hazard and answers it with a per-run service name; this parameter is the same
    ///     answer for the composition root.
    public static func boot(
        databaseURL: URL? = nil,
        seedURL: URL? = SeedDatabase.urlInBundle(),
        baseURL: URL = SyncService.defaultBaseURL,
        transport: (any AuthorizedTransport)? = nil,
        authHTTP: (any AuthHTTP)? = nil,
        remoteAccess: RemoteAccess = .resolved,
        credentials: any CredentialStore = KeychainCredentialStore()
    ) async throws -> DataLayer {
        let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: seedURL)

        // The device id is minted once and kept. Anonymous contributions attach to it and migrate
        // to a user at `POST /devices/claim`; regenerating it would orphan them (D9).
        let deviceID: UUID
        if let stored = try await store.appState(.deviceUUID), let parsed = UUID(uuidString: stored) {
            deviceID = parsed
        } else {
            deviceID = UUID()
            try await store.setAppState(.deviceUUID, to: deviceID.uuidString)
        }

        // ── The service ────────────────────────────────────────────────────────────────────────
        //
        // The session is lazy by construction: `AppSession` registers the device the first time a
        // credential is actually needed, so a launch that only wants to look at a map never reaches
        // the network (`AppSession.bootstrap()` says why). Nothing here calls it.
        //
        // ── This line used to read `AppSession(deviceUUID: deviceID)`, and that was a hole in the
        //    gate the size of the whole `/auth/*` surface (review of PR #84, F1) ─────────────────
        //
        // The default `AuthClient()` is `SyncService.defaultBaseURL` over `URLSession.shared`, and
        // `boot`'s own `baseURL:` was never handed to it. `remoteAccess` chose between
        // `SessionTransport` and `RefusingTransport` for `RemoteAPI` — and `AppSession` goes through
        // neither, so a `.disabled` build still dialled `https://cypress-sync.fly.dev/api/v1` the
        // moment anything asked it for a credential. The reviewer measured it with a `URLProtocol`
        // in front of `URLSession.shared`: with `RemoteAccess == .disabled`, a sign-in opened
        // `…/auth/oidc`.
        //
        // It was unreachable-in-practice only for as long as `signInWithApple` had no caller. #158
        // step 5 gave it one, on screen 15, in a build the UI suite launches — which is exactly the
        // sequence `RemoteAccess`'s own header describes: nothing was wrong with any individual
        // test, the absence of a decision pointed the suite at production.
        //
        // **The gate is read from `remoteAccess` and not from `access` below.** See `authHTTP`'s
        // parameter documentation: a caller that passed a `transport` decided what `RemoteAPI`'s
        // wire is and decided nothing about this one, so the override deliberately does not reach
        // here. `RemoteAccessTests` proves the resulting build opens no socket, with the
        // interception calibrated by a control request first.
        let session = AppSession(
            deviceUUID: deviceID,
            client: AuthClient(
                baseURL: baseURL,
                http: authHTTP ?? (remoteAccess.allowsNetwork ? URLSession.shared : OfflineSession.make())
            ),
            credentials: credentials
        )

        // ── Who this installation is, decided from both halves rather than from the database ────
        //
        // `app_state.current_user_id` used to be read straight into `LocalAPI` and that was the whole
        // of the account's boot. It is a database fact, and on iOS the database does not survive an
        // app deletion while the Keychain does — so a reinstall on a phone holding a live account
        // session drew a signed-out app whose every request went out with the account's bearer.
        // `SessionRestore` states the rule that closes it, in both directions, and its header carries
        // the owner's ruling and the reason this arm diverges from the device arm's opposite one.
        //
        // **Nothing here reaches the network, and that is a requirement rather than a happy result.**
        // The only fact the restore needs is the account id, and the account id is *in* the session
        // (`SessionCredentials.userID`). `AppSession.bootstrap()` rules that a launch must not dial
        // out for somebody who only wanted to look at a map; a restore that had to would have broken
        // that rule for every launch, not just the one after a reinstall.
        //
        // **Three inputs, not two, and the third is the one an existing device needs** (review of
        // this PR, F1). "No local account beside a live session" describes the reinstall this ruling
        // is about — and equally describes every beta install whose owner tapped `Sign out` under the
        // shipping build, because that sign-out cleared `current_user_id` and left the Keychain alone.
        // Those devices reach this line on the first launch after the update, with no reinstall
        // involved, and a two-input rule signs them back into the account they left.
        // `signed_out_user_id` is what tells the two apart; `SessionRestore.reconcile` has the whole
        // argument, including why it is read only when the database names nobody.
        let storedUserID = (try await store.appState(.currentUserID)).flatMap(UUID.init(uuidString:))
        let signedOutUserID = (try await store.appState(.signedOutUserID)).flatMap(UUID.init(uuidString:))
        let reconciliation = SessionRestore.reconcile(
            storedUserID: storedUserID,
            signedOutUserID: signedOutUserID,
            sessionUserID: await session.signedInUserID
        )

        // The account's role (ERRATA E124-B), carried in `app_state` like the user id — there is no
        // `users` table on device (ERRATA E86). Absent, or an unknown string, reads as `.member`.
        //
        // **A restore does not raise it, and that is deliberate**: no route on this service reports a
        // role, so a restored install reads back `.member`. A role is authority, and the direction to
        // fail in is the one that does not grant it. `LocalAPI.restoreAccount` is where that is
        // enforced rather than here, because it is enforced for the provider and the consent in the
        // same breath.
        let role = (try await store.appState(.currentUserRole)).flatMap(UserRole.init(rawValue:)) ?? .member
        let local = LocalAPI(store: store, deviceID: deviceID, userID: storedUserID, role: role)

        // Applied through `LocalAPI`'s own verbs rather than by writing `app_state` here. A restore is
        // the local half of a sign-in: `restoreAccount` sweeps this installation's unattributed rows
        // onto the account and writes the id, and clears the three facts a restore cannot know.
        // Ending signed out is `signOut()`, which keeps every row and remembers the id. Re-
        // implementing either as a bare `setAppState` would be a second statement of a rule that
        // already has one.
        //
        // Both are idempotent, which is what makes a launch killed part-way through recoverable: the
        // next launch reads all three inputs again and reaches the same verdict. See `SessionRestore`
        // for why there is no "restore in progress" flag to be left behind.
        switch reconciliation {
        case .unchanged:
            break
        case let .restore(userID):
            try await local.restoreAccount(deviceUUID: deviceID, userID: userID)
        case .endSignedOut:
            // **Both halves.** One of the two states that reach here is a live session beside a
            // deliberate sign-out (F1), and leaving that session standing would leave the bearer as
            // the account's — which is the defect the ending is supposed to close, not a leftover of
            // it. On the other state the session is already gone or already dead, and this is a
            // no-op. `signOut()` and not `forgetEverything()`: the device credential goes on draining
            // the anonymous queue (D9).
            try await local.signOut()
            try await session.signOut()
        }

        // The mirror rule, applied at the moment the fact changes rather than only at the next launch
        // (review of this PR, F4). `AppSession` discards a session the service refuses; without this
        // the app went on drawing that account until the app was relaunched. `signOut()` and not
        // `forgetEverything()` for the reason above, and `try?` because there is nothing a failed
        // local sign-out could report to — the next launch's reconciliation reaches the same verdict
        // from `app_state` and the now-empty Keychain.
        await session.onSessionEnded { [local] _ in try? await local.signOut() }

        // ── One decision, not two ──────────────────────────────────────────────────────────────
        //
        // **An explicitly-passed transport overrides the gate**, and it overrides it for the *send
        // sink* as well as for the wire. The first cut of this gate overrode only the wire, so a
        // caller that supplied a scripted transport got it — and then had its send sink silently
        // omitted, because the gate was still `.disabled`. `DataLayerWiringTests` went red on four
        // tests that had nothing wrong with them, which is what a two-variable answer to a
        // one-variable question does.
        //
        // A caller holding a transport has already said what the wire is; that is the decision, and
        // `remoteAccess` records it so nothing downstream has to consult two facts to know one.
        let access: RemoteAccess = transport == nil ? remoteAccess : .live
        let authorized = transport ?? (access.allowsNetwork
            ? SessionTransport(session: session)
            : RefusingTransport())

        // `DELETE /me` tombstones the keys still queued at the moment of deletion, "even though this
        // service has never seen them" (`me.go`), and `RemoteAPI` holds no queue — it holds no store
        // of any kind, which is the property that made it a boundary proof. So the composition root
        // is what has both, and this closure is the seam being filled: with no provider `RemoteAPI`
        // *refuses*, because an empty array is the claim that nothing is queued and RULINGS R3's
        // stated failure mode is deleting differently from what was asked.
        //
        // It reads the table and not `outbox` below, which is what keeps this a straight line
        // instead of a cycle: what is still queued is a fact about the rows, and `OutboxQueue` is
        // policy over the same rows.
        let queue = store.queue
        let remote = RemoteAPI(
            baseURL: baseURL,
            transport: authorized,
            pendingOutboxKeys: {
                try await queue.read { connection in
                    try OutboxStore().unsentClientUUIDs(connection: connection)
                }
            }
        )

        let readLog = RemoteReadLog()

        // `RoutedAPI.deleteAccount` sends `DELETE /me` before it deletes anything on the phone (the
        // owner's ruling of 2026-08-23, closing ERRATA E272), and this is how it knows there is an
        // account to send about. Signed out, the deletion stays local — `me.go` refuses a device
        // credential, so asking would turn a working local deletion into a refusal.
        //
        // **Only when the gate is open**, for the send sink's reason two blocks down: with
        // `RefusingTransport` behind it every deletion would fail, and abort-on-failure would then
        // leave a local-only build unable to delete an account at all.
        let api = RoutedAPI(
            local: local,
            remote: remote,
            log: readLog,
            signedInUserID: access.allowsNetwork ? { await session.signedInUserID } : nil
        )

        // ── Two sinks, and this is the round that wires the second (RULINGS R72 §1) ─────────────
        //
        // `apply` is the local commit: a contribution is on its tree the moment the drain runs,
        // offline or not. It names `local` rather than `api` deliberately — `RoutedAPI` does route
        // `sync` to the phone, but a wiring that depended on that would be one router edit away from
        // deleting the local write while every layer carried on behaving exactly as written
        // (ERRATA E261 §2).
        //
        // `send` is `APIOutboxSendSink` over `RemoteAPI` and **not over `api`**, for the mirror
        // reason: a router in this position would "send" through `local` and mark the row
        // `remote_sent` with no byte having left the phone. The type signature is what refuses it —
        // see `APIOutboxSendSink`.
        //
        // **The send sink is omitted entirely when the gate is off**, rather than pointed at a
        // refusing transport. A refusing send sink would still count failures, move rows onto the
        // backoff and put reasons on screen 17 — observable behaviour a UI test would then be
        // asserting against a network that is not there. Omitting it restores exactly the wiring
        // every build before #158 shipped, which is the one the UI suite was green on.
        let outbox = OutboxQueue(
            queue: store.queue,
            apply: APIOutboxTransport(api: local),
            send: access.allowsNetwork ? APIOutboxSendSink(remote: remote) : nil
        )

        // Anything left `uploading` belongs to a previous launch that was killed mid-drain. It is
        // recovered on the first drain; doing it here as well means the outbox screen shows the
        // truth before any sync is attempted.
        try await store.queue.write { connection in
            _ = try OutboxStore().recoverInterrupted(at: Date(), connection: connection)
        }

        return DataLayer(
            store: store,
            api: api,
            local: local,
            outbox: outbox,
            deviceID: deviceID,
            session: session,
            remoteAccess: access,
            readLog: readLog
        )
    }

    /// Boots preferring the reader's chosen downloaded city over the bundle (RULINGS R43 §1:
    /// one inventory attaches, and which one is the reader's choice).
    ///
    /// `CityLibrary.validatedActiveSeedURL()` has already introspected the file and refused a
    /// schema generation from the future; what remains is the open itself, and a failure there
    /// deactivates the choice and boots the bundle — launching without the chosen city beats not
    /// launching, and the Cities screen then shows the truth (installed, not in use).
    public static func bootPreferringActiveCity(
        databaseURL: URL? = nil,
        library: CityLibrary
    ) async throws -> DataLayer {
        if let cityURL = library.validatedActiveSeedURL() {
            do {
                return try await boot(databaseURL: databaseURL, seedURL: cityURL)
            } catch {
                try? library.deactivate()
            }
        }
        return try await boot(databaseURL: databaseURL)
    }

    /// Screen 17's model, wired to this layer's outbox and name resolution.
    ///
    /// Synchronous, because `OutboxView` owns it through `@State` and a view cannot `await` its own
    /// initializer. Nothing is lost by that: `OutboxViewState.start()` reads the stored wi-fi
    /// preference and takes the first snapshot itself, and the view calls it from `.task`. The
    /// default until that read lands is on, because the toggle exists to respect a volunteer's data
    /// plan (screen 17 §3).
    @MainActor
    public func makeOutboxViewState() -> OutboxViewState {
        // `local`, because `displayNames` is a `LocalAPI` method and a name is a city-layer fact
        // (Class L): it is in the installed inventory and a live query would return a row exactly as
        // old as the published file (§4.2).
        let api = local
        return OutboxViewState(
            queue: outbox,
            store: store,
            syncPhotosOnWifiOnly: true,
            // `displayNames` asks for a name and nothing else. Reading a whole profile per queued
            // tree would pull photo, visit and care series across for a row that renders one string.
            treeNameResolver: { ids in await api.displayNames(for: ids) }
        )
    }
}
