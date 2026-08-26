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

    /// Anything not supplied is built here rather than in the signature:
    /// default argument expressions are evaluated outside the initialiser's
    /// isolation, so a main-actor type cannot be one. Previews and tests pass
    /// their own services in.
    init(
        configuration: AppConfiguration = .current,
        settings: AppSettings? = nil,
        networkMonitor: NetworkMonitor? = nil,
        troubleshooting: (any TroubleshootingServicing)? = nil
    ) {
        self.configuration = configuration
        self.settings = settings ?? AppSettings()
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
        self.troubleshooting = troubleshooting ?? Self.makeTroubleshooting(for: configuration)
    }

    /// Builds the diagnosis pipeline for a configuration.
    ///
    /// The provider list is a fallback chain with one provider today; adding a
    /// second is a change to this array and nothing else. With nothing
    /// configured, `UnconfiguredAIService` makes that an ordinary error rather
    /// than a special case threaded through the app.
    private static func makeTroubleshooting(
        for configuration: AppConfiguration
    ) -> any TroubleshootingServicing {
        let providers: [any AIService] = configuration.ai.map {
            [GroqService(transport: $0, model: configuration.groqModel)]
        } ?? []
        let ai: any AIService = providers.isEmpty
            ? UnconfiguredAIService()
            : FallbackAIService(providers: providers)
        let videoSearch = configuration.video.map { YouTubeVideoSearchService(transport: $0) }
        return TroubleshootingService(ai: ai, videoSearch: videoSearch)
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
