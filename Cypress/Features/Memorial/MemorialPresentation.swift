//
//  MemorialPresentation.swift
//  Cypress — Features/Memorial
//
//  Screen 19 · Memorial. SCREENS.md lines 1315–1356.
//
//  A removed tree's profile: read-only, history intact. Screen 01 already draws the entrance —
//  removed trees are gray dash-marked pins, "memorials, tappable to screen 19" — so unlike most
//  screens this one is arrived at rather than invented.
//
//  ── The three rules that shape this file ──────────────────────────────────────────────────
//  - **An observation never mutates `trees.status`** (DECISIONS §3.7, BUILD-PLAN §6). A tree is a
//    memorial because a moderator or coordinator confirmed a review flag, never because somebody
//    checked in. Nothing here writes anything at all; the screen is a read, and `TreeStatus
//    .isMemorial` is the only question it asks.
//  - **Counts must be honest** (ERRATA E38). The hero's `86 photos · 2019–2026` is two claims about
//    a whole series, so it is drawn from `Series.totalCount` and vanishes when the read was a page.
//    Same for the caretaker clause on the first-photo row, which is A8's and floored at three.
//  - **A sentence with a fact the record does not carry is left out, not filled in.** Two of
//    SCREENS.md 19's drawn facts have no column behind them anywhere in BUILD-PLAN §4 — the removal
//    *date* and the removal *reason* ("storm damage") — so the clauses that need them do not render.
//    See `MemorialFacts.removedAt` and ERRATA.
//
//  ── Read-only is an absence, not a state ──────────────────────────────────────────────────
//  "no Visit CTA, no quad action row, no foliage strip. That absence *is* the read-only state." So
//  there is no `isReadOnly` flag here and no disabled styling anywhere: this presentation simply has
//  no CTA to offer and no strip to describe, and a reader of this type cannot ask it for one.
//
//  No SwiftUI in this file (`CypressTests/MemorialPresentationTests.swift`).
//

import Foundation

// MARK: - The facts the payload cannot carry

/// The two facts SCREENS.md 19 draws that `TreeProfile` has no column for.
///
/// **BUILD-PLAN §4's `trees` has no `removed_at` and no removal reason.** The status enum records
/// *that* a tree is removed and nothing about when or why. So:
///
/// - `Removed by the city, May 2026.` (§2) loses its date;
/// - `Red Flowering Gum · Corymbia ficifolia · 2003–2026` (§3) loses its closing year, and with it
///   the whole range, because a range with one end is not a range;
/// - `On record · 23 years` (§6) is that same subtraction and loses the card;
/// - `City record · marked removed · storm damage` (§4) loses the row, since without a date it is
///   not a moment on a timeline, and the reason has no column at all.
///
/// Two candidate sources exist and choosing between them is a schema decision (DECISIONS constraint
/// 20: "all schema changes via checked-in migrations"), not a decision for this screen:
///
/// 1. a `trees.removed_at` column set by the weekly diff (BUILD-PLAN §7), which is the direct
///    answer and the one an export would want;
/// 2. the confirmed `review_flags` row — §7 opens `removed_but_active` for exactly the trees that
///    have a timeline worth memorialising, and its confirmation is the moment the status changed.
///
/// This type is the seam for both: it is what a payload would fill, it is `nil` today, and every
/// sentence that needs it already knows how to be written without it. Recorded in ERRATA.
struct MemorialFacts: Equatable {
    /// When the record was marked removed. Nil until a column or a flag read exists.
    let removedAt: Date?

    /// Nothing known — what every tree in the shipped store resolves to today.
    static let unknown = MemorialFacts(removedAt: nil)

    init(removedAt: Date? = nil) {
        self.removedAt = removedAt
    }
}

// MARK: - Presentation

/// Everything screen 19 renders, derived from one `TreeProfile` plus what the record knows about the
/// removal.
struct MemorialPresentation: Equatable {

    /// One C9 row of §4's timeline.
    struct Moment: Equatable, Identifiable {
        /// Which of the four the row is, which decides its thumb (C9 `Leading`).
        enum Kind: Equatable {
            case firstPhoto
            case visit
            case checkIn(Vitality)
            case cityRecord
        }

        let id: UUID
        let kind: Kind
        /// The bold lead-in: `First photo` / `Visit` / `Check-in` / `City record`.
        let label: String
        /// Everything after it, verbatim including its separator.
        let detail: String
        /// Trailing mono stamp, e.g. `Mar 2019`.
        let timestamp: String
    }

