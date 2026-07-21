//
//  ProgressRing.swift
//  Cypress — DesignSystem/Components
//
//  C27 · `ProgressRing` (08) and C28 · `ConfidenceBar` (02) — SCREENS.md §2.
//
//  D1 guard: the ring on 08 tracks *species you can recognise*, which is knowledge, not a count of
//  actions — "There are no leaderboards" is printed on the same screen. `ProgressRing` therefore
//  takes a fraction and a caption, never a running total of visits, photos or care events.
//

import SwiftUI

struct ProgressRing: View {
    /// 0…1. Drawn as `conic-gradient(#2F6B4F 0 30%, #E0E6D8 30% 100%)`.
    let fraction: Double
    /// The label inside the disc. `30%` on 08.
    var label: String?

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: CypressColor.canopy, location: 0),
                        .init(color: CypressColor.canopy, location: clamped),
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
                                .foregroundStyle(CypressColor.cypressDeep)
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
            .accessibilityLabel(label ?? "\(Int(clamped * 100)) percent")
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
}

// MARK: - C28 · ConfidenceBar

/// C28 · `ConfidenceBar` — the 4pt track under the top candidate on 02.
/// Only the top card has one, which is a call-site rule, not a component one.
struct ConfidenceBar: View {
    /// 0…1. `88%` on the drawn card.
    let fraction: Double

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
        .accessibilityLabel("Confidence \(Int(min(max(fraction, 0), 1) * 100)) percent")
    }
}
