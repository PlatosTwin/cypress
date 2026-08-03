//
//  ProgressRing.swift
//  Cypress — DesignSystem/Components
//
//  C27 · `ProgressRing` (08) and C28 · `ConfidenceBar` (02) — SCREENS.md §2.
//
//  D1 guard: the ring on 08 tracks *species you can recognize*, which is knowledge, not a count of
//  actions — "There are no leaderboards" is printed on the same screen. `ProgressRing` therefore
//  takes a fraction and a caption, never a running total of visits, photos or care events.
//

import SwiftUI

struct ProgressRing: View {
    /// 0…1. Drawn as `conic-gradient(#2F6B4F 0 30%, #E0E6D8 30% 100%)`.
    let fraction: Double
    /// The label inside the disc. `30%` on 08.
    var label: String?
    /// What the ring says instead of what it looks like.
    ///
    /// A ring is a visual encoding of one number, and the number is already inside it — so the
    /// default spoken form is that number as a sentence rather than as a glyph. The parameter
    /// exists because the ring on 08 sits beside prose that says the same thing better ("12 of 40
    /// species you can recognize in the Outer Sunset"), and a caller that has that sentence should
    /// hand it over or hide the ring rather than have VoiceOver read the fraction twice.
    var spokenLabel: String?

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    // `selectionFill` and `ctaFill` rather than the raw `canopy` / `cypressDeep`
                    // hues. The six brand colors are `lightOnly` by design — CypressColor's own
                    // header says their scheme-dependent roles are carried by the paired role
                    // tokens — and reaching past them left the ring drawing `#2F6B4F` on `#0E1712`
                    // in the dark, with its `#1D4634` label all but invisible inside it. Both pairs
                    // are documented (§1.2 dark table: mint is "primary CTA fill, selection"), so
                    // the light rendering is unchanged to the byte and nothing here is invented.
                    // See ERRATA E50.
                    gradient: Gradient(stops: [
                        .init(color: CypressColor.selectionFill, location: 0),
                        .init(color: CypressColor.selectionFill, location: clamped),
                        .init(color: CypressColor.progressRingTrack, location: clamped),
                        .init(color: CypressColor.progressRingTrack, location: 1),
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                )
            )
            .overlay {
                Circle()
                    .fill(CypressColor.progressRingInner)
                    .overlay {
                        if let label {
                            Text(label)
                                .font(CypressFont.mono14SemiBold)
                                .foregroundStyle(CypressColor.ctaFill)
                        }
                    }
                    .frame(
                        width: CypressSpacing.Component.progressRingInner,
                        height: CypressSpacing.Component.progressRingInner
                    )
            }
            .frame(
                width: CypressSpacing.Component.progressRing,
                height: CypressSpacing.Component.progressRing
            )
            .accessibilityElement(children: .ignore)
            // One phrasing for both paths. It used to be `label ?? "N percent"`, which read the
            // glyph `30%` when a label was supplied and the sentence "30 percent" when it was not
            // — the same ring saying the same number two different ways depending on whether a
            // caller happened to pass a string.
            .accessibilityLabel(spokenLabel ?? "\(Int((clamped * 100).rounded())) percent")
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
}

// MARK: - C28 · ConfidenceBar

/// C28 · `ConfidenceBar` — the 4pt track under the top candidate on 02.
/// Only the top card has one, which is a call-site rule, not a component one.
struct ConfidenceBar: View {
    /// 0…1. `88%` on the drawn card.
    let fraction: Double

    /// What the track says out loud.
    ///
    /// **Not "confidence".** `VisitShortlist.confidence(topDistanceM:runnerUpDistanceM:accuracyM:)`
    /// is explicit that this is a GPS-geometry confidence — how much clear air there is between the
    /// nearest tree and the next one, relative to the fix's own error — and not a confidence that
    /// the species is right. Sighted users get that qualification from the screen around the bar:
    /// it is drawn under the top card, beside "CONFIRM BY EYE" and a distinguishing trait. A
    /// listener gets no such surroundings from a bare percentage, so the qualification is in the
    /// words.
    var accessibilityLabel: String {
        "Nearest tree match, \(Int((min(max(fraction, 0), 1) * 100).rounded())) percent, from GPS distance alone"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: CypressSpacing.Component.confidenceRadius,
                    style: .continuous
                )
                .fill(CypressColor.borderCool)

                RoundedRectangle(
                    cornerRadius: CypressSpacing.Component.confidenceRadius,
                    style: .continuous
                )
                .fill(CypressColor.canopy)
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(
            maxWidth: CypressSpacing.Component.confidenceMaxWidth,
            alignment: .leading
        )
        .frame(height: CypressSpacing.Component.confidenceHeight)
        .padding(.top, CypressSpacing.Component.confidenceTop)
        // `.accessibilityElement` first, and it is the whole fix. The label used to sit on a
        // `GeometryReader` full of `RoundedRectangle`s — no text, no element — so it attached to
        // nothing and the bar was silent. It was then silent twice over, because the candidate row
        // that hosts it applies `children: .combine`, which walks a subtree that had no element in
        // it to collect.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
