//
//  TreeDataDispute.swift
//  Cypress — Core/Models
//
//  A contributor's disagreement with a record's own data (`RULINGS R79`, `AppSchema` v22).
//
//  ── Why this is not a `ReviewFlag` ─────────────────────────────────────────────────────────────
//
//  `ReviewFlag` is boolean-shaped: a kind, a tree, a raiser, and a three-state status a lead moves.
//  R79's city surface is not that shape and the ruling says so in as many words — "the dispute row
//  must carry: which issue kinds are checked, per-field suggested values, and free-text notes —
//  richer than the existing boolean-shaped species/never-existed flags". One dispute may check
//  several issues at once, and it carries the reporter's own correction beside each.
//
//  It is also not resolvable on the device, which is the second reason it is not a flag. A city row
//  lives in the ATTACHed read-only seed; nothing here may write it, and R79 explicitly defers
//  whether a dispute ever reaches the city's own dataset. So there is no `confirmed` and no
//  `dismissed` — the only transition this record has is the one its **author** can make, which is
//  to take it back (`withdrawnAt`).
//
//  ── The two states, and the one missing on purpose ────────────────────────────────────────────
//
//  Open (`withdrawnAt == nil`) and withdrawn. There is deliberately no third: adjudication is a web
//  deliverable (ARCHITECTURE §8), and a device that materialized a verdict would be moving city data
//  on a say-so nobody adjudicated.
//
//  Foundation only, like everything else in `Core`.
//

import Foundation

/// One contributor's dispute of one tree record's data (`tree_data_disputes`, `AppSchema` v22).
public struct TreeDataDispute: CoreEntity {

    // MARK: - What is being disputed

    /// R79's three checkboxes, verbatim. More than one may apply to a single dispute, which is why
    /// they are a `Set` here and a child table in SQL rather than a column.
    ///
    /// `tree_dispute_issues.kind`'s stored vocabulary; the `CHECK` there is these `rawValue`s.
    public enum IssueKind: String, Codable, Sendable, Hashable, CaseIterable {
        /// "Pin in wrong location." Answered with the reporter's own fix — see `SuggestedLocation`
        /// for why a fix has to state its accuracy to count.
        case wrongLocation = "wrong_location"
        /// "Wrong species."
        case wrongSpecies = "wrong_species"
        /// "Wrong other metadata" — the owner's two examples and nothing else: a clearly wrong
        /// planted year, and a recorded tree whose plot is actually empty.
        case wrongMetadata = "wrong_metadata"
    }

    /// The fields a dispute may suggest a value for (`tree_dispute_suggestions.field`).
    ///
    /// **Per field, not per kind**, which is the shape the round's contract fixes: a suggestion is a
    /// statement about a column, and the mapping from a checked issue to the columns it may speak
    /// about is `issue` below rather than a second table.
    ///
    /// The vocabulary is closed and is the stored `CHECK`. Widening it later is **not free**: SQLite
    /// cannot widen a `CHECK` in place, so a seventh field is a rebuild of `tree_dispute_suggestions`
    /// — cheap, because that table is a *child* and dropping a child cascades nothing, but a
    /// migration all the same. `AppSchema` v22's comment says the same thing beside the table.
    public enum SuggestedField: String, Codable, Sendable, Hashable, CaseIterable {
        case latitude = "lat"
        case longitude = "lon"
        /// The fix's own stated accuracy, in meters, beside the coordinates it justifies.
        ///
        /// **It travels because a suggested position without it cannot be weighed.** F17 is the
        /// receipt: `MapLocationProvider.Availability.located` carried `accuracyM` from the start and
        /// nothing on the path to screen 12 read it, so a fix good to ±5 m and one good to ±3,000 m
        /// were treated identically and the Journal named a neighborhood two miles from the reader.
        /// A coordinate offered as a *correction to the city's own record* is the same trap with a
        /// worse blast radius.
        case locationAccuracyM = "location_accuracy_m"
        case speciesID = "species_id"
        case plantedYear = "planted_year"
        /// A status the reporter believes the record should carry.
        ///
        /// **Constrained by the reader, not by this table.** The column admits any string; part 1
        /// only ever writes `vacant_site` — "a recorded tree whose plot is actually empty", the
        /// second of the owner's two metadata examples — and `DataDisputeLimits.statusSuggestion`
        /// is the code that says so. Modelling the empty plot as a status rather than as a fresh
        /// boolean is the owner's own instruction, and it is what makes the profile's existing
        /// vacant-site handling mean something when a dispute is one day adjudicated.
        case status = "status"

