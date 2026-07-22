//
//  SharePresentation.swift
//  Cypress — Features/Share
//
//  Screen 10 · Share. SCREENS.md lines 985–1011.
//
//  The one screen in the app that produces something public, which is why almost everything in this
//  file is a rule from DECISIONS §3 rather than a layout decision.
//
//  ── 1. The photo predicate is the public one, and it is deliberate ────────────────────────
//  `Photo` carries two visibility questions under two names, kept apart on purpose (ERRATA E37):
//  `isVisibleToItsContributor` is "I may see the photograph I took", and `isPubliclyVisible` is
//  "the world may see this", which is `moderation_state == approved` (BUILD-PLAN §10, A3).
//
//  A share card is a public surface. It is rendered so that a stranger with no app and no account
//  can open it, so it takes `isPubliclyVisible` — `TreeProfilePresentation.publiclyVisiblePhotos`,
//  which exists for exactly this call site. Screen 03 takes the other one and is right to: 03 runs
//  on the device that took the photograph.
//
//  The consequence is that **the share card never carries a photograph today**, because nothing in
//  the shipping app can set `.approved` — there is no moderation service, and marking a photo
//  approved to make a card render would be a claim about a review that never happened. That is not
//  a broken screen: SCREENS.md 10 §3 draws the thumbnail as a *Cypress gradient* (C22), not as
//  imagery, so the drawn state and the honest state are the same picture. When moderation ships,
//  approved photos start appearing here and nothing in this file changes.
//
//  ── 2. No attribution is rendered, so none can leak ───────────────────────────────────────
//  D11 forces anonymous public attribution for under-18 accounts regardless of the stored
//  preference, and `User.isPublicAttributionEffective` is the only predicate allowed to answer that
//  question. SCREENS.md 10 enumerates the sheet's contents — grabber, title, preview card,
//  destination row — and there is no name, no avatar and no "shared by" line anywhere in it. So this
//  screen has no attribution call site at all, which is the strongest form of compliance available:
//  there is nothing here for the predicate to gate. See ERRATA (E59) for the footnote the clickable
//  prototype carried and this spec drops.
//
//  ── 3. No photo location, and none is minted here ─────────────────────────────────────────
//  ERRATA E42 records that `Photo.publicCoordinate` is deliberately left unpopulated: the tree's own
//  pin is already exact and already public, so a photo coordinate adds nothing a public surface
//  needs and adds a second, independent record of where a person stood. E42 names screen 10 as
//  where that would be re-opened. It is not re-opened here. Nothing in this folder reads, writes or
//  derives a coordinate, and the card's location line is the *tree's* street address — a fact about
//  a public object, from the city's own inventory row.
//
//  No SwiftUI in this file.
//

import Foundation

// MARK: - Destinations

/// One target in 10 §4's row. Four, in the order SCREENS.md draws them.
///
/// The label is the enum's, not the caller's, so no screen can relabel a target it does not
/// implement.
enum ShareDestination: String, CaseIterable, Identifiable {
    case messages
    case instagram
    case airDrop
    case copyLink

    var id: String { rawValue }

    /// Verbatim from 10 §4.
    var label: String {
        switch self {
        case .messages: return "Messages"
        case .instagram: return "Instagram"
        case .airDrop: return "AirDrop"
        case .copyLink: return "Copy link"
        }
    }

    /// Whether the target is the pasteboard rather than a hand-off to another app.
    ///
    /// `Copy link` is the one of the four iOS can perform exactly as labelled. The other three name
    /// destinations that have no direct API — Instagram publishes none for links, and Messages and
    /// AirDrop are reached through the system share sheet, which *is* what those words mean on this
    /// platform. See `ShareView` for what each one does.
    var isPasteboard: Bool { self == .copyLink }

    var accessibilityHint: String {
        isPasteboard ? "Copies the public link" : "Opens the system share sheet"
    }
}

// MARK: - Presentation

/// The derivation the view renders, from one `TreeProfile`.
struct SharePresentation: Equatable {

    let profile: TreeProfile
    private let calendar: Calendar

    init(profile: TreeProfile, calendar: Calendar = .current) {
        self.profile = profile
        self.calendar = calendar
    }

    static func == (lhs: SharePresentation, rhs: SharePresentation) -> Bool {
        lhs.profile == rhs.profile
    }

    private var tree: Tree { profile.tree }

    // MARK: The card

    /// The card's headline. Same rule as the profile's H1 — a given name wins, the species common
    /// name is the fallback display everywhere — so a tree is called the same thing on the card as
    /// it is on the screen the card was shared from.
    var treeDisplayName: String { TreeProfilePresentation(profile: profile).title }

