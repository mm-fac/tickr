/// Looks up tradable symbols by a free-text query (ticker or company name).
///
/// Additive companion to ``QuoteProvider`` / ``CandleProvider``: a type can adopt this
/// alongside them (as ``FinnhubProvider`` does) without changing any existing protocol.
public protocol SymbolSearchProvider: Sendable {
    /// Returns the symbols matching `query`, best match first. An empty array means the
    /// query was understood but matched nothing; implementations throw for transport or
    /// decoding failures.
    func search(matching query: String) async throws -> [SymbolSearchResult]
}
