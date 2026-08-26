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

    init(remoteAccess: RemoteAccess = .resolved) {
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
        // `reboot()` refuses unless the layer is `.ready`, which is what makes an install in a
        // background relaunch — where nothing was ever booted — a no-op rather than a special case.
        progress.onInstalled = { [weak self] in self?.reboot() }
    }

    func boot() async {
        guard case .booting = phase else { return }
        // **Before the layer, and only once.** Until the session has been asked what it is still
        // carrying, `downloads.inFlight` is nil and means nothing — a Cities screen rendered in that
        // window would draw `Download` for a city already arriving. Asking is one round trip to
        // `nsurlsessiond`; the flag is what stops `reboot()` re-asking on every inventory change.
        if !downloads.hasAdopted {
            await downloadService.adopt()
        }
        do {
            let layer = try await DataLayer.bootOverInstalledCities(library: CityLibrary.default())
            phase = .ready(layer)
        } catch {
            phase = .failed(String(describing: error))
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
    func reboot() {
        guard case .ready = phase else { return }
        phase = .booting
    }
}
