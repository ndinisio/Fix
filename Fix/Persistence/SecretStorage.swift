import Foundation
import Security

/// Somewhere to keep a secret. Abstracted so the credential layer can be tested
/// without a Keychain, which is awkward to reach from a test bundle.
protocol SecretStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String) throws
}

/// The real implementation, backed by the device Keychain.
///
/// API keys never go in `UserDefaults`: that is a plain file inside the app
/// container, readable from a backup. Items here are written with
/// `afterFirstUnlockThisDeviceOnly`, so they are unavailable until the device
/// has been unlocked once after boot and never migrate to another device.
struct KeychainStorage: SecretStorage {
    enum Failure: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    "The key couldn't be saved: \(message)"
                } else {
                    "The key couldn't be saved."
                }
            }
        }
    }

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "Fix") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Failure.keychain(status)
            }
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            guard updateStatus == errSecSuccess else { throw Failure.keychain(updateStatus) }
            return
        }

        let insert = query.merging(attributes) { current, _ in current }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.keychain(addStatus) }
    }
}
