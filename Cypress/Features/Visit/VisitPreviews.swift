//
//  VisitPreviews.swift
//  Cypress — Features/Visit
//
//  Fixtures for screens 02, 04 and 18 — the three screens in the app that had none.
//
//  ── Why this file did not exist and why it does now ───────────────────────────────────────
//  Every other feature folder carries a `*Previews.swift` with a `CypressAPI` double and a set of
//  drawn-state fixtures, and that is what `DynamicTypeScreenshotTests` renders. Visit had none, so
//  02, 04 and 18 were the three screens nobody could photograph without running the app and walking
//  a flow that needs a camera and a GPS fix. They were, accordingly, three of the sixteen screens
//  that had never been looked at (ERRATA E114).
//
//  The three doubles here are the smallest inputs each screen derives from:
//
//  - **02** derives from a fix and a `treesNear` read. The fix comes from
//    `VisitLocationProvider(pinnedFix:)`, a `#if DEBUG` seam on the provider itself, because
//    `CLLocationManager` inside a test host never leaves `notDetermined` and every capture of 02
//    was therefore its `Finding you` notice.
//  - **04** derives from a camera. There is no camera in a simulator and there is not going to be
//    one, so what this stands up is the state a simulator (and a phone with the permission refused)
//    actually renders — the chrome, the tray and the placeholder.
//  - **18** derives from a `VisitSaveReceipt`, which is minted rather than staged: the receipt type
//    is what the save returns and building one by hand would let this file drift from it.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers the two reads the visit flow makes and refuses everything else. Previews only.
struct VisitPreviewAPI: CypressAPI {

    var nearby: [NearbyTree] = VisitPreviewFixtures.shortlistRows
    var profile: TreeProfile = TreeProfile(tree: VisitPreviewFixtures.cypress)

    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        Array(nearby.prefix(limit))
    }

    func treeProfile(id: UUID) async throws -> TreeProfile { profile }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

/// A transport that accepts nothing, so a preview never writes anywhere real.
struct VisitPreviewTransport: OutboxTransport {
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws {}
}

// MARK: - Fixtures

enum VisitPreviewFixtures {

    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!
    static let origin = Coordinate(latitude: 37.7601, longitude: -122.5054)