        /// Which checkbox a suggestion in this field belongs under.
        ///
        /// Exhaustive with no `default`, so a seventh field cannot be added without somebody saying
        /// which issue it speaks for — the same guard `OutboxItem.Kind.accountDeletionTreatment`
        /// puts on its own enum, and for the same reason: a missing answer here would be a
        /// suggestion attached to a dispute that does not make it.
        public var issue: IssueKind {
            switch self {
            case .latitude, .longitude, .locationAccuracyM: return .wrongLocation
            case .speciesID: return .wrongSpecies
            case .plantedYear, .status: return .wrongMetadata
            }
        }
    }

    // MARK: - A suggested position

    /// A coordinate offered as the correct one, and how well the phone knew where it was.
    ///
    /// The two travel together because neither is usable alone — see `SuggestedField
    /// .locationAccuracyM`. `accuracyM` is optional for the reason `AlmanacLimits
    /// .fixCanResolveAnArea(accuracyM:withinM:)` gives for permitting `nil`: every live path
    /// supplies a number, and the callers that do not are previews and tests driving a bare
    /// coordinate. Refusing `nil` would blank those rather than protect anybody.
    public struct SuggestedLocation: Hashable, Sendable, Codable {
        public let coordinate: Coordinate
        /// Meters, as the fix stated them. `nil` when the caller had no fix to quote.
        public let accuracyM: Double?

        public init(coordinate: Coordinate, accuracyM: Double?) {
            self.coordinate = coordinate
            self.accuracyM = accuracyM
        }
    }

    // MARK: - The suggested values

    /// What the reporter says the record should say instead — typed, rather than the six stored
    /// strings.
    ///
    /// **One type for the model and for the API parameter, flattened in one place.** The table
    /// stores `(field, value)` text pairs because the vocabulary has to be a `CHECK` and the values
    /// are of four different types; every other layer wants a species id to be a `UUID` and a year
    /// to be an `Int`. Two types either side of that seam is how the two vocabularies start to
    /// differ, so `stored` and `init(stored:)` below are the only place the conversion happens.
    ///
    /// Every field is optional: a dispute may check "wrong species" and offer no replacement, which
    /// is a real and useful report ("this is not a London Plane, I do not know what it is"). What is
    /// *not* allowed is a suggestion for an issue the dispute does not check — see
    /// `DataDisputeLimits.refusal(issues:suggestions:)`.
    public struct Suggestions: Hashable, Sendable, Codable {
        public var location: SuggestedLocation?
        public var speciesID: UUID?
        public var plantedYear: Int?
        public var status: TreeStatus?

        public init(
            location: SuggestedLocation? = nil,
            speciesID: UUID? = nil,
            plantedYear: Int? = nil,
            status: TreeStatus? = nil
        ) {
            self.location = location
            self.speciesID = speciesID
            self.plantedYear = plantedYear
            self.status = status
        }

        public var isEmpty: Bool {
            location == nil && speciesID == nil && plantedYear == nil && status == nil
        }

        /// The issues these suggestions speak about — `SuggestedField.issue` for whatever is set.
        public var issuesSpokenFor: Set<IssueKind> {
            Set(stored.keys.map(\.issue))
        }

