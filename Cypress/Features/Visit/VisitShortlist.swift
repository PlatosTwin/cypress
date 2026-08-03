//
//  VisitShortlist.swift
//  Cypress — Features/Visit
//
//  The decision layer behind screen 02. Foundation only, no SwiftUI: every rule D6 imposes is a
//  pure function of (candidates, GPS accuracy) and is therefore checkable without a simulator.
//

import Foundation

// MARK: - A row of the shortlist

/// One candidate on screen 02.
struct VisitCandidate: Identifiable, Hashable {
    let nearby: NearbyTree

    var id: UUID { nearby.tree.id }
    var tree: Tree { nearby.tree }
    var distanceM: Double { nearby.distanceM }

    /// The species common name, falling back to the scientific name, falling back to the honest
    /// "we do not know". The seed's long tail carries no species at all and inventing one would be
    /// fabricated botany (BUILD-PLAN §15).
    var displayName: String {
        nearby.speciesCommonName ?? nearby.speciesScientificName ?? "Unidentified tree"
    }

    /// Rendered only when it is a real second name — never a duplicate of the line above it, and
    /// never a name the ingest failed to read (`docs/rulings-pending/unread-species-name.md`). This
    /// is the "what tree is this?" list: a row of it reading `:: Magnolia` under the city's own word
    /// for the same tree is exactly the defect that ruling is about, one screen over.
    ///
    /// No sentence stands in for it here, for `MapTreeCard.meta`'s reason — this row is two lines
    /// and a distance, its second line is already absent across most of the seed, and the profile
    /// it opens carries the sentence.
    var latinName: String? {
        guard let scientific = nearby.speciesScientificName else { return nil }
        guard !Species.isUnreadScientificName(scientific) else { return nil }
        return scientific == displayName ? nil : scientific
    }

    /// `nil` until the curated species pipeline lands. The row renders **without** a tell rather
    /// than inventing one (BUILD-PLAN §15; the type documents this on `NearbyTree.tell`).
    var tell: IDTip? { nearby.tell }

    /// `6 m NE` — the distance line, mono, per SCREENS 02.
    func distanceLabel(from origin: Coordinate?) -> String {
        VisitBearing.label(distanceM: distanceM, from: origin, to: tree.coordinate)
    }
}

// MARK: - The shortlist itself

/// The result of ranking `treesNear` output against the current fix.
struct VisitShortlist: Equatable {

    /// What the screen is actually in.
    enum State: Equatable {
        /// Location is unavailable or denied — no ranking is possible at all.
        case noLocation
        /// A fix exists and nothing is within the search radius.
        case empty
        /// A fix exists, candidates exist, and the GPS is good enough to rank them.
        case ranked
        /// A fix exists but is too coarse to rank anything (BUILD-PLAN §9, "low-GPS state of
        /// what-tree-is-this"). Candidates still render; confirmation is always required.
        case lowAccuracy
    }

    let state: State
    let candidates: [VisitCandidate]
    /// The reported horizontal accuracy of the fix that produced this list, in metres. Stored on
    /// every contribution the flow writes (D6).
    let accuracyM: Double?
    /// D6: the two nearest sit inside GPS error of each other, so an explicit confirmation tap is
    /// required before anything is written.
    let requiresConfirmation: Bool
    /// The top card is highlighted without a tap because the geometry is unambiguous.
    let highlightsTopCandidate: Bool
    /// 0…1 for C28 under the top card. `nil` when there is nothing to be confident about.
    let topConfidence: Double?

    static let empty = VisitShortlist(
        state: .noLocation, candidates: [], accuracyM: nil,
        requiresConfirmation: true, highlightsTopCandidate: false, topConfidence: nil
    )

    // MARK: Tuning, all of it from the documents

    /// "GPS-ranked candidates … nearest first, up to 8."
    static let maximumCandidates = 8
    /// Wide enough to reach past the error circle in an urban canyon (D6: 20–50 m) without
    /// dragging in the next block.
    static let searchRadiusM: Double = 60
    /// Confidence hinting: "if the top candidate is within 3 m and the next is ≥10 m away,
    /// highlight the top card automatically."
    static let confidentTopDistanceM: Double = 3
    static let confidentRunnerUpDistanceM: Double = 10
    /// Above this, the fix cannot separate two street trees at all — D6's own numbers: street trees
    /// sit 6–10 m apart, so an error circle wider than 25 m is not a ranking, it is a guess.
    static let lowAccuracyThresholdM: Double = 25
    /// The accuracy assumed when the fix does not report one. Deliberately pessimistic: an unknown
    /// error circle must not silently unlock the no-confirmation path on an append-only record.
    static let assumedAccuracyM: Double = lowAccuracyThresholdM

    // MARK: Ranking