    /// One card of §6's grid.
    struct Stat: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
    }

    /// §1's bottom-right pill, `86 photos · 2019–2026`, or nil when the series was a page.
    let heroMetaPill: String?
    /// §1's bottom-left eyebrow, `Last photo · Apr 2026`.
    let heroEyebrow: String?

    /// §2's banner: the bold lead-in and the rest, both verbatim.
    let bannerLeadIn: String
    let bannerBody: String

    /// §3.
    let title: String
    let subtitle: String
    let badge: StatusBadge.Kind

    /// §4, oldest first.
    let moments: [Moment]

    /// §5's green callout, or nil where its sentence would not be true.
    let lineageLeadIn: String?
    let lineageBody: String?

    /// §6.
    let stats: [Stat]

    /// The map this screen can send the reader to (ERRATA E144).
    ///
    /// **A memorial gets it too, and the record is what makes it honest.** The tree is gone; the
    /// place is not, and the coordinate is one of the few things about a removed tree that is still
    /// exactly true. C19 draws the record as the grey dash-marked pin screen 01's own caption calls
    /// a memorial (RULINGS R7), so the map states what kind of record it is without this screen
    /// having to add a sentence about it — and a reader who came here from My Grove or the journal
    /// can go and stand where it stood.
    let locateSet: PinSet

    // MARK: - Derivation

    init(
        profile: TreeProfile,
        facts: MemorialFacts = .unknown,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        let tree = profile.tree
        let photos = profile.photos.filter { profile.isOwnPhoto($0) ? $0.isVisibleToItsContributor : $0.isPubliclyVisible }
        let visits = profile.visits.filter { $0.deletedAt == nil }
        let observations = profile.observations.filter { $0.deletedAt == nil }
        let removalYear = facts.removedAt.map { calendar.component(.year, from: $0) }

        self.heroMetaPill = MemorialCopy.heroMetaPill(
            photos: photos,
            removalYear: removalYear,
            calendar: calendar
        )
        self.heroEyebrow = photos.items.map(\.capturedAt).max().map {
            MemorialCopy.lastPhotoEyebrow(MemorialCopy.monthYear.string(from: $0))
        }

        self.bannerLeadIn = MemorialCopy.bannerLeadIn(removedAt: facts.removedAt)
        self.bannerBody = MemorialCopy.bannerBody

        self.title = MemorialCopy.title(profile: profile)
        self.subtitle = MemorialCopy.subtitle(
            profile: profile,
            title: MemorialCopy.title(profile: profile),
            plantedYear: tree.plantedYear,
            removalYear: removalYear
        )
        // Never computed from vitality here. §3 draws `REMOVED` and C13's own mapping puts
        // `status.isMemorial` ahead of every other badge, so a memorial cannot show `THRIVING`
        // because its last check-in was a five.
        self.badge = .removed

        // Named with §3's H1, which is what the reader has just read.
        self.locateSet = PinSet.locate(profile, name: MemorialCopy.title(profile: profile))

        self.moments = Self.moments(
            photos: photos,
            visits: visits,
            observations: observations,
            caretakerCount: Self.caretakerCount(profile: profile, now: now, calendar: calendar),
            removedAt: facts.removedAt,
            calendar: calendar,
            locale: locale
        )

        // §5 is about the *city* replanting a site it owns. A community-added record has no city
        // behind it and no site the city will replant, so the promise is not made there.
        if tree.source == .cityImport {
            self.lineageLeadIn = MemorialCopy.lineageLeadIn
            self.lineageBody = MemorialCopy.lineageBody
        } else {
            self.lineageLeadIn = nil
            self.lineageBody = nil
        }

        self.stats = Self.stats(tree: tree, plantedYear: tree.plantedYear, removalYear: removalYear)
    }

    // MARK: - §4 The timeline

    /// The four moments SCREENS.md 19 draws, oldest first.
    ///
    /// **This is not screen 03's activity feed.** 03 lists recent contributions newest-first and
    /// caps them at four; 19 draws a life, in order: the beginning, the last time somebody came, the
    /// last time anybody looked closely, and the end. Reading the mock as "the four most recent
    /// rows" is contradicted by its own first row, which is the *oldest* thing on the tree.
    ///
    /// **Judgment call, and the spec gives one instance and no rule** (ERRATA). What was chosen is
    /// the reading that needs the least invention: each of the four rows is a distinct kind of
    /// moment rather than a slot in a feed, and any of them may be absent — a tree nobody
    /// photographed has no first photo, a tree nobody checked in on has no check-in row.
    private static func moments(
        photos: Series<Photo>,
        visits: Series<Visit>,
        observations: Series<TreeObservation>,
        caretakerCount: Int?,
        removedAt: Date?,
        calendar: Calendar,
        locale: Locale
    ) -> [Moment] {
        var moments: [Moment] = []

        if let first = photos.items.min(by: { $0.capturedAt < $1.capturedAt }) {
            moments.append(
                Moment(
                    id: first.id,
                    kind: .firstPhoto,
                    label: MemorialCopy.firstPhotoLabel,
                    detail: MemorialCopy.firstPhotoDetail(caretakers: caretakerCount, locale: locale),
                    timestamp: MemorialCopy.monthYear.string(from: first.capturedAt)
                )
            )
        }

        if let visit = visits.items.max(by: { $0.capturedAt < $1.capturedAt }) {
            moments.append(
                Moment(
                    id: visit.id,
                    kind: .visit,
                    label: MemorialCopy.visitLabel,
                    detail: MemorialCopy.visitDetail(note: visit.note),
                    timestamp: MemorialCopy.monthYear.string(from: visit.capturedAt)
                )
            )
        }

        if let observation = observations.items.max(by: { $0.capturedAt < $1.capturedAt }),
           let vitality = observation.vitality {
            moments.append(
                Moment(
                    id: observation.id,
                    kind: .checkIn(vitality),
                    label: MemorialCopy.checkInLabel,
                    detail: MemorialCopy.checkInDetail(
                        vitality: vitality,
                        // "a steward confirmed the decline" is a claim about who made the row, and
                        // `verification_state` is the column that carries it (D12, BUILD-PLAN §5).
                        // An unverified check-in gets the clause dropped rather than reworded.
                        isOrgVerified: observation.verificationState == .orgVerified
                    ),
                    timestamp: MemorialCopy.monthYear.string(from: observation.capturedAt)
                )
            )
        }

        if let removedAt {
            moments.append(
                Moment(
                    // A synthetic row with no row behind it, so its id is derived from the fact it
                    // states rather than borrowed from a record that does not exist.
                    id: MemorialPresentation.cityRecordMomentID,
                    kind: .cityRecord,
                    label: MemorialCopy.cityRecordLabel,
                    // The mock's ` · storm damage` is not here: no column carries a removal reason,
                    // and a plausible one is exactly the invented botany BUILD-PLAN §15 forbids in
                    // its own domain.
                    detail: MemorialCopy.cityRecordDetail,
                    timestamp: MemorialCopy.monthYear.string(from: removedAt)
                )
            )
        }

        return moments.sorted { left, right in
            Self.order(of: left.kind) < Self.order(of: right.kind)
        }
    }

    /// A fixed id for the synthetic city-record row, so `ForEach` is stable across reloads.
    static let cityRecordMomentID = UUID(uuidString: "19000000-0000-4000-8000-000000000001")!

    /// The drawn order: the beginning, the visit, the check-in, the end.
    private static func order(of kind: Moment.Kind) -> Int {
        switch kind {
        case .firstPhoto: return 0
        case .visit: return 1
        case .checkIn: return 2
        case .cityRecord: return 3
        }
    }

    // MARK: - A8, for `six people came to know it`

    /// A8: "distinct users with 2 or more care_events or observations on the tree in 24 months;
    /// shown only when 3 or more".
    ///
    /// The same rule `TreeProfilePresentation.caretakers` applies for screen 03's regulars row, and
    /// deliberately not the same code: one screen's presentation type reaching into another's is the
    /// sibling dependency ARCHITECTURE §3 keeps out of `Features/`. That leaves the rule stated
    /// twice, which is worth an entry in ERRATA rather than a shortcut here.
    ///
    /// **The 24-month window is not applied on a memorial.** A8 wrote it for a living tree, where
    /// "who knows this tree" is a question about now; a tree removed in 2026 would score zero
    /// caretakers within two months of its own memorial being read, and the sentence
    /// (`six people came to know it`, past tense) is about its whole life. So the window is the
    /// tree's life, and the floor of three is kept exactly.
    private static func caretakerCount(profile: TreeProfile, now: Date, calendar: Calendar) -> Int? {
        // A page undercounts, silently and by an amount nothing on screen could hint at.
        guard profile.careEvents.isComplete, profile.observations.isComplete else { return nil }

        var contributionsPerUser: [UUID: Int] = [:]
        for event in profile.careEvents.items where event.deletedAt == nil {
            guard let userID = event.userID else { continue }
            contributionsPerUser[userID, default: 0] += 1
        }
        for observation in profile.observations.items where observation.deletedAt == nil {
            guard let userID = observation.userID else { continue }
            contributionsPerUser[userID, default: 0] += 1
        }

        let qualifying = contributionsPerUser.filter { $0.value >= caretakerMinimumContributions }
        guard qualifying.count >= caretakerThreshold else { return nil }
        return qualifying.count
    }

    /// A8's "2 or more care_events or observations".
    static let caretakerMinimumContributions = 2
    /// A8's cold-start floor. Below it the clause does not render at all (DECISIONS constraint 1).
    static let caretakerThreshold = 3

    // MARK: - §6 The stat grid

    private static func stats(tree: Tree, plantedYear: Int?, removalYear: Int?) -> [Stat] {
        var stats: [Stat] = []

        // `On record · 23 years` is `removalYear − plantedYear`. Both ends or neither: a span with
        // one end known is not a span, and reaching for "now" as the other end would say a removed
        // tree is still accruing years.
        if let plantedYear, let removalYear, removalYear >= plantedYear {
            stats.append(
                Stat(
                    id: "onRecord",
                    label: MemorialCopy.onRecordLabel,
                    value: MemorialCopy.years(removalYear - plantedYear)
                )
            )
        }

        // `#088-21` — the publishing inventory's own id, the citable city record (BUILD-PLAN §7).
        // The same rule `TreeProfilePresentation.cityRecordText` states for 03 and 14, and the same
        // one string, so a memorial cannot start naming a city the other two screens have stopped
        // naming (`CityRecordCopy.recordNumber`, RULINGS R28).
        if tree.source == .cityImport, let ref = tree.externalRef, !ref.isEmpty {
            stats.append(
                Stat(
                    id: "cityRecord",
                    label: MemorialCopy.cityRecordStatLabel,
                    value: CityRecordCopy.recordNumber(ref)
                )
            )
        }

        return stats
    }
}

