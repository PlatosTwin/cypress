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
//  ── The 10 m floor refuses out loud, and the refusal is true ─────────────────────────────────
//  The owner's ruling of 2026-09-10 kept `DataDisputeLimits`' floor and required the refusal to be
//  explained. A fix too coarse to place the tree is therefore never attached silently and never
//  dropped silently: the location block says, with the numbers it has, that it was not used and
//  what would help. Whether the fix is too coarse is asked of `DataDisputeLimits.refusal` — the
//  same pure function the API enforces with — so the block and the rule that binds cannot disagree.
//
//  **What would help is not always Settings** (PR #185's orchestrator rulings 6 and 9). Precise
//  Location off is the one cause Settings can fix, and only then does the sentence send the reader
//  there. A 20 m fix among buildings with Precise Location on is told to try in the open or wait,
//  and a fix CoreLocation stated no radius for is refused without quoting the 25 m the provider
//  substitutes for it — that number is the app's, not the phone's (`MapLocationProvider.Precision`).
//  The block keeps listening while the screen is open, so a later, better fix replaces a refused one
//  (ruling 7); and while a fix is still pending under the pin chip, *Send report* waits for it rather
//  than sending "the pin is wrong" without the position the reporter asked to attach (ruling 8).
//  The wait is bounded (owner ruling 11): after `DataDisputeLocation.fixTimeout` with no fix, or as
//  soon as CoreLocation reports an error, the block says it could not find the location and *Send*
//  works for the other choices; *Use my current location* asks again. The 15 s start at the grant:
//  while iOS's permission prompt is up the block waits with no clock (the owner's ruling of
//  2026-09-29, `DataDisputeModel.armTimeoutIfWaiting`).
//
//  ── "There's no tree here" stands alone ─────────────────────────────────────────────────────
//  The owner's ruling of 2026-09-28: choosing it clears the other three chips and disables them,
//  and un-choosing it enables them again. An empty plot has no position, species or planted year to
//  correct, and a report saying both would be two claims that contradict each other.
//
//  ── What the city has ───────────────────────────────────────────────────────────────────────
//  Under each opened section, one quiet line quoting the record's own value (owner, 2026-09-28).
//  `DataDisputeOnFile` has what it reads and why a missing value draws no line at all.
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

/// Everything the location block reads off the app's one provider at one moment.
///
/// The availability and `MapLocationProvider.Precision`, together, because the block's sentence
/// needs both and they arrive from different callbacks: a reader who turns Precise Location on in
/// Settings changes `precision` without necessarily changing the fix. One value, so the view can
/// hand the model every change to either (`DataDisputeView`'s `onChange`).
struct DataDisputeFixReading: Equatable, Sendable {
    var availability: MapLocationProvider.Availability
    var precision: MapLocationProvider.Precision = .ordinary
    /// How many times CoreLocation has reported an error (`MapLocationProvider.failureCount`). A
    /// count rather than a flag, so a second error after a retry is a change the view hands over.
    var failureCount = 0
}

/// Why the block did not use a fix. Each arm has its own sentence (`DataDisputeCopy.locationRefusal`).
enum DataDisputeLocationRefusal: Hashable, Sendable {
    /// The fix states a radius over the floor. `isReduced` is whether Precise Location is off for
    /// Cypress — the only case where Settings is the answer.
    case tooCoarse(accuracyM: Double, requiredM: Double, isReduced: Bool)
    /// CoreLocation stated no radius at all. Refused rather than taken on trust (ruling 9), and the
    /// sentence quotes only the floor: the one number the reader could be shown here, 25 m, is the
    /// provider's pessimistic substitute and nothing the phone said.
    case accuracyUnknown(requiredM: Double, isReduced: Bool)

    var isReduced: Bool {
        switch self {
        case let .tooCoarse(_, _, isReduced), let .accuracyUnknown(_, isReduced): return isReduced
        }
    }
}

/// What the location block knows, after the reporter has (or has not) asked for their position.
///
/// Built from `MapLocationProvider` — the app's one location stack — and never from a second
/// `CLLocationManager`. The provider is the same object screen 01 asks with, so a grant made here
/// reports fixes everywhere, and a fix the map already holds is available here at once.
enum DataDisputeLocation: Hashable, Sendable {
    /// Nobody has asked yet.
    case notAsked
    /// Asked; the provider has no fix to give yet. *Send report* waits while the pin chip is on.
    case waiting
    /// The phone will not say where it is — the reader refused (`servicesOff == false`) or Location
    /// Services are off for the whole device.
    case off(servicesOff: Bool)
    /// A fix good enough to place the tree, attached as the suggested position.
    case captured(TreeDataDispute.SuggestedLocation)
    /// A fix that was not used. It is **not** attached; the refusal is what the block says instead.
    case refused(DataDisputeLocationRefusal)
    /// Asked, and no fix came: `fixTimeout` passed, or CoreLocation reported an error (owner ruling
    /// 11). Nothing is attached, *Send* is not held, and asking again starts over.
    case unavailable

