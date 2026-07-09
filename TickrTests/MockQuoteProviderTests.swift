import XCTest
import TickrCore
@testable import Tickr

final class MockQuoteProviderTests: XCTestCase {
    func testMockQuoteProviderReturnsCannedQuote() async throws {
        let expectedQuote = Quote(
            symbol: "MSFT",
            currentPrice: 430.25,
            change: -1.50,
            percentChange: -0.35,
            high: 435.00,
            low: 428.75,
            open: 432.10,
            previousClose: 431.75,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        )
        let provider = MockQuoteProvider(quotes: ["MSFT": expectedQuote])

        let quote = try await provider.quote(for: " msft ")

        XCTAssertEqual(quote, expectedQuote)
    }
}
