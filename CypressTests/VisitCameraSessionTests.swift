//
//  VisitCameraSessionTests.swift
//  CypressTests
//
//  One camera session takes a full tree, a trunk and a leaf (ERRATA E150), and the way back to the map
//  is a destination rather than a number of chevrons (ERRATA E149).
//
//  ── What these tests are for, and what they deliberately do not do ────────────────────────────
//  The defect being guarded is **silent data loss**. Three shots used to be one `OutboxPhoto?` written
//  to one path, `<visitID>.jpg`, so the third capture removed the destination and moved itself on top
//  of the first two — and nothing reads a staged file between the shutter and the drain, so there was
//  no moment at which a contributor could have noticed. A test that watched `stage(_:)` being called
//  would have been green against that bug for the whole of its life.
//
//  So every assertion here is on **state after all three captures**, and the round-trip test asserts on
//  the `photos` rows and the files in the photo directory after a real drain. Nothing spies on a call.
//
//  The three fixtures are different *sizes* rather than different colours, because a size can be read
//  back off a file with `PhotoBinary.pixelSize` without decoding it — so "the leaf shot overwrote the
//  full tree" is a readable failure rather than three passes on three identical images.
//

#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Screen 04 · one session, three framings, and the way home")
struct VisitCameraSessionTests {

    // MARK: - Fixtures

    /// The pixel size each framing's fixture is written at, so a file can be identified by measuring it.
    static let sizes: [ShotType: (width: Int, height: Int)] = [
        .fullTree: (400, 600),
        .trunk: (300, 300),
        .leaf: (240, 180),
    ]

    static func jpeg(_ shotType: ShotType) throws -> Data {
        let size = try #require(sizes[shotType])
        return try jpeg(width: size.width, height: size.height)
    }

