//
//  ThumbnailGradient.swift
//  Cypress — DesignSystem/Components
//
//  C22 · `ThumbnailGradient` — SCREENS.md §2. "Every tree image is a stack of radial-gradient
//  layers over a linear base, with `border:1px solid rgba(29,70,52,.14)`."
//
//  The recipes are tokens (`CypressGradient.Thumbnail`); this is the framed, bordered, correctly
//  rounded view around one. When real photography arrives it takes the same frame — pass a
//  different `content`.
//
//  ── Tap targets ───────────────────────────────────────────────────────────────────────────
//  The drawn thumbs run 34–76pt. A thumbnail that is *itself* the control (rather than sitting
//  inside a full-width row that is already tappable) keeps its drawn size and takes a 44pt hit
//  area — pass `action:`.
//

import SwiftUI

struct ThumbnailGradient<Content: View>: View {

    /// The drawn sizes, each with the radius §1.4 pairs it with.
    enum Size: String, CaseIterable, Identifiable {
        /// 02 top candidate — 76pt, `radius.thumb.lg`.
        case candidate
        /// 10 share preview — 72pt, `radius.thumb.lg`.
        case share
        /// 02 row — 60pt, `radius.thumb.md`.
        case candidateRow
        /// 01 card — 58pt, `radius.thumb.md`.
        case mapCard
        /// 07 nearby individuals — 44pt, `radius.thumb.sm`.
        case nearby
        /// C9 activity — 38pt, `radius.thumb.sm` (10).
        case activity
        /// C10 almanac tile — 34pt, `radius.thumb.sm` (10).
        case almanac

        var id: String { rawValue }

        var side: CGFloat {
            switch self {
            case .candidate: return CypressSpacing.Component.thumb76
            case .share: return CypressSpacing.Component.thumb72
            case .candidateRow: return CypressSpacing.Component.thumb60
            case .mapCard: return CypressSpacing.Component.thumb58
            case .nearby: return CypressSpacing.Component.thumb44
            case .activity: return CypressSpacing.Component.thumb38
            case .almanac: return CypressSpacing.Component.thumb34
            }
        }

        var radius: CGFloat {
            switch self {
            case .candidate, .share: return CypressRadius.thumbLg
            case .candidateRow, .mapCard: return CypressRadius.thumbMd
            case .nearby: return CypressRadius.thumbSm
            case .activity, .almanac: return CypressRadius.thumbSmAlt
            }
        }
    }

    let size: Size
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        if let action {
            Button(action: action) { thumb }
                .buttonStyle(.plain)
                .cypressHitArea()
        } else {
            thumb
        }
    }

    private var thumb: some View {
        content
            .frame(width: size.side, height: size.side)
            .cypressCornerRadius(size.radius)
            .cypressBorder(CypressColor.borderPinRing, radius: size.radius)
            .contentShape(RoundedRectangle(cornerRadius: size.radius, style: .continuous))
    }
}

extension ThumbnailGradient where Content == CypressGradientField {
    /// The placeholder thumbnail: one of the four canonical species gradient sets.
    init(_ thumbnail: CypressGradient.Thumbnail, size: Size, action: (() -> Void)? = nil) {
        self.init(size: size, action: action) { CypressGradientField(thumbnail.recipe) }
    }

    /// Any recipe — the activity thumbs, the 13 photo strip, a hero re-used small.
    init(recipe: CypressGradientRecipe, size: Size, action: (() -> Void)? = nil) {
        self.init(size: size, action: action) { CypressGradientField(recipe) }
    }
}