    /// `Great Highway at Judah · San Francisco` — 10 §3.
    ///
    /// The city is a constant because the product is one city deep at launch and NYC is
    /// import-ready rather than shipped (DECISIONS §4, "Scope boundaries"). A tree whose city row
    /// carries no address gets the city alone rather than a dangling separator.
    var locationLine: String {
        guard let address = tree.address, !address.isEmpty else { return ShareCopy.city }
        return "\(address) · \(ShareCopy.city)"
    }

    /// `cypress.app/sf/tree/<uuid>` — 10 §3's URL line.
    ///
    /// **A deliberate deviation from the mock.** SCREENS.md draws `cypress.app/sf/tree/9f3a`, a
    /// four-hex slug. Four hex digits are 65,536 values and the shipped inventory holds 195,309
    /// trees, so that slug cannot name one of them: it is a mock fixture, and rendering its shape
    /// would put a wrong identifier on a link somebody sends to a friend.
    ///
    /// What it is instead is the tree's own `id`, which the product already commits to as the
    /// public, immutable, citable identifier ("stable citable tree UUIDs", DECISIONS §2.5;
    /// "immutable UUIDs" §2.5 P-C3). Recorded in ERRATA (E60).
    var publicURL: URL {
        URL(string: ShareCopy.publicURLPrefix + tree.id.uuidString.lowercased())!
    }

    /// What the URL line prints. The scheme is dropped, exactly as the mock prints it.
    var publicURLText: String {
        ShareCopy.publicURLPrefix.replacingOccurrences(of: "https://", with: "")
            + tree.id.uuidString.lowercased()
    }

    // MARK: The season strip (A5, D5)

    /// The photos this **public** card may draw from.
    ///
    /// `isPubliclyVisible`, never `isVisibleToItsContributor`. See the file header for why, and
    /// `Photo`'s own for the two names.
    var publiclyVisiblePhotos: Series<Photo> {
        profile.photos.filter(\.isPubliclyVisible)
    }

    /// A3's best photo over the public set — the card's imagery when there is any.
    ///
    /// `isPublicBestPhotoCandidate` rather than `isBestPhotoShot`: the framing half alone would pick
    /// a photograph nobody approved. Nil today for every tree, and the card draws its C22 gradient,
    /// which is what SCREENS.md 10 §3 specifies anyway.
    var bestPublicPhoto: Photo? {
        publiclyVisiblePhotos.items
            .filter(\.isPublicBestPhotoCandidate)
            .max { left, right in
                if left.capturedAt != right.capturedAt { return left.capturedAt < right.capturedAt }
                return left.resolution < right.resolution
            }
    }

    /// Twelve months, January first (A5: "the most recent photo per calendar month across all
    /// years"), over the **public** set.
    ///
    /// A filled cell on a public card is a claim that a photograph of this tree exists publicly for
    /// that month. Computed over the device's own pending photos it would be a claim about pictures
    /// no stranger can open, so the same predicate that gates the thumbnail gates the strip.
    var foliageDensities: [FoliageStrip.Density] {
        let covered = publiclyPhotographedMonths
        return (1...12).map { covered.contains($0) ? .full : .thin }
    }

    var publiclyPhotographedMonths: Set<Int> {
        Set(publiclyVisiblePhotos.items.map { calendar.component(.month, from: $0.capturedAt) })
    }

    /// D5's driver, handed to `FoliageStrip`, which enforces the rule itself. `nil` for a site with
    /// no species and for a species whose habit no source states (ERRATA E9).
    var leafRetention: LeafRetention? { profile.species?.leafRetention }

    /// The C22 recipe behind the 72pt thumbnail, chosen by genus like every other tree thumbnail in
    /// the app.
    var thumbnailSpeciesName: String? { profile.species?.scientificName }

    var accessibilityLabel: String {
        "\(treeDisplayName), \(locationLine). Public link \(publicURLText)."
    }
}

// MARK: - Copy

/// Every string screen 10 renders, verbatim from SCREENS.md 10 unless noted.
enum ShareCopy {

    /// 10 §2, verbatim. Note it does *not* carry the tree's name — the earlier prototype's
    /// `Share {{ treeName }}` was replaced by a fixed title with the name on the card below it.
    static let title = "Share this tree"

    /// The city half of the card's location line. One city deep at launch (DECISIONS §4).
    static let city = "San Francisco"

    /// The public tree page's origin. W1 is a separate deliverable and is not built here
    /// (ARCHITECTURE §8), so this link has nothing behind it yet; see ERRATA (E60).
    static let publicURLPrefix = "https://cypress.app/sf/tree/"
}
