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

    func boot() async {
        guard case .booting = phase else { return }
        do {
            let layer = try await DataLayer.bootOverInstalledCities(library: CityLibrary.default())
            phase = .ready(layer)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Tears the layer down and boots again — the Cities screen calls this after any install or
    /// removal (RULING D8).
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
