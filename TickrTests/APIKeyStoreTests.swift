import XCTest
@testable import Tickr

/// In-memory ``SecretStore`` standing in for the Keychain, so tests never touch real
/// system services (AGENTS.md, and CI has no Keychain).
final class InMemorySecretStore: SecretStore {
    private(set) var storage: [String: String] = [:]
    /// When set, the next matching call throws this error, to exercise failure paths.
    var throwOnNextCall: Error?

    init(seed: [String: String] = [:]) {
        storage = seed
    }

    func secret(for account: String) throws -> String? {
        if let error = throwOnNextCall {
            throwOnNextCall = nil
            throw error
        }
        return storage[account]
    }

    func setSecret(_ secret: String?, for account: String) throws {
        if let error = throwOnNextCall {
            throwOnNextCall = nil
            throw error
        }
        storage[account] = secret
    }
}

@MainActor
final class APIKeyStoreTests: XCTestCase {
    private let account = "finnhub"

    func testStartsEmptyWhenNothingStored() {
        let store = APIKeyStore(store: InMemorySecretStore(), account: account)
        XCTAssertNil(store.apiKey)
        XCTAssertFalse(store.hasKey)
    }

    func testLoadsExistingKeyOnInit() {
        let secrets = InMemorySecretStore(seed: [account: "abc123"])
        let store = APIKeyStore(store: secrets, account: account)
        XCTAssertEqual(store.apiKey, "abc123")
        XCTAssertTrue(store.hasKey)
    }

    func testSavePersistsAndReflectsKey() {
        let secrets = InMemorySecretStore()
        let store = APIKeyStore(store: secrets, account: account)

        store.save("my-key")

        XCTAssertEqual(store.apiKey, "my-key")
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(secrets.storage[account], "my-key")
    }

    func testSaveTrimsWhitespace() {
        let store = APIKeyStore(store: InMemorySecretStore(), account: account)
        store.save("  spaced-key  ")
        XCTAssertEqual(store.apiKey, "spaced-key")
    }

    func testSavingEmptyOrWhitespaceClearsKey() {
        let secrets = InMemorySecretStore(seed: [account: "existing"])
        let store = APIKeyStore(store: secrets, account: account)

        store.save("   ")

        XCTAssertNil(store.apiKey)
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(secrets.storage[account])
    }

    func testClearRemovesKey() {
        let secrets = InMemorySecretStore(seed: [account: "existing"])
        let store = APIKeyStore(store: secrets, account: account)

        store.clear()

        XCTAssertNil(store.apiKey)
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(secrets.storage[account])
    }

    func testKeyPersistsAcrossStoreInstances() {
        let secrets = InMemorySecretStore()
        APIKeyStore(store: secrets, account: account).save("persisted")

        let reloaded = APIKeyStore(store: secrets, account: account)
        XCTAssertEqual(reloaded.apiKey, "persisted")
    }

    func testEmptyStoredValueNormalisesToNoKey() {
        let secrets = InMemorySecretStore(seed: [account: "   "])
        let store = APIKeyStore(store: secrets, account: account)
        XCTAssertNil(store.apiKey)
        XCTAssertFalse(store.hasKey)
    }

    func testInitToleratesReadFailure() {
        let secrets = InMemorySecretStore()
        secrets.throwOnNextCall = KeychainError.status(-1)
        // A Keychain read failure must degrade to "no key", not crash.
        let store = APIKeyStore(store: secrets, account: account)
        XCTAssertNil(store.apiKey)
    }
}
