//
//  TreeProfileView.swift
//  Cypress — Features/TreeProfile
//
//  Screen 03 · Tree profile, screen 14 · Cold-start profile, and D2 · Tree profile, dark.
//  SCREENS.md lines 716–766, 1143–1181 and 1401–1427.
//
//  One view, two states. `TreeProfilePresentation.isCold` decides which; SCREENS.md 14 describes
//  its own deltas as "differences from 03 to encode as a variant", and per D8 the cold variant is
//  what every tree in the shipped city inventory renders on launch day.
//
//  Everything visual is a C-component (C1, C2, C3, C6, C7, C8, C9, C11, C12, C13, C14, C26)
//  composed here. The only shape drawn in this folder is 14's camera glyph, which SCREENS.md
//  specifies by path and which no other screen uses.
//
//  ── Three affordances on this screen are invented, and are marked ─────────────────────────
//  The check-in button (C7), the "see the whole year" link under the activity feed, and the empty
//  measurement slot in the stat grid are not in SCREENS.md. They exist under a one-time, explicit
//  authorization from the project owner to give screens 05, 13 and 16 an entrance — four of the six
//  screens the app had built and could not reach. Each is decided in `TreeProfilePresentation`,
//  where the reasoning sits, so a designer can overrule any of them in one file. See ERRATA (E98).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). Spacing literals are SCREENS.md's own margins, taken from `CypressSpacing`.
//

import SwiftUI

struct TreeProfileView: View {

    @State private var model: TreeProfileModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Screen 04 is a camera, and `Route` has no case for it — the profile therefore hands the
    /// visit action out rather than inventing a destination (DECISIONS constraint 21).
    private let onVisit: (UUID) -> Void
    /// Favoriting is a mutation through the outbox, not a navigation. Same reason.
    private let onFavorite: (UUID) -> Void

    init(
        treeID: UUID,
        api: any CypressAPI,
        caretakerInitials: [String] = [],
        onVisit: @escaping (UUID) -> Void = { _ in },
        onFavorite: @escaping (UUID) -> Void = { _ in }
    ) {
        _model = State(
            wrappedValue: TreeProfileModel(treeID: treeID, api: api, caretakerInitials: caretakerInitials)
        )
        self.onVisit = onVisit
        self.onFavorite = onFavorite
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CypressColor.surfaceScreen)
            // Every screen here draws its own back control — C1's circle, or the hero's on 03 — so
            // the system bar would put a second `‹ Back` above it. Every other pushed destination
            // already hid it; this one and 19 were the two that did not, which is why a pushed
            // profile showed two ways back and the mocks show one.
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task { if model.presentation == nil { await model.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case let .failed(error):
            failure(error)
        case let .loaded(presentation):
            profile(presentation)
        }
    }

    // MARK: - The screen

