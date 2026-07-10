import Foundation
import Security

/// ``APIKeyStore`` backed by the macOS Keychain, storing the Finnhub API key as a single
/// generic-password item. The key never touches UserDefaults or the filesystem
/// (AGENTS.md). `service` + `account` identify the one item this app owns.
///
/// Not exercised in CI — the unit tests inject an in-memory ``APIKeyStore`` instead, so
/// no test depends on the real Keychain.
struct KeychainAPIKeyStore: APIKeyStore {
    /// Failures the Keychain can report. `unexpectedStatus` carries the raw `OSStatus`
    /// for diagnosis; `invalidData` guards the (theoretical) non-UTF-8 round-trip.
    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    private let service: String
    private let account: String

    init(service: String = "com.mmfac.tickr", account: String = "finnhub-api-key") {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func write(_ key: String) throws {
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidData }

        // Update the item in place if it exists; otherwise add it. This avoids a
        // delete-then-add race and preserves any existing keychain access attributes.
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
