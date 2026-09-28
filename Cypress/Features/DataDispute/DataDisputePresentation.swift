//
//  DataDisputePresentation.swift
//  Cypress — Features/DataDispute
//
//  The pure half of the data-dispute screen (RULINGS R79, part 2): what the reporter has chosen,
//  what that turns into on the way to `raiseDataDispute`, and every sentence the screen can say.
//
//  ── The four choices and the three stored issues ────────────────────────────────────────────
//  R79 wrote three checkboxes, the third with a submenu ("wrong other metadata": a clearly wrong
//  planted year, or a recorded tree whose plot is empty). The owner's ruling of 2026-09-28 flattened
//  that into four plain choices and left storage alone, so the last two choices both file under
//  `wrong_metadata` — `DataDisputeChoice.issue` is the one place that mapping is written.
//
//  ── A suggestion exists only under its own choice ───────────────────────────────────────────
//  The draft keeps every value the reporter has entered, so un-choosing and re-choosing a chip does
//  not throw away a typed year. What reaches the API is filtered by the choices: `suggestions` reads
//  a value only when its chip is on. That is what keeps `Refusal.suggestionOutsideCheckedIssues`
//  unreachable from this screen by construction rather than by a guard — and it still has a sentence
//  of its own below, because the brief for this screen is that no refusal collapses into a generic
//  error, reachable or not.
//
//  ── The 10 m floor refuses out loud ─────────────────────────────────────────────────────────
//  The owner's ruling of 2026-09-10 kept `DataDisputeLimits`' floor and required the refusal to be
//  explained. A fix too coarse to place the tree is therefore never attached silently and never
//  dropped silently: the location block says, with both numbers, that it was not used and what to
//  turn on. The sentence is `DataDisputeCopy.refusal(_:)` for `.locationFixTooCoarse`, asked of the
//  same pure function the API enforces with, so the words under the control and the rule that binds
//  cannot disagree.
//

import Foundation

// MARK: - The four choices

/// The four plain options the owner ruled on 2026-09-28, in the order the screen draws them.
enum DataDisputeChoice: String, CaseIterable, Hashable, Sendable {
    case wrongPlace
    case wrongSpecies
    case wrongPlantedYear
    case noTree

    /// The stored issue this choice files under. The last two share one — see the file header.
    var issue: TreeDataDispute.IssueKind {
        switch self {
        case .wrongPlace: return .wrongLocation
        case .wrongSpecies: return .wrongSpecies
        case .wrongPlantedYear, .noTree: return .wrongMetadata
        }
    }
}

// MARK: - Where the reporter is standing

/// What the location block knows, after the reporter has (or has not) asked for their position.
///
/// Built from `MapLocationProvider.Availability` — the app's one location stack — and never from a
/// second `CLLocationManager`. The provider is the same object screen 01 asks with, so a grant made
/// here reports fixes everywhere, and a fix the map already holds is available here at once.
enum DataDisputeLocation: Hashable, Sendable {
    /// Nobody has asked yet.
    case notAsked
    /// Asked; the provider has no fix to give yet.
    case waiting
    /// The phone will not say where it is — the reader refused (`servicesOff == false`) or Location
    /// Services are off for the whole device.
    case off(servicesOff: Bool)
    /// A fix good enough to place the tree, attached as the suggested position.
    case captured(TreeDataDispute.SuggestedLocation)
    /// A fix the floor refused. It is **not** attached; the refusal is what the block says instead.
    case refused(DataDisputeLimits.Refusal)

    /// The block's answer to the provider's current state.
    ///
    /// A located fix is tested with `DataDisputeLimits.refusal` itself — the rule the API enforces —
    /// asked about a dispute that raises only the location issue, so the only refusal it can return
    /// is the one about the fix.
    static func reading(_ availability: MapLocationProvider.Availability) -> DataDisputeLocation {
        switch availability {
        case .notAsked, .waitingForFix:
            return .waiting
        case .denied:
            return .off(servicesOff: false)
        case .servicesOff:
            return .off(servicesOff: true)
        case let .located(coordinate, accuracyM):
            let fix = TreeDataDispute.SuggestedLocation(coordinate: coordinate, accuracyM: accuracyM)
            if let refusal = DataDisputeLimits.refusal(
                issues: [.wrongLocation],
                suggestions: TreeDataDispute.Suggestions(location: fix)
            ) {
                return .refused(refusal)
            }
            return .captured(fix)
        }
    }

    /// Whether the block should offer the way to Settings — the two states only Settings can fix.
    var offersSettings: Bool {
        switch self {
        case .off, .refused: return true
        case .notAsked, .waiting, .captured: return false
        }
    }
}

