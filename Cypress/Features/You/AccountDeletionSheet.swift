//
//  AccountDeletionSheet.swift
//  Cypress — Features/You
//
//  The two doors at the deletion step (the project owner's ruling; `AccountDeletionChoice` argues
//  the design, `AccountDeletionCopy` holds every word). Presentation only — a binding, three
//  callbacks and no `LocalAPI` — so every state previews and photographs with static data.
//
//  ── Why this is a sheet and no longer a confirmation dialog ────────────────────────────────
//  The surface it replaces was a `confirmationDialog` with two buttons and a message, and it was the
//  right shape for one behavior: the destructive tap and the sentence about it in the same modal
//  moment. It cannot hold two. A dialog's message is a single blob and its buttons are bare labels,
//  so a two-door dialog would have to put the difference between the doors *inside the button
//  titles* — which is precisely the arrangement in which a person chooses before they have read
//  anything. The owner's constraint is the opposite: both doors readable **before** choosing.
//
//  So: a sheet that draws both paragraphs at once, with the safe one already selected. Still
//  **NOT SPECIFIED** — SCREENS.md draws no deletion surface and BUILD-PLAN §9 lists none — so it
//  follows the nearest specified thing (ARCHITECTURE rule 8), which is screen 15's sheet: the same
//  card-and-hairline vocabulary the You tab already uses, and the app's own CTA at the bottom.
//
//  ── The three gates, and what each one is for ──────────────────────────────────────────────
//  1. The You tab's destructive row **opens this sheet and destroys nothing**. Verified against the
//     database in ERRATA E131 and still true.
//  2. Choosing is a tap on a card. Nothing happens on selection; the account is untouched until the
//     CTA is pressed, and the CTA's label names the door it will take, so the last tap on the safe
//     path reads `Delete account, leave my records` and the last tap on the other reads
//     `Delete account and erase everything`. That is the whole defense against reaching the
//     destructive door by momentum: it cannot be reached without the word "erase" being under the
//     thumb.
//  3. The destructive door alone raises a second confirmation. The asymmetry is the design: the safe
//     path stays two taps and does not feel like a penance, and the door that destroys somebody's
//     photographs asks once more in words that name them.
//
//  Not a raw hex, font size or radius in the file (ARCHITECTURE §6).
//

import SwiftUI

struct AccountDeletionSheet: View {

    /// The door, owned by the presenter so that raising the sheet can reset it. See
    /// `AccountSection` for why it is not `@State` here: a choice that survived a dismissal would
    /// be a destructive setting somebody could forget they had left switched on.
    @Binding var choice: AccountDeletionChoice

    /// Whether a deletion is already in flight. Everything stops accepting taps while it is.
    var isBusy = false

    /// Called with the chosen door, and only from behind gate 2 or gate 3 above.
    var onDelete: (AccountDeletionChoice) -> Void = { _ in }

    /// `Keep my account`, and the swipe-down, and the scrim. All three mean the same thing.
    var onCancel: () -> Void = {}

