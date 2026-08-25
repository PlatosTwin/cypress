//
//  PrivateReminderList.swift
//  Cypress — Features/You
//
//  Where a private reminder can be read again (ERRATA E131, on E23's terms).
//
//  ── The defect ─────────────────────────────────────────────────────────────────────────────
//  Screen 06 offers `Save a private reminder for yourself` and confirms the save is private to the
//  person who made it. Both were true — the row reaches `private_reminders` and nobody else can
//  read it — and there was nowhere in the app to read it *yourself*.
//  `LocalAPI.privateReminders(limit:)` had been written with the correct one-owner query and had no
//  shipping caller, so the whole feature was a control that acknowledged a save into a drawer with
//  no handle. Private is only a promise while the record is still reachable by its owner.
//
//  (The confirmation read `Saved. Your reminder stays yours alone.` until the copy audit of
//  2026-08-23; see `ReportCopy.reminderSaved`.)
//
//  ── Why the You tab ────────────────────────────────────────────────────────────────────────
//  ERRATA E23 settled that these are device-scoped and private, and that ownership moves onto an
//  account at `claimDevice`. That makes the list a statement about *you* rather than about a tree,
//  which is why it is not on screen 03: a tree profile is public in intent — everything on it is a
//  thing anybody looking at that tree would see — and a hazard reminder is the one record D4 keeps
//  off it. The You tab is where the app already keeps the person's own doors (BUILD-PLAN §9).
//
//  ── What is deliberately absent ────────────────────────────────────────────────────────────
//  No count, no dates rolled into a streak, no "you have reported N hazards" (ARCHITECTURE §5.1).
//  No delete: a reminder is soft-deletable in the model and there is no drawn control for it
//  anywhere, and inventing a destructive one on a screen whose whole subject is a safety note is a
//  bigger decision than this entry is making. Everything here is a door or a fact.
//
//  Presentation only — finished items and one callback — so each state photographs without a store.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct PrivateReminderList: View {

    let items: [PrivateReminderItem]
    /// Whether the read failed, as opposed to returning nothing. See `AccountModel.remindersFailed`
    /// — two tab roots in this app once drew their empty state on a failed read.
    var hasFailed = false
    /// Open the tree the reminder is about.
    var onOpen: (PrivateReminderItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(PrivateReminderCopy.sectionLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            if hasFailed {
                note(PrivateReminderCopy.failedState)
            } else if items.isEmpty {
                note(PrivateReminderCopy.emptyState)
            } else {
                VStack(spacing: CypressSpacing.gapRows) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - Empty and failed

    /// One card, two sentences, same shape either way. The distinction is in the words, not in the
    /// drawing — a failed read that looked like an empty list is exactly the bug this guards.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(CypressFont.body13)
            .foregroundStyle(CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, YouMetrics.settingPaddingV)
            .padding(.horizontal, YouMetrics.settingPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }

    // MARK: - A reminder

    private func row(_ item: PrivateReminderItem) -> some View {
        Button {
            onOpen(item)
        } label: {
            VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                Text(HazardCategoryLabel.text(for: item.category))
                    .font(CypressFont.body135Bold)
                    .foregroundStyle(CypressColor.textInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // No line at all when the tree could not be named, rather than an empty one: an
                // unnamed tree is not a tree with a blank name (the rule screens 11, 13 and 16 use
                // for their header pills).
                if let name = item.treeName, !name.isEmpty {
                    Text(name)
                        .font(CypressFont.body115)
                        .foregroundStyle(CypressColor.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(PrivateReminderCopy.savedLine(at: item.createdAt))
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, YouMetrics.settingPaddingV)
            .padding(.horizontal, YouMetrics.settingPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — no mock draws a reminder list. Each states a fact and
/// stops (ARCHITECTURE §5.7).
///
/// Nothing here may imply the city heard anything (DECISIONS §3.3, ARCHITECTURE §5.4). Screen 06's
/// disclosure says "the city has not been notified until you call", and a list of reminders is
/// exactly where that could quietly stop being said, so the empty state says it again.
enum PrivateReminderCopy {

    static let sectionLabel = "Your private reminders"

    /// Screen 06's own promise, restated where the reminders are. It says what the list is *for*, so
    /// an empty one reads as "nothing saved yet" rather than "nothing found".
    ///
    /// **It names the flow in the words the person saw, not the mock's number.** This string
    /// shipped as "a reminder you keep on screen 06 after a 311 handoff", and "screen 06" is a
    /// coordinate in SCREENS.md — it was the only user-facing string in the app that used one, and
    /// nobody reading the You tab has ever seen a screen number. "Report an issue" is screen 06's
    /// own C1 title and "Call 311 now" is the button above the save, so both halves of the sentence
    /// are now things a person can have read. The privacy fact at the end is still screen 06's
    /// confirmation and still the whole reason this section exists — it now says it in that
    /// screen's new words (copy audit of 2026-08-23, R20/R21), as its own sentence rather than as
    /// a clause hung off the end of a longer one.
    static let emptyState =
        "Nothing saved. A reminder you keep after reporting an issue and calling 311 shows up "
        + "here. Reminders are private to you."

    /// **A read that failed, said as a failure.** Not "nothing saved": that is a sentence about the
    /// person's records, and saying it over a database that could not be read tells somebody their
    /// reminders are gone.
    ///
    /// Three sentences rather than two since the copy audit of 2026-08-23 (R22). The em dash ran
    /// the reassurance into the instruction; the reassurance is the load-bearing half and now
    /// stands on its own.
    static let failedState = "Your reminders could not be read just now. Nothing has been lost. Open the You tab again."

    static func savedLine(at date: Date) -> String {
        "Saved \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
