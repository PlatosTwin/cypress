//
//  Buttons.swift
//  Cypress — DesignSystem/Components
//
//  C6 · `PrimaryButton` and C7 · `SecondaryOutlineButton` — SCREENS.md §2.
//
//  Both are full-width and already well above the 44pt minimum at every documented size
//  (13pt padding + a 14.5pt label ≈ 45pt), so neither needs a hit-area expansion.
//
//  **NOT SPECIFIED** (SCREENS.md §5 gap 2): pressed, disabled and focus states. The README
//  describes a `#1D4634`→`#2F6B4F` darken on press but the spec file does not, so no pressed
//  styling is invented here beyond SwiftUI's default opacity on `.plain`.
//

import SwiftUI

// MARK: - C6 · PrimaryButton

struct PrimaryButton: View {

    enum Style: String, CaseIterable, Identifiable {
        /// `padding:15px`, 16px/700, radius 14, `shadow.primary`. The default (02, 03, 05, 09, 14, 16).
        case standard
        /// 12 "Walk the nine" — `padding:13px`, 14.5px, radius 12, **no shadow**.
        case compact
        /// 18 "Next nearest…" — `padding:16px`.
        case large
        /// 04 — fill New Growth `#4E8F6A`, label `#0E1A12`, weight 800, no shadow.
        case camera

        var id: String { rawValue }

        var padding: CGFloat {
            switch self {
            case .standard, .camera: return CypressSpacing.Component.buttonPadding
            case .compact: return CypressSpacing.Component.buttonPaddingSmall
            case .large: return CypressSpacing.Component.buttonPaddingLarge
            }
        }

        var radius: CGFloat {
            switch self {
            case .compact: return CypressRadius.control
            case .standard, .large, .camera: return CypressRadius.cardSm
            }
        }

        var fill: Color {
            self == .camera ? CypressColor.ctaCameraFill : CypressColor.ctaFill
        }

        var label: Color {
            self == .camera ? CypressColor.ctaCameraLabel : CypressColor.ctaLabel
        }

        /// Dark (D2, D3) and 04 both raise the weight to 800; light stays at 700.
        func font(forcedDarkWeight: Bool) -> Font {
            switch self {
            case .standard, .large:
                return forcedDarkWeight ? CypressFont.body16ExtraBold : CypressFont.body16
            case .compact:
                return forcedDarkWeight ? CypressFont.body145ExtraBold : CypressFont.body145Bold
            case .camera:
                return CypressFont.body16ExtraBold
            }
        }

        /// `shadow.primary` in light on the standard sizes only. Dark and 04 carry none.
        var shadow: CypressShadowStyle? {
            switch self {
            case .standard, .large: return CypressShadow.primary
            case .compact, .camera: return nil
            }
        }
    }

    let title: String
    var style: Style = .standard
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, style: Style = .standard, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style.font(forcedDarkWeight: colorScheme == .dark || style == .camera))
                .foregroundStyle(style.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, style.padding)
                .padding(.horizontal, style.padding)
                .background {
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .fill(style.fill)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressShadow(light: style.shadow, dark: nil)
    }
}

// MARK: - C7 · SecondaryOutlineButton

struct SecondaryOutlineButton: View {

    enum Style: String, CaseIterable, Identifiable {
        /// 02, 18 — `padding:14px`, 15px.
        case standard
        /// 06 — `padding:13px`, 14.5px.
        case compact

        var id: String { rawValue }

        var padding: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.buttonPaddingMedium
            case .compact: return CypressSpacing.Component.buttonPaddingSmall
            }
        }

        var font: Font {
            switch self {
            case .standard: return CypressFont.body15Bold
            case .compact: return CypressFont.body145Bold
            }
        }
    }

    let title: String
    var style: Style = .standard
    let action: () -> Void

    init(_ title: String, style: Style = .standard, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(style.font)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity)
                .padding(.vertical, style.padding)
                .padding(.horizontal, style.padding)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .strokeBorder(
                            CypressColor.ctaFill,
                            lineWidth: CypressSpacing.Component.outlineWidth
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
