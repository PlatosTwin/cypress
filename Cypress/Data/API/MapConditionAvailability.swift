//
//  MapConditionAvailability.swift
//  Cypress — Data/API
//
//  **Whether the map's two condition chips could match anything at all** (task #136, RULINGS R31).
//
//  `In bloom` and `Needs care` are the mock's own chips and they stay on the row — but in the
//  shipped seed every `species.seasonal` is `{}` and the only statuses are `alive` and
//  `vacant_site` (R23.1's findings), so both chips' only possible outcome today is E126's apology
//  card. R31: a chip in that position renders disabled with the reason on its own surface, and it
//  re-enables itself the moment matching data exists — no flag, no release; the data's arrival is
//  the switch. This type is the answer to "does matching data exist", asked of the store.
//

import Foundation

/// Which of screen 01's two condition chips could currently match at least one tree.
///
/// A fact about the *data*, not the viewport: `false` means "no tree anywhere in what this app can
/// see could satisfy the chip", which is the only state in which R31 disables it. A chip whose
/// matches merely happen to be off-screen is an ordinary chip whose empty state says to pan
/// (E126); a chip with no possible match anywhere is a control that promises and cannot deliver.
public struct MapConditionAvailability: Hashable, Sendable {

    /// Whether any tree in scope carries `status == .declining` — from the seed, from a local
    /// status override (a community observation standing a declining tree, E124-B), or from a
    /// community-added row.
    public var needsCare: Bool

    /// Whether any species carries a bloom calendar naming the current month **and** a tree of
    /// that species is in scope. Both halves matter: a calendar with no tree is botany with no map,
    /// and D5's schema being ready is not data having arrived.
    public var inBloom: Bool

    /// Whether any species carries a bloom calendar **at all**, whatever this month is.
    ///
    /// R31 drafted the disabled chip's sentence against a seed where "every `seasonal` is `{}`",
    /// and the seed on the machine refutes that premise: 11 species carry `bloom_months` and
    /// months 10–12 name no blooming tree anywhere. So `inBloom == false` is two different facts —
    /// the calendars have not been written (the app's debt, R31's sentence), or they have and
    /// nothing blooms *this month* (a season, not a debt) — and the chip's reason must not claim
    /// the first while the second is the truth. This flag is what tells them apart.
    public var hasAnyBloomCalendar: Bool

    public init(needsCare: Bool, inBloom: Bool, hasAnyBloomCalendar: Bool) {
        self.needsCare = needsCare
        self.inBloom = inBloom
        self.hasAnyBloomCalendar = hasAnyBloomCalendar
    }

    /// Nothing can match. What an implementation with no store truthfully has, and the state the
    /// chips render disabled from until a read says otherwise.
    public static let none = MapConditionAvailability(
        needsCare: false, inBloom: false, hasAnyBloomCalendar: false
    )
}

/// Defaulted for every conformance that has no inventory to ask — the same shape as
/// `mapMembership`'s default in `MapMembership.swift`, and declared as a protocol requirement in
/// `CypressAPI` rather than only here, for E125's reason: an extension member dispatches
/// statically, and every screen holds `any CypressAPI`.
extension CypressAPI {
    public func mapConditionAvailability(month: Int) async throws -> MapConditionAvailability {
        .none
    }
}
