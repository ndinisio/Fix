import Foundation
import Testing
@testable import Fix

/// Serialized: the stub protocol holds one handler at a time.
@Suite(.serialized)
struct APIClientTests {
    private struct Payload: Decodable, Equatable {
        let value: String
    }

    private var request: URLRequest {
        URLRequest(url: URL(string: "https://example.com/thing")!)
    }

    @Test func decodesSuccessfulResponse() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: #"{"value":"ok"}"#)

        let payload: Payload = try await StubURLProtocol.makeClient()
            .send(request, decoding: Payload.self)

        #expect(payload == Payload(value: "ok"))
    }

    @Test func malformedJSONBecomesInvalidResponse() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(json: "not json at all")

        await #expect(throws: APIError.invalidResponse) {
            let _: Payload = try await StubURLProtocol.makeClient().send(request, decoding: Payload.self)
        }
    }

    @Test func retriesServerErrorsThenSucceeds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respondFailingTimes(2, status: 500, then: #"{"value":"recovered"}"#)

        let payload: Payload = try await StubURLProtocol.makeClient(maxAttempts: 3)
            .send(request, decoding: Payload.self)

        #expect(payload == Payload(value: "recovered"))
        #expect(StubURLProtocol.recordedRequests.count == 3)
    }

    @Test func givesUpAfterMaxAttempts() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 503)

        await #expect(throws: APIError.server(statusCode: 503)) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 2).data(for: request)
        }
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func rateLimitReportsRetryAfter() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 429, headers: ["Retry-After": "12"])

        await #expect(throws: APIError.rateLimited(retryAfter: 12)) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 1).data(for: request)
        }
    }

    @Test func unauthorizedIsNotRetried() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 401)

        await #expect(throws: APIError.unauthorized) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 3).data(for: request)
        }
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func timeoutIsReportedAsTimedOut() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await #expect(throws: APIError.timedOut) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 1).data(for: request)
        }
    }

    @Test func offlineIsNotRetried() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: APIError.offline) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 3).data(for: request)
        }
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func aRefusedRequestCarriesTheProvidersExplanation() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(
            status: 404,
            json: #"{"error":{"message":"The model `llama-x` does not exist","type":"invalid_request_error"}}"#
        )

        await #expect(
            throws: APIError.rejected(detail: "The model `llama-x` does not exist")
        ) {
            _ = try await StubURLProtocol.makeClient().data(for: request)
        }
        #expect(StubURLProtocol.recordedRequests.count == 1, "Retrying a refusal repeats it")
    }

    @Test func aRefusalWithNoBodyStillReportsUsefully() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 400, json: "")

        await #expect(throws: APIError.rejected(detail: nil)) {
            _ = try await StubURLProtocol.makeClient().data(for: request)
        }
    }

    @Test func rateLimitsAreNotTreatedAsRefusals() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.respond(status: 429, headers: ["Retry-After": "5"])

        await #expect(throws: APIError.rateLimited(retryAfter: 5)) {
            _ = try await StubURLProtocol.makeClient(maxAttempts: 1).data(for: request)
        }
    }

    @Test func readsErrorMessagesFromBothProviders() {
        let groq = #"{"error":{"message":"Model decommissioned","type":"invalid_request_error"}}"#
        let youTube = #"{"error":{"code":403,"message":"API key not valid","errors":[]}}"#

        #expect(APIClient.providerMessage(from: Data(groq.utf8)) == "Model decommissioned")
        #expect(APIClient.providerMessage(from: Data(youTube.utf8)) == "API key not valid")
        #expect(APIClient.providerMessage(from: Data("not json".utf8)) == nil)
        #expect(APIClient.providerMessage(from: Data(#"{"error":{}}"#.utf8)) == nil)
    }

    @Test func backoffGrows() {
        #expect(APIClient.backoff(for: 1) < APIClient.backoff(for: 2))
        #expect(APIClient.backoff(for: 2) < APIClient.backoff(for: 3))
    }

    @Test func errorsExplainThemselves() {
        #expect(APIError.offline.isRetryable)
        #expect(!APIError.notConfigured.isRetryable)
        #expect(!APIError.unauthorized.isRetryable)
        #expect(!APIError.rejected(detail: nil).isRetryable)
        #expect(APIError.rejected(detail: "Model gone").guidance.contains("Model gone"))
        #expect(!APIError.offline.guidance.isEmpty)
        #expect(APIError.rateLimited(retryAfter: 30).guidance.contains("30"))
    }
}
