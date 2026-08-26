import Foundation
import Testing
@testable import FIX

/// Secret storage that never touches the Keychain, so the credential rules can
/// be tested from a test bundle.
final class InMemorySecretStorage: SecretStorage, @unchecked Sendable {
    private var values: [String: String] = [:]
    private(set) var writeCount = 0

    init(_ initial: [String: String] = [:]) {
        values = initial
    }

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String?, forKey key: String) throws {
        writeCount += 1
        values[key] = value
    }
}

@Suite
struct CredentialTests {
    @Test @MainActor func readsWhatWasStored() {
        let storage = InMemorySecretStorage([
            CredentialStore.Service.ai.rawValue: "gsk_stored"
        ])
        let store = CredentialStore(storage: storage)

        #expect(store.key(for: .ai) == "gsk_stored")
        #expect(store.hasKey(for: .ai))
        #expect(!store.hasKey(for: .video))
    }

    @Test @MainActor func savesAndRemoves() throws {
        let store = CredentialStore(storage: InMemorySecretStorage())

        try store.save("gsk_new", for: .ai)
        #expect(store.key(for: .ai) == "gsk_new")

        try store.save(nil, for: .ai)
        #expect(store.key(for: .ai) == nil)
        #expect(!store.hasKey(for: .ai))
    }

    @Test @MainActor func blankInputRemovesRatherThanStoringEmptiness() throws {
        let store = CredentialStore(storage: InMemorySecretStorage())

        try store.save("   ", for: .video)

        #expect(store.key(for: .video) == nil)
    }

    @Test @MainActor func trimsPastedKeys() throws {
        let store = CredentialStore(storage: InMemorySecretStorage())

        try store.save("  gsk_padded\n", for: .ai)

        #expect(store.key(for: .ai) == "gsk_padded", "Pasting from a browser often brings whitespace")
    }

    @Test func redactionShowsEnoughToRecognise() {
        #expect(CredentialStore.redacted("gsk_abcdefghijkl") == "gsk_••••ijkl")
        #expect(!CredentialStore.redacted("short").contains("short"))
    }

    // MARK: - Precedence

    @Test func aUserKeyConfiguresAnOtherwiseUnconfiguredBuild() {
        let build = AppConfiguration.resolve(environment: [:], infoDictionary: nil)
        #expect(!build.isAIConfigured)

        let effective = build.applying(groqAPIKey: "gsk_user", youTubeAPIKey: nil)

        #expect(effective.ai == .direct(apiKey: "gsk_user"))
        #expect(effective.video == nil, "A key for one service does not configure the other")
    }

    @Test func aUserKeyOverridesAKeyBakedIntoTheBuild() {
        let build = AppConfiguration.resolve(
            environment: [:], infoDictionary: ["GroqAPIKey": "gsk_from_build"]
        )

        let effective = build.applying(groqAPIKey: "gsk_from_user", youTubeAPIKey: nil)

        #expect(effective.ai == .direct(apiKey: "gsk_from_user"))
    }

    @Test func aRelayIsNeverReplacedByAKeyOnTheDevice() {
        let build = AppConfiguration.resolve(
            environment: [:], infoDictionary: ["RelayBaseURL": "relay.example.com/v1"]
        )

        let effective = build.applying(groqAPIKey: "gsk_user", youTubeAPIKey: "yt_user")

        #expect(effective.ai?.isRelay == true, "A server-held credential beats one on a phone")
        #expect(effective.video?.isRelay == true)
        #expect(build.usesRelay)
    }

    @Test func removingAKeyFallsBackToTheBuild() {
        let build = AppConfiguration.resolve(
            environment: [:], infoDictionary: ["GroqAPIKey": "gsk_from_build"]
        )

        let effective = build.applying(groqAPIKey: nil, youTubeAPIKey: nil)

        #expect(effective.ai == .direct(apiKey: "gsk_from_build"))
    }

    @Test func blankKeysAreIgnored() {
        let build = AppConfiguration.resolve(environment: [:], infoDictionary: nil)

        let effective = build.applying(groqAPIKey: "  ", youTubeAPIKey: "")

        #expect(effective.ai == nil)
        #expect(effective.video == nil)
    }

    // MARK: - Rebuilding

    @Test @MainActor func addingAKeyMakesTheAppUsable() {
        let storage = InMemorySecretStorage()
        let credentials = CredentialStore(storage: storage)
        let services = ServiceContainer(
            configuration: AppConfiguration.resolve(environment: [:], infoDictionary: nil),
            credentials: credentials,
            settings: AppSettings(defaults: UserDefaults(suiteName: #function) ?? .standard),
            networkMonitor: NetworkMonitor()
        )
        #expect(!services.configuration.isAIConfigured)

        try? credentials.save("gsk_user", for: .ai)
        services.credentialsDidChange()

        #expect(services.configuration.isAIConfigured, "No restart should be needed")
        #expect(services.buildConfiguration.isAIConfigured == false, "The build config is untouched")
    }

    @Test @MainActor func injectedServicesSurviveARebuild() {
        let sample = ScriptedAIService(.success(TestFixtures.diagnosis()))
        let injected = TroubleshootingService(ai: sample, videoSearch: nil)
        let services = ServiceContainer(
            configuration: AppConfiguration.resolve(environment: [:], infoDictionary: nil),
            credentials: CredentialStore(storage: InMemorySecretStorage()),
            settings: AppSettings(defaults: UserDefaults(suiteName: #function) ?? .standard),
            networkMonitor: NetworkMonitor(),
            troubleshooting: injected
        )

        services.credentialsDidChange()

        #expect(services.troubleshooting is TroubleshootingService)
    }
}
