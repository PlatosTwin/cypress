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

    /// Screen 15's sign-in action, from the composition root (ERRATA E124). Held beside `api` and
    /// handed straight to `AccountAskView`, because who performs a sign-in is the root's question,
    /// not this screen's — the same boundary that keeps `api` here rather than reached for.
    private let onLink: AccountAskLink?

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
        onLink: AccountAskLink? = nil,
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
        self.onLink = onLink
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
        // The sign-in action is `onLink`, from the composition root (ERRATA E124). It completes
        // on-device — mint a `userID`, `claimDevice` this device's contributions onto it — rather
        // than round-tripping a magic link this build has no server for. **What this comment used to
        // add — that `storageLine` keeps saying "this phone only" after it, "which stays true" — is
        // no longer true**: #158's wiring round sends an anonymous installation's queue to
        // `cypress-sync` under its device credential, so that line is false before this sheet opens.
        // See `RootView.accountLink()` and `docs/errata-pending/` for why it is not simply rewritten.
        // When `onLink` is nil (a build with neither a server nor the local seam) 15 renders its
        // "not ready yet" notice instead, unchanged.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .fullScreenCover(isPresented: model.accountAskPresentation) {
            AccountAskView(api: api, onLink: onLink, onFinish: { model.resolveAccountAsk() })
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
            // czPop — the prototype puts it on exactly this circle (18's success mark) and on the
            // "Link copied" pill, which SCREENS.md does not draw and this app therefore does not
            // build. `CypressMotion.pop`. The check is decoration over the word "Visit saved"
            // directly under it, so it carries no label of its own.
            .accessibilityHidden(true)
            .cypressPop(on: model.receipt.visit.id)

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
        .fixedSize(horizontal: false, vertical: true)
        // The same gutter the storage line below already keeps. Without one the mono run set
        // flush against the right glass edge at AX5 (ERRATA E196 §9).
        .padding(.horizontal, CypressSpacing.gutterSheet)
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

                    // czPinDrop, staggered down the route. This is the one map in the app the
                    // prototype's stagger actually fits: a handful of pins in a fixed box that is
                    // drawn once and does not pan. Screen 01's pins are `Annotation`s inside a
                    // live `Map` that recycles them on every camera change, so a per-pin appearance
                    // animation there would fire continuously during a pan — the same class of
                    // problem `MapHomeView.bottomSlot` documents, and it is left alone for the same
                    // reason.
                    ForEach(Array(route.enumerated()), id: \.element.id) { index, candidate in
                        let point = position(of: candidate, in: proxy.size)
                        let isActive = candidate.id == activeTreeID
                        MapPin(isActive
                            ? .routeActive
                            : (visitedTreeIDs.contains(candidate.id) ? .routeDone : .cityTree))
                            // czPulse on the amber pin only — "this tree needs something" is what
                            // amber is reserved for, and on 18 the active pin is the one being
                            // pointed at.
                            .cypressPulse(CypressColor.accentAmber, isActive: isActive)
                            .cypressPinDrop(index: index)
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
        // A degenerate span (one tree, or a perfectly straight row) centers rather than dividing
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
