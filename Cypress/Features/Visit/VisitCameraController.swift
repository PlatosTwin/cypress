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
        availability = .running

        // `startRunning` blocks; keeping it off the main actor is what stops the tray from
        // stuttering as the screen appears.
        Task.detached(priority: .userInitiated) { session.startRunning() }
    }

    // MARK: - Capture

    /// Takes one frame. Returns JPEG bytes, or `nil` if the session is not live or the capture
    /// failed — the caller keeps "Log visit" disabled either way.
    func capturePhoto() async -> Data? {
        guard availability == .running, session?.isRunning == true else { return nil }

        let settings = AVCapturePhotoSettings()
        // Fastest path to a frame: this screen's budget is ten seconds for the whole visit, and a
        // quality-prioritised capture spends a visible fraction of it.
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
