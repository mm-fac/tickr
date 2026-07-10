import XCTest
import TickrCore
@testable import Tickr

final class PreviewCandleProviderTests: XCTestCase {
    func testProducesNonEmptySeriesForEveryRange() async throws {
        let provider = PreviewCandleProvider()
        for range in ChartRange.allCases {
            let series = try await provider.candles(for: "AAPL", range: range)
            XCTAssertFalse(series.candles.isEmpty, "Expected candles for \(range)")
            XCTAssertEqual(series.symbol, "AAPL")
            // Timestamps are strictly increasing.
            let timestamps = series.candles.map(\.timestamp)
            XCTAssertEqual(timestamps, timestamps.sorted())
        }
    }

    func testSeriesVaryByRange() async throws {
        let provider = PreviewCandleProvider()
        let day = try await provider.candles(for: "AAPL", range: .day1)
        let year = try await provider.candles(for: "AAPL", range: .year1)
        XCTAssertNotEqual(day.candles.count, year.candles.count)
        XCTAssertEqual(day.resolution, "5")
        XCTAssertEqual(year.resolution, "D")
    }

    func testIsDeterministicForSameInputs() async throws {
        let a = try await PreviewCandleProvider().candles(for: " aapl ", range: .month1)
        let b = try await PreviewCandleProvider().candles(for: "AAPL", range: .month1)
        XCTAssertEqual(a, b, "Same symbol/range should yield the same series.")
    }

    func testDifferentSymbolsProduceDifferentSeries() async throws {
        let provider = PreviewCandleProvider()
        let aapl = try await provider.candles(for: "AAPL", range: .day1)
        let msft = try await provider.candles(for: "MSFT", range: .day1)
        XCTAssertNotEqual(aapl.candles.map(\.close), msft.candles.map(\.close))
    }

    func testFailingSymbolThrows() async {
        let provider = PreviewCandleProvider(failingSymbols: ["AAPL"])
        do {
            _ = try await provider.candles(for: "aapl", range: .day1)
            XCTFail("Expected an error for a failing symbol")
        } catch let error as CandleProviderError {
            XCTAssertEqual(error, .noData(symbol: "AAPL", range: .day1))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
