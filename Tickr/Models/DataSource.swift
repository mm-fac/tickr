import Foundation
import TickrCore

/// The data source the app should use, derived purely from the presence of an API key.
///
/// This is the provider-selection logic in one testable place: a non-empty key means
/// live Finnhub data, anything else (nil, empty, whitespace) means the offline mocks.
enum DataSource: Equatable {
    /// Use live Finnhub providers with the given (trimmed, non-empty) key.
    case live(apiKey: String)
    /// Use the offline mock providers.
    case mock

    init(apiKey: String?) {
        if let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            self = .live(apiKey: trimmed)
        } else {
            self = .mock
        }
    }

    /// Whether live data is selected. Convenience for tests and the Settings hint.
    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

/// A ``QuoteProvider`` that resolves to the live or mock provider on every call, based on
/// the current key in ``APIKeyStore``. Re-checking per request is what lets a key entered
/// in Settings take effect immediately, without rebuilding view models or restarting.
struct RoutingQuoteProvider: QuoteProvider {
    let keyStore: APIKeyStore
    let makeLive: @Sendable (String) -> QuoteProvider
    let mock: QuoteProvider

    func quote(for symbol: String) async throws -> Quote {
        switch DataSource(apiKey: await keyStore.apiKey) {
        case .live(let key):
            return try await makeLive(key).quote(for: symbol)
        case .mock:
            return try await mock.quote(for: symbol)
        }
    }
}

/// Candle counterpart to ``RoutingQuoteProvider``; see its docs for the routing rationale.
struct RoutingCandleProvider: CandleProvider {
    let keyStore: APIKeyStore
    let makeLive: @Sendable (String) -> CandleProvider
    let mock: CandleProvider

    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        switch DataSource(apiKey: await keyStore.apiKey) {
        case .live(let key):
            return try await makeLive(key).candles(for: symbol, range: range)
        case .mock:
            return try await mock.candles(for: symbol, range: range)
        }
    }
}

/// Symbol-search counterpart to ``RoutingQuoteProvider``; see its docs for the rationale.
struct RoutingSymbolSearchProvider: SymbolSearchProvider {
    let keyStore: APIKeyStore
    let makeLive: @Sendable (String) -> SymbolSearchProvider
    let mock: SymbolSearchProvider

    func search(matching query: String) async throws -> [SymbolSearchResult] {
        switch DataSource(apiKey: await keyStore.apiKey) {
        case .live(let key):
            return try await makeLive(key).search(matching: query)
        case .mock:
            return try await mock.search(matching: query)
        }
    }
}

/// Builds the app's routing providers, wiring the live Finnhub implementations behind the
/// ``APIKeyStore``. Kept in one place so ``TickrApp`` stays declarative and the wiring can
/// be exercised in tests with fake live/mock providers.
@MainActor
enum ProviderFactory {
    static func quoteProvider(keyStore: APIKeyStore) -> QuoteProvider {
        RoutingQuoteProvider(
            keyStore: keyStore,
            makeLive: { FinnhubProvider(apiKey: $0) },
            mock: MockQuoteProvider()
        )
    }

    static func candleProvider(keyStore: APIKeyStore) -> CandleProvider {
        // Candles come from Stooq when live — Finnhub's free tier blocks candle access,
        // so quotes/search stay on Finnhub while charts route to Stooq. Stooq needs no
        // key, so the key handed to makeLive is intentionally ignored.
        RoutingCandleProvider(
            keyStore: keyStore,
            makeLive: { _ in StooqCandleProvider() },
            mock: PreviewCandleProvider()
        )
    }

    static func searchProvider(keyStore: APIKeyStore) -> SymbolSearchProvider {
        RoutingSymbolSearchProvider(
            keyStore: keyStore,
            makeLive: { FinnhubProvider(apiKey: $0) },
            mock: MockSymbolSearchProvider()
        )
    }
}
