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
//  docs/rulings-pending/share-destinations.md. The `ScrollView` is also the keyboard mechanism:
//  a focused text field inside it is scrolled clear of the keyboard by the system, provided the
//  *presenting view does not opt out of the keyboard safe area* — so a screen hosting this shell
//  must use `.ignoresSafeArea(.container)`, never bare `.ignoresSafeArea()`, which silently
//  includes `.keyboard` and lets the keyboard cover the field being typed into.
//  `.account` (15) keeps its content-sized card: it is a short ask with no text input, and its
//  mock is a card, not a page.
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
    var onScrimTap: (() -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for exactly one frame — the first — so `czSheet` has a keyframe at 0 % to move from.
    @State private var hasRisen = false

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
            // A full-height card is still a *sheet*: a strip of scrim stays visible above it, the
            // same 62pt the skeleton reserves for the status bar, so the grabber never sits under
            // the clock and the card reads as presented rather than as a screen swap.
            .padding(.top, style.fillsHeight ? CypressSpacing.Device.statusBarInset : 0)
            // czSheet — the sheet rises 90 pt on the overshoot curve. `CypressMotion.sheet`.
            .offset(y: settled ? 0 : CypressMotionOffset.sheetRise)
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
