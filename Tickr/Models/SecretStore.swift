import Foundation

/// Reads and writes a single secret string (e.g. an API key), keyed by account, behind a
/// tiny protocol so the Keychain-backed implementation can be swapped for an in-memory
/// fake in tests. CI has no Keychain, so ``APIKeyStore`` is always exercised against a
/// fake there (AGENTS.md: tests never hit real system services).
///
/// Setting a `nil` value deletes the item. All methods throw so a Keychain failure can
/// surface; callers that only need best-effort behaviour treat a throw as "no secret".
protocol SecretStore {
    /// The secret stored for `account`, or nil when none is present.
    func secret(for account: String) throws -> String?
    /// Store `secret` for `account`, replacing any existing value; a nil `secret` deletes it.
    func setSecret(_ secret: String?, for account: String) throws
}
