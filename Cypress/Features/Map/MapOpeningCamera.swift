//
//  MapOpeningCamera.swift
//  Cypress — Features/Map
//
//  Where screen 01 opens, and what it says when that is not on you.
//
//  ── The ask ──────────────────────────────────────────────────────────────────────────────────────
//  "Opening the app should open on where you're located right now, 100% of the time." (#115)
//
//  Two thirds of that is a camera problem and was fixed where the camera lives — ERRATA E167, in
//  `MapAnnotationLayer`: the fly-to-you was minted, applied, and then thrown away by an opening
//  region MapKit was still holding from before the map had a size. With that repaired the map really
//  does open on the reader whenever the phone knows where they are.
//
//  The last third is the window before the phone answers, and the states where it never will. This
//  file is that third: what the camera sits on in the meantime, and — the part that is not optional —
//  what the screen *says* about it.
//
//  ── Why anything is remembered at all ────────────────────────────────────────────────────────────
//  There is a gap between the app drawing its first frame and CoreLocation producing a fix, and no
//  amount of camera correctness closes it: the fix does not exist yet. Something has to be on screen.
//
//  It used to be `MapLayout.defaultCentre` — Mission Dolores Park — every single time, for everyone,
//  forever. A park, in a *street* tree inventory, whose own documentation admits "the nearest
//  inventoried tree is on 18th or 20th St, outside a 120 × 261 m view". So the app's first frame was
//  a stranger's park with no trees on it.
//
//  **A place the reader has actually been beats a stranger's park.** The last camera they left the
//  map on is the best available guess at where they are, it is theirs, and on the overwhelmingly
//  common case — the app reopened in the same neighbourhood as last time — it is very nearly right.
//  Dolores Park survives as the answer to the one question nothing else can answer: the first launch,
//  where there is no history and no fix.
//
//  ── Why `UserDefaults` and not `app_state` ───────────────────────────────────────────────────────
//  `VisitSaveLedger`'s reasoning, and one more that decides it outright.
//
//  The ledger's argument applies unchanged: this is a UI fact, not a contribution. It does not sync,
//  it does not appear in an export, and putting it in the store would give it a permanence it should
//  not have.
//
//  The deciding one is that `CypressStore.appState(_:)` is `async`. The opening camera has to be
//  known *before the first frame is drawn* — that is the entire job — and a value that arrives one
//  `await` later is a value that arrives after the map has already opened somewhere else and has to
//  jump. Which is the defect, performed slightly faster.
//
//  ── The cost model ───────────────────────────────────────────────────────────────────────────────
//  Tasks #51, #75 and #84 were all map performance, and #84 was the basemap re-evaluating some 200
//  times a second at rest. A camera that wrote to storage on every pan would hand that back.
//
//  So **nothing is written while the reader is moving the map.** A settle updates a struct in memory;
//  the write happens once, when the app leaves the foreground or the screen goes away. There is no
//  debounce timer to tune and no I/O on the pan path at all.
//

import CoreLocation
import Foundation
import MapKit

/// The camera screen 01 was last left on, remembered across launches.
///
/// One value, loaded once per process and written at most once per visit to the screen. See the
/// header for why it is `UserDefaults` and why the write is not on the pan path.
@MainActor
final class MapCameraMemory {

    /// A camera, in the two facts that reproduce it: where it was pointed and how much it covered.
    struct Snapshot: Equatable, Sendable {
        var centre: Coordinate
        var latitudeSpan: Double
        var longitudeSpan: Double
    }

    static let shared = MapCameraMemory()

    /// Four doubles: latitude, longitude, latitude span, longitude span. An array rather than four
    /// keys so a half-written camera is not representable — either all four are there or none are.
    static let defaultsKey = "map.lastCamera"

    /// The widest span worth remembering, in degrees of latitude.
    ///
    /// A camera pinched out to the whole hemisphere is not a place the reader has been, it is a
    /// gesture they made on the way somewhere; reopening the app on it would be worse than the park.
    /// Ten degrees is about 1,100 km — far wider than any useful view of one city, and narrow enough
    /// that a stored value beyond it is a bug rather than a preference.
    static let maximumSpanDegrees: Double = 10

    private let defaults: UserDefaults

    private var hasLoaded = false
    /// What was on disk when this process started, and never anything else. The *opening* camera and
    /// the sentence explaining it both have to mean "where you left the map last time", which stops
    /// being true the moment this screen notes its first settle.
    private var launchSnapshot: Snapshot?
    /// What will be written. Updated by every settle, read by nobody but `flush()`.
    private var current: Snapshot?
    private var isDirty = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The camera this install was left on last time, if there is one and it is usable.
    var remembered: Snapshot? {
        loadIfNeeded()
        return launchSnapshot
    }

