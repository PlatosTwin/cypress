//
//  VisitCameraPreview.swift
//  Cypress — Features/Visit
//
//  The live viewfinder, and the thing that stands in for it when there is no camera.
//

import AVFoundation
import SwiftUI

/// Wraps `AVCaptureVideoPreviewLayer`. A layer-backed `UIView` rather than a hosted layer, so the
/// preview resizes with the frame instead of needing a manual `layoutSubviews` dance.
struct VisitCameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        // The viewfinder is full-bleed under a framing overlay; letterboxing it would put the
        // corners somewhere the photo is not.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The viewfinder when there is no live session: on a simulator, with the camera refused, or in
/// the moment before the session starts.
///
/// It draws `CypressGradient.cameraViewfinder` — the exact layered gradient SCREENS 04 specifies
/// for the viewfinder — so the screen is verifiable in a simulator and reads as a viewfinder
/// rather than as a black rectangle with an error in it.
struct VisitViewfinderPlaceholder: View {
    var body: some View {
        CypressGradientField(CypressGradient.cameraViewfinder)
            .accessibilityHidden(true)
    }
}