    @ViewBuilder
    private func profile(_ presentation: TreeProfilePresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if presentation.isCold {
                    coldHeader
                    // The well says "No photos of this tree yet"; a vacant site has no tree to
                    // photograph and a memorial no longer has one, so neither gets the invitation.
                    // See `acceptsContributions`.
                    if presentation.acceptsContributions {
                        emptyPhotoWell
                    }
                } else {
                    hero(presentation)
                }

                if presentation.showsFoliageStrip {
                    foliageStrip(presentation)
                }

                identityBlock(presentation)

                if let tip = presentation.recognitionTip {
                    // C14. Absent when the species has no authored tip — no botany is invented to
                    // fill the box (BUILD-PLAN §15).
                    Callout(
                        " " + tip.text,
                        style: .green,
                        leadIn: TreeProfilePresentation.recognitionLeadIn
                    )
                    .padding(.horizontal, CypressSpacing.gutter)
                    .padding(.top, TreeProfileMetrics.blockGap)
                }

                if presentation.acceptsContributions {
                    PrimaryButton(presentation.ctaTitle) { onVisit(model.treeID) }
                        .padding(.horizontal, CypressSpacing.gutter)
                        .padding(
                            .top,
                            presentation.isCold ? TreeProfileMetrics.coldBlockGap : TreeProfileMetrics.blockGap
                        )
                }

                if presentation.offersCheckIn {
                    checkInButton
                }

                if !presentation.isCold {
                    QuadActionRow { action in perform(action) }
                    regularsRow(presentation)
                    activityFeed(presentation)
                }

                statGrid(presentation)

                if presentation.isCold {
                    footnote(presentation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The hero runs to the top of the display; its own 66pt inset positions the back circle
        // under the status bar. The cold header keeps the safe area, as 14's `padding-top:62px`.
        .ignoresSafeArea(edges: presentation.isCold ? [] : .top)
    }

    // MARK: - 1 · Hero (C2) / cold header (C1) + empty well

    private func hero(_ presentation: TreeProfilePresentation) -> some View {
        HeroPhotoHeader(
            style: colorScheme == .dark ? .profileDark : .profile,
            metaPill: presentation.heroMetaPill,
            // D2 drops the `Best photo · Oct 2025` eyebrow.
            eyebrow: colorScheme == .dark ? nil : presentation.heroEyebrow,
            onBack: { router?.pop() }
        )
    }

    private var coldHeader: some View {
        ScreenHeader(title: TreeProfilePresentation.fallbackTitle, onBack: { router?.pop() })
    }

    /// 14 §2 — the dashed well, `height:170px`, radius 18, `2px dashed`, centred `VStack(spacing:8)`.
    private var emptyPhotoWell: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            ZStack {
                Circle().fill(CypressColor.cityRecordBadgeFill)
                TreeProfileCameraGlyph()
            }
            .frame(width: TreeProfileMetrics.emptyWellCircle, height: TreeProfileMetrics.emptyWellCircle)

            Text(TreeProfilePresentation.emptyPhotoWellText)
                .font(CypressFont.body13)
                .foregroundStyle(CypressColor.textFaint)
        }
        .frame(maxWidth: .infinity)
        .frame(height: TreeProfileMetrics.emptyWellHeight)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                .fill(CypressColor.surfaceEmptyThumb)
        }
        .cypressDashedBorder(
            CypressColor.borderDashedStrong,
            radius: CypressRadius.cardLg,
            width: CypressSpacing.Component.outlineWidth
        )
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, TreeProfileMetrics.wellTop)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 2 · Foliage strip (C3, A5, D5)

    private func foliageStrip(_ presentation: TreeProfilePresentation) -> some View {
        FoliageStrip(
            // D5 is enforced inside the component; handing it the species attribute is the whole
            // contract. An evergreen can never take the leaf-off treatment.
            leafRetention: presentation.leafRetention,
            densities: presentation.foliageDensities,
            // D2 drops the month row.
            showsMonthRow: colorScheme != .dark
        )
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, TreeProfileMetrics.blockGap)
        // The component labels each cell as a canopy state; this strip encodes photo coverage
        // (A5), so the honest label replaces them rather than sitting alongside.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.foliageStripAccessibilityLabel)
    }

    // MARK: - 3 · Identity block

    private func identityBlock(_ presentation: TreeProfilePresentation) -> some View {
        VStack(alignment: .leading, spacing: TreeProfileMetrics.latinTop) {
            HStack(alignment: .firstTextBaseline, spacing: CypressSpacing.gapCandidates) {
                Text(presentation.title)
                    .font(presentation.isCold ? CypressFont.treeNameColdStart : CypressFont.treeNameHero)
                    .foregroundStyle(CypressColor.textInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = presentation.badge {
                    StatusBadge(badge)
                }
                Spacer(minLength: 0)
            }
            Text(presentation.subtitle)
                .cypressLatinName(presentation.isCold ? CypressFont.latinName145 : CypressFont.latinName)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, presentation.isCold ? CypressSpacing.gutterLabel : CypressSpacing.gutter)
        .padding(.top, presentation.isCold ? TreeProfileMetrics.coldBlockGap : TreeProfileMetrics.blockGap)
    }

    // MARK: - 7 · Regulars row (C26, A8, D1)

    @ViewBuilder
    private func regularsRow(_ presentation: TreeProfilePresentation) -> some View {
        // D2 drops the regulars row entirely, and A8 hides it below three caretakers.
        if colorScheme != .dark,
           let caretakers = presentation.caretakers,
           let headline = presentation.caretakerHeadline {
            HStack(spacing: CypressSpacing.gapCandidates) {
                AvatarStack(
                    initials: Array(caretakers.initials.prefix(TreeProfileMetrics.avatarsShown)),
                    overflow: overflowLabel(for: caretakers)
                )
                Text(headline)
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.textBody)
                Spacer(minLength: 0)
                // SCREENS.md draws a trailing mono `2 this month` here. It is a public count of
                // user actions, which D1 forbids and which DECISIONS outranks SCREENS.md on
                // (ARCHITECTURE §1 precedence). Recency and identity phrasing only, so it is gone.
            }
            .padding(.vertical, TreeProfileMetrics.regularsPaddingV)
            .padding(.horizontal, TreeProfileMetrics.regularsPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
            .cypressCardShadow()
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, TreeProfileMetrics.regularsTop)
            .accessibilityElement(children: .combine)
        }
    }

    private func overflowLabel(for caretakers: TreeProfilePresentation.Caretakers) -> String? {
        let shown = min(caretakers.initials.count, TreeProfileMetrics.avatarsShown)
        let remaining = caretakers.count - shown
        return remaining > 0 ? "+\(remaining)" : nil
    }

    // MARK: - 5b · Check-in (C7, screen 05)

    /// The check-in entrance. C7 at its compact size, which is what 06 uses for the same
    /// relationship — one loud thing, one quiet one under it.
    ///
    /// See `TreeProfilePresentation.checkInCTATitle` for why this control exists at all and under
    /// whose authority; it is invented, and it is marked so a designer can delete it in one place.
    private var checkInButton: some View {
        SecondaryOutlineButton(TreeProfilePresentation.checkInCTATitle, style: .compact) {
            router?.push(.checkIn(model.treeID))
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, CypressSpacing.gapRows)
    }

    // MARK: - 8 · Activity feed (C9)

    @ViewBuilder
    private func activityFeed(_ presentation: TreeProfilePresentation) -> some View {
        if !presentation.activity.isEmpty {
            VStack(spacing: CypressSpacing.gapRows) {
                ForEach(presentation.activity) { item in
                    ActivityRow(
                        leading: leading(for: item),
                        label: item.label,
                        detail: item.detail,
                        timestamp: item.timestamp
                    )
                }
            }
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, CypressSpacing.gapRows)

            if presentation.offersActivityLink {
                activityLink
            }
        }
    }

    /// The activity entrance (screen 13). See `TreeProfilePresentation.activityLinkTitle`.
    ///
    /// A text link rather than a C-component: C1–C30 is a closed catalogue and none of it is a link.
    /// Building a small screen-local control from tokens is what this codebase already does where
    /// the catalogue has no entry — screen 08's three-pill row and screen 13's photo strip are both
    /// built that way (ERRATA E46). It takes its colour and weight from the tokens C7 uses, so it
    /// reads as the same family of control at a quieter volume, and `.cypressHitArea()` gives a
    /// one-line label the 44pt target ARCHITECTURE §6 requires.
    private var activityLink: some View {
        Button {
            router?.push(.activity(model.treeID))
        } label: {
            Text(TreeProfilePresentation.activityLinkTitle)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, TreeProfileMetrics.activityLinkTop)
    }

    private func leading(for item: TreeProfilePresentation.ActivityItem) -> ActivityRow.Leading {
        switch item.kind {
        case .visit:
            return .photo(colorScheme == .dark ? CypressGradient.activityVisitDark : CypressGradient.activityVisit)
        case .care:
            return .care
        }
    }

    // MARK: - 9 · Stat grid (C11, C12, D7)

    private func statGrid(_ presentation: TreeProfilePresentation) -> some View {
        StatGrid {
            ForEach(presentation.stats) { stat in
                if let destination = stat.destination {
                    // One control, two destinations: a card with a reading opens the history of it
                    // (11), a card without one opens the sheet that writes it (16). Which is which
                    // is `TreeProfilePresentation.StatDestination`'s decision, not this view's.
                    Button {
                        router?.push(route(for: destination))
                    } label: {
                        // The city's site vocabulary is free text (BUILD-PLAN §7) and can run to
                        // three lines; `maxHeight` keeps the two cards of a row the same height
                        // rather than letting one card float short beside a tall neighbour.
                        StatCard(label: stat.label, value: stat.value)
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .cypressHitArea()
                } else {
                    StatCard(label: stat.label, value: stat.value)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, presentation.isCold ? TreeProfileMetrics.blockGap : TreeProfileMetrics.statGridTop)
        .padding(.bottom, presentation.isCold ? 0 : CypressSpacing.bottomBar)
    }

    // MARK: - 7 (cold) · Footnote

    private func footnote(_ presentation: TreeProfilePresentation) -> some View {
        Text(presentation.coldStartFootnote)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TreeProfileMetrics.footnotePaddingH)
            .padding(.top, TreeProfileMetrics.footnoteTop)
            .padding(.bottom, CypressSpacing.bottomFootnote)
    }

    // MARK: - Failure

    private func failure(_ error: APIError) -> some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(error == .notFound ? "No record for this tree." : "This profile could not be loaded.")
                .cypressBody135()
            if error.retryable {
                SecondaryOutlineButton("Try again", style: .compact) {
                    Task { await model.reload() }
                }
                .frame(maxWidth: TreeProfileMetrics.retryButtonWidth)
            }
        }
        .padding(CypressSpacing.gutter)
    }

    // MARK: - Affordances

    private func route(for destination: TreeProfilePresentation.StatDestination) -> Route {
        switch destination {
        case .growthHistory: return .growthHistory(model.treeID)
        case .measure: return .measure(model.treeID)
        }
    }

    private func perform(_ action: QuadActionRow.Action) {
        switch action {
        case .favorite: onFavorite(model.treeID)
        case .care: router?.present(.careLog(model.treeID))
        case .share: router?.present(.share(model.treeID))
        case .report: router?.push(.report(model.treeID))
        }
    }
}

