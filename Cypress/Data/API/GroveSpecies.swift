import Foundation

/// The payload behind `GET /me/grove`'s Species tab — screen 08, "Species you know".
///
/// Private by default (D11): there is no query here that could return another contributor's grove,
/// and nothing on this payload is ever published. No streaks and no leaderboards — screen 08 said
/// so in a §6 footnote until the copy audit of 2026-08-23 removed it (owner ruling), and the rule
/// was never the sentence's: it is D1's, and the shape of this type is what makes it true. This
/// carries species and dates, and no count of anybody's visits, photographs or care events (D1,
/// ARCHITECTURE §5.1), so there is nothing here to rank a contributor by whether or not a screen
/// says there is not.
///
/// **Why the two halves are separate.** The screen shows a ring reading `12 of 40 species` over the
/// caption `you can recognize in the Outer Sunset`, so the numerator is a fact about the
/// contributor and the denominator is a fact about the city's inventory of one neighborhood. They
/// come from different tables with different provenance and they are not sub-parts of one number:
/// the grid below the ring shows *every* species the contributor knows, including ones that do not
/// grow in their own neighborhood. Intersecting the two is `GrovePresentation`'s job, and
/// `Series.filter` keeps the completeness of both while it does it.
public struct GroveSpecies: Hashable, Sendable {

    /// Where this contributor's own trees are — A4: "resident neighborhood inferred from
    /// most-visited".
    ///
    /// `nil` on a device that has contributed nothing, because there is nothing to infer it from.
    /// That is the cold-start case rather than an error: a grove with no trees in it has no
    /// neighborhood, and a ring captioned "in the ___" cannot render (ARCHITECTURE §5.6).
    public let neighborhood: GroveNeighborhood?

    /// Every species this contributor has met, oldest first.
    ///
    /// A `Series` rather than an array because the ring prints its size: a page counted as a total
    /// is exactly the bug `Series` exists to make unwritable (ERRATA E38).
    public let known: Series<KnownSpecies>

    public init(neighborhood: GroveNeighborhood?, known: Series<KnownSpecies>) {
        self.neighborhood = neighborhood
        self.known = known
    }

    public static var empty: GroveSpecies { GroveSpecies(neighborhood: nil, known: .empty) }
}

/// The contributor's resident area and the species the city records growing in it.
///
/// "Neighborhood" in the type name is A4's word and stays; since R29 reached this screen the
/// area itself may be either of R29's two shapes, and the two are different promises the caption
/// keeps apart: a polygon is a *place*, the fallback is a stated *distance* around the
/// contributor's own most-visited tree, taken only when no tree they have touched carries a
/// polygon — which before this pass left every San Jose contributor's ring unrendered forever.
public struct GroveNeighborhood: Hashable, Sendable {

    /// The area: a polygon's name verbatim from the seed (A4, ERRATA E2 — never abbreviated or
    /// prettified, see ERRATA E47 for what that costs screen 08's caption), or R29's stated
    /// distance where no polygon covers anything the contributor has touched.
    public let area: AlmanacArea

    /// The distinct species of every city-inventory tree standing in this neighborhood — the
    /// ring's denominator.
    ///
    /// Species ids rather than a count, so the numerator can be computed by intersecting this with
    /// what the contributor knows without a second query that could disagree with it. It is a
    /// `Series` for the same reason `known` is: a partial read of the neighborhood would make the
    /// denominator too small and the ring too full.
    ///
    /// **City inventory only.** A community-added tree carries an unverified species assertion
    /// (DECISIONS §3.16, D12), and letting one into the denominator would let a contributor change
    /// their own denominator by adding a tree. The numerator is drawn from the same source for the
    /// same reason.
    public let species: Series<UUID>

    public init(area: AlmanacArea, species: Series<UUID>) {
        self.area = area
        self.species = species
    }
}

public extension CypressAPI {
    /// An implementation with no contribution store behind it has an empty grove.
    ///
    /// That is a true statement about such an implementation rather than a placeholder: screen 08
    /// renders its cold-start state from exactly this value, and the cold-start state is what a
    /// device that has contributed nothing should see (BUILD-PLAN §9 M2, "empty grove"). The
    /// default exists so that adding a preview double, or a second real client, does not have to
    /// invent a grove to compile. `LocalAPI` overrides it with the real read and `RemoteAPI`
    /// overrides it to throw, because a server that is not built yet has no answer at all — which
    /// is a different thing from an empty one.
    func groveSpecies() async throws -> GroveSpecies { .empty }
}

/// One species this contributor has met, and the first time they met it.
///
/// "Met" is any contribution — a visit, a check-in, a measurement, a care event — to a tree of this
/// species. It is deliberately not a count of those contributions: how many times you have stood in
/// front of a Ginkgo is not a thing this app tells you (D1).
public struct KnownSpecies: Hashable, Sendable, Identifiable {
    public var id: UUID { speciesID }

    public let speciesID: UUID
    public let scientificName: String
    /// The seed leaves `common_name` NULL for 11 of its 569 species; `LocalAPI` falls back to the
    /// scientific name exactly as `SpeciesQueries` does, because inventing a common name is
    /// fabricating content (BUILD-PLAN §15).
    public let commonName: String
    /// The earliest of this contributor's own contributions to a tree of this species.
    public let firstMetAt: Date
    /// The street address the city holds for that tree, when it holds one. Feeds the celebration
    /// callout's `on Noriega`; absent when the city recorded no address, which drops the clause.
    public let firstMetAddress: String?

    public init(
        speciesID: UUID,
        scientificName: String,
        commonName: String,
        firstMetAt: Date,
        firstMetAddress: String?
    ) {
        self.speciesID = speciesID
        self.scientificName = scientificName
        self.commonName = commonName
        self.firstMetAt = firstMetAt
        self.firstMetAddress = firstMetAddress
    }
}
