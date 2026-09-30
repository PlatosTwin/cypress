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

    // MARK: - The wiring: what each screen actually hands the pinch (PR #195 review, finding 1)
    //
    // The two tests above prove `mask` and `isAimingCamera` separately, and neither proves the line
    // between them. The review's mutation showed it: both call sites hard-wired to `isAiming: true`
    // kept every test in this file green while each screen's pinch stayed armed over a still.
    //
    // So these read the `VisitCameraZoomPinch` value each screen builds, with a photograph staged
    // and again after `retake()`, and assert the `isAiming` it carries. The value is found by walking
    // the view with `Mirror`, which is how a SwiftUI view's stored modifiers are reachable in-process.
    // `@State` that is not installed hands back the value it was initialized with, so the model a
    // test stages a photograph on is the model the view reads. See `stateModel(of:)`.
    //
    // **Add-a-tree is walked from its photo well, not from `body`.** The well is inside the
    // composer's `GeometryReader`, whose content is a closure, and `Mirror` cannot see into a
    // closure. `VisitAddTreeView.photoWell(widthCeiling:)` is the call site itself, so this still
    // reads the value the screen passes; `addTreeCarriesThePinch` is what proves the well is in the
    // body. Screen 04's viewfinder is not behind a `GeometryReader` at the drawn sizes, so it is
    // walked from `body`.

    @Test("add-a-tree's well hands the pinch false over a photograph and true after a retake")
    func addTreeWiresItsAimToThePinch() throws {
        let view = VisitPreviewFixtures.addTree()
        let model: VisitAddTreeModel = try #require(Self.stateModel(of: view), "no model in the view")

        #expect(Self.pinches(in: view.photoWell(widthCeiling: .infinity)).map(\.isAiming) == [true])

        model.useLibraryImage(VisitPreviewFixtures.onePixelJPEG())
        let staged = try #require(model.photoPath, "the photograph was not staged")
        defer { try? FileManager.default.removeItem(atPath: staged) }
        #expect(
            Self.pinches(in: view.photoWell(widthCeiling: .infinity)).map(\.isAiming) == [false],
            "add-a-tree's well has a photograph in it and still hands the pinch isAiming: true"
        )

        model.retake()
        #expect(
            Self.pinches(in: view.photoWell(widthCeiling: .infinity)).map(\.isAiming) == [true],
            "add-a-tree's well is empty again after Retake and hands the pinch isAiming: false"
        )
    }

    @Test("screen 04 hands the pinch false over a photograph and true after a retake")
    func screen04WiresItsAimToThePinch() throws {
        let view = VisitPreviewFixtures.camera()
        let model: VisitCameraModel = try #require(Self.stateModel(of: view), "no model in the view")

        #expect(Self.pinches(in: view.body).map(\.isAiming) == [true])

        model.useLibraryImage(VisitPreviewFixtures.onePixelJPEG())
        defer {
            for path in model.draft.photoPaths {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }
        #expect(model.hasSnapped, "the photograph was not staged")
        #expect(
            Self.pinches(in: view.body).map(\.isAiming) == [false],
            "screen 04 has a photograph for this framing and still hands the pinch isAiming: true"
        )

        model.retake()
        #expect(
            Self.pinches(in: view.body).map(\.isAiming) == [true],
            "screen 04's framing is empty again after Retake and hands the pinch isAiming: false"
        )
    }

    // MARK: - The walk

    /// The model a view holds in `@State`, read the way the view reads it when it is not installed.
    private static func stateModel<Model: AnyObject>(of view: some View) -> Model? {
        for child in Mirror(reflecting: view).children where child.label == "_model" {
            for inner in Mirror(reflecting: child.value).children {
                if let model = inner.value as? Model { return model }
            }
        }
        return nil
    }

    /// Every `VisitCameraZoomPinch` stored anywhere in `root`'s value tree.
    ///
    /// Class instances are not entered: the models and the controller are classes, and nothing
    /// SwiftUI stores a modifier in on the paths walked here is one. The depth cap is a guard against
    /// an unexpectedly deep tree, not a limit the screens come near.
    private static func pinches(in root: Any) -> [VisitCameraZoomPinch] {
        var found: [VisitCameraZoomPinch] = []
        func walk(_ value: Any, depth: Int) {
            if let pinch = value as? VisitCameraZoomPinch {
                found.append(pinch)
                return
            }
            let mirror = Mirror(reflecting: value)
            guard depth < 200, mirror.displayStyle != .class else { return }
            for child in mirror.children { walk(child.value, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }
}
#endif
