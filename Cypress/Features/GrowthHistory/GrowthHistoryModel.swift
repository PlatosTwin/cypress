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
}
