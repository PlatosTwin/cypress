//
//  SpeciesModel.swift
//  Cypress — Features/Species
//
//  Screen 07's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no GRDB, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class SpeciesModel {

    /// Where the read is.
    ///
    /// An enum rather than an optional plus a boolean, because "loading" and "this species does not
    /// exist" have to be distinguishable: 07 is reachable by id from a grove tile, and a stale tile
    /// pointing at a species the seed no longer carries has to say so rather than sit blank.
    enum Phase: Equatable {
        case loading
        case loaded(SpeciesPresentation)
        case failed
    }

    private(set) var phase: Phase = .loading

    let speciesID: UUID
    private let api: any CypressAPI
    private let now: () -> Date
    private let calendar: Calendar

    init(
        speciesID: UUID,
        api: any CypressAPI,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.speciesID = speciesID
        self.api = api
        self.now = now
        self.calendar = calendar
    }

    /// The calendar the seasonal callout names its month in. The view needs it to spell the month.
    var monthCalendar: Calendar { calendar }

    // MARK: - Loading

    /// One read, and it is the whole screen.
    ///
    /// A failure is `.failed`, never a half-page: the species record is the subject of every block
    /// below the hero, so there is nothing honest to draw without it.
    ///
    /// The fix is a parameter rather than a stored property because it *arrives*. The page opens
    /// before CoreLocation has a first fix, so a read taken at `.task` time would permanently show
    /// a page with no `Near you` card on a device that got a fix a second later — which is what
    /// happened the first time this screen ran on the simulator. `SpeciesView` reloads once when
    /// the fix appears; see its `.task(id:)`.
    func load(near coordinate: Coordinate?) async {
        do {
            let guide = try await api.speciesGuide(id: speciesID, near: coordinate)
            phase = .loaded(
                SpeciesPresentation(guide: guide, month: calendar.component(.month, from: now()))
            )
        } catch {
            phase = .failed
        }
    }

    /// Re-reads after a failure. The load is idempotent — it writes nothing — so a retry is free.
    func retry(near coordinate: Coordinate?) async {
        phase = .loading
        await load(near: coordinate)
    }
}
