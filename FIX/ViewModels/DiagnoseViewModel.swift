import Foundation
import Observation

/// State for the Diagnose screen: what the user typed, and whether it is enough
/// to ask about.
@MainActor
@Observable
final class DiagnoseViewModel {
    var device: String = ""
    var problem: String = ""
    var details = ProblemDetails()
    /// Optional context stays collapsed until asked for.
    var isShowingDetails = false

    /// Devices used recently, refreshed when the screen appears.
    private(set) var recentDevices: [String] = []

    /// Enough to diagnose: a device, and a problem described in more than a
    /// word. The threshold is low on purpose — FIX is expected to cope with
    /// vague descriptions, just not with empty ones.
    var canDiagnose: Bool {
        device.nilIfBlank != nil && (problem.nilIfBlank?.count ?? 0) >= 5
    }

    var suggestions: [DeviceSuggestion] {
        DeviceCatalog.suggestions(matching: device, recents: recentDevices)
    }

    func refreshRecents(from library: Library) {
        recentDevices = library.recentDeviceNames()
    }

    func request() -> DiagnosisRequest {
        DiagnosisRequest(device: device, problem: problem, details: details)
    }

    func apply(suggestion: DeviceSuggestion) {
        device = suggestion.name
    }

    /// Clears the problem once a session has been started. The device is kept
    /// deliberately: the same device tends to come back, and retyping it is
    /// friction for no benefit.
    func clearProblem() {
        problem = ""
        details = ProblemDetails()
        isShowingDetails = false
    }
}
