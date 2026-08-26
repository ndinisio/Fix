import Foundation
import Observation

/// Wires the app's services together once, at launch.
///
/// Everything above this reads `TroubleshootingServicing`, so which provider is
/// in use — or whether one is configured at all — is invisible to the rest of
/// the app.
@MainActor
@Observable
final class ServiceContainer {
    let configuration: AppConfiguration
    let networkMonitor: NetworkMonitor
    let settings: AppSettings
    let troubleshooting: any TroubleshootingServicing

    init(
        configuration: AppConfiguration = .current,
        settings: AppSettings = AppSettings(),
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.configuration = configuration
        self.settings = settings
        self.networkMonitor = networkMonitor

        // A fallback chain with one provider today. Adding a second is a change
        // to this array and nothing else.
        let providers: [any AIService] = configuration.ai.map {
            [GroqService(transport: $0, model: configuration.groqModel)]
        } ?? []
        let ai: any AIService = providers.isEmpty
            ? UnconfiguredAIService()
            : FallbackAIService(providers: providers)
        let videoSearch = configuration.video.map { YouTubeVideoSearchService(transport: $0) }

        self.troubleshooting = TroubleshootingService(ai: ai, videoSearch: videoSearch)
    }

    /// For previews and tests, where the services are supplied directly.
    init(
        configuration: AppConfiguration,
        settings: AppSettings,
        networkMonitor: NetworkMonitor,
        troubleshooting: any TroubleshootingServicing
    ) {
        self.configuration = configuration
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.troubleshooting = troubleshooting
    }
}

/// Stands in when no provider is configured, so the failure is a clear,
/// consistent error instead of a special case threaded through the app.
struct UnconfiguredAIService: AIService {
    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis {
        throw APIError.notConfigured
    }

    func carePlan(for device: String) async throws -> CarePlan {
        throw APIError.notConfigured
    }
}
