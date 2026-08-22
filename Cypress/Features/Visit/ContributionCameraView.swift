//
//  ContributionCameraView.swift
//  Cypress — Features/Visit
//
//  The in-app camera as a plain capture surface, for the contribution forms that attach
//  photographs without being a visit: the care log (09, task #168) and the check-in (05,
//  task #169).
//
//  ── Why this is not `VisitCameraView` itself ─────────────────────────────────────────────
//  Screen 04 is a *visit*: ghost overlay, three framing slots, phenology, its own save. What 09
//  and 05 need is only the shutter — the owner's report is that "to add a photo there's no
//  option to take one (or multiple)". So this reuses the camera the app already has — the same
//  `VisitCameraController` session, the same `VisitCameraPreview` layer, the same shutter and ✕
//  furniture, the same library fallback for a device (or simulator) with no camera — and draws
//  none of 04's visit-specific surface. Nothing camera-shaped is invented here.
//
//  Several frames per session, deliberately: each tap of the shutter hands one JPEG to
//  `onCapture` and the viewfinder stays live, so "take one (or multiple)" is one open-close.
//
//  Dark always, like every camera surface (ARCHITECTURE §6) — `.cypressForcedDark()`.
//

import PhotosUI
import SwiftUI

struct ContributionCameraView: View {

    /// One captured frame's bytes. Called once per shutter tap (or once per library pick when
    /// the camera cannot run); the caller stages and owns them.
    let onCapture: (Data) -> Void
    let onDone: () -> Void

    @State private var camera = VisitCameraController()
    @State private var libraryItems: [PhotosPickerItem] = []
    /// How many frames this session has handed out — the tray's receipt, and the flash's key.
    @State private var captureCount = 0
    /// The capture whose flash has already faded; same two-keyframe scheme as screen 04's.
    @State private var fadedCount = 0
    @State private var captureFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
            tray
                .background(CypressColor.Dark.bgCameraTray)
        }
        // The fill escapes the safe area, not the composed view — see `VisitCameraView.body`, which
        // carries the whole account of the build 25 report and of why the two are not the same
        // thing. This screen has no text field and so cannot show the keyboard half of that defect;
        // it is the same three lines over the same host and it is corrected with them, because the
        // next person to copy this pair should copy the version that paints its own ground.
        .background(CypressColor.Dark.bgCamera.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .cypressForcedDark()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        onCapture(data)
                        captureCount += 1
                    }
                }
                libraryItems = []
            }
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            if camera.isLive, let session = camera.session {
                VisitCameraPreview(session: session)
            } else {
                // No session: a simulator, a refusal, or the moment before the session starts.
                VisitViewfinderPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .bottom) { shutterBlock }
        .overlay { shutterFlash }
    }

    /// czFlash, keyed on the capture count the way 04 keys on its tick: only ever a capture, so
    /// nothing else can flash the screen white. Suppressed under Reduce Motion; there the tray's
    /// count line is the confirmation.
    @ViewBuilder
    private var shutterFlash: some View {
        if !reduceMotion {
            Color.white
                .opacity(captureCount > fadedCount ? CypressMotionOffset.flashOpacity : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onChange(of: captureCount) { _, count in
                    withAnimation(CypressMotion.flash) { fadedCount = count }
                }
        }
    }

    @ViewBuilder
    private var shutterBlock: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            if camera.needsLibraryFallback {
                // Screen 04's own sentence for the same state, in the same pill treatment —
                // plain text on a viewfinder is unreadable against a photograph.
                Text(fallbackReason)
                    .font(CypressFont.body125)
                    .foregroundStyle(VisitColor.guidancePillText)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, VisitMetrics.Camera.guidancePillPaddingV)
                    .padding(.horizontal, VisitMetrics.Camera.guidancePillPaddingH)
                    .background {
                        Capsule()
                            .fill(VisitColor.guidancePillFill)
                            .background { Capsule().fill(.ultraThinMaterial) }
                    }
                    .padding(.horizontal, CypressSpacing.gutter)

                PhotosPicker(selection: $libraryItems, matching: .images, photoLibrary: .shared()) {
                    VisitShutterButton(isLibrary: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose photos from your library")
            } else {
                Button {
                    Task {
                        if let data = await camera.capturePhoto() {
                            onCapture(data)
                            captureCount += 1
                            captureFailed = false
                        } else {
                            captureFailed = true
                        }
                    }
                } label: {
                    VisitShutterButton(isLibrary: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take a photo")
            }
        }
        .padding(.bottom, VisitMetrics.Camera.shutterBottom)
    }

    private var fallbackReason: String {
        switch camera.availability {
        case .denied:
            return "Camera access is off. Add the photo from your library instead."
        default:
            return "No camera available here. Add the photo from your library instead."
        }
    }

    /// The same ✕ screen 04 draws, and here it means what it means there over a live viewfinder:
    /// leave. Every frame already handed to `onCapture` is kept — the caller staged it — which is
    /// why this can share `onDone` rather than being a discard.
    private var closeButton: some View {
        Button(action: onDone) {
            ZStack {
                Circle().fill(VisitColor.cameraCloseFill)
                VisitCloseGlyph()
                    .stroke(
                        CypressColor.Dark.textSecondary,
                        style: StrokeStyle(
                            lineWidth: VisitMetrics.Camera.closeStroke,
                            lineCap: .round
                        )
                    )
                    .frame(width: VisitMetrics.Camera.closeGlyph, height: VisitMetrics.Camera.closeGlyph)
            }
            .frame(width: VisitMetrics.Camera.closeButton, height: VisitMetrics.Camera.closeButton)
        }
        .buttonStyle(.plain)
        .padding(.top, CypressSpacing.Device.statusBarInset)
        .padding(.leading, CypressSpacing.gutter)
        .accessibilityLabel("Close the camera")
    }

    // MARK: - Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: VisitMetrics.Camera.traySpacing) {
            if let line = addedLine {
                Text(line)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if captureFailed {
                Text(ContributionCameraCopy.captureFailed)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.accentAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PrimaryButton(ContributionCameraCopy.doneCTA, style: .camera) { onDone() }
        }
        .padding(.horizontal, VisitMetrics.Camera.trayPadding)
        .padding(.top, VisitMetrics.Camera.trayPadding)
        .padding(.bottom, VisitMetrics.Camera.trayBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The session's receipt. A count of what is in this one draft's hands, not of anything a
    /// person has done over time — D1 is about tallies on the record, and this line dies with
    /// the sheet.
    private var addedLine: String? {
        switch captureCount {
        case 0: return nil
        case 1: return "1 photo added"
        default: return "\(captureCount) photos added"
        }
    }
}

// MARK: - Copy

/// **NOT SPECIFIED** — no mock draws this surface; every sentence states a fact and stops
/// (ARCHITECTURE §5.7). The fallback sentences are screen 04's, verbatim, so one state has one
/// wording everywhere.
enum ContributionCameraCopy {
    static let doneCTA = "Done"
    /// Never claims a photo that was not taken — the same rule as every failed-save line.
    static let captureFailed = "That frame could not be captured. Try again."
}
