import Foundation
import TickrCore

struct MockQuoteProvider: QuoteProvider {
    enum MockQuoteProviderError: Error, Equatable {
        case missingQuote(symbol: String)
    }

    private let quotes: [String: Quote]

    init(quotes: [String: Quote] = MockQuoteProvider.defaultQuotes) {
        self.quotes = Dictionary(uniqueKeysWithValues: quotes.map { key, value in
            (key.uppercased(), value)
        })
    }

    func quote(for symbol: String) async throws -> Quote {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let quote = quotes[normalizedSymbol] else {
            throw MockQuoteProviderError.missingQuote(symbol: normalizedSymbol)
        }
        return quote
    }

    private static let defaultQuotes: [String: Quote] = [
        "AAPL": Quote(
            symbol: "AAPL",
            currentPrice: 200.12,
            change: 1.25,
            percentChange: 0.63,
            high: 201.00,
            low: 198.50,
            open: 199.20,
            previousClose: 198.87,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        ),
    ]
}
