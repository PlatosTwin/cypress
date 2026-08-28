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

    /// The city being downloaded and how far along it is. One at a time (ruling §3).
    ///
    /// **Read from the composition root's box, not owned here.** This model is rebuilt on every push
    /// — its catalog is deliberately never persisted (ruling §3) — so a transfer it owned ended when
    /// the reader pressed Back, and ended for good when the process did. Since the transfer moved to
    /// a background session it outlives both, and what this screen does is *read* it.
    var downloading: (id: String, fraction: Double)? {
        guard let inFlight = downloads.inFlight else { return nil }
        return (inFlight.record.id, inFlight.fraction)
    }

    /// The most recent attempt that failed, until the next attempt or screen load clears it. In the
    /// same box, for the same reason: the attempt may have failed while no screen existed.
    var failedCityID: String? { downloads.failedCityID }

    private let library: CityLibrary
    private let downloader: CityDownloader
    /// The app-lifetime transfer. See `downloading`.
    private let service: CityDownloadService
    private let downloads: CityDownloadProgress
    /// The value of `CityDownloadProgress.installCount` this screen has already read the disk for.
    ///
    /// **A watermark rather than a flag anyone clears.** An install can land while this screen does
    /// not exist, or while it is on screen and the reader is watching; either way what the screen
    /// owes is one re-read of the disk per install, and comparing a number it kept against a number
    /// that only ever goes up is the version of that which cannot be got wrong by forgetting.
    private var installsSeen = 0
    /// What the app's own bundle holds (`SeedCities`). The default is `inMainBundle`, which reads
    /// the seed once per process — this model is rebuilt on every push and its default argument is
    /// evaluated more often than that, so the caching lives there rather than being asserted here.
    private let bundledCities: [SeedCities.City]
    /// The composition root's re-boot: tears down `DataLayer` and rebuilds the union over
    /// whatever is now on disk.
    private let onInventoryChange: () -> Void
    /// How many inventory files may be attached beside the bundle at once.
    ///
    /// **Asked of SQLite at open, never hard-coded**. `SQLITE_LIMIT_ATTACHED` is a
    /// compile-time constant of whichever library the platform ships — Apple's is 10 — and a number
    /// written into this file would be a claim nothing rechecks on the day it changes.
    /// `CypressStore.attachedDatabaseLimit` reads it off the live connection and the composition
    /// root passes it here.
    private let installableCityLimit: Int

    /// **Which inventory files the read layer actually opened**, by pack id — the arms of the live
    /// union, minus the bundle, which has no pack id.
    ///
    /// A city on disk whose id is not in here is a file the app declined to read, and the row says
    /// so (`CityDownloadRow.unreadable`). **Derived rather than reported**, and that is what makes it
    /// complete: a file can drop out of the union at two quite separate places — `validateCityFile`
    /// refuses a shape before the union ever sees it, and `InventoryUnion.build` refuses one whose
    /// catalog merge throws — and a screen wired to either one alone would draw `Installed · …` over
    /// a file the map is not reading. What is attached is one fact and it covers both.
    ///
    /// **`nil` means there is no read layer to ask, and no row is marked.** That is the state of
    /// every unit test that builds this model over a temporary library with no `CypressStore` behind
    /// it, and of a preview. It is deliberately not spelled as the empty set: an empty *set* is a
    /// live read layer that opened nothing, which would mark every installed city, and defaulting to
    /// that would turn "this test did not wire a store" into "every one of your cities is broken".
    /// `RootView` passes a real set, and `CityDownloadsFeedbackTests` covers both a set that names
    /// the file and one that does not.
    private let liveInventoryIDs: Set<String>?

    /// - Parameters:
    ///   - service: the composition root's transfer. **Defaulted to one that can reach nothing**,
    ///     over this model's own library — the same fail-safe direction `RemoteAccess` argues for,
    ///     so a model built without one cannot open a socket. `RootView` always passes the real one.
    ///   - downloads: the box that service publishes into. Defaulted with it, and the pair is
    ///     always built together: a service publishing into a box nobody reads is a screen that
    ///     never draws a ring.
    ///
    ///   Neither is a default *argument*, because a default argument is evaluated in the caller's
    ///   context and `CityDownloadProgress` is `@MainActor`.
    init(
        library: CityLibrary,
        downloader: CityDownloader = CityDownloader(),
        service: CityDownloadService? = nil,
        downloads: CityDownloadProgress? = nil,
        bundledCities: [SeedCities.City] = SeedCities.inMainBundle,
        installableCityLimit: Int,
        liveInventoryIDs: Set<String>? = nil,
        onInventoryChange: @escaping () -> Void
    ) {
        self.library = library
        self.downloader = downloader
        let downloads = downloads ?? CityDownloadProgress()
        self.downloads = downloads
        self.service = service ?? CityDownloadService(
            library: library,
            configuration: OfflineSession.configuration(),
            progress: downloads
        )
        self.bundledCities = bundledCities
        self.installableCityLimit = installableCityLimit
        self.liveInventoryIDs = liveInventoryIDs
        self.onInventoryChange = onInventoryChange
    }

    /// Whether another city can be attached beside the ones already installed.
    ///
    /// The bundle occupies one of SQLite's attachment slots and every downloaded pack occupies
    /// another, so the honest count is what is installed against the limit minus the bundle. An
    /// *update* to a city already on the phone replaces its file rather than adding one and is
    /// never blocked by this — see `CityDownloadRow.decide`.
    var hasInstallHeadroom: Bool {
        installed.count < installableCityLimit
    }

    // MARK: - The screen's rows

    /// **One row per city, by construction, from all three sources on both paths.** The catalog,
    /// the download library and the app bundle can each name the same city — and before this round
    /// the bundle was invisible to all of them, which is how the screen came to offer 81 MB of a
    /// city it was already drawing. Every id from all three is folded to a unique, ordered sequence
    /// *before* any row is made, so no path through this model can emit two rows for one city and no
    /// reader is left choosing between two indistinguishable copies of San Francisco.
    ///
    /// **Precedence is the same on both paths, and that is the point.** A published entry describes
    /// the city best, because `installState` gives it the library and the bundle as well. Failing
    /// that, a *downloaded* copy outranks the bundled one — the `active-city` marker can point at it,
    /// so it is the copy that can be in use, removed, or re-attached. The bundle is last, and it is
    /// what makes a city visible at all when neither of the other two knows it.
    ///
    /// The loaded branch briefly went catalog → bundle with the library left out entirely, so a
    /// downloaded, attached, *delisted* city drew its bundled row instead: `In use` and `Remove`
    /// vanished from an 81 MB file that was attached at that moment, and `Built-in inventory` drew
    /// `Use` while something else was in use. The offline branch had it right, and the two now
    /// answer through the same `diskRow(for:)`.
    /// The screen, headed and grouped — what the view draws.
    ///
    /// `rows` stays the flat decision and this is the arrangement of it, so nothing about *what* a
    /// card says depends on which heading it ends up under.
    var sections: [CityDownloadSection] {
        CityDownloadSection.sections(from: rows) { [weak self] row in
            guard let self, case .loaded(let manifest) = self.catalog,
                  let city = manifest.cities.first(where: { $0.id == row.id }),
                  let region = city.region
            else { return nil }
            return (id: region.parentCity, displayName: region.parentCityDisplayName)
        }
    }

    var rows: [CityDownloadRow] {
        var rows: [CityDownloadRow] = [.builtIn(cityNames: bundledCityNames)]
        let bundledIDs = bundledCities.map(\.id)
        let installedIDs = installed.map(\.id)
        switch catalog {
        case .loaded(let manifest):
            let published = Dictionary(
                manifest.cities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
            )
            rows += orderedUniqueIDs(manifest.cities.map(\.id) + installedIDs + bundledIDs)
                .compactMap { id in
                    guard let city = published[id] else {
                        // Not in the catalog: an installed copy, else the bundle's own. Reachable
                        // whenever a manifest is older than the device — a city delisted, or one
                        // published after the bundle was built and not yet in the catalog.
                        return diskRow(for: id)
                    }
                    return .published(
                        city: city,
                        state: installState(for: city),
                        hasInstallHeadroom: hasInstallHeadroom,
                        downloadingFraction: downloading?.id == id ? downloading?.fraction : nil,
                        lastAttemptFailed: failedCityID == id
                    )
                }
        case .checking, .unavailable:
            // Disk facts alone — every installed city keeps its no-network affordances, and the
            // bundle's own cities are disk facts too, which is the whole point of this round: what
            // the app holds does not depend on reaching a bucket. **Ruled by the owner, 2026-08-14**
            // (review finding 9): the offline screen shows the same cities as the online one, so a
            // bundled city keeps its card here rather than disappearing with the network.
            rows += orderedUniqueIDs(installedIDs + bundledIDs).compactMap(diskRow(for:))
        }
        // **A transfer no row above describes still gets one, on every branch.** This is new ground
        // that the background session opened. Before it, a download could only exist while the
        // screen that started it was on top of a catalog it had just fetched; now one can be
        // adopted from a previous launch, survive the reader turning the network off, or be for a
        // pack the catalog in hand does not name.
        //
        // **The test is the finished rows, not the three id sources**, and that is the fix for
        // review finding F2. Guarding on `installedIDs + bundledIDs` was the offline branch's own
        // test written in the offline branch's terms, so the loaded branch — whose ids are
        // `manifest.cities + installedIDs + bundledIDs` — drew nothing at all for a transfer the
        // catalog could not describe: no `Downloading…`, no ring, and no `Cancel`, while
        // `download()`'s `guard downloading == nil` left every other city on the screen inert.
        // Two inputs reach it without a device pathology: a pack delisted from the catalog since
        // the transfer was adopted, and `CityDownloader.fetchManifest()`'s documented fallback to
        // the format-1 catalog, which lists whole cities only and so names no borough at all.
        // Asking whether any row already carries the id answers for both branches at once and
        // cannot drift from either one's notion of where ids come from.
        //
        // No new copy: `Downloading…` and the ring are R43 §3's, and the name comes from the
        // record the transfer is carrying, which the publisher wrote (constraint 15).
        if let inFlight = downloads.inFlight,
           !rows.contains(where: { $0.id == inFlight.record.id }) {
            rows.append(.downloadingOffline(inFlight))
        }
        // **One post-pass over both branches, and that is what makes it complete.** Whether a file
        // opened is not a fact either branch above consults — the catalog does not know, the library
        // knows only that bytes are on disk — so it is applied to the finished rows instead of
        // threaded through two independent row-deciding paths that have drifted apart before
        // (`diskRow(for:)`'s own comment records the last time).
        return rows.map(unreadableIfRefused)
    }

    /// The read layer's verdict on one row, applied last.
    ///
    /// Only an *installed* city can be marked: the built-in card and a bundled city with no
    /// downloaded copy have no file of their own to fail, and the bundle's own arm is not named in
    /// `liveInventoryIDs` at all.
    private func unreadableIfRefused(_ row: CityDownloadRow) -> CityDownloadRow {
        guard let liveInventoryIDs,
              installed.contains(where: { $0.id == row.id }),
              !liveInventoryIDs.contains(row.id)
        else { return row }
        return row.unreadable()
    }

    /// The names the bundled seed states for the cities inside it, for the built-in card's second
    /// line. Read from the file, never listed here (DECISIONS constraint 15); a city the seed cannot
    /// name contributes nothing rather than its id, because this line is prose a reader reads and an
    /// id in the middle of a sentence is not a name.
    private var bundledCityNames: [String] {
        bundledCities.compactMap(\.displayName)
    }

    /// The row for a city the catalog cannot describe: the downloaded copy if there is one, else the
    /// bundled one, else nothing. **One implementation, used by both branches**, which is what keeps
    /// their precedence from drifting apart again.
    private func diskRow(for id: String) -> CityDownloadRow? {
        let installedCopy = installed.first { $0.id == id }
        let bundledCopy = bundledCities.first { $0.id == id }
        // **A city the bundle holds is a bundled city even with a copy downloaded over it** — the
        // downloaded copy is an update to that city, not a peer inventory — and that has to be true
        // offline too, or losing the network moves a card out from under the built-in inventory and
        // gives it a `Remove` button for a city the app cannot remove.
        if let installedCopy, let bundledCopy {
            return .bundledUpdatedOffline(installedCopy, bundled: bundledCopy)
        }
        if let installedCopy { return .installedOffline(installedCopy) }
        return bundledCopy.map(CityDownloadRow.bundled)
    }

    /// The one place a city's state is decided, so the row and the `Download` action can never be
    /// looking at different facts.
    private func installState(for city: CityManifest.City) -> CityInstallState {
        let installedCopy = installed.first { $0.id == city.id }
        return CityInstallState(
            published: city,
            installedVersion: installedCopy?.version,
            // What the installed copy actually holds, from its own receipt — so a re-publish that
            // only changed the source seed's hash is not reported as an update (see
            // `CityInstallState.installedIsCurrent`).
            installedContentRev: installedCopy?.contentRev,
            installedSchemaVersion: installedCopy?.publishedSchemaVersion,
            // The whole city, not its date: a bundled city with no derivable record date is still
            // bundled, and collapsing those two facts is what put the `Download` button back.
            bundled: bundledCities.first { $0.id == city.id }
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
        service.clearFailure()
        do {
            catalog = .loaded(try await downloader.fetchManifest())
        } catch {
            catalog = .unavailable
        }
    }

    /// How many files have landed since launch. The view watches this; see `catchUpOnInstalls`.
    var completedInstallCount: Int { downloads.installCount }

    /// Re-reads the disk if an install has landed since this screen last looked.
    ///
    /// **Called from the view's own render**, because an install can now complete with no screen in
    /// existence and with no view-tree reboot behind it either — a background relaunch has no
    /// `DataLayer` to reboot. `load()` alone would only catch it on the next appearance, so a reader
    /// watching the ring reach 100 % would sit on `Downloading…` until they left and came back.
    /// Idempotent by construction: the watermark only moves when the counter does.
    func catchUpOnInstalls() {
        guard downloads.installCount != installsSeen else { return }
        installsSeen = downloads.installCount
        refreshDiskFacts()
    }

    func download(_ city: CityManifest.City) {
        guard downloading == nil else { return }
        // **The disk is re-read before the decision, not after it.** `installed` is a snapshot taken
        // by `load()` on appearance, and both guards below are computed from it — so a tap decided
        // on a snapshot is a tap decided on whatever was true when the screen opened. That was
        // survivable while every install came from this screen; it is not now, because an install
        // can land from a background transfer, or from a relaunch this screen never saw. Found by
        // the cap test, which refused nothing at all until this line existed.
        refreshDiskFacts()
        // The same property the row draws its button from (`CityInstallState.allowsDownload`).
        // Refusing here as well as declining to draw the button is what makes a second copy of a
        // city the device already holds structurally impossible rather than merely unreachable:
        // there is no caller — a stale view, a future affordance, a test — that can start one.
        let state = installState(for: city)
        guard state.allowsDownload else { return }
        // ── The attachment cap, refused here as well as undrawn ───────────────────────────────
        //
        // `CityDownloadRow.decide` withholds the `Download` button at the cap (R84 D5) and until
        // now that was the *only* statement of the rule — the transfer itself did not consult it.
        // That was survivable while a transfer lived and died inside one screen. It is not now: a
        // background transfer outlives the row that started it, so a tap on a stale view is a file
        // that lands minutes later, in another process, with no slot for it — and the reader is
        // shown `Couldn't be read` for a file that is perfectly readable and merely homeless.
        //
        // Scoped exactly as the button is: only a fetch that would ADD an inventory. An update
        // reuses the slot that city already holds and is never withheld (D5's second sentence),
        // which `state.isOnDevice` is the test for.
        guard hasInstallHeadroom || state.isOnDevice else { return }
        service.start(city)
    }

    func cancelDownload() {
        service.cancel()
    }

    /// Removes a downloaded city, and — for a city the bundle also holds — reverts it to the copy
    /// inside the app.
    ///
    /// **One operation for both affordances**, because they are one operation: what is deleted is
    /// the downloaded file, and what happens next follows from what is left. For a pack the bundle
    /// does not carry, the city leaves the union. For one it does, the bundled rows stop being
    /// shadowed and the city goes back to its included record. `Remove` and `Revert to the included
    /// copy` are two honest names for that, which is why the screen picks between them rather than
    /// this method taking a flag.
    func remove(_ id: String) {
        do {
            try library.remove(id: id)
        } catch {
            return
        }
        refreshDiskFacts()
        // **Always** — see `download`. The union just lost an arm, or a shadow.
        onInventoryChange()
    }

    private func refreshDiskFacts() {
        installed = library.installedCities()
    }
}
