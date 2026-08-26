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
}