        /// The rows as the table holds them.
        ///
        /// **`Double.description` and `String(Int)` rather than a formatter**, deliberately: Swift's
        /// `Double` description has been the shortest representation that parses back to the same
        /// bit pattern since Swift 4.2, and a `NumberFormatter` is locale-dependent — a decimal comma
        /// in this column would be a suggested coordinate nothing could read back. `TreeStatusTests`
        /// aside, the round trip is asserted directly in `DataDisputeTests`.
        public var stored: [SuggestedField: String] {
            var rows: [SuggestedField: String] = [:]
            if let location {
                rows[.latitude] = location.coordinate.latitude.description
                rows[.longitude] = location.coordinate.longitude.description
                // Absent rather than empty when the caller had no number: the row's presence is
                // itself the statement that an accuracy was known.
                if let accuracyM = location.accuracyM {
                    rows[.locationAccuracyM] = accuracyM.description
                }
            }
            if let speciesID { rows[.speciesID] = speciesID.uuidString }
            if let plantedYear { rows[.plantedYear] = String(plantedYear) }
            if let status { rows[.status] = status.rawValue }
            return rows
        }

        /// Rebuilds from the stored rows.
        ///
        /// A latitude without a longitude yields no location at all, rather than half of one: the
        /// two are written in the same transaction and a half-pair is a hand-edited database, not a
        /// state this app produces. Same for a value that will not parse — the field is simply not
        /// there, which is the safe direction on a payload a screen draws controls from.
        public init(stored rows: [SuggestedField: String]) {
            var suggestions = Suggestions()
            if let latitude = rows[.latitude].flatMap(Double.init),
               let longitude = rows[.longitude].flatMap(Double.init) {
                suggestions.location = SuggestedLocation(
                    coordinate: Coordinate(latitude: latitude, longitude: longitude),
                    accuracyM: rows[.locationAccuracyM].flatMap(Double.init)
                )
            }
            suggestions.speciesID = rows[.speciesID].flatMap(UUID.init(uuidString:))
            suggestions.plantedYear = rows[.plantedYear].flatMap(Int.init)
            suggestions.status = rows[.status].flatMap(TreeStatus.init(rawValue:))
            self = suggestions
        }
    }

    // MARK: - The record

    public let id: UUID
    /// The idempotency key the queue and the service dedupe on, minted before the write.
    public let clientUUID: UUID
    /// The record disputed. No foreign key: a city tree lives in the ATTACHed read-only seed and
    /// SQLite cannot declare a `REFERENCES` across an attachment (`AppSchema`'s header).
    public let treeID: UUID
    /// Which half of the inventory that record is in. Stored so a reader can tell a city dispute
    /// from a community one without a second lookup into two different tables.
    public let treeSource: TreeSource
    /// The account that raised it, or `nil` for a device that has not signed in (D9).
    ///
    /// `review_flags.raised_by`'s shape and its meaning: this database belongs to one installation,
    /// so a `NULL` here is *this* device's anonymous contributor and no one else's.
    public let raisedBy: UUID?
    public let issues: Set<IssueKind>
    public let suggestions: Suggestions
    /// R79's "notes / additional information" field.
    public let notes: String?
    public let createdAt: Date
    public var updatedAt: Date
    /// When the author took it back, or `nil` while it stands.
    public var withdrawnAt: Date?

    public var isOpen: Bool { withdrawnAt == nil }

    public init(
        id: UUID = UUID(),
        clientUUID: UUID = UUID(),
        treeID: UUID,
        treeSource: TreeSource,
        raisedBy: UUID?,
        issues: Set<IssueKind>,
        suggestions: Suggestions = Suggestions(),
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        withdrawnAt: Date? = nil
    ) {
        self.id = id
        self.clientUUID = clientUUID
        self.treeID = treeID
        self.treeSource = treeSource
        self.raisedBy = raisedBy
        self.issues = issues
        self.suggestions = suggestions
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.withdrawnAt = withdrawnAt
    }
}
