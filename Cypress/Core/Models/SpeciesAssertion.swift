import Foundation

/// `species_assertions.source` (BUILD-PLAN §4).
public enum SpeciesAssertionSource: String, Codable, Sendable, Hashable, CaseIterable {
    case cityImport = "city_import"
    case community = "community"
    case org = "org"
    case aiSuggestion = "ai_suggestion"
}

/// A versioned species claim about a tree (BUILD-PLAN §4 `species_assertions`, PRODUCT §3).
///
/// Append-only: corrections never silently overwrite. A superseded assertion keeps its row and
/// points forward via `supersededBy`, so the full ID history is preserved (PRODUCT §3,
/// DECISIONS §2.5 P-M3).
///
/// No `deletedAt`: this table is not user-touchable in the soft-delete sense — history is the point.
public struct SpeciesAssertion: CoreEntity {
    public let id: UUID
    public let treeID: UUID
    /// Nullable for a genus-only or unknown claim (PRODUCT §3).
    public let speciesID: UUID?
    public let source: SpeciesAssertionSource
    /// `confidence numeric nullable` (BUILD-PLAN §4). 0…1.
    public let confidence: Double?
    public let assertedBy: UUID?
    /// Self-reference to the assertion that replaced this one.
    public var supersededBy: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        speciesID: UUID?,
        source: SpeciesAssertionSource,
        confidence: Double? = nil,
        assertedBy: UUID? = nil,
        supersededBy: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.treeID = treeID
        self.speciesID = speciesID
        self.source = source
        self.confidence = confidence
        self.assertedBy = assertedBy
        self.supersededBy = supersededBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The current assertion is the one nothing supersedes.
    public var isCurrent: Bool { supersededBy == nil }
}
