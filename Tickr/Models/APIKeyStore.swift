import Foundation

/// Reads, writes, and clears a single secret string — the Finnhub API key — behind a
/// tiny protocol so tests can substitute an in-memory double and never touch the real
/// Keychain (AGENTS.md: keys never land in UserDefaults or files, and tests never depend
/// on the system Keychain / network).
///
/// Callers treat a blank key as "clear the key" rather than storing an empty string; see
/// ``SettingsModel``.
protocol APIKeyStore: Sendable {
    /// The stored key, or `nil` when none has been saved.
    func read() throws -> String?
    /// Persists `key`, replacing any existing value.
    func write(_ key: String) throws
    /// Removes any stored key. A no-op when nothing is stored.
    func delete() throws
}
