import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class YahooCandleProviderTests: XCTestCase {
    func testBuildsYahooRequestsForEachRangeMapping() async throws {
        let cases: [(ChartRange, String, String)] = [
            (.day1, "1d", "5m"),
            (.week1, "5d", "30m"),
            (.month1, "1mo", "1d"),
            (.year1, "1y", "1wk"),
        ]

        for (range, expectedRange, expectedInterval) in cases {
            let client = YahooStubHTTPClient(data: Data(yahooValidJSON.utf8), response: try yahooHTTPResponse(statusCode: 200))
            let provider = YahooCandleProvider(httpClient: client)

            let series = try await provider.candles(for: " aapl ", range: range)

            XCTAssertEqual(series.symbol, "AAPL")
            XCTAssertEqual(series.resolution, expectedInterval)
            let request = try XCTUnwrap(client.requests.first)
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty, false)
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, "query1.finance.yahoo.com")
            XCTAssertEqual(components.path, "/v8/finance/chart/AAPL")
            XCTAssertEqual(components.queryItems?.first { $0.name == "range" }?.value, expectedRange)
            XCTAssertEqual(components.queryItems?.first { $0.name == "interval" }?.value, expectedInterval)
        }
    }

    func testParsesCandlesAndSkipsNullEntries() async throws {
        let client = YahooStubHTTPClient(data: Data(yahooValidJSON.utf8), response: try yahooHTTPResponse(statusCode: 200))
        let provider = YahooCandleProvider(httpClient: client)

        let series = try await provider.candles(for: "MSFT", range: .day1)

        XCTAssertEqual(series.candles, [
            Candle(timestamp: Date(timeIntervalSince1970: 1_704_067_200), open: 10, high: 12, low: 9, close: 11, volume: 1000),
            Candle(timestamp: Date(timeIntervalSince1970: 1_704_067_800), open: 20, high: 23, low: 19, close: 22, volume: 2000),
        ])
    }

    func testChartErrorThrowsTypedDescription() async throws {
        let client = YahooStubHTTPClient(data: Data(yahooErrorJSON.utf8), response: try yahooHTTPResponse(statusCode: 200))
        let provider = YahooCandleProvider(httpClient: client)

        do {
            _ = try await provider.candles(for: "SPY", range: .month1)
            XCTFail("Expected chart error")
        } catch let error as YahooCandleProviderError {
            XCTAssertEqual(error, .chartError(description: "No data found"))
        }
    }

    func testMalformedJSONThrowsInvalidData() async throws {
        let client = YahooStubHTTPClient(data: Data("not json".utf8), response: try yahooHTTPResponse(statusCode: 200))
        let provider = YahooCandleProvider(httpClient: client)

        do {
            _ = try await provider.candles(for: "NVDA", range: .year1)
            XCTFail("Expected invalid data")
        } catch let error as CandleProviderError {
            XCTAssertEqual(error, .invalidData)
        }
    }
}

private let yahooValidJSON = """
{
  "chart": {
    "result": [
      {
        "timestamp": [1704067200, 1704067500, 1704067800],
        "indicators": {
          "quote": [
            {
              "open": [10, null, 20],
              "high": [12, 13, 23],
              "low": [9, 8, 19],
              "close": [11, 12, 22],
              "volume": [1000, 1500, 2000]
            }
          ]
        }
      }
    ],
    "error": null
  }
}
"""

private let yahooErrorJSON = """
{
  "chart": {
    "result": null,
    "error": { "code": "Not Found", "description": "No data found" }
  }
}
"""

private final class YahooStubHTTPClient: HTTPClient, @unchecked Sendable {
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

private func yahooHTTPResponse(statusCode: Int) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/AAPL"))
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
}
