import Foundation
import Observation

/// Holds the user's Finnhub API key and persists it in the Keychain via a ``SecretStore``.
///
/// UI state (the Settings ``SecureField`` observes it), so it lives in the app target, but
/// it holds no SwiftUI/AppKit types and stays unit-testable by injecting a fake store.
/// The key is loaded once on init and kept in memory as ``apiKey`` so the routing
/// providers can read the current value cheaply on every request; ``save(_:)`` /
/// ``clear()`` update both the Keychain and the in-memory copy, so a change takes effect
/// immediately without an app restart.
@MainActor
@Observable
final class APIKeyStore {
    /// The current API key, or nil when none is stored. Never empty: an empty/whitespace
    /// value is normalised to nil so callers can treat "no key" as a single case.
    private(set) var apiKey: String?

    private let store: SecretStore
    private let account: String

    init(store: SecretStore = KeychainSecretStore(), account: String = "finnhub") {
        self.store = store
        self.account = account
        self.apiKey = Self.normalize((try? store.secret(for: account)) ?? nil)
    }

    /// Whether a usable key is present. Drives the Settings hint and provider selection.
    var hasKey: Bool { apiKey != nil }

    /// Persist `key` (trimmed) and reflect it in ``apiKey``. Passing an empty or
    /// whitespace-only string clears the stored key instead.
    func save(_ key: String) {
        let normalized = Self.normalize(key)
        try? store.setSecret(normalized, for: account)
        apiKey = normalized
    }

    /// Remove the stored key, reverting the app to sample data.
    func clear() {
        try? store.setSecret(nil, for: account)
        apiKey = nil
    }

    /// Collapse empty/whitespace-only input to nil and trim surrounding whitespace.
    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
