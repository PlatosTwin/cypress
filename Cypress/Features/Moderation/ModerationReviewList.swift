//
//  ModerationReviewList.swift
//  Cypress — Features/Moderation
//
//  A lead's removal-review queue, drawn from a finished list of items and two callbacks (ERRATA
//  E124-B). Presentation only — no `LocalAPI`, no async — so it photographs and previews with static
//  data, the same split `AlmanacScreen` and `AccountAskScreen` use.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). Every string here is NOT SPECIFIED
//  — the moderation surface has no mock — so each states a fact and stops, the shape the rest of the
//  unspecified copy in this app uses.
//

import SwiftUI

struct ModerationReviewList: View {

    let items: [RemovalReviewItem]
    /// Open the tree so a lead can look before confirming.
    var onOpen: (RemovalReviewItem) -> Void = { _ in }
    /// Confirm the removal — the tree becomes a memorial.
    var onConfirm: (RemovalReviewItem) -> Void = { _ in }

    /// The tree a confirm is pending on. Marking a city record removed is consequential and one-way
    /// in the app today, so it asks first.
    @State private var pending: RemovalReviewItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ModerationCopy.sectionLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            if items.isEmpty {
                empty
            } else {
                VStack(spacing: CypressSpacing.gapRows) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
        }
        .confirmationDialog(
            ModerationCopy.confirmTitle,
            isPresented: confirmPresented,
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(ModerationCopy.confirmAction, role: .destructive) { onConfirm(item) }
            Button(ModerationCopy.cancel, role: .cancel) {}
        } message: { item in
            Text(ModerationCopy.confirmMessage(treeName: item.treeName))
        }
    }

    // MARK: - Empty

    private var empty: some View {
        Text(ModerationCopy.emptyState)
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

    // MARK: - A review

    private func row(_ item: RemovalReviewItem) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            // The tapping target that opens the tree: the whole heading block.
            Button {
                onOpen(item)
            } label: {
                VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                    Text(item.treeName)
                        .font(CypressFont.body135Bold)
                        .foregroundStyle(CypressColor.textInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let address = item.address, !address.isEmpty {
                        Text(address)
                            .font(CypressFont.body115)
                            .foregroundStyle(CypressColor.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(ModerationCopy.raisedLine(at: item.raisedAt))
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            confirmButton(item)
        }
        .padding(.vertical, YouMetrics.settingPaddingV)
        .padding(.horizontal, YouMetrics.settingPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }

    private func confirmButton(_ item: RemovalReviewItem) -> some View {
        Button {
            pending = item
        } label: {
            Text(ModerationCopy.confirmAction)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ModerationMetrics.buttonPaddingV)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(CypressColor.ctaFill)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var confirmPresented: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — the moderation surface has no mock. Each states a fact
/// and stops (ARCHITECTURE §5.7: sentence case, no spaces around em dashes).
enum ModerationCopy {
    static let sectionLabel = "Reviews"

    static let emptyState = "Nothing is waiting. When someone reports a tree as removed, it shows up here to confirm."

    static let confirmAction = "Confirm removed"
    static let confirmTitle = "Mark this tree as removed?"
    static let cancel = "Cancel"

    static func confirmMessage(treeName: String) -> String {
        "\(treeName) becomes a memorial page. This is how the city record is corrected."
    }

    static func raisedLine(at date: Date) -> String {
        "Reported removed · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Metrics

/// **Not spec values** — the moderation surface has no drawn geometry. These follow the You tab's
/// own setting row (`YouMetrics`), which is the nearest thing in the app to these cards.
enum ModerationMetrics {
    static let buttonPaddingV: CGFloat = 10
}
