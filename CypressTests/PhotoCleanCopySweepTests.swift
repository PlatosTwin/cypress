import Foundation
import Testing
@testable import Cypress

/// The sweep that removes the clean copies a killed photo strip leaves beside a photograph.
///
/// `PhotoBinary.stripMetadataInPlace` writes `.<name>-<UUID>.clean` beside the photo and renames it
/// over the photo. Its cleanup is a `defer`, which does not run when the app is killed during the
/// strip. `PhotoBinary.removeAbandonedCleanCopies` removes those copies, and must remove nothing
/// else and nothing a strip still in progress needs. Every case here runs on real files in a
/// temporary folder.
@Suite("Photo clean-copy sweep")
struct PhotoCleanCopySweepTests {

    private static func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-clean-sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @Test("a clean copy a killed strip left is removed, and so is its own scratch file")
    func aLeftoverIsRemoved() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let uuid = UUID().uuidString
        let leftover = directory.appendingPathComponent(".A1B2-full_tree.jpg-\(uuid).clean")
        let scratch = directory.appendingPathComponent(".A1B2-full_tree.jpg-\(uuid).clean.stripping")
        try PhotoIngestTests.writeJPEG(at: leftover, width: 8, height: 8, withLocation: false)
        try Data("half written".utf8).write(to: scratch)

        let removed = PhotoBinary.removeAbandonedCleanCopies(in: directory)

        #expect(!Self.exists(leftover), "the clean copy a killed strip left is still on the phone")
        #expect(!Self.exists(scratch), "the scratch file of a killed strip is still on the phone")
        #expect(Set(removed.map(\.lastPathComponent)) == [leftover.lastPathComponent, scratch.lastPathComponent])
    }

    @Test("the photographs themselves, and files whose names only look like a clean copy, are kept")
    func everythingElseIsKept() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let uuid = UUID().uuidString
        let photo = directory.appendingPathComponent("\(uuid).jpg")
        let staged = directory.appendingPathComponent("\(uuid)-trunk.jpg")
        try PhotoIngestTests.writeJPEG(at: photo, width: 8, height: 8)
        try PhotoIngestTests.writeJPEG(at: staged, width: 8, height: 8)
        let lookalikes = [
            "photo.jpg-\(uuid).clean",              // no leading dot
            ".photo.jpg-not-a-uuid.clean",          // no UUID
            ".photo.jpg\(uuid).clean",              // no hyphen before the UUID
            ".-\(uuid).clean",                      // no photo name
            ".photo.jpg-\(uuid).cleaner",           // a different ending
            ".photo.jpg-\(uuid).clean.jpg",         // a different ending
            ".photo.jpg-\(uuid).stripping",         // a scratch file that is not a clean copy's
            "\(uuid).jpg.stripping",                // the upload's scratch, not a strip in place
            ".DS_Store",
        ].map { directory.appendingPathComponent($0) }
        for file in lookalikes { try Data("keep me".utf8).write(to: file) }
        // A folder with exactly a clean copy's name is not a file a strip wrote.
        let folder = directory.appendingPathComponent(".photo.jpg-\(UUID().uuidString).clean", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let removed = PhotoBinary.removeAbandonedCleanCopies(in: directory)

        #expect(removed.isEmpty, "removed \(removed.map(\.lastPathComponent))")
        for file in [photo, staged, folder] + lookalikes {
            #expect(Self.exists(file), "\(file.lastPathComponent) was removed")
        }
    }

    @Test("a sweep that runs while a strip is in progress leaves the strip's copy, and the strip still finishes")
    func aStripInProgressIsNotBroken() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = try PhotoIngestTests.writeJPEG(
            at: directory.appendingPathComponent("photo.jpg"), width: 64, height: 48
        )
        #expect(PhotoBinary.carriesIdentifyingMetadata(atPath: photo.path), "fixture: the photo says where")

        var copyDuringStrip: URL?
        var removedDuringStrip: [URL] = []
        // The sweep runs at the one moment the strip is most exposed: its clean copy is written and
        // the rename that swaps it in has not happened yet.
        try PhotoBinary.stripMetadataInPlace(atPath: photo.path, rename: { from, to in
            copyDuringStrip = from
            removedDuringStrip = PhotoBinary.removeAbandonedCleanCopies(in: directory)
            try PhotoBinary.rename(from, to)
        })

        let copy = try #require(copyDuringStrip)
        #expect(PhotoBinary.cleanCopyName(of: copy.lastPathComponent) != nil, "fixture: the strip's copy has the swept shape")
        #expect(removedDuringStrip.isEmpty, "the sweep removed \(removedDuringStrip.map(\.lastPathComponent)) from a strip in progress")
        #expect(Self.exists(photo), "the photo is gone")
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: photo.path), "the strip did not finish: the photo still says where")
        #expect(PhotoBinary.pixelSize(atPath: photo.path).map { [$0.width, $0.height] } == [64, 48])

        // Once the strip is over, its name is free: a copy left under it now is a leftover.
        try Data("left".utf8).write(to: copy)
        #expect(PhotoBinary.removeAbandonedCleanCopies(in: directory).map(\.lastPathComponent) == [copy.lastPathComponent])
    }
}
