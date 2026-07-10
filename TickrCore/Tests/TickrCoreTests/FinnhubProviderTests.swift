import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class FinnhubProviderTests: XCTestCase {
    func testDecodesFinnhubQuoteJSONIntoQuote() async throws {
        let client = StubHTTPClient(
            data: Data(finnhubQuoteJSON.utf8),
            response: try httpResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        let quote = try await provider.quote(for: " aapl ")

        XCTAssertEqual(client.requests.count, 1)
        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "finnhub.io")
        XCTAssertEqual(components.path, "/api/v1/quote")
        XCTAssertEqual(components.queryItems?.first { $0.name == "symbol" }?.value, "AAPL")
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "test-token")
        XCTAssertEqual(
            quote,
            Quote(
                symbol: "AAPL",
                currentPrice: 261.74,
                change: 3.23,
                percentChange: 1.2495,
                high: 263.31,
                low: 258.40,
                open: 259.12,
                previousClose: 258.51,
                timestamp: Date(timeIntervalSince1970: 1_709_596_800)
            )
        )
    }

    func testHTTPErrorThrowsTypedError() async throws {
        let client = StubHTTPClient(data: Data(), response: try httpResponse(statusCode: 429))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.quote(for: "MSFT")
            XCTFail("Expected an HTTP error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .httpError(statusCode: 429))
        }
    }

    func testMalformedJSONThrowsTypedError() async throws {
        let client = StubHTTPClient(
            data: Data(#"{"c":"not a number"}"#.utf8),
            response: try httpResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.quote(for: "MSFT")
            XCTFail("Expected a decoding error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .decodingFailed)
        }
    }

    func testBlankSymbolThrowsTypedErrorWithoutRequestingNetwork() async throws {
        let client = StubHTTPClient(data: Data(), response: try httpResponse(statusCode: 200))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.quote(for: "   ")
            XCTFail("Expected an invalid symbol error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .invalidSymbol)
        }
        XCTAssertTrue(client.requests.isEmpty)
    }
}

private let finnhubQuoteJSON = #"""
{
  "c": 261.74,
  "d": 3.23,
  "dp": 1.2495,
  "h": 263.31,
  "l": 258.40,
  "o": 259.12,
  "pc": 258.51,
  "t": 1709596800
}
"""#

private final class StubHTTPClient: HTTPClient, @unchecked Sendable {
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

private func httpResponse(statusCode: Int) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(URL(string: "https://example.com/quote"))
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
}

extension FinnhubProviderTests {
    func testDecodesFinnhubCandleJSONIntoCandleSeries() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_709_596_800)
        let client = StubHTTPClient(
            data: Data(finnhubCandlesJSON.utf8),
            response: try httpResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client, clock: FixedClock(now: fixedNow))

        let series = try await provider.candles(for: " aapl ", range: .day1)

        XCTAssertEqual(client.requests.count, 1)
        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "finnhub.io")
        XCTAssertEqual(components.path, "/api/v1/stock/candle")
        XCTAssertEqual(components.queryItems?.first { $0.name == "symbol" }?.value, "AAPL")
        XCTAssertEqual(components.queryItems?.first { $0.name == "resolution" }?.value, "5")
        XCTAssertEqual(components.queryItems?.first { $0.name == "from" }?.value, "1709510400")
        XCTAssertEqual(components.queryItems?.first { $0.name == "to" }?.value, "1709596800")
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "test-token")
        XCTAssertEqual(
            series,
            CandleSeries(
                symbol: "AAPL",
                resolution: "5",
                candles: [
                    Candle(
                        timestamp: Date(timeIntervalSince1970: 1_709_510_400),
                        open: 180.00,
                        high: 182.25,
                        low: 179.50,
                        close: 181.75,
                        volume: 1_000
                    ),
                    Candle(
                        timestamp: Date(timeIntervalSince1970: 1_709_510_700),
                        open: 181.75,
                        high: 183.00,
                        low: 181.25,
                        close: 182.50,
                        volume: 1_250
                    ),
                ]
            )
        )
    }

    func testFinnhubNoDataCandleStatusThrowsTypedError() async throws {
        let client = StubHTTPClient(
            data: Data(#"{"s":"no_data"}"#.utf8),
            response: try httpResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.candles(for: "MSFT", range: .week1)
            XCTFail("Expected a no data error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .noData)
        }
    }

    func testChartRangeWindowMappingIsDeterministic() {
        let endDate = Date(timeIntervalSince1970: 1_709_596_800)

        XCTAssertEqual(ChartRange.day1.finnhubResolution, "5")
        XCTAssertEqual(ChartRange.day1.window(endingAt: endDate), ChartWindow(from: Date(timeIntervalSince1970: 1_709_510_400), to: endDate))
        XCTAssertEqual(ChartRange.week1.finnhubResolution, "30")
        XCTAssertEqual(ChartRange.week1.window(endingAt: endDate), ChartWindow(from: Date(timeIntervalSince1970: 1_708_992_000), to: endDate))
        XCTAssertEqual(ChartRange.month1.finnhubResolution, "D")
        XCTAssertEqual(ChartRange.month1.window(endingAt: endDate), ChartWindow(from: Date(timeIntervalSince1970: 1_707_004_800), to: endDate))
        XCTAssertEqual(ChartRange.year1.finnhubResolution, "W")
        XCTAssertEqual(ChartRange.year1.window(endingAt: endDate), ChartWindow(from: Date(timeIntervalSince1970: 1_678_060_800), to: endDate))
    }
}

private let finnhubCandlesJSON = #"""
{
  "c": [181.75, 182.50],
  "h": [182.25, 183.00],
  "l": [179.50, 181.25],
  "o": [180.00, 181.75],
  "s": "ok",
  "t": [1709510400, 1709510700],
  "v": [1000, 1250]
}
"""#

private struct FixedClock: Clock {
    let now: Date
}
