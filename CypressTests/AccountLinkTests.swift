import Foundation
import Testing
@testable import Cypress

/// The composition root's half of local sign-in (ERRATA **E124**).
///
/// Two other suites cover the pieces: `AccountAskSheetTests` proves screen 15's model against a
/// supplied `onLink` (nil → "not ready yet", throw → "failed", success → one recorded request), and
/// `DeviceClaimTests` proves `claimDevice` moves every anonymous contribution onto the account. What
/// neither can see is the seam between them — that `RootView.accountLink()`, the action the `.identify`
/// call site hands to the visit flow, is a *working* local sign-in rather than a stub.
///
/// That is the failure flipping `BetaCapability.accountsAvailable` invites: the flag turns the ask
/// back on, and an action that minted no id, or set none, or persisted none, would present a sheet
/// that looks signed-in-capable and quietly is not — with the model correct and `claimDevice` correct
/// and only the composition root's action hollow. This suite exercises that action directly and fails
/// if it stops completing or stops persisting. (That the call site passes it rather than the nil
/// default is left to the compiler and the one line in `RootView` — not asserted here, because a
/// SwiftUI view's passed closures are not introspectable without rendering the visit flow, which is
/// camera-gated.)
@MainActor
@Suite("Local sign-in wiring")
struct AccountLinkTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!

    /// A `DataLayer` over an in-memory store, assembled the way `DataLayer.boot` assembles a real one
    /// (`DeviceClaimTests` wires `LocalAPI` + `OutboxQueue` the same way). No seed: a community add is
    /// what `requireTree` accepts.
    private static func bootInMemory() async throws -> DataLayer {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))
        // `api:` is the *local* half in both positions here on purpose. These tests are about the
        // on-device account leg, and a router in front of it would put a network refusal between the
        // assertion and the table it is about. What `DataLayer.boot` really wires is
        // `CypressTests/DataLayerWiringTests`' subject, not this suite's.
        return DataLayer(
            store: store,
            api: api,
            local: api,
            outbox: outbox,
            deviceID: deviceID,
            session: AppSession(deviceUUID: deviceID),
            readLog: RemoteReadLog()
        )
    }

    @Test("the root supplies a sign-in that completes on-device and persists across a relaunch")
    func rootSignInCompletesLocally() async throws {
        let data = try await Self.bootInMemory()

        // Something anonymous to bring across, so "signed in" is observable as ownership moving rather
        // than only as a flag flipping.
        let tree = try await data.local.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-link-test.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        _ = try await data.outbox.enqueue(.visit(Visit(
            treeID: tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            note: "before sign-in",
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )))
        _ = try await data.outbox.drain()

        let link = RootView(data: data).accountLink()
        #expect(await data.local.userID == nil, "nobody is signed in before the tap")

        // Exactly what screen 15 hands its action when a button is tapped.
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))

        let signedInAs = await data.local.userID
        #expect(signedInAs != nil, "the tap signed nobody in — accountLink is nil or a no-op")

        // Persisted in `app_state`, so `DataLayer.boot` reads it back and a relaunch stays signed in.
        let persisted = try await data.store.appState(.currentUserID)
        #expect(persisted == signedInAs?.uuidString, "sign-in did not survive to app_state")

        // And the visit came with them (this is `claimDevice` firing, from the composition root).
        let owner = try await data.store.queue.read { connection -> String? in
            let statement = try connection.prepare("SELECT user_id FROM visits")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.stringIfPresent("user_id") }.first ?? nil
        }
        #expect(owner == signedInAs?.uuidString, "the visit stayed the device's after sign-in")
    }

    @Test("a second sign-in keeps the same local account rather than minting a rival")
    func signInIsIdempotentOnIdentity() async throws {
        let data = try await Self.bootInMemory()
        let link = RootView(data: data).accountLink()

        try await link(AccountLinkRequest(provider: .email, acceptsLicense: false))
        let first = await data.local.userID
        try await link(AccountLinkRequest(provider: .email, acceptsLicense: false))
        let second = await data.local.userID

        #expect(first != nil)
        #expect(first == second, "re-linking minted a new account id and orphaned the first (ERRATA E34 can re-present the ask)")
    }
}
