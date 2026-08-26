import Foundation
import Testing
@testable import Cypress

/// What changes on the Cities screen once a transfer outlives the screen that started it.
///
/// The transfer's own machinery — the record, the verification, adoption, cancellation — is in
/// `CityDownloadTests` and `CityDownloadsFeedbackTests`. What is here is the consequences: a
/// download that finishes with nobody watching, a download the catalog cannot describe, and the
/// attachment cap, which stopped being a drawing rule the moment a tap could land a file minutes
/// later in another process.
@Suite("Background city downloads")
@MainActor
struct BackgroundDownloadTests {

    static func entry(
        id: String,
        version: String = "s17-r2026-08-22.02-ac7b1ccc",
        displayName: String = "Manhattan",
        bytes: Int64 = 1024
    ) -> CityManifest.City {
        CityManifest.City(
            id: id, displayName: displayName, coverage: "full", treeCount: 1,
            schemaVersion: 17, version: version,
            path: "cities/\(id)/\(version)/\(id).sqlite",
            bytes: bytes, sha256: String(repeating: "00", count: 32)
        )
    }

    static func tempLibrary() throws -> CityLibrary {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgdl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return CityLibrary(rootURL: root)
    }

    /// A model over a library and a service that can reach nothing — every test here is about what
    /// the model *decides*, and none of them wants bytes to move.
    static func model(
        library: CityLibrary,
        installableCityLimit: Int = 9,
        downloads: CityDownloadProgress? = nil
    ) -> (CityDownloadsModel, CityDownloadProgress, CityDownloadService) {
        // Not a default argument: a default argument is evaluated in the caller's context, and this
        // type is `@MainActor`.
        let downloads = downloads ?? CityDownloadProgress()
        let service = CityDownloadService(
            library: library,
            configuration: OfflineSession.configuration(),
            progress: downloads
        )
        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(session: OfflineSession.make()),
            service: service,
            downloads: downloads,
            bundledCities: [],
            installableCityLimit: installableCityLimit,
            onInventoryChange: {}
        )
        return (model, downloads, service)
    }

    /// Puts `count` plausible installed cities on disk, so the cap can be reached without moving a
    /// byte. Only the directory shape matters — `installedCities()` counts version directories.
    static func fillLibrary(_ library: CityLibrary, count: Int) throws {
        for index in 0..<count {
            let id = "filler-\(index)"
            let url = library.fileURL(id: id, version: "s17-r2026-08-22")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
    }

    // MARK: - The attachment cap

    /// **At the cap, the transfer is refused and not merely undrawn** (RULINGS R84 D5).
    ///
    /// This was a drawing rule alone — `CityDownloadRow.decide` withheld the button and
    /// `CityDownloadsModel.download` never consulted the count. That was survivable while a
    /// transfer lived and died inside the screen that started it; it is not now. A background
    /// transfer outlives its row, so a tap on a stale view is a file that lands minutes later, in
    /// another process, with no attachment slot for it — and the reader is shown `Couldn't be read`
    /// for a file that reads perfectly well and is merely homeless.
    @Test("a download that would exceed the attachment cap does not start")
    func theCapRefusesTheTransferAndNotOnlyTheButton() throws {
        let library = try Self.tempLibrary()
        try Self.fillLibrary(library, count: 3)
        let (model, downloads, _) = Self.model(library: library, installableCityLimit: 3)

        model.download(Self.entry(id: "us-ny-nyc-manhattan"))
        #expect(
            downloads.inFlight == nil,
            "a transfer started with every attachment slot taken — it will land with nowhere to go"
        )
    }

    /// The control, and the half that makes the test above a refusal rather than a model that
    /// refuses everything.
    @Test("with a slot free, the same download starts")
    func belowTheCapTheSameDownloadStarts() throws {
        let library = try Self.tempLibrary()
        try Self.fillLibrary(library, count: 2)
        let (model, downloads, _) = Self.model(library: library, installableCityLimit: 3)

        model.download(Self.entry(id: "us-ny-nyc-manhattan"))
        #expect(downloads.inFlight?.record.id == "us-ny-nyc-manhattan")
    }

    /// **An update is never withheld by the cap** — D5's second sentence. It replaces the file in
    /// the slot that city already holds, so a reader at the cap can still take a newer record for
    /// everything they have.
    @Test("an update to a city already installed is not refused at the cap")
    func anUpdateIsNotWithheldAtTheCap() throws {
        let library = try Self.tempLibrary()
        try Self.fillLibrary(library, count: 3)
        let (model, downloads, _) = Self.model(library: library, installableCityLimit: 3)

        // `filler-0` is on disk at an older version, so this is an update rather than an addition.
        model.download(Self.entry(id: "filler-0", version: "s17-r2026-09-01"))
        #expect(
            downloads.inFlight?.record.id == "filler-0",
            "an update was refused at the cap, though it reuses a slot rather than taking one"
        )
    }

    // MARK: - A transfer with no catalog behind it

    /// **The offline screen says a download is running**, which it could not previously do.
    ///
    /// Before the background session a transfer existed only while the screen that started it stood
    /// on a catalog it had just fetched. One can now be adopted from a previous launch, or outlive
    /// the network going away, and a Cities screen saying nothing about the bytes currently
    /// arriving would be exactly the silence R43 §3 wrote the `Downloading…` line to prevent.
    @Test("a transfer the catalog cannot describe still draws a row")
    func anAdoptedTransferIsDrawnWithNoCatalog() throws {
        let library = try Self.tempLibrary()
        let (model, _, _) = Self.model(library: library)
        let city = Self.entry(id: "us-ny-nyc-manhattan", displayName: "Manhattan")

        // No catalog has been fetched: `model.catalog` is `.checking`, the offline branch.
        model.download(city)

        let row = try #require(
            model.rows.first { $0.id == city.id },
            "the offline screen drew no row for a transfer that is running"
        )
        // The publisher's name, carried on the transfer — never an id this layer prettified.
        #expect(row.title == "Manhattan")
        #expect(row.stateLine == CityDownloadsCopy.downloading)
        #expect(row.progress != nil, "the row has no ring, so it states a download and shows none")
        #expect(row.affordances == [.cancel])
        #expect(!row.isOnDevice, "an unfinished download filed itself under On this phone")
    }

    /// A city already on disk keeps its own row rather than acquiring a second one — the download
    /// row above must not become a way to draw a city twice.
    @Test("a transfer for a city already installed adds no second row")
    func anInFlightUpdateDoesNotDuplicateItsRow() throws {
        let library = try Self.tempLibrary()
        try Self.fillLibrary(library, count: 1)
        let (model, _, _) = Self.model(library: library)

        model.download(Self.entry(id: "filler-0", version: "s17-r2026-09-01"))

        #expect(model.rows.filter { $0.id == "filler-0" }.count == 1)
    }

    // MARK: - An install that lands with nobody watching

    /// **The screen re-reads the disk when an install lands, without being told to look.**
    ///
    /// A transfer completes on URLSession's queue now — possibly while the reader is watching the
    /// ring, possibly in a process with no screen at all — so `load()`, which runs once per
    /// appearance, is no longer the only moment the disk can change under this model.
    @Test("an install that lands while the screen is standing still is picked up")
    func aCompletedInstallIsPickedUpWithoutAReload() throws {
        let library = try Self.tempLibrary()
        let (model, downloads, _) = Self.model(library: library)
        #expect(model.rows.count == 1, "only the built-in card, before anything is installed")

        // A file appears on disk the way a completed background transfer leaves one, and the box
        // records the install exactly as `CityDownloadService.settle` does.
        try Self.fillLibrary(library, count: 1)
        downloads.recordInstall()
        model.catchUpOnInstalls()

        #expect(
            model.rows.contains { $0.id == "filler-0" },
            "the screen did not notice a file that landed while it was on screen"
        )
    }

    /// **Idempotent, and it has to be**: the view calls this from a change handler, so a re-render
    /// with no install behind it must not re-read the disk.
    @Test("catching up on installs does nothing when nothing has landed")
    func catchingUpIsIdempotent() throws {
        let library = try Self.tempLibrary()
        let (model, downloads, _) = Self.model(library: library)
        downloads.recordInstall()
        model.catchUpOnInstalls()

        // The disk changes, and nothing tells the model — so it must not notice.
        try Self.fillLibrary(library, count: 1)
        model.catchUpOnInstalls()
        #expect(
            !model.rows.contains { $0.id == "filler-0" },
            "the model re-read the disk with no install recorded, so the watermark is not doing anything"
        )
    }

    /// **The composition root's reboot fires once per file that lands, not once per settled
    /// transfer.** A failed or cancelled transfer changes nothing the union reads, and rebooting the
    /// data layer over it would tear down the reader's screen for no reason at all.
    @Test("the union is rebooted once per install, and never for a failure")
    func theRebootHookFiresOncePerInstall() {
        let downloads = CityDownloadProgress()
        var reboots = 0
        downloads.onInstalled = { reboots += 1 }

        downloads.apply(failedCityID: "us-ny-nyc-queens")
        #expect(reboots == 0, "a failed transfer rebooted the data layer")

        downloads.recordInstall()
        downloads.recordInstall()
        #expect(reboots == 2)
        #expect(downloads.installCount == 2)
    }

    // MARK: - A loaded catalog that cannot describe the transfer (review finding F2)

    /// **A `.loaded` catalog is not a catalog that names every transfer.**
    ///
    /// The in-flight row was appended inside the offline branch only, guarded on the ids *that*
    /// branch builds rows from. So with a catalog in hand, a transfer the catalog could not
    /// describe drew nothing at all — no `Downloading…`, no ring and, worst of the three, no
    /// `Cancel` — while `CityDownloadsModel.download`'s `guard downloading == nil` is global and
    /// left every other city on the screen inert until the transfer finished or the app was
    /// force-quit. Silence plus an inert screen is exactly what R43 §3 wrote the `Downloading…`
    /// line to prevent, fixed on one branch and left on the other.
    ///
    /// **Two inputs reach it without a device pathology**, and neither needs a delisted pack to be
    /// hypothetical: a pack delisted from the catalog since the transfer was adopted, and
    /// `CityDownloader.fetchManifest()`'s documented fallback to the format-1 catalog, which by
    /// construction lists whole cities only and so names no borough at all. This test builds the
    /// first, because a one-entry catalog is the same shape either way from the model's side.
    @Test("a loaded catalog still draws the transfer it cannot describe")
    func aLoadedCatalogDrawsTheTransferItCannotDescribe() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgdl-loaded-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A real one-entry format-2 catalog, fetched the way the screen fetches one. It names
        // Manhattan and nothing else.
        let bucket = root.appendingPathComponent("bucket", isDirectory: true)
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        try Data(
            CityDownloadsFeedbackTests.manifestJSON(
                contentRev: "2026-08-22", version: "s17-r2026-08-22-ac7b1ccc"
            ).utf8
        ).write(to: bucket.appendingPathComponent("manifest-v2.json"))

        let library = CityLibrary(rootURL: root.appendingPathComponent("lib", isDirectory: true))
        let downloads = CityDownloadProgress()
        let model = CityDownloadsModel(
            library: library,
            downloader: CityDownloader(baseURL: bucket),
            service: CityDownloadService(
                library: library,
                configuration: OfflineSession.configuration(),
                progress: downloads
            ),
            downloads: downloads,
            bundledCities: [],
            installableCityLimit: 9,
            onInventoryChange: {}
        )
        await model.load()
        guard case .loaded = model.catalog else {
            Issue.record("the catalog did not load, so this test is not about the loaded branch")
            return
        }

        // Brooklyn is arriving, and the catalog in hand has never heard of it. Published straight
        // into the box, which is what `adopt()` does on a launch that inherits a transfer.
        let brooklyn = Self.entry(id: "us-ny-nyc-brooklyn", displayName: "Brooklyn")
        downloads.apply(inFlight: .init(record: CityDownloadRecord(brooklyn), fraction: 0.25))

        let row = try #require(
            model.rows.first { $0.id == brooklyn.id },
            "a loaded catalog drew no row at all for the transfer that is running"
        )
        // The publisher's name, carried on the transfer — never an id this layer prettified.
        #expect(row.title == "Brooklyn")
        #expect(row.stateLine == CityDownloadsCopy.downloading)
        #expect(row.progress == 0.25, "the row states a download and shows no ring")
        #expect(
            row.affordances == [.cancel],
            "the reader cannot call off a transfer that has taken the whole screen hostage"
        )

        // The control, and it is what makes the assertions above an addition rather than a screen
        // that draws a download row for everything: the catalog's own city is still drawn once, by
        // the catalog, with the affordance the catalog decided.
        let manhattan = model.rows.filter { $0.id == "us-ny-nyc-manhattan" }
        #expect(manhattan.count == 1)
        #expect(manhattan.first?.affordances == [.download])
    }

    // MARK: - An install that lands while the layer is booting (review finding F3)

    /// The two halves of the race, held by the test rather than by the clock.
    @MainActor
    final class BootProbe {
        var builds = 0
        /// Run once, **after** a layer has been built and **before** it is published — the window
        /// in which `AppModel.phase` is `.booting` and the disk read behind the layer is already
        /// history.
        var duringBuild: (() -> Void)?
    }

    /// **An install that lands while the layer is booting is reconciled, not dropped.**
    ///
    /// The round shipped with the claim that `reboot()` is a no-op unless a layer is booted, so
    /// there are two cases — a live union that reboots, and no union, where the next boot reads the
    /// disk. Review finding F3 found the third: `phase == .booting`. `boot()` suspends inside it,
    /// `DataLayer.bootOverInstalledCities` reads `installedInventoryFiles()` exactly once at the
    /// top, and a file landing in that window called a `reboot()` that declined — after which the
    /// boot published a layer built before the file existed and nothing reconciled it. The reader
    /// was then shown R84's ratified `Couldn't be read` over a byte-perfect file, for the rest of
    /// the process, because `RootView` derives `liveInventoryIDs` from the union's arms.
    ///
    /// **The window is held open deliberately rather than raced for.** `makeLayer` is `AppModel`'s
    /// one seam; the probe installs the pack and calls `reboot()` at the instant the shipped code
    /// would have thrown the request away, so this asserts the reconciliation rather than sampling
    /// a timing. Both halves are asserted: that a second layer was built at all, and — the fact the
    /// reader actually sees — that the published union has the pack's arm in it.
    @Test("an install that lands while the layer is booting is picked up by that boot")
    func anInstallDuringBootIsReconciled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgdl-bootrace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let library = CityLibrary(rootURL: root.appendingPathComponent("cities", isDirectory: true))
        let databaseURL = root.appendingPathComponent("cypress.sqlite")

        // A pack shaped like a published s17 one, so `validateCityFile` accepts it and the union
        // attaches it — the same fixture `CumulativeInventoryTests` builds its arms from.
        let packURL = root.appendingPathComponent("manhattan-staged.sqlite")
        try CumulativeInventoryTests.seed(
            at: packURL,
            trees: (1...3).map {
                CumulativeInventoryTests.TreeRow(
                    id: Int64($0), idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: nil
                )
            },
            // **No species rows, deliberately.** This test attaches its pack beside the *real*
            // bundled seed rather than beside another fixture, and `InventoryUnion`'s canonical
            // catalog is keyed by `species.uuid` with a UNIQUE index on `scientific_name` — so a
            // fixture species carrying a real name under a fixture uuid is refused by that index
            // and the whole arm drops out. Measured: `UNIQUE constraint failed:
            // species.scientific_name`, which is a refusal of the fixture and not of the fix.
            // The union does not need this pack's trees to have species to attach its arm.
            species: [],
            contentRev: "2026-08-22",
            packID: "us-ny-nyc-manhattan"
        )

        let probe = BootProbe()
        let model = AppModel(makeLayer: {
            probe.builds += 1
            let layer = try await DataLayer.bootOverInstalledCities(
                databaseURL: databaseURL, library: library
            )
            // The disk read that produced `layer` is behind us and `phase` is still `.booting`:
            // this is the window, and it is exactly where the dropped request used to go.
            probe.duringBuild?()
            return layer
        })
        probe.duringBuild = { [weak model] in
            probe.duringBuild = nil
            do {
                _ = try library.install(
                    verifiedFileAt: packURL,
                    id: "us-ny-nyc-manhattan",
                    version: "s17-r2026-08-22-ac7b1ccc"
                )
            } catch {
                // Loud rather than swallowed: a fixture that failed to install would make the
                // assertions below fail for a reason that is not the one they are about.
                Issue.record("the fixture pack did not install: \(error)")
            }
            // Precisely what `CityDownloadProgress.onInstalled` does when a file lands.
            model?.reboot()
        }

        await model.boot()

        #expect(
            probe.builds == 2,
            "the boot published the layer it had already built, so the install was dropped"
        )
        let layer = try #require(model.data, "the app never reached .ready")
        let arms = Set((layer.store.inventory?.arms ?? []).map(\.id))
        #expect(
            arms.contains("us-ny-nyc-manhattan"),
            """
            the published union has arms \(arms.sorted()) — the pack that landed during the boot is \
            not among them, so its row draws `Couldn't be read` over a file that is perfectly good
            """
        )
    }
}
