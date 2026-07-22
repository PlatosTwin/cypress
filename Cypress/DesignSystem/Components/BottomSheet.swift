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

    var body: some View {
        ZStack(alignment: .bottom) {
            style.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onScrimTap?() }

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
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, style.paddingTop)
            .padding(.horizontal, style.paddingHorizontal)
            .padding(.bottom, CypressSpacing.bottomSheet)
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
        }
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
