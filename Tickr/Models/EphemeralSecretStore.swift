import Foundation

/// In-memory ``SecretStore`` used under `--ui-testing`.
///
/// Holds secrets in a dictionary for the lifetime of the process and never touches the
/// Keychain, so the UI-testing dependency graph can inject it in place of
/// ``KeychainSecretStore``. Starts empty, so ``APIKeyStore`` resolves to "no key" and the
/// app forces the offline mock providers. The unit tests assert the graph selected this
/// type (and therefore never constructed a Keychain-backed store).
final class EphemeralSecretStore: SecretStore {
    private var storage: [String: String]

    init(seed: [String: String] = [:]) {
        self.storage = seed
    }

    func secret(for account: String) throws -> String? {
        storage[account]
    }

    func setSecret(_ secret: String?, for account: String) throws {
        storage[account] = secret
    }
}