    static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "9F3A0000-0000-4000-8000-%012X", index))!
    }

    // ── The four trees SCREENS 02 lists, at the distances it lists ────────────────────────────

    static let cypress = Tree(
        id: id(0x02_01),
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.76013, longitude: -122.50537),
        verificationState: .cityRecord
    )
    static let ginkgo = Tree(
        id: id(0x02_02),
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.76017, longitude: -122.50533),
        verificationState: .cityRecord
    )
    static let plane = Tree(
        id: id(0x02_03),
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.76010, longitude: -122.50524),
        verificationState: .cityRecord
    )
    static let box = Tree(
        id: id(0x02_04),
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.75995, longitude: -122.50540),
        verificationState: .cityRecord
    )

    /// SCREENS 02's four rows. The tells are the spec's own strings, which exist here because the
    /// spec draws them; the shipped seed carries `id_tips = []` and the rows render without one
    /// (BUILD-PLAN §15) — `untelledRows` is that state.
    static let shortlistRows: [NearbyTree] = [
        NearbyTree(
            tree: cypress,
            distanceM: 3,
            speciesScientificName: "Hesperocyparis macrocarpa",
            speciesCommonName: "Monterey Cypress",
            tell: IDTip(icon: "leaf", text: "scale-like leaves, lemony when crushed")
        ),
        NearbyTree(
            tree: ginkgo,
            distanceM: 9,
            speciesScientificName: "Ginkgo biloba",
            speciesCommonName: "Ginkgo",
            tell: IDTip(icon: "leaf", text: "fan-shaped leaves")
        ),
        NearbyTree(
            tree: plane,
            distanceM: 14,
            speciesScientificName: "Platanus × hispanica",
            speciesCommonName: "London Plane",
            tell: IDTip(icon: "leaf", text: "camouflage bark, maple-like leaves")
        ),
        NearbyTree(
            tree: box,
            distanceM: 17,
            speciesScientificName: "Pittosporum undulatum",
            speciesCommonName: "Victorian Box",
            tell: IDTip(icon: "leaf", text: "wavy leaf edges, honey scent at night")
        ),
    ]

    /// The shipped seed's actual shape: real trees, no authored tells.
    static var untelledRows: [NearbyTree] {
        shortlistRows.map {
            NearbyTree(
                tree: $0.tree,
                distanceM: $0.distanceM,
                speciesScientificName: $0.speciesScientificName,
                speciesCommonName: $0.speciesCommonName,
                tell: nil
            )
        }
    }

    /// An unmigrated in-memory queue — the previews draw the screens, they do not save from them.
    /// Screens 02, 04 and 18 read rather than write, so nothing here ever hits the `outbox` table.
    static func outbox() -> OutboxQueue {
        OutboxQueue(queue: try! DatabaseQueue.inMemory(), apply: VisitPreviewTransport())
    }

    /// A *migrated* queue, for the one fixture that actually enqueues — `receipt()`. The screen-18
    /// fixture is the only preview in the app that saves rather than draws, and a save needs the
    /// `outbox` table to exist. `CypressStore.inMemory()` runs `AppSchema.migrations`, so the table
    /// is there; nothing is seeded, because a receipt is a write and not a read.
    static func migratedOutbox() async throws -> OutboxQueue {
        let store = try await CypressStore.inMemory()
        return OutboxQueue(queue: store.queue, apply: VisitPreviewTransport())
    }

    // ── 02 ────────────────────────────────────────────────────────────────────────────────────

    /// D6's ambiguous case, which is the state SCREENS 02 draws: a ±9 m circle wide enough that the
    /// first two candidates both fall inside it, so the second status chip appears.
    @MainActor
    static func identify(
        rows: [NearbyTree] = shortlistRows,
        fix: VisitLocationProvider.Fix = .located(origin, accuracyM: 9)
    ) -> VisitIdentifyView {
        VisitIdentifyView(
            api: VisitPreviewAPI(nearby: rows),
            location: VisitLocationProvider(pinnedFix: fix),
            onPick: { _ in },
            onAddTree: {},
            onBack: {}
        )
    }

    // ── 04 ────────────────────────────────────────────────────────────────────────────────────

    @MainActor
    static func camera(displayName: String = "Grandmother Cypress") -> VisitCameraView {
        VisitCameraView(
            treeID: cypress.id,
            treeDisplayName: displayName,
            gpsAccuracyM: { 9 },
            api: VisitPreviewAPI(),
            outbox: outbox(),
            attribution: attribution,
            onSaved: { _ in },
            onClose: {}
        )
    }

    // ── The community add ─────────────────────────────────────────────────────────────────────

    /// The add-tree composer, on a fix good enough that every row it can draw is drawn — the state
    /// the owner reported against (ERRATA E174), and the state the photo well's ceiling is measured
    /// in. `VisitPreviewAPI.addTree` refuses, so nothing here can write a tree.
    ///
    /// It exists for the same reason `camera()` does: the screen is behind a flow that needs a GPS
    /// fix, and a renderer that has none draws the `Finding you` notice instead of the screen.
    @MainActor
    static func addTree(
        fix: VisitLocationProvider.Fix = .located(origin, accuracyM: 5)
    ) -> VisitAddTreeView {
        VisitAddTreeView(
            api: VisitPreviewAPI(),
            location: VisitLocationProvider(pinnedFix: fix),
            attribution: attribution,
            onAdded: { _ in },
            onOpenExisting: { _ in },
            onBack: {}
        )
    }

    // ── 18 ────────────────────────────────────────────────────────────────────────────────────

    /// A receipt as the save actually produces one, rather than one assembled by hand. A visit
    /// cannot be saved without a photo (`VisitOutboxWriter.enqueue` throws `validationFailed`
    /// otherwise, which is PROTOTYPE-FLOW §1.6.1's disabled-CTA rule at the boundary), so one is
    /// staged first — a 1×1 JPEG under the real staging directory, deleted nowhere because the
    /// preview outbox is in-memory and thrown away with the test.
    @MainActor
    static func receipt(treeID: UUID = cypress.id) async throws -> VisitSaveReceipt {
        let visitID = UUID()
        // A real 1×1 JPEG. Two bare markers used to do — a path on disk was all this needed — but
        // staging rewrites the container to drop the metadata now (E148) and it refuses bytes that
        // are not a container. Refusing them is the point of it, so the preview supplies a photograph.
        let path = try VisitPhotoStaging.write(onePixelJPEG(), for: visitID, shotType: .fullTree)
        return try await VisitOutboxWriter.save(
            VisitDraft(
                visitID: visitID,
                treeID: treeID,
                note: "New tips glowing",
                gpsAccuracyM: 9,
                photos: [OutboxPhoto(path: path, shotType: .fullTree)]
            ),
            attribution: attribution,
            outbox: migratedOutbox()
        )
    }

    /// Screen 18 with a route behind it — the ten-tree morning, four of them done.
    @MainActor
    static func saved(
        receipt: VisitSaveReceipt,
        rows: [NearbyTree] = shortlistRows,
        visited: [UUID]? = nil
    ) -> VisitSavedView {
        VisitSavedView(
            receipt: receipt,
            treeDisplayName: "Judah Street Gum",
            origin: origin,
            visitedTreeIDs: visited ?? [receipt.visit.treeID],
            api: VisitPreviewAPI(nearby: rows),
            ledger: VisitSaveLedger(defaults: transientDefaults()),
            onNextTree: { _ in },
            onRouteComplete: {},
            onDone: {},
            onOpenTimeline: { _ in }
        )
    }

    /// One dark-gray pixel, encoded as a JPEG. What a preview needs of a photograph is that it be one.
    static func onePixelJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.jpegData(compressionQuality: 1) ?? Data()
    }

    /// A `UserDefaults` suite nothing else reads, so rendering 18 never touches D9's real counter.
    static func transientDefaults() -> UserDefaults {
        UserDefaults(suiteName: "cypress.preview.\(UUID().uuidString)") ?? .standard
    }
}

