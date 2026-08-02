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
            let layer = try await DataLayer.bootPreferringActiveCity(library: CityLibrary.default())
            phase = .ready(layer)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Tears the layer down and boots again — the Cities screen calls this after changing which
    /// inventory is active (pending city-downloads ruling §1: "switching rebuilds the data
    /// layer"). Setting the phase back is enough: `CypressApp` renders the booting branch, whose
    /// `.task` calls `boot()` exactly as it did at launch, and the fresh `DataLayer` gets a fresh
    /// `RootView` because the root is identity-keyed to the store instance.
    func reboot() {
        guard case .ready = phase else { return }
        phase = .booting
    }
}