    /// How long the block waits for a fix before it says it could not find one (owner ruling 11).
    /// Counted from the grant, never while the permission prompt is up (the owner's 2026-09-29 ruling).
    static let fixTimeout: Duration = .seconds(15)

    /// The block's answer to the provider's current state.
    ///
    /// A fix with a stated radius is tested with `DataDisputeLimits.refusal` itself — the rule the
    /// API enforces — asked about a dispute that raises only the location issue, so the only refusal
    /// it can return is the one about the fix. A fix with no stated radius is refused here, before
    /// the rule sees the substitute (`DataDisputeLocationRefusal.accuracyUnknown`).
    static func reading(_ reading: DataDisputeFixReading) -> DataDisputeLocation {
        let isReduced = reading.precision.isReduced
        switch reading.availability {
        case .notAsked, .waitingForFix:
            return .waiting
        case .denied:
            return .off(servicesOff: false)
        case .servicesOff:
            return .off(servicesOff: true)
        case let .located(coordinate, accuracyM):
            guard reading.precision.accuracyIsKnown else {
                return .refused(.accuracyUnknown(
                    requiredM: DataDisputeLimits.positionResolutionRadiusM, isReduced: isReduced
                ))
            }
            let fix = TreeDataDispute.SuggestedLocation(coordinate: coordinate, accuracyM: accuracyM)
            if case let .locationFixTooCoarse(accuracyM, requiredM) = DataDisputeLimits.refusal(
                issues: [.wrongLocation],
                suggestions: TreeDataDispute.Suggestions(location: fix)
            ) {
                return .refused(.tooCoarse(accuracyM: accuracyM, requiredM: requiredM, isReduced: isReduced))
            }
            return .captured(fix)
        }
    }

    /// Whether the block should offer the way to Settings — only for the states Settings can fix:
    /// location off, and a fix refused **because Precise Location is off**. A fix refused with
    /// Precise Location on is not helped by Settings, and offering it there sends the reader to a
    /// switch that is already on (PR #185's review, finding 2).
    var offersSettings: Bool {
        switch self {
        case .off: return true
        case let .refused(refusal): return refusal.isReduced
        case .notAsked, .waiting, .captured, .unavailable: return false
        }
    }

    /// Whether a new reading from the provider replaces this one while the screen is open.
    ///
    /// Everything the reporter asked for and did not get follows the provider: a pending fix, a
    /// refused one (ruling 7 — the first fix after `start()` is often coarse, and the next is often
    /// fine), and location off (the reader went to Settings and came back). A **captured** fix does
    /// not: it is the position the reporter was standing at when they accepted it, and a later one
    /// quietly replacing it would move their report. `notAsked` does not either: nobody asked.
    var followsTheProvider: Bool {
        switch self {
        case .waiting, .refused, .off, .unavailable: return true
        case .notAsked, .captured: return false
        }
    }
}

// MARK: - What the city has

/// The record's own values, for the one quiet line under each opened section (owner, 2026-09-28).
///
/// **Only what the record holds, and nothing when it holds nothing.** A missing value draws no line
/// rather than "The city has no planted year": `nil` here means the copy of the inventory on this
/// phone carries none, which is not the same statement as the city having none — a seed built
/// before a column existed, or an adapter that does not read it, answers `nil` for a city that
/// publishes the value (DECISIONS constraint 15: no civic content invented).
struct DataDisputeOnFile: Hashable, Sendable {
    /// The species as the profile names it: the common name, else the scientific one. A row whose
    /// scientific name the ingest never read (RULINGS R54) is quoted in the city's own wording, or
    /// not at all — the raw `:: …` string is not a name.
    let species: String?
    let plantedYear: Int?
    /// The record's street address, else its coordinate. The address is the city's own column and
    /// the thing a person standing on the block can compare; the coordinate is what the pin *is*,
    /// and it is what is left when the record has no address.
    let position: String?

    init(species: String?, plantedYear: Int?, position: String?) {
        self.species = species
        self.plantedYear = plantedYear
        self.position = position
    }

    init(_ profile: TreeProfile) {
        self.init(tree: profile.tree, species: profile.species)
    }