// MARK: - The draft

/// Everything the reporter has chosen and entered.
struct DataDisputeDraft: Hashable, Sendable {
    var choices: Set<DataDisputeChoice> = []
    var location: DataDisputeLocation = .notAsked
    /// The species the reporter says it is, from the app's own picker. `nil` is a real answer —
    /// "this is not what the city says, and I do not know what it is".
    var species: Species?
    /// As typed. Parsed by `plantedYear(currentYear:)`.
    var plantedYearText = ""
    var notes = ""

    /// The stored issues these choices raise.
    var issues: Set<TreeDataDispute.IssueKind> { Set(choices.map(\.issue)) }

    /// The suggested values, each read only under its own choice. See the file header.
    func suggestions(currentYear: Int) -> TreeDataDispute.Suggestions {
        var suggestions = TreeDataDispute.Suggestions()
        if choices.contains(.wrongPlace), case let .captured(fix) = location {
            suggestions.location = fix
        }
        if choices.contains(.wrongSpecies) {
            suggestions.speciesID = species?.id
        }
        if choices.contains(.wrongPlantedYear), case let .valid(year) = plantedYear(currentYear: currentYear) {
            suggestions.plantedYear = year
        }
        if choices.contains(.noTree) {
            // Not a boolean: the empty plot is a status suggestion, the owner's own instruction, and
            // `DataDisputeLimits.statusSuggestion` is the one value of it this round writes.
            suggestions.status = DataDisputeLimits.statusSuggestion
        }
        return suggestions
    }

    /// What the year field holds.
    enum PlantedYear: Hashable, Sendable {
        /// Nothing typed. Choosing "wrong planted year" without a replacement is a real report.
        case empty
        case valid(Int)
        /// Something typed that is not a year this screen will suggest.
        case invalid
    }

    /// Four digits, and not after this year. Nothing else is judged: a planted year is the city's
    /// fact to be corrected, and this screen has no business inventing a plausible range for it.
    func plantedYear(currentYear: Int) -> PlantedYear {
        let text = plantedYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard text.count == 4, text.allSatisfy(\.isASCIIDigit), let year = Int(text),
              year <= currentYear else { return .invalid }
        return .valid(year)
    }

    /// The notes, or `nil` when there is nothing in them but whitespace.
    var trimmedNotes: String? {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Why this draft may not be sent, as the sentence the screen shows, or `nil` when it may.
    ///
    /// **The API's own rule first**, through `DataDisputeLimits.refusal` — the same pure function
    /// `LocalAPI.raiseDataDispute` enforces with — so an empty draft is refused by the sentence that
    /// names that rule rather than by a year check it never reached. The year check is the screen's
    /// own and comes second: it only speaks when the year chip is on and the field holds something.
    func problem(currentYear: Int) -> String? {
        if let refusal = DataDisputeLimits.refusal(
            issues: issues, suggestions: suggestions(currentYear: currentYear)
        ) {
            return DataDisputeCopy.refusal(refusal)
        }
        if choices.contains(.wrongPlantedYear), plantedYear(currentYear: currentYear) == .invalid {
            return DataDisputeCopy.plantedYearInvalid
        }
        return nil
    }
}

private extension Character {
    /// `Character.isNumber` admits every script's digits and fractions ("½", "٣"); `Int.init` would
    /// then refuse them anyway, but a four-*character* check that counted them would be counting the
    /// wrong thing.
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - The words

/// Every string the dispute screen renders (ARCHITECTURE §5.7).
///
/// **No mock specifies any of it** — this screen is modeled on screen 06's structure by the owner's
/// ruling of 2026-09-28, and its copy is listed in full in the PR that adds it for the owner to rule
/// on (DECISIONS constraint 21). Typographic apostrophes throughout, as `TreeProfileCopy` uses.
enum DataDisputeCopy {

    // C1
    static let screenTitle = "Report a mistake"

    // The choices
    static let choicesLabel = "What’s wrong · choose any that apply"

    static func choice(_ choice: DataDisputeChoice) -> String {
        switch choice {
        case .wrongPlace: return "Pin is in the wrong place"
        case .wrongSpecies: return "Wrong species"
        case .wrongPlantedYear: return "Wrong planted year"
        case .noTree: return "There’s no tree here"
        }
    }

    // Pin is in the wrong place
    static let locationLabel = "Where the tree really is"
    static let locationHint = "Stand next to the tree, then use your location."
    static let useLocation = "Use my current location"
    static let locationWaiting = "Finding your location…"
    static let locationDenied =
        "Location is off for Cypress. Turn it on in Settings to use where you’re standing."
    static let locationServicesOff =
        "Location Services are off on this phone. Turn them on in Settings to use where you’re standing."
    static let openSettings = "Open Settings"

