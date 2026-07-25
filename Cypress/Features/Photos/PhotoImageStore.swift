//
//  PhotoImageStore.swift
//  Cypress — Features/Photos
//
//  The one place in the app that turns a `Photo` row into pixels on a screen (ERRATA E125).
//
//  ── Why a store and not a `.task` per image ───────────────────────────────────────────────
//  Screen 20 draws every photograph of a tree in a scroll view, and screen 03 draws one of the same
//  set as its hero. Loading per view means the hero is decoded again the moment somebody opens the
//  browser, and every photograph is decoded again each time it scrolls back into view — a full-size
//  phone photograph is around 12 megapixels, or 48 MB once decoded, so "again" is not free and
//  "several at once" is a jetsam report.
//
//  So: one cache, keyed by photo id, holding **downsampled** images. Downsampling happens in
//  ImageIO rather than by drawing into a smaller context, because `kCGImageSourceThumbnailMaxPixelSize`
//  decodes at the size asked for; the 48 MB never exists.
//
//  ── What it deliberately does not do ──────────────────────────────────────────────────────
//  **Evict.** A tree's photographs are tens of images at a few hundred KB decoded, and the store's
//  lifetime is the app's. A cache with an eviction policy nobody has measured is a policy that
//  evicts the hero on the frame it is drawn.
//
//  **Reach for a file.** Bytes come from `CypressAPI.photoData`, which is the boundary
//  ARCHITECTURE §4 requires; this layer knows a photo id and an image and nothing about where a
//  photograph is kept.
//

import Foundation
import ImageIO
import Observation
import UIKit

@MainActor
@Observable
final class PhotoImageStore {

    /// The longest edge a cached image is decoded to.
    ///
    /// A hero is 224 pt tall and a browser card a little more; at 3× that is under 700 px, so 1,400
    /// leaves room for a full-width iPad-ish layout without holding anything near the original.
    static let maximumEdge = 1_400

    private let api: (any CypressAPI)?
    private var images: [UUID: UIImage] = [:]
    /// Photographs whose bytes are gone or unreadable. Kept so a broken row is asked for once and
    /// draws its placeholder from then on, rather than retrying on every scroll.
    private var missing: Set<UUID> = []
    private var inFlight: Set<UUID> = []

    /// `nil` stands a screen up from fixtures with no bytes behind it — the same seam
    /// `ModerationModel` uses, and what previews and the screen sweep pass.
    init(api: (any CypressAPI)? = nil) {
        self.api = api
    }

    /// The image if it is already decoded. Never blocks and never starts a load: a `View` body must
    /// not have side effects.
    func image(_ id: UUID) -> UIImage? { images[id] }

    /// Whether this photograph has been looked for and is not there.
    func isMissing(_ id: UUID) -> Bool { missing.contains(id) }

    /// Decodes one photograph into the cache, if it is not there already.
    func load(_ id: UUID) async {
        guard let api, images[id] == nil, !missing.contains(id), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        guard let data = try? await api.photoData(id: id) else {
            missing.insert(id)
            return
        }
        let edge = Self.maximumEdge
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.downsample(data, maximumEdge: edge)
        }.value
        if let decoded {
            images[id] = decoded
        } else {
            missing.insert(id)
        }
    }

    /// Decodes at the size wanted rather than decoding and then shrinking.
    ///
    /// `nonisolated` and `static` so it can run off the main actor: this is the expensive half, and
    /// it is the half with no state to share.
    nonisolated static func downsample(_ data: Data, maximumEdge: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Without this, a photograph whose orientation lives in its container comes back on its
            // side — which is most photographs taken in portrait. `PhotoBinary` goes to some trouble
            // to keep that tag through the EXIF strip; throwing it away here would waste that.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumEdge
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
