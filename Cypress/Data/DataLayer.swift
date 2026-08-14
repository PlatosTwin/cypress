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
    ///   - transport: the authorized wire. **Nil means the live one** — `SessionTransport` over the
    ///     `AppSession` this call constructs. It is a parameter so a test can wire the real
    ///     composition root against a scripted transport and assert what it wired, which is the only
    ///     way to test this function at all: `DataLayerWiringTests` boots the same code path the app
    ///     runs and never touches the network.
    public static func boot(
        databaseURL: URL? = nil,
        seedURL: URL? = SeedDatabase.urlInBundle(),
        baseURL: URL = SyncService.defaultBaseURL,
        transport: (any AuthorizedTransport)? = nil
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

        let userID = (try await store.appState(.currentUserID)).flatMap(UUID.init(uuidString:))
        // The account's role (ERRATA E124-B), carried in `app_state` like the user id — there is no
        // `users` table on device (ERRATA E86). Absent, or an unknown string, reads as `.member`.
        let role = (try await store.appState(.currentUserRole)).flatMap(UserRole.init(rawValue:)) ?? .member
        let local = LocalAPI(store: store, deviceID: deviceID, userID: userID, role: role)

        // ── The service ────────────────────────────────────────────────────────────────────────
        //
        // The session is lazy by construction: `AppSession` registers the device the first time a
        // credential is actually needed, so a launch that only wants to look at a map never reaches
        // the network (`AppSession.bootstrap()` says why). Nothing here calls it.
        let session = AppSession(deviceUUID: deviceID)
        let authorized = transport ?? SessionTransport(session: session)

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
        let api = RoutedAPI(local: local, remote: remote, log: readLog)

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
        let outbox = OutboxQueue(
            queue: store.queue,
            apply: APIOutboxTransport(api: local),
            send: APIOutboxSendSink(remote: remote)
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
