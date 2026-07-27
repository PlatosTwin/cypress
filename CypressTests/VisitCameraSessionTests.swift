//
//  VisitCameraSessionTests.swift
//  CypressTests
//
//  One camera session takes a full tree, a trunk and a leaf (ERRATA E152), and the way back to the map
//  is a destination rather than a number of chevrons (ERRATA E151).
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

    // MARK: - 5 · The chip row, wearing three marks, at AX5

    /// #45's overflow, re-checked under the pressure a third meaningful control adds — and a correction
    /// to what the check was thought to be.
    ///
    /// ── The version of this test that could not fail ──────────────────────────────────────────
    /// It hosted the whole of screen 04 at AX5 and asserted the result measured no wider than a 393 pt
    /// phone. This row is an `.overlay` on the viewfinder, and **an overlay never enlarges what it is
    /// over** — so putting the row back to an `HStack`, which was believed to be the defect, left that
    /// assertion green. Broken deliberately and confirmed green, which is the only way that is ever
    /// found.
    ///
    /// ── And then the defect turned out not to be a defect of this kind ────────────────────────
    /// With the row hosted on its own it could finally be measured, and an `HStack` **fits**: 326 pt in
    /// the 361 pt this row is given. SwiftUI compresses children rather than overflowing a proposal.
    /// What it costs is the chips — each squeezed from its natural 158 pt to about 103, its label
    /// wrapping into a column of stacked syllables. Height does not separate the two either: the
    /// compressed `HStack` is *taller* (203 pt) than the wrapping flow (175 pt), for the same reason.
    /// So there is no measurement that decides between them, and this test does not pretend there is.
    ///
    /// ── What is left that a test can decide ────────────────────────────────────────────────────
    /// That the row stays inside the width it is given at AX5, which is a real regression guard: a
    /// `fixedSize()`, a `frame(minWidth:)` or a chip that refuses to compress would break it, and any of
    /// those is how #45 happened in the first place. **Which of the two layouts is legible is verified by
    /// looking**, per ARCHITECTURE §7, and the screenshots are in this branch's report.
    @Test("the shot-type chips stay inside the width they are given at AX5")
    func theChipRowFitsTheWidthItIsGivenAtAX5() async throws {
        // What `VisitCameraView` leaves the row: the phone, less the tray's two gutters.
        let available: CGFloat = 393 - VisitMetrics.Camera.trayPadding * 2

        func measure(_ framings: [VisitShotTypeChips.Framing]) async -> CGSize {
            let host = UIHostingController(
                rootView: VisitShotTypeChips(framings: framings)
                    .environment(\.dynamicTypeSize, .accessibility5)
            )
            let frame = CGRect(x: 0, y: 0, width: available, height: 2_000)
            host.view.frame = frame
            let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: available, height: 2_000))
            window.rootViewController = host
            window.isHidden = false
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(60))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
            }
            defer { window.isHidden = true; window.rootViewController = nil }
            return host.sizeThatFits(in: CGSize(width: available, height: .greatestFiniteMagnitude))
        }

        func framing(_ type: ShotType, _ label: String, selected: Bool = false) -> VisitShotTypeChips.Framing {
            VisitShotTypeChips.Framing(id: type, label: label, isSelected: selected, isCaptured: true)
        }

        let all = [
            framing(.fullTree, "Full tree", selected: true),
            framing(.trunk, "Trunk"),
            framing(.leaf, "Leaf close-up"),
        ]
        let three = await measure(all)
        #expect(
            three.width <= available,
            "the chip row measured \(three.width) pt in the \(available) pt it is given"
        )

        // And the row has to be *something* — a measurement of zero is a row that did not build, which
        // would satisfy the line above and is the shape of failure this file exists to refuse.
        #expect(three.height > 0 && three.width > 0, "the chip row measured \(three) — it drew nothing")
    }

    /// The chip row and the shutter are one bottom-anchored stack now, and the chips must still land on
    /// the mock's `bottom:150px` in the state the mock draws.
    ///
    /// **The screenshot is the proof, not this.** What a layout looks like is not a thing a unit test in
    /// this project can read (ARCHITECTURE §7: visual verification is by running the app). What this
    /// pins is the arithmetic that a later tidy-up could get wrong in exactly one way — subtracting the
    /// shutter's ring, which is an `.overlay` on a 68 pt frame and takes no layout space, and which
    /// would move the chips 12 pt off the mock.
    @Test("the chip row still sits 150 pt off the bottom when the shutter block is at its drawn size")
    func theChipRowKeepsItsDrawnPosition() {
        let metrics = VisitMetrics.Camera.self
        let chipsBottomEdge = metrics.shutterBottom + metrics.shutterDiameter + metrics.shotTypeGapAboveShutter
        #expect(
            chipsBottomEdge == metrics.shotTypeBottom,
            "the chips land \(chipsBottomEdge) pt off the bottom, and SCREENS 04 draws them at \(metrics.shotTypeBottom)"
        )
        #expect(metrics.shotTypeGapAboveShutter == 48, "the ring was counted as layout height")
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

    // MARK: - 7 · The way back to the map (ERRATA E151)

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

    // MARK: - 8 · The accessibility variant (R14; ERRATA — see docs/errata-pending/screen04-ax.md)

    /// The floor is arithmetic on the capture, and it can be checked as arithmetic.
    ///
    /// What it pins is the *derivation*, not a number somebody liked: 4:3 is the `.photo` preset's own
    /// aspect and `width × 4/3` is the height at which a `.resizeAspectFill` preview stops cropping the
    /// top and bottom off the frame. A later tidy-up that rounds this to 520 or 540 fails here.
    @Test("the viewfinder's floor is the height at which it stops cropping the photograph")
    func theViewfinderFloorIsTheCaptureFrame() {
        let phone = CGSize(width: 393, height: 852)
        let floor = VisitMetrics.Camera.viewfinderFloor(width: phone.width, available: phone.height)

        #expect(floor == phone.width * 4 / 3, "the floor is \(floor), not the 3:4 frame's height")
        #expect(floor == 524, "the floor on a 393 pt phone is \(floor)")

        // It is a *floor*, not a redesign: it has to sit under the height the viewfinder already has
        // at the sizes SCREENS 04 draws, or it would be moving the drawn layout. Measured on the
        // running app on a 393 × 852 pt iPhone 16: 583 pt at the drawn size, 550 pt at `xxxLarge`,
        // 503 pt at AX1 — so the floor binds first exactly where `isAccessibilitySize` does.
        #expect(floor < 550, "the floor would bind at xxxLarge, which the drawn layout does not expect")
        #expect(floor > 503, "the floor is below AX1's natural height, so it would never bind at all")

        // And it yields on a display too short to hold it and a tray both, rather than taking the
        // whole screen and leaving the controls nowhere.
        let short = VisitMetrics.Camera.viewfinderFloor(width: phone.width, available: 400)
        #expect(short == 400 - VisitMetrics.Camera.controlsFloor, "the clamp did not bind: \(short)")
        #expect(short < floor)
    }

    /// **The one that had to be able to see the thing that changed.**
    ///
    /// E152's own note is the warning: the chip row is an `.overlay`, an overlay never enlarges what it
    /// is over, and a measurement of the *parent* therefore cannot observe the row at all — the test
    /// that tried it stayed green with the defect restored. So this does not measure the screen. It
    /// hosts the whole of screen 04 at AX5 in a real window at a real phone's size and then asks the
    /// UIKit layer three questions it can actually answer: where the scroll view starts, whether it has
    /// content past its own viewport, and which side of it each control ended up on.
    ///
    /// That last one is the fix stated as a property. R14's argument is that *a control reachable by
    /// scrolling is reachable* — so "the three framings are in the scroll" is the whole of E152 being
    /// reachable again, and "the shutter is not" is the answer to R14's third open question written
    /// down where a later edit has to trip over it.
    @Test("at AX5 the three framings are inside the scrolling controls and the shutter is not")
    func theFramingsAreReachableAtAX5() async throws {
        let phone = CGSize(width: 393, height: 852)
        let hosted = try await Self.host(VisitPreviewFixtures.camera(), at: .accessibility5, in: phone)
        defer { hosted.dismiss() }

        let scroll = try #require(
            Self.firstScrollView(in: hosted.root),
            "screen 04 at AX5 has no scroll view, so nothing below the fold is reachable"
        )

        // The viewfinder took exactly its floor, and the scroll took the rest.
        let floor = VisitMetrics.Camera.viewfinderFloor(width: phone.width, available: hosted.root.bounds.height)
        #expect(
            abs(scroll.frame.minY - floor) < 1,
            "the controls start at \(scroll.frame.minY) pt, and the viewfinder's floor is \(floor)"
        )

        // There is content past the viewport — which is what makes this a fix rather than a
        // rearrangement. If everything fitted, the chips were never off the screen to begin with.
        #expect(
            scroll.contentSize.height > scroll.bounds.height,
            "the controls measured \(scroll.contentSize.height) pt in a \(scroll.bounds.height) pt viewport"
        )

        let inScroll = Self.accessibilityLabels(under: scroll)
        for framing in ["Full tree", "Trunk", "Leaf close-up"] {
            #expect(
                inScroll.contains(where: { $0.hasPrefix(framing) }),
                "\(framing) is not in the scrolling controls — labels there were \(inScroll)"
            )
        }

        // The shutter is on the other side of that line, which is what "pinned" means here. On a
        // simulator the camera is always unavailable, so it is the library form of the control — the
        // state BUILD-PLAN §9 requires and the only one this host can reach.
        let shutter = "Choose a photo from your library"
        #expect(
            !inScroll.contains(shutter),
            "the shutter travelled with the controls instead of pinning to the viewfinder"
        )
        #expect(
            Self.accessibilityLabels(under: hosted.root).contains(shutter),
            "the shutter is not on the screen at all"
        )
    }

    /// The other half, and the one that keeps this from becoming a redesign: below the accessibility
    /// sizes screen 04 is what SCREENS 04 draws, with no scroll view and the chip row back on the
    /// viewfinder where the mock puts it.
    @Test("at the drawn size the controls do not scroll and the chips are back on the viewfinder")
    func theDrawnLayoutIsUntouched() async throws {
        let phone = CGSize(width: 393, height: 852)
        let hosted = try await Self.host(VisitPreviewFixtures.camera(), at: .large, in: phone)
        defer { hosted.dismiss() }

        #expect(
            Self.firstScrollView(in: hosted.root) == nil,
            "the drawn layout grew a scroll view"
        )
        let labels = Self.accessibilityLabels(under: hosted.root)
        for framing in ["Full tree", "Trunk", "Leaf close-up"] {
            #expect(labels.contains(where: { $0.hasPrefix(framing) }), "\(framing) is not on the screen")
        }
    }

    // MARK: - Hosting a screen so UIKit can be asked about it

    /// A screen standing in a real off-screen window, which is the only way `ScrollView` reports a
    /// content size and accessibility elements exist to be found. Same technique and the same reasons
    /// as `DynamicTypeScreenshotTests.render`.
    struct Hosted {
        let root: UIView
        let dismiss: () -> Void
    }

    static func host(
        _ content: some View,
        at size: DynamicTypeSize,
        in frame: CGSize
    ) async throws -> Hosted {
        let host = UIHostingController(
            rootView: AnyView(content.environment(\.dynamicTypeSize, size))
        )
        let bounds = CGRect(origin: .zero, size: frame)
        host.view.frame = bounds
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: frame.width, height: frame.height))
        window.rootViewController = host
        window.isHidden = false
        // `await`, not a run-loop spin: the screen's `.task` loads through an actor, and until it
        // lands the camera reports `.idle` and the fallback branch has not been chosen yet.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        return Hosted(root: host.view, dismiss: {
            window.isHidden = true
            window.rootViewController = nil
        })
    }

    static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// Every accessibility label reachable under `view`, through both the view tree and the
    /// `accessibilityElements` SwiftUI vends off its hosting layers — a SwiftUI control is usually the
    /// second of those, not the first, so walking subviews alone finds nothing.
    static func accessibilityLabels(under view: UIView) -> [String] {
        var found: [String] = []
        var seen = Set<ObjectIdentifier>()

        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement, let label = object.accessibilityLabel {
                found.append(label)
            }
            for element in (object.accessibilityElements as? [NSObject]) ?? [] {
                visit(element)
            }
            for subview in (object as? UIView)?.subviews ?? [] {
                visit(subview)
            }
        }

        visit(view)
        return found
    }
}
#endif