    /// Whether the map opened on somewhere the reader has actually been.
    ///
    /// The screen says different things in the two cases, so this is asked rather than inferred from
    /// `remembered != nil` at some later moment when it would no longer be the same question.
    var hasRememberedCamera: Bool { remembered != nil }

    /// A settled camera. **In memory only** — see the header on the cost model.
    func note(_ snapshot: Snapshot) {
        guard Self.isWorthRemembering(snapshot) else { return }
        loadIfNeeded()
        guard current != snapshot else { return }
        current = snapshot
        isDirty = true
    }

    /// Write it down. Called when the app leaves the foreground and when the screen goes away, which
    /// between them cover every way a reader stops looking at the map.
    func flush() {
        guard isDirty, let current else { return }
        isDirty = false
        defaults.set(Self.encode(current), forKey: Self.defaultsKey)
    }

    /// Drops both the stored camera and everything this process has learnt. Only tests need it, but
    /// they need it to be total — a `forget` that left `launchSnapshot` standing would make every
    /// test after it read the one before it.
    func forget() {
        defaults.removeObject(forKey: Self.defaultsKey)
        hasLoaded = false
        launchSnapshot = nil
        current = nil
        isDirty = false
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        launchSnapshot = Self.decode(defaults.array(forKey: Self.defaultsKey) as? [Double])
        current = launchSnapshot
    }

    // MARK: The stored form

    /// Whether a camera is a place rather than a glitch.
    ///
    /// Every one of these has been seen from `MKMapView` at least once in this codebase's life: a
    /// zero span is the camera before the map has settled (`MapRecentre.Camera.isCentred` guards the
    /// same case), and a centre at MapKit's own default is what a map that was never aimed reads back
    /// as — 37.3346, which E167 is the story of. A camera that fails this is not written and not
    /// restored; the reader gets the park, which is at least a real place.
    static func isWorthRemembering(_ snapshot: Snapshot) -> Bool {
        guard snapshot.latitudeSpan > 0, snapshot.longitudeSpan > 0 else { return false }
        guard snapshot.latitudeSpan <= maximumSpanDegrees,
              snapshot.longitudeSpan <= maximumSpanDegrees else { return false }
        guard abs(snapshot.centre.latitude) <= 90, abs(snapshot.centre.longitude) <= 180 else {
            return false
        }
        return CLLocationCoordinate2DIsValid(snapshot.centre.clLocationCoordinate)
    }

    static func encode(_ snapshot: Snapshot) -> [Double] {
        [
            snapshot.centre.latitude,
            snapshot.centre.longitude,
            snapshot.latitudeSpan,
            snapshot.longitudeSpan
        ]
    }

    /// Anything that is not four usable doubles is no camera at all. `UserDefaults` is a file other
    /// processes and other versions of this app can have written, so this decodes defensively rather
    /// than trusting its own encoder.
    static func decode(_ values: [Double]?) -> Snapshot? {
        guard let values, values.count == 4 else { return nil }
        guard values.allSatisfy(\.isFinite) else { return nil }
        let snapshot = Snapshot(
            centre: Coordinate(latitude: values[0], longitude: values[1]),
            latitudeSpan: values[2],
            longitudeSpan: values[3]
        )
        return isWorthRemembering(snapshot) ? snapshot : nil
    }
}

// MARK: - What the screen opens on, and what it owes the reader

/// Screen 01's opening behaviour, as decisions rather than as branches inside a view.
///
/// Pure and free of SwiftUI, so the whole of it is assertable in
/// `CypressTests/MapOpeningCameraTests` without a camera, a phone or a permission sheet.
enum MapOpening {

    /// What the camera is sitting on, when it is not sitting on the reader. Two cases, because the
    /// screen has two honest things it can say and they are not the same sentence.
    enum Showing: Equatable {
        /// The camera this install was last left on.
        case whereYouLeftOff
        /// `MapLayout.defaultCentre`. A first launch, or a stored camera that did not survive
        /// `MapCameraMemory.isWorthRemembering`.
        case theCityFallback
    }

    /// What the screen is waiting for, if anything.
    ///
    /// The two waits are separated because they end differently — one ends when somebody answers a
    /// sheet, the other when a satellite does — and a screen that told the reader the same thing in
    /// both would be repeating E158's mistake one screen over.
    enum Wait: Equatable {
        /// There is a fix, or there will never be one without a trip to Settings. Nothing to time.
        case none
        /// Nobody has answered the permission ask yet.
        case permission
        /// Permission granted; CoreLocation has not produced a first fix.
        case fix
    }

