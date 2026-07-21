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
            let layer = try await DataLayer.boot()
            phase = .ready(layer)
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
