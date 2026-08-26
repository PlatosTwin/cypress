import Foundation
import Observation

/// The composition root's state.
///
/// ARCHITECTURE §3: shared services reach views through the SwiftUI environment from a single
/// composition root. `AppModel` owns `DataLayer` and nothing else owns it.
///
/// Booting is asynchronous because opening the store runs migrations and attaches the ~88 MB seed.
/// That attach is sub-millisecond (`SeedDatabase`), so this is a formality rather than a splash
/// screen — but it can fail, and a failure that leaves the map silently empty is worse than one
/// that says so.
@MainActor
@Observable
final class AppModel {

    enum Phase {
        case booting
        case ready(DataLayer)
        case failed(String)
    }

    private(set) var phase: Phase = .booting

    var data: DataLayer? {
        if case .ready(let layer) = phase { return layer }
        return nil
    }

    /// What the Cities screen reads about a transfer. Owned here rather than by the screen, and
    /// **deliberately outside `DataLayer`**: `reboot()` below replaces the layer, and a background
    /// `URLSession` may be constructed only once per identifier per process — a second one traps
    /// with *"A background URLSession with identifier … already exists"*. So the transfer survives
    /// the reboot its own completion causes.
    let downloads: CityDownloadProgress

    /// The transfer, on a session `nsurlsessiond` owns.
    ///
    /// **Built at launch, before anything asks for it**, because that is the contract: a process
    /// relaunched to be told a background download finished has to re-create the session with the
    /// same identifier before the events can be delivered to it. Building it lazily, when the Cities
    /// screen is first pushed, would mean the one launch that exists *only* to receive those events
    /// never built the object they are for.
    ///
    /// **The gate is `RemoteAccess`, and it is the same gate the manifest fetch already uses.** With
    /// the network switched off — which is every DEBUG launch that does not say otherwise, and so
    /// every UI test — this is an ordinary refusing session and no background session is registered
    /// at all. See `RemoteAccess` for why that default is the safe direction.
    let downloadService: CityDownloadService

    /// How a layer is built, so `boot()`'s reconciliation can be exercised without a device.
    ///
    /// **The only seam on this type, and the production value is the call it replaced verbatim.**
    /// `boot()`'s `.booting` reconciliation (see `installLandedDuringBoot`) is a race between a
    /// file landing and a disk read, and a test that cannot say when the disk is read cannot prove
    /// the race is closed — it can only run the two and hope. A closure lets
    /// `BackgroundDownloadTests` land the file at exactly the instant the window is open, over its
    /// own temporary library and database rather than the app's Application Support directory.
    private let makeLayer: @MainActor () async throws -> DataLayer

