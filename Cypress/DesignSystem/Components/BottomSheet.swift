//
//  BottomSheet.swift
//  Cypress — DesignSystem/Components
//
//  C17 · `BottomSheet` — SCREENS.md §2. The care log (09), share (10) and account ask (15).
//
//  This is the *presentation shell* the mocks draw: scrim, 26pt top corners, grabber, `shadow.sheet`.
//  It is not `.sheet(isPresented:)` — 09/10 draw a skeleton of the profile behind the scrim rather
//  than the live profile, which a system sheet cannot do. `ProfileSkeleton` reproduces it.
//
//  ── Height (ticket #146) ───────────────────────────────────────────────────────────────────
//  `.standard` sheets are **full-height**: the card runs from just under the status bar to the
//  bottom of the display, with the content top-aligned inside a `ScrollView`. The mocks drew 09/10
//  as content-sized bottom cards; the owner overrode that on device ("half-screened") — see
//  RULINGS R39. The `ScrollView` is also the keyboard mechanism:
//  a focused text field inside it is scrolled clear of the keyboard by the system, provided the
//  *presenting view does not opt out of the keyboard safe area* — so a screen hosting this shell
//  must use `.ignoresSafeArea(.container)`, never bare `.ignoresSafeArea()`, which silently
//  includes `.keyboard` and lets the keyboard cover the field being typed into.
//  `.account` (15) keeps its content-sized card: it is a short ask with no text input, and its
//  mock is a card, not a page.
//
//  ── Exits (ticket #175) ────────────────────────────────────────────────────────────────────
//  09 and 10 draw no close button, so this shell owns every way out. A full-height card leaves
//  only the 62pt status-bar strip of scrim exposed, and on a Dynamic Island device the system's
//  own status-bar hit region consumes roughly the top 54pt of it — measured on an iPhone 16 Pro
//  simulator: taps at y=30/45 never reach the app, taps at y=58 do — which left the wired,
//  working scrim tap an ~8pt sliver nobody hits on purpose. The primary exit is therefore the
//  drag the grabber was always promising: a full-width handle band across the top of the card
//  (`sheetDragZone`) drags it down, `SheetDismissRule` decides commit-or-spring-back, and the
//  scrim tap stays for the sliver and for VoiceOver's named "Dismiss" element. See
//  docs/rulings-pending/sheet-exits.md.
//

import SwiftUI

struct BottomSheet<Content: View>: View {

    enum Style {
        /// 09, 10 — `padding:10px 18px 44px`, grabber present, scrim `.44`.
        case standard
        /// 15 — `padding:22px 20px 44px`, **no grabber**, scrim `.3`.
        case account

