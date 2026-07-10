/// A single hit from a symbol search: enough to display the match and to add it to
/// favorites. Mirrors the fields Finnhub's `/search` endpoint returns.
public struct SymbolSearchResult: Codable, Equatable, Sendable, Identifiable {
    /// The canonical symbol used for quotes/favorites, e.g. `"AAPL"`.
    public let symbol: String
    /// Human-readable name of the instrument, e.g. `"APPLE INC"`.
    public let description: String
    /// The symbol as it should be shown to the user (may differ from ``symbol`` for
    /// non-US listings), e.g. `"AAPL"`.
    public let displaySymbol: String
    /// The instrument type, e.g. `"Common Stock"`.
    public let type: String

    public var id: String { symbol }

    public init(symbol: String, description: String, displaySymbol: String, type: String) {
        self.symbol = symbol
        self.description = description
        self.displaySymbol = displaySymbol
        self.type = type
    }
}
