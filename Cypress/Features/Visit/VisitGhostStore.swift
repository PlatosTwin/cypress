//
//  VisitGhostStore.swift
//  Cypress — Features/Visit
//
//  The ghost overlay's backing store: **the last full-tree photo of this tree**, kept so the next
//  visit can be lined up against it.
//
//  ── Why this is the product ──────────────────────────────────────────────────────────────
//  "The camera opens straight to a ghost overlay of the last photo so the timeline stays
//  comparable" (SCREENS 04 caption). It is the one artifact the official city app will never have,
//  and it is what turns a pile of photos into a time series a person can actually read. Everything
//  else on screen 04 is a form.
//
//  ── Why a separate cache rather than reading the photo table ─────────────────────────────
//  `LocalAPI.uploadPhoto` **moves** the captured binary out of the staging directory into its own
//  photo directory and records the filename as `photos.storage_key`. That directory is private to
//  `LocalAPI`, and reaching into it from a feature would be exactly the "no view touches the store
//  directly" rule ARCHITECTURE §4 forbids. So the ghost keeps its own downsampled copy, written at
//  the moment of capture:
//
//  - it is available immediately, without waiting for a drain;
//  - it survives termination, because it is in Application Support, not `tmp`;
//  - it is small (a 30 %-opacity alignment layer needs no detail), so keeping one per tree costs
//    nothing.
//
//  **Seam:** when photos start arriving from the server, the ghost should prefer the newest
//  `full_tree` photo from `TreeProfile.photos` and fall back to this cache. That is one `if let` in
//  `ghost(for:)`, and the call sites do not change. Which photos are eligible is
//  `Photo.isBestPhotoShot` over the set the device may show, **not** `isPublicBestPhotoCandidate`:
//  lining a shot up against your own last visit is not publication, and gating it on moderation is
//  what left this app with no photograph on any screen (ERRATA E37).
//

import Foundation
import UIKit

enum VisitGhostStore {

    /// The longest edge of a stored ghost. It is drawn full-bleed behind a live preview at 30 %
    /// opacity; anything sharper is bytes nobody sees.
    static let maximumEdge: CGFloat = 1_280
    static let compressionQuality: CGFloat = 0.7

    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("VisitGhosts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func url(for treeID: UUID) throws -> URL {
        try directory().appendingPathComponent("\(treeID.uuidString).jpg")
    }

    /// The ghost for a tree, or `nil` on a first visit.
    ///
    /// "On a first visit there is no ghost; that state is required" (BUILD-PLAN §9, "first-visit
    /// camera without ghost overlay"). `nil` is not a failure and the screen says so.
    static func ghost(for treeID: UUID) -> UIImage? {
        guard let url = try? url(for: treeID),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    /// Records a capture as this tree's ghost.
    ///
    /// Only `.fullTree` shots become ghosts — `ShotType.supportsGhostOverlay` is the rule, and it
    /// lives on the model. A trunk close-up is not something to line the next crown photo up
    /// against.
    @discardableResult
    static func record(_ imageData: Data, for treeID: UUID, shotType: ShotType) -> Bool {
        guard shotType.supportsGhostOverlay,
              let image = UIImage(data: imageData),
              let reduced = downscale(image, longestEdge: maximumEdge),
              let jpeg = reduced.jpegData(compressionQuality: compressionQuality),
              let url = try? url(for: treeID)
        else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            return true
        } catch {
            // A ghost that fails to write costs the *next* visit its alignment layer and nothing
            // else. It must never take the visit down with it.
            return false
        }
    }

    /// Aspect-preserving downscale. A no-op when the image is already small enough.
    static func downscale(_ image: UIImage, longestEdge: CGFloat) -> UIImage? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > longestEdge, longest > 0 else { return image }
        let scale = longestEdge / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