    static func locationCaptured(accuracyM: Double?) -> String {
        guard let accuracyM else { return "Your location is recorded." }
        return "Your location is recorded, good to within \(meters(accuracyM)) m."
    }

    /// The sentence the location block shows, for every state but the one with nothing to say yet.
    static func location(_ location: DataDisputeLocation) -> String {
        switch location {
        case .notAsked: return locationHint
        case .waiting: return locationWaiting
        case let .off(servicesOff): return servicesOff ? locationServicesOff : locationDenied
        case let .captured(fix): return locationCaptured(accuracyM: fix.accuracyM)
        case let .refused(refusal): return self.refusal(refusal)
        }
    }

    // Wrong species
    static let speciesLabel = "The right species"
    static let chooseSpecies = "Choose the species"
    static let changeSpecies = "Choose a different species"

    // Wrong planted year
    static let plantedYearLabel = "The right planted year"
    static let plantedYearPrompt = "Year, like 1998"
    static let plantedYearAccessibilityLabel = "Planted year"
    static let plantedYearInvalid = "A planted year has four digits and can’t be in the future."

    // Notes
    static let notesLabel = "Anything else"
    static let notesPrompt = "Add a note (optional)"
    static let notesAccessibilityLabel = "Note"

    // The dashed disclosure (C14), in screen 06's shape: an opening, the fact in bold, and the rest.
    //
    // **The emphasis is screen 06's own words for the same fact, and it is not softened.** R79 defers
    // sync-back to the city explicitly, and DECISIONS §3 constraint 3 (made permanent by D16) is that
    // the app never claims the city was told when it was not.
    static let disclosureOpening = "Your report is saved with your contributions, and you can take it "
        + "back from this tree’s page. Nothing on the map changes, and"
    static let disclosureEmphasis = "the city has not been notified"
    static let disclosureContinuation = ". Cypress does not send these reports to any city."

    // C6
    static let sendCTA = "Send report"

    /// Every refusal `DataDisputeLimits` can return, each as its own sentence.
    static func refusal(_ refusal: DataDisputeLimits.Refusal) -> String {
        switch refusal {
        case .noIssueChecked:
            return "Choose at least one thing that’s wrong."
        case .suggestionOutsideCheckedIssues:
            return "A suggestion was attached to something you didn’t choose, so nothing was sent."
        case let .locationFixTooCoarse(accuracyM, requiredM):
            return "Your location is only good to within \(meters(accuracyM)) m, and a new position "
                + "has to be good to within \(meters(requiredM)) m, so it was not used. Turn on "
                + "Precise Location for Cypress in Settings, then try again."
        case .unsupportedStatusSuggestion:
            return "Cypress can only record that there’s no tree here, so nothing was sent."
        }
    }

    /// Why a raise the rules allowed still did not land.
    static func raiseFailure(_ error: APIError) -> String {
        switch error {
        case .conflict:
            return "You already have a report on this tree. Take it back from the tree’s page to "
                + "send a new one."
        case .forbidden:
            return "Only city records can be reported here, so nothing was sent."
        case .notFound:
            return "This tree could not be found, so nothing was sent."
        default:
            return "Your report could not be saved. Nothing was sent."
        }
    }

    /// Meters as the sentences quote them: whole, and **rounded up**.
    ///
    /// Up rather than to nearest, and it matters at exactly one place: a fix good to 10.4 m is over
    /// the 10 m floor, and "only good to within 10 m … has to be good to within 10 m" would be a
    /// refusal contradicting itself. Rounding the accuracy up can only ever overstate the error,
    /// which is the honest direction for a number the reader is being told is too large.
    static func meters(_ value: Double) -> Int {
        Int(value.rounded(.up))
    }
}

// MARK: - Metrics

/// The screen's spacing, from screen 06's own rhythm (`ReportMetrics`) and the tokens under it.
enum DataDisputeMetrics {
    /// Gap between a section's micro-label and its content — `ReportMetrics.labelToChips`.
    static let labelToContent: CGFloat = ReportMetrics.labelToChips
    /// Gap between the pieces inside one section: a line, a control, a second line.
    static let insideSection: CGFloat = CypressSpacing.gapRows
    /// 06 §6: dashed disclosure `margin:14px 16px 0`.
    static let disclosureTop: CGFloat = ReportMetrics.disclosureTop
    /// Screen 05's sticky CTA block, which is the app's one drawn precedent for C6 pinned under a
    /// scrolling form.
    static let ctaTop: CGFloat = CheckInMetrics.ctaTop
}
