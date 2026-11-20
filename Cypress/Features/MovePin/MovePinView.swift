//
//  MovePinView.swift
//  Cypress — Features/MovePin
//
//  **NOT SPECIFIED.** The owner's Move pin control of 2026-11-12; the argument is in
//  `MovePinPresentation.swift`, and this file only draws it.
//
//  Built from the add flow's own pin screen (`VisitPinAdjustView`): the same basemap, the same pin
//  drawn at the center while the map moves under it, and the same nudge pad, so moving a pin looks
//  the same before and after a tree is recorded. What differs is the rule: no 75 m circle around a
//  fix (the service sets no bound on a correction), and the screen writes the move itself.
//
//  **Save and Cancel are plain buttons on a pushed screen**, not a `confirmationDialog`: on iOS 26 a
//  dialog's cancel action is not drawn (ROADMAP chip 77), and PR #185 moved its take-back to
//  controls that draw on both runtimes for that reason.
//
//  Not a raw hex, a raw font size or a raw radius in the file (ARCHITECTURE §6).
//

import MapKit
import SwiftUI

struct MovePinView: View {

    @State private var model: MovePinModel
    @State private var position: MapCameraRequest?
    @State private var region = MKCoordinateRegion()

    /// The move is written. The composition root pops back to the profile, which re-reads itself.
    private let onSaved: () -> Void
    /// Left without saving. Nothing moves.
    private let onCancel: () -> Void

    init(
        treeID: UUID,
        coordinate: Coordinate,
        api: any CypressAPI,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = State(wrappedValue: MovePinModel(treeID: treeID, original: coordinate, api: api))
        self.onSaved = onSaved
        self.onCancel = onCancel
    }

    var body: some View {
        let presentation = model.presentation

        VStack(spacing: 0) {
            ScreenHeader(title: MovePinCopy.title, bottomInset: .wide, onBack: onCancel)
            statement(presentation)
            map
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.didSave) { _, saved in
            if saved { onSaved() }
        }
    }

    // MARK: - The sentences above the map

    private func statement(_ presentation: MovePinPresentation) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(presentation.placement)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.failure ?? MovePinCopy.rule)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.bottom, CypressSpacing.labelSectionTop)
    }

    // MARK: - The map

    /// `VisitPinAdjustView.map`'s arrangement: the pin is the center of the map, and the map moves
    /// under it. That view's header carries the argument against a draggable annotation.
    private var map: some View {
        MapKitBasemap(
            position: Binding(
                get: {
                    position ?? .opening(
                        MapLayout.region(around: model.original, meters: VisitMetrics.PinAdjust.openingSpanM)
                    )
                },
                set: { position = $0 }
            ),
            region: $region,
            clusters: [],
            pins: [],
            userCoordinate: nil,
            selectedPinID: nil,
            onCameraChange: { box, _ in
                let center = VisitPinAdjust.center(of: box)
                // A pan clears the last refusal, because the pin is somewhere new.
                if center.distance(to: model.pin) > VisitMetrics.PinAdjust.stillnessM { model.failure = nil }
                model.pin = center
            },
            onSelectPin: { _ in },
            onSelectCluster: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            MapPin(.community)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VisitPinAdjustCopy.pinLabel)
                .accessibilityValue(model.presentation.placement)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            nudgePad
            PrimaryButton(MovePinCopy.save, isEnabled: model.canSave) {
                Task { await model.save() }
            }
            SecondaryOutlineButton(MovePinCopy.cancel, style: .compact) { onCancel() }
            Button { move(to: model.original) } label: {
                Text(MovePinCopy.recenter)
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.ctaFill)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cypressHitArea()
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Identify.footerTop)
        .padding(.bottom, CypressSpacing.bottomCTA)
    }

    /// `VisitPinAdjustView.nudgePad`'s four controls, without its circle: the accessibility answer
    /// to a map that only a pan can move.
    private var nudgePad: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(VisitPinAdjustCopy.nudgeLabel).cypressMonoSectionLabel()
            HStack(spacing: CypressSpacing.gapRows) {
                ForEach(VisitPinAdjust.Direction.allCases, id: \.self) { direction in
                    SecondaryOutlineButton(
                        VisitPinAdjustCopy.nudgeGlyph(direction),
                        style: .compact
                    ) {
                        let step = direction.step
                        let moved = VisitPinAdjust.offset(model.pin, northM: step.northM, eastM: step.eastM)
                        move(to: moved)
                        AccessibilityNotification.Announcement(model.presentation.placement).post()
                    }
                    .accessibilityLabel(VisitPinAdjustCopy.nudge(direction))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Moves the pin and the camera under it together, at the reader's current zoom.
    /// `VisitPinAdjustView.move(to:)`'s argument about the first settle applies.
    private func move(to coordinate: Coordinate) {
        let span = region.span.latitudeDelta > 0
            ? region.span
            : MapLayout.region(around: coordinate, meters: VisitMetrics.PinAdjust.openingSpanM).span
        model.failure = nil
        model.pin = coordinate
        position = .move(to: MKCoordinateRegion(center: coordinate.clLocationCoordinate, span: span))
    }
}
