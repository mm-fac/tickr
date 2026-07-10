import Foundation
import Security

/// ``SecretStore`` backed by the macOS Keychain, storing each secret as a generic
/// password item. The API key never touches UserDefaults or a file on disk (AGENTS.md:
/// "API keys never appear in the repo, in code, or in fixtures" — and, by extension, not
/// in plaintext app storage).
///
/// Not used in tests: CI has no Keychain, so tests inject an in-memory fake through the
/// ``SecretStore`` protocol instead.
struct KeychainSecretStore: SecretStore {
    /// Keychain service name namespacing this app's items.
    let service: String

    init(service: String = "io.tickr.apikeys") {
        self.service = service
    }

    func secret(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    func setSecret(_ secret: String?, for account: String) throws {
        guard let secret, !secret.isEmpty else {
            try delete(account: account)
            return
        }

        let data = Data(secret.utf8)
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        default:
            throw KeychainError.status(updateStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Failures surfaced by ``KeychainSecretStore``.
enum KeychainError: Error, Equatable {
    /// The Keychain returned an item in an unexpected shape.
    case unexpectedData
    /// A non-success `OSStatus` from a Keychain call.
    case status(OSStatus)
}
