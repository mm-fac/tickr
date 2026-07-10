/// Offline ``SymbolSearchProvider`` for previews, the un-configured app, and tests.
/// Filters a static catalog by case-insensitive substring on either the symbol or the
/// description, so it behaves enough like the real search to exercise the UI. Never
/// touches the network (AGENTS.md).
public struct MockSymbolSearchProvider: SymbolSearchProvider {
    private let catalog: [SymbolSearchResult]

    public init(catalog: [SymbolSearchResult] = MockSymbolSearchProvider.defaultCatalog) {
        self.catalog = catalog
    }

    public func search(matching query: String) async throws -> [SymbolSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        return catalog.filter {
            $0.symbol.lowercased().contains(normalizedQuery)
                || $0.description.lowercased().contains(normalizedQuery)
        }
    }

    public static let defaultCatalog: [SymbolSearchResult] = [
        SymbolSearchResult(symbol: "AAPL", description: "APPLE INC", displaySymbol: "AAPL", type: "Common Stock"),
        SymbolSearchResult(symbol: "MSFT", description: "MICROSOFT CORP", displaySymbol: "MSFT", type: "Common Stock"),
        SymbolSearchResult(symbol: "GOOG", description: "ALPHABET INC-CL C", displaySymbol: "GOOG", type: "Common Stock"),
        SymbolSearchResult(symbol: "GOOGL", description: "ALPHABET INC-CL A", displaySymbol: "GOOGL", type: "Common Stock"),
        SymbolSearchResult(symbol: "AMZN", description: "AMAZON.COM INC", displaySymbol: "AMZN", type: "Common Stock"),
        SymbolSearchResult(symbol: "NVDA", description: "NVIDIA CORP", displaySymbol: "NVDA", type: "Common Stock"),
        SymbolSearchResult(symbol: "TSLA", description: "TESLA INC", displaySymbol: "TSLA", type: "Common Stock"),
    ]
}
