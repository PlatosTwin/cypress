import Foundation

/// Phenology vocabulary shared by photos and visits (PRODUCT §3 "Photo", BUILD-PLAN §4
/// `visits.phenology_tags`).
///
/// `visits.phenology_tags` is "validated against the species seasonal vocabulary" — see
/// `Species.availablePhenologyTags` and `PhenologyTag.isAvailable(for:)`. `fallColor` is not in an
/// evergreen's vocabulary (D5).
public enum PhenologyTag: String, Codable, Sendable, Hashable, CaseIterable {
    case leafOut = "leaf_out"
    case fullLeaf = "full_leaf"
    case fallColor = "fall_color"
    case bare = "bare"
    case flowering = "flowering"
    case fruiting = "fruiting"

    /// Whether this tag may be offered for a species (D5). Evergreens never get fall color.
    public func isAvailable(for species: Species) -> Bool {
        species.availablePhenologyTags.contains(self)
    }

    /// Filters a set of tags down to the ones the species can legitimately carry.
    /// Used when validating a `Visit` against the species seasonal vocabulary (BUILD-PLAN §4).
    public static func validated(_ tags: [PhenologyTag], for species: Species) -> [PhenologyTag] {
        tags.filter { $0.isAvailable(for: species) }
    }
}