    /// The destructive door's second gate.
    @State private var isConfirmingErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                question
                doors
                consequences
                actions
            }
            .padding(.horizontal, CypressSpacing.gutterSheet)
            .padding(.top, AccountDeletionMetrics.sheetTop)
            .padding(.bottom, CypressSpacing.bottomSheet)
        }
        .background(CypressColor.surfaceSheet)
        // ══════════════════════════════════════════════════════════════════════════════════════
        // Gate 3, on the destructive door only. `eraseConfirmCancel` carries `role: .cancel`, so
        // backing out is the outside tap, the Escape key and the VoiceOver default — and it backs
        // out to the *choice*, where the account still exists, which is why it says `Go back`
        // rather than `Keep my account`.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .confirmationDialog(
            AccountDeletionCopy.eraseConfirmTitle,
            isPresented: $isConfirmingErase,
            titleVisibility: .visible
        ) {
            Button(AccountDeletionCopy.eraseConfirmAction, role: .destructive) {
                onDelete(.eraseEverything)
            }
            Button(AccountDeletionCopy.eraseConfirmCancel, role: .cancel) {}
        } message: {
            Text(AccountDeletionCopy.eraseConfirmMessage)
        }
    }

    // MARK: - Head

    private var title: some View {
        Text(AccountDeletionCopy.title)
            .font(CypressFont.accountTitle)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, AccountDeletionMetrics.titleBottom)
    }

    private var question: some View {
        Text(AccountDeletionCopy.choiceQuestion)
            .font(CypressFont.body135Bold)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, AccountDeletionMetrics.questionBottom)
    }

    // MARK: - The doors

    /// Both, always, in `AccountDeletionChoice.allCases` order — which puts the default first, and
    /// puts it first *because* the enum declares it first rather than because this view sorted it.
    private var doors: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            ForEach(AccountDeletionChoice.allCases, id: \.self) { door in
                DoorCard(
                    door: door,
                    isChosen: choice == door,
                    action: isBusy ? nil : { choice = door }
                )
            }
        }
    }

    // MARK: - What is true either way

    /// R3's other half, the queue clause, and the one fact that cannot be undone — below both doors
    /// and outside both, because all three are true of whichever one is chosen.
    private var consequences: some View {
        VStack(alignment: .leading, spacing: AccountDeletionMetrics.consequenceGap) {
            Text(AccountDeletionCopy.personalRecords)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)

            Text(AccountDeletionCopy.queuedWork)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)

            Text(AccountDeletionCopy.irreversible)
                .font(CypressFont.body125Bold)
                .foregroundStyle(CypressColor.textInk)
        }
        .lineSpacing(CypressFont.LineSpacing.body125)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AccountDeletionMetrics.consequencesTop)
        .padding(.bottom, AccountDeletionMetrics.consequencesBottom)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: AccountDeletionMetrics.actionGap) {
            DeleteButton(
                title: AccountDeletionCopy.confirmAction(for: choice),
                isDestructiveDoor: choice == .eraseEverything,
                isEnabled: !isBusy,
                action: confirm
            )

            Button(action: isBusy ? {} : onCancel) {
                Text(AccountDeletionCopy.cancelAction)
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.textMuted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cypressHitArea()
            .disabled(isBusy)
        }
    }

    /// The one place a tap can become a deletion, and it deletes nothing on the destructive door —
    /// it raises gate 3. Written as a `switch` rather than an `if` so that a third door added later
    /// cannot silently inherit the safe path's single confirmation.
    private func confirm() {
        switch choice {
        case .leaveRecords: onDelete(.leaveRecords)
        case .eraseEverything: isConfirmingErase = true
        }
    }
}

// MARK: - One door

/// A selectable card carrying a door's whole paragraph. Both are on screen at once, which is the
/// owner's constraint that both be readable before choosing, taken literally.
///
/// The selection is drawn in the app's own two accent registers rather than in a new one: the
/// default door in `selectionFill`, which is what "chosen" looks like everywhere else in Cypress,
/// and the destructive door in the amber the 311 hazard panel uses, which is this app's only color
/// for "stop and read". There is no red in the palette and this is not the place to introduce one.
private struct DoorCard: View {

    let door: AccountDeletionChoice
    let isChosen: Bool
    var action: (() -> Void)?

