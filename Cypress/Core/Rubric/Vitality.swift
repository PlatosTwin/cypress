import Foundation

/// The anchored five-class vitality rubric (PRODUCT §3, "Vitality scale").
///
/// The label and the plain-language anchor sentence are carried **by the type**, verbatim from the
/// rubric table, because D3 requires the anchor sentence to be always visible at rating time. A
/// view renders `Vitality.rubric`; it never authors this copy, and there is no code path that can
/// show a class without its anchor.
///
/// Color is secondary coding only (D3) and therefore lives in the design system, not here.
///
/// Status: the rubric is "draft v0 — needs urban forestry advisor sign-off before launch"
/// (PRODUCT §3, DECISIONS §2.5 P-C1). Which rubric ultimately ships — USFS urban FIA crown classes
/// wholesale or this validated five-class derivative — is still open; the raw value is the integer
/// 1–5 stored in `observations.vitality`, so a later mapping stays possible.
public enum Vitality: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case severeDecline = 1
    case poor = 2
    case fair = 3
    case good = 4
    case thriving = 5

    /// Class label, verbatim from the PRODUCT §3 rubric table.
    public var label: String {
        switch self {
        case .thriving: return "Thriving"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .severeDecline: return "Severe decline"
        }
    }

    /// Plain-language anchor sentence, verbatim from the PRODUCT §3 rubric table.
    /// Always visible at rating time (D3) — never truncated, never moved into a view.
    public var anchor: String {
        switch self {
        case .thriving:
            return "Full, dense canopy for the season; vigorous new growth; no visible dieback"
        case .good:
            return "Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback)"
        case .fair:
            return "Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable"
        case .poor:
            return "Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious"
        case .severeDecline:
            return "Mostly bare in season; over 50% dieback; survival doubtful"
        }
    }

    /// The numeric class as stored in `observations.vitality` (BUILD-PLAN §4, `vitality int 1 to 5`).
    public var classNumber: Int { rawValue }

    /// The five rows in the order screen 05 presents them (D3, five full-width rows).
    ///
    /// **Worst at the top.** The design export draws the rows `1 · Severe decline` … `5 · Thriving`
    /// downward, and SCREENS.md 05 §3 transcribes them in that order; this constant said "best at
    /// the top" and listed the reverse, which nothing rendered until now. The order is part of the
    /// rubric rather than of the view, for the same reason the anchor sentences are: a rater who
    /// learns "the top row is the bad one" on one screen must not meet the opposite on another.
    public static let rubric: [Vitality] = [.severeDecline, .poor, .fair, .good, .thriving]

    public static func < (lhs: Vitality, rhs: Vitality) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Seasonality

extension Vitality {
    /// Whether a vitality rating may be collected for this species in this calendar month.
    ///
    /// PRODUCT §3, seasonality rule: "deciduous species are rated only in leaf-on season. The app
    /// suppresses the vitality UI off-season using species leaf phenology; structure flags remain
    /// available year-round."
    ///
    /// Evergreen and semi-deciduous species are ratable year-round: they carry foliage in every
    /// month, so "full, dense canopy **for the season**" is always answerable.
    ///
    /// **Unknown habit permits the rating** (ERRATA E9). The rule PRODUCT §3 states is narrow —
    /// *deciduous* species are suppressed off-season — and suppression is itself an assertion, that
    /// this tree is out of leaf right now. With no sourced habit we cannot make it, and the cost of
    /// the two errors is not symmetric: wrongly permitting costs one observation a rater can skip,
    /// wrongly suppressing removes the vitality UI from a tree for half the year with no way for
    /// anybody in the field to say otherwise.
    ///
    /// - Parameters:
    ///   - leafRetention: the species attribute that drives all phenology surfaces (D5), or `nil`
    ///     when no source states it.
    ///   - month: calendar month, 1–12.
    ///   - leafOnMonths: the months this species is in leaf, or `nil` when unknown.
    ///     See `Species.leafOnMonths`.
    public static func isRatingPermitted(
        leafRetention: LeafRetention?,
        month: Int,
        leafOnMonths: Set<Int>?
    ) -> Bool {
        guard (1...12).contains(month) else { return false }
        switch leafRetention {
        case nil, .evergreen?, .semiDeciduous?:
            return true
        case .deciduous?:
            // A deciduous species always has a window (`Species.leafOnMonths`), so this only
            // fires for a caller that has the habit but not the calendar; it does not suppress.
            guard let leafOnMonths else { return true }
            return leafOnMonths.contains(month)
        }
    }

    /// Convenience over a concrete species.
    public static func isRatingPermitted(for species: Species, month: Int) -> Bool {
        isRatingPermitted(
            leafRetention: species.leafRetention,
            month: month,
            leafOnMonths: species.leafOnMonths
        )
    }

    /// Why the vitality section is hidden, so the leaf-off state can say so rather than silently
    /// dropping a row (PRODUCT §5 M6, BUILD-PLAN §9 M2 "vitality suppressed leaf-off state").
    public enum Suppression: Sendable, Hashable {
        case none
        /// Deciduous species, out of leaf-on season. Structure flags stay available year-round.
        case leafOffSeason
    }

    public static func suppression(for species: Species, month: Int) -> Suppression {
        isRatingPermitted(for: species, month: month) ? .none : .leafOffSeason
    }
}
