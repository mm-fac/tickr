import Foundation
import Observation
import TickrCore

/// Drives the sidebar's favorites list. Reads the favorited symbols from
/// ``FavoritesStore`` and loads a live ``Quote`` for each via a ``QuoteProvider``.
///
/// Lives in the app target (not TickrCore) because it is UI state, but it holds no
/// SwiftUI/AppKit types so it stays easy to unit test. A quote that fails to load
/// leaves its row's ``Row/quote`` nil, so the view shows a placeholder instead of
/// crashing or dropping the row.
@MainActor
@Observable
final class SidebarViewModel {
    /// Display state for a single favorited symbol.
    struct Row: Identifiable, Equatable {
        let symbol: String
        /// The latest quote, or nil when it has not loaded yet or failed to load.
        let quote: Quote?

        var id: String { symbol }
    }

    private(set) var rows: [Row]

    private let store: FavoritesStore
    private let provider: QuoteProvider

    init(store: FavoritesStore, provider: QuoteProvider) {
        self.store = store
        self.provider = provider
        self.rows = store.symbols.map { Row(symbol: $0, quote: nil) }

        store.onChange = { [weak self] symbols in
            Task { @MainActor in
                await self?.reload(symbols: symbols)
            }
        }
    }

    /// Reload quotes for the current favorites.
    func refresh() async {
        await reload(symbols: store.symbols)
    }

    private func reload(symbols: [String]) async {
        // Reflect the symbol list immediately, reusing any quotes we already have so
        // rows don't flash to a placeholder while fresh quotes load.
        let existing = Dictionary(rows.map { ($0.symbol, $0.quote) }, uniquingKeysWith: { first, _ in first })
        rows = symbols.map { Row(symbol: $0, quote: existing[$0] ?? nil) }

        // Fetch quotes concurrently; a failure yields a nil quote (placeholder) rather
        // than throwing out of the whole reload.
        let loaded = await withTaskGroup(of: (String, Quote?).self) { group in
            for symbol in symbols {
                group.addTask { [provider] in
                    (symbol, try? await provider.quote(for: symbol))
                }
            }

            var result: [String: Quote?] = [:]
            for await (symbol, quote) in group {
                result[symbol] = quote
            }
            return result
        }

        rows = symbols.map { Row(symbol: $0, quote: loaded[$0] ?? nil) }
    }
}