    /// The record's values. `species` is the profile's — for a city row, the seed's own
    /// `trees.species_current` (`LocalAPI.resolveSpecies` prefers the record's species), which sits
    /// in the read-only ATTACHed inventory that no claim on this device writes.
    init(tree: Tree, species: Species?) {
        if let species {
            if species.scientificNameIsUnread {
                self.species = species.cityWordingForUnreadName
            } else {
                self.species = SpeciesPickCopy.chosen(species)
            }
        } else {
            self.species = nil
        }
        self.plantedYear = tree.plantedYear
        if let address = tree.address?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty {
            self.position = address
        } else {
            let coordinate = tree.coordinate
            self.position = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }
    }

    /// The value for one opened section, or `nil` when there is nothing to quote. "There's no tree
    /// here" has no section of its own, and so no line.
    func value(for choice: DataDisputeChoice) -> String? {
        switch choice {
        case .wrongPlace: return position
        case .wrongSpecies: return species
        case .wrongPlantedYear: return plantedYear.map(String.init)
        case .noTree: return nil
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

    /// Turns a chip on or off, under the owner's rule that "There's no tree here" stands alone.
    ///
    /// Choosing it clears the other three; while it is on they cannot be chosen, and a tap on one is
    /// ignored rather than quietly turning "no tree" off. Un-choosing it enables them again, unticked
    /// — the values typed under them are still held, and come back if their chips are chosen again.
    mutating func toggle(_ choice: DataDisputeChoice) {
        if choices.contains(choice) {
            choices.remove(choice)
        } else if choice == .noTree {
            choices = [.noTree]
        } else if !isDisabled(choice) {
            choices.insert(choice)
        }
    }

    /// Whether a chip can be chosen right now. Only "There's no tree here" disables anything.
    func isDisabled(_ choice: DataDisputeChoice) -> Bool {
        choice != .noTree && choices.contains(.noTree)
    }

    /// The pin chip is on and the position the reporter asked for has not arrived yet.
    ///
    /// *Send report* waits while this is true (ruling 8). Sending now would file "the pin is wrong"
    /// without the position — which the reporter asked for and the block is still promising — and
    /// the fix would then land in a screen nobody is reading (PR #185's review, finding 3). A fix
    /// that resolves as refused ends the wait: the block has said why, out loud, and "the pin is
    /// wrong and my phone cannot say where the tree is" is a report the record admits. So does a fix
    /// that never comes (`.unavailable`, owner ruling 11): the wait is bounded, never permanent.
    var isAwaitingFix: Bool {
        choices.contains(.wrongPlace) && location == .waiting
    }

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
    /// No fix in `fixTimeout`, or a CoreLocation error (owner ruling 11). In the refusals' shape —
    /// what happened, "so … was not used", then what would help — and the help names the button,
    /// because asking again is the retry the ruling gives.
    static let locationUnavailable =
        "Your phone couldn’t find your location, so no position was used. Try again in the open, "
        + "then use your location again."
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
        case let .refused(refusal): return locationRefusal(refusal)
        case .unavailable: return locationUnavailable
        }
    }

    /// Why a fix was not used, and what would help — **true in each case** (rulings 6 and 9).
    ///
    /// Three parts. What the phone said about its accuracy: a stated radius, rounded up; or, when
    /// CoreLocation stated none, that it could not say — never the 25 m substituted for it. Then the
    /// floor and "so it was not used". Then the remedy, and only one of them is Settings: Precise
    /// Location off is the one cause the reader can change there. With it on, the honest advice is
    /// the sky and a moment, and the block does keep listening (ruling 7), so waiting is real advice.
    static func locationRefusal(_ refusal: DataDisputeLocationRefusal) -> String {
        let opening: String
        let requiredM: Double
        switch refusal {
        case let .tooCoarse(accuracyM, required, _):
            opening = "Your location is only good to within \(meters(accuracyM)) m"
            requiredM = required
        case let .accuracyUnknown(required, _):
            opening = "Your phone couldn’t say how accurate your location is"
            requiredM = required
        }
        let remedy = refusal.isReduced
            ? "Turn on Precise Location for Cypress in Settings, then try again."
            : "Try again in the open, or wait a moment."
        return opening + ", and a new position has to be good to within \(meters(requiredM)) m, "
            + "so it was not used. " + remedy
    }

    // What the city has on file, under each opened section (owner, 2026-09-28).
    static func cityHas(_ value: String) -> String { "The city has: \(value)" }

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

    /// Above the keyboard, to put it away — the number pad has no return key of its own.
    static let keyboardDone = "Done"

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
            // Unreachable from this screen: a coarse fix never enters `suggestions`, so the location
            // block's own sentence (`locationRefusal`) is the one a reader sees. This one has no
            // Precise Location in it because the rule's refusal does not know whether it is off,
            // and a sentence that does not know must not send anybody to Settings (ruling 6).
            return "Your location is only good to within \(meters(accuracyM)) m, and a new position "
                + "has to be good to within \(meters(requiredM)) m, so nothing was sent."
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
