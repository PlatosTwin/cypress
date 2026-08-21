//
//  VisitCameraController.swift
//  Cypress — Features/Visit
//
//  The AVFoundation half of screen 04.
//
//  ── The two paths, and which one is primary ──────────────────────────────────────────────
//  The **device path** is the product: a live `AVCaptureSession` behind the ghost overlay, so the
//  volunteer lines the crown up against last month's crown and taps once. That is the ten-second
//  visit.
//
//  The **library path** is the fallback BUILD-PLAN §9 requires ("camera permission ask and denied
//  fallback (photo library)"), and it doubles as the only path the simulator can run, because a
//  simulator has no camera device. Both facts point at the same code, which is why it is a real,
//  first-class path rather than a stub: it is exercised on every simulator run.
//
//  Nothing here decides *policy* — whether to ask, what to show when refused. That is the model's
//  job. This type reports what the hardware and the user have made possible and captures a frame
//  when asked.
//

import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class VisitCameraController {

    /// What the viewfinder can currently do.
    enum Availability: Equatable {
        /// Nothing has been attempted yet.
        case idle
        /// Permission has not been asked for.
        case undetermined
        /// A live session is running. The only state that draws a real preview.
        case running
        /// The user said no. Screen 04 falls back to the photo library and says why.
        case denied
        /// There is no capture device — a simulator, or hardware in use elsewhere. Same fallback,
        /// different sentence, because "allow camera access" is not actionable here.
        case unavailable
        /// The session failed to configure. Treated as `unavailable` by the UI; kept separate so
        /// the reason can be logged rather than guessed at.
        case failed(String)
    }

    private(set) var availability: Availability = .idle

    /// The session the preview layer renders. Non-nil only once configuration succeeded.
    private(set) var session: AVCaptureSession?

    private let output = AVCapturePhotoOutput()
    private var captureDelegate: PhotoCaptureDelegate?

    /// The device the session is running, kept so the zoom can be set on it. Nil on every path that
    /// leaves `availability` at anything but `.running`, which is what makes `zoomRange` honest on a
    /// simulator: there is no device, so there is no zoom, and screen 04 draws no control for one.
    private var device: AVCaptureDevice?

    /// Whether a real viewfinder is on screen. Drives the "no camera" viewfinder placeholder.
    var isLive: Bool { availability == .running }

    /// Whether the photo-library fallback should be offered.
    var needsLibraryFallback: Bool {
        switch availability {
        case .denied, .unavailable, .failed: return true
        case .idle, .undetermined, .running: return false
        }
    }

    // MARK: - Lifecycle

    /// Asks for permission if it has not been asked for, then starts the session.
    ///
    /// Safe to call more than once; a running session is left alone.
    func start() async {
        if case .running = availability { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            availability = .undetermined
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                availability = .denied
                return
            }
        case .denied, .restricted:
            availability = .denied
            return
        @unknown default:
            availability = .denied
            return
        }

        await configureAndRun()
    }

    func stop() {
        guard let session else { return }
        let running = session
        Task.detached(priority: .utility) { running.stopRunning() }
        self.session = nil
        self.device = nil
        zoomFactor = 1
        if case .running = availability { availability = .idle }
    }

    private func configureAndRun() async {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else {
            // The simulator lands here, every time.
            availability = .unavailable
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                availability = .failed("capture session refused the wide-angle input")
                return
            }
            session.addInput(input)
            session.addOutput(output)
        } catch {
            session.commitConfiguration()
            availability = .failed(String(describing: error))
            return
        }

        session.commitConfiguration()
        self.session = session
        self.device = device
        // A fresh session opens at the device's own floor, which is 1 on every wide-angle camera
        // and is read rather than assumed — `zoomFactor` is what the pinch multiplies, and starting
        // it anywhere but where the hardware is would make the first pinch jump.
        zoomFactor = device.videoZoomFactor
        availability = .running

        // `startRunning` blocks; keeping it off the main actor is what stops the tray from
        // stuttering as the screen appears.
        Task.detached(priority: .userInitiated) { session.startRunning() }
    }

    // MARK: - Zoom

    // ══════════════════════════════════════════════════════════════════════════════════════════════
    // **Pinch to zoom on the viewfinder** — reported from TestFlight, ruled in on 2026-08-21.
    //
    // Screen 04's own words are "line the crown up against last month's crown", and a street tree is
    // photographed from the pavement it is planted in: the crown of a mature plane is sixty feet up
    // and there is nowhere to step back to. Without a zoom the only framing available was the one
    // the pavement allowed.
    //
    // ── Why `videoZoomFactor` and not a transform on the preview ────────────────────────────────
    // A `scaleEffect` on `VisitCameraPreview` would enlarge the *preview* and leave the captured
    // frame exactly as wide as it always was — the volunteer would frame a crown, press the shutter,
    // and get the whole street back. `videoZoomFactor` is on the input device, so what is captured
    // is what was aimed. It is also the only one of the two that the ghost overlay can be trusted
    // against: the ghost is a photograph taken through the same pipeline.
    //
    // ── Why it is set rather than ramped ────────────────────────────────────────────────────────
    // `ramp(toVideoZoomFactor:withRate:)` animates the lens toward a *destination* over time, which
    // is what a `1×/2×/5×` button wants. A pinch has no destination: it has a factor per frame, and
    // a ramp behind it would lag the fingers by the length of the ramp and then overshoot when they
    // stopped. Every camera app sets the factor directly during the gesture, and that is what this
    // does. The clamp is where the care goes instead.
    // ══════════════════════════════════════════════════════════════════════════════════════════════

    /// What the lens is currently at. 1 on a device with no camera, where nothing draws a control
    /// for it.
    private(set) var zoomFactor: CGFloat = 1

    /// **NOT SPECIFIED** — SCREENS.md 04 draws no zoom, so this ceiling is chosen here.
    ///
    /// `videoMaxZoomFactor` on a modern iPhone is well over 100, and everything past the optical
    /// range of the lens in use is upscaling: past roughly 6× a street tree is a smear of green that
    /// a volunteer would then attach to a record as evidence. `maxAvailableVideoZoomFactor` — which
    /// is the *current* ceiling, and falls when the device is in a mode that restricts it — is taken
    /// as the hard limit and this is the softer one over the top of it.
    static let preferredMaxZoom: CGFloat = 6

    /// What a pinch may ask for, on the device currently running. `1...1` when there is no device,
    /// which is a range with nothing in it to reach and is how screen 04 knows to draw no control.
    var zoomRange: ClosedRange<CGFloat> {
        guard let device else { return 1...1 }
        let low = device.minAvailableVideoZoomFactor
        let high = min(device.maxAvailableVideoZoomFactor, Self.preferredMaxZoom)
        // A device whose current maximum is under our own floor would otherwise form an invalid
        // range and trap. `low` is the one number here that cannot be argued with.
        return low...max(low, high)
    }

    /// Whether the viewfinder can be zoomed at all. False on a simulator, on a refusal, and on the
    /// (theoretical) device whose range is a single point.
    var isZoomable: Bool { zoomRange.lowerBound < zoomRange.upperBound }

    /// Sets the lens to `factor`, held inside `zoomRange`.
    ///
    /// Silent on failure by design, and there is exactly one failure: `lockForConfiguration` throws
    /// when something else holds the device. A sentence on screen 04 saying the zoom did not take
    /// would be a sentence about the app, on the screen whose whole budget is ten seconds — and the
    /// viewfinder is already telling the truth, because it shows what the lens actually did.
    func setZoom(_ factor: CGFloat) {
        guard let device, isZoomable else { return }
        let clamped = VisitCameraZoom.clamp(factor, to: zoomRange)
        guard let _ = try? device.lockForConfiguration() else { return }
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
        zoomFactor = clamped
    }

    // MARK: - Capture

    /// Takes one frame. Returns JPEG bytes, or `nil` if the session is not live or the capture
    /// failed — the caller keeps "Log visit" disabled either way.
    func capturePhoto() async -> Data? {
        guard availability == .running, session?.isRunning == true else { return nil }

        let settings = AVCapturePhotoSettings()
        // Fastest path to a frame: this screen's budget is ten seconds for the whole visit, and a
        // quality-prioritized capture spends a visible fraction of it.
        settings.photoQualityPrioritization = .speed

        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] data in
                self?.captureDelegate = nil
                continuation.resume(returning: data)
            }
            captureDelegate = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - The zoom's arithmetic

