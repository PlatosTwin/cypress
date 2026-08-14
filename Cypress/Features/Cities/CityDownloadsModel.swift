import Foundation
import Observation

/// The Cities screen's state: the fetched catalog, the disk facts, one download at a time, and
/// the switch that re-boots the data layer (RULINGS R43 §§1–4).
///
/// Owned by the screen (`@State`), constructed by the composition root — it needs the library,
/// the downloader, and the root's own re-boot hook, none of which a feature may conjure.
@MainActor
@Observable
final class CityDownloadsModel {

    /// The manifest fetch's lifecycle. Never persisted (ruling §3): offline renders disk facts.
    enum Catalog: Equatable {
        case checking
        case loaded(CityManifest)
        case unavailable
    }

    private(set) var catalog: Catalog = .checking
    private(set) var installed: [CityLibrary.InstalledCity] = []
    private(set) var activeCityID: String?
    /// The city being downloaded and how far along it is. One at a time (ruling §3).
    private(set) var downloading: (id: String, fraction: Double)?
    /// The most recent attempt that failed, until the next attempt or screen load clears it.
    private(set) var failedCityID: String?

    private let library: CityLibrary
    private let downloader: CityDownloader
    /// What the app's own bundle holds, read from the bundled seed once (`SeedCities`). Constant
    /// for the life of the process — the bundle is swapped by a build, not by anything on screen.
    private let bundledCities: [SeedCities.City]
    /// The composition root's re-boot: tears down `DataLayer` and attaches the (new) choice.
    private let onInventoryChange: () -> Void
    private var downloadTask: Task<Void, Never>?

    init(
        library: CityLibrary,
        downloader: CityDownloader = CityDownloader(),
        bundledCities: [SeedCities.City] = SeedCities.inBundle(),
        onInventoryChange: @escaping () -> Void
    ) {
        self.library = library
        self.downloader = downloader
        self.bundledCities = bundledCities
        self.onInventoryChange = onInventoryChange
    }

    // MARK: - The screen's rows

    /// **One row per city, by construction.** Three sources can name the same city — the catalog,
    /// the download library, and the app bundle — and before this round the bundle was invisible to
    /// all of them, which is how the screen came to offer 81 MB of a city it was already drawing.
    /// The ids are folded to a unique, ordered sequence *before* any row is made, so no path
    /// through this model can emit two rows for one city and no reader is left choosing between two
    /// indistinguishable copies of San Francisco.
    var rows: [CityDownloadRow] {
        var rows: [CityDownloadRow] = [.builtIn(isActive: activeCityID == nil)]
        switch catalog {
        case .loaded(let manifest):
            let published = Dictionary(
                manifest.cities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            rows += orderedUniqueIDs(manifest.cities.map(\.id) + bundledCities.map(\.id))
                .compactMap { id in
                    guard let city = published[id] else {
                        // Bundled and unpublished: reachable the moment the bundle is built with a
                        // city the catalog has not caught up to.
                        return bundledCities.first { $0.id == id }.map(CityDownloadRow.bundled)
                    }
                    return .published(
                        city: city,
                        state: installState(for: city),
                        isActive: activeCityID == id,
                        downloadingFraction: downloading?.id == id ? downloading?.fraction : nil,
                        lastAttemptFailed: failedCityID == id
                    )
                }
        case .checking, .unavailable:
            // Disk facts alone — every installed city keeps its no-network affordances, and the
            // bundle's own cities are disk facts too, which is the whole point of this round: what
            // the app holds does not depend on reaching a bucket.
            let onDisk = Dictionary(
                installed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            rows += orderedUniqueIDs(installed.map(\.id) + bundledCities.map(\.id))
                .compactMap { id in
                    if let city = onDisk[id] {
                        // A downloaded copy shadows the bundled one (the `active-city` marker
                        // points at it), so it is the copy the row describes.
                        return .installedOffline(city, isActive: activeCityID == id)
                    }
                    return bundledCities.first { $0.id == id }.map(CityDownloadRow.bundled)
                }
        }
        return rows
    }

    /// The one place a city's state is decided, so the row and the `Download` action can never be
    /// looking at different facts.
    private func installState(for city: CityManifest.City) -> CityInstallState {
        CityInstallState(
            published: city,
            installedVersion: installed.first { $0.id == city.id }?.version,
            bundledContentRev: bundledCities.first { $0.id == city.id }?.contentRev
        )
    }

    /// `ids` in first-seen order with duplicates dropped, and `built-in` seeded as already taken so
    /// a city whose id collides with the built-in card's cannot produce a second row either.
    private func orderedUniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = [CityDownloadRow.builtInID]
        return ids.filter { seen.insert($0).inserted }
    }

    /// The line under the header: the fetch in flight, or its failure. Nil once loaded.
    var catalogNote: String? {
        switch catalog {
        case .checking: return CityDownloadsCopy.checking
        case .unavailable: return CityDownloadsCopy.offline
        case .loaded: return nil
        }
    }

    // MARK: - Actions

    /// Fetches the catalog and re-reads the disk. Runs on every appearance; a re-fetch that
    /// fails falls back to disk facts rather than keeping a catalog it can no longer vouch for.
    func load() async {
        refreshDiskFacts()
        failedCityID = nil
        do {
            catalog = .loaded(try await downloader.fetchManifest())
        } catch {
            catalog = .unavailable
        }
    }

    func download(_ city: CityManifest.City) {
        guard downloading == nil else { return }
        // The same property the row draws its button from (`CityInstallState.allowsDownload`).
        // Refusing here as well as declining to draw the button is what makes a second copy of a
        // city the device already holds structurally impossible rather than merely unreachable:
        // there is no caller — a stale view, a future affordance, a test — that can start one.
        guard installState(for: city).allowsDownload else { return }
        failedCityID = nil
        downloading = (city.id, 0)
        downloadTask = Task {
            do {
                let verified = try await downloader.downloadCity(
                    city,
                    to: library.stagingURL,
                    progress: { fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloading?.id == city.id else { return }
                            self.downloading = (city.id, fraction)
                        }
                    }
                )
                try library.install(verifiedFileAt: verified, id: city.id, version: city.version)
                refreshDiskFacts()
                // Updating the inventory in use re-attaches it — the reader already made that
                // choice, and the update is the same choice with fresher data (ruling §1).
                if activeCityID == city.id {
                    onInventoryChange()
                }
            } catch is CancellationError {
                // Canceled by the reader: the temp file is already gone, nothing to say.
            } catch {
                // Partial or impostor bytes never reached the library (`CityDownloader`'s
                // contract); the row reverts and says so.
                failedCityID = city.id
            }
            downloading = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Attaches a downloaded city — or, with nil, the built-in bundle — by marking the choice
    /// and re-booting the data layer (ruling §1).
    func use(_ id: String?) {
        do {
            if let id {
                try library.activate(id: id)
            } else {
                try library.deactivate()
            }
        } catch {
            return
        }
        activeCityID = library.activeCityID()
        onInventoryChange()
    }

    func remove(_ id: String) {
        let wasActive = activeCityID == id
        do {
            try library.remove(id: id)
        } catch {
            return
        }
        refreshDiskFacts()
        // Removing the inventory in use reverts to the bundle immediately (ruling §3).
        if wasActive {
            onInventoryChange()
        }
    }

    private func refreshDiskFacts() {
        installed = library.installedCities()
        activeCityID = library.activeCityID()
    }
}
