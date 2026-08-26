import Foundation
import Observation

/// The API keys the user has entered on this device.
///
/// FIX is configured at build time where a relay is available. Where one is
/// not — a personal build, or someone running it from source — this lets the
/// user supply their own key instead, held in the Keychain rather than in the
/// app bundle. It is their key, on their device, and it is never written to
/// source, to a build setting, or to Git.
@MainActor
@Observable
final class CredentialStore {
    /// A service whose key the user can supply.
    enum Service: String, CaseIterable, Identifiable, Sendable {
        case ai = "provider.groq.apiKey"
        case video = "provider.youtube.apiKey"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ai: "AI Provider"
            case .video: "Video Search"
            }
        }

        var providerName: String {
            switch self {
            case .ai: "Groq"
            case .video: "YouTube Data API"
            }
        }

        /// What the key is used for, in one sentence.
        var purpose: String {
            switch self {
            case .ai: "Diagnoses problems and writes the troubleshooting steps."
            case .video: "Finds repair videos for a diagnosis. Optional — FIX works without it."
            }
        }

        /// Where to get one.
        var consoleURL: URL? {
            switch self {
            case .ai: URL(string: "https://console.groq.com/keys")
            case .video: URL(string: "https://console.cloud.google.com/apis/credentials")
            }
        }

        var symbolName: String {
            switch self {
            case .ai: "sparkles"
            case .video: "play.rectangle"
            }
        }
    }

    private(set) var keys: [Service: String] = [:]

    @ObservationIgnored private let storage: any SecretStorage

    init(storage: any SecretStorage = KeychainStorage()) {
        self.storage = storage
        for service in Service.allCases {
            keys[service] = storage.string(forKey: service.rawValue)?.nilIfBlank
        }
    }

    func key(for service: Service) -> String? {
        keys[service]
    }

    func hasKey(for service: Service) -> Bool {
        key(for: service) != nil
    }

    /// Saves a key, or removes it when passed nothing.
    func save(_ key: String?, for service: Service) throws {
        let trimmed = key?.nilIfBlank
        try storage.set(trimmed, forKey: service.rawValue)
        keys[service] = trimmed
    }

    func removeAll() throws {
        for service in Service.allCases {
            try save(nil, for: service)
        }
    }

    /// A key shown back to the user, with only enough visible to recognise it.
    static func redacted(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "\(key.prefix(4))••••\(key.suffix(4))"
    }
}