    /// The unprompted occupant of screen 01's bottom slot: what the map says about itself when
    /// nobody has pressed anything.
    ///
    /// **This is ERRATA E126 applied to the map** — "a screen showing something other than what you
    /// asked for must say why" — and the reason there are four cases rather than a boolean is E158's
    /// finding, three months of "too weak" shown to people whose phone had simply not answered yet.
    /// Refused, restricted, unanswered and still-looking are four different facts about the world and
    /// the reader is owed the right one.
    enum Standing: Equatable {
        /// The map is on the reader, or is theirs to move. Nothing to explain.
        case nothing
        /// The permission ask has not been answered and the sheet is no longer on screen.
        case notAsked(Showing)
        /// Granted, still looking, and looking long enough that it has become a question.
        case searching(Showing)
        /// Refused, or Location Services off device-wide. `MapLocationCopy.title` tells those apart.
        case refused(MapLocationProvider.Availability, Showing)
    }

    /// How long a wait may go unremarked before the screen owes the reader a sentence.
    ///
    /// **Not zero, and the reason is that a notice which flashes is noise.** With permission already
    /// granted, CoreLocation answers a cold launch from its cache in well under a second; a notice
    /// posted the instant the map appears would therefore appear and withdraw itself on every single
    /// launch, and a sentence that is always wrong within a second teaches the reader to stop reading
    /// the slot it appears in. Three seconds is longer than a healthy launch and far shorter than the
    /// time it takes to wonder why the map is somewhere else.
    ///
    /// It does **not** gate the refusal. A refusal is not a wait — there is nothing coming — so it is
    /// said at once, which is what screen 01 already did and what this must not regress.
    static let patience: Duration = .seconds(3)

    /// Where the map opens.
    static func openingRegion(remembered: MapCameraMemory.Snapshot?) -> MKCoordinateRegion {
        guard let remembered else {
            return MapLayout.region(around: MapLayout.defaultCentre)
        }
        return MKCoordinateRegion(
            center: remembered.centre.clLocationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: remembered.latitudeSpan,
                longitudeDelta: remembered.longitudeSpan
            )
        )
    }

    static func showing(remembered: Bool) -> Showing {
        remembered ? .whereYouLeftOff : .theCityFallback
    }

    static func wait(for availability: MapLocationProvider.Availability) -> Wait {
        switch availability {
        case .notAsked: return .permission
        case .waitingForFix: return .fix
        case .located, .denied, .servicesOff: return .none
        }
    }

    /// The whole standing decision.
    ///
    /// `waited` is whether `patience` has elapsed in the current wait. It is deliberately an argument
    /// rather than a clock read inside here: a decision that consults the time is a decision no test
    /// can pin down, and the timing belongs to the view that owns the task.
    static func standing(
        availability: MapLocationProvider.Availability,
        waited: Bool,
        showing: Showing
    ) -> Standing {
        switch availability {
        case .located:
            return .nothing
        case .denied, .servicesOff:
            // Said immediately. Nothing is coming, so there is nothing to be patient about.
            return .refused(availability, showing)
        case .notAsked:
            return waited ? .notAsked(showing) : .nothing
        case .waitingForFix:
            return waited ? .searching(showing) : .nothing
        }
    }
}

// MARK: - The words

/// What screen 01 says about the place it opened on.
///
/// Out of the view for the reason every other `*Copy` in this app is: the sentence a state produces
/// is a decision worth a test, and a test should not have to render a `View` to read it.
enum MapOpeningCopy {

    /// The clause that names what the reader is looking at instead of themselves.
    ///
    /// It is the second half of every sentence here, and it is the half E126 is actually about. "The
    /// map cannot find you" explains the absence; it does not explain the *presence* of a particular
    /// stretch of San Francisco, and a reader who has never been to Dolores Park deserves to be told
    /// that is what they are looking at rather than left to assume the app thinks they are there.
    static func showing(_ showing: MapOpening.Showing) -> String {
        switch showing {
        case .whereYouLeftOff: return "The map is where you last left it."
        case .theCityFallback: return "The map is over the middle of the city."
        }
    }

    /// Unanswered. Different from refused: nobody has said no, they have said nothing.
    ///
    /// No Settings button — `MapLocationNotice` takes one only for a state Settings can fix, and this
    /// one is fixed by the recentre control, which asks. The hint on that control says so
    /// (`MapRecentreCopy.hint(.askable)`).
    static let notAskedTitle = "Cypress has not been given your location"
    static func notAskedMessage(_ place: MapOpening.Showing) -> String {
        "Nothing has answered the location request yet, so there is nowhere to centre the map. "
            + showing(place)
    }

    /// Granted and still looking.
    ///
    /// **This is the sentence E158 is about**, written for the state E158 found being described as a
    /// fix "too weak": the phone has not answered. It says what is true, it says what the map is
    /// doing instead, and it promises the move — a promise `MapHomeView` keeps, because the same
    /// first fix that ends this state is the one that centres the camera.
    static let searchingTitle = "Finding you"
    static func searchingMessage(_ place: MapOpening.Showing) -> String {
        "Cypress has permission and is still waiting for a first fix. " + showing(place)
            + " It will move to you as soon as one arrives."
    }
}
