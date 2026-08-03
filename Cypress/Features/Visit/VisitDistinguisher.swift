//
//  VisitDistinguisher.swift
//  Cypress — Features/Visit
//
//  D6's second half: "show the two nearest **with a distinguishing trait each**".
//
//  ── Why this file exists at all ───────────────────────────────────────────────────────────
//  The trait the design intends is the species `id_tip` — "scale-like leaves, lemony when
//  crushed". `NearbyTree.tell` is `nil` for every row today, because the curated species pipeline
//  (BUILD-PLAN §8) has not landed, and BUILD-PLAN §15 forbids inventing one.
//
//  So D6 and §15 pull in opposite directions, and the resolution is: **distinguish on facts the
//  record actually carries.** A street number, a planting year, a city DBH range and a site type
//  are inventory data, not botany. They separate two records standing 8 m apart just as well as a
//  leaf shape does, and none of them is made up.
//
//  When the curated tips land, `.tell` becomes the first branch and everything below it becomes
//  the fallback for the long tail — no call site changes.
//

import Foundation

/// One side of a comparison: what to show under a candidate so it can be told from its neighbor.
struct VisitDistinguishingTrait: Equatable {
    /// The micro-label above the pair, e.g. `TELL THEM APART BY STREET NUMBER`.
    let dimension: String
    /// This candidate's value on that dimension.
    let value: String
    /// Whether the value is a curated `id_tip`, which reads as prose ("Its tell: …") rather than
    /// as a field.
    let isCuratedTell: Bool
    /// True when the value is already on the card in its own right — the species name is the card's
    /// title, and printing it twice under it reads as a bug rather than as a tell. The banner still
    /// names the dimension, which is the part that tells you *where to look*.
    let isRedundantWithCard: Bool
}

enum VisitDistinguisher {

    /// The traits for a pair of candidates, or `nil` when the two records are genuinely
    /// indistinguishable on everything they carry.
    ///
    /// Returning `nil` is a real answer and the UI says so out loud. Manufacturing a difference
    /// where the data has none is exactly the failure D6 exists to prevent, one layer up.
    static func traits(
        _ first: VisitCandidate,
        _ second: VisitCandidate
    ) -> (first: VisitDistinguishingTrait, second: VisitDistinguishingTrait)? {
        for dimension in Dimension.allCases {
            guard let a = dimension.value(for: first), let b = dimension.value(for: second) else { continue }
            guard a.caseInsensitiveCompare(b) != .orderedSame else { continue }
            func trait(_ value: String) -> VisitDistinguishingTrait {
                VisitDistinguishingTrait(
                    dimension: dimension.label,
                    value: value,
                    isCuratedTell: dimension == .tell,
                    isRedundantWithCard: dimension == .species
                )
            }
            return (trait(a), trait(b))
        }
        return nil
    }

    /// In priority order: the botanical tell first, then the facts a volunteer can check from the
    /// curb without knowing anything about trees.
    enum Dimension: CaseIterable {
        /// The curated `id_tip`. First, and today never available.
        case tell
        /// Two different species is the strongest separator there is.
        case species
        /// The street address on the city record — readable off the building you are standing at.
        case address
        /// `sidewalk cutout`, `median`, `park` — where the tree is planted.
        case siteType
        /// One tree was planted in 1998 and one in 2019; the difference is visible at a glance.
        case plantedYear
        /// The city's DBH range. A range, never a point — it may never be rendered as a measured
        /// value (`Core/Models/Geometry.swift`, `IntRange`).
        case cityDBH

        var label: String {
            switch self {
            case .tell: return "Tell them apart"
            case .species: return "Tell them apart by species"
            case .address: return "Tell them apart by address"
            case .siteType: return "Tell them apart by planting site"
            case .plantedYear: return "Tell them apart by age"
            case .cityDBH: return "Tell them apart by trunk size"
            }
        }

        func value(for candidate: VisitCandidate) -> String? {
            switch self {
            case .tell:
                return candidate.tell?.text
            case .species:
                // Only a separator when both rows actually name a species; two "Unidentified tree"
                // rows are not distinguished by their placeholder.
                guard candidate.nearby.speciesCommonName != nil || candidate.nearby.speciesScientificName != nil
                else { return nil }
                return candidate.displayName
            case .address:
                return candidate.tree.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            case .siteType:
                return candidate.tree.siteType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            case .plantedYear:
                guard let year = candidate.tree.plantedYear else { return nil }
                return "planted \(year)"
            case .cityDBH:
                guard let range = candidate.tree.dbhCityCmRange else { return nil }
                return "city record \(range.lowerBound)–\(range.upperBound) cm"
            }
        }
    }

    /// The copy shown when `traits` returns `nil`. Says what is true and asks for the tap anyway —
    /// the tap is what makes the attribution deliberate, which is the part D6 cannot give up.
    static let indistinguishableCopy =
        "These two records carry the same details. Pick the one you are standing at."
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
