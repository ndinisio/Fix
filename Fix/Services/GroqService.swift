import Foundation

/// ``AIService`` backed by Groq's OpenAI-compatible chat completions API.
///
/// Two transports are supported. With a relay, requests go to a backend that
/// holds the credentials and forwards them, and the app sends no key at all.
/// With a direct key the app talks to Groq itself — fine while developing,
/// unsuitable for a shipped build.
final class GroqService: AIService {
    private let transport: ServiceTransport
    private let model: String
    private let client: APIClient

    /// Groq's OpenAI-compatible endpoint.
    private static let directBaseURL = URL(string: "https://api.groq.com/openai/v1")!
    /// Path used for both transports: a relay is expected to proxy this route.
    private static let completionsPath = "chat/completions"

    init(
        transport: ServiceTransport,
        model: String = AppConfiguration.groqDefaultModel,
        client: APIClient = APIClient()
    ) {
        self.transport = transport
        self.model = model
        self.client = client
    }

    // MARK: - AIService

    func diagnose(_ request: DiagnosisRequest) async throws -> Diagnosis {
        let diagnosis: Diagnosis = try await complete(
            system: FixPrompt.system + "\n\n" + FixPrompt.diagnosisSchema,
            user: FixPrompt.diagnosisMessage(for: request),
            maxTokens: 1800
        )
        // An answer with nothing to do and nothing to ask is a failure, not an
        // empty screen.
        guard diagnosis.isActionable else { throw APIError.invalidResponse }
        return diagnosis
    }

    func carePlan(for device: String) async throws -> CarePlan {
        var plan: CarePlan = try await complete(
            system: FixPrompt.carePlanSystem,
            user: FixPrompt.carePlanMessage(for: device),
            maxTokens: 900
        )
        guard plan.isActionable else { throw APIError.invalidResponse }
        // The model is not asked to echo the device name back.
        plan.device = device
        plan.generatedAt = .now
        return plan
    }

    /// Checks that the credentials work, without spending tokens on a
    /// completion. Listing models is the cheapest authenticated call there is.
    func validateCredentials() async throws {
        var request = URLRequest(url: baseURL().appending(path: "models"))
        request.httpMethod = "GET"
        if case .direct(let apiKey) = transport {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        _ = try await client.data(for: request)
    }

    // MARK: - Request

    private func complete<T: Decodable>(
        system: String,
        user: String,
        maxTokens: Int
    ) async throws -> T {
        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            // Low but not zero: diagnosis should be stable, not identical.
            temperature: 0.2,
            maxTokens: maxTokens,
            responseFormat: .init(type: "json_object")
        )

        var request = URLRequest(url: endpointURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if case .direct(let apiKey) = transport {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw APIError.invalidResponse
        }

        let response: ChatResponse = try await client.send(request, decoding: ChatResponse.self)
        guard let content = response.choices.first?.message.content,
              let json = Self.extractJSONObject(from: content)
        else {
            throw APIError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func endpointURL() -> URL {
        baseURL().appending(path: Self.completionsPath)
    }

    private func baseURL() -> URL {
        switch transport {
        case .relay(let baseURL): baseURL
        case .direct: Self.directBaseURL
        }
    }

    /// Pulls the JSON object out of a completion.
    ///
    /// JSON mode makes this unnecessary almost always, but a model that wraps
    /// its answer in a code fence or adds a sentence of preamble should not
    /// cost the user their diagnosis.
    static func extractJSONObject(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(trimmed[start...end])
    }
}

// MARK: - Wire types

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}
