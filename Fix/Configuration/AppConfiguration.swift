import Foundation

/// How Fix reaches a service.
///
/// Two transports exist deliberately:
///
/// - ``relay`` sends requests to a backend you control, which holds the
///   provider credentials and forwards them. This is the only transport
///   suitable for a build you ship to other people.
/// - ``direct`` talks to the provider from the device using a key baked into
///   the build. Convenient while developing, unsafe in production: anything
///   inside an app bundle can be extracted from it.
enum ServiceTransport: Equatable, Sendable {
    case relay(baseURL: URL)
    case direct(apiKey: String)

    var isRelay: Bool {
        if case .relay = self { return true }
        return false
    }
}

/// Resolved, read-only configuration for the running app.
///
/// Values come from the environment first (Xcode scheme variables, which never
/// end up in the build products) and fall back to `FixConfiguration` in
/// `Info.plist`, which is populated from `Config/Secrets.xcconfig` at build
/// time. Missing values are not an error: the app runs, explains that
/// diagnosis is unavailable, and keeps history and saved devices working.
struct AppConfiguration: Sendable {
    /// Transport for the AI provider, or `nil` when nothing is configured.
    var ai: ServiceTransport?
    /// Transport for video search, or `nil` when nothing is configured.
    var video: ServiceTransport?
    /// Groq model identifier used for diagnosis requests.
    var groqModel: String

    static let groqDefaultModel = "llama-3.3-70b-versatile"

    var isAIConfigured: Bool { ai != nil }
    var isVideoSearchConfigured: Bool { video != nil }

    // MARK: - Resolution

    static let current = AppConfiguration.resolve(
        environment: ProcessInfo.processInfo.environment,
        infoDictionary: Bundle.main.object(forInfoDictionaryKey: "FixConfiguration") as? [String: Any]
    )

    /// Builds a configuration from raw inputs. Split out from ``current`` so it
    /// can be exercised in tests without a bundle.
    static func resolve(
        environment: [String: String],
        infoDictionary: [String: Any]?
    ) -> AppConfiguration {
        func value(env: String, info: String) -> String? {
            let candidates = [environment[env], infoDictionary?[info] as? String]
            return candidates
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }

        let relay = value(env: "FIX_RELAY_BASE_URL", info: "RelayBaseURL").flatMap(Self.normalizedURL)
        let groqKey = value(env: "FIX_GROQ_API_KEY", info: "GroqAPIKey")
        let youTubeKey = value(env: "FIX_YOUTUBE_API_KEY", info: "YouTubeAPIKey")
        let model = value(env: "FIX_GROQ_MODEL", info: "GroqModel") ?? groqDefaultModel

        // A relay covers both services and always wins: if one is configured we
        // never fall back to shipping a key on the device.
        return AppConfiguration(
            ai: relay.map { .relay(baseURL: $0) } ?? groqKey.map { .direct(apiKey: $0) },
            video: relay.map { .relay(baseURL: $0) } ?? youTubeKey.map { .direct(apiKey: $0) },
            groqModel: model
        )
    }

    /// Returns a copy using keys the user supplied on the device.
    ///
    /// A relay is never overridden: it already holds the credentials on a
    /// server, which is strictly better than a key sitting on a phone. Where
    /// there is no relay, a key the user typed wins over one baked into the
    /// build, because it is the more recent, more deliberate choice.
    func applying(groqAPIKey: String?, youTubeAPIKey: String?) -> AppConfiguration {
        var updated = self
        if ai?.isRelay != true, let key = groqAPIKey?.nilIfBlank {
            updated.ai = .direct(apiKey: key)
        }
        if video?.isRelay != true, let key = youTubeAPIKey?.nilIfBlank {
            updated.video = .direct(apiKey: key)
        }
        return updated
    }

    /// True when this build points at a relay, in which case the app should not
    /// be asking anyone for a key.
    var usesRelay: Bool {
        ai?.isRelay == true || video?.isRelay == true
    }

    /// Accepts either a full URL or a bare host (optionally with a path).
    ///
    /// `.xcconfig` files treat `//` as the start of a comment, so a scheme
    /// cannot be written literally in `Config/Secrets.xcconfig`. Assuming HTTPS
    /// for a bare host keeps that file readable without inviting plain HTTP.
    static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let absolute = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: absolute), url.host != nil else { return nil }
        return url
    }
}
