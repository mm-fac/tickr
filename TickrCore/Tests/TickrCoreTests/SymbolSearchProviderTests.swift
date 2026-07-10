import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class SymbolSearchProviderTests: XCTestCase {
    func testDecodesFinnhubSearchJSONIntoResultsAndBuildsRequest() async throws {
        let client = SearchStubHTTPClient(
            data: Data(finnhubSearchJSON.utf8),
            response: try searchHTTPResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        let results = try await provider.search(matching: "  apple ")

        XCTAssertEqual(client.requests.count, 1)
        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "finnhub.io")
        XCTAssertEqual(components.path, "/api/v1/search")
        XCTAssertEqual(components.queryItems?.first { $0.name == "q" }?.value, "apple")
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "test-token")
        XCTAssertEqual(
            results,
            [
                SymbolSearchResult(symbol: "AAPL", description: "APPLE INC", displaySymbol: "AAPL", type: "Common Stock"),
                SymbolSearchResult(symbol: "APLE", description: "APPLE HOSPITALITY REIT INC", displaySymbol: "APLE", type: "Common Stock"),
            ]
        )
    }

    func testEmptyResultListDecodesToNoResults() async throws {
        let client = SearchStubHTTPClient(
            data: Data(#"{"count":0,"result":[]}"#.utf8),
            response: try searchHTTPResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        let results = try await provider.search(matching: "zzzz")

        XCTAssertTrue(results.isEmpty)
    }

    func testBlankQueryReturnsEmptyWithoutRequestingNetwork() async throws {
        let client = SearchStubHTTPClient(data: Data(), response: try searchHTTPResponse(statusCode: 200))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        let results = try await provider.search(matching: "   ")

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testHTTPErrorThrowsTypedError() async throws {
        let client = SearchStubHTTPClient(data: Data(), response: try searchHTTPResponse(statusCode: 429))
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.search(matching: "AAPL")
            XCTFail("Expected an HTTP error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .httpError(statusCode: 429))
        }
    }

    func testMalformedJSONThrowsTypedError() async throws {
        let client = SearchStubHTTPClient(
            data: Data(#"{"count":1,"result":[{"symbol":42}]}"#.utf8),
            response: try searchHTTPResponse(statusCode: 200)
        )
        let provider = FinnhubProvider(apiKey: "test-token", httpClient: client)

        do {
            _ = try await provider.search(matching: "AAPL")
            XCTFail("Expected a decoding error")
        } catch let error as FinnhubProviderError {
            XCTAssertEqual(error, .decodingFailed)
        }
    }

    func testMockSymbolSearchProviderFiltersCatalogBySubstring() async throws {
        let provider = MockSymbolSearchProvider()

        let bySymbol = try await provider.search(matching: "goog")
        XCTAssertEqual(bySymbol.map(\.symbol), ["GOOG", "GOOGL"])

        let byDescription = try await provider.search(matching: "microsoft")
        XCTAssertEqual(byDescription.map(\.symbol), ["MSFT"])

        let empty = try await provider.search(matching: "   ")
        XCTAssertTrue(empty.isEmpty)
    }
}

private let finnhubSearchJSON = #"""
{
  "count": 2,
  "result": [
    {
      "description": "APPLE INC",
      "displaySymbol": "AAPL",
      "symbol": "AAPL",
      "type": "Common Stock"
    },
    {
      "description": "APPLE HOSPITALITY REIT INC",
      "displaySymbol": "APLE",
      "symbol": "APLE",
      "type": "Common Stock"
    }
  ]
}
"""#

private final class SearchStubHTTPClient: HTTPClient, @unchecked Sendable {
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

private func searchHTTPResponse(statusCode: Int) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(URL(string: "https://example.com/search"))
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
}
