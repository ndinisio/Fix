import Foundation
import Network
import Observation

/// Tracks whether the device has a usable connection.
///
/// Used to tell the user *before* they tap Diagnose that a new diagnosis needs
/// a connection, and to keep the offline message honest — history, saved
/// devices and past answers all keep working without one.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected: Bool = true

    // `nonisolated(unsafe)` because `deinit` runs outside the main actor and
    // has to reach these. Both are safe to touch from any thread: NWPathMonitor
    // and DispatchQueue are internally synchronised, and neither is mutated
    // after this initialiser.
    @ObservationIgnored nonisolated(unsafe) private let monitor = NWPathMonitor()
    @ObservationIgnored nonisolated(unsafe) private let queue = DispatchQueue(
        label: "com.fix.network-monitor"
    )

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isConnected != connected else { return }
                self.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
