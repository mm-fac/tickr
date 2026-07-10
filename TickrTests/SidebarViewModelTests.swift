import XCTest
import TickrCore
@testable import Tickr

@MainActor
final class SidebarViewModelTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func makeStore(symbols: [String] = []) throws -> FavoritesStore {
        let store = FavoritesStore(fileURL: tempDirectory.appendingPathComponent("\(UUID().uuidString).json"))
        for symbol in symbols {
            try store.add(symbol)
        }
        return store
    }

    private func quote(_ symbol: String, price: Double, percentChange: Double) -> Quote {
        Quote(
            symbol: symbol,
            currentPrice: price,
            change: 0,
            percentChange: percentChange,
            high: price,
            low: price,
            open: price,
            previousClose: price,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        )
    }

    func testStartsEmptyWhenNoFavorites() throws {
        let viewModel = SidebarViewModel(store: try makeStore(), provider: MockQuoteProvider(quotes: [:]))
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func testRowsCarrySymbolsBeforeRefresh() throws {
        let viewModel = SidebarViewModel(store: try makeStore(symbols: ["AAPL", "MSFT"]), provider: MockQuoteProvider())
        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL", "MSFT"])
        XCTAssertTrue(viewModel.rows.allSatisfy { $0.quote == nil })
    }

    func testRefreshPopulatesRowDataInStoreOrder() async throws {
        let aapl = quote("AAPL", price: 200.12, percentChange: 0.63)
        let msft = quote("MSFT", price: 430.25, percentChange: -0.35)
        let provider = MockQuoteProvider(quotes: ["AAPL": aapl, "MSFT": msft])
        let viewModel = SidebarViewModel(store: try makeStore(symbols: ["AAPL", "MSFT"]), provider: provider)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL", "MSFT"])
        XCTAssertEqual(viewModel.rows[0].quote, aapl)
        XCTAssertEqual(viewModel.rows[1].quote, msft)
    }

    func testRefreshToleratesFailedQuoteWithPlaceholder() async throws {
        let aapl = quote("AAPL", price: 200.12, percentChange: 0.63)
        // Provider knows AAPL but not FAIL, so quoting FAIL throws.
        let provider = MockQuoteProvider(quotes: ["AAPL": aapl])
        let viewModel = SidebarViewModel(store: try makeStore(symbols: ["AAPL", "FAIL"]), provider: provider)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL", "FAIL"])
        XCTAssertEqual(viewModel.rows[0].quote, aapl)
        XCTAssertNil(viewModel.rows[1].quote, "A failed quote should leave a placeholder row, not crash or drop it.")
    }

    func testRefreshReflectsStoreChanges() async throws {
        let store = try makeStore(symbols: ["AAPL"])
        let provider = MockQuoteProvider(quotes: [
            "AAPL": quote("AAPL", price: 200.12, percentChange: 0.63),
            "MSFT": quote("MSFT", price: 430.25, percentChange: -0.35),
        ])
        let viewModel = SidebarViewModel(store: store, provider: provider)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL"])

        try store.add("MSFT")
        await viewModel.refresh()

        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL", "MSFT"])
        XCTAssertNotNil(viewModel.rows[1].quote)
    }

    func testStoreChangeHandlerReloadsRows() async throws {
        let store = try makeStore(symbols: ["AAPL"])
        let provider = MockQuoteProvider(quotes: [
            "AAPL": quote("AAPL", price: 200.12, percentChange: 0.63),
            "MSFT": quote("MSFT", price: 430.25, percentChange: -0.35),
        ])
        let viewModel = SidebarViewModel(store: store, provider: provider)
        await viewModel.refresh()

        // Mutating the store fires onChange, which schedules an async reload.
        try store.add("MSFT")

        let expectation = expectation(description: "rows include the added symbol")
        Task { @MainActor in
            for _ in 0..<50 {
                if viewModel.rows.map(\.symbol) == ["AAPL", "MSFT"] {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(viewModel.rows.map(\.symbol), ["AAPL", "MSFT"])
    }
}
