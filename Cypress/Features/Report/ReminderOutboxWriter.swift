//
//  ReminderOutboxWriter.swift
//  Cypress — Features/Report
//
//  Screen 06 §5's `Save a private reminder for yourself`, made real (ERRATA E23).
//
//  Same shape as `VisitOutboxWriter`, and for the same sentence in ARCHITECTURE §4: "every mutation
//  is idempotent on a client-generated `clientUUID`, written to the outbox *first*, and only then
//  attempted against the API." The reminder is durable before anything is attempted, and the drain
//  that follows is best effort — a drain that fails has not lost the reminder, so it is not a failed
//  save and is never reported as one.
//
//  Foundation only. The screen's confirmation is drawn from what this returns, not from a spinner.
//

import Foundation

/// What a reminder save produced, for screen 06's confirmation line.
struct ReminderSaveReceipt {
    let reminder: PrivateReminder
    /// The outbox row as stored.
    let item: OutboxItem
}

enum ReminderOutboxWriter {

    /// Writes the reminder to the outbox and then, separately, tries to drain it.
    ///
    /// - Parameter attribution: who is contributing right now. `ReminderOwner` turns it into the one
    ///   owner the reminder keeps: the signed-in user if there is one, this device otherwise (D9).
    ///   The screen does not decide this and cannot see it.
    /// - Throws: only if the *enqueue* fails. A drain failure is swallowed: the row is durable and
    ///   the outbox owns retrying it.
    @discardableResult
    static func save(
        _ draft: PrivateReminderDraft,
        attribution: Attribution,
        outbox: OutboxQueue,
        now: Date = Date()
    ) async throws -> ReminderSaveReceipt {
        let reminder = PrivateReminder(
            // Minted with the draft, not here, so a double tap saves one reminder: the id is the
            // outbox's idempotency key, and a repeat of the same key is deduped rather than stored
            // twice (ARCHITECTURE §4).
            id: draft.reminderID,
            owner: ReminderOwner(attribution),
            treeID: draft.treeID,
            category: draft.category,
            createdAt: now,
            updatedAt: now
        )

        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let item = try await outbox.enqueue(.privateReminder(reminder))

        // ── 2. Best effort, after. ────────────────────────────────────────────────────────────
        _ = try? await outbox.drain()

        return ReminderSaveReceipt(reminder: reminder, item: item)
    }
}