// MARK: - Copy

/// Screen 19's strings, verbatim from SCREENS.md including its typographic characters.
///
/// This is the screen where an invented sentence would be most out of place, so every string below
/// is either the mock's own or a clause of the mock's own left out. Nothing is reworded to cover a
/// gap; a fact the record does not hold takes its clause with it.
enum MemorialCopy {

    // MARK: §1 Hero

    /// `86 photos · 2019–2026`.
    ///
    /// Three claims, all about the *whole* series, so a page renders nothing (ERRATA E38): how many
    /// photographs there are, the year the first was taken, and the year the last was. The range is
    /// an en dash with no spaces (ARCHITECTURE §5.7).
    ///
    /// The closing year is the removal year when the record knows it — the mock's `2026` is the year
    /// the tree ended, not the year of its last photograph, and on a memorial those can differ by
    /// months. Without a removal date it falls back to the last photograph's year, which is a true
    /// statement about the photographs even when it is not the tree's last year.
    static func heroMetaPill(photos: Series<Photo>, removalYear: Int?, calendar: Calendar) -> String? {
        guard let count = photos.totalCount, count > 0,
              let earliest = photos.items.map(\.capturedAt).min(),
              let latest = photos.items.map(\.capturedAt).max()
        else { return nil }

        let noun = count == 1 ? "photo" : "photos"
        let from = calendar.component(.year, from: earliest)
        let to = removalYear ?? calendar.component(.year, from: latest)
        guard to > from else { return "\(count) \(noun) · \(from)" }
        return "\(count) \(noun) · \(from)–\(to)"
    }

