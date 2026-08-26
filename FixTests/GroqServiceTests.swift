import Foundation
import Testing
@testable import Fix

@Suite(.serialized)
struct GroqServiceTests {
    private let request = DiagnosisRequest(device: "MacBook Air M3", problem: "It won't charge.")

    private func service(transport: ServiceTransport = .direct(apiKey: "test-key")) -> GroqService {
        GroqService(transport: transport, model: "test-model", client: StubURLProtocol.makeClient())
    }

    @Test func parsesADiagnosisFromACompletion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TestFixtures.completionEnvelope(content: TestFixtures.diagnosisJSON))

        let diagnosis = try await service().diagnose(request)

        #expect(diagnosis.category == .charging)
        #expect(diagnosis.steps.count == 1)
    }

    @Test func recoversFromAFencedResponse() async throws {
        StubURLProtocol.reset()
        let fenced = "Here you go:\n```json\n\(TestFixtures.diagnosisJSON)\n```"
        StubURLProtocol.respond(json: TestFixtures.completionEnvelope(content: fenced))

        let diagnosis = try await service().diagnose(request)

        #expect(diagnosis.summary.hasPrefix("The charger"))
    }

    @Test func rejectsAnAnswerWithNothingToDo() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(
            json: TestFixtures.completionEnvelope(content: #"{"summary":"No idea.","steps":[]}"#)
        )

        await #expect(throws: APIError.invalidResponse) {
            _ = try await service().diagnose(request)
        }
    }

    @Test func rejectsAnEmptyCompletion() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"choices":[]}"#)

        await #expect(throws: APIError.invalidResponse) {
            _ = try await service().diagnose(request)
        }
    }

    @Test func sendsTheKeyOnlyWhenTalkingToGroqDirectly() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TestFixtures.completionEnvelope(content: TestFixtures.diagnosisJSON))

        _ = try await service().diagnose(request)
        let direct = try #require(StubURLProtocol.recordedRequests.first)
        #expect(direct.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(direct.url?.host() == "api.groq.com")

        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TestFixtures.completionEnvelope(content: TestFixtures.diagnosisJSON))
        let relayURL = try #require(URL(string: "https://relay.example.com/v1"))
        _ = try await service(transport: .relay(baseURL: relayURL)).diagnose(request)

        let relayed = try #require(StubURLProtocol.recordedRequests.first)
        #expect(relayed.value(forHTTPHeaderField: "Authorization") == nil, "A relay holds the key, not the app")
        #expect(relayed.url?.absoluteString == "https://relay.example.com/v1/chat/completions")
    }

    @Test func sendsOnlyTheTroubleshootingContext() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: TestFixtures.completionEnvelope(content: TestFixtures.diagnosisJSON))

        _ = try await service().diagnose(
            DiagnosisRequest(
                device: "PlayStation 5",
                problem: "No display",
                details: ProblemDetails(onset: .today, alreadyTried: "A different cable")
            )
        )

        let body = try #require(StubURLProtocol.recordedRequests.first?.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("PlayStation 5"))
        #expect(text.contains("No display"))
        #expect(text.contains("A different cable"))
        #expect(text.contains("test-model"))
    }

    @Test func followUpTellsTheModelWhatFailed() {
        let message = FixPrompt.diagnosisMessage(for: DiagnosisRequest(
            device: "PS5",
            problem: "No display",
            history: [
                AttemptedStep(title: "Swap the HDMI cable", outcome: .didNotWork),
                AttemptedStep(title: "Try another TV", outcome: .didNotWork)
            ]
        ))

        #expect(message.contains("Swap the HDMI cable: did not help"))
        #expect(message.contains("Do not repeat them"))
    }

    @Test func extractsJSONFromSurroundingText() {
        #expect(GroqService.extractJSONObject(from: #"{"a":1}"#) == #"{"a":1}"#)
        #expect(GroqService.extractJSONObject(from: "```json\n{\"a\":1}\n```") == #"{"a":1}"#)
        #expect(GroqService.extractJSONObject(from: "Sure! {\"a\":1} Hope that helps.") == #"{"a":1}"#)
        #expect(GroqService.extractJSONObject(from: "no json here") == nil)
    }

    @Test func promptCarriesTheSafetyRules() {
        #expect(FixPrompt.system.contains("swollen"))
        #expect(FixPrompt.system.contains("Safety comes before troubleshooting"))
        #expect(FixPrompt.system.contains("Never invent error codes"))
        #expect(FixPrompt.diagnosisSchema.contains("videoSearchQuery"))
    }
}
