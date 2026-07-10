import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class CandleProviderTests: XCTestCase {
    func testDecodesFinnhubCandleJSONIntoCandleSeriesAndBuildsRequest() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let client = CandleStubHTTPClient(data: Data(finnhubCandleJSON.utf8), response: try candleHTTPResponse(statusCode: 200))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client, clock: { fixedNow })

        let series = try await provider.candles(for: " aapl ", range: .day1)

        XCTAssertEqual(client.requests.count, 1)
        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "finnhub.io")
        XCTAssertEqual(components.path, "/api/v1/stock/candle")
        XCTAssertEqual(components.queryItems?.first { $0.name == "symbol" }?.value, "AAPL")
        XCTAssertEqual(components.queryItems?.first { $0.name == "resolution" }?.value, "5")
        XCTAssertEqual(components.queryItems?.first { $0.name == "from" }?.value, "1699913600")
        XCTAssertEqual(components.queryItems?.first { $0.name == "to" }?.value, "1700000000")
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "test-token")
        XCTAssertEqual(
            series,
            CandleSeries(
                symbol: "AAPL",
                resolution: "5",
                candles: [
                    Candle(timestamp: Date(timeIntervalSince1970: 1_699_913_600), open: 188.0, high: 190.0, low: 187.5, close: 189.5, volume: 1_500_000),
                    Candle(timestamp: Date(timeIntervalSince1970: 1_699_913_900), open: 189.5, high: 191.0, low: 189.0, close: 190.25, volume: 1_700_000),
                ]
            )
        )
    }

    func testNoDataStatusThrowsTypedError() async throws {
        let client = CandleStubHTTPClient(data: Data(#"{"s":"no_data"}"#.utf8), response: try candleHTTPResponse(statusCode: 200))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client, clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        do {
            _ = try await provider.candles(for: "MSFT", range: .week1)
            XCTFail("Expected no data error")
        } catch let error as CandleProviderError {
            XCTAssertEqual(error, .noData(symbol: "MSFT", range: .week1))
        }
    }

    func testChartRangeWindowsAreDeterministic() {
        let endDate = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(ChartRange.day1.window(endingAt: endDate), ChartWindow(resolution: "5", from: Date(timeIntervalSince1970: 1_699_913_600), to: endDate))
        XCTAssertEqual(ChartRange.week1.window(endingAt: endDate), ChartWindow(resolution: "30", from: Date(timeIntervalSince1970: 1_699_395_200), to: endDate))
        XCTAssertEqual(ChartRange.month1.window(endingAt: endDate), ChartWindow(resolution: "60", from: Date(timeIntervalSince1970: 1_697_408_000), to: endDate))
        XCTAssertEqual(ChartRange.year1.window(endingAt: endDate), ChartWindow(resolution: "D", from: Date(timeIntervalSince1970: 1_668_464_000), to: endDate))
    }

    func testMockCandleProviderReturnsSeededSeries() async throws {
        let series = CandleSeries(symbol: "AAPL", resolution: "D", candles: [])
        let provider = MockCandleProvider(results: ["AAPL": .success(series)])

        let returnedSeries = try await provider.candles(for: " aapl ", range: .year1)

        XCTAssertEqual(returnedSeries, series)
    }
}

private let finnhubCandleJSON = #"""
{
  "c": [189.5, 190.25],
  "h": [190.0, 191.0],
  "l": [187.5, 189.0],
  "o": [188.0, 189.5],
  "s": "ok",
  "t": [1699913600, 1699913900],
  "v": [1500000, 1700000]
}
"""#

private final class CandleStubHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let data: Data
    private let response: HTTPURLResponse

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (data, response)
    }
}

private func candleHTTPResponse(statusCode: Int) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(URL(string: "https://example.com/stock/candle"))
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
}
