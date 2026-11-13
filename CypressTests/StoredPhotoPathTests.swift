//
//  StoredPhotoPathTests.swift
//  CypressTests
//
//  Report F36: a tester's own photograph would not open after an app update ("That photograph
//  could not be opened"). The row stored an absolute path into the app's data container; the update
//  moved the container, so the stored prefix named a folder that no longer existed, though the file
//  itself had moved with it. These tests stand up a fake container, store a path into it, move it
//  the way an update does, and read the photograph back.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Cypress

@Suite("Stored photo paths · a container move does not lose the photograph (F36)")
struct StoredPhotoPathTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000F036")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    /// One fake installation: a container before the update (`before`), the path the same
    /// container will have after it (`after`), and a staged capture inside `before`.
    private struct Container {
        let root: URL
        let before: URL
        let after: URL
        let staged: URL

        var applicationSupportAfter: URL {
            after.appendingPathComponent("Library/Application Support", isDirectory: true)
        }

        /// What an app update does to the data container: the same files, a new path.
        func move() throws {
            try FileManager.default.moveItem(at: before, to: after)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private static func container(bytes: Data) throws -> Container {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-f36-\(UUID().uuidString)", isDirectory: true)
        let before = root.appendingPathComponent("Application/\(UUID().uuidString)", isDirectory: true)
        let after = root.appendingPathComponent("Application/\(UUID().uuidString)", isDirectory: true)
        let captures = before.appendingPathComponent(
            "Library/Application Support/VisitCaptures", isDirectory: true
        )
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: after.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let staged = captures.appendingPathComponent("\(UUID().uuidString)-full_tree.jpg")
        try bytes.write(to: staged)
        return Container(root: root, before: before, after: after, staged: staged)
    }

    private static func api(for container: Container) async throws -> LocalAPI {
        let store = try await CypressStore.inMemory()
        return LocalAPI(
            store: store,
            deviceID: deviceID,
            photoDirectory: container.root.appendingPathComponent("Photos", isDirectory: true),
            applicationSupportDirectory: container.applicationSupportAfter,
            now: { moment }
        )
    }

    static func jpeg(width: Int = 40, height: Int = 60) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    // MARK: - Through the API

    @Test("a tree you added still shows its photograph after an update moves the container")
    func addedTreePhotoSurvivesAContainerMove() async throws {
        let bytes = try Self.jpeg()
        let container = try Self.container(bytes: bytes)
        defer { container.remove() }
        let api = try await Self.api(for: container)

        // The flow behind the report: an add-tree photograph is never uploaded, so its row keeps
        // `local_path` (an absolute path into the container) for the life of the installation.
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: container.staged.path,
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let profile = try await api.treeProfile(id: tree.id)
        let photoID = try #require(profile.photos.items.first?.id)

        try container.move()
        #expect(!FileManager.default.fileExists(atPath: container.staged.path),
                "the fixture must leave the stored path pointing at nothing")

        let data = try await api.photoData(id: photoID)
        #expect(data == bytes, "the bytes moved with the container and must be found there")
    }

    @Test("a photo queued before an update still uploads after it, instead of being dropped")
    func queuedPhotoSurvivesAContainerMove() async throws {
        let bytes = try Self.jpeg()
        let container = try Self.container(bytes: bytes)
        defer { container.remove() }
        let api = try await Self.api(for: container)

        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/nonexistent/cypress-f36-tree.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        // A check-in photograph waiting in the outbox: its path was recorded before the update.
        let ticket = try await api.beginPhotoUpload(PhotoUploadRequest(
            treeID: tree.id,
            shotType: .trunk,
            localPath: container.staged.path,
            capturedAt: Self.moment
        ))

        try container.move()

        try await api.uploadPhoto(at: container.staged.path, ticket: ticket)
        #expect(FileManager.default.fileExists(atPath: ticket.destination.path),
                "the upload must move the moved file into the photo directory")
        let data = try await api.photoData(id: ticket.photoID)
        #expect(PhotoImageStore.downsample(data, maximumEdge: 200) != nil)
    }

    // MARK: - The resolver itself

    @Test("the part after Application Support is re-rooted onto the current folder")
    func reroots() throws {
        let stored = "/Users/someone/Library/Developer/CoreSimulator/Devices/X/data/Containers/Data/"
            + "Application/OLD/Library/Application Support/VisitCaptures/a-full_tree.jpg"
        let now = URL(fileURLWithPath: "/new/Library/Application Support", isDirectory: true)
        let rerooted = try #require(StoredPhotoPath.rerooted(stored, onto: now))
        #expect(rerooted.path == "/new/Library/Application Support/VisitCaptures/a-full_tree.jpg")
    }

    @Test("a path that climbs with .. is refused, so a stored string cannot leave the folder")
    func refusesTraversal() {
        let stored = "/old/Library/Application Support/../../etc/passwd"
        let now = URL(fileURLWithPath: "/new/Library/Application Support", isDirectory: true)
        #expect(StoredPhotoPath.rerooted(stored, onto: now) == nil)
    }

    @Test("a path outside Application Support is returned unchanged")
    func leavesOtherPathsAlone() {
        let stored = "/tmp/cypress-f36-somewhere-else.jpg"
        let now = URL(fileURLWithPath: "/new/Library/Application Support", isDirectory: true)
        #expect(StoredPhotoPath.rerooted(stored, onto: now) == nil)
        #expect(StoredPhotoPath.resolve(stored, applicationSupport: now).path == stored)
    }

    // MARK: - The viewer's cache

    private final class Attempts: @unchecked Sendable {
        var photoData = 0
    }

    /// `photoData` fails on its first call and answers on every later one, as a network blip or a
    /// file found after a fix would. Every access is from the `@MainActor` store, so the counter is
    /// only touched on one thread; `@unchecked` records that, as `FailedReadTests.FailsOnce` does.
    private struct PhotoFailsOnce: CypressAPI {
        let attempts: Attempts
        let bytes: Data

        func photoData(id: UUID) async throws -> Data {
            attempts.photoData += 1
            if attempts.photoData == 1 { throw APIError.serverError }
            return bytes
        }

        func groveSpecies() async throws -> GroveSpecies { .empty }
        func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac { .empty }
        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
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

    @Test("the viewer tries again when it opens again, after one failed read")
    @MainActor
    func viewerRetriesAFailedRead() async throws {
        let attempts = Attempts()
        let store = PhotoImageStore(api: PhotoFailsOnce(attempts: attempts, bytes: try Self.jpeg()))
        let id = UUID()

        await store.loadViewer(id)
        #expect(store.viewerImage(id) == nil, "the first read fails by construction")

        // The viewer closes and opens again.
        store.releaseViewer()
        await store.loadViewer(id)
        #expect(attempts.photoData == 2, "the second opening must ask for the bytes again")
        #expect(store.viewerImage(id) != nil, "and draw them when they arrive")
        #expect(!store.isMissing(id), "a row that read must not stay marked missing")
    }

    @Test("a deleted photograph is not read again, however often the viewer opens")
    @MainActor
    func viewerDoesNotRetryADeletedPhotograph() async throws {
        let attempts = Attempts()
        let store = PhotoImageStore(api: PhotoFailsOnce(attempts: attempts, bytes: try Self.jpeg()))
        let id = UUID()

        store.forget(id)
        await store.loadViewer(id)
        await store.loadViewer(id)
        #expect(attempts.photoData == 0)
        #expect(store.viewerImage(id) == nil)
        #expect(store.isMissing(id))
    }
}
