//
//  VisitCameraSubjectTests.swift
//  CypressTests
//
//  Two defects found by using screen 04 on a phone, which is the only place either could be found:
//  both need a camera, and one of them needs a tree that has already been photographed once
//  (ERRATA E125).
//
//  1. **The ghost ignored the subject.** The overlay is the last *full-tree* photo — that is what
//     `ShotType.supportsGhostOverlay` says and what `VisitGhostStore.record` enforces on the way in.
//     The screen only read the storing half: it drew the tree behind Trunk and Leaf too, asking for
//     a bark close-up to be lined up against a whole tree.
//
//  2. **The tray ran off the right edge.** `scaledToFill` reports the scaled size, so a portrait
//     photo behind the viewfinder measured 627 pt against a 393 pt phone; the note field and the
//     Log visit button were laid out to that width and cut off. See `PhotoFill`.
//
//  The second is measured against the real screen rather than a stand-in for it, because the bug was
//  a measurement — a fixture that is not the shipping view proves nothing about the shipping view.
//

#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Screen 04 · the subject rules the overlay, and nothing outgrows the phone")
struct VisitCameraSubjectTests {

    // MARK: - Fixtures

    private static func model(shotType: ShotType = .fullTree) -> VisitCameraModel {
        let model = VisitCameraModel(
            treeID: VisitPreviewFixtures.cypress.id,
            treeDisplayName: "Grandmother Cypress",
            gpsAccuracyM: 9,
            api: VisitPreviewAPI(),
            outbox: VisitPreviewFixtures.outbox(),
            attribution: VisitPreviewFixtures.attribution
        )
        model.shotType = shotType
        return model
    }

    /// A real JPEG in portrait, at the shape a phone actually produces. The aspect ratio is the
    /// whole of the layout defect: a square photo would have overflowed by nothing and the test
    /// would have passed against the broken view.
    private static func portraitJPEG(width: Int = 3_024, height: Int = 4_032) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImage = { () -> CGImage? in
            context.setFillColor(CGColor(red: 0.15, green: 0.35, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }() else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    // MARK: - 1 · The overlay follows the subject

    @Test("A trunk or leaf close-up gets no tree hanging behind it")
    func overlayIsFullTreeOnly() {
        #expect(Self.model(shotType: .fullTree).subjectTakesGhost)
        #expect(!Self.model(shotType: .trunk).subjectTakesGhost)
        #expect(!Self.model(shotType: .leaf).subjectTakesGhost)
    }

    @Test("The pill does not ask you to match an angle there is nothing to match")
    func guidanceFollowsTheSubject() {
        #expect(Self.model(shotType: .trunk).guidance == "Trunk · framed on its own")
        #expect(Self.model(shotType: .leaf).guidance == "Leaf close-up · framed on its own")
        // No ghost is stored for this fixture's tree, so full tree keeps its first-photo sentence.
        #expect(Self.model(shotType: .fullTree).guidance.contains("Full tree"))
        #expect(!Self.model(shotType: .trunk).guidance.contains("match"))
    }

    @Test("The caption says the overlay is off rather than that there is no ghost")
    func captionFollowsTheSubject() {
        #expect(Self.model(shotType: .trunk).ghostCaption == "overlay off · full-tree only")
        #expect(Self.model(shotType: .fullTree).ghostCaption == "no ghost yet · first photo")
    }

    @Test("A stored ghost is still not drawn over a close-up")
    func aStoredGhostIsNotDrawnOverACloseUp() async throws {
        let treeID = UUID()
        defer { try? FileManager.default.removeItem(at: try VisitGhostStore.url(for: treeID)) }
        #expect(VisitGhostStore.record(try Self.portraitJPEG(width: 400, height: 600),
                                       for: treeID, shotType: .fullTree))

        let model = VisitCameraModel(
            treeID: treeID,
            treeDisplayName: "A tree with a history",
            gpsAccuracyM: 9,
            api: VisitPreviewAPI(),
            outbox: VisitPreviewFixtures.outbox(),
            attribution: VisitPreviewFixtures.attribution
        )
        await model.load()
        #expect(model.ghost != nil, "the fixture wrote one; if this is nil the rest asserts nothing")

        #expect(model.showsGhost)
        model.shotType = .trunk
        #expect(!model.showsGhost)
        model.shotType = .leaf
        #expect(!model.showsGhost)
        model.shotType = .fullTree
        #expect(model.showsGhost)
    }

    // MARK: - 2 · Nothing on this screen may outgrow the phone

    /// The shipping screen 04, with a portrait ghost behind it, measured against a phone's width.
    ///
    /// Before `PhotoFill` this reported **627 pt** — which is where the note field and the Log visit
    /// button went. The window is real and the wait is real because the ghost is loaded in `.task`
    /// and a view that never appeared never loaded one.
    @Test("Screen 04 never measures wider than the display it is on")
    func theTrayStaysOnTheScreen() async throws {
        let treeID = VisitPreviewFixtures.cypress.id
        defer { try? FileManager.default.removeItem(at: try VisitGhostStore.url(for: treeID)) }
        #expect(VisitGhostStore.record(try Self.portraitJPEG(), for: treeID, shotType: .fullTree))

        let width: CGFloat = 393
        let height: CGFloat = 852
        let host = UIHostingController(rootView: VisitPreviewFixtures.camera())
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
            "screen 04 measured \(measured.width) pt wide on a \(width) pt phone; the tray is off-screen"
        )
    }

    /// The component's own guarantee, stated as a comparison, because the naive form is what was
    /// there and what somebody would reach for again.
    @Test("PhotoFill reports the width it is offered; scaledToFill does not")
    func photoFillClampsWhatScaledToFillDoesNot() throws {
        let image = try #require(UIImage(data: Self.portraitJPEG()))
        let proposal = CGSize(width: 393, height: 852)

        let naive = UIHostingController(rootView: VStack(spacing: 0) {
            ZStack { Image(uiImage: image).resizable().scaledToFill() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            Color.clear.frame(height: 100)
        })
        let guarded = UIHostingController(rootView: VStack(spacing: 0) {
            ZStack { PhotoFill(image: image) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            Color.clear.frame(height: 100)
        })

        #expect(naive.sizeThatFits(in: proposal).width > proposal.width)
        #expect(guarded.sizeThatFits(in: proposal).width == proposal.width)
    }
}
#endif
