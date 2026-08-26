import SwiftUI

/// The one way FIX shows a failure.
///
/// Built on `ContentUnavailableView` so it matches the empty states elsewhere
/// in the app and in the system. "Try Again" appears only when trying again
/// could actually change the outcome.
struct ErrorStateView: View {
    let error: APIError
    var retry: (() async -> Void)?
    var openSettings: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.symbolName)
        } description: {
            Text(error.guidance)
        } actions: {
            if let retry, error.isRetryable {
                Button("Try Again") {
                    Task { await retry() }
                }
                .buttonStyle(.borderedProminent)
            }
            if let openSettings, error == .notConfigured || error == .unauthorized {
                Button("Open Settings", action: openSettings)
            }
        }
    }
}

#Preview("Offline") {
    ErrorStateView(error: .offline, retry: {})
}

#Preview("Not configured") {
    ErrorStateView(error: .notConfigured, retry: {}, openSettings: {})
}
