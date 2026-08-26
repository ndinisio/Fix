import Foundation

/// Tries each provider in order and returns the first successful answer.
///
/// Only one provider is configured today, so this usually wraps a single
/// service and costs nothing. It exists so that adding a second provider later
/// is a change to one initialiser rather than a change to every call site.
final class FallbackAIService: AIService {
    private let providers: [any AIService]

    init(providers: [any AIService]) {
        self.providers = providers
    }

    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis {
        try await attempt { try await $0.diagnose(request) }
    }

    func carePlan(for device: String) async throws -> CarePlan {
        try await attempt { try await $0.carePlan(for: device) }
    }

    private func attempt<T>(
        _ work: (any AIService) async throws -> T
    ) async throws -> T {
        guard !providers.isEmpty else { throw APIError.notConfigured }
        var errors: [APIError] = []
        for provider in providers {
            do {
                return try await work(provider)
            } catch let error as APIError {
                // A cancelled request is the user's decision, not a provider
                // failure: never burn a second provider on it.
                if error == .cancelled { throw error }
                errors.append(error)
            } catch {
                errors.append(.underlying(description: "The connection failed. Try again."))
            }
        }
        // Being offline explains every other failure, so report that instead of
        // whichever provider happened to be tried last.
        if errors.contains(.offline) { throw APIError.offline }
        throw errors.last ?? APIError.invalidResponse
    }
}