    /// `Last photo · Apr 2026`.
    ///
    /// Not 03's `Best photo`. A3's "best photo" is a choice about which photograph represents a
    /// living tree; the last one is a fact about when the record stopped, which is what this screen
    /// is about.
    static func lastPhotoEyebrow(_ monthYear: String) -> String { "Last photo · \(monthYear)" }

    // MARK: §2 The banner

    /// `Removed by the city, May 2026.` — or without the date, which is every record today.
    ///
    /// The date is dropped rather than guessed. `trees.updated_at` is the nearest column and it does
    /// not mean this: it moves on any write, so reading it as a removal month would put a date on
    /// screen that a later species correction could change. See `MemorialFacts`.
    static func bannerLeadIn(removedAt: Date?) -> String {
        guard let removedAt else { return "Removed by the city." }
        return "Removed by the city, \(monthYear.string(from: removedAt))."
    }

    /// The rest of §2, verbatim — leading space and un-spaced em dash included (ARCHITECTURE §5.7).
    static let bannerBody = " This profile is now read-only. Every photo, visit, and check-in stays—a record of the tree that was here."

    // MARK: §3 Identity

    /// The H1. The same precedence 03 and 14 use: a given name (D15), then the species common name,
    /// then the street, then the bare word.
    static func title(profile: TreeProfile) -> String {
        if let name = profile.activeName, name.isDisplayable { return name.name }
        if let common = profile.species?.commonName, !common.isEmpty { return common }
        if let address = profile.tree.address, !address.isEmpty { return address }
        return "Tree"
    }

