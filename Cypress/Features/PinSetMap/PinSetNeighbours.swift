//
//  PinSetNeighbours.swift
//  Cypress — Features/PinSetMap
//
//  **NOT SPECIFIED.** ERRATA E142. The one read this screen performs, and the argument for why a
//  screen whose own header says it "never calls `mapContent(in:)`" now does, for exactly one of its
//  three subjects.
//
//  ── Why the block has to be on the map ────────────────────────────────────────────────────
//  A map with one pin on it answers "which street" and stops. The reader is standing on that street
//  looking at a row of trees, and the question they still have is *which one* — the third from the
//  corner, or the one outside number 2576. A pin drawn alone cannot be counted along a block,
//  because there is nothing to count. So the neighbours are drawn, and the subject is drawn 1.25×
//  (`MapLayout.selectedPinScale`, through `selectedPinID` — the app's existing and only vocabulary
//  for "this one") in the middle of them.
//
//  ── Why this read cannot disagree with anything ───────────────────────────────────────────
//  E129 forbids the destination re-reading its group, and the reason is precise: the almanac's row
//  has already printed a *count*, and a second read a second later can disagree with the sentence
//  the reader tapped. Nothing here is counted. The record travels on the route exactly as before and
//  is drawn from the payload on the first frame; what this read returns is scenery, it is never
//  counted out loud, and `PinSetPresentation.coverage` only mentions it once it has arrived. If the
//  read fails or returns nothing, the screen is the one-pin map it would have been anyway.
//
//  ── Why a closure and not the API ─────────────────────────────────────────────────────────
//  The composition root resolves the boundary call and hands the feature the one operation it needs,
//  which is the pattern `RootView` already uses for the journal export (`JournalExportBytes`). It
//  also keeps the two counted groups honest by construction: they are pushed with no neighbours at
//  all, so there is no path by which E129's screen can acquire a query it is documented not to have.
//

import Foundation

/// Reads the records standing around a coordinate.
///
/// A `Sendable` box around one async call, so the view can hold it, previews can hand it a constant,
/// and tests can hand it a spy. It is deliberately not `any CypressAPI`: the whole surface this
/// screen is allowed to touch is one read of one box.
struct PinSetNeighbours: Sendable {

    let read: @Sendable (Coordinate) async -> [TreePin]

    init(read: @escaping @Sendable (Coordinate) async -> [TreePin]) {
        self.read = read
    }

    /// The screen with no neighbours to draw — the two counted groups, and every preview.
    static let none = PinSetNeighbours { _ in [] }

    /// The real read, over the app's one boundary (ARCHITECTURE §4).
    ///
    /// **The box is the camera's own**, `MapLayout.defaultSpanMetres` across and centred on the
    /// record, so the pins that come back are the pins the reader can see and nothing is fetched to
    /// be drawn off screen. The zoom is stated rather than derived because it is not a camera: it is
    /// the assertion that this read wants *individual pins*, which `MapViewport` decides from the
    /// zoom (A1: clusters at 15 and below, pins at 16 and above). A clustered answer here would be
    /// one badge saying "31" in place of the block.
    ///
    /// `pinLimit` is left at its default. One block at 120 m is tens of records, not thousands, and
    /// a cap chosen here would be a second, quieter opinion about the pin budget than the one
    /// `MapModel` holds for the screen that actually has a budget problem (ERRATA E130).
    ///
    /// A failure is an empty array and not an error. There is nothing for this screen to say about a
    /// read that only ever added context to a map that is already correct without it, and a banner
    /// over a working map would be the app apologising for something the reader did not ask for.
    static func around(_ api: any CypressAPI) -> PinSetNeighbours {
        PinSetNeighbours { coordinate in
            let viewport = MapViewport(
                bounds: BoundingBox(around: coordinate, radiusM: MapLayout.defaultSpanMetres / 2),
                zoom: MapViewport.highestClusteringZoom + 1
            )
            guard case let .pins(answer)? = try? await api.mapContent(in: viewport) else { return [] }
            return answer.items
        }
    }
}
