import Foundation

public actor MockCandleProvider: CandleProvider {
    private var results: [String: Result<CandleSeries, Error>]

    public init(results: [String: Result<CandleSeries, Error>] = [:]) {
        self.results = results
    }

    public func setResult(_ result: Result<CandleSeries, Error>, for symbol: String) {
        results[Self.key(for: symbol)] = result
    }

    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        let normalizedSymbol = Self.key(for: symbol)
        guard let result = results[normalizedSymbol] else {
            throw CandleProviderError.noData(symbol: normalizedSymbol, range: range)
        }
        return try result.get()
    }

    private static func key(for symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
