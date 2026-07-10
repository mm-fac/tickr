import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import TickrCore

final class ProviderSelectorTests: XCTestCase {

    // MARK: usableKey

    func testUsableKeyIsNilForNilOrBlank() {
        XCTAssertNil(ProviderSelector.usableKey(from: nil))
        XCTAssertNil(ProviderSelector.usableKey(from: ""))
        XCTAssertNil(ProviderSelector.usableKey(from: "   "))
        XCTAssertNil(ProviderSelector.usableKey(from: "\n\t "))
    }

    func testUsableKeyTrimsSurroundingWhitespace() {
        XCTAssertEqual(ProviderSelector.usableKey(from: "abc123"), "abc123")
        XCTAssertEqual(ProviderSelector.usableKey(from: "  abc123  "), "abc123")
        XCTAssertEqual(ProviderSelector.usableKey(from: "\tabc123\n"), "abc123")
    }

    // MARK: resolve — no key falls back to mocks

    func testResolveWithoutKeyReturnsMockSetUnchanged() {
        let mock = makeMockSet()
        let resolved = ProviderSelector.resolve(apiKey: nil, mock: mock, httpClient: StubHTTPClient())

        XCTAssertFalse(resolved.isLive)
        XCTAssertTrue(resolved.quote is StubQuoteProvider)
        XCTAssertTrue(resolved.candle is MockCandleProvider)
        XCTAssertTrue(resolved.search is MockSymbolSearchProvider)
    }

    func testResolveWithBlankKeyReturnsMockSet() {
        let mock = makeMockSet()
        let resolved = ProviderSelector.resolve(apiKey: "   ", mock: mock, httpClient: StubHTTPClient())

        XCTAssertFalse(resolved.isLive)
        XCTAssertTrue(resolved.quote is StubQuoteProvider)
    }

    // MARK: resolve — a key wires live Finnhub for all three roles

    func testResolveWithKeyWiresFinnhubForEveryRole() {
        let mock = makeMockSet()
        let resolved = ProviderSelector.resolve(apiKey: "finnhub-token", mock: mock, httpClient: StubHTTPClient())

        XCTAssertTrue(resolved.isLive)
        XCTAssertTrue(resolved.quote is FinnhubProvider)
        XCTAssertTrue(resolved.candle is FinnhubProvider)
        XCTAssertTrue(resolved.search is FinnhubProvider)
    }

    func testResolveTrimsKeyBeforeWiringLive() async throws {
        // A padded key still wires live and, when used, sends the trimmed token.
        let client = StubHTTPClient(
            data: Data(finnhubQuoteJSON.utf8),
            statusCode: 200
        )
        let resolved = ProviderSelector.resolve(apiKey: "  padded-token  ", mock: makeMockSet(), httpClient: client)
        XCTAssertTrue(resolved.isLive)

        _ = try await resolved.quote.quote(for: "AAPL")

        let requestURL = try XCTUnwrap(client.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "token" }?.value, "padded-token")
    }

    // MARK: helpers

    private func makeMockSet() -> ProviderSet {
        ProviderSet(
            quote: StubQuoteProvider(),
            candle: MockCandleProvider(),
            search: MockSymbolSearchProvider(),
            isLive: false
        )
    }
}

private struct StubQuoteProvider: QuoteProvider {
    func quote(for symbol: String) async throws -> Quote {
        Quote(
            symbol: symbol,
            currentPrice: 1,
            change: 0,
            percentChange: 0,
            high: 1,
            low: 1,
            open: 1,
            previousClose: 1,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}

private final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let data: Data
    private let statusCode: Int

    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

private let finnhubQuoteJSON = #"""
{ "c": 261.74, "d": 3.23, "dp": 1.2495, "h": 263.31, "l": 258.40, "o": 259.12, "pc": 258.51, "t": 1709596800 }
"""#
