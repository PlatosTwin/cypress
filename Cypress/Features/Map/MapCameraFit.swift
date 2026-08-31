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

    /// One group, tallied — what the ranking sees, and the only thing it sees.
    struct Standing: Equatable {
        let group: Group
        let count: Int
        /// The newest contribution to any tree in the group, or nil when no row dates one.
        let latest: Date?
    }

    /// The ranking, over a list **whose order the caller chooses**.
    ///
    /// ── Why this is separate from `winner(among:)`, and takes an array ───────────────────────
    /// Because its one guarantee is that the order does not matter, and that is not assertable
    /// against a `Dictionary`: the sequence a dictionary yields is a function of this process's
    /// hash seed, so a test that permutes the *places* and gets the same answer has proved nothing
    /// about the ranking — it has observed that one process's seed did not change. That is exactly
    /// how this round's first determinism guard came to be green against a build with key 3
    /// deleted (PR #135 review, F2). Handed an array, the property is a fact about the ranking and
    /// a test can put the two orders in by hand.
    ///
    /// ── The three keys: the ruling, the reader, and totality ─────────────────────────────────
    /// 1. **Most trees.** The owner's sentence, and the whole of the decision on any real input.
    /// 2. **The most recent contribution.** Two cities holding the same number of the reader's
    ///    trees is a genuine tie, and the reader's own answer to "which of these am I in" is the
    ///    one they were at last. **This round's proposal, not the owner's ruling** — the ruling
    ///    stopped at "the city where you have the most trees". The alternative weighed and not
    ///    taken is written here rather than deferred to: break the tie on inventory size, largest
    ///    first, which is what `InventoryUnion.openingCenter` already does for the opening camera
    ///    and would make the two camera paths agree. It loses because "the biggest city wins" is a
    ///    fact about the inventory rather than about the reader, and this camera is the reader's.
    /// 3. **The group's own key, ascending.** Dates can be nil and can be equal, so a ranking that
    ///    stopped at 2 can still call two groups the same — and a reader who taps the link twice
    ///    must get the same map twice.
    ///
    /// **Key 3 is the whole of the determinism and there is deliberately no second mechanism.**
    /// `sortKey` is unique per group, so with key 3 the comparison is a strict *total* order and
    /// the maximum is unique — it is a property of the comparison rather than of the sequence, so
    /// no input order and no `max(by:)` tie behavior can reach it. A previous version also sorted
    /// the input by `sortKey` before ranking. It was removed rather than kept as belt-and-braces:
    /// two mechanisms either of which suffices are two mechanisms **neither of which any test can
    /// hold**, which the review measured — deleting either one alone left the whole suite green
    /// (F2). One answer, one guard.
    static func best(among standings: [Standing]) -> Group? {
        standings.max { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            let lhsLatest = lhs.latest ?? .distantPast
            let rhsLatest = rhs.latest ?? .distantPast
            if lhsLatest != rhsLatest { return lhsLatest < rhsLatest }
            // Reversed, so the *smallest* key is the maximum, which makes ascending key order the
            // readable rule. Total, because `sortKey` is unique per group: no two distinct
            // standings compare equal, so the maximum does not depend on where they sit.
            return lhs.group.sortKey > rhs.group.sortKey
        }?.group
    }

    /// The tally. Which group the camera should open on, or nil when there is nothing to open on.
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
        // Handed to the ranking in whatever order the dictionary yields, which is safe precisely
        // because `best` does not depend on it. See its header.
        return best(among: counts.map {
            Standing(group: $0.key, count: $0.value.count, latest: $0.value.latest)
        })
    }

    /// The whole decision: the box screen 01 should open on, or nil when this round has no camera
    /// to aim.
    ///
    /// **Nil is a real answer and the caller honors it.** A reader whose every contributed tree is
    /// in a city pack they have since removed has a journal full of rows and no pin the map can
    /// draw (ERRATA E287). There is no camera that shows them their trees, so this round aims none.
    ///
    /// **Nil does not mean the screen holds still, and an earlier version of this sentence said it
    /// did** (PR #135 review, F3). What the caller does with nil is hand back the opening one-shot
    /// it was holding, so `MapHomeView.centerOnUserIfNeeded()` runs and the map may fly to the
    /// *reader* — the ordinary opening behavior, resumed. That is the honest outcome and it is what
    /// the link did before this round: the owner ratified stillness for the **fit**, which is this
    /// function returning nil rather than a plausible box, not suppression of a fly-to-you that has
    /// nothing to do with the ruling.
    static func frame(for places: [ContributedPlace]) -> BoundingBox? {
        guard let winner = winner(among: places) else { return nil }
        let members = places.filter {
            ($0.idSpace.map(Group.city) ?? .unplaced($0.treeID)) == winner
        }
        return MapCameraFrame.around(members.map(\.coordinate))
    }
}
