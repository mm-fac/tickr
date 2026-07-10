import XCTest
import TickrCore
@testable import Tickr

final class DataSourceTests: XCTestCase {
    func testNilKeySelectsMock() {
        XCTAssertEqual(DataSource(apiKey: nil), .mock)
        XCTAssertFalse(DataSource(apiKey: nil).isLive)
    }

    func testEmptyKeySelectsMock() {
        XCTAssertEqual(DataSource(apiKey: ""), .mock)
    }

    func testWhitespaceKeySelectsMock() {
        XCTAssertEqual(DataSource(apiKey: "   \n\t "), .mock)
    }

    func testNonEmptyKeySelectsLive() {
        XCTAssertEqual(DataSource(apiKey: "abc123"), .live(apiKey: "abc123"))
        XCTAssertTrue(DataSource(apiKey: "abc123").isLive)
    }

    func testLiveKeyIsTrimmed() {
        XCTAssertEqual(DataSource(apiKey: "  abc123  "), .live(apiKey: "abc123"))
    }
}

/// Records the last symbol/query it was asked for and returns a tagged result, so routing
/// tests can tell which provider (live vs mock) actually answered.
private struct TagQuoteProvider: QuoteProvider {
    let tag: String
    func quote(for symbol: String) async throws -> Quote {
        Quote(
            symbol: tag,
            currentPrice: 0, change: 0, percentChange: 0,
            high: 0, low: 0, open: 0, previousClose: 0,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}

private struct TagCandleProvider: CandleProvider {
    let tag: String
    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        CandleSeries(symbol: tag, resolution: "D", candles: [])
    }
}

private struct TagSearchProvider: SymbolSearchProvider {
    let tag: String
    func search(matching query: String) async throws -> [SymbolSearchResult] {
        [SymbolSearchResult(symbol: tag, description: tag, displaySymbol: tag, type: "test")]
    }
}

@MainActor
final class ProviderRoutingTests: XCTestCase {
    private let account = "finnhub"

    private func makeKeyStore(key: String? = nil) -> APIKeyStore {
        let seed = key.map { [account: $0] } ?? [:]
        return APIKeyStore(store: InMemorySecretStore(seed: seed), account: account)
    }

    func testQuoteRoutesToMockWithoutKey() async {
        let router = RoutingQuoteProvider(
            keyStore: makeKeyStore(),
            makeLive: { _ in TagQuoteProvider(tag: "live") },
            mock: TagQuoteProvider(tag: "mock")
        )
        do {
            let quote = try await router.quote(for: "AAPL")
            XCTAssertEqual(quote.symbol, "mock")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQuoteRoutesToLiveWithKey() async {
        let router = RoutingQuoteProvider(
            keyStore: makeKeyStore(key: "k"),
            makeLive: { _ in TagQuoteProvider(tag: "live") },
            mock: TagQuoteProvider(tag: "mock")
        )
        do {
            let quote = try await router.quote(for: "AAPL")
            XCTAssertEqual(quote.symbol, "live")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveProviderReceivesCurrentKey() async {
        let keyStore = makeKeyStore(key: "secret-key")
        // Capture the key handed to makeLive to prove the current key is threaded through.
        actor Captured { var key: String?; func set(_ v: String) { key = v } }
        let captured = Captured()
        let router = RoutingQuoteProvider(
            keyStore: keyStore,
            makeLive: { key in
                Task { await captured.set(key) }
                return TagQuoteProvider(tag: "live")
            },
            mock: TagQuoteProvider(tag: "mock")
        )
        do {
            _ = try await router.quote(for: "AAPL")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let seen = await captured.key
        XCTAssertEqual(seen, "secret-key")
    }

    func testQuoteRoutingReactsToKeyChangeWithoutRebuild() async {
        let keyStore = makeKeyStore()
        let router = RoutingQuoteProvider(
            keyStore: keyStore,
            makeLive: { _ in TagQuoteProvider(tag: "live") },
            mock: TagQuoteProvider(tag: "mock")
        )

        // Starts on mocks...
        do {
            let quote = try await router.quote(for: "AAPL")
            XCTAssertEqual(quote.symbol, "mock")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // ...adding a key flips the same router instance to live, no restart.
        keyStore.save("live-key")
        do {
            let quote = try await router.quote(for: "AAPL")
            XCTAssertEqual(quote.symbol, "live")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // ...and clearing it reverts to mocks.
        keyStore.clear()
        do {
            let quote = try await router.quote(for: "AAPL")
            XCTAssertEqual(quote.symbol, "mock")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCandleRoutingRespectsKey() async {
        let keyStore = makeKeyStore()
        let router = RoutingCandleProvider(
            keyStore: keyStore,
            makeLive: { _ in TagCandleProvider(tag: "live") },
            mock: TagCandleProvider(tag: "mock")
        )
        do {
            let mockSeries = try await router.candles(for: "AAPL", range: .day1)
            XCTAssertEqual(mockSeries.symbol, "mock")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        keyStore.save("k")
        do {
            let liveSeries = try await router.candles(for: "AAPL", range: .day1)
            XCTAssertEqual(liveSeries.symbol, "live")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchRoutingRespectsKey() async {
        let keyStore = makeKeyStore()
        let router = RoutingSymbolSearchProvider(
            keyStore: keyStore,
            makeLive: { _ in TagSearchProvider(tag: "live") },
            mock: TagSearchProvider(tag: "mock")
        )
        do {
            let mockResults = try await router.search(matching: "ap")
            XCTAssertEqual(mockResults.first?.symbol, "mock")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        keyStore.save("k")
        do {
            let liveResults = try await router.search(matching: "ap")
            XCTAssertEqual(liveResults.first?.symbol, "live")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFactoryBuildsRoutingProviders() {
        let keyStore = makeKeyStore()
        XCTAssertTrue(ProviderFactory.quoteProvider(keyStore: keyStore) is RoutingQuoteProvider)
        XCTAssertTrue(ProviderFactory.candleProvider(keyStore: keyStore) is RoutingCandleProvider)
        XCTAssertTrue(ProviderFactory.searchProvider(keyStore: keyStore) is RoutingSymbolSearchProvider)
    }

    func testFactoryCandlesUseYahooWhenLive() {
        // Candles must route to Yahoo when live, since Finnhub's free tier blocks candles.
        let keyStore = makeKeyStore(key: "k")
        guard let router = ProviderFactory.candleProvider(keyStore: keyStore) as? RoutingCandleProvider else {
            return XCTFail("Expected a RoutingCandleProvider")
        }
        XCTAssertTrue(router.makeLive("k") is YahooCandleProvider)
    }

    func testFactoryQuotesAndSearchStayOnFinnhubWhenLive() {
        // Quotes and search remain on Finnhub; only candles use Yahoo.
        let keyStore = makeKeyStore(key: "k")
        guard let quoteRouter = ProviderFactory.quoteProvider(keyStore: keyStore) as? RoutingQuoteProvider else {
            return XCTFail("Expected a RoutingQuoteProvider")
        }
        guard let searchRouter = ProviderFactory.searchProvider(keyStore: keyStore) as? RoutingSymbolSearchProvider else {
            return XCTFail("Expected a RoutingSymbolSearchProvider")
        }
        XCTAssertTrue(quoteRouter.makeLive("k") is FinnhubProvider)
        XCTAssertTrue(searchRouter.makeLive("k") is FinnhubProvider)
    }
}