    var body: some View {
        Button(action: action ?? {}) {
            VStack(alignment: .leading, spacing: AccountDeletionMetrics.doorTextGap) {
                HStack(alignment: .top, spacing: AccountDeletionMetrics.doorMarkGap) {
                    mark
                    Text(title)
                        .font(CypressFont.body14)
                        .foregroundStyle(CypressColor.textInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(paragraph)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineSpacing(CypressFont.LineSpacing.body125)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, AccountDeletionMetrics.doorBodyInset)
            }
            .padding(.vertical, YouMetrics.settingPaddingV)
            .padding(.horizontal, YouMetrics.settingPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(isChosen ? chosenFill : CypressColor.surfaceCard)
            }
            .cypressBorder(
                isChosen ? chosenBorder : CypressColor.borderCool,
                radius: CypressRadius.cardSm
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// The radio mark. A filled ring in the door's own accent, drawn from the same tokens as the
    /// border so a card cannot say "chosen" in one place and "not chosen" in another.
    private var mark: some View {
        Circle()
            .strokeBorder(
                isChosen ? chosenBorder : CypressColor.borderDashedStrong,
                lineWidth: AccountDeletionMetrics.markStroke
            )
            .background {
                if isChosen {
                    Circle()
                        .fill(chosenBorder)
                        .padding(AccountDeletionMetrics.markInset)
                }
            }
            .frame(width: AccountDeletionMetrics.markSide, height: AccountDeletionMetrics.markSide)
            .padding(.top, AccountDeletionMetrics.markTop)
            .accessibilityHidden(true)
    }

    private var title: String {
        switch door {
        case .leaveRecords: return AccountDeletionCopy.leaveRecordsTitle
        case .eraseEverything: return AccountDeletionCopy.eraseEverythingTitle
        }
    }

    private var paragraph: String {
        switch door {
        case .leaveRecords: return AccountDeletionCopy.leaveRecordsBody
        case .eraseEverything: return AccountDeletionCopy.eraseEverythingBody
        }
    }

    private var chosenBorder: Color {
        switch door {
        case .leaveRecords: return CypressColor.selectionFill
        case .eraseEverything: return CypressColor.hazardPanelBorder
        }
    }

    private var chosenFill: Color {
        switch door {
        case .leaveRecords: return CypressColor.calloutGreenFill
        case .eraseEverything: return CypressColor.hazardPanelFill
        }
    }
}

// MARK: - The CTA

/// The app's primary CTA shape, in one of two fills.
///
/// Not `PrimaryButton` with a flag: C6's fill is `ctaFill` for every caller in the app, and adding a
/// destructive case to the shared component would put a color on it that only one screen ever uses
/// — the argument `AccountProviderButton` makes for screen 15's three routes, applied here. The
/// geometry is C6's own tokens so it still reads as the same control.
private struct DeleteButton: View {

    let title: String
    let isDestructiveDoor: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CypressFont.body16)
                .foregroundStyle(isEnabled ? label : CypressColor.ctaDisabledLabel)
                .frame(maxWidth: .infinity)
                .padding(CypressSpacing.Component.buttonPadding)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(isEnabled ? fill : CypressColor.ctaDisabledFill)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var fill: Color {
        isDestructiveDoor ? CypressColor.hazardCTAFill : CypressColor.ctaFill
    }

    private var label: Color {
        isDestructiveDoor ? CypressColor.hazardCTAText : CypressColor.ctaLabel
    }
}

// MARK: - Metrics

/// **NOT SPECIFIED**, like the surface itself. Every number is either one the You tab already uses
/// or the smallest value that keeps this sheet from looking like a different app (ARCHITECTURE §6:
/// no raw number in a view file).
enum AccountDeletionMetrics {
    static let sheetTop: CGFloat = 28
    static let titleBottom: CGFloat = 14
    static let questionBottom: CGFloat = 10
    static let consequencesTop: CGFloat = 18
    static let consequencesBottom: CGFloat = 22
    static let consequenceGap: CGFloat = 10
    static let actionGap: CGFloat = 12
    static let doorTextGap: CGFloat = 6
    static let doorMarkGap: CGFloat = 10
    /// Lines the paragraph up under the title rather than under the radio mark.
    static let doorBodyInset: CGFloat = 28
    static let markSide: CGFloat = 18
    static let markStroke: CGFloat = 1.5
    static let markInset: CGFloat = 4
    static let markTop: CGFloat = 1
}
