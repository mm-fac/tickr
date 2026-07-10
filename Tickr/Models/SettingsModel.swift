import Foundation
import Observation
import TickrCore

/// Drives the Settings scene's Finnhub API-key field and wires the app's providers to
/// match. Reads/writes the key through an ``APIKeyStore`` (the Keychain in the app, an
/// in-memory double in tests) and swaps the shared ``ProviderHub`` between live Finnhub
/// and offline mocks via ``ProviderSelector`` — so a key change takes effect immediately,
/// without an app restart.
///
/// UI state, so it lives in the app target; it holds no SwiftUI/AppKit types and stays
/// unit-testable. Provider *selection* itself is TickrCore's ``ProviderSelector`` — this
/// model just persists the key and applies the result.
@MainActor
@Observable
final class SettingsModel {
    /// The editable key text bound to the Settings ``SecureField``. Editing it does not
    /// persist anything; the user commits with ``save()``.
    var keyDraft: String

    /// Whether live Finnhub data is currently wired (a usable key is saved). Drives the
    /// "using sample data" hint and the live/sample status in the Settings scene.
    private(set) var isLive: Bool

    /// A gentle message when the last save could not reach the Keychain, or `nil` when
    /// all is well. Surfaced in the Settings scene; never fatal.
    private(set) var saveError: String?

    private let store: APIKeyStore
    private let hub: ProviderHub
    private let mock: ProviderSet
    private let httpClient: HTTPClient

    /// Invoked after the provider set changes so the app can refresh what's on screen
    /// (e.g. reload the sidebar's quotes). Defaults to a no-op.
    var onProvidersChanged: @MainActor () async -> Void = {}

    init(
        store: APIKeyStore,
        hub: ProviderHub,
        mock: ProviderSet,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        self.store = store
        self.hub = hub
        self.mock = mock
        self.httpClient = httpClient

        let existing = try? store.read()
        let key = existing ?? nil
        self.keyDraft = key ?? ""
        self.isLive = ProviderSelector.usableKey(from: key) != nil
    }

    /// Persist the current ``keyDraft`` (or clear the key when it is blank) and re-wire the
    /// provider hub to match. Takes effect immediately: the next fetch uses the new
    /// providers, and ``onProvidersChanged`` refreshes what's already on screen.
    func save() async {
        let usableKey = ProviderSelector.usableKey(from: keyDraft)
        do {
            if let usableKey {
                try store.write(usableKey)
            } else {
                try store.delete()
            }
            saveError = nil
        } catch {
            // Persisting failed (e.g. Keychain denied). Leave the wiring unchanged and
            // tell the user gently rather than crashing.
            saveError = "Couldn't save the API key to the Keychain. Please try again."
            return
        }

        let set = ProviderSelector.resolve(apiKey: usableKey, mock: mock, httpClient: httpClient)
        await hub.update(set)
        isLive = set.isLive
        await onProvidersChanged()
    }
}
