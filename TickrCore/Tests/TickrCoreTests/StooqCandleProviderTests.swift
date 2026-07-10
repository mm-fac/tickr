import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class StooqCandleProviderTests: XCTestCase {
    func testParsesStooqCSVAndBuildsDailyRequest() async throws {
        let client = StooqStubHTTPClient(data: Data(stooqCSV.utf8), response: try stooqHTTPResponse(statusCode: 200))
        let provider = StooqCandleProvider(httpClient: client, clock: { date("2024-01-31") })

        let series = try await provider.candles(for: " aapl ", range: .month1)

        XCTAssertEqual(client.requests.count, 1)
        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "stooq.com")
        XCTAssertEqual(components.path, "/q/d/l/")
        XCTAssertEqual(components.queryItems?.first { $0.name == "s" }?.value, "aapl.us")
        XCTAssertEqual(components.queryItems?.first { $0.name == "i" }?.value, "d")
        XCTAssertEqual(series.symbol, "AAPL")
        XCTAssertEqual(series.resolution, "D")
        XCTAssertEqual(series.candles, [
            Candle(timestamp: date("2024-01-02"), open: 10, high: 12, low: 9, close: 11, volume: 1000),
            Candle(timestamp: date("2024-01-25"), open: 20, high: 23, low: 19, close: 22, volume: 2000),
        ])
    }

    func testSlicesDailySeriesForEachSupportedRange() async throws {
        let client = StooqStubHTTPClient(data: Data(stooqWindowCSV.utf8), response: try stooqHTTPResponse(statusCode: 200))
        let provider = StooqCandleProvider(httpClient: client, clock: { date("2024-01-31") })

        let week = try await provider.candles(for: "MSFT", range: .week1)
        let month = try await provider.candles(for: "MSFT", range: .month1)
        let year = try await provider.candles(for: "MSFT", range: .year1)

        XCTAssertEqual(week.candles.map(\.timestamp), [date("2024-01-25"), date("2024-01-31")])
        XCTAssertEqual(month.candles.map(\.timestamp), [date("2024-01-02"), date("2024-01-25"), date("2024-01-31")])
        XCTAssertEqual(year.candles.map(\.timestamp), [date("2023-01-31"), date("2023-02-01"), date("2024-01-02"), date("2024-01-25"), date("2024-01-31")])
    }

    func testMalformedRowsAreSkipped() async throws {
        let client = StooqStubHTTPClient(data: Data(stooqMalformedCSV.utf8), response: try stooqHTTPResponse(statusCode: 200))
        let provider = StooqCandleProvider(httpClient: client, clock: { date("2024-01-31") })

        let series = try await provider.candles(for: "NVDA", range: .month1)

        XCTAssertEqual(series.candles, [
            Candle(timestamp: date("2024-01-25"), open: 20, high: 23, low: 19, close: 22, volume: 2000),
        ])
    }

    func testEmptyResponseThrowsNoData() async throws {
        let client = StooqStubHTTPClient(data: Data("Date,Open,High,Low,Close,Volume\n".utf8), response: try stooqHTTPResponse(statusCode: 200))
        let provider = StooqCandleProvider(httpClient: client, clock: { date("2024-01-31") })

        do {
            _ = try await provider.candles(for: "SPY", range: .year1)
            XCTFail("Expected no data error")
        } catch let error as CandleProviderError {
            XCTAssertEqual(error, .noData(symbol: "SPY", range: .year1))
        }
    }

    func testDayRangeThrowsTypedUnsupportedError() async throws {
        let client = StooqStubHTTPClient(data: Data(stooqCSV.utf8), response: try stooqHTTPResponse(statusCode: 200))
        let provider = StooqCandleProvider(httpClient: client, clock: { date("2024-01-31") })

        do {
            _ = try await provider.candles(for: "AAPL", range: .day1)
            XCTFail("Expected unsupported range error")
        } catch let error as StooqCandleProviderError {
            XCTAssertEqual(error, .unsupportedRange(.day1))
            XCTAssertTrue(client.requests.isEmpty)
        }
    }
}

private let stooqCSV = """
Date,Open,High,Low,Close,Volume
2023-12-29,1,2,0.5,1.5,500
2024-01-02,10,12,9,11,1000
2024-01-25,20,23,19,22,2000
"""

private let stooqWindowCSV = """
Date,Open,High,Low,Close,Volume
2023-01-31,1,2,0.5,1.5,500
2023-02-01,2,3,1,2.5,600
2024-01-02,10,12,9,11,1000
2024-01-25,20,23,19,22,2000
2024-01-31,30,35,29,34,3000
"""

private let stooqMalformedCSV = """
Date,Open,High,Low,Close,Volume
not-a-date,10,12,9,11,1000
2024-01-24,not-number,12,9,11,1000
2024-01-25,20,23,19,22,2000
2024-01-26,20,23,19
"""

private final class StooqStubHTTPClient: HTTPClient, @unchecked Sendable {
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

private func stooqHTTPResponse(statusCode: Int) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(URL(string: "https://example.com/q/d/l/"))
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
}

private func date(_ value: String) -> Date {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date(timeIntervalSince1970: 0)
}