    init(
        remoteAccess: RemoteAccess = .resolved,
        makeLayer: (@MainActor () async throws -> DataLayer)? = nil
    ) {
        self.makeLayer = makeLayer ?? {
            try await DataLayer.bootOverInstalledCities(library: CityLibrary.default())
        }
        let library = (try? CityLibrary.default())
            ?? CityLibrary(rootURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-cities", isDirectory: true))
        let progress = CityDownloadProgress()
        downloads = progress
        downloadService = CityDownloadService(
            library: library,
            configuration: remoteAccess.allowsNetwork
                ? CityDownloadService.backgroundConfiguration()
                : OfflineSession.configuration(),
            progress: progress
        )
        // The composition root's reboot, handed to the object that knows when an install lands.
        // `reboot()` tears down a `.ready` layer, records the request while one is `.booting` (see
        // `installLandedDuringBoot`), and does nothing at all when the boot failed — so an install
        // in a background relaunch, where `boot()` may never be called, needs no special case here.
        progress.onInstalled = { [weak self] in self?.reboot() }
    }

    /// An install that landed while this boot was in flight, so the layer it produces is already
    /// known to be stale before it is published.
    ///
    /// **The third case, and it is the one review finding F3 caught.** The argument this round
    /// shipped with was that `reboot()` is a no-op unless a layer is booted, so there are two cases
    /// — "there is a union, and it reboots" and "there is no union, and the next boot reads the
    /// disk". `.booting` is neither. `boot()` **suspends inside it**, and
    /// `DataLayer.bootOverInstalledCities` reads `library.installedInventoryFiles()` exactly once,
    /// at the top; a file that lands during that await calls `reboot()`, which declines because the
    /// phase is not `.ready`, and the layer then publishes over a disk it never saw. Nothing
    /// reconciles afterwards — `CityDownloadsModel.catchUpOnInstalls` refreshes *disk facts*, not
    /// the union — so `RootView`'s `liveInventoryIDs` omits the pack for the rest of the process
    /// and the row draws R84's ratified `Couldn't be read` over a byte-perfect file.
    ///
    /// Two inputs reach it: a launch with an almost-finished adopted transfer (`adopt()` is awaited
    /// first, so a transfer at 99 % is republished and then given the whole of the layer boot to
    /// land in), and back-to-back installs, where install *n* reboots and install *n+1* lands
    /// inside the boot that reboot started.
    ///
    /// A flag rather than a re-entrant `reboot()` call after publishing: setting `phase` back to
    /// `.booting` from inside `boot()` would depend on SwiftUI noticing a value that was `.booting`
    /// before and after the turn, and re-running the `.task` that calls this. It would not.
    private var installLandedDuringBoot = false

    func boot() async {
        guard case .booting = phase else { return }
        // **Before the layer, and only once.** Until the session has been asked what it is still
        // carrying, `downloads.inFlight` is nil and means nothing — a Cities screen rendered in that
        // window would draw `Download` for a city already arriving. Asking is one round trip to
        // `nsurlsessiond`; the flag is what stops `reboot()` re-asking on every inventory change.
        if !downloads.hasAdopted {
            await downloadService.adopt()
        }
        // Loops rather than publishes-then-reboots, so the reader never sees a layer that is
        // already known to be missing a file. Each pass reads the disk again; the loop ends the
        // first time nothing lands while it is reading, which is the same condition every launch
        // that installs nothing meets on its first pass.
        while true {
            installLandedDuringBoot = false
            do {
                let layer = try await makeLayer()
                if installLandedDuringBoot { continue }
                phase = .ready(layer)
                return
            } catch {
                phase = .failed(String(describing: error))
                return
            }
        }
    }

    /// Tears the layer down and boots again — the Cities screen calls this after any install or
    /// removal.
    ///
    /// **A whole-layer reboot, deliberately, and it is the honest one.** Adding or removing an arm
    /// invalidates more than the files: the union's views are rebuilt over a different set of
    /// schemas, the canonical species catalog is renumbered, and every prepared statement in the
    /// connection's cache was compiled against the old views. Dropping and recreating in place
    /// would have to get all three right at once, on a connection other code may be mid-read on;
    /// booting again gets them right by construction, and it is the path every launch already
    /// takes. It costs the tens of milliseconds `InventoryUnion.build` measures, once, at the
    /// moment the reader pressed a button and is already waiting.
    ///
    /// Setting the phase back is enough: `CypressApp` renders the booting branch, whose `.task`
    /// calls `boot()` exactly as it did at launch, and the fresh `DataLayer` gets a fresh
    /// `RootView` because the root is identity-keyed to the store instance.
    ///
    /// **`.booting` is not "nothing to do", it is "too late to say so this way"** — see
    /// `installLandedDuringBoot`. A boot in flight has already read the disk, so a request arriving
    /// inside it is recorded and honoured by that boot rather than dropped. `.failed` is genuinely
    /// nothing to do: there is no union to be stale.
    func reboot() {
        guard case .ready = phase else {
            if case .booting = phase { installLandedDuringBoot = true }
            return
        }
        phase = .booting
    }
}
