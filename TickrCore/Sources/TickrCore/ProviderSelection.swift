import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The trio of data providers the app reads from, bundled together with a flag for
/// whether they are backed by the live Finnhub service (``isLive``) or by offline mocks.
///
/// A single ``FinnhubProvider`` conforms to all three provider protocols, so when a key
/// is configured the same instance backs `quote`, `candle`, and `search`. Without a key
/// each slot holds an independent offline mock. Grouping them lets the app swap the whole
/// set atomically when the API key changes (see the app-side provider hub).
public struct ProviderSet: Sendable {
    public let quote: any QuoteProvider
    public let candle: any CandleProvider
    public let search: any SymbolSearchProvider
    /// `true` when the set is backed by the live Finnhub service; `false` for offline mocks.
    public let isLive: Bool

    public init(
        quote: any QuoteProvider,
        candle: any CandleProvider,
        search: any SymbolSearchProvider,
        isLive: Bool
    ) {
        self.quote = quote
        self.candle = candle
        self.search = search
        self.isLive = isLive
    }
}

/// Decides which providers back the app based on the presence of a Finnhub API key.
///
/// This is the platform-agnostic selection logic the Settings flow relies on: a usable
/// key wires the live ``FinnhubProvider``; the absence of one keeps the app on the
/// offline `mock` set. Kept in TickrCore (not the app target) so it is covered by
/// `swift test` and never depends on SwiftUI, AppKit, or the Keychain.
public enum ProviderSelector {
    /// Normalizes a raw key entry into a usable key, or `nil` when there is none.
    ///
    /// Leading/trailing whitespace is trimmed; an empty or whitespace-only string is
    /// treated as "no key" so a blank Settings field cleanly falls back to mocks.
    public static func usableKey(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Resolves the provider set for the given API key.
    ///
    /// With a usable key, all three providers are backed by one ``FinnhubProvider``
    /// (marked ``ProviderSet/isLive``); otherwise the offline `mock` set is returned
    /// unchanged. The `httpClient` is injected so the wired provider can be exercised in
    /// tests without hitting the network.
    public static func resolve(
        apiKey raw: String?,
        mock: ProviderSet,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) -> ProviderSet {
        guard let key = usableKey(from: raw) else { return mock }
        let finnhub = FinnhubProvider(apiKey: key, httpClient: httpClient)
        return ProviderSet(quote: finnhub, candle: finnhub, search: finnhub, isLive: true)
    }
}
