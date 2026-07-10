public protocol QuoteProvider: Sendable {
    func quote(for symbol: String) async throws -> Quote
    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries
}
