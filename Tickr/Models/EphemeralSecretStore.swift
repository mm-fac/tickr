import Foundation

/// Pure in-memory ``SecretStore`` used only by the deterministic `--ui-testing` launch
/// mode, so a UI-test run can never touch the real Keychain.
///
/// Kept as its own explicitly-named type (rather than reusing a preview/test fake) so a
/// unit test can assert the UI-testing dependency graph actually selected *this* type —
/// not merely that ``APIKeyStore`` started with no key, which an empty Keychain-backed
/// store would also satisfy (issue #37 retry evidence).
final class EphemeralSecretStore: SecretStore {
    private var storage: [String: String] = [:]

    func secret(for account: String) throws -> String? {
        storage[account]
    }

    func setSecret(_ secret: String?, for account: String) throws {
        storage[account] = secret
    }
}
