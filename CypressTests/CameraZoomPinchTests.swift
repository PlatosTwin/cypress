//
//  CameraZoomPinchTests.swift
//  CypressTests
//
//  F33: add-a-tree's viewfinder gets screen 04's pinch zoom (RULINGS R80 item 5, extended by the
//  owner on 2026-09-28).
//
//  ── What this can decide, and what it cannot ──────────────────────────────────────────────
//  `ZoomTests` states the house position: a pinch cannot be synthesized in the unit suite, and the
//  lens it drives exists on no simulator (`AVCaptureDevice.default(...)` is nil, so
//  `VisitCameraController.isZoomable` is false and the gesture never arms). What reaches the lens is
//  `VisitCameraZoom`'s arithmetic, which `ZoomTests` already covers for both screens now that they
//  share it.
//
//  What F33 adds is a claim about composition: **add-a-tree's view carries the same gesture as
//  screen 04, armed by the same rule.** Both halves are decidable here:
//
//  - **The gesture is there.** A SwiftUI view's `body` has a concrete type, and a modifier applied
//    anywhere under it is part of that type. So `VisitCameraZoomPinch` appears in the type of
//    `VisitAddTreeView.body` exactly when some branch of the screen applies it. Removing it from the
//    well removes it from the type. The probe is calibrated against screen 04, which is known to
//    carry it, and against screen 02, which is known not to.
//  - **The rule is screen 04's.** `VisitCameraZoomPinch.mask` is the one place the gate is written,
//    and `VisitAddTreeModel.isAimingCamera` is the one input add-a-tree gives it.
//
//  What stays on the physical phone: that two fingers on the well move the lens, and that the pinch
//  and the composer's `ScrollView` do not fight over the same touches.
//

#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Pinch zoom on add-a-tree's viewfinder (F33)")
struct CameraZoomPinchTests {

    /// The full type of a view's `body`, which names every modifier applied under it.
    private static func bodyType(_ view: some View) -> String {
        String(reflecting: type(of: view.body))
    }

    private static let modifierName = String(reflecting: VisitCameraZoomPinch.self)

    @Test("add-a-tree's screen carries the camera pinch")
    func addTreeCarriesThePinch() {
        let addTree = Self.bodyType(VisitPreviewFixtures.addTree())
        #expect(
            addTree.contains(Self.modifierName),
            "VisitAddTreeView's body has no \(Self.modifierName) anywhere in it, so add-a-tree's viewfinder cannot be pinched"
        )
    }

    /// The probe, calibrated: it finds the gesture where it is known to be and does not find it where
    /// it is known not to be. Without both, a green `addTreeCarriesThePinch` could be a probe that
    /// always says yes.
    @Test("the probe finds the pinch on screen 04 and not on screen 02")
    func theProbeIsCalibrated() {
        #expect(
            Self.bodyType(VisitPreviewFixtures.camera()).contains(Self.modifierName),
            "screen 04 carries the pinch and the probe did not see it"
        )
        #expect(
            !Self.bodyType(VisitPreviewFixtures.identify()).contains(Self.modifierName),
            "screen 02 has no camera and the probe reported a pinch on it"
        )
    }

    @Test("the pinch takes touches only with a lens to move and a live frame to aim")
    func theGateIsBothConditions() {
        #expect(VisitCameraZoomPinch.mask(isZoomable: true, isAiming: true) == .all)
        #expect(VisitCameraZoomPinch.mask(isZoomable: false, isAiming: true) == .subviews)
        #expect(VisitCameraZoomPinch.mask(isZoomable: true, isAiming: false) == .subviews)
        #expect(VisitCameraZoomPinch.mask(isZoomable: false, isAiming: false) == .subviews)
    }

    /// Screen 04 stops aiming once the framing has a photograph (`hasSnapped`). Add-a-tree has one
    /// framing, so it stops once it has its photograph, and aims again after `Retake`.
    @Test("add-a-tree aims until it has its photograph, and again after a retake")
    func addTreeAimsUntilItHasAPhoto() throws {
        let model = VisitAddTreeModel(
            api: VisitPreviewAPI(),
            location: VisitLocationProvider(pinnedFix: .located(VisitPreviewFixtures.origin, accuracyM: 5)),
            attribution: VisitPreviewFixtures.attribution
        )
        #expect(model.isAimingCamera, "an empty well is not aiming")

        // The library path reaches `apply(imageData:)`, which is exactly what the shutter reaches.
        // `load()` is never called: it would start a capture session.
        model.useLibraryImage(VisitPreviewFixtures.onePixelJPEG())
        let staged = try #require(model.photoPath, "the photograph was not staged")
        defer { try? FileManager.default.removeItem(atPath: staged) }
        #expect(!model.isAimingCamera, "a well holding a still is still aiming")

        model.retake()
        #expect(model.isAimingCamera, "the well is empty again after Retake and is not aiming")
    }
}
#endif
