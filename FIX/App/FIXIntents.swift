import AppIntents
import Foundation

/// "Troubleshoot my iPhone" — opens FIX with the device already filled in.
///
/// Deliberately the only intent. FIX cannot diagnose anything without a problem
/// description, so an intent that claimed to fix something from a phrase alone
/// would be promising more than it can do. This one saves the first step and
/// hands over to the app.
struct TroubleshootDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Troubleshoot a Device"
    static let description = IntentDescription(
        "Opens FIX ready to diagnose a problem with a device."
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Device", requestValueDialog: "Which device?")
    var device: String?

    init() {}

    init(device: String?) {
        self.device = device
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.troubleshoot(device: device)
        return .result()
    }
}

struct FIXShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TroubleshootDeviceIntent(),
            phrases: [
                "Troubleshoot a device with \(.applicationName)",
                "Diagnose a problem with \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Troubleshoot",
            systemImageName: "stethoscope"
        )
    }
}
