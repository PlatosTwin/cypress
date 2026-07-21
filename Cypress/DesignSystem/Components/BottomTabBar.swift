//
//  BottomTabBar.swift
//  Cypress — DesignSystem/Components
//
//  C16 · `BottomTabBar` — SCREENS.md §2. Four tabs, hand-drawn icons, no icon font.
//  Labels verbatim: `Map`, `My Grove`, `Journal`, `You`.
//
//  Each tab is a full-height quarter of the bar — well over 44pt — so no hit-area growth is needed.
//

import SwiftUI

struct BottomTabBar: View {

    enum Tab: String, CaseIterable, Identifiable {
        case map
        case myGrove
        case journal
        case you

        var id: String { rawValue }

        /// Verbatim from §2.
        var label: String {
            switch self {
            case .map: return "Map"
            case .myGrove: return "My Grove"
            case .journal: return "Journal"
            case .you: return "You"
            }
        }
    }

    @Binding var selection: Tab
    /// 08 drops the backdrop blur and keeps the top hairline only.
    var usesBlur: Bool = true
    /// The initial in the `You` avatar. `N` on every drawn screen.
    var avatarInitial: String = "N"

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    tabContent(tab)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, CypressSpacing.Component.tabBarPaddingTop)
        .padding(.horizontal, CypressSpacing.Component.tabBarPaddingH)
        .padding(.bottom, CypressSpacing.Component.tabBarPaddingBottom)
        .background {
            if usesBlur {
                CypressColor.tabBarFill.background(.ultraThinMaterial)
            } else {
                CypressColor.tabBarFill
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CypressColor.tabBarTopBorder)
                .frame(height: CypressSpacing.Component.hairline)
        }
    }

    private func tabContent(_ tab: Tab) -> some View {
        let isActive = tab == selection
        let tint = isActive ? CypressColor.tabActive : CypressColor.textFaint
        return VStack(spacing: CypressSpacing.Component.tabIconLabelGap) {
            icon(tab, tint: tint)
            Text(tab.label)
                .font(isActive ? CypressFont.body11ExtraBold : CypressFont.body11SemiBold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(_ tab: Tab, tint: Color) -> some View {
        switch tab {
        case .map:
            // 22×22 rounded square, 2px border, centred 6×6 dot.
            RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
                .strokeBorder(tint, lineWidth: CypressSpacing.Component.tabIconStroke)
                .overlay {
                    Circle()
                        .fill(tint)
                        .frame(
                            width: CypressSpacing.Component.tabIconMapDot,
                            height: CypressSpacing.Component.tabIconMapDot
                        )
                }
                .frame(
                    width: CypressSpacing.Component.tabIconMap,
                    height: CypressSpacing.Component.tabIconMap
                )
        case .myGrove:
            LeafGlyph(size: CypressSpacing.Component.tabIconLeaf, tint: tint)
        case .journal:
            // 18×20 book: 2px border, radius `3px 6px 6px 3px`, 2px spine bar at left:3.
            UnevenRoundedRectangle(
                topLeadingRadius: 3,
                bottomLeadingRadius: 3,
                bottomTrailingRadius: CypressRadius.badge,
                topTrailingRadius: CypressRadius.badge,
                style: .continuous
            )
            .strokeBorder(tint, lineWidth: CypressSpacing.Component.tabIconStroke)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(tint)
                    .frame(width: CypressSpacing.Component.tabIconStroke)
                    .padding(.leading, CypressSpacing.Component.tabIconBookSpineInset)
            }
            .frame(
                width: CypressSpacing.Component.tabIconBookWidth,
                height: CypressSpacing.Component.tabIconBookHeight
            )
        case .you:
            Circle()
                .fill(CypressColor.canopy)
                .overlay {
                    Text(avatarInitial)
                        .font(CypressFont.body105ExtraBold)
                        .foregroundStyle(CypressColor.tabAvatarLetter)
                }
                .frame(
                    width: CypressSpacing.Component.tabIconAvatar,
                    height: CypressSpacing.Component.tabIconAvatar
                )
        }
    }
}
