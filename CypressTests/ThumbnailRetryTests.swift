//
//  ThumbnailRetryTests.swift
//  CypressTests
//
//  ROADMAP 113, the follow-up to report F36. PR #206 let the full-screen viewer read a photograph
//  again after a failed read. A thumbnail (`PhotoImageStore.load`, which every `PhotoImage` calls)
//  still kept its first failure for the session and drew the placeholder until the app was killed.
//  These tests hold the thumbnail's retry and its limits.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Thumbnails · a failed read is tried again later, within limits (ROADMAP 113)")
@MainActor
struct ThumbnailRetryTests {

    /// Counts `photoData` calls. The calls never overlap: each test awaits one load before it
    /// starts the next, so no actor is needed. `@unchecked` records that.
    private final class Reads: @unchecked Sendable {
        var count = 0
    }

    /// A clock the test moves by hand.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    /// `photoData` fails on its first `failures` calls and answers on every later one.
    private struct PhotoFailsFirst: CypressAPI {
        let reads: Reads
        let failures: Int
        let bytes: Data

        func photoData(id: UUID) async throws -> Data {
            reads.count += 1
            if reads.count <= failures { throw APIError.serverError }
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

    private static func store(failures: Int, reads: Reads, clock: Clock) throws -> PhotoImageStore {
        PhotoImageStore(
            api: PhotoFailsFirst(reads: reads, failures: failures, bytes: try StoredPhotoPathTests.jpeg()),
            now: { clock.now }
        )
    }

    @Test("a thumbnail whose first read fails shows the photograph when it appears again later")
    func thumbnailRetriesAFailedRead() async throws {
        let reads = Reads()
        let clock = Clock()
        let store = try Self.store(failures: 1, reads: reads, clock: clock)
        let id = UUID()

        await store.load(id)
        #expect(store.image(id) == nil, "the first read fails by construction")
        #expect(store.isMissing(id))

        // The thumbnail appears again (a scroll, a screen opened again) after the retry interval.
        clock.advance(PhotoImageStore.thumbnailRetryInterval)
        await store.load(id)
        #expect(reads.count == 2, "the later appearance must ask for the bytes again")
        #expect(store.image(id) != nil, "and draw them when they arrive")
        #expect(!store.isMissing(id), "a row that read must not stay marked missing")
    }

    @Test("a thumbnail that never reads stops asking at the limit, and waits between asks")
    func thumbnailRetriesAreBounded() async throws {
        let reads = Reads()
        let clock = Clock()
        let store = try Self.store(failures: .max, reads: reads, clock: clock)
        let id = UUID()

        await store.load(id)
        // An appearance inside the interval (a fast scroll back) reads nothing.
        await store.load(id)
        #expect(reads.count == 1, "a retry inside the interval must not read")

        for _ in 0..<20 {
            clock.advance(PhotoImageStore.thumbnailRetryInterval)
            await store.load(id)
        }
        #expect(reads.count == PhotoImageStore.thumbnailReadLimit,
                "a lasting failure must stop at the limit, not read on every appearance")
        #expect(store.isMissing(id))
    }

    @Test("a deleted photograph is not read again by a thumbnail, however much time passes")
    func thumbnailDoesNotRetryADeletedPhotograph() async throws {
        let reads = Reads()
        let clock = Clock()
        let store = try Self.store(failures: 1, reads: reads, clock: clock)
        let id = UUID()

        await store.load(id)
        store.forget(id)
        clock.advance(PhotoImageStore.thumbnailRetryInterval * 10)
        await store.load(id)
        #expect(reads.count == 1, "only the read before the delete happened")
        #expect(store.image(id) == nil)
        #expect(store.isMissing(id))
    }

    @Test("a thumbnail whose read failed recovers when the viewer reads the same photograph")
    func viewerReadFillsTheThumbnail() async throws {
        let reads = Reads()
        let clock = Clock()
        let store = try Self.store(failures: 1, reads: reads, clock: clock)
        let id = UUID()

        await store.load(id)
        #expect(store.image(id) == nil, "the first read fails by construction")

        // The person taps the placeholder; the viewer reads the bytes. No time passes, so the
        // thumbnail's own retry has not come due.
        await store.loadViewer(id)
        #expect(reads.count == 2)
        #expect(store.image(id) != nil, "the thumbnail behind the viewer must draw the photograph")
    }
}
