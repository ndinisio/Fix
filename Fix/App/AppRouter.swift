import Foundation
import Observation

/// Cross-screen navigation state: which tab is showing, and a device waiting to
/// be dropped into the Diagnose form.
///
/// A shared instance exists because App Intents run outside the view hierarchy
/// and need somewhere to leave their request. The app uses that same instance,
/// so a Shortcut and a tap on "Troubleshoot" end up in exactly the same place.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case diagnose, devices, history
    }

    static let shared = AppRouter()

    var selectedTab: Tab = .diagnose
    /// Consumed by the Diagnose screen, then cleared.
    var pendingDevice: String?

    /// Opens Diagnose, optionally with the device filled in.
    func troubleshoot(device: String?) {
        pendingDevice = device?.nilIfBlank
        selectedTab = .diagnose
    }

    func consumePendingDevice() -> String? {
        defer { pendingDevice = nil }
        return pendingDevice
    }
}
