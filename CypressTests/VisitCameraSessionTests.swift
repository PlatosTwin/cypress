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
//  The three fixtures are different *sizes* rather than different colors, because a size can be read
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
            gpsAccuracyM: { 9 },
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
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))

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
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))

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

    // MARK: - 4b · The ✕ over a captured shot discards the shot, not the session (task #152)
    //
    // Reported from the owner's device walk of 2026-07-31: ✕ after capturing exited to the tree
    // profile. The ✕ over a captured photograph means "not this shot" — the viewfinder comes back
    // and the session survives. Only over the live viewfinder does ✕ leave.
    //
    // The camera itself cannot be driven in a simulator (`useLibraryImage` is the only capture
    // path there, behind a system PhotosPicker no UI test can script reliably), so the decision is
    // covered here at the unit level, on the same model the view asks. The physical-phone pass is
    // the owner's, as with every camera behavior.

    @Test("the ✕ over a captured shot discards that shot and stays")
    func closeOverACapturedShotDiscardsAndStays() throws {
        let model = Self.model()
        try Self.shootAll(model, [.fullTree, .trunk])
        defer { Self.removeStaged(model.draft.photoPaths) }

        model.shotType = .trunk
        #expect(model.hasSnapped)
        #expect(model.closeIntent == .discardShot)

        let dismisses = model.performClose()
        #expect(!dismisses, "the ✕ over a captured shot left the camera")
        // The live viewfinder is back for this framing…
        #expect(!model.hasSnapped, "the captured trunk is still on screen")
        #expect(model.snapshot == nil)
        #expect(model.draft.photo(shotType: .trunk) == nil)
        // …and the session survived: the selection, the other framing's photograph, the save.
        #expect(model.shotType == .trunk, "the framing selection was reset")
        #expect(model.draft.photo(shotType: .fullTree) != nil, "the full tree went with the trunk")
        #expect(model.canLogVisit, "the session stopped being saveable")
    }

    @Test("the ✕ over the live viewfinder leaves — so discard-then-✕ is two taps out")
    func closeOverTheViewfinderLeaves() throws {
        let model = Self.model()
        #expect(model.closeIntent == .leaveCamera)
        #expect(model.performClose(), "the ✕ over the live viewfinder did not leave")

        // After a discard the next ✕ is over the live viewfinder again, and that one leaves.
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }
        #expect(model.closeIntent == .discardShot)
        #expect(!model.performClose())
        #expect(model.closeIntent == .leaveCamera)
        #expect(model.performClose())
    }

    @Test("the ✕'s spoken name changes with what it would do")
    func closeLabelFollowsIntent() throws {
        // The fact, not the phrasing (R30's rule): the two states must not share a name, because a
        // listener over a captured shot who hears the viewfinder's name is being promised an exit.
        let model = Self.model()
        let overViewfinder = model.closeLabel
        model.useLibraryImage(try Self.jpeg(.fullTree))
        defer { Self.removeStaged(model.draft.photoPaths) }
        let overCapturedShot = model.closeLabel
        #expect(!overViewfinder.isEmpty)
        #expect(!overCapturedShot.isEmpty)
        #expect(overViewfinder != overCapturedShot, "one name for two different taps")
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
        // One photograph is the old behavior and reads as it always did.
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

    // MARK: - 8 · The accessibility variant (R14; ERRATA E159, E160)

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

    /// **R14's split, measured on the running layout: the viewfinder takes its floor and what is left
    /// is a scroll view with more in it than fits.**
    ///
    /// ── The version of this test that could not run, let alone fail ────────────────────────────
    /// This was first written to host screen 04 and read the *accessibility tree* — which control ended
    /// up on which side of the fold, by label. It never passed, because it was never run: a hosted
    /// SwiftUI tree in an off-screen window vends **no accessibility elements at all**. Probed
    /// directly, a bare `Button("Hello button")` in a `UIHostingController` reports
    /// `accessibilityElementCount() == 0` and no elements anywhere in its hierarchy; SwiftUI builds
    /// that tree lazily for a real assistive client, and a unit test host is not one. So every
    /// `accessibilityLabels(under:)` lookup came back empty and every assertion over it was vacuous or
    /// false. That helper is gone rather than fixed — a helper that always answers "nothing" is the
    /// exact shape of the green suite this project keeps catching itself in.
    ///
    /// What is left is what UIKit *will* answer for a hosted tree: geometry. That is enough for the
    /// ruling, because R14's split is geometric — "the viewfinder keeps a floor and the controls get a
    /// scroll view" is a statement about where one ends and the other begins, and about there being
    /// something below the fold to scroll to. **Which** control is on which side is verified by
    /// looking, per ARCHITECTURE §7 and exactly as `theChipRowFitsTheWidthItIsGivenAtAX5` already says
    /// of the row above it; the screenshots are in this branch's report.
    @Test("at AX5 the viewfinder takes its floor and the controls scroll beneath it")
    func theControlsScrollBeneathTheFloorAtAX5() async throws {
        let phone = CGSize(width: 393, height: 852)
        let hosted = try await Self.host(VisitPreviewFixtures.camera(), at: .accessibility5, in: phone)
        defer { hosted.dismiss() }

        let scroll = try #require(
            Self.controlsScrollView(in: hosted.root),
            "screen 04 at AX5 has no scroll view, so nothing below the fold is reachable"
        )

        // The viewfinder took exactly its floor, and the scroll took the rest.
        //
        // **In the root's coordinates, not the scroll view's own frame.** SwiftUI wraps a `ScrollView`
        // in a `PlatformContainer` and positions *that*, leaving the scroll view at the origin of it —
        // so `scroll.frame.minY` is 0 on a scroll view sitting 524 pt down the screen, and an
        // assertion against it fails while the layout is correct.
        let floor = VisitMetrics.Camera.viewfinderFloor(width: phone.width, available: phone.height)
        let inRoot = scroll.convert(scroll.bounds, to: hosted.root)
        #expect(
            abs(inRoot.minY - floor) < 1,
            "the controls start at \(inRoot.minY) pt, and the viewfinder's floor is \(floor)"
        )
        #expect(
            abs(scroll.bounds.height - (phone.height - floor)) < 1,
            "the controls got \(scroll.bounds.height) pt of the \(phone.height - floor) pt left over"
        )

        // There is content past the viewport — which is what makes this a fix rather than a
        // rearrangement. If everything fitted, nothing was ever off the screen to begin with.
        #expect(
            scroll.contentSize.height > scroll.bounds.height,
            "the controls measured \(scroll.contentSize.height) pt in a \(scroll.bounds.height) pt viewport"
        )
    }

    /// The other half, and the one that keeps this from becoming a redesign: below the accessibility
    /// sizes screen 04 is what SCREENS 04 draws, with no scroll view anywhere on it.
    @Test("at the drawn size the controls do not scroll")
    func theDrawnLayoutIsUntouched() async throws {
        let phone = CGSize(width: 393, height: 852)
        let hosted = try await Self.host(VisitPreviewFixtures.camera(), at: .large, in: phone)
        defer { hosted.dismiss() }

        #expect(
            Self.controlsScrollView(in: hosted.root) == nil,
            "the drawn layout grew a scroll view"
        )
    }

    // MARK: - 9 · The two reports of 2026-07-27 (#112, #113)

    /// A curated species with a sourced deciduous habit and both calendars — the state that offers the
    /// whole phenology vocabulary, and the state no fixture in this project had ever reached.
    ///
    /// `VisitPhenologyVocabulary` offered the row "for the curated 40 and nobody else" at the
    /// time, so almost nothing reached it; London Plane is both one of the 40 and the commonest
    /// street tree in San Francisco, which is exactly why the owner met this defect and the suite
    /// never did. (#151 later removed that gate — the six-chip row is the common case now, which
    /// makes this layout property more load-bearing, not less.)
    static let londonPlane = try! Species(
        scientificName: "Platanus × acerifolia",
        commonName: "London Plane",
        family: "Platanaceae",
        leafRetention: .deciduous,
        seasonal: SeasonalCalendar(
            bloomMonths: [4, 5],
            fallColorMonths: [10, 11],
            fruitMonths: [9, 10],
            newGrowthMonths: [3, 4]
        ),
        curated: true
    )

    /// **#112, stated as the property that was actually violated.**
    ///
    /// Not "the row fits" — it always fitted, and that is precisely the trap the row above fell into
    /// (see `theChipRowFitsTheWidthItIsGivenAtAX5`, whose first version could not fail). SwiftUI's
    /// `HStack` *compresses* rather than overflowing, so a row far too wide still measures no wider
    /// than the width it was given. What it spends to get there is the chips: each is squeezed below
    /// the width its own label needs, and the label wraps mid-word.
    ///
    /// So the measurement is the row's **height**, and the property is that the row is a whole number
    /// of single-line chips tall. `CypressChipFlow` hands every chip the size it asks for and puts the
    /// overflow on the next line, so its height is exactly `lines x chipHeight + gaps` for some whole
    /// `lines`. A chip whose label has wrapped is taller than one line, and no packing of whole chips
    /// can produce that height — the ratio comes out fractional.
    ///
    /// **The single-line height is measured off this same row given room to spread**, not off a chip
    /// hosted on its own. A lone `Chip` through `UIHostingController.sizeThatFits` reports 83.67 pt
    /// where the flow lays the same chip out at 56.67; measuring the row against that number failed by
    /// exactly the difference and said the layout was broken when the ruler was. One view, one
    /// measuring path, two widths.
    ///
    /// At **`.large`**, deliberately. The owner reported this at the default text size; a test pinned
    /// to AX5 would have been green on the morning the report came in.
    @Test("the phenology row draws whole chips at the default text size, not squeezed ones")
    func thePhenologyRowDoesNotSqueezeItsChips() async throws {
        // What `VisitCameraView`'s tray leaves the row: the phone, less its two gutters.
        let available: CGFloat = 393 - VisitMetrics.Camera.trayPadding * 2
        let gap = VisitMetrics.Camera.chipGap
        let species = Self.londonPlane
        let tags = VisitPhenologyVocabulary.tags(for: species)
        #expect(tags.count == 6, "the vocabulary offered \(tags.count) tags, not the whole six")

        let row = VisitPhenologyChips(species: species, tags: tags)

        // The same row given far more width than it can use: every chip on one line, at the height a
        // chip is when nothing is squeezing it.
        let oneLine = await Self.measure(row, at: .large, width: 4_000)
        #expect(oneLine.height > 0, "the row measured no height at all")

        // And the row at the width the tray actually gives it.
        let measured = await Self.measure(row, at: .large, width: available)

        let lines = (measured.height + gap) / (oneLine.height + gap)
        #expect(
            abs(lines - lines.rounded()) < 0.02,
            """
            the row is \(measured.height) pt tall where one line of chips is \(oneLine.height) — \
            that is \(lines) lines, and a fractional line is a chip whose label has wrapped
            """
        )

        // The premise: the six chips genuinely do not fit on one line here. Without this the test
        // would pass on a row that was never under pressure, which is the other way a layout test
        // ratifies the defect it was written to catch.
        #expect(
            lines.rounded() >= 2,
            "the row took \(lines.rounded()) line(s) in \(available) pt — nothing was under pressure"
        )
        #expect(measured.width > 0, "the row measured \(measured) — it drew nothing")
    }

    /// **#113.** The add-tree well is the shape of the photograph it holds, and that shape is portrait.
    ///
    /// Two halves, because the constant and the view can each be wrong on their own. The first is the
    /// derivation — the well's ratio is the capture's, inverted for SwiftUI's width ÷ height
    /// convention — so a later edit restating it as a rounded literal fails here, the way the
    /// viewfinder floor's test is meant to fail. The second is the drawing, measured off
    /// `VisitAddTreePhotoWell` itself, because a token nothing applies is just a token: the well was
    /// wrong for its whole life while `wellHeight` sat there looking deliberate.
    @Test("the add-tree photo well is the portrait frame the camera captures")
    func theAddTreeWellIsAPortraitCaptureFrame() async throws {
        let ratio = VisitMetrics.AddTree.wellAspectRatio

        #expect(ratio < 1, "the well is still landscape — width ÷ height is \(ratio)")
        #expect(
            ratio == 1 / VisitMetrics.Camera.captureAspectRatio,
            "the well's shape is \(ratio) and the capture's is \(VisitMetrics.Camera.captureAspectRatio)"
        )
        // **The annotation is load-bearing, and this is not a tolerance.** Written inline as
        // `#expect(ratio == 3.0 / 4.0, …)` this assertion failed against a `ratio` whose bit pattern
        // is exactly `0x3fe8000000000000` — 0.75 to the last bit. `#expect(a == b)` expands to a
        // generic `__checkBinaryOperation(lhs: T, _ op: (T, () -> U) -> Bool, rhs: @autoclosure () -> U)`,
        // and with `T == CGFloat` and a bare float-literal expression on the right, the solver binds
        // `U` to **`AnyHashable`** rather than to `CGFloat`. The two sides are then boxes rather than
        // numbers, and `AnyHashable(CGFloat(0.75)) != AnyHashable(Double(0.75))` because the dynamic
        // types differ, however equal the values are. Naming the type here keeps `U` at `CGFloat`, so
        // this compares the number. See ERRATA E171.
        let portrait: CGFloat = 3.0 / 4.0
        #expect(ratio == portrait, "the well is \(ratio), not the 3:4 frame a phone held upright takes")

        // The number the old constant got wrong, kept so the mistake cannot come back quietly: at the
        // gutter's width on a 393 pt phone an unbounded well is 481 pt tall, not 268.
        //
        // **481 is still the shape and is no longer the drawing, and that distinction is E174.** The
        // well the composer draws is bounded by `wellWidthCeiling`, because 481 pt of a 393 × 852
        // phone left the form under it invisible. What the bound takes is *width*, so this number
        // stays exactly true of the shape: the well is still the frame of a 3:4 photograph at every
        // size it is ever drawn at, and the case below is the one that measures the bounded one.
        let width: CGFloat = 393 - CypressSpacing.gutter * 2
        #expect(abs(width / ratio - 481) < 1, "the well is \(width / ratio) pt tall at \(width) pt wide")

        // And the well itself draws that shape when it is given that width and no ceiling.
        let measured = await Self.measure(
            VisitAddTreePhotoWell { Color.clear },
            at: .large,
            width: width
        )
        #expect(measured.height > measured.width, "the well was drawn wider than it is tall: \(measured)")
        #expect(
            abs(measured.width / measured.height - ratio) < 0.01,
            "the well was drawn \(measured), a ratio of \(measured.width / measured.height)"
        )
        #expect(abs(measured.height - 481) < 1, "the unbounded well drew \(measured.height) pt, not 481")
    }

    /// **#127 · ERRATA E174.** The ceiling takes width, so it cannot change the well's shape.
    ///
    /// This is the assertion that keeps E174 from undoing E162. A bound on a frame that holds a
    /// photograph has exactly two forms: take height and letterbox (or, with a `.resizeAspectFill`
    /// preview, crop — which is the defect E162 exists for), or take width and stay the same shape at
    /// a smaller size. `VisitAddTreePhotoWell.widthCeiling` is the second, and the way to prove it is
    /// to bind the ceiling hard and read the ratio back off the drawing.
    @Test("bounding the well narrows it and does not reshape it")
    func theWellCeilingTakesWidthNotShape() async throws {
        let ratio = VisitMetrics.AddTree.wellAspectRatio
        let width: CGFloat = 393 - CypressSpacing.gutter * 2

        // A ceiling well below the width the well would otherwise take, so it certainly binds.
        let ceiling: CGFloat = 200
        let measured = await Self.measure(
            VisitAddTreePhotoWell(widthCeiling: ceiling) { Color.clear },
            at: .large,
            width: width
        )

        #expect(
            abs(measured.width - ceiling) < 1,
            "the well drew \(measured.width) pt wide against a \(ceiling) pt ceiling"
        )
        // The shape, unchanged — this is the E162 invariant surviving the bound.
        #expect(
            abs(measured.width / measured.height - ratio) < 0.01,
            "the bounded well drew \(measured), a ratio of \(measured.width / measured.height)"
        )
        #expect(
            abs(measured.height - ceiling / ratio) < 1,
            "the bounded well drew \(measured.height) pt tall where its own shape says \(ceiling / ratio)"
        )

        // And a ceiling wider than the column is not a bound at all: the well still takes the width
        // it is given. Without this, a ceiling that had quietly become a *frame* would pass above.
        let unbound = await Self.measure(
            VisitAddTreePhotoWell(widthCeiling: 4_000) { Color.clear },
            at: .large,
            width: width
        )
        #expect(abs(unbound.width - width) < 1, "the well drew \(unbound.width) pt in a \(width) pt column")
    }

    /// **#127 · ERRATA E174.** The photograph does not take the whole screen, and the form is on it.
    ///
    /// Reported by the project owner: *"Screen for Add this Tree has the photo square fill the entire
    /// vertical area so it's not clear to the user that there is content below the photo that they
    /// can fill out."*
    ///
    /// ── This is the assertion the previous one could not make ──────────────────────────────
    /// `theAddTreeWellIsAPortraitCaptureFrame` measures the well as a component, which is how E162's
    /// defect was caught and is not how E174's was: the well was the right shape and the wrong
    /// *share of the screen*, and a component measured on its own has no screen to be a share of. So
    /// this hosts the real composer at a real phone's size, draws it, and reads the well's rows out
    /// of the pixels — the same thing the owner did, with a ruler.
    ///
    /// Three claims, and each fails on `main` before the fix:
    ///
    /// 1. **The well takes at most two thirds of the scroll viewport.** It took 82 % at the drawn
    ///    size on the iPhone 16e this was measured on, and more than 100 % at AX5.
    /// 2. **The well starts at the top of the viewport.** This is what makes claim 1 mean what it
    ///    says rather than something weaker — with the accuracy chip scrolling above the well, the
    ///    chip's height came out of the third that was meant to be left over, and at AX5 the chip is
    ///    78 pt of a 255 pt viewport.
    /// 3. **There is ink below the well and inside the viewport**, which is the owner's sentence
    ///    stated as a fact about pixels: something is drawn under the photograph, without scrolling.
    @Test(
        "the add-tree photograph leaves the form on the screen",
        arguments: [DynamicTypeSize.large, DynamicTypeSize.accessibility5]
    )
    func theAddTreeWellLeavesTheFormOnTheScreen(at size: DynamicTypeSize) async throws {
        let phone = CGSize(width: 393, height: 852)
        let hosted = try await Self.host(
            VisitPreviewFixtures.addTree(), at: size, in: phone, style: .light
        )
        defer { hosted.dismiss() }

        let scroll = try #require(
            Self.controlsScrollView(in: hosted.root),
            "the add-tree composer has no scroll view, so it has no viewport to be a share of"
        )
        let viewport = scroll.convert(scroll.bounds, to: hosted.root)
        #expect(viewport.height > 0, "the composer's viewport measured \(viewport)")

        let bitmap = try Self.draw(hosted.root)
        let band = Int(viewport.minY.rounded())..<Int(viewport.maxY.rounded())
        let well = try #require(
            Self.rows(
                of: Self.srgb(CypressColor.surfaceEmptyThumb),
                in: bitmap,
                band: band,
                // Narrower than the well is at AX5 (122 pt on the phone this was measured on) and far
                // wider than any stray run of that fill could be.
                minimumRun: 60
            ),
            "no photo well was drawn anywhere in the composer's viewport at \(size)"
        )
        let wellHeight = CGFloat(well.count)
        let ceiling = viewport.height * VisitMetrics.AddTree.wellViewportShare

        // 1 · the share.
        #expect(
            wellHeight <= ceiling + 2,
            """
            at \(size) the well drew \(wellHeight) pt of a \(viewport.height) pt viewport — \
            \(Int((wellHeight / viewport.height * 100).rounded())) %, against a ceiling of \(ceiling)
            """
        )

        // 2 · nothing of the form is above it, so the third that is left over is all beneath it.
        #expect(
            CGFloat(well.lowerBound) - viewport.minY < 3,
            "at \(size) the well starts \(CGFloat(well.lowerBound) - viewport.minY) pt into the viewport"
        )

        // 3 · and something is actually drawn down there.
        //
        // **The 6 pt offset is load-bearing.** The well's own dashed border is several hundred
        // pixels of not-the-page-color lying immediately under its last filled row, and counting
        // those made this claim pass on the very layout it was written to fail: at AX5 before the
        // fix the well was clipped by the footer with nothing at all beneath it, and its own bottom
        // edge answered for the form. The `if` is the other half — past the clip there is no band
        // left, and a `Range` with its bounds the wrong way round traps rather than failing.
        //
        // The page and the well's fill are 5/255 apart on every channel, so this tolerance treats
        // them as the same nothing. That is deliberate: a well that reappeared below `inkStart`
        // must not be able to answer for the form either.
        let page = Self.srgb(CypressColor.surfaceScreen)
        var ink = 0
        let inkStart = well.upperBound + 6
        if inkStart < band.upperBound {
            for y in inkStart..<band.upperBound where y < bitmap.height {
                for x in 0..<bitmap.width where !bitmap.matches(x, y, page, tolerance: 12) {
                    ink += 1
                }
            }
        }
        #expect(
            ink >= 200,
            "at \(size) only \(ink) pixels are drawn below the photograph and above the CTA"
        )
    }

    // MARK: - Hosting a screen so UIKit can be asked about it

    /// A screen standing in a real off-screen window, which is the only way `ScrollView` reports a
    /// content size and a laid-out frame. Same technique and the same reasons as
    /// `DynamicTypeScreenshotTests.render`.
    ///
    /// **What it cannot be asked** is anything about accessibility — see
    /// `theControlsScrollBeneathTheFloorAtAX5`. A hosted SwiftUI tree vends no elements at all.
    struct Hosted {
        let root: UIView
        let dismiss: () -> Void
    }

    static func host(
        _ content: some View,
        at size: DynamicTypeSize,
        in frame: CGSize,
        style: UIUserInterfaceStyle = .unspecified
    ) async throws -> Hosted {
        let host = UIHostingController(
            rootView: AnyView(content.environment(\.dynamicTypeSize, size))
        )
        host.overrideUserInterfaceStyle = style
        host.view.frame = CGRect(origin: .zero, size: frame)
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: frame.width, height: frame.height))
        window.overrideUserInterfaceStyle = style
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

    /// What `content` measures at `width`, with height unbounded.
    ///
    /// **`safeAreaRegions = []` is load-bearing, not tidiness.** A `UIHostingController` in a bare
    /// window still resolves a safe area, and `sizeThatFits` folds it into the answer: measured with
    /// it, one phenology chip came back 83.67 pt tall where the layout draws it at 56.67, and the
    /// add-tree well came back 535 pt where it draws 481. Both are the same 54 pt of inset, and both
    /// would have been read as the view being wrong rather than the ruler.
    static func measure(_ content: some View, at size: DynamicTypeSize, width: CGFloat) async -> CGSize {
        let host = UIHostingController(rootView: AnyView(content.environment(\.dynamicTypeSize, size)))
        host.safeAreaRegions = []
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 2_000)
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: 2_000))
        window.rootViewController = host
        window.isHidden = false
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(60))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        defer { window.isHidden = true; window.rootViewController = nil }
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    /// The scroll view R14's variant puts the controls in.
    ///
    /// **Not any `UIScrollView`**, and that distinction is the whole of the helper. `UITextView` is a
    /// scroll view, screen 04's note field is a `TextField(axis: .vertical)` which UIKit backs with
    /// one, and it sits *inside* the controls — so a depth-first search that accepts the first
    /// `UIScrollView` it meets answers "yes, the controls scroll" on the drawn layout, where they do
    /// not, and reports the note field's origin as the viewfinder's floor. Both of those were live
    /// failures of the version of these tests that shipped in this branch unreviewed.
    static func controlsScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !(scroll is UITextView) { return scroll }
        for subview in view.subviews {
            if let found = controlsScrollView(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Reading a drawn screen back as pixels (ERRATA E174)

    /// A hosted screen drawn into memory, **one pixel per point**, in the root view's coordinates.
    ///
    /// ── Why a bitmap and not the view tree ────────────────────────────────────────────────
    /// The subject of E174 is a `RoundedRectangle` inside a `ScrollView`. SwiftUI vends no `UIView`
    /// for it, `Hosted` vends no accessibility elements (see `theControlsScrollBeneathTheFloorAtAX5`),
    /// and a hosted tree therefore offers no way at all to ask "how tall is the photo well *on the
    /// screen*". The complaint E174 answers is about what a person sees, so what this reads is what
    /// was drawn: the well's fill is `surfaceEmptyThumb` and nothing else inside the composer's
    /// scroll uses it, so the rows it occupies are the rows it occupies.
    ///
    /// `layer.render(in:)` rather than `drawHierarchy(in:afterScreenUpdates:)`: it needs no screen
    /// update to have happened, which an off-screen window cannot promise.
    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }

        func matches(_ x: Int, _ y: Int, _ color: (r: Int, g: Int, b: Int), tolerance: Int) -> Bool {
            let p = rgb(x, y)
            return abs(p.r - color.r) <= tolerance
                && abs(p.g - color.g) <= tolerance
                && abs(p.b - color.b) <= tolerance
        }
    }

    static func draw(_ view: UIView) throws -> Bitmap {
        let w = Int(view.bounds.width.rounded())
        let h = Int(view.bounds.height.rounded())
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw CocoaError(.fileWriteUnknown) }
            // UIKit's origin is top-left and Core Graphics' is bottom-left, so without this the
            // screen is drawn upside down and every row index below means the wrong thing.
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)
            view.layer.render(in: context)
        }
        return Bitmap(width: w, height: h, bytes: bytes)
    }

    /// A design-system color as the sRGB triple it draws as, in the light appearance.
    static func srgb(_ color: Color) -> (r: Int, g: Int, b: Int) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// The rows of `band` on which at least `minimumRun` pixels are `color`.
    ///
    /// A count and not a contiguous run: the empty well has a sentence across its middle at the
    /// drawn size, which breaks any single run, and only the first and last rows are being asked
    /// for. The threshold is what keeps a stray antialiased pixel from counting as the well.
    static func rows(
        of color: (r: Int, g: Int, b: Int),
        in bitmap: Bitmap,
        band: Range<Int>,
        minimumRun: Int
    ) -> ClosedRange<Int>? {
        var first: Int?
        var last: Int?
        for y in band where y >= 0 && y < bitmap.height {
            var count = 0
            for x in 0..<bitmap.width where bitmap.matches(x, y, color, tolerance: 2) { count += 1 }
            if count >= minimumRun {
                if first == nil { first = y }
                last = y
            }
        }
        guard let first, let last else { return nil }
        return first...last
    }
}
#endif
