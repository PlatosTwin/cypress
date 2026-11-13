import Foundation

/// Drains the outbox when the connection becomes unmetered and a photograph is waiting for it.
///
/// **The owner's decision of 2026-11-13 for F35: waiting photos upload by themselves when wi-fi
/// returns.** Without this, a photograph held back on cellular would wait until the volunteer saved
/// something else, tapped retry, or brought the app to the front, and screen 17 would go on saying
/// "waiting for wi-fi" on wi-fi.
///
/// `DataLayer.boot` makes one per layer, and the layer owns it. When the last copy of the layer is
/// released (`AppModel.reboot()` replaces it), this object goes too and its listening task is
/// cancelled, so a replaced layer never drains in the background.
///
/// Overlapping drains are safe: `OutboxQueue.drain` returns an empty report while another is
/// running.
public final class OutboxWifiWatcher: Sendable {
    private let task: Task<Void, Never>

    public init(queue: OutboxQueue, networkPath: any NetworkPathSource) {
        // The stream is made here, before `init` returns, and not inside the task: a change that
        // arrived between `init` and the task's first instruction would otherwise be lost.
        let changes = networkPath.unmeteredChanges()
        task = Task.detached(priority: .utility) {
            for await unmetered in changes {
                guard unmetered else { continue }
                _ = try? await queue.drainIfPhotosAwaitWifi()
            }
        }
    }

    deinit {
        task.cancel()
    }
}
