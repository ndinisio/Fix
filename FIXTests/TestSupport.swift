import Foundation
@testable import FIX

/// Serves canned HTTP responses so the networking tests exercise the real
/// `URLSession` path without touching the network.
final class StubURLProtocol: URLProtocol {
    /// Set by each test before it makes a request. The suites that use this are
    /// serialized, so there is one handler in play at a time.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Every request that reached the stub, in order.
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        recordedRequests = []
    }

    /// A session wired to this stub, plus a client that does not really sleep
    /// between retries.
    static func makeClient(maxAttempts: Int = 3) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            session: URLSession(configuration: configuration),
            maxAttempts: maxAttempts,
            sleep: { _ in }
        )
    }

    static func respond(
        status: Int = 200,
        json: String = "{}",
        headers: [String: String] = [:]
    ) {
        handler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (response, Data(json.utf8))
        }
    }

    /// Fails `failures` times with `status`, then succeeds.
    static func respondFailingTimes(_ failures: Int, status: Int, then json: String) {
        var remaining = failures
        handler = { request in
            let url = request.url ?? URL(string: "https://example.com")!
            if remaining > 0 {
                remaining -= 1
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
                )!
                return (response, Data())
            }
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.recordedRequests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// An AI service with scripted behaviour, for testing the layers above it.
final class ScriptedAIService: AIService, @unchecked Sendable {
    enum Behaviour {
        case success(Diagnosis)
        case failure(APIError)
    }

    private let behaviour: Behaviour
    private(set) var diagnoseCallCount = 0
    private(set) var carePlanCallCount = 0
    private(set) var lastRequest: DiagnosisRequest?

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis {
        diagnoseCallCount += 1
        lastRequest = request
        switch behaviour {
        case .success(let diagnosis): return diagnosis
        case .failure(let error): throw error
        }
    }

    func carePlan(for device: String) async throws -> CarePlan {
        carePlanCallCount += 1
        switch behaviour {
        case .success:
            return CarePlan(device: device, summary: "Keep it cool.", tips: [
                CareTip(title: "Dust the vents", detail: "Twice a year.")
            ])
        case .failure(let error):
            throw error
        }
    }
}

/// A video search with scripted behaviour.
final class ScriptedVideoSearchService: VideoSearchService, @unchecked Sendable {
    enum Behaviour {
        case success([VideoResult])
        case failure(APIError)
    }

    private let behaviour: Behaviour
    private(set) var callCount = 0
    private(set) var lastQuery: String?

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func searchVideos(query: String, limit: Int) async throws -> [VideoResult] {
        callCount += 1
        lastQuery = query
        switch behaviour {
        case .success(let videos): return Array(videos.prefix(limit))
        case .failure(let error): throw error
        }
    }
}

enum TestFixtures {
    static let video = VideoResult(
        id: "abc",
        title: "Fix a MacBook that won't charge",
        channelName: "Repair Workshop",
        thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
        videoURL: URL(string: "https://www.youtube.com/watch?v=abc")!,
        duration: "8:41"
    )

    static func diagnosis(
        summary: String = "The charger is the most likely cause.",
        steps: [TroubleshootingStep] = [
            TroubleshootingStep(id: "step-1", title: "Try another outlet", detail: "Use a wall socket."),
            TroubleshootingStep(id: "step-2", title: "Swap the cable", detail: "Use a known-good cable.")
        ],
        videoSearchQuery: String? = "MacBook not charging fix"
    ) -> Diagnosis {
        Diagnosis(
            summary: summary,
            category: .charging,
            steps: steps,
            videoSearchQuery: videoSearchQuery
        )
    }

    static let diagnosisJSON = """
    {
      "summary": "The charger or cable is the most likely cause.",
      "category": "charging",
      "confidence": "medium",
      "likelyCauses": ["Faulty charger", "Damaged cable"],
      "steps": [
        {
          "id": "step-1",
          "title": "Try another outlet",
          "detail": "Plug into a wall socket you know works.",
          "expectedOutcome": "A charging indicator appears.",
          "ifItFails": "The outlet is not the problem.",
          "difficulty": "easy",
          "risk": "low"
        }
      ],
      "safetyWarnings": [{ "text": "Stop if the charger is hot.", "severity": "caution" }],
      "careTips": [{ "title": "Keep the port clear", "detail": "Check for lint.", "cadence": "Monthly" }],
      "videoSearchQuery": "MacBook Air not charging troubleshooting",
      "escalation": "Book a service appointment."
    }
    """

    /// Wraps a diagnosis body in the chat-completions envelope Groq returns.
    static func completionEnvelope(content: String) -> String {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}"
    }
}
