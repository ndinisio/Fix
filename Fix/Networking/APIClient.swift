import Foundation

/// One place where HTTP happens.
///
/// Every service in Fix goes through this type, so retry policy, timeouts,
/// status-code handling and error mapping are written once and behave the same
/// everywhere. Services describe *what* to request; this decides how.
final class APIClient: @unchecked Sendable {
    private let session: URLSession
    private let maxAttempts: Int
    /// Injected so tests do not have to wait out real backoff delays.
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        session: URLSession = .fixDefault,
        maxAttempts: Int = 3,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
        self.sleep = sleep
    }

    /// Performs a request and decodes the response body.
    func send<T: Decodable>(
        _ request: URLRequest,
        decoding: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await data(for: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    /// Performs a request, retrying transient failures with exponential
    /// backoff. Rate limits honour `Retry-After` when the server sends one.
    func data(for request: URLRequest) async throws -> Data {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 401, 403:
                    throw APIError.unauthorized
                case 429:
                    let retryAfter = Self.retryAfter(from: http)
                    guard attempt < maxAttempts else {
                        throw APIError.rateLimited(retryAfter: retryAfter)
                    }
                    try await sleep(retryAfter ?? Self.backoff(for: attempt))
                case 400..<500:
                    // The request itself was refused. The provider says why,
                    // and that explanation is worth far more than a status code.
                    throw APIError.rejected(detail: Self.providerMessage(from: data))
                case 500..<600:
                    guard attempt < maxAttempts else {
                        throw APIError.server(statusCode: http.statusCode)
                    }
                    try await sleep(Self.backoff(for: attempt))
                default:
                    throw APIError.server(statusCode: http.statusCode)
                }
            } catch let error as APIError {
                throw error
            } catch is CancellationError {
                throw APIError.cancelled
            } catch let error as URLError {
                let mapped = APIError(urlError: error)
                // A dropped connection is worth one more try; being offline or
                // cancelled is not.
                guard mapped != .offline, mapped != .cancelled, attempt < maxAttempts else {
                    throw mapped
                }
                try await sleep(Self.backoff(for: attempt))
            } catch {
                throw APIError.underlying(description: "The connection failed. Try again.")
            }
            attempt += 1
        }
    }

    /// 0.6s, 1.8s, 5.4s — long enough to clear a brief wobble, short enough
    /// that the user is not left staring at a progress view.
    static func backoff(for attempt: Int) -> TimeInterval {
        0.6 * pow(3, Double(attempt - 1))
    }

    /// Pulls the human-readable message out of a provider's error body. Groq
    /// and the YouTube Data API both nest it at `error.message`.
    static func providerMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable {
                let message: String?
            }
            let error: Failure?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else { return nil }
        return message
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else { return nil }
        // Never sit on a spinner for longer than a minute.
        return min(seconds, 60)
    }
}

extension URLSession {
    /// Shared configuration for Fix's requests: no response caching of AI
    /// answers (they are cached deliberately, in the app), and timeouts short
    /// enough that a stalled request surfaces as an error the user can act on.
    static let fixDefault: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
