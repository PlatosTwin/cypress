//
//  MeasurementWithdrawalAccess.swift
//  Cypress — Data/API
//
//  The one thing a person could not do to a number they contributed: **take it back** (report F27).
//
//  ── What F27 asked for, and the half of it that needs nothing built ────────────────────────────
//
//  The report reads "measurements can be neither edited nor deleted". *Edited* is not a gap in the
//  measure surface, it is the app's design everywhere: `CypressAPI`'s write surface is
//  append-or-withdraw end to end, a species correction supersedes rather than overwrites and keeps
//  the superseded row pointing forward, and every capture screen carries the whole burden in its
//  pre-submit confirmation precisely because nothing can be amended afterwards. Changing a reading
//  is adding a reading, which screen 16 already does and which RULINGS R15's `Add a reading` link
//  made one tap on the tree where it used to be two.
//
//  *Deleted* was real. `measurements.deleted_at` has existed since `AppSchema` v1 and is honored by
//  `TreeMeasurement.isChartable`, by `ContributionStore.measurements`, by the journal, the grove and
//  the profile's stat cards — and nothing anywhere set it.
//
//  ── Why the verb is `withdraw` and not `delete` ────────────────────────────────────────────────
//
//  Because that is what it does, and the two words promise different things. `deletePhoto` destroys
//  bytes: the JPEG leaves the container, and a tombstone that could still find the picture would be
//  a lie (ERRATA E136's argument). A reading is a number, its unit, its method and when it was
//  taken; there is nothing to destroy and nothing that stripping the row would achieve — D7's CHECKs
//  make a stored measurement with the number taken out unstorable in the first place. What somebody
//  asks for when they take a reading back is that it stop counting, and `deleted_at` is exactly that
//  in every reader.
//

import Foundation

// MARK: - Default implementation
//
// **Declared on the protocol as well**, and `CypressAPI` says at length why: a default that is
// *only* an extension member dispatches statically, so an implementation's override is unreachable
// through `any CypressAPI` — which is what every screen holds (ERRATA E125).

public extension CypressAPI {

    /// Withdraws one reading this person contributed.
    ///
    /// `notFound` for `deletePhoto`'s reason and in the same safe direction: an implementation with
    /// no contributions has no reading to withdraw, and a withdrawal default that quietly
    /// *succeeded* would be the worst possible shape for this method — a screen would tell somebody
    /// their reading was gone while it went on being charted.
    func withdrawMeasurement(id: UUID) async throws -> WithdrawnMeasurement {
        throw APIError.notFound
    }
}

// MARK: - What a withdrawal did

/// The result of taking one reading back, in the terms the caller has to be able to check.
///
/// Returned rather than logged for `PhotoDeletion`'s reason: a claim nothing checks is a claim that
/// quietly stops being true, and "the call did not throw" is not evidence that a row moved.
///
/// **Distinct from `MeasurementWithdrawal`, which is the queued act.** This is the report — what
/// changed on *this device* — and the split is the same one `PhotoDeletion` and `PhotoWithdrawal`
/// make: none of what is below describes anything a server holds, so none of it is sent.
public struct WithdrawnMeasurement: Sendable, Equatable {
    /// The reading that went.
    public let measurementID: UUID
    /// The tree it was on, so a caller can reload the surface it was drawn on.
    public let treeID: UUID
    /// Which of D7's two series it was in.
    public let kind: MeasurementKind

    /// Whether the tree now holds **no live reading of that kind at all**.
    ///
    /// The fact that changes a surface rather than a row: screen 03's stat card for this
    /// measurement goes back to being an empty slot (R15), screen 11's chart card for it disappears
    /// entirely (`GrowthHistoryPresentation.chart(for:)` draws no card for a kind with no point),
    /// and the tree becomes one that the profile once again offers a door into screen 16 for.
    ///
    /// Read after the tombstone commits and in the same transaction, so it describes the record the
    /// withdrawal left rather than the one it found.
    public let leftTheKindWithNoReading: Bool

    public init(
        measurementID: UUID,
        treeID: UUID,
        kind: MeasurementKind,
        leftTheKindWithNoReading: Bool
    ) {
        self.measurementID = measurementID
        self.treeID = treeID
        self.kind = kind
        self.leftTheKindWithNoReading = leftTheKindWithNoReading
    }
}
