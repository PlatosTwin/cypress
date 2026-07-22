import Foundation

/// What this installation holds under its device id, and would carry onto an account (D9).
///
/// ── Why this exists ───────────────────────────────────────────────────────────────────────
/// Screen 15's headline is `Keep your three visits`. That sentence contains a number about the
/// person reading it, and there was no honest way to get one: `VisitSaveLedger` keeps a save
/// counter but deliberately refuses to expose it as a string (ARCHITECTURE §5.1 — "if you find
/// yourself writing `visitCount` into a user-visible string, stop"), and it is a UI funnel counter
/// in `UserDefaults` rather than a fact about the record. `journal()` returns a `Page`, and a page's
/// size is not a total (ERRATA E38). So the screen either states a number it cannot prove, or the
/// protocol grows a read (ARCHITECTURE §4: "If a screen needs data, the protocol grows a method").
///
/// ── Why this is not the thing D1 forbids ──────────────────────────────────────────────────
/// D1 kills "streaks, points, ranks, badges, or **public** counts of user actions", and DECISIONS
/// §3.1 adds "recency and identity phrasing only". Every clause of that is about a surface where
/// one person's activity is visible to somebody else, or is scored. This is none of those:
///
/// - it is never public — the numbers describe rows that exist on exactly one phone and have not
///   been attributed to anybody at all;
/// - it is never compared — there is no ordering, no other person's figure to sit beside it, and no
///   query on `CypressAPI` that could produce one;
/// - it is not a reward — it is the inventory of what a person would lose, said once, in the one
///   moment the app asks them for something (D9).
///
/// The one screen that reads it renders a single element of it and nothing else. If a second caller
/// ever appears, that is the moment to re-read D1 rather than this comment.
///
/// ── The six kinds ─────────────────────────────────────────────────────────────────────────
/// These are exactly the record kinds `claimDevice(deviceUUID:userID:)` moves onto the account —
/// the four contribution tables, D4's private reminder (ERRATA E23) and, since `AppSchema` v5, the
/// favourite (ERRATA E89). Photos are deliberately absent: a photo carries no owner of its own, it
/// hangs off the visit that took it, so it survives sign-in because its visit does.
public struct DeviceContributions: Hashable, Sendable {

    /// Ten-second visits (screen 04 → 18).
    public let visits: Int
    /// Light check-ins (screen 05).
    public let checkIns: Int
    /// Numbers entered through the measure sheet (screen 16, D7).
    public let measurements: Int
    /// Quick care logs (screen 09).
    public let careEvents: Int
    /// D4's private hazard reminders (screen 06, ERRATA E23).
    public let privateReminders: Int
    /// Trees hearted on screen 03's quad row and still held by this device (ERRATA E89). Tombstoned
    /// toggles are excluded: an un-favourited tree is not something anybody would say they have.
    public let favorites: Int

    public init(
        visits: Int = 0,
        checkIns: Int = 0,
        measurements: Int = 0,
        careEvents: Int = 0,
        privateReminders: Int = 0,
        favorites: Int = 0
    ) {
        self.visits = visits
        self.checkIns = checkIns
        self.measurements = measurements
        self.careEvents = careEvents
        self.privateReminders = privateReminders
        self.favorites = favorites
    }

    /// A device that has contributed nothing yet — and the honest answer for an implementation
    /// with no contribution store behind it.
    public static let none = DeviceContributions()

    /// Everything the device is holding, across the six kinds.
    public var total: Int {
        visits + checkIns + measurements + careEvents + privateReminders + favorites
    }

    public var isEmpty: Bool { total == 0 }
}

// MARK: - Default

public extension CypressAPI {

    /// An implementation with no contribution store behind it is holding nothing.
    ///
    /// The same shape as `groveSpecies()`'s and `almanac()`'s defaults, and for the same reason: it
    /// is a true statement about such an implementation rather than a placeholder, and a preview
    /// double or a second client does not have to invent a contribution history to compile. The one
    /// surface that reads this drops its number when the count is zero rather than writing `Keep
    /// your 0 visits`, so the default degrades to the numberless sentence rather than to a wrong one.
    ///
    /// `LocalAPI` overrides it, because `LocalAPI` has the rows.
    func deviceContributions() async throws -> DeviceContributions { .none }
}
