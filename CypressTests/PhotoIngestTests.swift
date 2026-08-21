import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Cypress

/// What happens to a photo binary between the shutter and the tree's timeline.
///
/// Three things that were not happening:
///
/// - the pixel size was never recorded, so `Photo.resolution` was 0 on every row and A3's
///   "ties broken by resolution" could not run (ERRATA E41);
/// - the record never reached a screen, because moderation gated the contributor's own device
///   (ERRATA E37);
/// - nothing stripped EXIF, on a path DECISIONS §3.10 requires it on (ERRATA E40).
@Suite("Photo ingest")
struct PhotoIngestTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000F1")!

    // MARK: - A photograph on disk, with a metadata sidecar to lose

    /// Something ImageIO would not do. Plain error rather than an expectation, because this runs
    /// inside a helper and a helper that fails should fail its caller, not record an issue of its
    /// own.
    struct FixtureFailure: Error { let what: String }

    /// Writes a real JPEG carrying EXIF, a GPS fix and TIFF camera identification — the shape of
    /// file a camera capture or a photo-library import actually hands over.
    @discardableResult
    static func writeJPEG(
        at url: URL,
        width: Int,
        height: Int,
        withLocation: Bool = true
    ) throws -> URL {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw FixtureFailure(what: "context") }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw FixtureFailure(what: "image") }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw FixtureFailure(what: "destination") }
        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2025:10:12 09:41:00",
                kCGImagePropertyExifLensModel: "iPhone 16 Pro back camera",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 16 Pro",
            ] as [CFString: Any],
        ]
        if withLocation {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.799005143246,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.443869066799,
                kCGImagePropertyGPSLongitudeRef: "W",
            ] as [CFString: Any]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureFailure(what: "finalize") }
        return url
    }

    private static func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-photo-ingest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func gpsDictionaryExists(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return properties[kCGImagePropertyGPSDictionary] != nil
    }

    // MARK: - The fixture is what it claims to be

    @Test("the fixture really writes a photo with EXIF and a GPS fix in it")
    func fixtureCarriesMetadata() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("with-exif.jpg")
        try Self.writeJPEG(at: file, width: 640, height: 480)

        #expect(PhotoBinary.carriesIdentifyingMetadata(atPath: file.path))
        #expect(Self.gpsDictionaryExists(at: file))
        let size = try #require(PhotoBinary.pixelSize(atPath: file.path))
        #expect(size.width == 640)
        #expect(size.height == 480)
    }

    @Test("a file that is not an image has no size and cannot be laundered into one")
    func nonImagesAreRefused() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notAnImage = directory.appendingPathComponent("notes.txt")
        try Data("this is not a photograph".utf8).write(to: notAnImage)

        #expect(PhotoBinary.pixelSize(atPath: notAnImage.path) == nil)
        #expect(PhotoBinary.pixelSize(atPath: directory.appendingPathComponent("absent.jpg").path) == nil)
        #expect(throws: (any Error).self) {
            try PhotoBinary.writeStrippingMetadata(
                from: notAnImage,
                to: directory.appendingPathComponent("out.jpg")
            )
        }
    }

    // MARK: - E40: the strip itself

    @Test("stripping drops EXIF and GPS and keeps the pixels")
    func strippingKeepsThePicture() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("in.jpg")
        let destination = directory.appendingPathComponent("out.jpg")
        try Self.writeJPEG(at: source, width: 320, height: 240)

        try PhotoBinary.writeStrippingMetadata(from: source, to: destination)

        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: destination.path))
        #expect(!Self.gpsDictionaryExists(at: destination))
        let size = try #require(PhotoBinary.pixelSize(atPath: destination.path))
        #expect(size.width == 320)
        #expect(size.height == 240)
    }

    // MARK: - The whole path, as a visit takes it

    @Test("a visit's photo reaches the timeline with its size, without its EXIF, and visible")
    func visitPhotoRoundTrip() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoDirectory = directory.appendingPathComponent("Photos", isDirectory: true)

        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))

        // No seed here, so the subject is a community add — the same path screen 02 takes when the
        // tree is not in the inventory.
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7761, longitude: -122.4464),
                photoLocalPath: "/tmp/cypress-photo-ingest-seed.jpg",
                attribution: Attribution.anonymous(deviceID: Self.deviceID)
            )
        )

        // `addTree` is one of spec §3.4's nine and now queues an `add_tree` row of its own,
        // in the transaction that adds the tree. This suite is not about that row, and every
        // queue count below would otherwise be counting the fixture. See
        // `OutboxTestSupport.discardFixtureRows`.
        try await OutboxTestSupport.discardFixtureRows(in: store)

        let staged = directory.appendingPathComponent("staged.jpg")
        try Self.writeJPEG(at: staged, width: 3024, height: 4032)

        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: Self.deviceID),
            note: "Fog dripping off the crown",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        _ = try await outbox.enqueue(
            .visit(visit),
            photos: [OutboxPhoto(path: staged.path, shotType: .fullTree)]
        )
        let report = try await outbox.drain()
        #expect(report.synced == 1, "the drain did not settle the visit: \(report)")

        let profile = try await api.treeProfile(id: tree.id)
        // `addTree` writes one photo of its own, and the visit adds a second.
        let stored = try #require(profile.photos.items.first { $0.visitID == visit.id })

        // E41: the size is on the record, so A3's tie-break has something to break a tie with.
        #expect(stored.width == 3024)
        #expect(stored.height == 4032)
        #expect(stored.resolution == 3024 * 4032)
        #expect(stored.storageKey != nil, "the binary phase did not complete")

        // E42: no location was stored. The tree's own pin is exact and public already; a photo
        // coordinate would be a second, independent record of where the contributor stood.
        #expect(stored.publicCoordinate == nil)

        // E40: the binary in the app's own directory carries no metadata sidecar.
        let landed = photoDirectory.appendingPathComponent("\(stored.id.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: landed.path))
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: landed.path))
        #expect(!Self.gpsDictionaryExists(at: landed))
        #expect(PhotoBinary.pixelSize(atPath: landed.path)?.width == 3024)
        #expect(!FileManager.default.fileExists(atPath: staged.path), "the staged copy was not cleared")

        // E37: it is `.pending`, because nothing moderated it — and it is on the screen anyway,
        // because this is the device that took it.
        #expect(stored.moderationState == .pending)
        #expect(profile.isOwnPhoto(stored))
        let presentation = TreeProfilePresentation(profile: profile)
        #expect(presentation.visiblePhotos.items.contains { $0.id == stored.id })
        #expect(presentation.publiclyVisiblePhotos.items.isEmpty)
        #expect(!presentation.isCold)
    }
}
