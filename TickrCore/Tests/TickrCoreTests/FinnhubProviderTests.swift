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
