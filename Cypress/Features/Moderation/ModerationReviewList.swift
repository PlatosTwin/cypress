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

    let items: [ReviewQueueItem]
    /// Open the tree so a lead can look before deciding.
    var onOpen: (ReviewQueueItem) -> Void = { _ in }
    /// Confirm — the tree takes the status the report claimed.
    var onConfirm: (ReviewQueueItem) -> Void = { _ in }
    /// Dismiss — the flag closes and the tree does not move (ERRATA E170).
    var onDismiss: (ReviewQueueItem) -> Void = { _ in }

    /// The tree a confirm is pending on. Moving a city record's status is consequential and one-way
    /// in the app today, so it asks first.
    @State private var pending: ReviewQueueItem?

    /// The tree a dismiss is pending on. It asks too, and not out of symmetry: dismissing is the one
    /// verb here that makes somebody else's report go away, and there is no undo for it either.
    @State private var pendingDismissal: ReviewQueueItem?

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
            ModerationCopy.confirmTitle(kind: pending?.kind),
            isPresented: confirmPresented,
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(ModerationCopy.confirmAction(kind: item.kind), role: .destructive) { onConfirm(item) }
            Button(ModerationCopy.cancel, role: .cancel) {}
        } message: { item in
            Text(ModerationCopy.confirmMessage(treeName: item.treeName, kind: item.kind))
        }
        .confirmationDialog(
            ModerationCopy.dismissTitle,
            isPresented: dismissPresented,
            titleVisibility: .visible,
            presenting: pendingDismissal
        ) { item in
            Button(ModerationCopy.dismissAction, role: .destructive) { onDismiss(item) }
            Button(ModerationCopy.cancel, role: .cancel) {}
        } message: { item in
            Text(ModerationCopy.dismissMessage(treeName: item.treeName))
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

    private func row(_ item: ReviewQueueItem) -> some View {
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
                    Text(ModerationCopy.raisedLine(kind: item.kind, at: item.raisedAt))
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Two verbs, and the confirm is the filled one. Not because dismissing matters less —
            // it is the honest answer to a wrong report — but because the two must not look
            // interchangeable on a row whose confirm moves a city record's status.
            confirmButton(item)
            dismissButton(item)
        }
        .padding(.vertical, YouMetrics.settingPaddingV)
        .padding(.horizontal, YouMetrics.settingPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }

    private func confirmButton(_ item: ReviewQueueItem) -> some View {
        Button {
            pending = item
        } label: {
            Text(ModerationCopy.confirmAction(kind: item.kind))
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

    /// The second verb, drawn as an outlined button rather than a filled one — the same weight
    /// difference the app already uses between a primary action and the one beside it.
    private func dismissButton(_ item: ReviewQueueItem) -> some View {
        Button {
            pendingDismissal = item
        } label: {
            Text(ModerationCopy.dismissAction)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ModerationMetrics.buttonPaddingV)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }

    private var confirmPresented: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )
    }

    private var dismissPresented: Binding<Bool> {
        Binding(
            get: { pendingDismissal != nil },
            set: { if !$0 { pendingDismissal = nil } }
        )
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — the moderation surface has no mock. Each states a fact
/// and stops (ARCHITECTURE §5.7: sentence case, no spaces around em dashes).
enum ModerationCopy {
    static let sectionLabel = "Reviews"

    static let emptyState = "Nothing is waiting. When someone reports a tree as dead or removed, it shows up here to review."

    static let cancel = "Cancel"

    // MARK: Confirm — one verb, two vocabularies (ERRATA E170)

    /// The two kinds must not share a word. "Confirm removed" over a tree somebody reported *dead*
    /// was the shape of the defect this closes: one queue, one verb, and a lead with no way to tell
    /// from the button which claim they were agreeing with.
    ///
    /// The `default` covers the kinds that never reach this queue (`ReviewFlag.Kind.confirmedStatus`
    /// is nil for them, and `openReviews` does not fetch them). It says the plain thing rather than
    /// naming a status, because a kind arriving here that cannot resolve into one is a bug, and a
    /// button that guessed at a status would be that bug wearing a confident label.
    static func confirmAction(kind: ReviewFlag.Kind?) -> String {
        switch kind {
        case .appearsRemoved: return "Confirm removed"
        case .appearsDead: return "Confirm dead"
        default: return "Confirm"
        }
    }

    static func confirmTitle(kind: ReviewFlag.Kind?) -> String {
        switch kind {
        case .appearsRemoved: return "Mark this tree as removed?"
        case .appearsDead: return "Mark this tree as dead?"
        default: return "Confirm this report?"
        }
    }

    /// What actually happens, per kind, and **nothing about the city**.
    ///
    /// The removal line used to end "This is how the city record is corrected", which is the sentence
    /// DECISIONS §3.3 forbids wearing a passive voice: nothing in this app notifies San Francisco, and
    /// confirming a flag writes one row in `tree_status_overrides` on this phone. RULINGS R12 exists
    /// because that gap was noticed once already; it is not going to be re-introduced in the copy for
    /// the surface that closes R12's other half.
    ///
    /// The dead line says the tree stays, because that is the part a lead cannot guess: a confirmed
    /// death is not a memorial and the profile keeps its REPORT and CARE buttons
    /// (`TreeStatus.deadReported.acceptsNewContributions`).
    static func confirmMessage(treeName: String, kind: ReviewFlag.Kind?) -> String {
        switch kind {
        case .appearsRemoved:
            return "\(treeName) becomes a memorial page on this phone. The city is not notified."
        case .appearsDead:
            return "\(treeName) is marked dead on this phone and keeps its page, so a hazard here can still be reported. The city is not notified."
        default:
            return "\(treeName) is updated on this phone. The city is not notified."
        }
    }

    // MARK: Dismiss — the verb the queue never had (ERRATA E170)

    static let dismissAction = "Dismiss"
    static let dismissTitle = "Dismiss this report?"

    /// Names the two things a lead needs to know and stops: nothing moves, and the report goes away.
    /// It does not apologize for the reporter or editorialise about who was right — `review_flags`
    /// records who raised it and who closed it, and that is the whole of what the app knows.
    static func dismissMessage(treeName: String) -> String {
        "\(treeName) is left as it is and the report closes. Nothing about the tree changes."
    }

    // MARK: The row

    static func raisedLine(kind: ReviewFlag.Kind, at date: Date) -> String {
        let what: String
        switch kind {
        case .appearsRemoved: what = "Reported removed"
        case .appearsDead: what = "Reported dead"
        default: what = "Reported"
        }
        return "\(what) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Metrics

/// **Not spec values** — the moderation surface has no drawn geometry. These follow the You tab's
/// own setting row (`YouMetrics`), which is the nearest thing in the app to these cards.
enum ModerationMetrics {
    static let buttonPaddingV: CGFloat = 10
}
