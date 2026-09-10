//
//  GrowthHistoryModel.swift
//  Cypress — Features/GrowthHistory
//
//  Screen 11's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no GRDB, no network (ARCHITECTURE §4).
//
//  It reads `GET /trees/{id}`, whose payload already carries `measurements` as the **whole** series
//  ("The full measurement series", `TreeProfile`; `ContributionStore.measurements` has no `LIMIT`
//  "and there must not be"). That matters here more than anywhere: a chart drawn over page one of a
//  series is a growth curve with its beginning missing, and nothing on the card would say so
//  (ERRATA E38).
//

import Foundation
import Observation

@MainActor
@Observable
final class GrowthHistoryModel {

    enum Phase: Equatable {
        case loading
        case loaded(TreeProfile)
        case failed(APIError)
    }

    private(set) var phase: Phase = .loading

    /// The row whose withdraw control has been tapped, and therefore the row the confirmation is
    /// about. Nil whenever no question is on screen — one tap withdraws nothing.
    var pendingWithdrawal: GrowthLogRow?

    /// Set when a withdrawal was refused or failed. Cleared at the start of the next attempt, so
    /// the sentence on screen is always about the most recent one.
    private(set) var withdrawError: String?

    let treeID: UUID
    private let api: any CypressAPI
    private let calendar: Calendar

    init(treeID: UUID, api: any CypressAPI, calendar: Calendar = .current) {
        self.treeID = treeID
        self.api = api
        self.calendar = calendar
    }

    var presentation: GrowthHistoryPresentation? {
        guard case let .loaded(profile) = phase else { return nil }
        return GrowthHistoryPresentation(profile: profile, calendar: calendar)
    }

    func load() async {
        do {
            phase = .loaded(try await api.treeProfile(id: treeID))
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// The load writes nothing, so a retry is free.
    func reload() async {
        phase = .loading
        await load()
    }

    /// Withdraws one reading, having been asked twice (report F27).
    ///
    /// **The re-read afterwards is not a refresh, it is the screen** — and it is `TreePhotosModel
    /// .delete`'s pattern for the same reason plus one. Everything on 11 is derived from the
    /// series: which chart cards exist, where the axis starts, what the baseline label says, which
    /// legend pills are drawn, and whether `noChartReason` has anything to say. Patching the row
    /// out of a local array would leave every one of those computed from a set that no longer
    /// matches the record. The extra reason is `withdrawableMeasurementIDs`, which is a fact only
    /// the store holds.
    ///
    /// **`phase` is not reset to `.loading` first**, unlike `reload()`. A withdrawal is a change to
    /// a screen the reader is standing on, and blanking the whole of it to a spinner for the length
    /// of one read makes a small edit look like a navigation. `load()` overwrites `phase` when the
    /// read returns.
    func withdraw(_ measurementID: UUID) async {
        withdrawError = nil
        do {
            _ = try await api.withdrawMeasurement(id: measurementID)
            await load()
        } catch {
            withdrawError = GrowthHistoryCopy.withdrawFailed
        }
    }
}
