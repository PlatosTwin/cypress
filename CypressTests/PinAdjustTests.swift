import Foundation
import Testing
import UIKit
@testable import Cypress

/// Moving the pin on the community add.
///
/// `CommunityAddTests` proves the screen and the boundary agree about *whether* a tree may be added.
/// This suite is about *where* it lands, which used to have exactly one answer — `location.fix
/// .coordinate`, verbatim — and now has two.
///
/// The assertions are deliberately about **consequences and stored state**, not about the existence
/// of controls. A green suite has already missed real defects on this project, and the shape of the
/// miss each time was a test that asserted the presence of a thing rather than the effect of using
/// it. So the load-bearing test here reads the coordinate back out of the database and compares it to
/// the one the reader dropped, which is the only assertion that can tell a placed pin from a placed
/// pin that was quietly discarded on the way to `addTree`.
@Suite("Pin adjust")
struct PinAdjustTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD02")!
    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    /// A corner of the Mission with nothing of ours on it. The seed is not attached in these tests,
    /// so the only trees within any dedupe radius are the ones a test adds.
    private static let fix = Coordinate(latitude: 37.7599, longitude: -122.4148)

    @MainActor
    private static func model(
        api: any CypressAPI,
        fix pinnedFix: VisitLocationProvider.Fix = .located(fix, accuracyM: 24)
    ) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: pinnedFix),
            attribution: attribution
        )
    }

    /// A real 1×1 JPEG, for `CommunityAddTests.jpeg`'s reason: the model decodes the frame before it
    /// accepts it, so a fixture that is not an image does not exercise the path that ships.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    // MARK: - The geometry

    @Test("a step north is a step north, and it is the length it says it is")
    func offsetMovesTheStatedDistance() {
        let north = VisitPinAdjust.offset(Self.fix, northM: 40, eastM: 0)
        let east = VisitPinAdjust.offset(Self.fix, northM: 0, eastM: 40)

        // A millimetre, not a tolerance — `VisitPinAdjust.metresPerDegreeLatitude` is derived from the
        // same sphere `Coordinate.distance` measures on, and this is the assertion that says so. On
        // the 111,320 that the bounding boxes use, 40 m comes back as 39.955 and fifteen nudges land
        // 84 mm inside a limit the screen is printing as reached.
        #expect(abs(north.distance(to: Self.fix) - 40) < 0.001, "40 m north measures as \(north.distance(to: Self.fix))")
        #expect(abs(east.distance(to: Self.fix) - 40) < 0.001, "40 m east measures as \(east.distance(to: Self.fix))")
        #expect(north.latitude > Self.fix.latitude)
        #expect(east.longitude > Self.fix.longitude)
        // The bearing the screen will print, from the same arithmetic screen 02 uses.
        #expect(VisitBearing.compass(from: Self.fix, to: north) == "N")
        #expect(VisitBearing.compass(from: Self.fix, to: east) == "E")
    }

    /// The one place a floating-point slip would be invisible and wrong: fifteen nudges is exactly the
    /// radius, and every one of them has to be accepted.
    @Test("fifteen nudges reach the limit and the sixteenth is refused")
    func theNudgeStopsAtTheBoundary() {
        var pin = Self.fix
        for step in 1...15 {
            let moved = try? #require(
                VisitPinAdjust.nudge(pin, towards: .north, from: Self.fix),
                "nudge \(step) of 15 was refused inside the circle"
            )
            pin = moved ?? pin
        }

        #expect(abs(pin.distance(to: Self.fix) - VisitPinAdjust.radiusM) < 0.05)
        #expect(
            VisitPinAdjust.nudge(pin, towards: .north, from: Self.fix) == nil,
            "the pin walked out of the circle"
        )
        // And it is refused rather than clamped: nothing about the refusal moves the pin.
        #expect(VisitPinAdjust.nudge(pin, towards: .south, from: Self.fix) != nil, "the pin is stuck")
    }

    @Test("the bound is a circle, not the box around it")
    func theBoundIsACircle() {
        // On the diagonal, 55 m north and 55 m east is 77.8 m from the fix — inside the box that
        // encloses the circle and outside the circle. This is E35's mistake in the other direction.
        let corner = VisitPinAdjust.offset(Self.fix, northM: 55, eastM: 55)
        #expect(corner.distance(to: Self.fix) > VisitPinAdjust.radiusM)
        #expect(!VisitPinAdjust.isWithinBound(corner, of: Self.fix))
        #expect(VisitPinAdjust.isWithinBound(VisitPinAdjust.offset(Self.fix, northM: 50, eastM: 50), of: Self.fix))
    }

    @Test("the pin may go far enough to be useful and not far enough to be a guess")
    func theRadiusCoversTheCasesItWasChosenFor() {
        // Across the street on a standard 68'9" right-of-way, from a fix 40 m out of place: the two
        // errors the owner named, composed.
        #expect(VisitPinAdjust.isWithinBound(VisitPinAdjust.offset(Self.fix, northM: 40, eastM: 21), of: Self.fix))
        // Three blocks away is not a tree anybody is looking at.
        #expect(!VisitPinAdjust.isWithinBound(VisitPinAdjust.offset(Self.fix, northM: 250, eastM: 0), of: Self.fix))
        // And the ordering that keeps the dedupe meaningful.
        #expect(VisitPinAdjust.radiusM > TreeDraft.proximityDedupeRadiusM)
    }

    // MARK: - What the screen says

    @Test("the screen states where the pin is and what the limit is, every time")
    func thePresentationStatesBothHalves() {
        let atFix = VisitPinAdjustPresentation(anchor: Self.fix, pin: Self.fix)
        #expect(atFix.isAtFix)
        #expect(atFix.isWithinBound)
        #expect(atFix.placement == VisitPinAdjustCopy.atFix)

        let moved = VisitPinAdjustPresentation(
            anchor: Self.fix,
            pin: VisitPinAdjust.offset(Self.fix, northM: 20, eastM: 20)
        )
        #expect(!moved.isAtFix)
        #expect(moved.placement.contains("28 m"), "the distance is not stated: \(moved.placement)")
        #expect(moved.placement.contains("north-east"), "the bearing is not spelled out: \(moved.placement)")
        // The limit is named before it is reached, not only once it is hit.
        #expect(moved.rule.contains("\(Int(VisitPinAdjust.radiusM)) m"))
    }

    /// **The requirement that is easiest to skip: the reader has to be told, on screen, that the pin
    /// has stopped.** A bound that only disables a button is a bound nobody can explain.
    @Test("past the limit the screen says so and the confirm goes dead")
    func thePresentationSaysWhyItStopped() {
        let beyond = VisitPinAdjustPresentation(
            anchor: Self.fix,
            pin: VisitPinAdjust.offset(Self.fix, northM: 120, eastM: 0)
        )

        #expect(!beyond.isWithinBound, "the confirm would still be live 120 m from the fix")
        #expect(beyond.rule != VisitPinAdjustCopy.withinLimit, "the copy did not change at the limit")
        #expect(beyond.rule.contains("past the \(Int(VisitPinAdjust.radiusM)) m limit"))
        // And the refused nudge says the same number, so the two ways of meeting the wall agree.
        #expect(VisitPinAdjustCopy.nudgeRefused.contains("\(Int(VisitPinAdjust.radiusM)) m"))
    }

    @Test("every compass point the bearing can return is a word rather than a letter")
    func everyBearingIsSpelledOut() {
        for point in VisitBearing.compassPoints {
            let spelled = VisitPinAdjustCopy.spelledOut(point)
            #expect(spelled != point, "\(point) is read aloud as its letters")
            #expect(spelled == spelled.lowercased(), "\(point) is not prose")
        }
    }

    // MARK: - The model

    @MainActor
    @Test("without a fix there is no map to open, and no way to place a tree with no GPS at all")
    func noFixNoPin() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)

        for fix in [VisitLocationProvider.Fix.pending, .denied] {
            let subject = Self.model(api: api, fix: fix)
            #expect(!subject.canAdjustPin, "\(fix) was offered a map with no centre")
            subject.beginPlacingPin()
            #expect(subject.phase == .composing, "\(fix) opened the pin screen anyway")
            #expect(subject.coordinate == nil)
        }
    }

    @MainActor
    @Test("the default is still the fix, and the fast path never touches the map")
    func theDefaultIsTheFix() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.model(api: api)

        #expect(subject.placement == .gps)
        #expect(!subject.isReaderPlaced)
        #expect(subject.pinOffsetM == nil)
        #expect(subject.coordinate == Self.fix)
        #expect(subject.canAdjustPin, "there is a fix, so there is a pin to move")
    }

    @MainActor
    @Test("a confirmed pin becomes the coordinate, and the fix stops being it")
    func aConfirmedPinWins() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        let spot = VisitPinAdjust.offset(Self.fix, northM: 30, eastM: 0)

        subject.beginPlacingPin()
        #expect(subject.phase == .placingPin)
        #expect(!subject.canAdd, "the CTA is live while the coordinate is being changed")

        subject.confirmPin(spot)

        #expect(subject.phase == .composing)
        #expect(subject.isReaderPlaced)
        #expect(subject.coordinate == spot)
        #expect(abs(try #require(subject.pinOffsetM) - 30) < 0.05)
    }

    @MainActor
    @Test("leaving the map without confirming changes nothing")
    func cancelKeepsTheFix() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.model(api: api)

        subject.beginPlacingPin()
        subject.cancelPlacingPin()

        #expect(subject.phase == .composing)
        #expect(!subject.isReaderPlaced)
        #expect(subject.coordinate == Self.fix)

        // And cancelling a second visit does not undo the first one's placement.
        let spot = VisitPinAdjust.offset(Self.fix, northM: 12, eastM: 0)
        subject.beginPlacingPin()
        subject.confirmPin(spot)
        subject.beginPlacingPin()
        subject.cancelPlacingPin()
        #expect(subject.coordinate == spot, "cancelling threw away a placement it never touched")
    }

    @MainActor
    @Test("a pin confirmed out of range is not the coordinate the tree gets")
    func theBoundHoldsAtTheModelAndNotOnlyAtTheButton() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.model(api: api)

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(Self.fix, northM: 400, eastM: 0))

        #expect(!subject.isReaderPlaced, "a pin 400 m away became the tree's coordinate")
        #expect(subject.coordinate == Self.fix)
        #expect(subject.phase == .placingPin, "the screen closed on a placement it refused")
    }

    @MainActor
    @Test("a pin put back where it started is the fix again, not a placement of the same point")
    func aPinLeftAtTheFixIsTheFix() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let subject = Self.model(api: api)

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(Self.fix, northM: 25, eastM: 0))
        #expect(subject.isReaderPlaced)

        subject.beginPlacingPin()
        subject.confirmPin(Self.fix)

        #expect(!subject.isReaderPlaced, "confirming at the fix still claims the reader placed it")
        #expect(subject.pinOffsetM == nil)
        #expect(subject.coordinate == Self.fix)
    }

    // MARK: - What actually lands in the database

    /// **The assertion this whole round exists for.**
    ///
    /// Read back out of `community_trees` through `treeProfile`, not off the model that was just
    /// asked. Every layer between the pin and the row — `coordinate`, `TreeDraft`, `addTree`,
    /// `CommunityTreeStore.insert` — could drop the placement and leave the model saying the right
    /// thing about a record that holds the fix.
    @MainActor
    @Test("the tree is stored at the pin the reader dropped, and nowhere near the fix")
    func theStoredCoordinateIsThePin() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())

        let spot = VisitPinAdjust.offset(Self.fix, northM: 45, eastM: 20)
        subject.beginPlacingPin()
        subject.confirmPin(spot)

        let id = try #require(await subject.add(), "the add returned no tree")
        let stored = try await api.treeProfile(id: id).tree.coordinate

        #expect(stored.distance(to: spot) < 0.5, "the tree is \(stored.distance(to: spot)) m from the pin")
        #expect(
            stored.distance(to: Self.fix) > 45,
            "the tree landed on the phone's fix, so the placement was discarded somewhere"
        )
    }

    /// The other half of the row-of-trees case, and the thing a widened pin could have broken: the
    /// 10 m dedupe follows the pin.
    @MainActor
    @Test("five trees placed along one block from one standing spot are five trees")
    func aRowOfTreesAddedFromOneSpot() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        var placed: [Coordinate] = []
        for index in 0..<5 {
            let subject = Self.model(api: api)
            subject.useLibraryImage(try Self.jpeg())
            // Street trees sit 6–10 m apart (D6); this is a row at 12 m along one block face, all of
            // it photographed from the same kerb.
            let spot = VisitPinAdjust.offset(Self.fix, northM: 0, eastM: Double(index) * 12)
            subject.beginPlacingPin()
            subject.confirmPin(spot)

            let id = try #require(
                await subject.add(),
                "tree \(index + 1) of the row was refused: \(subject.phase)"
            )
            placed.append(try await api.treeProfile(id: id).tree.coordinate)
        }

        #expect(Set(placed.map(\.latitude)).count >= 1)
        for (index, coordinate) in placed.enumerated() {
            #expect(
                coordinate.distance(to: VisitPinAdjust.offset(Self.fix, northM: 0, eastM: Double(index) * 12)) < 0.5,
                "tree \(index + 1) is not where it was placed"
            )
        }
    }

    /// And the refusal still works — widening the pin's reach must not widen the hole in the dedupe.
    @MainActor
    @Test("moving the pin onto a tree already on record is still refused, with its candidates")
    func theDedupeFollowsThePin() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // An existing tree 40 m away — comfortably outside the 10 m circle around the fix, so the
        // add would succeed on the default path.
        let occupied = VisitPinAdjust.offset(Self.fix, northM: 40, eastM: 0)
        let first = try await api.addTree(
            TreeDraft(
                coordinate: occupied,
                photoLocalPath: try VisitPhotoStaging.write(Data([0xFF, 0xD8, 0xFF, 0xD9]), for: UUID()),
                attribution: Self.attribution
            )
        )

        let subject = Self.model(api: api)
        subject.useLibraryImage(try Self.jpeg())
        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(occupied, northM: 3, eastM: 0))

        #expect(await subject.add() == nil, "a second tree was added 3 m from an existing one")
        guard case let .duplicate(candidates) = subject.phase else {
            Issue.record("the screen is in \(subject.phase) rather than showing the duplicate warning")
            return
        }
        #expect(candidates.contains { $0.tree.id == first.id })
    }
}
