//
//  CypressToggle.swift
//  Cypress — DesignSystem/Components
//
//  C25 · `Toggle` — SCREENS.md §2. The `Sync photos on wifi only` switch on 17.
//  Named `CypressToggle` because SwiftUI already owns `Toggle`.
//
//  **NOT SPECIFIED** (§2 C25, §5 gap 4): the off state. The mock draws only the on switch. The
//  choice made here: the track becomes `border.cool` — the same inactive hairline every other idle
//  control in the system uses — and the knob slides to the leading edge. Nothing else changes, so
//  the off state is a colour and a position, not a different control.
//
//  Tap target: the track is 44×26 as drawn. The width already meets the minimum; the height does
//  not, so the switch keeps its drawn size and takes a 44pt hit area.
//

import SwiftUI

struct CypressToggle: View {
    @Binding var isOn: Bool
    var accessibilityLabelText: String

    init(isOn: Binding<Bool>, accessibilityLabel: String) {
        self._isOn = isOn
        self.accessibilityLabelText = accessibilityLabel
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? CypressColor.selectionFill : CypressColor.toggleOffTrack)
                .frame(
                    width: CypressSpacing.Component.toggleTrackWidth,
                    height: CypressSpacing.Component.toggleTrackHeight
                )
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(CypressColor.toggleKnob)
                        .frame(
                            width: CypressSpacing.Component.toggleKnob,
                            height: CypressSpacing.Component.toggleKnob
                        )
                        .cypressShadow(CypressShadow.toggleKnob)
                        .padding(CypressSpacing.Component.toggleKnobInset)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}
