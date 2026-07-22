//
//  VisitSavedView.swift
//  Cypress — Features/Visit
//
//  Screen 18 · Next tree
//  "Saving a check-in immediately offers the next nearest tree, checked trees dim on the map, and a
//  ten-tree morning moves along on its own."
//

import SwiftUI

struct VisitSavedView: View {

    @State private var model: VisitSavedModel

    /// Held beside the model because screen 15 does its own read (`deviceContributions()`), and the
    /// boundary rule is that a feature gets its data through `CypressAPI` rather than through
    /// another feature's model (ARCHITECTURE §4).
    private let api: any CypressAPI

    /// Advance to the next tree — straight to its camera, per PROTOTYPE-FLOW's `nextAction`.
    let onNextTree: (VisitCandidate) -> Void
    /// "Route done · see your grove". The grove is screen 08 and not this feature's; the container
    /// decides where that goes.
    let onRouteComplete: () -> Void
    /// "Done for today".
    let onDone: () -> Void
    /// "See it on the tree's timeline" — screen 03, another feature's.
    let onOpenTimeline: (UUID) -> Void

    init(
        receipt: VisitSaveReceipt,
        treeDisplayName: String,
        origin: Coordinate?,
        visitedTreeIDs: [UUID],
        api: any CypressAPI,
        ledger: VisitSaveLedger,
        onNextTree: @escaping (VisitCandidate) -> Void,
        onRouteComplete: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onOpenTimeline: @escaping (UUID) -> Void
    ) {
        _model = State(wrappedValue: VisitSavedModel(
            receipt: receipt,
            treeDisplayName: treeDisplayName,
            origin: origin,
            visitedTreeIDs: visitedTreeIDs,
            api: api,
            ledger: ledger
        ))
        self.api = api
        self.onNextTree = onNextTree
        self.onRouteComplete = onRouteComplete
        self.onDone = onDone
        self.onOpenTimeline = onOpenTimeline
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                successBlock
                routeMap
                primaryCTA
                secondaryActions
                footnote
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .task { await model.load() }
        // ══════════════════════════════════════════════════════════════════════════════════════
        // D9 SEAM — screen 15 (the account ask) is presented here, and only here.
        //
        // `model.shouldPresentAccountAsk` is true from the **third** save (DESIGN v3 / D9 beat
        // SPEC-PHASE1's "first"; see `VisitSaveLedger`), and at most twice in total — once, plus one
        // second chance if the first went unanswered because the app died with the sheet up
        // (ERRATA E34).
        //
        // Presented from `model.accountAskPresentation`, not from the flag: that binding resolves
        // the ask on every way of closing the sheet, so a dismissal that never reaches `onFinish`
        // cannot leave the ask owed. Both halves of E34's fix are load-bearing and neither carries
        // it alone.
        //
        // `fullScreenCover` rather than `.sheet`, for the reason `RootView` gives screens 09 and 10:
        // 15 draws its *own* scrim over its own map backdrop (C17 `.account`, scrim `.3`), and a
        // system sheet would impose a second card and a second dimming over the top of it.
        //
        // No sign-in action is passed. `CypressAPI` states why in its own header — there is no auth
        // server and no local equivalent of a token exchange — and a stub that minted an account on
        // device would have this screen claim a backup that does not exist (ARCHITECTURE §5.4's
        // principle, applied to an account rather than to the city). The screen says so instead.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .fullScreenCover(isPresented: model.accountAskPresentation) {
            AccountAskView(api: api, onFinish: { model.resolveAccountAsk() })
        }
    }

    // MARK: - Success

    private var successBlock: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(CypressColor.thrivingBadgeFill)
                CypressCheckmark()
                    .stroke(
                        CypressColor.thrivingBadgeText,
                        style: StrokeStyle(
                            lineWidth: VisitMetrics.Saved.successCheckStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(
                        width: VisitMetrics.Saved.successCheckWidth,
                        height: VisitMetrics.Saved.successCheckHeight
                    )
            }
            .frame(width: VisitMetrics.Saved.successCircle, height: VisitMetrics.Saved.successCircle)

            // SCREENS 18 draws `Check-in saved`. Nothing was checked in — the structured health
            // observation is screen 05 and it did not run. The one-word change keeps the
            // confirmation true to what the user actually did.
            Text("Visit saved")
                .font(CypressFont.successTitle)
                .foregroundStyle(CypressColor.textInk)
                .padding(.top, VisitMetrics.Saved.successTitleTop)

            subtitle
                .padding(.top, VisitMetrics.Saved.successSubtitleTop)

            if let recency = model.recencyLine {
                Text(recency)
                    .cypressBody135(color: CypressColor.textMuted)
                    .padding(.top, VisitMetrics.Saved.successSubtitleTop)
            }

            Text(model.storageLine)
                .cypressBody135(color: CypressColor.textFaint)
                .multilineTextAlignment(.center)
                .padding(.top, CypressSpacing.gapRows)
                .padding(.horizontal, CypressSpacing.gutterSheet)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, VisitMetrics.Saved.successTop)
        .padding(.bottom, VisitMetrics.Saved.successBottom)
    }

    private var subtitle: some View {
        Group {
            if let position = model.routePositionLine {
                Text(model.treeDisplayName)
                    .font(CypressFont.body135)
                    .foregroundStyle(CypressColor.textMuted)
                    + Text(" · ")
                    .font(CypressFont.body135)
                    .foregroundStyle(CypressColor.textMuted)
                    + Text(position)
                    .font(CypressFont.mono12)
                    .foregroundStyle(CypressColor.textMuted)
            } else {
                Text(model.treeDisplayName)
                    .font(CypressFont.body135)
                    .foregroundStyle(CypressColor.textMuted)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Route map

    private var routeMap: some View {
        VisitRouteMap(
            route: model.route,
            visitedTreeIDs: model.visitedTreeIDs,
            activeTreeID: model.receipt.visit.treeID
        )
        .frame(height: VisitMetrics.Saved.routeMapHeight)
        .cypressCornerRadius(CypressRadius.cardLg)
        .cypressBorder(CypressColor.borderRouteMap, radius: CypressRadius.cardLg)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.vertical, VisitMetrics.Saved.routeMapTop)
    }

    // MARK: - Actions

    private var primaryCTA: some View {
        PrimaryButton(model.nextLabel, style: .large) {
            if let next = model.nextTree {
                onNextTree(next)
            } else {
                onRouteComplete()
            }
        }
        .padding(.horizontal, CypressSpacing.gutter)
    }

    private var secondaryActions: some View {
        VStack(spacing: VisitMetrics.Saved.secondaryTop) {
            SecondaryOutlineButton("Done for today") { onDone() }

            Button {
                onOpenTimeline(model.receipt.visit.treeID)
            } label: {
                Text("See it on the tree's timeline")
                    .font(CypressFont.body135Bold)
                    .foregroundStyle(CypressColor.ctaFill)
                    .frame(maxWidth: .infinity)
                    .cypressTapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Saved.secondaryTop)
    }

    private var footnote: some View {
        Text(
            "Ten check-ins in a row is the real volunteer morning. The save answers the only "
                + "question that matters: which tree is next."
        )
        .cypressBody135(color: CypressColor.textMuted)
        .lineSpacing(VisitMetrics.Saved.footnoteLineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VisitMetrics.Saved.footnoteHorizontal)
        .padding(.top, VisitMetrics.Saved.footnoteTop)
        .padding(.bottom, CypressSpacing.bottomFootnote)
    }
}

// MARK: - The mini route map

/// SCREENS 18 §2 — the reduced `MapCanvas` with the day's route on it.
///
/// The pins are placed from **real coordinates**, projected into the box: the route comes from
/// `treesNear`, so the shape on screen is the shape of the block you are standing on. Done trees
/// draw as `MapPin.routeDone` — "done trees go quiet" — and the tree just saved draws as the amber
/// active pin.
struct VisitRouteMap: View {

    let route: [VisitCandidate]
    let visitedTreeIDs: [UUID]
    let activeTreeID: UUID

    /// Keeps pins off the rounded corners.
    private let inset: CGFloat = 24

    var body: some View {
        MapCanvas.reduced {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    water(in: proxy.size)

                    ForEach(route) { candidate in
                        let point = position(of: candidate, in: proxy.size)
                        MapPin(candidate.id == activeTreeID
                            ? .routeActive
                            : (visitedTreeIDs.contains(candidate.id) ? .routeDone : .cityTree))
                            .position(x: point.x, y: point.y)
                    }

                    Text("done trees go quiet")
                        .font(CypressFont.mono10)
                        .foregroundStyle(CypressColor.textFaintAlt)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, VisitMetrics.Saved.routeLabelTrailing)
                        .padding(.bottom, VisitMetrics.Saved.routeLabelBottom)
                }
            }
        }
    }

    private func water(in size: CGSize) -> some View {
        VisitColor.routeWater
            .opacity(VisitMetrics.Saved.routeWaterOpacity)
            .frame(width: size.width * VisitMetrics.Saved.routeWaterFraction)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Equirectangular projection of the route's own bounding box into the drawn box. Good enough
    /// at a two-block scale and, unlike a fixed pin layout, it moves when the user does.
    private func position(of candidate: VisitCandidate, in size: CGSize) -> CGPoint {
        let coordinates = route.map(\.tree.coordinate)
        guard !coordinates.isEmpty else { return CGPoint(x: size.width / 2, y: size.height / 2) }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? 0, maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0, maxLon = longitudes.max() ?? 0

        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        // A degenerate span (one tree, or a perfectly straight row) centres rather than dividing
        // by zero.
        let x = maxLon > minLon
            ? inset + (candidate.tree.coordinate.longitude - minLon) / (maxLon - minLon) * width
            : size.width / 2
        // Latitude grows north, screen y grows south.
        let y = maxLat > minLat
            ? inset + (maxLat - candidate.tree.coordinate.latitude) / (maxLat - minLat) * height
            : size.height / 2
        return CGPoint(x: x, y: y)
    }
}
