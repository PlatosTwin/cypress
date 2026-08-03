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
    /// The composition root's re-boot: tears down `DataLayer` and attaches the (new) choice.
    private let onInventoryChange: () -> Void
    private var downloadTask: Task<Void, Never>?

    init(
        library: CityLibrary,
        downloader: CityDownloader = CityDownloader(),
        onInventoryChange: @escaping () -> Void
    ) {
        self.library = library
        self.downloader = downloader
        self.onInventoryChange = onInventoryChange
    }

    // MARK: - The screen's rows

    var rows: [CityDownloadRow] {
        var rows: [CityDownloadRow] = [.builtIn(isActive: activeCityID == nil)]
        switch catalog {
        case .loaded(let manifest):
            rows += manifest.cities.map { city in
                .published(
                    city: city,
                    state: CityInstallState(
                        published: city,
                        installedVersion: installed.first { $0.id == city.id }?.version
                    ),
                    isActive: activeCityID == city.id,
                    downloadingFraction: downloading?.id == city.id ? downloading?.fraction : nil,
                    lastAttemptFailed: failedCityID == city.id
                )
            }
        case .checking, .unavailable:
            // Disk facts alone — every installed city keeps its no-network affordances.
            rows += installed.map { .installedOffline($0, isActive: activeCityID == $0.id) }
        }
        return rows
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