    static func jpeg(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage(),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    /// A camera model over the preview API. `load()` is never called — it would start a capture session
    /// — and it does not need to be: `useLibraryImage` is BUILD-PLAN §9's camera-denied fallback and it
    /// reaches `apply(imageData:)`, which is exactly what the shutter reaches.
    static func model(
        treeID: UUID = VisitPreviewFixtures.cypress.id,
        outbox: OutboxQueue = VisitPreviewFixtures.outbox()
    ) -> VisitCameraModel {
        VisitCameraModel(
            treeID: treeID,
            treeDisplayName: "Grandmother Cypress",
            gpsAccuracyM: 9,
            api: VisitPreviewAPI(),
            outbox: outbox,
            attribution: VisitPreviewFixtures.attribution
        )
    }

    /// A camera model whose outbox can actually be **written** to.
    ///
    /// `VisitPreviewFixtures.outbox()` is deliberately *unmigrated* — "the previews draw the screens,
    /// they do not save from them" — so a `logVisit()` over it fails on `no such table: outbox` and
    /// returns nil. Two tests here save without going near `LocalAPI`, and they were reading that as a
    /// refusal of the framings under test.
    static func savingModel(treeID: UUID = VisitPreviewFixtures.cypress.id) async throws -> VisitCameraModel {
        model(treeID: treeID, outbox: try await VisitPreviewFixtures.migratedOutbox())
    }

    /// Takes one photograph of each framing, in the order the chips are drawn, exactly as a contributor
    /// would: select the chip, then press the shutter.
    static func shootAll(_ model: VisitCameraModel, _ framings: [ShotType] = [.fullTree, .trunk, .leaf]) throws {
        for framing in framings {
            model.shotType = framing
            model.useLibraryImage(try jpeg(framing))
        }
    }

    static func removeStaged(_ paths: [String]) {
        for path in paths { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path)) }
    }

    // MARK: - 1 · Three framings survive one session

    @Test("three shots in one session are three photographs, not the last one three times")
    func threeShotsStayThreePhotographs() throws {
        let model = Self.model()
        try Self.shootAll(model)
        defer { Self.removeStaged(model.draft.photoPaths) }

        #expect(model.capturedCount == 3, "the session holds \(model.capturedCount) photographs")
        #expect(model.capturedShotTypes == Set([.fullTree, .trunk, .leaf]))
        #expect(Set(model.draft.photoPaths).count == 3, "two framings share a path: \(model.draft.photoPaths)")

        // Each file is still the photograph it was written from, *after* the other two were written.
        // This is the assertion the old code fails: all three paths were equal, so all three measured
        // 240×180 and only the leaf survived.
        for framing in [ShotType.fullTree, .trunk, .leaf] {
            let photo = try #require(model.draft.photo(shotType: framing), "no \(framing.rawValue) photograph")
            let size = try #require(PhotoBinary.pixelSize(atPath: photo.path), "\(framing.rawValue) unreadable")
            let expected = try #require(Self.sizes[framing])
            let complaint = "the \(framing.rawValue) photograph is \(size.width)×\(size.height), "
                + "expected \(expected.width)×\(expected.height) — another framing overwrote it"
            #expect(size.width == expected.width && size.height == expected.height, "\(complaint)")
        }
    }

    @Test("the viewfinder shows the photograph of the framing selected, and the camera for the others")
    func theViewfinderFollowsTheSelectedFraming() throws {
        let model = Self.model()
        model.shotType = .fullTree
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }

        #expect(model.hasSnapped, "the full tree was photographed")
        #expect(model.snapshot != nil)

        // Choosing an unphotographed framing must open the camera again — not show the tree you already
        // took. This is the whole of "without having to leave and come back".
        model.shotType = .trunk
        #expect(!model.hasSnapped, "selecting Trunk showed the full-tree photograph instead of the camera")
        #expect(model.snapshot == nil)
        #expect(model.canLogVisit, "the full-tree photograph is still saveable while Trunk is selected")

        model.shotType = .fullTree
        #expect(model.hasSnapped, "going back to Full tree lost the photograph that was taken for it")
    }

    // MARK: - 2 · Two of three is a complete contribution

    /// The decision, asserted rather than described: a contributor who takes two and stops gets a saved
    /// visit carrying two photographs. Not a draft, not a refusal, and nothing discarded.
    @Test("two of three saves as two photographs")
    func twoOfThreeIsStorable() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e150-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let api = LocalAPI(store: store, deviceID: UUID(), photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7599, longitude: -122.4269),
                photoLocalPath: try VisitPhotoStaging.write(
                    try Self.jpeg(width: 32, height: 32), for: UUID(), shotType: .fullTree
                ),
                attribution: VisitPreviewFixtures.attribution
            )
        )

        let model = Self.model(treeID: tree.id, outbox: outbox)
        try Self.shootAll(model, [.fullTree, .leaf])
        defer { Self.removeStaged(model.draft.photoPaths) }

        #expect(model.canLogVisit, "two of three was refused")
        let receipt = try #require(await model.logVisit(), "a two-photograph visit would not save")
        #expect(receipt.item.photos.count == 2, "the row carried \(receipt.item.photos.count) binaries")

        // Both reached the record with their own framing. The tree already had the community add's
        // photograph on it, so the two here are counted by shot type rather than by total.
        let photos = try await api.treeProfile(id: tree.id).photos.items
        let visitPhotos = photos.filter { $0.visitID == receipt.visit.id }
        #expect(visitPhotos.count == 2, "the visit landed \(visitPhotos.count) photographs, expected 2")
        #expect(
            Set(visitPhotos.map(\.shotType)) == Set([.fullTree, .leaf]),
            "the framings did not survive: \(visitPhotos.map(\.shotType.rawValue))"
        )
        #expect(
            !visitPhotos.contains { $0.shotType == .trunk },
            "a trunk photograph was invented for a framing nobody photographed"
        )
    }

    // MARK: - 3 · The whole path, through a real drain

    /// The proof that the third photograph does not overwrite the first two **anywhere on the path**:
    /// three captures, one outbox row, a real drain, three `photos` rows, three distinct storage keys,
    /// and three files in the photo directory.
    ///
    /// `storageKey` is the load-bearing one. Each binary gets its own `beginPhotoUpload`, so its own
    /// photo id, so its own `<photoID>.jpg` destination — and if the three staged paths had collided,
    /// the second upload would have found its source already moved and failed `notFound`.
    @Test("three photographs round-trip to three stored files")
    func threePhotographsRoundTrip() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-e150-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let api = LocalAPI(store: store, deviceID: UUID(), photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7601, longitude: -122.4271),
                photoLocalPath: try VisitPhotoStaging.write(
                    try Self.jpeg(width: 32, height: 32), for: UUID(), shotType: .fullTree
                ),
                attribution: VisitPreviewFixtures.attribution
            )
        )

        let model = Self.model(treeID: tree.id, outbox: outbox)
        try Self.shootAll(model)
        let stagedPaths = model.draft.photoPaths
        defer { Self.removeStaged(stagedPaths) }

        let receipt = try #require(await model.logVisit())
        #expect(receipt.item.photos.count == 3)

        // One row for the visit, carrying three binaries — not three rows.
        let payload = try OutboxPayload.decode(kind: receipt.item.kind, from: receipt.item.payload)
        guard case .visit = payload else {
            Issue.record("the row is not a visit")
            return
        }

        _ = try await outbox.drain()

        let visitPhotos = try await api.treeProfile(id: tree.id).photos.items
            .filter { $0.visitID == receipt.visit.id }
        #expect(visitPhotos.count == 3, "the drain landed \(visitPhotos.count) photographs, expected 3")
        #expect(Set(visitPhotos.map(\.shotType)) == Set([.fullTree, .trunk, .leaf]))

        let storageKeys = visitPhotos.compactMap(\.storageKey)
        #expect(storageKeys.count == 3, "a photograph was not uploaded: \(visitPhotos.map(\.storageKey))")
        #expect(Set(storageKeys).count == 3, "two photographs share a stored file: \(storageKeys)")

        // Three files really on disk, each still the size it was photographed at, and each one still
        // clean — the strip runs again on the way in, and it must not have lost the framings' identity.
        for photo in visitPhotos {
            let key = try #require(photo.storageKey)
            let url = photoDirectory.appendingPathComponent((key as NSString).lastPathComponent)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(photo.shotType.rawValue) has no file")
            let size = try #require(PhotoBinary.pixelSize(atPath: url.path))
            let expected = try #require(Self.sizes[photo.shotType])
            let complaint = "the stored \(photo.shotType.rawValue) file is "
                + "\(size.width)×\(size.height), expected \(expected.width)×\(expected.height)"
            #expect(size.width == expected.width && size.height == expected.height, "\(complaint)")
        }

        // Staging is empty again: `uploadPhoto` moves, it does not copy.
        for path in stagedPaths {
            #expect(
                !FileManager.default.fileExists(atPath: path),
                "a staged binary was left behind after the drain: \(path)"
            )
        }
    }

    // MARK: - 4 · Retake, and the framing being frozen at the shutter

    @Test("retaking one framing leaves the others alone")
    func retakeIsPerFraming() throws {
        let model = Self.model()
        try Self.shootAll(model)
        defer { Self.removeStaged(model.draft.photoPaths) }

        let fullTreeBefore = try #require(model.draft.photo(shotType: .fullTree))
        model.shotType = .trunk
        model.retake()

        #expect(model.capturedCount == 2, "retaking the trunk removed \(3 - model.capturedCount) photographs")
        #expect(!model.hasSnapped, "the trunk is back to the viewfinder")
        #expect(model.draft.photo(shotType: .trunk) == nil)
        #expect(model.draft.photo(shotType: .fullTree) == fullTreeBefore, "the full tree was disturbed")
        #expect(model.draft.photo(shotType: .leaf) != nil, "the leaf was disturbed")

        // And the replacement goes back into the same slot rather than becoming a fourth photograph.
        model.useLibraryImage(try Self.jpeg(width: 120, height: 90))
        #expect(model.capturedCount == 3)
        #expect(model.draft.photo(shotType: .trunk)?.path == fullTreeBefore.path.replacingOccurrences(
            of: ShotType.fullTree.rawValue, with: ShotType.trunk.rawValue
        ), "the retake did not reuse the trunk's own path")
    }

    /// The framing is decided at the shutter, not at "Log visit".
    ///
    /// It used to be re-read on save — reasonable when a visit held one photograph, and destructive with
    /// three, because it would relabel every staged photograph as whichever chip happened to be selected
    /// when the button was pressed. The file on disk is named after the framing, so a relabel would also
    /// make the row and the file disagree about which photograph they are.
    @Test("leaving a different chip selected does not relabel the photographs")
    func theFramingIsFrozenAtTheShutter() async throws {
        let model = try await Self.savingModel()
        try Self.shootAll(model, [.fullTree, .trunk])
        defer { Self.removeStaged(model.draft.photoPaths) }

        // The contributor taps Leaf, looks at the viewfinder, and presses Log visit without shooting.
        model.shotType = .leaf
        let receipt = try #require(await model.logVisit())

        #expect(
            Set(receipt.item.photos.map(\.shotType)) == Set([.fullTree, .trunk]),
            "the framings were rewritten at save: \(receipt.item.photos.map(\.shotType.rawValue))"
        )
        #expect(
            !receipt.item.photos.contains { $0.shotType == .leaf },
            "a photograph nobody framed as a leaf was stored as one"
        )
        for photo in receipt.item.photos {
            #expect(
                photo.path.hasSuffix("-\(photo.shotType.rawValue).jpg"),
                "the row and the file disagree about the framing: \(photo)"
            )
        }
    }

    /// The alignment layer is the last **full-tree** photograph, whatever chip was left selected.
    /// Passing the selected chip would have made whether a ghost got recorded depend on where the
    /// contributor's finger stopped.
    @Test("the ghost is recorded from the full-tree shot, not from whatever was selected last")
    func theGhostComesFromTheFullTreeShot() async throws {
        let treeID = UUID()
        defer {
            if let ghost = try? VisitGhostStore.url(for: treeID) {
                try? FileManager.default.removeItem(at: ghost)
            }
        }

        let model = try await Self.savingModel(treeID: treeID)
        try Self.shootAll(model)
        defer { Self.removeStaged(model.draft.photoPaths) }

        model.shotType = .leaf
        _ = try #require(await model.logVisit())

        let ghost = try #require(
            VisitGhostStore.ghost(for: treeID),
            "no ghost was recorded, so the next visit has nothing to line up against"
        )
        // And it is the **full tree**, not merely *a* photograph. The three fixtures have three
        // shapes and nothing here is over `maximumEdge`, so `record`'s downscale is a no-op and the
        // stored ghost still measures whatever it was made from. Without this the assertion above
        // would pass on a ghost made from the trunk.
        let fullTree = try #require(Self.sizes[.fullTree])
        let complaint = "the ghost is \(Int(ghost.size.width))×\(Int(ghost.size.height)), which is not "
            + "the full-tree photograph (\(fullTree.width)×\(fullTree.height)) — it came from another framing"
        #expect(
            Int(ghost.size.width) == fullTree.width && Int(ghost.size.height) == fullTree.height,
            "\(complaint)"
        )
    }

    /// The shutter flash counts captures, and only captures.
    ///
    /// `VisitCameraView` used to fire it on `hasSnapped` turning true, which was the same event as a
    /// capture while a visit held one photograph. Per framing it is not: selecting a chip that already
    /// holds a photograph turns `hasSnapped` true as well, so tapping between filled chips flashed the
    /// screen white as though each tap had photographed something. On a simulator or a library fallback
    /// that flash is the *only* confirmation a capture has, so a false one is a lie about the one thing
    /// this screen has to be honest about.
    @Test("the shutter flash fires once per photograph taken, and not when a chip is selected")
    func theFlashCountsCapturesOnly() throws {
        let model = Self.model()
        #expect(model.captureTick == 0)

        model.shotType = .fullTree
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }
        #expect(model.captureTick == 1)

        model.shotType = .trunk
        model.useLibraryImage(try Self.jpeg(.trunk))
        #expect(model.captureTick == 2)

        // Tapping back and forth across two framings that both hold a photograph. `hasSnapped` goes
        // true on each of these, and nothing was photographed.
        model.shotType = .fullTree
        model.shotType = .trunk
        model.shotType = .fullTree
        #expect(model.captureTick == 2, "selecting a photographed chip flashed the screen \(model.captureTick - 2) times")

        // A retake takes the photograph away and then puts one back: no flash for the discard, one
        // for the replacement.
        model.retake()
        #expect(model.captureTick == 2, "discarding a photograph flashed a confirmation")
        model.useLibraryImage(try Self.jpeg(width: 120, height: 90))
        #expect(model.captureTick == 3)

        model.shotType = .leaf
        model.useLibraryImage(try Self.jpeg(.leaf))
        #expect(model.captureTick == 4)
    }

    /// Bytes that are not a photograph take nothing and confirm nothing.
    ///
    /// The flash is the confirmation, and it is fired from the same statement that records the capture
    /// — after the write, not before it — so the only way to flash is to have staged a file.
    @Test("a capture that could not be written flashes nothing and takes nothing")
    func aRefusedCaptureIsNotAFlash() throws {
        let model = Self.model()
        model.shotType = .fullTree
        model.useLibraryImage(Data("this is not a photograph".utf8))

        #expect(model.captureTick == 0, "a refused capture flashed a confirmation")
        #expect(model.capturedCount == 0)
        #expect(!model.canLogVisit)
    }

    // MARK: - 5 · The tray, with three chips wearing marks, at AX5

    /// E125's overflow, re-checked under the pressure that a third control adds.
    ///
    /// The chip row grew a captured mark on each chip and moved to `CypressChipFlow`, which wraps. At
    /// AX5 three chips with marks are wider than the phone, so an `HStack` here would put the third one
    /// off the right edge — the same failure, in the same place, from a different cause.
    @Test("screen 04 with all three framings photographed still fits the phone at AX5")
    func theTrayStaysOnTheScreenWithThreeCaptures() async throws {
        let width: CGFloat = 393
        let height: CGFloat = 852

        let host = UIHostingController(
            rootView: VisitPreviewFixtures.camera()
                .environment(\.dynamicTypeSize, .accessibility5)
        )
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: height))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let measured = host.sizeThatFits(in: CGSize(width: width, height: height))
        #expect(
            measured.width <= width,
            "screen 04 measured \(measured.width) pt wide on a \(width) pt phone at AX5"
        )
    }

    // MARK: - 6 · The copy that keeps the count honest

    @Test("the CTA names how many photographs are about to be saved")
    func theCTACountsWhatItWillSave() throws {
        let model = Self.model()
        #expect(model.logVisitLabel == "Log visit")

        model.shotType = .fullTree
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }
        // One photograph is the old behaviour and reads as it always did.
        #expect(model.logVisitLabel == "Log visit")

        model.shotType = .trunk
        model.useLibraryImage(try Self.jpeg(.trunk))
        #expect(model.logVisitLabel == "Log visit · 2 photos")

        model.shotType = .leaf
        model.useLibraryImage(try Self.jpeg(.leaf))
        #expect(model.logVisitLabel == "Log visit · 3 photos")
    }

    @Test("the invitation names what is missing, and stops once nothing is")
    func theRemainingLineNamesWhatIsMissing() throws {
        let model = Self.model()
        // Nothing taken yet: the guidance pill is already saying what to frame, so there is no second
        // sentence about it.
        #expect(model.remainingShotsLine == nil)

        model.shotType = .fullTree
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }
        let line = try #require(model.remainingShotsLine)
        #expect(line.contains("trunk"))
        #expect(line.contains("leaf close-up"))
        #expect(!line.lowercased().contains("full tree"), "it offered a framing that is already taken")

        model.shotType = .trunk
        model.useLibraryImage(try Self.jpeg(.trunk))
        model.shotType = .leaf
        model.useLibraryImage(try Self.jpeg(.leaf))
        #expect(model.remainingShotsLine == nil, "it kept asking after all three were taken")
    }

    // MARK: - 7 · The way back to the map (ERRATA E149)

    /// `goToMap` is the app's one absolute destination, and all three fields have to move.
    ///
    /// `path` is the one that looks optional and is not: this router keeps one path for all four tabs,
    /// so leaving something pushed would leave the map hidden underneath it.
    @Test("back to the map clears the cover, the stack and the tab")
    func goToMapIsAbsolute() {
        let router = AppRouter()
        router.tab = .grove
        router.push(.treeProfile(UUID()))
        router.push(.checkIn(UUID()))
        router.present(.identify(nil))

        router.goToMap()

        #expect(router.sheet == nil, "the visit flow's cover is still up")
        #expect(router.path.isEmpty, "the map is behind \(router.path.count) pushed screens")
        #expect(router.tab == .map)
    }

    /// The grove had the same fault and it was invisible rather than sticky: the tab changed under a
    /// pushed screen, so nothing appeared to happen.
    @Test("going to a tab root clears what is pushed over it")
    func goToTabClearsTheStack() {
        let router = AppRouter()
        router.push(.treeProfile(UUID()))
        router.present(.identify(nil))

        router.goToTab(.grove)

        #expect(router.sheet == nil)
        #expect(router.path.isEmpty, "the grove arrived underneath \(router.path.count) pushed screens")
        #expect(router.tab == .grove)
    }

    /// Screen 18's timeline link, from a camera that was opened from that tree's own profile.
    @Test("the timeline link does not stack a second copy of the profile it came from")
    func theTimelineLinkDoesNotDuplicateTheProfile() {
        let treeID = UUID()
        let router = AppRouter()
        router.push(.treeProfile(treeID))

        router.push(.treeProfile(treeID), unlessAlreadyOnTop: true)
        #expect(router.path == [.treeProfile(treeID)], "a second identical profile was pushed")

        // A *different* tree is a real destination and still pushes.
        let other = UUID()
        router.push(.treeProfile(other), unlessAlreadyOnTop: true)
        #expect(router.path == [.treeProfile(treeID), .treeProfile(other)])

        // And the plain form is unchanged, because everything else in the app relies on it.
        router.push(.treeProfile(other))
        #expect(router.path.count == 3)
    }
}
#endif
