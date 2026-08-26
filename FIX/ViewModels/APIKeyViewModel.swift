import Foundation
import Observation

/// Entering, checking and removing one service's API key.
@MainActor
@Observable
final class APIKeyViewModel {
    enum CheckState: Equatable {
        case idle
        case checking
        case verified
        case failed(APIError)
        case saveFailed(String)
    }

    let service: CredentialStore.Service
    var draft: String = ""
    private(set) var state: CheckState = .idle
    /// True once the stored key has been read, so the field is not cleared out
    /// from under someone who is typing.
    private var hasLoaded = false

    init(service: CredentialStore.Service) {
        self.service = service
    }

    func load(from credentials: CredentialStore) {
        guard !hasLoaded else { return }
        hasLoaded = true
        draft = credentials.key(for: service) ?? ""
    }

    var canSave: Bool {
        state != .checking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStoredKey: Bool { storedKey != nil }
    private var storedKey: String?

    /// Saves the key, then makes one real request to confirm it works — so
    /// "Ready" in Settings means the credentials were accepted, not merely that
    /// something was typed.
    func save(into services: ServiceContainer) async {
        do {
            try services.credentials.save(draft, for: service)
        } catch {
            state = .saveFailed(error.localizedDescription)
            return
        }
        services.credentialsDidChange()
        storedKey = services.credentials.key(for: service)
        await check(using: services)
    }

    func remove(from services: ServiceContainer) {
        do {
            try services.credentials.save(nil, for: service)
        } catch {
            state = .saveFailed(error.localizedDescription)
            return
        }
        services.credentialsDidChange()
        draft = ""
        storedKey = nil
        state = .idle
    }

    func check(using services: ServiceContainer) async {
        let configuration = services.configuration
        let transport: ServiceTransport?
        switch service {
        case .ai: transport = configuration.ai
        case .video: transport = configuration.video
        }
        guard let transport else {
            state = .idle
            return
        }

        state = .checking
        do {
            switch service {
            case .ai:
                try await GroqService(
                    transport: transport, model: configuration.groqModel
                ).validateCredentials()
            case .video:
                try await YouTubeVideoSearchService(transport: transport).validateCredentials()
            }
            state = .verified
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.underlying(description: "The check couldn't be completed."))
        }
    }
}
