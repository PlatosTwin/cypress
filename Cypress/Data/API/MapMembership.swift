import Foundation

/// The two ways a reader can be related to a tree, as screen 01's filter row asks about them
/// (#116, RULINGS R23).
///
/// ── Why these are one type and not two methods ─────────────────────────────────────────────
/// Both answer the same shape of question — "which trees are mine, for this sense of mine" — and
/// both are read from `main` under the same ownership clause (device id, or the account this device
/// has been claimed by). One method with a kind keeps that clause in one place, which is where D11
/// wants it: "privacy is the shape of the query", and there is no form of either that can return
/// somebody else's rows.
///
/// ── Why `yours` is not `favourites` ───────────────────────────────────────────────────────
/// A favourite is a *bookmark*: a tree you want to find again, which you may never have stood in
/// front of. A contribution is a *record*: a tree you were at, with something to show for it. The
/// owner asked for both, in that order of importance, and they genuinely disagree — the grove's own
/// query has carried the distinction since screen 08 (`GroveQueries.ownContributions` unions the
/// four contribution tables and does not touch `favorites`).
public enum MapMembership: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// Trees this installation has contributed to: visited, photographed, checked in on, measured,
    /// cared for, or added.
    ///
    /// **Photographs are in here by their visit rather than on their own**, which is the same rule
    /// `DeviceContributions` states: "a photo carries no owner of its own, it hangs off the visit
    /// that took it". Every photograph in the app was taken through the visit flow, so a tree you
    /// photographed is a tree you visited, and unioning `photos` as well would add no tree and one
    /// more table to keep an ownership clause correct in.
    ///
    /// **Community-added trees are in here too**, which the four contribution tables do not cover: a
    /// tree you added is the most emphatically yours there is, and it lives in `community_trees`.
    case yours

    /// Trees hearted on screen 03's quad row and still held (D9, ERRATA E89).
    ///
    /// Device-scoped, and tombstones are excluded — an un-favourited tree is not one anybody would
    /// say they have (`DeviceContributions.favorites` makes the same call for the same reason).
    case favourites

    public var id: String { rawValue }
}

// MARK: - Default

public extension CypressAPI {

    /// An implementation with no contribution store behind it holds no such trees.
    ///
    /// The same shape as `deviceContributions()`'s and `almanac()`'s defaults, and for the same
    /// reason: it is a true statement about such an implementation rather than a placeholder, so a
    /// preview double or a second client does not have to invent a history to compile.
    ///
    /// **Empty is a real answer here, not a missing one**, and screen 01 renders it as such: a
    /// reader who taps `Yours` on a fresh install gets an empty map that says why it is empty and
    /// how to leave (ERRATA E126), not a map quietly showing every tree in the city.
    ///
    /// `LocalAPI` overrides it, because `LocalAPI` has the rows.
    func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> { [] }
}
