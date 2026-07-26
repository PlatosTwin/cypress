import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Cypress

/// What a photograph says about where it was taken, read off the bytes on disk (ERRATA E148).
///
/// **Why this suite exists next to `PhotoIngestTests`.** That suite already asserts that
/// `PhotoBinary.writeStrippingMetadata` drops the sidecar and that a *visit's* photograph reaches the
/// timeline without one. Both were true and both were beside the point for the community add, which
/// stages a capture and hands the staged path to `addTree` — no upload, no strip. The E148 leak lived
/// in the gap between "the strip works" and "the strip is on every path", and a suite organised around
/// the function cannot see that gap.
///
/// So every assertion here is on **a file, after a path**: the fixture goes through the API a capture
/// screen actually calls, and the output is opened with `CGImageSourceCopyPropertiesAtIndex` and asked
/// what it contains. Nothing here spies on `writeStrippingMetadata` being called, because a spy on the
/// call site passes for exactly as long as it takes somebody to add a second way in — which is the
/// bug, not a hypothetical about the bug.
///
/// **The other half is E142, and it is not decoration.** Stripping is easy if you are allowed to lose
/// orientation, and losing it turns every portrait photograph on its side in the hero, the browser and
/// the confirm well. So each test that asserts GPS is gone asserts in the same breath that
/// `kCGImagePropertyOrientation` survived, on a fixture that carries orientation 6. A fix for one of
/// these that breaks the other must fail here.
/// **The fixtures are deliberately small.** 600×800 is not a phone's frame, and nothing here needs one:
/// what is under test is a container rewrite, which is indifferent to how many pixels it copies. A
/// 12-megapixel fixture costs 48 MB of live bitmap per test in a host that already has the 103 MB seed
/// attached several times over, and buys no assertion.
@Suite("Photo metadata")
struct PhotoMetadataTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E1")!
    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    /// A corner of the Mission with nothing of ours on it; the seed is not attached in these tests.
    private static let fix = Coordinate(latitude: 37.7599, longitude: -122.4148)

    /// The GPS a phone standing in somebody's front garden would write. Deliberately a real,
    /// unrounded fix to five decimal places — about a metre — because the thing this suite is about is
    /// that D11's 25 m fuzz on the *pin* is worth nothing while this number ships in the file.
    private static let leakedLatitude = 37.759913
    private static let leakedLongitude = 122.414872

    /// Right-hand-rotated: what an iPhone writes for a portrait photograph. Landscape pixels plus a
    /// tag, which is why the tag has to survive (E142).
    private static let orientationRightTop = 6

    // MARK: - The fixture

    struct FixtureFailure: Error { let what: String }

    /// A JPEG that genuinely carries a GPS fix, a capture time, camera identification and an
    /// orientation tag — the shape of container `AVCapturePhoto.fileDataRepresentation()` and a
    /// photo-library import both hand over.
    ///
    /// Returned as `Data` rather than written to a URL because that is what the capture screens have:
    /// the leak was in what happened to bytes on their way to becoming a file, so a fixture that
    /// starts as a file would skip the step under test.
    static func cameraJPEG(
        width: Int = 400,
        height: Int = 300,
        withLocation: Bool = true,
        orientation: Int? = orientationRightTop
    ) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw FixtureFailure(what: "context") }
        context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.15, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw FixtureFailure(what: "image") }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw FixtureFailure(what: "destination") }

        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:25 09:41:00",
                kCGImagePropertyExifLensModel: "iPhone 16 Pro back camera 6.765mm f/1.78",
                kCGImagePropertyExifBodySerialNumber: "F2LX9QK1J3",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 16 Pro",
                kCGImagePropertyTIFFDateTime: "2026:07:25 09:41:00",
            ] as [CFString: Any],
            kCGImagePropertyMakerAppleDictionary: ["1": 12, "3": 61] as [String: Any],
        ]
        if withLocation {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: leakedLatitude,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: leakedLongitude,
                kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSTimeStamp: "16:41:00",
            ] as [CFString: Any]
        }
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureFailure(what: "finalize") }
        return output as Data
    }

    // MARK: - Reading a file back

    /// Everything a file says about itself, at the container level.
    private static func properties(ofFileAt path: String) throws -> [CFString: Any] {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FixtureFailure(what: "not an image container: \(path)")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw FixtureFailure(what: "no properties: \(path)")
        }
        return properties
    }

    private static func properties(of data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw FixtureFailure(what: "no properties in \(data.count) bytes") }
        return properties
    }

    /// Every key in the file, sub-dictionaries flattened as `GPS.Latitude`, sorted.
    ///
    /// This is what the failure messages print. A privacy assertion that says only `false` sends the
    /// next reader back to ImageIO's documentation to find out *what* leaked; one that names the keys
    /// tells them which path they broke.
    private static func keyPaths(_ properties: [CFString: Any]) -> [String] {
        var found: [String] = []
        for (key, value) in properties {
            let name = (key as String).replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
            if let nested = value as? [CFString: Any] {
                found += nested.keys.map { "\(name).\($0 as String)" }
            } else if let nested = value as? [String: Any] {
                found += nested.keys.map { "\(name).\($0)" }
            } else {
                found.append(name)
            }
        }
        return found.sorted()
    }

    /// The postcondition, stated once: nothing about where, when, or on what — and still the right
    /// way up.
    ///
    /// `PhotoBinary.carriesIdentifyingMetadata` is the app's own version of the first half and is
    /// asserted alongside, but the assertions here are on named keys rather than delegated to it: a
    /// leak that the shipping predicate has an opinion about is a leak two things agree on, and a
    /// privacy test whose only oracle is the code under test can be fixed by editing the oracle.
    private static func expectClean(
        _ properties: [CFString: Any],
        orientation expectedOrientation: Int?,
        _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let keys = keyPaths(properties)
        let where_ = "\(what) — keys present: \(keys.joined(separator: ", "))"

        #expect(
            properties[kCGImagePropertyGPSDictionary] == nil,
            "\(where_): the GPS dictionary survived, so the file still says where the photographer stood",
            sourceLocation: sourceLocation
        )
        #expect(
            properties[kCGImagePropertyMakerAppleDictionary] == nil,
            "\(where_): the Apple maker note survived", sourceLocation: sourceLocation
        )
        #expect(
            properties[kCGImagePropertyIPTCDictionary] == nil,
            "\(where_): the IPTC dictionary survived", sourceLocation: sourceLocation
        )
        #expect(
            properties[kCGImagePropertyExifAuxDictionary] == nil,
            "\(where_): the Exif Aux dictionary survived", sourceLocation: sourceLocation
        )

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        for key in [
            kCGImagePropertyExifDateTimeOriginal,
            kCGImagePropertyExifLensModel,
            kCGImagePropertyExifBodySerialNumber,
        ] {
            #expect(
                exif[key] == nil,
                "\(where_): Exif.\(key as String) survived", sourceLocation: sourceLocation
            )
        }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFDateTime] {
            #expect(
                tiff[key] == nil,
                "\(where_): TIFF.\(key as String) survived", sourceLocation: sourceLocation
            )
        }

        // No coordinate anywhere in the file, under any key. The loop above names the containers this
        // app knows about; this catches a number that arrived in one it does not.
        let flattened = String(describing: properties)
        #expect(
            !flattened.contains("37.759"),
            "\(where_): the latitude is still somewhere in the file",
            sourceLocation: sourceLocation
        )

        // E142, in the same breath, because a strip that loses this is not a fix.
        if let expectedOrientation {
            #expect(
                (properties[kCGImagePropertyOrientation] as? Int) == expectedOrientation,
                """
                \(where_): orientation is \
                \(String(describing: properties[kCGImagePropertyOrientation])) and not \
                \(expectedOrientation) — E142: a portrait photograph is landscape pixels plus this \
                tag, and every hero, browser row and confirm well draws it on its side without it
                """,
                sourceLocation: sourceLocation
            )
        }
    }

    static func probeKeys(atPath path: String) throws -> [String] {
        keyPaths(try properties(ofFileAt: path))
    }

    private static func removeStaged(_ path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    // MARK: - The fixture is what it claims to be

    /// Without this, every test below is a test that proves nothing: an assertion that a file has no
    /// GPS passes trivially against a fixture that never had any.
    @Test("the fixture carries a real GPS fix, camera identification and an orientation tag")
    func fixtureLeaksEverything() throws {
        let properties = try Self.properties(of: try Self.cameraJPEG())
        let keys = Self.keyPaths(properties)

        let gps = try #require(
            properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            "fixture has no GPS dictionary; keys: \(keys.joined(separator: ", "))"
        )
        // Within a metre of what was written, not equal to it: EXIF stores a coordinate as three
        // rationals, so 37.759913 comes back 37.75991333… — which is the point. A tenth of a
        // thousandth of a degree is about 11 cm, and that is what the file is carrying.
        let latitude = try #require(gps[kCGImagePropertyGPSLatitude] as? Double)
        #expect(abs(latitude - Self.leakedLatitude) < 0.00001)
        #expect(properties[kCGImagePropertyMakerAppleDictionary] != nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int) == Self.orientationRightTop)

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect((tiff[kCGImagePropertyTIFFModel] as? String) == "iPhone 16 Pro")
    }

    // MARK: - The staging funnel, which is what both capture screens call

    @Test("a staged capture has lost its GPS and kept which way up it goes")
    func stagingStrips() throws {
        let staged = try VisitPhotoStaging.write(try Self.cameraJPEG(), for: UUID(), shotType: .fullTree)
        defer { Self.removeStaged(staged) }

        let properties = try Self.properties(ofFileAt: staged)
        Self.expectClean(properties, orientation: Self.orientationRightTop, "the staged file")
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: staged))

        // The pixels came across untouched — a container rewrite, not a re-encode.
        let size = try #require(PhotoBinary.pixelSize(atPath: staged))
        #expect(size.width == 400)
        #expect(size.height == 300)
    }

    /// An upright photograph takes the one-pass route through `writeStrippingMetadata` (there is
    /// nothing to put back), so it is a different code path and gets its own file on disk.
    @Test("an upright capture is staged clean too, by the shorter route")
    func stagingStripsAnUprightCapture() throws {
        let staged = try VisitPhotoStaging.write(
            try Self.cameraJPEG(orientation: nil), for: UUID(), shotType: .fullTree
        )
        defer { Self.removeStaged(staged) }

        Self.expectClean(try Self.properties(ofFileAt: staged), orientation: nil, "the staged file")
    }

    /// **The new staging path gets the same coverage as the old one (ERRATA E152).**
    ///
    /// One session now stages three files instead of one, and the framing is what tells them apart. The
    /// risk this covers is the obvious one and it would be silent: if all three still resolved to one
    /// path, the third capture would overwrite the first two and every existing assertion here would
    /// still pass, because each one only ever looks at the file it was just handed. So this asserts on
    /// **all three files at once, after all three writes** — which is the only order in which an
    /// overwrite is visible — and it asserts the strip on each of them, so no framing can reach disk by a
    /// route that skips `PhotoBinary.write`.
    @Test("all three framings of one visit are staged, distinct, and each one clean")
    func stagingKeepsThreeFramingsApartAndStripsEachOne() throws {
        let visitID = UUID()
        let framings: [ShotType] = [.fullTree, .trunk, .leaf]

        // Three different photographs, distinguishable by their pixel dimensions — so "the leaf shot
        // overwrote the full-tree shot" is a readable failure rather than three identical passes.
        let sizes: [ShotType: (width: Int, height: Int)] = [
            .fullTree: (400, 300), .trunk: (600, 800), .leaf: (240, 240)
        ]

        var staged: [ShotType: String] = [:]
        for framing in framings {
            let size = sizes[framing]!
            staged[framing] = try VisitPhotoStaging.write(
                try Self.cameraJPEG(width: size.width, height: size.height),
                for: visitID,
                shotType: framing
            )
        }
        defer { staged.values.forEach(Self.removeStaged) }

        // Three files, not one wearing three names.
        #expect(
            Set(staged.values).count == 3,
            "the three framings share a path, so two photographs were overwritten: \(staged)"
        )

        for framing in framings {
            let path = try #require(staged[framing])
            #expect(
                FileManager.default.fileExists(atPath: path),
                "the \(framing.rawValue) file is gone — a later capture removed it"
            )
            // Still the photograph it was written from, after the other two were written.
            let size = try #require(
                PhotoBinary.pixelSize(atPath: path),
                "the \(framing.rawValue) file is not readable as an image"
            )
            let expected = sizes[framing]!
            let complaint = "the \(framing.rawValue) file is \(size.width)×\(size.height), expected "
                + "\(expected.width)×\(expected.height) — it was overwritten by another framing"
            #expect(size.width == expected.width && size.height == expected.height, "\(complaint)")
            // E148 holds on every one of them, not just on whichever went last.
            Self.expectClean(
                try Self.properties(ofFileAt: path),
                orientation: Self.orientationRightTop,
                "the staged \(framing.rawValue) file"
            )
            #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: path))
        }
    }

    /// A retake replaces its own framing and leaves the others alone — the other half of the filename
    /// decision. If the name carried a counter or a fresh id instead, this would leave an orphan behind
    /// in a directory iCloud backs up.
    @Test("retaking one framing overwrites that framing and nothing else")
    func stagingRetakeReplacesOnlyItsOwnFraming() throws {
        let visitID = UUID()
        let trunk = try VisitPhotoStaging.write(
            try Self.cameraJPEG(width: 600, height: 800), for: visitID, shotType: .trunk
        )
        let fullTree = try VisitPhotoStaging.write(
            try Self.cameraJPEG(width: 400, height: 300), for: visitID, shotType: .fullTree
        )
        defer { [trunk, fullTree].forEach(Self.removeStaged) }

        let retaken = try VisitPhotoStaging.write(
            try Self.cameraJPEG(width: 240, height: 240), for: visitID, shotType: .trunk
        )
        #expect(retaken == trunk, "a retake of the trunk went to a new path, orphaning the first file")

        let trunkSize = try #require(PhotoBinary.pixelSize(atPath: trunk))
        #expect(trunkSize.width == 240 && trunkSize.height == 240, "the retake did not replace the trunk")

        let fullTreeSize = try #require(PhotoBinary.pixelSize(atPath: fullTree))
        #expect(
            fullTreeSize.width == 400 && fullTreeSize.height == 300,
            "retaking the trunk destroyed the full-tree photograph"
        )
        Self.expectClean(
            try Self.properties(ofFileAt: trunk),
            orientation: Self.orientationRightTop,
            "the retaken trunk file"
        )
    }

    /// The refusal, and why it is a refusal. Both capture screens turn this throw into "that photo
    /// could not be saved to this phone" with the CTA still disabled, which is a state a contributor
    /// answers by retaking — the alternative, writing the bytes down unexamined, is the leak.
    @Test("bytes that are not a container are not staged at all")
    func stagingRefusesWhatItCannotRewrite() throws {
        let visitID = UUID()
        #expect(throws: (any Error).self) {
            try VisitPhotoStaging.write(
                Data("this is not a photograph".utf8), for: visitID, shotType: .fullTree
            )
        }
        let url = try VisitPhotoStaging.url(for: visitID, shotType: .fullTree)
        #expect(
            !FileManager.default.fileExists(atPath: url.path),
            "the refused bytes were left on disk anyway"
        )
    }

    // MARK: - The community add, end to end, which is the path that leaked

    /// The whole of E148 in one test: the screen's own photo entry point, the real staging directory,
    /// `addTree`, and then the file that `photos.local_path` points at.
    ///
    /// `useLibraryImage` is not a test seam — it is BUILD-PLAN §9's camera-denied fallback and the
    /// only photo path a simulator can take, and it reaches `apply(imageData:)`, which is exactly what
    /// the shutter reaches. The bytes travel the same way a capture's do.
    @MainActor
    @Test("a community add's photograph is on disk without the garden's coordinates in it")
    func communityAddStripsThePhotograph() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e148-\(UUID().uuidString)", isDirectory: true)
        let api = LocalAPI(
            store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory
        )
        defer { try? FileManager.default.removeItem(at: photoDirectory) }

        let subject = VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(Self.fix, accuracyM: 8)),
            attribution: Self.attribution
        )
        subject.useLibraryImage(try Self.cameraJPEG(width: 600, height: 800))

        let staged = try #require(subject.photoPath, "the capture was not staged: \(subject.phase)")
        defer { Self.removeStaged(staged) }
        let treeID = try #require(await subject.add(), "the add was refused: \(subject.phase)")

        // The row's own file, which for a community add is where the photograph lives for good:
        // `addTree` never uploads, so `local_path` is never cleared and nothing else ever rewrites it.
        let profile = try await api.treeProfile(id: treeID)
        let photo = try #require(profile.photos.items.first)
        #expect(photo.storageKey == nil, "a community add's photo was uploaded after all")

        Self.expectClean(
            try Self.properties(ofFileAt: staged),
            orientation: Self.orientationRightTop,
            "the file photos.local_path points at"
        )

        // And the same bytes as the app itself serves them, which is the other way a copy escapes:
        // this is what `PhotoImageStore` reads and what a share sheet would one day be handed.
        Self.expectClean(
            try Self.properties(of: try await api.photoData(id: photo.id)),
            orientation: Self.orientationRightTop,
            "the bytes photoData serves"
        )
    }

    /// The backstop, and the reason it is at the boundary rather than on the screen: a path that
    /// stages its own bytes without going through `VisitPhotoStaging` still cannot get a coordinate
    /// into a `photos` row. This is the E148 bug reconstructed — a raw camera file written straight to
    /// a path and handed to `addTree` — and it must now come out clean.
    @Test("addTree cleans a photograph that reached it by some other route")
    func addTreeIsTheBackstop() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let raw = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e148-raw-\(UUID().uuidString).jpg")
        try Self.cameraJPEG().write(to: raw, options: .atomic)
        defer { try? FileManager.default.removeItem(at: raw) }
        #expect(
            PhotoBinary.carriesIdentifyingMetadata(atPath: raw.path),
            "fixture: the bypassing file was already clean, so this proves nothing"
        )

        _ = try await api.addTree(
            TreeDraft(
                coordinate: Self.fix,
                photoLocalPath: raw.path,
                attribution: Self.attribution
            )
        )

        Self.expectClean(
            try Self.properties(ofFileAt: raw.path),
            orientation: Self.orientationRightTop,
            "the file a bypassing caller handed to addTree"
        )
    }

    // MARK: - The check-in path, all the way through the outbox

    /// The path the task's brief did not accuse, checked rather than assumed. It was *eventually*
    /// clean before E148 — `uploadPhoto` strips on the way into the photo directory — but it staged
    /// the camera's bytes in Application Support first and served them from `local_path` for as long
    /// as the drain took or failed for. Now both ends are clean, and the orientation survives two
    /// consecutive rewrites, which is the thing E142 would notice.
    @Test("a check-in photograph is clean when staged and still clean when landed")
    func checkInStripsAtBothEnds() async throws {
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e148-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }

        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        let subjectPhoto = try VisitPhotoStaging.write(
            try Self.cameraJPEG(), for: UUID(), shotType: .fullTree
        )
        defer { Self.removeStaged(subjectPhoto) }
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Self.fix,
                photoLocalPath: subjectPhoto,
                attribution: Self.attribution
            )
        )

        // What `VisitCameraModel.apply(imageData:)` does with a capture, byte for byte.
        let visitID = UUID()
        let staged = try VisitPhotoStaging.write(
            try Self.cameraJPEG(width: 600, height: 800), for: visitID, shotType: .fullTree
        )
        defer { Self.removeStaged(staged) }
        Self.expectClean(
            try Self.properties(ofFileAt: staged),
            orientation: Self.orientationRightTop,
            "the staged check-in capture"
        )

        let visit = Visit(
            id: visitID,
            treeID: tree.id,
            attribution: Self.attribution,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        _ = try await outbox.enqueue(
            .visit(visit), photos: [OutboxPhoto(path: staged, shotType: .fullTree)]
        )
        let report = try await outbox.drain()
        #expect(report.synced == 1, "the drain did not settle the visit: \(report)")

        let profile = try await api.treeProfile(id: tree.id)
        let stored = try #require(profile.photos.items.first { $0.visitID == visit.id })
        let key = try #require(stored.storageKey, "the binary phase did not complete")
        let landed = photoDirectory.appendingPathComponent(key)

        Self.expectClean(
            try Self.properties(ofFileAt: landed.path),
            orientation: Self.orientationRightTop,
            "the file in the app's photo directory"
        )
        // E41's columns still land, so the second rewrite has not cost the record its dimensions.
        #expect(stored.width == 600)
        #expect(stored.height == 800)
    }
}