    /// `Red Flowering Gum · Corymbia ficifolia · 2003–2026`.
    ///
    /// Common name, scientific name, and the years the record covers — each present only when it is
    /// both known and not already the H1. The years need both ends (see `MemorialFacts`).
    static func subtitle(
        profile: TreeProfile,
        title: String,
        plantedYear: Int?,
        removalYear: Int?
    ) -> String {
        var parts: [String] = []
        if let species = profile.species {
            if !species.commonName.isEmpty, species.commonName != title {
                parts.append(species.commonName)
            }
            if species.scientificName != title {
                parts.append(species.scientificName)
            }
        }
        if let plantedYear, let removalYear, removalYear >= plantedYear {
            parts.append("\(plantedYear)–\(removalYear)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: §4 The timeline

    static let firstPhotoLabel = "First photo"
    static let visitLabel = "Visit"
    static let checkInLabel = "Check-in"
    static let cityRecordLabel = "City record"

    /// ` · the record begins · six people came to know it`.
    ///
    /// The headcount is A8's and is floored at three; below it the clause is dropped and the row
    /// still draws, exactly as `AlmanacCopy.bloomSubtitle` drops its own. Past tense, because the
    /// tree is.
    static func firstPhotoDetail(caretakers: Int?, locale: Locale) -> String {
        let opening = " · the record begins"
        guard let caretakers else { return opening }
        return "\(opening) · \(spelledOut(caretakers, locale: locale)) people came to know it"
    }

    /// ` · “The reddest bloom on the block, every January”` — the visit's own note, in the mock's
    /// curly quotes. A visit with no note keeps the row and says nothing more about it.
    static func visitDetail(note: String?) -> String {
        guard let note, !note.isEmpty else { return "" }
        return " · “\(note)”"
    }

    /// ` · vitality 2 · a steward confirmed the decline`.
    ///
    /// The second clause is a provenance claim and renders only when `verification_state` supports
    /// it. "the decline" is kept from the mock rather than generalised: a check-in that an org
    /// confirmed on a tree that was later removed is a decline, and rewriting it into something
    /// vaguer would be writing new copy for this screen.
    static func checkInDetail(vitality: Vitality, isOrgVerified: Bool) -> String {
        let opening = " · vitality \(vitality.rawValue)"
        guard isOrgVerified else { return opening }
        return "\(opening) · a steward confirmed the decline"
    }

    /// ` · marked removed`. The mock's trailing ` · storm damage` has no column behind it anywhere
    /// in BUILD-PLAN §4 and is not written.
    static let cityRecordDetail = " · marked removed"

    // MARK: §5 Lineage

    static let lineageLeadIn = "A new tree is coming."
    /// Verbatim, leading space and un-spaced em dash included.
    static let lineageBody = " When the city replants this site, the new profile will link back here—the site keeps its lineage."

    // MARK: §6 Stats

    static let onRecordLabel = "On record"
    static let cityRecordStatLabel = "City record"

    /// `23 years`.
    static func years(_ count: Int) -> String {
        count == 1 ? "1 year" : "\(count) years"
    }

    // MARK: - The states SCREENS.md does not draw

    /// A tree this screen was opened for that is not removed. **NOT SPECIFIED** (ERRATA).
    ///
    /// It states the fact and stops. Offering a way through to screen 03 would be this feature
    /// constructing another's view, and doing it silently would make a memorial link that opens a
    /// living profile — which is the one confusion this screen cannot afford.
    static let notAMemorial = "This tree is still standing."

    /// The same two failure sentences screen 03 uses, kept identical on purpose: a reader who has
    /// seen one should not have to work out whether the other means something different.
    static let noRecord = "No record for this tree."
    static let couldNotLoad = "This profile could not be loaded."
    static let tryAgain = "Try again"

    // MARK: - Numbers and dates

    /// `three`, `six`. The mock spells its people counts out, as SCREENS.md 12 and 13 do.
    static func spelledOut(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `Mar 2019`.
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()
}

// MARK: - Screen metrics

/// The margins SCREENS.md 19 gives this screen that `CypressSpacing` does not already name.
enum MemorialMetrics {
    /// §2 and §5: `margin:14px 16px 0`.
    static let bannerTop: CGFloat = 14
    /// §3, §4, §6: `padding:12px 16px 0` / `14px 16px 0`.
    static let blockGap: CGFloat = 12
    static let identityTop: CGFloat = 14
    /// §3: `margin-top:2px` on the latin line.
    static let latinTop: CGFloat = 2
}
