//
//  VisitCameraZoomPinch.swift
//  Cypress — Features/Visit
//
//  Pinch to zoom the lens behind a live viewfinder. RULINGS R80 item 5 put it on screen 04, the
//  owner ruled on 2026-09-28 (F33) that the same item covers add-a-tree's viewfinder, and on
//  2026-09-29 that check-in (05) and care log (09)'s camera gets the same pinch.
//

import SwiftUI

/// The pinch that drives a `VisitCameraController`'s `AVCaptureDevice.videoZoomFactor`.
///
/// **One gesture, used by all three viewfinders that own a controller:** screen 04
/// (`VisitCameraView`), add-a-tree (`VisitAddTreeView`, F33), and the camera check-in (05) and care
/// log (09) open (`ContributionCameraView`, owner ruling of 2026-09-29). It was written inline on
/// screen 04 first. Add-a-tree owns its own `VisitCameraController` (`VisitAddTreeModel.camera`) and
/// had no zoom, so the gesture moved here rather than being copied. A second copy would have been a
/// second set of rules for the same lens: where a pinch starts, how it multiplies, and when it is off.
///
/// See `VisitCameraController.setZoom` for why this moves the *device* and not the preview, and
/// `VisitCameraZoom` for the arithmetic, which is where the testable part of a pinch lives.
struct VisitCameraZoomPinch: ViewModifier {

    let camera: VisitCameraController

    /// Whether the viewfinder is live rather than showing a still, so there is something to aim.
    /// Screen 04 passes `!hasSnapped`. Add-a-tree passes `VisitAddTreeModel.isAimingCamera`.
    /// `ContributionCameraView` passes `true`, because its viewfinder never shows a still.
    let isAiming: Bool

    /// Where the lens was when the current pinch began; `nil` between pinches.
    ///
    /// **`@GestureState` rather than `@State` and an `onEnded`** (PR #102 review). `@GestureState`
    /// resets itself when a gesture ends *or is cancelled*, so a pinch interrupted by a phone call
    /// or by the screen going away under it leaves nothing behind. The `@State` version has a path
    /// where the reset never runs, and a stale base makes the next pinch multiply from where an
    /// older one started. `PhotoViewerView` makes the same argument for its own two.
    @GestureState private var zoomBase: CGFloat?

    /// When the pinch takes touches at all.
    ///
    /// Off unless there is a lens to move (`camera.isZoomable`, false on every simulator and on a
    /// refusal), and off once the frame is a still, when there is nothing left to aim.
    ///
    /// `.subviews` hands every touch to the children and takes none here, which is what "off" means
    /// for a gesture. It is `including:` rather than iOS 18's `isEnabled:` because this app is
    /// iOS 17+.
    static func mask(isZoomable: Bool, isAiming: Bool) -> GestureMask {
        isZoomable && isAiming ? .all : .subviews
    }

    func body(content: Content) -> some View {
        content.gesture(pinch, including: Self.mask(isZoomable: camera.isZoomable, isAiming: isAiming))
    }

    /// `zoomBase` is where the lens was when the fingers landed, read once on the first update of
    /// each pinch. The controller stays the one place that knows where the lens *is*. This closure
    /// only ever reads it, and only at the start.
    ///
    /// The `?? camera.zoomFactor` is not defensive noise. It is the same value `updating` captures,
    /// so the first update of a pinch reads the lens correctly whichever of the two callbacks
    /// SwiftUI runs first.
    ///
    /// Untested on the glass, and it cannot be tested there from here: `isZoomable` is false on
    /// every simulator (`AVCaptureDevice.default(...)` is nil), so the gesture never arms. See
    /// `VisitCameraController`'s zoom block for what else on this path is waiting for the phone.
    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($zoomBase) { _, base, _ in
                if base == nil { base = camera.zoomFactor }
            }
            .onChanged { value in
                camera.setZoom(
                    VisitCameraZoom.factor(
                        base: zoomBase ?? camera.zoomFactor,
                        magnification: value.magnification,
                        in: camera.zoomRange
                    )
                )
            }
    }
}

extension View {
    /// Pinch to zoom `camera`'s lens while `isAiming`. See `VisitCameraZoomPinch`.
    func visitCameraZoomPinch(_ camera: VisitCameraController, isAiming: Bool) -> some View {
        modifier(VisitCameraZoomPinch(camera: camera, isAiming: isAiming))
    }
}
