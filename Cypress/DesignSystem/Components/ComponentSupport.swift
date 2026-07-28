//
//  ComponentSupport.swift
//  Cypress — DesignSystem/Components
//
//  Shared plumbing for the C1–C30 catalogue: forced-dark surfaces, the tap-target rule, the two
//  hand-drawn glyph shapes the catalogue keeps re-using, and the border helpers.
//
//  Nothing here invents a value. Sizes come from `CypressSpacing.Component`, colours from
//  `CypressColor`, radii from `CypressRadius`.
//

import SwiftUI

// MARK: - Forced dark

/// Screens 04 and D1–D3 are dark *regardless of the system setting* (ARCHITECTURE §6).
///
/// `.automatic` resolves off the environment, which is what every ordinary screen wants: the
/// tokens are trait-resolving pairs. `.forcedDark` pins the environment scheme to dark for a
/// subtree, so the same token code produces the documented dark values on a light device.
enum CypressAppearance: String, CaseIterable, Identifiable {
    case automatic
    case forcedDark

    var id: String { rawValue }
}

extension View {
    /// Applies a `CypressAppearance` to this subtree.
    @ViewBuilder
    func cypressAppearance(_ appearance: CypressAppearance) -> some View {
        switch appearance {
        case .automatic:
            self
        case .forcedDark:
            environment(\.colorScheme, .dark)
        }
    }

    /// Pins this subtree to the dark palette — screen 04 and D1–D3.
    func cypressForcedDark() -> some View {
        cypressAppearance(.forcedDark)
    }
}

// MARK: - Tap targets

extension View {
    /// Grows the *hit area* to at least `size` × `size` without changing the laid-out size.
    ///
    /// ARCHITECTURE §6 and SCREENS.md §5 gap 12: "where the mock and accessibility disagree, the
    /// target grows and the *visual* stays put via `contentShape`." `CypressSpacing.cypressTapTarget()`
    /// grows the layout box, which is right for a standalone button; this one is for the many places
    /// in §2 where the drawn pill, pin or thumbnail must keep its exact size inside a row.
    ///
    /// The clear background is a real, hit-testable view that overflows its parent's bounds; it is
    /// not clipped, so the extra area is live.
    func cypressHitArea(_ size: CGFloat = CypressSpacing.minTapTarget) -> some View {
        background(alignment: .center) {
            Color.clear
                .frame(minWidth: size, minHeight: size)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Borders

extension View {
    /// A 1pt (or `width`pt) token border on a Cypress radius, drawn inside the bounds.
    func cypressBorder(
        _ color: Color,
        radius: CGFloat,
        width: CGFloat = CypressSpacing.Component.hairline
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        }
    }

    /// A pill border (`radius.pill`).
    func cypressPillBorder(
        _ color: Color,
        width: CGFloat = CypressSpacing.Component.hairline
    ) -> some View {
        overlay {
            Capsule().strokeBorder(color, lineWidth: width)
        }
    }

    /// The dashed well border of C14 (dashed) and C15.
    ///
    /// **NOT SPECIFIED:** SCREENS.md gives `1px dashed <color>` but no dash pattern. 4-on/3-off is
    /// used throughout, chosen once here so every dashed edge in the app matches.
    func cypressDashedBorder(
        _ color: Color = CypressColor.borderDashed,
        radius: CGFloat = CypressRadius.control,
        width: CGFloat = CypressSpacing.Component.hairline
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    color,
                    style: StrokeStyle(lineWidth: width, dash: CypressDash.pattern)
                )
        }
    }
}

/// The one dashed pattern in the app. See `cypressDashedBorder`.
enum CypressDash {
    static let pattern: [CGFloat] = [4, 3]
    /// C19's `2.5px dashed` community pin ring. Tighter than `pattern`, because an 18pt circle
    /// only fits a few dashes before it stops reading as a ring. Also **NOT SPECIFIED**.
    static let pinRing: [CGFloat] = [2.5, 2]
}

// MARK: - Glyphs

/// C1's back chevron — SVG `M8 2L2 8l6 6` in a 10×16 viewBox, round caps and joins.
/// `direction: .trailing` mirrors it into the `M1 1l6 6-6 6` chevron the 01 tree card uses.
struct CypressChevron: Shape {
    enum Direction { case leading, trailing }

