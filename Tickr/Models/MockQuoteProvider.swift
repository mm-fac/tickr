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
        "MSFT": Quote(
            symbol: "MSFT",
            currentPrice: 430.25,
            change: -1.50,
            percentChange: -0.35,
            high: 435.00,
            low: 428.75,
            open: 432.10,
            previousClose: 431.75,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        ),
        "GOOG": Quote(
            symbol: "GOOG",
            currentPrice: 175.40,
            change: 2.10,
            percentChange: 1.21,
            high: 176.00,
            low: 172.90,
            open: 173.50,
            previousClose: 173.30,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        ),
    ]
}
