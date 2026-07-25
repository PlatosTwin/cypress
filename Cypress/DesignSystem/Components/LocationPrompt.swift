//
//  LocationPrompt.swift
//  Cypress — DesignSystem/Components
//
//  The one empty state a user action can fill (RULINGS R11's residual, ERRATA E123).
//
//  §5.6 keeps most empty blocks silent — a block with no data is simply absent. The exception is the
//  screen with no *location*: the almanac and screen 07's `Near you` go blank when there is no fix,
//  and that is the single empty state a tap can resolve, because granting location is an action the
//  reader can take. So this is the one place the app says what the space is for and offers the button
//  that fills it, rather than leaving a considered blank.
//
//  It is a button, not a sentence: tapping it calls `onRequest`, which the composition root wires to
//  `MapLocationProvider.start()` — the same provider screen 01 asks with, so a grant here reports
//  fixes everywhere. On a device that has already refused, `start()` is a safe no-op and the system
//  keeps its own settings surface; the copy stays true either way ("turn on location" is advice, not
//  a promise that this button alone flips a denied permission).
//

import SwiftUI

/// A gentle, tappable prompt shown where a screen would otherwise be blank for want of a location.
struct LocationPrompt: View {
    let title: String
    let subtitle: String
    let onRequest: () -> Void

    var body: some View {
        Button(action: onRequest) {
            VStack(spacing: CypressSpacing.gapRows) {
                Text(title)
                    .font(CypressFont.body15Bold)
                    .foregroundStyle(CypressColor.textInk)
                Text(subtitle)
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, CypressSpacing.gutterSheet)
            .padding(.horizontal, CypressSpacing.gutter)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressDashedBorder(
                CypressColor.borderDashedStrong,
                radius: CypressRadius.cardLg,
                width: CypressSpacing.Component.outlineWidth
            )
        }
        .buttonStyle(.plain)
        // One element to VoiceOver — the title, the subtitle and the frame are one button, and its
        // trait says so. The title alone would drop the "and here is why"; combining keeps both.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
