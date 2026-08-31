//
//  MapCameraFit.swift
//  Cypress — Features/Map
//
//  Two decisions with no view, no MapKit and no clock in them: the box that holds a set of
//  coordinates, and which of the reader's cities a camera arriving from the Journal should open on.
//
//  ── Why the box math moved here ──────────────────────────────────────────────────────────────
//  `PinSetPresentation.frame(around:)` was the app's only fit-to-a-set, written for screen 12's
//  counted rows: hold every pin, pad by a fraction of the group's own extent, and never zoom in
//  tighter than screen 01's own opening view. Every one of those three rules is the right rule for
//  the Journal link too, and a second copy of them would be two camera policies that agree today.
//  So the arithmetic is here and `PinSetPresentation` calls it; that file keeps its own answer for
//  the empty case, which is a fact about screen 12 rather than about boxes.
//
//  ── What is NOT decided here ─────────────────────────────────────────────────────────────────
//  Whether a **search** should move the camera. RULINGS R25 leaves that open by name — "nearest to
//  the camera, or nearest to the reader?" — and nothing below is reachable from the search bar.
//  This file is asked one question by one caller.
//

import Foundation

/// The smallest camera that holds a set of coordinates.
enum MapCameraFrame {

    /// How much room a fitted camera leaves around the group, as a fraction of the group's own
    /// extent.
    ///
    /// **NOT SPECIFIED.** 0.25 is a quarter of the spread on each side, which keeps the outermost
    /// pin clear of the frame edge at the aspect ratios a phone actually has — a pin drawn hard
    /// against the edge reads as "there are more of these off screen", which is the one thing a
    /// camera showing a whole group must not imply.
    ///
    /// It arrived as `PinSetMetrics.framePadding` and that name still resolves to this constant.
    /// It is one number rather than two agreeing numbers on purpose: two screens now fit a camera
    /// to a set of the reader's trees, and a padding that drifted between them would be a
    /// difference nobody chose.
    static let padding: Double = 0.25

    /// The box, padded, with a floor — or nil when there is nothing to hold.
    ///
    /// **Three rules, all of them somebody else's measurement.**
    ///
    /// - **It holds every coordinate.** A camera framing the nearest few is the defect ERRATA E129
    ///   and E144 are both about, at one remove.
    /// - **The padding is a fraction of the group's own extent**, not a fixed distance, so a group
    ///   spread over a neighborhood and a group on one block get the same visual margin. A pin drawn
    ///   hard against the edge reads as "there are more of these off screen", which is the one thing
    ///   a camera showing the whole group must not imply (`padding`, above).
    /// - **It is never tighter than `MapLayout.defaultSpanMeters`.** ERRATA E12 measured 120 m as
    ///   the scale where San Francisco's street trees stop fusing into a mat; below it a group of
    ///   one opens on a single pin with no street to place it against.
    ///
    /// The floor is applied as a **union**, not as a clamp on the fitted box: a 120 m box around the
    /// fitted box's own center, then `min`/`max` on all four edges. A group already wider than the
    /// floor keeps its own extent on both axes, and a group narrower on one axis only is widened on
    /// that axis alone.
    static func around(_ coordinates: [Coordinate], padding: Double = padding) -> BoundingBox? {
        guard let first = coordinates.first else { return nil }

        let enclosing = coordinates.dropFirst().reduce(
            BoundingBox(
                minLatitude: first.latitude,
                maxLatitude: first.latitude,
                minLongitude: first.longitude,
                maxLongitude: first.longitude
            )
        ) { box, coordinate in
            BoundingBox(
                minLatitude: min(box.minLatitude, coordinate.latitude),
                maxLatitude: max(box.maxLatitude, coordinate.latitude),
                minLongitude: min(box.minLongitude, coordinate.longitude),
                maxLongitude: max(box.maxLongitude, coordinate.longitude)
            )
        }.expanded(by: padding)

        let floor = BoundingBox(
            around: Coordinate(
                latitude: (enclosing.minLatitude + enclosing.maxLatitude) / 2,
                longitude: (enclosing.minLongitude + enclosing.maxLongitude) / 2
            ),
            radiusM: MapLayout.defaultSpanMeters / 2
        )

        return BoundingBox(
            minLatitude: min(enclosing.minLatitude, floor.minLatitude),
            maxLatitude: max(enclosing.maxLatitude, floor.maxLatitude),
            minLongitude: min(enclosing.minLongitude, floor.minLongitude),
            maxLongitude: max(enclosing.maxLongitude, floor.maxLongitude)
        )
    }
}

