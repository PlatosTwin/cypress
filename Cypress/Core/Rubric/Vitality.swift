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
/// **The five anchor sentences are the owner's decision on ticket #261.** Before it, this file
/// carried PRODUCT §3's original draft-v0 sentences while `SCREENS.md` 05 §3 carried five different
/// ones — two handoff artifacts that had disagreed since the day both were distilled, not a
/// transcription error in either. The decision closes that fork rather than adjudicating it: the
/// approved sentences land in PRODUCT §3, `SCREENS.md` 05 §3 and here **together**, so the two
/// source tables and the app now state one rubric. RULINGS R13 still holds — `SCREENS.md` owns
/// screen copy, PRODUCT owns a class's meaning, and a dieback band is meaning.
///
/// The scale is a documented collapse of the seven i-Tree / Nowak urban crown-condition classes:
/// excellent → `.thriving`, good → `.good`, fair → `.fair`, poor → `.poor`, critical and dying
/// merged → `.severeDecline`. Their `dead` class is deliberately not a vitality class; it is the
/// `Appears dead` status segment, which opens a review flag where a vitality integer opens nothing.
///
/// Status: the rubric is still "draft v0 — needs urban forestry advisor sign-off before launch"
/// (PRODUCT §3, DECISIONS §2.5 P-C1). **#261 did not discharge that, and did not move ERRATA E30**
/// — the five per-class reference photographs are still the M2 entry gate and still do not exist.
/// What an advisor is being asked to underwrite is listed in the ruling; the raw value is the
/// integer 1–5 stored in `observations.vitality`, so a later mapping stays possible.
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

    /// Plain-language anchor sentence, verbatim from the rubric table (ticket #261).
    /// Always visible at rating time (D3) — never truncated, never moved into a view.
    ///
    /// **Every row states its dieback band, and the five bands partition the whole percents 0–100
    /// exactly once**: `.thriving` 0, `.good` 1–10, `.fair` 11–25, `.poor` 26–50, `.severeDecline`
    /// over half. The draft-v0 sentences did not: read literally, 0 percent satisfied both "no
    /// visible dieback" and "under 10% dieback", and 25 percent satisfied both "10 to 25%" and "25
    /// to 50%", so two of the values a rater is most likely to produce named two rows each.
    ///
    /// **Row 3 no longer mentions discoloration**, because the seasonality gate cannot exclude the
    /// month in which discoloration is normal. `Species.leafOnMonths` runs a deciduous window from
    /// the opening of new growth to the *close of the fall-color season*, so fall color sits inside
    /// leaf-on by construction — the intended behavior, and the same derivation ERRATA E33 repaired
    /// for a different bug. A tree in fall color is therefore in leaf, ratable, and discolored, and
    /// the old row 3 pointed its rater there. The repair is copy: adding a second condition to the
    /// gate would suppress the rubric in the fall for trees that are in leaf, which is what E33
    /// exists to prevent.
    public var anchor: String {
        switch self {
        case .thriving:
            return "No dead wood visible; canopy full for the season"
        case .good:
            return "1 to 10% of the crown is dead wood; canopy otherwise full"
        case .fair:
            return "11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf"
        case .poor:
            return "26 to 50% of the crown is dead wood or bare; large dead sections"
        case .severeDecline:
            return "Over half the crown is dead wood or bare in season; major limbs dead"
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
