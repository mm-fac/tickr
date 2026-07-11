import Foundation

/// In-memory ``SecretStore`` used by the deterministic UI-testing launch so the app never
/// reads, writes, or clears the real Keychain. It holds secrets only for the lifetime of
/// the process and starts empty on every launch, so the UI-testing graph begins with no
/// API key and therefore always resolves to the offline mock providers.
///
/// This is production app-target code (not a test double) so the ``AppDependencies`` graph
/// can select it directly in UI-testing mode without ever constructing
/// ``KeychainSecretStore``; unit tests can assert on its concrete type to prove that.
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
