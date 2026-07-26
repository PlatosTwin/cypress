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
//  ── Two things this screen now refuses to draw ───────────────────────────────────────────
//  - **A record with no tree in it.** A vacant planting site leaves for `Route.site` before anything
//    is derived; the decision is `TreeProfileDestination`, asked once under every entrance rather
//    than at any of them. See ERRATA (E113).
//  - **A favourite it cannot confirm.** C8's first cell has an on-state (RULINGS R2), and the state
//    is what the store holds rather than what the last tap said. See ERRATA (E112).
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). Spacing literals are SCREENS.md's own margins, taken from `CypressSpacing`.
//

import SwiftUI

struct TreeProfileView: View {

    @State private var model: TreeProfileModel
    /// Whether this screen has been on screen before — see the `onAppear` on `body`.
    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Screen 04 is a camera, and `Route` has no case for it — the profile therefore hands the
    /// visit action out rather than inventing a destination (DECISIONS constraint 21).
    private let onVisit: (UUID) -> Void

    /// Held so the species picker can be handed the same boundary this screen reads through. The
    /// model owns its own reference; this one exists because `SpeciesPickView` builds its own model.
    private let api: any CypressAPI

    /// - Parameter onFavorite: writes the *resulting state* of the heart — `true` for a favourite,
    ///   `false` for taking it off (RULINGS R2). Favoriting is a mutation through the outbox rather
    ///   than a navigation, and its owner is the composition root's to resolve (D9), so it is handed
    ///   in for the same reason the visit is. The screen does not read its result: what the cell
    ///   shows next is re-read from the store by `TreeProfileModel`.
    init(
        treeID: UUID,
        api: any CypressAPI,
        caretakerInitials: [String] = [],
        onVisit: @escaping (UUID) -> Void = { _ in },
        onFavorite: @escaping (UUID, Bool) async -> Void = { _, _ in }
    ) {
        _model = State(
            wrappedValue: TreeProfileModel(
                treeID: treeID,
                api: api,
                caretakerInitials: caretakerInitials,
                setFavorite: onFavorite
            )
        )
        self.api = api
        self.onVisit = onVisit
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
            // Re-read when this screen comes back to the front (ERRATA E127).
            //
            // Every write this screen hands out lands somewhere else and comes back: the measure
            // sheet (16), the care log (09), the check-in (05), the report (06), the camera (04).
            // The profile read them all once, on first appearance, and then never again — so a
            // reading taken on 16 left the stat card still saying `Add a reading`, the growth link
            // still absent, and the person who had just measured the tree looking at a screen that
            // did not know it. That is the reachability half of screen 11's defect; the link is the
            // other half.
            //
            // Not the first appearance, which `.task` above already served: `load()` would run twice
            // on every push. `reload()` keeps what is on screen while the read runs, so coming back
            // never blanks the profile.
            .onAppear {
                guard hasAppeared else {
                    hasAppeared = true
                    return
                }
                Task { await model.reload() }
            }
            // And when a sheet closes over it, which `onAppear` does not cover: a `fullScreenCover`
            // does not remove the screen underneath, so dismissing one fires no appearance at all.
            // The three writes that leave this screen that way are the camera (04), the care log (09)
            // and the share sheet, and the first of them is the loudest — log a visit from the CTA
            // and the profile it was made from went on saying "Be the first to photograph this tree"
            // about a tree that now had a photograph on it. Seen on the simulator, not in a test.
            .onChange(of: router?.sheet == nil) { _, nothingPresented in
                guard nothingPresented, model.presentation != nil else { return }
                Task { await model.reload() }
            }
            // A cover rather than a sheet, for the same reason the add flow uses one: the picker puts
            // a keyboard and a scrolling list up, and a half-height sheet leaves the list two rows
            // tall on a small phone. It is also the shape the same picker already has in the add
            // flow, and one control should not look like two screens.
            .fullScreenCover(isPresented: $model.isNamingSpecies) {
                SpeciesPickView(
                    api: api,
                    onPick: { species in Task { await model.claimSpecies(species) } },
                    // Declining here is simply leaving. Unlike the add screen there is no draft to
                    // retract from — nothing has been claimed, so there is nothing to un-claim, and
                    // both exits do the same thing for once.
                    onSkip: { model.isNamingSpecies = false },
                    onBack: { model.isNamingSpecies = false }
                )
            }
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
        case let .elsewhere(route):
            elsewhere(route)
        }
    }

    /// The record read for this screen belongs to another one (ERRATA E113).
    ///
    /// Nothing is drawn, and the router is asked to swap this screen for the right one *in place*,
    /// so `Back` returns to whatever pushed the profile rather than to the profile that should not
    /// have opened. A spinner is the honest thing to show for the frame it takes: the screen is
    /// still resolving where it goes.
    ///
    /// This is a routing call, not a feature constructing another feature's view — the distinction
    /// `MemorialView.notMemorial` and `SiteView.notASite` draw, and the reason they say what is true
    /// and stay put instead. They cannot redirect: both are *destinations*, reached deliberately by
    /// somebody who tapped a memorial pin or a site card, and a stale one is news. This screen is
    /// the opposite case — it is where six entrances land by default, and a vacant site arriving
    /// here is never news, it is the default being wrong.
    private func elsewhere(_ route: Route) -> some View {
        ProgressView()
            .task { router?.replace(.treeProfile(model.treeID), with: route) }
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

                if presentation.offersQuadActionRow {
                    // C8. Which cells this record may offer is the presentation's call
                    // (`quadActions`); which of them is *on* is the model's, and it is the store's
                    // answer rather than the last tap's (RULINGS R2, ERRATA E112).
                    //
                    // No longer behind `isCold` (ERRATA E127): a tree nobody has touched was
                    // offering no action at all, which is what SCREENS.md 14's "no quad-action row"
                    // delta shipped as. See `offersQuadActionRow` for the ruling and for why all
                    // four cells stay.
                    QuadActionRow(
                        actions: presentation.quadActions,
                        selected: model.isFavorite ? [.favorite] : []
                    ) { action in
                        perform(action)
                    }
                }

                if !presentation.isCold {
                    regularsRow(presentation)
                    activityFeed(presentation)
                }

                statGrid(presentation)

                if presentation.offersGrowthLink {
                    growthLink(presentation)
                }

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

    /// C2, and since E125 with an actual photograph in it.
    ///
    /// The gradient was always described as "a *placeholder for photography*" (SCREENS.md §2), and
    /// `HeroPhotoHeader` was built with a `background:` slot so swapping one in would be a one-line
    /// change at the call site. It was one line; what was missing was any way to get the bytes. See
    /// `PhotoAccess`.
    ///
    /// The whole hero is the tap target for screen 20. A photograph that leads a page is the natural
    /// place to ask "what else is there?", and it is where the answer changes: the browser is how a
    /// different photograph becomes this one (`PhotoHero`).
    private func hero(_ presentation: TreeProfilePresentation) -> some View {
        let style: HeroPhotoHeader<PhotoImage, EmptyView>.Style =
            colorScheme == .dark ? .profileDark : .profile
        return HeroPhotoHeader(
            style: style,
            metaPill: presentation.heroMetaPill,
            // D2 drops the `Best photo · Oct 2025` eyebrow.
            eyebrow: colorScheme == .dark ? nil : presentation.heroEyebrow,
            onBack: { router?.pop() },
            background: {
                PhotoImage(
                    photoID: presentation.bestPhoto?.id ?? Self.noPhoto,
                    placeholder: style.recipe
                )
            },
            bottomLeading: { EmptyView() }
        )
        // A tap anywhere on the photograph opens the set, *except* the back circle, which is a
        // button in an overlay and therefore gets the touch first.
        .contentShape(Rectangle())
        .onTapGesture { router?.push(.photos(model.treeID)) }
        // `children: .contain`, not `.combine` — the back circle lives inside this component, and
        // combining would swallow the one control that gets a listener off the screen.
        //
        // The label is not optional decoration. A trait without one produces exactly what
        // `DeepLinkVoiceOverTests` refuses to let ship: "a button at (0, 0, 393, 224) has no
        // accessibility label", announced as "button" and nothing else.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TreeProfilePresentation.heroLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(TreeProfilePresentation.heroHint)
    }

    /// The id used when there is no photograph to draw: it resolves to nothing, `PhotoImage` finds
    /// no bytes, and the gradient stays. A sentinel rather than an `if`, so the hero has one shape
    /// and the "no photo" case cannot drift into a differently-sized header.
    private static let noPhoto = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private var coldHeader: some View {
        ScreenHeader(title: TreeProfilePresentation.fallbackTitle, onBack: { router?.pop() })
    }

    /// 14 §2 — the dashed well, `height:170px`, radius 18, `2px dashed`, centred `VStack(spacing:8)`.
    ///
    /// **And a control, since ERRATA E127.** `LocationPrompt` (E123) established that a dashed-ring
    /// card in this vocabulary is tappable when a user action would fill it, and this is the app's
    /// clearest instance: a camera glyph in a dashed frame, drawn exactly when a photograph could be
    /// added. It calls the same `onVisit` the CTA beneath it calls, so the two say one thing.
    ///
    /// The `Button` wraps the composed well rather than replacing its accessibility work: the
    /// `.ignore` that fixed the doubled caption (E118) still holds, and the trait and hint are added
    /// on top of the one element it leaves.
    private var emptyPhotoWell: some View {
        Button { onVisit(model.treeID) } label: { emptyPhotoWellBody }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(TreeProfilePresentation.emptyPhotoWellHint)
    }

    private var emptyPhotoWellBody: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            ZStack {
                Circle().fill(CypressColor.cityRecordBadgeFill)
                TreeProfileCameraGlyph()
            }
            .frame(width: TreeProfileMetrics.emptyWellCircle, height: TreeProfileMetrics.emptyWellCircle)

            Text(TreeProfilePresentation.emptyPhotoWellText)
                .font(CypressFont.body13)
                .foregroundStyle(CypressColor.textFaint)
                .multilineTextAlignment(.center)
                // The sentence is 40-odd characters and fits on one line at the mock's size. At
                // AX1 it needs two and at AX5 four, and without this it would keep trying to take
                // the width it wants and be cut off by the well instead of wrapping inside it.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, CypressSpacing.gapCandidates)
        }
        .frame(maxWidth: .infinity)
        // One stop, not two (ERRATA E118). The well is a decorative circle, a camera glyph and a
        // caption; left alone, SwiftUI exposed the container *and* the caption inside it, both
        // carrying the same words, so VoiceOver read "No photos of this tree yet" and then read it
        // again. `.ignore` drops the descendants rather than merging them, which is right here
        // because the glyph is decoration in the same sense C16's tab icons are — it repeats the
        // sentence directly beneath it. Found by `testNothingIsAnnouncedTwice`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TreeProfilePresentation.emptyPhotoWellText)
        // `minHeight`, not `height`. 14 §2 draws `height:170px` and at the mock's type size that
        // is exactly what this renders; the difference only shows once the copy inside needs more
        // than 170 pt, at which point a fixed height clips the sentence and pushes the glyph
        // through the dashed border. The drawn size is a floor, not a cap.
        .frame(minHeight: TreeProfileMetrics.emptyWellHeight)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                .fill(CypressColor.surfaceEmptyThumb)
        }
        .cypressDashedBorder(
            CypressColor.borderDashedStrong,
            radius: CypressRadius.cardLg,
            width: CypressSpacing.Component.outlineWidth
        )
        // The 170pt card is mostly empty space around a 46pt circle and one line of text, and a
        // `Button` hit-tests the shape its label *draws*, not the frame the label was given. Without
        // this the only part of the well that answered a finger would be the glyph and the caption —
        // ERRATA E114's lesson from the other direction, where drawing and touch disagreed and the
        // accessibility tree could not tell.
        .contentShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, TreeProfileMetrics.wellTop)
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
        // The tree's name is a 27 pt serif and `StatusBadge` ends in `.fixedSize()`, so at AX5 the
        // badge took most of the row and `Grandmother Cypress` wrapped three characters at a time
        // down the left edge — the same failure C1's header had, from the same cause. The name is
        // the subject of the screen; below the size where both fit across, the badge goes under it.
        let name = Text(presentation.title)
            .font(presentation.isCold ? CypressFont.treeNameColdStart : CypressFont.treeNameHero)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)

        return VStack(alignment: .leading, spacing: TreeProfileMetrics.latinTop) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                    name.frame(maxWidth: .infinity, alignment: .leading)
                    if let badge = presentation.badge {
                        StatusBadge(badge)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: CypressSpacing.gapCandidates) {
                    name
                    if let badge = presentation.badge {
                        StatusBadge(badge)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text(presentation.subtitle)
                .cypressLatinName(presentation.isCold ? CypressFont.latinName145 : CypressFont.latinName)
                .fixedSize(horizontal: false, vertical: true)

            speciesClaim(presentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, presentation.isCold ? CypressSpacing.gutterLabel : CypressSpacing.gutter)
        .padding(.top, presentation.isCold ? TreeProfileMetrics.coldBlockGap : TreeProfileMetrics.blockGap)
    }

    /// The "after" half of "add tree species after/at same time as adding a custom tree".
    ///
    /// **It lives in the identity block, directly under the line it would change.** Not in C8's quad
    /// action row, which is four fixed cells this record either offers or does not (E127's ruling
    /// keeps all four), and not as a fifth stat card. The subtitle is where a species is *stated*, so
    /// the offer to state one belongs against it — and once it is stated the control is gone for good
    /// and the block goes back to the two lines SCREENS.md draws.
    ///
    /// A refusal draws under the control rather than replacing it: `claimSpecies` reloads, so the
    /// sentence sits beside a screen that is showing what is actually stored.
    @ViewBuilder
    private func speciesClaim(_ presentation: TreeProfilePresentation) -> some View {
        if presentation.offersSpeciesClaim {
            Button { model.isNamingSpecies = true } label: {
                Text(TreeProfileCopy.claimSpeciesAction)
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.ctaFill)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .cypressHitArea()
        }
        if let failure = model.speciesClaimFailure {
            Text(failure)
                .cypressBody135(color: CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                // The bubbles and the headline are the same fact twice — with no initials to draw
                // (E71) the stack is one `+6` bubble beside the words "Six people know this tree".
                // The sentence wins; the bubbles are the picture of it.
                .accessibilityHidden(true)
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
        // 03 §9's trailing `30px` closes the screen, so it moves below whatever is genuinely last:
        // the growth link when there is one, this grid when there is not.
        .padding(.bottom, presentation.isCold || presentation.offersGrowthLink ? 0 : CypressSpacing.bottomBar)
    }

    // MARK: - 9b · Growth history link (screen 11)

    /// Screen 11's entrance, said out loud. See `TreeProfilePresentation.offersGrowthLink` for why a
    /// stat card carrying a reading was not enough of one (ERRATA E127).
    ///
    /// Built exactly like `activityLink`, and for the same reason: C1–C30 is a closed catalogue with
    /// no link in it, and a screen-local control from tokens is what this codebase does where the
    /// catalogue has no entry (ERRATA E46). Same font, same colour, same 44pt hit area — it is the
    /// same kind of thing one block further down the screen, so it reads as one.
    private func growthLink(_ presentation: TreeProfilePresentation) -> some View {
        Button {
            router?.push(.growthHistory(model.treeID))
        } label: {
            Text(TreeProfilePresentation.growthLinkTitle)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, TreeProfileMetrics.activityLinkTop)
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
        // The only cell of the four that changes this screen rather than opening another one. The
        // model owns what "the other state" is, because it is the one thing here that knows what is
        // stored (R2).
        case .favorite: model.toggleFavorite()
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