/// What a pinch on screen 04's viewfinder asks the lens for.
///
/// Separate from the controller, and pure, because the controller cannot be exercised anywhere a
/// test runs: `AVCaptureDevice.default(...)` returns nil on every simulator, so `setZoom` is a
/// function that returns early on the only machine the unit suite has (`VisitCameraSessionTests`
/// records the same fact about the session). The clamp is the part that can be wrong in a way a
/// person would notice, so the clamp is the part that is testable.
enum VisitCameraZoom {

    /// `proposed`, held inside `range`.
    ///
    /// A non-finite proposal takes the floor rather than the nearest bound: `AVCaptureDevice`
    /// traps on a NaN `videoZoomFactor`, and a pinch whose two touches land on one point hands out
    /// exactly that. There is no "nearest" to a NaN, and the floor is the one answer that is never
    /// a surprise.
    static func clamp(_ proposed: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        guard proposed.isFinite else { return range.lowerBound }
        return min(max(proposed, range.lowerBound), range.upperBound)
    }

    /// Where a pinch of `magnification`, begun at `base`, wants the lens.
    ///
    /// Multiplicative and not additive, which is what makes a pinch feel like a pinch: doubling the
    /// distance between two fingers doubles the zoom wherever it started, so the same hand movement
    /// is the same change at 1× and at 4×. An additive gesture would crawl at the bottom of the
    /// range and leap at the top.
    static func factor(base: CGFloat, magnification: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        clamp(base * magnification, to: range)
    }
}

// MARK: - Delegate shim

/// `AVCapturePhotoOutput` still wants an NSObject delegate; this turns one callback into one
/// `async` return and is retained by the controller only for the length of the capture.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void
    private var hasCompleted = false

    init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