    var direction: Direction = .leading

    func path(in rect: CGRect) -> Path {
        // The source viewBox is 10 wide × 16 tall; the stroke sits inset by 2 on the x axis.
        var path = Path()
        let inset = rect.width * 0.2
        let top = CGPoint(x: rect.maxX - inset, y: rect.minY + rect.height * 0.125)
        let mid = CGPoint(x: rect.minX + inset, y: rect.midY)
        let bottom = CGPoint(x: rect.maxX - inset, y: rect.maxY - rect.height * 0.125)
        path.move(to: top)
        path.addLine(to: mid)
        path.addLine(to: bottom)
        if direction == .trailing {
            return path.applying(
                CGAffineTransform(translationX: rect.midX, y: 0)
                    .scaledBy(x: -1, y: 1)
                    .translatedBy(x: -rect.midX, y: 0)
            )
        }
        return path
    }
}

/// The check used by the 18 success circle (`M2 12l8 8L26 2`), the 19-selected vitality row and the
/// route-done pin (`M1 5l3.5 3.5L11 1`). One shape, drawn in a unit box and scaled by the caller.
struct CypressCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// C20's search glyph — `circle cx=7 cy=7 r=5` plus `line 11,11 → 15,15`, stroke width 1.8.
struct CypressSearchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Drawn in the source's 16×16 box, then scaled to `rect`.
        let scale = min(rect.width, rect.height) / 16
        var path = Path()
        path.addEllipse(
            in: CGRect(x: 2 * scale, y: 2 * scale, width: 10 * scale, height: 10 * scale)
        )
        path.move(to: CGPoint(x: 11 * scale, y: 11 * scale))
        path.addLine(to: CGPoint(x: 15 * scale, y: 15 * scale))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// C20's clear mark — a ring the size of the search glyph's circle with an ✕ inside it, drawn at the
/// same 1.8 stroke so the bar carries the same line weight at both ends.
///
/// **NOT SPECIFIED.** SCREENS.md §2 draws C20 with one glyph, the leading magnifier, and screen 01
/// lists nothing else in the bar; `docs/RULINGS.md` R15 is where the decision to add this one is
/// recorded and reasoned. Hand-drawn like every other mark in the app — there are no SF Symbols and
/// no icon font here (§2 C16, and `ShareDestinationGlyph` for the statement of the policy).
///
/// The ring is what makes it read as a control rather than as punctuation: an unringed ✕ at 16 pt
/// beside a 14.5 pt field is the same weight as a letter.
struct CypressClearGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Drawn in the same 16×16 box as `CypressSearchGlyph`, then scaled to `rect`.
        let scale = min(rect.width, rect.height) / 16
        var path = Path()
        // The ring: r=7 centred, inset by half the stroke so the outer edge lands on the box.
        path.addEllipse(
            in: CGRect(x: 1 * scale, y: 1 * scale, width: 14 * scale, height: 14 * scale)
        )
        // The ✕, inset far enough not to touch the ring.
        path.move(to: CGPoint(x: 5.5 * scale, y: 5.5 * scale))
        path.addLine(to: CGPoint(x: 10.5 * scale, y: 10.5 * scale))
        path.move(to: CGPoint(x: 10.5 * scale, y: 5.5 * scale))
        path.addLine(to: CGPoint(x: 5.5 * scale, y: 10.5 * scale))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

// MARK: - Text composition

/// The `<b>lead-in</b> rest of the sentence` pattern used by C9 and C14.
///
/// Kept as one helper so the em-dash and middle-dot copy rules of ARCHITECTURE §5.7 have a single
/// place to be respected: the separator is passed in verbatim, never assembled from spaces here.
func cypressLeadInText(
    _ leadIn: String,
    _ rest: String,
    leadInFont: Font,
    restFont: Font,
    leadInColor: Color,
    restColor: Color
) -> Text {
    Text(leadIn).font(leadInFont).foregroundColor(leadInColor)
        + Text(rest).font(restFont).foregroundColor(restColor)
}