// MARK: - Screen metrics

/// The margins SCREENS.md gives screens 03 and 14 that `CypressSpacing` does not already name.
/// Kept together so the screen has no loose numbers in its body.
enum TreeProfileMetrics {
    /// 03: `padding:12px 16px 0` between blocks.
    static let blockGap: CGFloat = 12
    /// 14: `padding:14px 18px 0`.
    static let coldBlockGap: CGFloat = 14
    /// 03 §3: `margin-top:2px` on the latin line.
    static let latinTop: CGFloat = 2
    /// 14 §2: `margin:10px 16px 0`, `height:170px`.
    static let wellTop: CGFloat = 10
    static let emptyWellHeight: CGFloat = 170
    /// The 46×46 circle behind the camera glyph.
    static let emptyWellCircle: CGFloat = 46
    /// 03 §7: `margin:10px 16px 0`, `padding:9px 13px`.
    static let regularsTop: CGFloat = 10
    static let regularsPaddingV: CGFloat = 9
    static let regularsPaddingH: CGFloat = 13
    /// C26 draws three initials plus an overflow bubble.
    static let avatarsShown = 3
    /// Not a spec value — the gap above the invented "see the whole year" link, matched to the
    /// spacing between the C9 rows it follows so it reads as part of the same block.
    static let activityLinkTop: CGFloat = 8
    /// 03 §9: `padding:10px 16px 30px`.
    static let statGridTop: CGFloat = 10
    /// 14 §7: `padding:14px 24px 36px`.
    static let footnoteTop: CGFloat = 14
    static let footnotePaddingH: CGFloat = 24
    /// Not a spec value — the retry control on the failure state, which SCREENS.md does not draw.
    static let retryButtonWidth: CGFloat = 200
}

