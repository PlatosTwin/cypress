//
//  SpeciesGuide.swift
//  Cypress — Data/API
//
//  The payload behind screen 07. `GET /species/{id}` hands back a `Species`, and a `Species` is a
//  field-guide entry: what the tree is and how to recognize it. SCREENS.md 07 also draws *how
//  common it is nearby* — two count cards and a list of individuals — and none of that is a
//  property of the species record. So it travels here, beside it.
//

import Foundation

/// Screen 07's payload: the species record, plus the two things about its population that the
/// record cannot carry.
///
/// Every population number on this type is optional or a `Series`, and that is the point. A count
/// is only printable when the read that produced it was a whole read (ERRATA E38); an
/// implementation that cannot count has to say so rather than hand back a plausible zero.
public struct SpeciesGuide: Sendable {

    public let species: Species

    /// 07 §5's `In this inventory` card: inventoried trees of this species across the whole
    /// attached inventory.
    ///
    /// A **total**, never a page — `COUNT(*)` over the whole inventory. `nil` means this
    /// implementation did not count, which is not the same fact as `0`, and the card does not draw.
    ///
    /// **It counts the attached inventory, not a city, and the label now says so.** The built-in
    /// bundle is fused across `sf` and `us-ca-sj`, so this number spans two cities; the card read
    /// `In San Francisco` until `RULINGS R48`.
    public let cityTreeCount: Int?

    /// 07 §5's `Near you` card. `nil` when there is no location fix — no "your area" for a count
    /// to be about (A4) — and `nil` where the merged record does not cover the ground the caller is
    /// standing on (R29), which is a different absence with the same honest rendering: no card.
    public let nearYou: SpeciesNeighborhoodCount?

    /// 07 §6's `Nearby individuals`. Empty without a fix — a distance needs somewhere to be from.
    public let nearby: Series<NearbySpeciesTree>

    public init(
        species: Species,
        cityTreeCount: Int? = nil,
        nearYou: SpeciesNeighborhoodCount? = nil,
        nearby: Series<NearbySpeciesTree> = .empty
    ) {
        self.species = species
        self.cityTreeCount = cityTreeCount
        self.nearYou = nearYou
        self.nearby = nearby
    }
}

/// How many of this species stand in the area the caller is standing in.
///
/// A4 fixed "your area" as an SF Analysis Neighborhood; RULINGS R29 widened it for the merged
/// record: **a named polygon where the record holds one, a stated radius where it does not.** The
/// polygon is resolved through the nearest inventoried tree's `neighborhood_id` — the city's
/// assignment, not a second point-in-polygon implementation that could disagree with it (E44). A
/// coordinate no polygon covers falls back to `AlmanacLimits.fallbackRadiusM` around the caller,
/// and only where the inventory actually covers that ground — a circle in a city the record has
/// never heard of is no area at all, and then this whole value is `nil` and the card does not draw.
///
/// The two cases are different promises and the payload says which one it is making: the card's
/// label — `Near you` — happens to be exactly true of either, but a surface that wants the area's
/// name must go through `area`, where a distance can never be mistaken for a place (R29).
public struct SpeciesNeighborhoodCount: Hashable, Sendable {
    /// The area the count is scoped to: the polygon's seed-verbatim name, or the fallback distance.
    public let area: AlmanacArea
    /// Inventoried trees of this species inside it. A total.
    public let count: Int

    public init(area: AlmanacArea, count: Int) {
        self.area = area
        self.count = count
    }
}

/// One row of 07 §6 — an individual of this species, near the caller.
public struct NearbySpeciesTree: Hashable, Sendable, Identifiable {

    public var id: UUID { treeID }
    public let treeID: UUID

    /// The row's title. The tree's active name when it has one, else the street address the city
    /// recorded (SCREENS.md 07 §6 draws `Great Highway at Judah`, an address).
    ///
    /// `nil` when the city recorded no address and nobody has named it. 94 of the 195,309 seeded
    /// trees have no address, and a row for one of them draws no title rather than a placeholder.
    public let title: String?

    /// Great-circle meters from the caller. 07 §6 renders it as `220 m`.
    public let distanceM: Double

    /// Photographs on this tree. `nil` unless the whole series was read, so a page's size can never
    /// reach the screen as a total (ERRATA E38).
    public let photoCount: Int?

    /// The most recent check-in's vitality class, if this tree has ever been checked in on.
    /// 07 §6 renders it as the lowercased class label — `thriving`, `good`.
    public let vitality: Vitality?

    /// Which of this tree's photographs the row draws, chosen by `PhotoHero.choose` — the same
    /// rule the profile hero draws by (ERRATA E125, E204) — or `nil` when this device has no live
    /// photograph of this tree. `nil` is the common case: `photoCount` can be positive from a
    /// tree's whole population of photographers while this row still carries no id, because
    /// nothing here syncs another contributor's photograph down (`TreeProfile.ownPhotoIDs`'s own
    /// comment). The row draws the placeholder in that case, same as a tree with no photographs
    /// at all — a sparse section is the correct, honest output (ERRATA E204).
    public let heroPhotoID: UUID?

    public init(
        treeID: UUID,
        title: String?,
        distanceM: Double,
        photoCount: Int?,
        vitality: Vitality?,
        heroPhotoID: UUID? = nil
    ) {
        self.treeID = treeID
        self.title = title
        self.distanceM = distanceM
        self.photoCount = photoCount
        self.vitality = vitality
        self.heroPhotoID = heroPhotoID
    }
}

/// The two numbers screen 07 §6 needs and SCREENS.md does not give.
///
/// Both are **NOT SPECIFIED**. The section is drawn as a finished list with no query behind it, so
/// these are the narrowest readings of the drawing rather than a design: the mock shows exactly two
/// rows, and its farther row is `400 m`, so the search has to reach at least that far. Recorded in
/// ERRATA (E43) rather than settled quietly here.
public enum SpeciesGuideLimits {
    /// How far `Nearby individuals` looks. 500 m clears the `400 m` row the mock draws.
    public static let nearbyRadiusM: Double = 500
    /// How many rows it draws. Two, as drawn.
    public static let nearbyRowLimit = 2
}

// MARK: - Default implementation

public extension CypressAPI {

    /// The field-guide entry with no population facts attached.
    ///
    /// A default rather than a bare requirement because `speciesGuide` is the only method on the
    /// protocol whose answer an implementation may legitimately not have any of: `RemoteAPI` has no
    /// service to ask, and a preview double stands the screen up from a fixture. Both would
    /// otherwise have to write this same body, and the failure mode of writing it badly — returning
    /// `0` instead of "did not count" — is exactly what screen 07 must never render.
    ///
    /// `LocalAPI` overrides it, because `LocalAPI` has the inventory.
    func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        SpeciesGuide(species: try await species(id: id))
    }
}
