import Foundation

/// Every table in the writable schema that names a person or an installation, and what each of
/// account deletion's two doors does to a row of it.
///
/// **Why this exists.** `delete(userID:choice:at:connection:)` reaches tables by name, and a
/// hand-kept list of table names fails silently: a table it does not mention simply matches
/// nothing. That happened to `tree_data_disputes`, which `AppSchema` v22 added with a `raised_by`
/// column that neither door could see until PR #165's review measured it. The outbox half of the
/// same problem was closed by `OutboxItem.Kind.accountDeletionTreatment`, an exhaustive `switch`
/// with no `default`. This is the table half, in the same shape.
///
/// **What makes it a guard rather than a list.** `AccountDeletionCoverageTests` migrates a fresh
/// database with `AppSchema`, reads every column name out of `pragma_table_info`, and fails unless:
///
/// 1. every column name in the writable schema is known to either name a person or installation,
///    or not to — so a new spelling (`reported_by`, `owner_id`) cannot be taken for an ordinary
///    column without somebody deciding it is one;
/// 2. the tables and columns that name a person or installation are exactly `allCases` and their
///    `identityColumns`, in both directions — so a new owner-bearing table does not compile its way
///    past this enum, and a case whose table is gone does not linger;
/// 3. under each door, a row owned by the deleting account ends as `fate(under:)` says, and a
///    stranger's row in the same table is byte-for-byte unchanged.
///
/// So adding a table with an owner column is a red test until it has a case here, and adding a case
/// is a compile error until `fate(under:)` answers it. The answer is the question the dispute table
/// was added without.
///
/// **What it cannot see.** An identity held in a *value* rather than in a column of its own. Two
/// exist today: `app_state`'s `currentUserID` row, which `delete` removes by key, and `outbox.payload`,
/// whose `userID` is `OutboxStore.forgetAccount`'s and is guarded by `accountDeletionTreatment`.
/// Neither is a column the schema can be asked about, so neither is here. Nor is a third thing held
/// in a key: `app_state`'s `photo_send_refused:<photos.id>` rows (`OutboxStore.recordRefusedPhoto`),
/// which name a photograph rather than a person. The erasing door removes them with their
/// photographs, and `AccountDeletionTests` asserts it.
extension AccountDeletion {

    /// A table with at least one column that names a person or an installation. The raw value is
    /// the table's name in `AppSchema`.
    public enum OwnedTable: String, CaseIterable, Sendable {
        case device
        case visits
        case observations
        case measurements
        case careEvents = "care_events"
        case photos
        case photoVotes = "photo_votes"
        case favorites
        case privateReminders = "private_reminders"
        case communityNotes = "community_notes"
        case reviewFlags = "review_flags"
        case treeNames = "tree_names"
        case treeStatusOverrides = "tree_status_overrides"
        case treeDataDisputes = "tree_data_disputes"
        case speciesAssertions = "species_assertions"

        public var tableName: String { rawValue }

        /// The column a deletion matches the account against.
        public var accountColumn: String {
            switch self {
            case .device, .visits, .observations, .measurements, .careEvents, .photos, .photoVotes,
                 .favorites, .privateReminders, .communityNotes, .speciesAssertions:
                return "user_id"
            case .reviewFlags, .treeDataDisputes:
                return "raised_by"
            case .treeNames:
                return "given_by"
            case .treeStatusOverrides:
                return "set_by"
            }
        }

        /// Every column of this table that names a person or an installation, the account column
        /// included.
        ///
        /// An installation column is D9's anonymous handle. Neither door clears one wholesale: a row
        /// owned by the device was never the account's (see `delete`), and on the four contribution
        /// tables `device_id` is `NOT NULL` and survives anonymization on purpose (v13's tombstone is
        /// what stops the next account adopting it). `photos.taken_on_device` is the exception the
        /// leaving door does clear, and `anonymizeContributions` says why.
        public var installationColumns: Set<String> {
            switch self {
            case .device:
                return ["device_uuid"]
            case .visits, .observations, .measurements, .careEvents, .photoVotes, .favorites,
                 .privateReminders, .speciesAssertions:
                return ["device_id"]
            case .photos:
                return ["device_id", "taken_on_device"]
            case .communityNotes, .reviewFlags, .treeNames, .treeStatusOverrides, .treeDataDisputes:
                return []
            }
        }

        public var identityColumns: Set<String> { installationColumns.union([accountColumn]) }

        /// What one door does to a row whose `accountColumn` names the deleting account.
        ///
        /// No `default`, on `accountDeletionTreatment`'s argument: a new case has to be answered here
        /// before the app compiles.
        public func fate(under choice: AccountDeletionChoice) -> RowFate {
            let (leaving, erasing): (RowFate, RowFate)
            switch self {
            // The contributions §3.12 describes: the forest keeps them and the name comes off, or
            // the person asked for them gone. `tree_data_disputes` joined this arm in PR #165.
            case .visits, .observations, .measurements, .careEvents, .photos, .photoVotes,
                 .reviewFlags, .treeNames, .treeDataDisputes:
                (leaving, erasing) = (.anonymized, .deleted)

            // R3: rows nobody but their owner can read go under both doors (E23, E89).
            case .favorites, .privateReminders:
                (leaving, erasing) = (.deleted, .deleted)

            // `community_notes.user_id` is NOT NULL, so the leaving door cannot anonymize it and
            // reports the count instead (`Outcome.communityNotesLeftAttributed`, E109).
            case .communityNotes:
                (leaving, erasing) = (
                    .leftAttributed(ruling: "E109: user_id is NOT NULL, so the leaving door reports the row rather than anonymizing it"),
                    .deleted
                )

            // A moderation decision keeps its effect and loses its author under both doors; the
            // device row is the "device link" §3.12 severs, under both doors.
            case .treeStatusOverrides, .device:
                (leaving, erasing) = (.anonymized, .anonymized)

            // Written with the account's id by `LocalAPI.addTree`, `claimSpecies` and
            // `correctSpecies` (`SpeciesAssertionStore.insert`), and named by neither door. Found
            // while this guard was being written, and measured by it: after either door the claim
            // still carries the deleted account's id. It is recorded as what the code does, not as
            // a ruling — the fix is its own change — and the day either door reaches the table,
            // `AccountDeletionCoverageTests` goes red here and this arm has to change with it.
            case .speciesAssertions:
                (leaving, erasing) = (
                    .notReached(defect: "neither door names species_assertions; the claim keeps the account's id"),
                    .notReached(defect: "neither door names species_assertions; the claim keeps the account's id")
                )
            }
            switch choice {
            case .leaveRecords: return leaving
            case .eraseEverything: return erasing
            }
        }
    }

    /// What becomes of one owned row.
    public enum RowFate: Sendable, Equatable {
        /// The row stays and its account column is NULL.
        case anonymized
        /// The row is gone.
        case deleted
        /// The row stays, still naming the account, and a ruling says why.
        case leftAttributed(ruling: String)
        /// The row stays, still naming the account, and nothing says it should. A known defect,
        /// stated so that it is measured rather than silent.
        case notReached(defect: String)

        /// Whether the row still names the account afterwards.
        public var keepsTheName: Bool {
            switch self {
            case .anonymized, .deleted: return false
            case .leftAttributed, .notReached: return true
            }
        }
    }
}
