import XCTest
import TickrCore
@testable import Tickr

@MainActor
final class DetailViewModelTests: XCTestCase {
    private func quote(_ symbol: String, price: Double = 100, change: Double = 1, percentChange: Double = 1) -> Quote {
        Quote(
            symbol: symbol,
            currentPrice: price,
            change: change,
            percentChange: percentChange,
            high: price,
            low: price,
            open: price,
            previousClose: price - change,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        )
    }

    private func series(_ closes: [Double], symbol: String = "AAPL", resolution: String = "D") -> CandleSeries {
        let candles = closes.enumerated().map { index, close in
            Candle(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 300),
                open: close,
                high: close,
                low: close,
                close: close,
                volume: 1_000
            )
        }
        return CandleSeries(symbol: symbol, resolution: resolution, candles: candles)
    }

    func testStartsLoadingWithDefaultDayRange() {
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: MockCandleProvider()
        )
        XCTAssertEqual(model.range, .day1)
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.quote)
    }

    func testLoadMapsClosesToChartPointsInOrder() async throws {
        let closes = [10.0, 11.5, 9.25, 12.0]
        let provider = MockCandleProvider(results: ["AAPL": .success(series(closes))])
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: provider
        )

        await model.load()

        guard case .loaded(let points) = model.state else {
            return XCTFail("Expected loaded state, got \(model.state)")
        }
        XCTAssertEqual(points.map(\.close), closes)
        // Points preserve series order.
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    func testLoadPopulatesQuoteForHeader() async throws {
        let expected = quote("AAPL", price: 200.12, change: 1.25, percentChange: 0.63)
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(quotes: ["AAPL": expected]),
            candleProvider: MockCandleProvider(results: ["AAPL": .success(series([1, 2]))])
        )

        await model.load()

        XCTAssertEqual(model.quote, expected)
    }

    func testSeriesMappingDiffersPerRange() async throws {
        let byRange: [ChartRange: CandleSeries] = [
            .day1: series([1, 2, 3]),
            .week1: series([10, 20, 30, 40]),
            .month1: series([100, 200]),
            .year1: series([1000, 2000, 3000, 4000, 5000]),
        ]
        let provider = RangeKeyedCandleProvider(seriesByRange: byRange)
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: provider
        )
        // Establish the initial (.day1) load; selecting the already-current range is a
        // no-op, so the loop below relies on this to cover day1.
        await model.load()

        for range in ChartRange.allCases {
            await model.select(range)
            XCTAssertEqual(model.range, range)
            guard case .loaded(let points) = model.state else {
                return XCTFail("Expected loaded state for \(range), got \(model.state)")
            }
            XCTAssertEqual(points.map(\.close), byRange[range]?.candles.map(\.close))
        }
    }

    func testSelectSameRangeIsNoOpAndDoesNotRefetch() async throws {
        let provider = CountingCandleProvider(series: series([1, 2, 3]))
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: provider,
            range: .day1
        )
        await model.load()
        let callsAfterLoad = await provider.callCount

        await model.select(.day1)

        let callsAfterReselect = await provider.callCount
        XCTAssertEqual(callsAfterReselect, callsAfterLoad, "Re-selecting the current range should not refetch.")
    }

    func testEmptySeriesYieldsEmptyState() async throws {
        let provider = MockCandleProvider(results: ["AAPL": .success(series([]))])
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: provider
        )

        await model.load()

        XCTAssertEqual(model.state, .empty)
    }

    func testProviderErrorYieldsFailedStateWithoutCrashing() async throws {
        // MockCandleProvider throws noData for any symbol it wasn't seeded with.
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: MockCandleProvider()
        )

        await model.load()

        XCTAssertEqual(model.state, .failed)
    }

    func testFailedQuoteStillLoadsChart() async throws {
        // Quote provider has no AAPL (throws); candle provider does. The chart still loads.
        let provider = MockCandleProvider(results: ["AAPL": .success(series([5, 6, 7]))])
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(quotes: [:]),
            candleProvider: provider
        )

        await model.load()

        XCTAssertNil(model.quote, "A failed quote should leave the header placeholder, not throw.")
        guard case .loaded(let points) = model.state else {
            return XCTFail("Expected loaded state, got \(model.state)")
        }
        XCTAssertEqual(points.map(\.close), [5, 6, 7])
    }

    func testFailedRangeRecoversWhenSwitchingToAWorkingRange() async throws {
        // day1 fails, week1 succeeds — switching ranges recovers from an error.
        let provider = RangeKeyedCandleProvider(seriesByRange: [.week1: series([3, 4, 5])])
        let model = DetailViewModel(
            symbol: "AAPL",
            quoteProvider: MockQuoteProvider(),
            candleProvider: provider,
            range: .day1
        )

        await model.load()
        XCTAssertEqual(model.state, .failed)

        await model.select(.week1)
        guard case .loaded(let points) = model.state else {
            return XCTFail("Expected loaded state after switching range, got \(model.state)")
        }
        XCTAssertEqual(points.map(\.close), [3, 4, 5])
    }
}

/// Returns a different series per range (or throws when a range isn't seeded), so tests
/// can prove the view model maps the range it was asked for.
private struct RangeKeyedCandleProvider: CandleProvider {
    let seriesByRange: [ChartRange: CandleSeries]

    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        guard let series = seriesByRange[range] else {
            throw CandleProviderError.noData(symbol: symbol, range: range)
        }
        return series
    }
}

/// Counts how many times candles were requested, to assert re-selection doesn't refetch.
private actor CountingCandleProvider: CandleProvider {
    private let series: CandleSeries
    private(set) var callCount = 0

    init(series: CandleSeries) {
        self.series = series
    }

    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        callCount += 1
        return series
    }
}
