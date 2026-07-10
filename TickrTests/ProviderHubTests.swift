import XCTest
import TickrCore
@testable import Tickr

final class ProviderHubTests: XCTestCase {

    func testHubForwardsToInitialProviders() async throws {
        let sample = quote("AAPL", price: 100)
        let hub = ProviderHub(providers: set(quote: MockQuoteProvider(quotes: ["AAPL": sample])))

        let result = try await hub.quote(for: "AAPL")

        XCTAssertEqual(result.currentPrice, 100)
    }

    func testUpdateSwapsProvidersForSubsequentFetches() async throws {
        let hub = ProviderHub(providers: set(quote: MockQuoteProvider(quotes: ["AAPL": quote("AAPL", price: 100)])))
        XCTAssertEqual(try await hub.quote(for: "AAPL").currentPrice, 100)

        await hub.update(set(quote: MockQuoteProvider(quotes: ["AAPL": quote("AAPL", price: 250)])))

        XCTAssertEqual(
            try await hub.quote(for: "AAPL").currentPrice,
            250,
            "After update the hub must serve the newly wired provider — the basis for live key changes without a restart."
        )
    }

    func testUpdateSwapsCandleAndSearchRolesToo() async throws {
        let series = CandleSeries(
            symbol: "AAPL",
            resolution: "D",
            candles: [Candle(timestamp: Date(timeIntervalSince1970: 0), open: 1, high: 2, low: 1, close: 2, volume: 10)]
        )
        let candleMock = MockCandleProvider()
        await candleMock.setResult(.success(series), for: "AAPL")
        let searchHit = SymbolSearchResult(symbol: "AAPL", description: "APPLE INC", displaySymbol: "AAPL", type: "Common Stock")

        let hub = ProviderHub(providers: set(quote: MockQuoteProvider(quotes: [:])))
        await hub.update(ProviderSet(
            quote: MockQuoteProvider(quotes: ["AAPL": quote("AAPL", price: 1)]),
            candle: candleMock,
            search: MockSymbolSearchProvider(catalog: [searchHit]),
            isLive: true
        ))

        let candles = try await hub.candles(for: "AAPL", range: .day1)
        XCTAssertEqual(candles.candles.count, 1)
        let results = try await hub.search(matching: "AAPL")
        XCTAssertEqual(results.first?.symbol, "AAPL")
    }

    // MARK: helpers

    private func set(quote: MockQuoteProvider) -> ProviderSet {
        ProviderSet(quote: quote, candle: PreviewCandleProvider(), search: MockSymbolSearchProvider(), isLive: false)
    }

    private func quote(_ symbol: String, price: Double) -> Quote {
        Quote(
            symbol: symbol,
            currentPrice: price,
            change: 0,
            percentChange: 0,
            high: price,
            low: price,
            open: price,
            previousClose: price,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        )
    }
}
