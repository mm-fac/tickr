import Foundation
import TickrCore

/// A stable, swappable façade over the current ``ProviderSet``.
///
/// The app hands one hub to the view models at launch; each view model keeps holding it
/// as its ``QuoteProvider`` / ``CandleProvider`` / ``SymbolSearchProvider``. When the API
/// key changes, ``SettingsModel`` calls ``update(_:)`` so the *next* fetch flows through
/// the newly selected providers — no app restart and no rebuilt view models.
///
/// An `actor` so the backing set can be swapped and read concurrently without locks; the
/// provider protocol methods are already `async`, so forwarding through the actor adds no
/// friction.
actor ProviderHub: QuoteProvider, CandleProvider, SymbolSearchProvider {
    private var providers: ProviderSet

    init(providers: ProviderSet) {
        self.providers = providers
    }

    /// Swap in a new provider set. Fetches already in flight keep using the providers
    /// they captured; subsequent fetches use the new set.
    func update(_ providers: ProviderSet) {
        self.providers = providers
    }

    func quote(for symbol: String) async throws -> Quote {
        try await providers.quote.quote(for: symbol)
    }

    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        try await providers.candle.candles(for: symbol, range: range)
    }

    func search(matching query: String) async throws -> [SymbolSearchResult] {
        try await providers.search.search(matching: query)
    }
}
