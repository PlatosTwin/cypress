//
//  FavoriteOutboxWriter.swift
//  Cypress — Data/Outbox
//
//  Screen 03's `Favorite` cell, made real (ERRATA E89).
//
//  Same shape as `ReminderOutboxWriter` and `VisitOutboxWriter`, and for the same sentence in
//  ARCHITECTURE §4: "every mutation is idempotent on a client-generated `clientUUID`, written to the
//  outbox *first*, and only then attempted against the API." The favourite is durable before
//  anything is attempted, and the drain that follows is best effort — a drain that fails has not
//  lost the favourite, so it is not a failed save.
//
//  **Why this lives in `Data/Outbox` and not in a feature folder.** Every other writer sits beside
//  the screen that assembles its draft: the check-in has a form, the reminder has a hazard category,
//  the measurement has a keypad. The favourite has none of that — screen 03 hands out a tree id and
//  nothing else, and the composition root resolves the owner, because identity is not a view's
//  question to answer. Putting it under `Features/TreeProfile` would make that folder own a write it
//  never performs.
//
//  Foundation only.
//

import Foundation

/// What a favourite save produced, for a caller that wants to know what was queued.
public struct FavoriteSaveReceipt: Sendable {
    public let toggle: FavoriteToggle
    /// The outbox row as stored.
    public let item: OutboxItem
}

public enum FavoriteOutboxWriter {

    /// Writes the toggle to the outbox and then, separately, tries to drain it.
    ///
    /// - Parameter isFavorite: the resulting *state*, not a verb. A favourite syncs as a toggle event
    ///   with a tombstone (BUILD-PLAN §4 and §6), so replaying "favourited" twice leaves one
    ///   favourite rather than flipping it back off.
    /// - Parameter attribution: who is contributing right now. `FavoriteOwner` turns it into the one
    ///   owner the row keeps: the signed-in user if there is one, this device otherwise (D9).
    /// - Parameter clientUUID: the idempotency key, minted by the caller so that two taps of one
    ///   control save one favourite. It moves with each flip, which is what makes the store's replay
    ///   guard (`WHERE client_uuid <> excluded.client_uuid`) tell a replay from a real un-favourite.
    /// - Throws: only if the *enqueue* fails. A drain failure is swallowed: the row is durable and
    ///   the outbox owns retrying it.
    @discardableResult
    public static func save(
        treeID: UUID,
        isFavorite: Bool,
        attribution: Attribution,
        outbox: OutboxQueue,
        clientUUID: UUID = UUID(),
        now: Date = Date()
    ) async throws -> FavoriteSaveReceipt {
        let toggle = FavoriteToggle(
            owner: FavoriteOwner(attribution),
            treeID: treeID,
            clientUUID: clientUUID,
            isFavorite: isFavorite,
            occurredAt: now
        )

        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let item = try await outbox.enqueue(.favoriteToggle(toggle))

        // ── 2. Best effort, after. ────────────────────────────────────────────────────────────
        _ = try? await outbox.drain()

        return FavoriteSaveReceipt(toggle: toggle, item: item)
    }
}
