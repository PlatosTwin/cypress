//
//  VisitAddTreeModel.swift
//  Cypress — Features/Visit
//
//  "None of these? Add this tree" — the community add (ERRATA E127).
//
//  ── What was here before ──────────────────────────────────────────────────────────────────
//  The button, at full opacity, wired to dismiss the flow and record nothing. PROTOTYPE-FLOW §1.5
//  drew it inert and *said so* in the label — "None of these? Add this tree · not in this prototype",
//  `opacity:.55` — and the build kept the button and dropped the honesty. Meanwhile
//  `LocalAPI.addTree` has been complete and tested since the data layer landed, with the 10 m
//  proximity dedupe in it and no caller anywhere in the app.
//
//  ── Why this is not an invented screen ────────────────────────────────────────────────────
//  BUILD-PLAN §9's M2 list names "**duplicate-proximity warning on add-a-tree**" as a required,
//  unmocked state, and §7's endpoint table specifies the behaviour it warns about: "`POST /trees` —
//  Community add: requires photo, species optional; runs the proximity dedupe check (10 m, any
//  species) and returns conflict with the candidate list when it trips". So the *flow* is required
//  and its one hard state is named; what is missing is a mock of it. Per ARCHITECTURE rule 8 the
//  layout follows the nearest specified thing rather than inventing a look: it is screen 02's frame
//  and header, screen 14's dashed photo well, screen 04's two photo sources, and C24 for the warning.
//
//  ── The three gates, all of them the data layer's rules restated on screen ────────────────
//  1. **A photo is required.** `addTree` throws `validationFailed` without one (BUILD-PLAN §6). The
//     CTA is disabled until there is one, so the boundary and the button agree.
//  2. **A fix is required.** A community tree *is* a coordinate; there is nothing to add without
//     one, and D6 has no notion of a tree whose position is a guess.
//  3. **The 10 m dedupe is the API's, not this screen's.** Nothing here pre-checks it. The screen
//     calls `addTree` and renders `ProximityConflict`'s own candidate list, so the warning can never
//     disagree with the refusal — which is the failure mode a client-side copy of the rule has.
//
//  No SwiftUI in this file.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class VisitAddTreeModel {

    /// What the screen is in.
    enum Phase: Equatable {
        /// Collecting a photo and waiting for a fix.
        case composing
        /// `addTree` is running.
        case adding
        /// BUILD-PLAN §9 M2's "duplicate-proximity warning on add-a-tree". The candidates are the
        /// API's, and every one of them is inside 10 m of the spot — `LocalAPI.addTree` re-checks the
        /// exact metres before it refuses (ERRATA E35).
        case duplicate([NearbyTree])
        /// The add failed for a reason that is not a duplicate.
        case failed(String)
    }

    private let api: any CypressAPI
    private let location: VisitLocationProvider
    private let attribution: Attribution

    let camera = VisitCameraController()

    private(set) var phase: Phase = .composing
    /// The frame taken, and where it is staged on disk. Both, because the screen draws one and the
    /// API is handed the other — and a photo that could not be written to disk is not a photo.
    private(set) var snapshot: UIImage?
    private(set) var photoPath: String?
    /// Names the staged file. Minted once, so retaking overwrites rather than accumulating, exactly
    /// as `VisitPhotoStaging` names a visit's capture after the visit.
    private let captureID = UUID()

    init(api: any CypressAPI, location: VisitLocationProvider, attribution: Attribution) {
        self.api = api
        self.location = location
        self.attribution = attribution
    }

    // MARK: - Derived

    var fix: VisitLocationProvider.Fix { location.fix }

    var coordinate: Coordinate? { location.fix.coordinate }

    var hasPhoto: Bool { photoPath != nil }

    /// Gates 1 and 2, together. The button is disabled for exactly the reasons the API would refuse.
    var canAdd: Bool {
        hasPhoto && coordinate != nil && phase != .adding
    }

    /// `GPS ±8 m`, in screen 02's own words so the two screens of one flow say it the same way.
    var gpsChipLabel: String? {
        guard let accuracy = location.fix.accuracyM else { return nil }
        return "GPS ±\(Int(accuracy.rounded())) m"
    }

    /// Which sentence stands where the photo and the spot would be. `nil` once both gates are met.
    ///
    /// One property rather than a chain of `if`s in the view, so what the screen says about its own
    /// readiness is testable without a renderer — and so the reasons cannot be reported in an order
    /// that tells somebody to take a photo when the real obstacle is that the phone does not know
    /// where it is.
    var blockingReason: String? {
        if coordinate == nil {
            return location.fix == .denied
                ? VisitAddTreeCopy.noLocationDenied
                : VisitAddTreeCopy.noLocationPending
        }
        if !hasPhoto { return VisitAddTreeCopy.noPhoto }
        return nil
    }

    // MARK: - Lifecycle

    func load() async {
        location.start()
        await camera.start()
    }

    func stop() {
        camera.stop()
    }

    // MARK: - The photo

    func snap() async {
        guard let data = await camera.capturePhoto() else { return }
        apply(imageData: data)
    }

    /// The photo-library path — BUILD-PLAN §9 M1's camera-denied fallback, and the only path a
    /// simulator can take.
    func useLibraryImage(_ data: Data) {
        apply(imageData: data)
    }

    func retake() {
        snapshot = nil
        photoPath = nil
    }

    private func apply(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        do {
            photoPath = try VisitPhotoStaging.write(imageData, for: captureID)
            snapshot = image
            if case .failed = phase { phase = .composing }
        } catch {
            // Same rule screen 04's camera keeps: a photo that cannot survive termination is not a
            // photo, so `canAdd` stays false and the screen says why.
            phase = .failed(VisitAddTreeCopy.photoNotStored(error))
        }
    }

    // MARK: - The add

    /// Calls `POST /trees` and reports what came back.
    ///
    /// - Returns: the new tree's id, or nil. Nil is not always a failure the reader must fix —
    ///   `.duplicate` is the API doing its job, and the screen offers the tree it found instead.
    ///
    /// **No outbox.** Every other mutation in this app is enqueued first (ARCHITECTURE §4), and this
    /// one cannot be: `outbox.kind` has no `tree` value, the caller needs the new tree's id to be
    /// able to open it, and the dedupe answer is a *conversation* — a refusal the reader has to
    /// resolve by looking at the candidates — which is the one thing a fire-and-forget queue cannot
    /// carry. The API is local, so there is no round trip to survive; when a server exists this is
    /// the call that grows an outbox kind, and the shape of that work is the dedupe conflict arriving
    /// late rather than immediately.
    ///
    /// A success leaves the phase at `.adding`, which is not an oversight: the screen is on its way
    /// out — the flow opens the tree it just created — and `canAdd` staying false for those frames is
    /// what stops a second tap from writing a second tree 0 m from the first. The 10 m dedupe would
    /// refuse that one, so the consequence would be a duplicate warning naming the tree the reader
    /// had themselves just added, which is the most confusing sentence this screen could produce.
    func add() async -> UUID? {
        guard canAdd, let coordinate, let photoPath else { return nil }
        phase = .adding
        do {
            let tree = try await api.addTree(
                TreeDraft(
                    coordinate: coordinate,
                    // Species is optional on the endpoint, and the screen asks for none: a species
                    // this app cannot confirm would be fabricated botany (BUILD-PLAN §15), and the
                    // record it writes says `community-added, unverified` for exactly that reason.
                    photoLocalPath: photoPath,
                    attribution: attribution
                )
            )
            return tree.id
        } catch let conflict as ProximityConflict {
            phase = .duplicate(conflict.candidates)
            return nil
        } catch {
            phase = .failed(VisitAddTreeCopy.addFailed)
            return nil
        }
    }
}