// MARK: - Where the reader's own trees are

/// The camera the Journal's `See them all on the map` link opens screen 01 on.
///
/// ── The ruling this implements ───────────────────────────────────────────────────────────────
/// The owner, on build 63: clicking `See them all on the map` should center the map **on the city
/// where you have the most trees**, which is also the answer for a reader with trees in several.
/// Before this, the link narrowed the map and left the camera wherever it was — so a reader who was
/// nowhere near a city they had contributed in arrived on a blank map that was, technically,
/// showing only their trees.
///
/// ── Why the winner is a city and not simply "all of them" ────────────────────────────────────
/// Because the honest fit over a set spanning two cities is the box that holds both, and the box
/// holding San Francisco and New York is the United States — a camera at which no pin is a pin and
/// nothing is on screen. Narrowing to one city is what makes "centered on where the trees are"
/// producible at all. Which city is the ruling's own answer: the one holding the most of them.
enum ContributedCamera {

    /// The unit the vote is counted in.
    ///
    /// **A tree with no city is its own group, rather than being dropped or being pooled with the
    /// others.** Pooling is the failure this whole type exists to avoid, one level down: two
    /// community-added trees a thousand kilometers apart with no inventory near either would form
    /// one "city" and fit to a continent. Dropping them would mean a reader whose only contribution
    /// is a tree they added somewhere the app has no inventory for gets no camera at all. As a
    /// singleton it can win only when no city holds more than one of the reader's trees, and the
    /// camera it wins is that tree at the 120 m floor — which is the right answer for that reader.
    enum Group: Hashable {
        case city(String)
        case unplaced(UUID)

        /// The last tie-break, and the only one that cannot itself tie. `Hashable` order is not
        /// stable across launches; this string is.
        var sortKey: String {
            switch self {
            case .city(let idSpace): return "city:\(idSpace)"
            case .unplaced(let treeID): return "tree:\(treeID.uuidString)"
            }
        }
    }

    /// Which group the camera should open on, or nil when there is nothing to open on.
    ///
    /// **The order of the three keys is the ruling, then determinism, then determinism again.**
    ///
    /// 1. **Most trees.** The owner's sentence, and the whole of the decision on any real input.
    /// 2. **The most recent contribution.** Two cities holding the same number of the reader's
    ///    trees is a genuine tie, and the reader's own answer to "which of these am I in" is the
    ///    one they were at last. Proposed rather than ruled — see the round's pending ruling for
    ///    the alternative that was recorded (largest-inventory-first, which is what
    ///    `InventoryUnion.openingCenter` already does for the opening camera).
    /// 3. **The group's own key.** Dates can be nil and can be equal; a comparison that can still
    ///    tie is a comparison that leaves the camera to `Dictionary` iteration order, which differs
    ///    between launches of the same build. A reader who taps the link twice must get the same
    ///    map twice.
    static func winner(among places: [ContributedPlace]) -> Group? {
        var counts: [Group: (count: Int, latest: Date?)] = [:]
        for place in places {
            let group = place.idSpace.map(Group.city) ?? .unplaced(place.treeID)
            var tally = counts[group] ?? (count: 0, latest: nil)
            tally.count += 1
            if let at = place.contributedAt, at > (tally.latest ?? .distantPast) {
                tally.latest = at
            }
            counts[group] = tally
        }
        return counts.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            let lhsLatest = lhs.value.latest ?? .distantPast
            let rhsLatest = rhs.value.latest ?? .distantPast
            if lhsLatest != rhsLatest { return lhsLatest < rhsLatest }
            // Reversed, so the *smallest* key is the maximum: `max(by:)` returns the last element
            // that is not less than every other, and ascending key order is the readable rule.
            return lhs.key.sortKey > rhs.key.sortKey
        }?.key
    }

    /// The whole decision: the box screen 01 should open on, or nil to leave the camera alone.
    ///
    /// **Nil is a real answer and the caller honors it.** A reader whose every contributed tree is
    /// in a city pack they have since removed has a journal full of rows and no pin the map can
    /// draw (ERRATA E287). There is no camera that shows them their trees, so the camera does not
    /// move — which is what the link did before this round, and is the one case where that was
    /// already the honest behavior.
    static func frame(for places: [ContributedPlace]) -> BoundingBox? {
        guard let winner = winner(among: places) else { return nil }
        let members = places.filter {
            ($0.idSpace.map(Group.city) ?? .unplaced($0.treeID)) == winner
        }
        return MapCameraFrame.around(members.map(\.coordinate))
    }
}
