import Foundation

/// What one person has done to one tree, by kind.
///
/// ── Why this exists ───────────────────────────────────────────────────────────────────────
/// My Grove's `Trees` list and the Journal are the two lists in this app keyed on the reader rather
/// than on a tree, and the project owner could not tell them apart. They are not the same list:
/// **a tree you visited twenty times is one row here and twenty rows there.** That is the whole
/// distinction, and until this type existed nothing on a grove row expressed it — a tree with one
/// visit and a tree with twenty drew the identical sentence.
///
/// So a grove row now says how you know the tree. `4 visits · 1 measurement` is a description of one
/// relationship. It is not a score, and the difference is not a matter of tone:
///
/// ── Why this is not the thing D1 forbids ──────────────────────────────────────────────────
/// D1 kills "streaks, points, ranks, badges, or **public** counts of user actions", and DECISIONS
/// §3.1 adds "recency and identity phrasing only". `DeviceContributions` already argues this ground
/// for screen 15's `Keep your three visits`, on three clauses, and every one of them holds here:
///
/// - **never public** — these rows exist on one phone, describing contributions that in the common
///   case have not been attributed to anybody at all (D9). No `CypressAPI` method returns another
///   person's grove, so there is no query that could put a second figure beside one of these;
/// - **never compared** — nothing sums these across the grove, nothing sorts on them, and nothing
///   picks a maximum. The list's order is `last_visited DESC NULLS LAST`, the store's, and
///   `GroveTreesTests.theTallyDoesNotSortTheList` fails if that ever becomes an ordering by size;
/// - **never a reward** — no badge, no color that changes with the number, no threshold, no
///   celebration. The row is drawn identically at one and at forty.
///
/// And two clauses this type needs that screen 15's does not, because a grove is a list and a list
/// invites a total:
///
/// - **no total anywhere.** There is deliberately no `total` property here and no sum across rows.
///   `DeviceContributions.total` exists because one sentence needs one number; a grove-wide total
///   would be a count of a person's actions with nothing else it could mean.
/// - **kinds, not a single number.** `4 entries` is one figure per tree, which is a figure a person
///   can rank their own trees by and want to raise. `3 visits · 1 measurement` says what kind of
///   relationship it is, which is a thing to have rather than a thing to maximize. It is also the
///   more useful sentence: it tells you that you have never measured the tree you walk past daily.
///
/// If a later round finds itself summing these, or ordering by them, or drawing anything that gets
/// bigger as one grows, that is the moment to re-read D1 rather than this comment.
///
/// ── ERRATA E38 ────────────────────────────────────────────────────────────────────────────
/// **These are totals and may be printed, and that is a property of how they are read, not of the
/// type.** `ContributionStore.groveRecords` answers them with `COUNT(*)` over the whole predicate,
/// which is the engine answering the question rather than a page's size wearing a total's clothes
/// (the same argument `deviceContributions` makes, and the failure E38 records).
///
/// An implementation that cannot prove that hands back **nil**, not zero, and `GroveEntry.record` is
/// optional for exactly that reason: a row with no proven record draws no tally at all. Zero would be
/// a claim — "you have done nothing to this tree" — that an unproven read is not entitled to make,
/// which is E38 pointed at the emptiest possible answer, the same place `JournalPresentation`
/// gates its empty state on the cursor rather than on `rows.isEmpty`.
public struct GroveRecord: Hashable, Sendable {

    /// Ten-second visits (screen 04).
    public let visits: Int
    /// Light check-ins (screen 05). Named for the control, not for the `observations` table.
    public let checkIns: Int
    /// Numbers entered through the measure sheet (screen 16, D7).
    public let measurements: Int
    /// Quick care logs (screen 09).
    public let careEvents: Int

    public init(visits: Int = 0, checkIns: Int = 0, measurements: Int = 0, careEvents: Int = 0) {
        self.visits = visits
        self.checkIns = checkIns
        self.measurements = measurements
        self.careEvents = careEvents
    }

    /// A tree in the grove with no contribution against it — which is a real state: a favorite
    /// nobody has visited (`ContributionStore.groveTreeIDs`'s second arm).
    public static let none = GroveRecord()

    /// Whether every kind is zero. Not a total: the one question the drawing asks of the whole
    /// record is whether there is anything to say, and `isEmpty` answers it without producing a
    /// number that could be printed.
    public var isEmpty: Bool {
        visits == 0 && checkIns == 0 && measurements == 0 && careEvents == 0
    }
}