    /// Turns `treesNear` output into the screen's model.
    ///
    /// - Parameters:
    ///   - nearby: rows from `CypressAPI.treesNear`, any order.
    ///   - accuracyM: the fix's horizontal accuracy, `nil` when the fix does not report one.
    ///   - hasFix: whether there is a location at all.
    static func rank(_ nearby: [NearbyTree], accuracyM: Double?, hasFix: Bool = true) -> VisitShortlist {
        guard hasFix else { return .empty }

        let candidates = nearby
            .sorted { $0.distanceM < $1.distanceM }
            .prefix(maximumCandidates)
            .map(VisitCandidate.init(nearby:))

        guard !candidates.isEmpty else {
            return VisitShortlist(
                state: .empty, candidates: [], accuracyM: accuracyM,
                requiresConfirmation: false, highlightsTopCandidate: false, topConfidence: nil
            )
        }

        let effectiveAccuracy = accuracyM ?? assumedAccuracyM
        let isLowAccuracy = effectiveAccuracy > lowAccuracyThresholdM

        let first = candidates[0].distanceM
        let second = candidates.count > 1 ? candidates[1].distanceM : Double.infinity
        let separation = second - first

        // D6, the whole point: "when candidates sit within GPS error of each other, show the two
        // nearest with a distinguishing trait each and require an explicit confirmation tap."
        // Two candidates the error circle cannot separate are, from the phone's point of view, the
        // same candidate. A single candidate has nothing to be confused with.
        let ambiguous = candidates.count > 1 && separation < effectiveAccuracy

        // The auto-highlight rule, verbatim. D6 outranks it: a coarse fix can satisfy both, and
        // when it does, the confirmation wins and the highlight is withheld — a pre-selected card
        // under a "confirm by eye" chip is a contradiction the user would resolve by tapping past.
        let confident = first <= confidentTopDistanceM && second >= confidentRunnerUpDistanceM

        return VisitShortlist(
            state: isLowAccuracy ? .lowAccuracy : .ranked,
            candidates: Array(candidates),
            accuracyM: accuracyM,
            requiresConfirmation: ambiguous || isLowAccuracy,
            highlightsTopCandidate: confident && !ambiguous && !isLowAccuracy,
            topConfidence: confidence(topDistanceM: first, runnerUpDistanceM: second, accuracyM: effectiveAccuracy)
        )
    }

    /// C28's fraction.
    ///
    /// **This is a GPS-geometry confidence, not a species-identification confidence.** Nothing in
    /// the app knows how likely it is that this tree is a Monterey Cypress; what it knows is how
    /// well the fix separates this record from the next one. Two factors, both relative to the
    /// error circle, because a 4 m gap means everything at ±3 m and nothing at ±40 m:
    ///
    /// - `proximity`  — how far inside the error circle the nearest record sits.
    /// - `separation` — how much further the runner-up is, capped at one full error circle.
    ///
    /// The 0.4/0.6 split leans on separation, because being *closest by a clear margin* is what the
    /// card is claiming. On the drawn card's own numbers (`±9 m`, `3 m` / `9 m`… `14 m`) it lands
    /// within a point of the mock's 88 %.
    static func confidence(topDistanceM: Double, runnerUpDistanceM: Double, accuracyM: Double) -> Double {
        let circle = max(accuracyM, 1)
        let proximity = clamp(1 - topDistanceM / circle)
        let separation = runnerUpDistanceM.isFinite
            ? clamp((runnerUpDistanceM - topDistanceM) / circle)
            : 1
        return clamp(0.4 * proximity + 0.6 * separation)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

// MARK: - Phenology vocabulary

/// Which phenology chips screen 04 may offer for a species — D5, in one place, framework-free so it
/// can be checked without a simulator.
enum VisitPhenologyVocabulary {

    /// Seasonal order, so the row reads as a year rather than as an enum declaration.
    static let order: [PhenologyTag] = [.leafOut, .fullLeaf, .flowering, .fruiting, .fallColor, .bare]

    /// The chips to offer, in order.
    ///
    /// One gate left, and a ruling behind the two that fell (#151,
    /// R35 — an observer's tag is their report of
    /// what is in front of them, not the app's claim about the species, so what the record does
    /// not know cannot empty this row):
    ///
    /// - **No species record → nothing, still.** `VisitPhenologyChips` and `Chip.phenology(_:for:)`
    ///   are built over a non-optional `Species`; whether this last gate should also fall is
    ///   proposed, not done, in the pending ruling.
    /// - **The curated gate is gone.** It offered the row "for the curated 40 and nobody else",
    ///   and it is what left the owner of #151 in front of a flowering Cassia leptophylla —
    ///   mapped, sourced habit, `curated = 0` like 529 of the seed's 569 species — with no way to
    ///   say "flowering".
    /// - **The unknown-habit gate is gone** with it (`Species.availablePhenologyTags`). D5's
    ///   evergreen exclusion survives one layer down, because it is a sourced fact rather than a
    ///   gap in one: a known evergreen is still never asked about fall colour or bare.
    static func tags(for species: Species?) -> [PhenologyTag] {
        guard let species else { return [] }
        return order.filter { $0.isAvailable(for: species) }
    }
}

// MARK: - Bearing

/// `6 m NE` — SCREENS 02's distance line.
enum VisitBearing {

    static let compassPoints = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Initial great-circle bearing from `origin` to `destination`, in degrees clockwise from north.
    static func degrees(from origin: Coordinate, to destination: Coordinate) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLon = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func compass(from origin: Coordinate, to destination: Coordinate) -> String {
        let index = Int((degrees(from: origin, to: destination) / 45).rounded()) % compassPoints.count
        return compassPoints[index]
    }

    /// `6 m NE`, or just `6 m` when there is no fix to take a bearing from.
    ///
    /// Metres are whole numbers: the mock draws `3 m N` / `17 m S`, and a decimal on a number whose
    /// error bar is ±9 m would be false precision.
    static func label(distanceM: Double, from origin: Coordinate?, to destination: Coordinate) -> String {
        let metres = Int(distanceM.rounded())
        guard let origin, metres > 0 else { return "\(metres) m" }
        return "\(metres) m \(compass(from: origin, to: destination))"
    }
}