        var paddingTop: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.sheetPaddingTop
            case .account: return CypressSpacing.Component.sheetPaddingTopAccount
            }
        }

        var paddingHorizontal: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.sheetPaddingH
            case .account: return CypressSpacing.Component.sheetPaddingHAccount
            }
        }

        var showsGrabber: Bool { self == .standard }

        /// Whether the card fills the display height (see the file header). `.standard` does;
        /// `.account` stays the content-sized card its mock draws.
        var fillsHeight: Bool { self == .standard }

        var scrim: Color {
            switch self {
            case .standard: return CypressColor.sheetScrim
            case .account: return CypressColor.sheetScrimSoft
            }
        }
    }

    var style: Style = .standard
    /// The dismissal, owned by the host. The name records its first wiring; since ticket #175 it
    /// is also where the drag handle's dismiss lands — one closure, however the sheet is left.
    var onScrimTap: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for exactly one frame — the first — so `czSheet` has a keyframe at 0 % to move from.
    @State private var hasRisen = false
    /// How far the drag handle currently holds the card below its resting place (ticket #175).
    @State private var dragOffset: CGFloat = 0
    /// The card's measured height — what `SheetDismissRule` judges a released drag against.
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            style.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onScrimTap?() }
                // The scrim is the ground the sheet arrives over, so it fades on `czFade` while
                // the sheet itself rises on `czSheet` — the prototype's own pairing (its 09/10/15
                // scrims carry `czFade`, its sheets `czSheet`).
                .opacity(settled ? 1 : 0)
                // The scrim is the only way out of 09 and 10 — neither draws a close button — so
                // it is a control, not decoration, and it says what tapping it does. A plain
                // `onTapGesture` on a `Color` gives VoiceOver a focusable region with no name.
                .accessibilityElement()
                .accessibilityHidden(onScrimTap == nil)
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                if style.showsGrabber {
                    Capsule()
                        .fill(CypressColor.borderSheetGrabber)
                        .frame(
                            width: CypressSpacing.Component.grabberWidth,
                            height: CypressSpacing.Component.grabberHeight
                        )
                        .padding(.top, CypressSpacing.Component.grabberTop)
                        .padding(.bottom, CypressSpacing.Component.grabberBottom)
                        .accessibilityHidden(true)
                }
                if style.fillsHeight {
                    // The scroll view is load-bearing twice over: it lets content shorter than the
                    // card sit at the top of a full-height page, and it is what moves a focused
                    // text field clear of the keyboard (see the file header).
                    ScrollView {
                        paddedContent
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    paddedContent
                }
            }
            .padding(.top, style.paddingTop)
            .frame(
                maxWidth: .infinity,
                maxHeight: style.fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            // The *fill* runs to the bottom of the display; the content does not move. §2 pins the
            // sheet to the bottom, and the mock's own 44pt bottom padding is what holds it clear of
            // the home indicator — so extending the whole view into the safe area would spend that
            // padding twice and leave the CTA sitting on the indicator. Only the background crosses.
            .background {
                CypressSheetShape()
                    .fill(CypressColor.surfaceSheet)
                    .ignoresSafeArea(edges: .bottom)
            }
            .cypressShadow(CypressShadow.sheet)
            // The grabber's promise, kept (ticket #175): a full-width band across the top of the
            // card — grabber row and title line — drags the sheet down and out. The band is an
            // overlay rather than a gesture on the card so the interior `ScrollView` keeps every
            // drag below it: scrolling, and the keyboard mechanism the file header describes,
            // are untouched. It exists only where the grabber that promises it exists, and only
            // when there is a dismissal to deliver.
            .overlay(alignment: .top) {
                if style.showsGrabber, onScrimTap != nil {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: CypressSpacing.Component.sheetDragZone)
                        .contentShape(Rectangle())
                        .gesture(dragToDismiss)
                        // The band is a hand-hold, not an element: VoiceOver leaves by the scrim's
                        // named "Dismiss" control, which activation reaches without hit-testing.
                        .accessibilityHidden(true)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            // A full-height card is still a *sheet*: a strip of scrim stays visible above it, the
            // same 62pt the skeleton reserves for the status bar, so the grabber never sits under
            // the clock and the card reads as presented rather than as a screen swap.
            .padding(.top, style.fillsHeight ? CypressSpacing.Device.statusBarInset : 0)
            // czSheet — the sheet rises 90 pt on the overshoot curve. `CypressMotion.sheet`.
            // Once risen, the offset is the drag handle's: the card follows the finger down.
            .offset(y: settled ? dragOffset : CypressMotionOffset.sheetRise)
            .opacity(settled ? 1 : 0)
        }
        .onAppear {
            // One `withAnimation` drives both the scrim's fade and the sheet's rise off the same
            // flag, so they cannot drift apart. Under Reduce Motion `resolved` returns nil and the
            // sheet is simply drawn where it belongs — which is the whole state change; the
            // animation was never carrying any of it.
            withAnimation(CypressMotion.resolved(CypressMotion.sheet, reduceMotion: reduceMotion)) {
                hasRisen = true
            }
        }
    }

    private var settled: Bool { hasRisen || reduceMotion }

    /// The handle's gesture. Following the finger is direct manipulation — the state *is* the
    /// finger's position — so Reduce Motion does not switch it off; what it switches off is the
    /// decorative spring back to rest, exactly as `CypressMotion.resolved` always has.
    /// The decision at release is `SheetDismissRule`'s, where it is arithmetic and tested.
    private var dragToDismiss: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                dragOffset = SheetDismissRule.cardOffset(forTranslation: value.translation.height)
            }
            .onEnded { value in
                if SheetDismissRule.shouldDismiss(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    cardHeight: cardHeight
                ) {
                    onScrimTap?()
                } else {
                    withAnimation(
                        CypressMotion.resolved(CypressMotion.sheet, reduceMotion: reduceMotion)
                    ) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// The mock's own margins — `18px` sides, `44px` bottom — applied to the content rather than
    /// the card, so that inside a `ScrollView` they scroll with it and the scroll indicator hugs
    /// the card's edge.
    private var paddedContent: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, style.paddingHorizontal)
            .padding(.bottom, CypressSpacing.bottomSheet)
    }
}

/// The skeleton the 09/10 sheets sit on: `padding:62px 16px 0`, `gap:10px`; a 150pt gradient hero,
/// then 24×64% and 14×44% bars, then 52pt blocks (three on 09, two on 10).
///
/// It exists because §2 is explicit that what is behind those sheets is *not* the live profile.
struct ProfileSkeleton: View {
    var blockCount: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapCandidates) {
            CypressGradientField(CypressGradient.heroProfile)
                .frame(height: CypressSpacing.Component.skeletonHero)
                .cypressCornerRadius(CypressRadius.cardMd)

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: CypressSpacing.gapCandidates) {
                    bar(
                        width: proxy.size.width * CypressSpacing.Component.skeletonBarLargeFraction,
                        height: CypressSpacing.Component.skeletonBarLarge,
                        radius: CypressRadius.thumbXs
                    )
                    bar(
                        width: proxy.size.width * CypressSpacing.Component.skeletonBarSmallFraction,
                        height: CypressSpacing.Component.skeletonBarSmall,
                        radius: CypressRadius.skeletonBarSmall
                    )
                }
            }
            .frame(
                height: CypressSpacing.Component.skeletonBarLarge
                    + CypressSpacing.Component.skeletonBarSmall
                    + CypressSpacing.gapCandidates
            )

            ForEach(0..<max(0, blockCount), id: \.self) { _ in
                bar(
                    width: nil,
                    height: CypressSpacing.Component.skeletonBlock,
                    radius: CypressRadius.control
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, CypressSpacing.Device.statusBarInset)
        .padding(.horizontal, CypressSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(CypressColor.surfaceSkeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
