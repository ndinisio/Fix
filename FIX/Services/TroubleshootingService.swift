import Foundation

/// The stages of a diagnosis, as they actually happen.
///
/// The loading screen shows these. Each one is reported when the corresponding
/// work starts, so nothing is claimed that is not really going on.
enum DiagnosisPhase: Hashable, Sendable, CaseIterable {
    case analyzing
    case findingVideos
    case finished

    var title: String {
        switch self {
        case .analyzing: "Working out what's wrong"
        case .findingVideos: "Finding relevant videos"
        case .finished: "Done"
        }
    }
}

/// One diagnosis, with whatever videos could be found for it.
struct DiagnosisOutcome: Sendable {
    var diagnosis: Diagnosis
    var videos: [VideoResult]
    /// True when video search was attempted and failed. The distinction
    /// matters: "we couldn't look" and "there's nothing" are different answers.
    var videoSearchDidFail: Bool
}

protocol TroubleshootingServicing: Sendable {
    func diagnose(
        _ request: DiagnosisRequest,
        includeVideos: Bool,
        onPhase: @Sendable (DiagnosisPhase) async -> Void
    ) async throws -> DiagnosisOutcome

    func carePlan(for device: String) async throws -> CarePlan
}

extension TroubleshootingServicing {
    func diagnose(_ request: DiagnosisRequest, includeVideos: Bool = true) async throws -> DiagnosisOutcome {
        try await diagnose(request, includeVideos: includeVideos, onPhase: { _ in })
    }
}

/// Runs a diagnosis end to end: ask the model, turn its search query into
/// videos, and cache both.
///
/// The ordering is deliberate. The model's answer is what the user came for, so
/// a video search that fails, times out, or is not configured degrades the
/// result instead of failing it.
final class TroubleshootingService: TroubleshootingServicing {
    private let ai: any AIService
    private let videoSearch: (any VideoSearchService)?
    private let diagnosisCache: ResponseCache<Diagnosis>
    private let videoCache: ResponseCache<[VideoResult]>
    private let carePlanCache: ResponseCache<CarePlan>
    private let videoLimit: Int

    init(
        ai: any AIService,
        videoSearch: (any VideoSearchService)?,
        diagnosisCache: ResponseCache<Diagnosis> = ResponseCache(),
        videoCache: ResponseCache<[VideoResult]> = ResponseCache(ttl: 6 * 60 * 60),
        carePlanCache: ResponseCache<CarePlan> = ResponseCache(ttl: 24 * 60 * 60),
        videoLimit: Int = 5
    ) {
        self.ai = ai
        self.videoSearch = videoSearch
        self.diagnosisCache = diagnosisCache
        self.videoCache = videoCache
        self.carePlanCache = carePlanCache
        self.videoLimit = videoLimit
    }

    func diagnose(
        _ request: DiagnosisRequest,
        includeVideos: Bool,
        onPhase: @Sendable (DiagnosisPhase) async -> Void
    ) async throws -> DiagnosisOutcome {
        await onPhase(.analyzing)

        let diagnosis: Diagnosis
        if let cached = await diagnosisCache.value(forKey: request.cacheKey) {
            diagnosis = cached
        } else {
            diagnosis = try await ai.diagnose(request)
            await diagnosisCache.insert(diagnosis, forKey: request.cacheKey)
        }

        guard includeVideos, let videoSearch else {
            await onPhase(.finished)
            return DiagnosisOutcome(diagnosis: diagnosis, videos: [], videoSearchDidFail: false)
        }

        await onPhase(.findingVideos)
        let query = Self.videoQuery(for: diagnosis, device: request.device)

        if let cached = await videoCache.value(forKey: query) {
            await onPhase(.finished)
            return DiagnosisOutcome(diagnosis: diagnosis, videos: cached, videoSearchDidFail: false)
        }

        do {
            let videos = try await videoSearch.searchVideos(query: query, limit: videoLimit)
            await videoCache.insert(videos, forKey: query)
            await onPhase(.finished)
            return DiagnosisOutcome(diagnosis: diagnosis, videos: videos, videoSearchDidFail: false)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch APIError.cancelled {
            throw APIError.cancelled
        } catch {
            // The diagnosis is the product; videos are a bonus.
            await onPhase(.finished)
            return DiagnosisOutcome(diagnosis: diagnosis, videos: [], videoSearchDidFail: true)
        }
    }

    func carePlan(for device: String) async throws -> CarePlan {
        let key = device.lowercased()
        if let cached = await carePlanCache.value(forKey: key) { return cached }
        let plan = try await ai.carePlan(for: device)
        await carePlanCache.insert(plan, forKey: key)
        return plan
    }

    /// Prefers the query the model wrote for video search. Falls back to the
    /// device and category rather than the user's whole message, which makes
    /// for poor search terms.
    static func videoQuery(for diagnosis: Diagnosis, device: String) -> String {
        if let query = diagnosis.videoSearchQuery?.nilIfBlank { return query }
        return "\(device) \(diagnosis.category.title) troubleshooting"
    }
}