// MARK: - Previews

/// The state SCREENS.md 02 draws: a ±9 m fix, four candidates, the top one highlighted.
#Preview("02 · what tree is this?") {
    VisitPreviewFixtures.identify()
}

/// The shipped seed's version of the same screen: no authored tells, so no tell lines.
#Preview("02 · no tells authored") {
    VisitPreviewFixtures.identify(rows: VisitPreviewFixtures.untelledRows)
}

/// A fix good enough that only one tree is in range — no confirm-by-eye chip.
#Preview("02 · one candidate, sure") {
    VisitPreviewFixtures.identify(
        rows: Array(VisitPreviewFixtures.shortlistRows.prefix(1)),
        fix: .located(VisitPreviewFixtures.origin, accuracyM: 4)
    )
}

/// Location refused. The shortlist cannot be ranked at all and the footer is the way out.
#Preview("02 · location denied") {
    VisitPreviewFixtures.identify(fix: .denied)
}

/// Dark. 02 has no specified dark screen (D1–D3 and 04 are the only ones, ERRATA E8), so this is
/// evidence of what the token layer resolves it to rather than a design.
#Preview("02 · dark") {
    VisitPreviewFixtures.identify().preferredColorScheme(.dark)
}

/// Screen 04 as a device without a camera renders it — which is every simulator, and every phone
/// whose camera permission was refused.
#Preview("04 · visit camera") {
    VisitPreviewFixtures.camera()
}

/// The community add, at the drawn type size — the photograph bounded so the form below it is on
/// the screen with it (ERRATA E174).
#Preview("add · composer") {
    VisitPreviewFixtures.addTree()
}

/// The same at AX5, which is where the well used to be a gray box clipped at the footer with the
/// whole form below a fold nothing admitted to.
#Preview("add · composer · AX5") {
    VisitPreviewFixtures.addTree().environment(\.dynamicTypeSize, .accessibility5)
}

/// The community add's pin step, on a fix as poor as a street canyon really produces.
///
/// **NOT SPECIFIED** — see `VisitPinAdjustPresentation`. Standalone rather than through the add
/// screen, because it takes a coordinate and two closures and owns no draft, which is also what
/// makes it deep-linkable for the accessibility suite.
#Preview("pin · right where you are standing") {
    VisitPinAdjustView(
        anchor: VisitPreviewFixtures.origin,
        accuracyM: 24,
        onConfirm: { _ in },
        onCancel: {}
    )
}

/// The same screen re-opened on a pin that has already been moved most of the way to the limit — the
/// state a correction starts from.
#Preview("pin · already moved") {
    VisitPinAdjustView(
        anchor: VisitPreviewFixtures.origin,
        accuracyM: 24,
        start: VisitPinAdjust.offset(VisitPreviewFixtures.origin, northM: 40, eastM: 25),
        onConfirm: { _ in },
        onCancel: {}
    )
}
#endif
