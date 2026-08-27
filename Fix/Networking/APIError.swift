import Foundation

/// Every failure the user can be shown, in one place.
///
/// Raw provider errors never reach the interface. Each case carries a title, a
/// sentence of plain guidance, and whether retrying is worth offering — which
/// is what an error view actually needs.
enum APIError: Error, Equatable, Sendable {
    case offline
    case notConfigured
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider understood the request and refused it — an unknown model,
    /// a malformed body, a withdrawn endpoint. Retrying changes nothing, so the
    /// provider's own explanation is carried through.
    case rejected(detail: String?)
    case server(statusCode: Int)
    case unauthorized
    case invalidResponse
    case cancelled
    case underlying(description: String)

    var title: String {
        switch self {
        case .offline: "No Internet Connection"
        case .notConfigured: "Diagnosis Unavailable"
        case .timedOut: "That Took Too Long"
        case .rateLimited: "Too Many Requests"
        case .rejected: "The Provider Refused That"
        case .server: "Something Went Wrong"
        case .unauthorized: "Diagnosis Unavailable"
        case .invalidResponse: "Couldn't Read the Answer"
        case .cancelled: "Cancelled"
        case .underlying: "Something Went Wrong"
        }
    }

    /// One sentence, in plain language, that tells the user what to do next.
    var guidance: String {
        switch self {
        case .offline:
            "Fix needs a connection to diagnose a new problem. Your history and saved devices are still available."
        case .notConfigured:
            "Fix hasn't been set up with an AI provider yet. Check Settings for details."
        case .timedOut:
            "The server didn't answer in time. Try again in a moment."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 1 {
                "Too many diagnoses at once. Try again in about \(Int(retryAfter.rounded())) seconds."
            } else {
                "Too many diagnoses at once. Wait a moment and try again."
            }
        case .rejected(let detail):
            if let detail {
                "\(detail)\n\nIf this names a model, pick a different one in Settings."
            } else {
                "The provider wouldn't accept the request. The model chosen in Settings may no longer be available."
            }
        case .server:
            "The service is having trouble. Try again shortly."
        case .unauthorized:
            "Fix couldn't sign in to the AI provider. Check the configuration in Settings."
        case .invalidResponse:
            "The answer came back in a form Fix couldn't use. Try again."
        case .cancelled:
            "The diagnosis was cancelled."
        case .underlying(let description):
            description
        }
    }

    /// Whether offering "Try Again" is honest. Nothing changes on a retry when
    /// the app is unconfigured or the credentials are wrong.
    var isRetryable: Bool {
        switch self {
        // Retrying a refusal repeats it: something has to change first.
        case .notConfigured, .unauthorized, .cancelled, .rejected: false
        default: true
        }
    }

    /// SF Symbol for the error state.
    var symbolName: String {
        switch self {
        case .offline: "wifi.slash"
        case .notConfigured, .unauthorized, .rejected: "gearshape"
        case .timedOut: "clock.badge.exclamationmark"
        case .rateLimited: "hourglass"
        case .cancelled: "xmark.circle"
        default: "exclamationmark.triangle"
        }
    }

    /// Maps a `URLError` onto the cases the interface knows how to present.
    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        default:
            self = .underlying(description: "The connection failed. Try again.")
        }
    }
}
