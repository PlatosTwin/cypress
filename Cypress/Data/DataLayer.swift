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
    public let api: LocalAPI
    public let outbox: OutboxQueue
    /// This installation's device id (D9). Stable across launches; minted on first run.
    public let deviceID: UUID

    /// Opens the store, runs migrations, attaches the seed, and wires the outbox to `LocalAPI`.
    ///
    /// - Parameters:
    ///   - databaseURL: defaults to Application Support.
    ///   - seedURL: defaults to the bundled seed. A `nil` seed is survivable — see `CypressStore.open`.
    public static func boot(
        databaseURL: URL? = nil,
        seedURL: URL? = SeedDatabase.urlInBundle()
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
        let api = LocalAPI(store: store, deviceID: deviceID, userID: userID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        // Anything left `uploading` belongs to a previous launch that was killed mid-drain. It is
        // recovered on the first drain; doing it here as well means the outbox screen shows the
        // truth before any sync is attempted.
        try await store.queue.write { connection in
            _ = try OutboxStore().recoverInterrupted(at: Date(), connection: connection)
        }

        return DataLayer(store: store, api: api, outbox: outbox, deviceID: deviceID)
    }

    /// Screen 17's model, wired to this layer's outbox and name resolution.
    @MainActor
    public func makeOutboxViewState() async -> OutboxViewState {
        let api = api
        let stored = try? await store.appState(.syncPhotosOnWifiOnly)
        let state = OutboxViewState(
            queue: outbox,
            store: store,
            // The default is on: the toggle exists to respect a volunteer's data plan (screen 17).
            syncPhotosOnWifiOnly: stored.map { ($0 as NSString).boolValue } ?? true,
            treeNameResolver: { ids in await api.displayNames(for: ids) }
        )
        await state.start()
        return state
    }
}
