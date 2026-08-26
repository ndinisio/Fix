import Foundation
import Testing
@testable import FIX

@Suite
struct TroubleshootingServiceTests {
    private let request = DiagnosisRequest(device: "MacBook Air M3", problem: "It won't charge.")

    @Test func returnsTheDiagnosisAndItsVideos() async throws {
        let videos = ScriptedVideoSearchService(.success([TestFixtures.video]))
        let service = TroubleshootingService(
            ai: ScriptedAIService(.success(TestFixtures.diagnosis())),
            videoSearch: videos
        )

        let outcome = try await service.diagnose(request)

        #expect(outcome.diagnosis.steps.count == 2)
        #expect(outcome.videos.count == 1)
        #expect(!outcome.videoSearchDidFail)
        #expect(videos.lastQuery == "MacBook not charging fix", "Uses the query written for video search")
    }

    @Test func aFailedVideoSearchDoesNotCostTheDiagnosis() async throws {
        let service = TroubleshootingService(
            ai: ScriptedAIService(.success(TestFixtures.diagnosis())),
            videoSearch: ScriptedVideoSearchService(.failure(.server(statusCode: 500)))
        )

        let outcome = try await service.diagnose(request)

        #expect(!outcome.diagnosis.summary.isEmpty)
        #expect(outcome.videos.isEmpty)
        #expect(outcome.videoSearchDidFail, "The UI must be able to say why there are no videos")
    }

    @Test func aFailedDiagnosisIsAnError() async throws {
        let service = TroubleshootingService(
            ai: ScriptedAIService(.failure(.offline)),
            videoSearch: ScriptedVideoSearchService(.success([]))
        )

        await #expect(throws: APIError.offline) { _ = try await service.diagnose(request) }
    }

    @Test func skipsVideoSearchWhenTurnedOff() async throws {
        let videos = ScriptedVideoSearchService(.success([TestFixtures.video]))
        let service = TroubleshootingService(
            ai: ScriptedAIService(.success(TestFixtures.diagnosis())),
            videoSearch: videos
        )

        let outcome = try await service.diagnose(request, includeVideos: false)

        #expect(outcome.videos.isEmpty)
        #expect(videos.callCount == 0)
        #expect(!outcome.videoSearchDidFail, "Not looking is not the same as failing")
    }

    @Test func reportsStagesInOrder() async throws {
        let service = TroubleshootingService(
            ai: ScriptedAIService(.success(TestFixtures.diagnosis())),
            videoSearch: ScriptedVideoSearchService(.success([]))
        )
        let recorder = PhaseRecorder()

        _ = try await service.diagnose(request, includeVideos: true) { phase in
            await recorder.record(phase)
        }

        #expect(await recorder.phases == [.analyzing, .findingVideos, .finished])
    }

    @Test func repeatingARequestDoesNotAskTwice() async throws {
        let ai = ScriptedAIService(.success(TestFixtures.diagnosis()))
        let service = TroubleshootingService(ai: ai, videoSearch: nil)

        _ = try await service.diagnose(request)
        _ = try await service.diagnose(request)

        #expect(ai.diagnoseCallCount == 1, "The second identical request is served from cache")
    }

    @Test func aFollowUpIsNotServedFromTheFirstRoundsCache() async throws {
        let ai = ScriptedAIService(.success(TestFixtures.diagnosis()))
        let service = TroubleshootingService(ai: ai, videoSearch: nil)

        _ = try await service.diagnose(request)
        var followUp = request
        followUp.history = [AttemptedStep(title: "Try another outlet", outcome: .didNotWork)]
        _ = try await service.diagnose(followUp)

        #expect(ai.diagnoseCallCount == 2)
    }

    @Test func fallsBackToDeviceAndCategoryForSearchTerms() {
        let diagnosis = TestFixtures.diagnosis(videoSearchQuery: nil)

        #expect(
            TroubleshootingService.videoQuery(for: diagnosis, device: "PS5")
                == "PS5 Charging troubleshooting"
        )
    }

    @Test func anUnconfiguredAppSaysSoRatherThanGuessing() async throws {
        let service = TroubleshootingService(ai: UnconfiguredAIService(), videoSearch: nil)

        await #expect(throws: APIError.notConfigured) { _ = try await service.diagnose(request) }
    }

    @Test func fallbackChainTriesTheNextProvider() async throws {
        let failing = ScriptedAIService(.failure(.server(statusCode: 500)))
        let working = ScriptedAIService(.success(TestFixtures.diagnosis()))
        let chain = FallbackAIService(providers: [failing, working])

        let diagnosis = try await chain.diagnose(request)

        #expect(!diagnosis.summary.isEmpty)
        #expect(failing.diagnoseCallCount == 1)
        #expect(working.diagnoseCallCount == 1)
    }

    @Test func fallbackReportsBeingOfflineRatherThanTheLastFailure() async throws {
        let chain = FallbackAIService(providers: [
            ScriptedAIService(.failure(.offline)),
            ScriptedAIService(.failure(.server(statusCode: 500)))
        ])

        await #expect(throws: APIError.offline) { _ = try await chain.diagnose(request) }
    }

    @Test func carePlansAreCached() async throws {
        let ai = ScriptedAIService(.success(TestFixtures.diagnosis()))
        let service = TroubleshootingService(ai: ai, videoSearch: nil)

        let first = try await service.carePlan(for: "iPhone 15")
        let second = try await service.carePlan(for: "iphone 15")

        #expect(first.summary == second.summary)
        #expect(first.tips.count == 1)
        #expect(ai.carePlanCallCount == 1, "A device's care plan is only generated once")
    }
}

/// Collects the phases reported during a diagnosis.
private actor PhaseRecorder {
    private(set) var phases: [DiagnosisPhase] = []

    func record(_ phase: DiagnosisPhase) {
        phases.append(phase)
    }
}
