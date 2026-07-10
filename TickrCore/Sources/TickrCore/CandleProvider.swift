import Foundation

public protocol CandleProvider: Sendable {
    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries
}

public enum CandleProviderError: Error, Equatable, Sendable {
    case noData(symbol: String, range: ChartRange)
    case invalidData
}