// MARK: - 14's camera glyph

/// SCREENS.md 14 §2, by path: `rect 1,4 20×13 rx3` + `circle 11,10.5 r3.6` stroked, and a filled
/// `rect 7,1 8×4 rx1.5`, in a 22×18 box, stroke width 1.8.
///
/// Local to this folder rather than in `DesignSystem/Components`: no other screen in SCREENS.md
/// uses it, and C1–C30 is a closed catalogue.
struct TreeProfileCameraGlyph: View {
    var body: some View {
        ZStack {
            TreeProfileCameraBody()
                .stroke(
                    CypressColor.textFaint,
                    style: StrokeStyle(lineWidth: TreeProfileCameraGlyph.stroke, lineJoin: .round)
                )
            TreeProfileCameraBump()
                .fill(CypressColor.textFaint)
        }
        .frame(width: TreeProfileCameraGlyph.width, height: TreeProfileCameraGlyph.height)
        .accessibilityHidden(true)
    }

    static let width: CGFloat = 22
    static let height: CGFloat = 18
    static let stroke: CGFloat = 1.8
}

private struct TreeProfileCameraBody: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / TreeProfileCameraGlyph.width, rect.height / TreeProfileCameraGlyph.height)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 1 * s, y: 4 * s, width: 20 * s, height: 13 * s),
            cornerSize: CGSize(width: 3 * s, height: 3 * s),
            style: .continuous
        )
        path.addEllipse(
            in: CGRect(x: (11 - 3.6) * s, y: (10.5 - 3.6) * s, width: 7.2 * s, height: 7.2 * s)
        )
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct TreeProfileCameraBump: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / TreeProfileCameraGlyph.width, rect.height / TreeProfileCameraGlyph.height)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 7 * s, y: 1 * s, width: 8 * s, height: 4 * s),
            cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s),
            style: .continuous
        )
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
