//
//  LeafGlyph.swift
//  Cypress — DesignSystem/Components
//
//  C21 · `LeafGlyph` — SCREENS.md §2. "The app's only bespoke mark: a square with
//  `border-radius: 50% 0` rotated 45°."
//
//  The geometry already lives in `CypressLeafGlyph` (CypressRadius.swift). This is the tinted,
//  correctly-sized view around it, plus the four drawn sizes as named cases so a call site never
//  types a number.
//

import SwiftUI

struct LeafGlyph: View {

    /// The four sizes §2 records.
    enum Size: String, CaseIterable, Identifiable {
        /// 16pt — the `My Grove` tab icon.
        case tabBar
        /// 14pt — the 01 FAB.
        case fab
        /// 12pt — the care thumbnail on 03.
        case careThumb
        /// 10pt — the recognize-it bullets on 07.
        case bullet

        var id: String { rawValue }

        var value: CGFloat {
            switch self {
            case .tabBar: return CypressSpacing.Component.leafTabBar
            case .fab: return CypressSpacing.Component.leafFAB
            case .careThumb: return CypressSpacing.Component.leafCareThumb
            case .bullet: return CypressSpacing.Component.leafBullet
            }
        }
    }

    let side: CGFloat
    var tint: Color = CypressColor.canopy

    init(_ size: Size, tint: Color = CypressColor.canopy) {
        self.side = size.value
        self.tint = tint
    }

    init(size: CGFloat, tint: Color = CypressColor.canopy) {
        self.side = size
        self.tint = tint
    }

    var body: some View {
        CypressLeafGlyph()
            .fill(tint)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
