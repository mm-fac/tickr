import XCTest
import TickrCore
@testable import Tickr

@MainActor
final class SymbolSearchViewModelTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SymbolSearchViewModelTests-\(UUID().uuidString)", isDirectory: true)
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

    private func result(_ symbol: String, _ description: String? = nil) -> SymbolSearchResult {
        SymbolSearchResult(
            symbol: symbol,
            description: description ?? "\(symbol) INC",
            displaySymbol: symbol,
            type: "Common Stock"
        )
    }

    // MARK: - Debounce

    func testStartsIdle() throws {
        let model = SymbolSearchViewModel(provider: CountingSearchProvider(), store: try makeStore())
        XCTAssertEqual(model.state, .idle)
    }

    func testRapidQueryChangesDebounceIntoASingleSearchForTheLatestQuery() async throws {
        let provider = CountingSearchProvider(results: [result("AAPL")])
        let model = SymbolSearchViewModel(provider: provider, store: try makeStore(), debounce: .milliseconds(20))

        // Set synchronously (no awaits between): each change cancels the pending search,
        // so only the final query should ever reach the provider.
        model.query = "A"
        model.query = "AA"
        model.query = "AAP"
        model.query = "AAPL"

        await model.awaitPendingSearch()

        let queries = await provider.queries
        XCTAssertEqual(queries, ["AAPL"], "Debounce should collapse rapid typing into one search.")
        XCTAssertEqual(model.state, .results([result("AAPL")]))
    }

    func testClearingQueryReturnsToIdleWithoutSearching() async throws {
        let provider = CountingSearchProvider(results: [result("AAPL")])
        let model = SymbolSearchViewModel(provider: provider, store: try makeStore(), debounce: .milliseconds(20))

        model.query = "AAPL"
        await model.awaitPendingSearch()
        XCTAssertEqual(model.state, .results([result("AAPL")]))

        model.query = "   "
        await model.awaitPendingSearch()

        XCTAssertEqual(model.state, .idle)
        let queries = await provider.queries
        XCTAssertEqual(queries, ["AAPL"], "A blank query should not trigger another search.")
    }

    // MARK: - Result states

    func testEmptyResultsYieldEmptyState() async throws {
        let model = SymbolSearchViewModel(provider: CountingSearchProvider(results: []), store: try makeStore(), debounce: .milliseconds(20))

        model.query = "zzzz"
        await model.awaitPendingSearch()

        XCTAssertEqual(model.state, .empty)
    }

    func testProviderErrorYieldsFailedStateWithoutCrashing() async throws {
        let model = SymbolSearchViewModel(provider: ThrowingSearchProvider(), store: try makeStore(), debounce: .milliseconds(20))

        model.query = "AAPL"
        await model.awaitPendingSearch()

        XCTAssertEqual(model.state, .failed)
    }

    // MARK: - Add flow

    func testAddAppendsToStoreAndMarksResultFavorited() async throws {
        let store = try makeStore()
        let apple = result("AAPL", "APPLE INC")
        let model = SymbolSearchViewModel(provider: CountingSearchProvider(results: [apple]), store: store, debounce: .milliseconds(20))

        model.query = "apple"
        await model.awaitPendingSearch()
        XCTAssertFalse(model.isFavorited(apple))

        let added = model.add(apple)

        XCTAssertTrue(added)
        XCTAssertTrue(store.contains("AAPL"), "Adding should update the shared store.")
        XCTAssertTrue(model.isFavorited(apple), "The results list should reflect the add immediately.")
    }

    func testAddingAnAlreadyFavoritedSymbolIsANoOp() async throws {
        let store = try makeStore(symbols: ["AAPL"])
        let apple = result("AAPL", "APPLE INC")
        let model = SymbolSearchViewModel(provider: CountingSearchProvider(results: [apple]), store: store)

        XCTAssertTrue(model.isFavorited(apple), "A pre-existing favorite should read as added.")
        let added = model.add(apple)

        XCTAssertFalse(added, "Re-adding an existing favorite should report no change.")
        XCTAssertEqual(store.symbols, ["AAPL"], "The store should not gain a duplicate.")
    }

    func testAddingFromSearchUpdatesTheSidebarThroughTheSharedStore() async throws {
        let store = try makeStore()
        let quotes = ["AAPL": Quote(
            symbol: "AAPL", currentPrice: 200, change: 1, percentChange: 0.5,
            high: 201, low: 199, open: 199, previousClose: 199,
            timestamp: Date(timeIntervalSince1970: 1_709_596_800)
        )]
        let sidebar = SidebarViewModel(store: store, provider: MockQuoteProvider(quotes: quotes))
        let apple = result("AAPL", "APPLE INC")
        let search = SymbolSearchViewModel(provider: CountingSearchProvider(results: [apple]), store: store)
        await sidebar.refresh()
        XCTAssertTrue(sidebar.rows.isEmpty)

        search.add(apple)

        // The store's onChange (owned by the sidebar) schedules an async reload.
        let expectation = expectation(description: "sidebar shows the added symbol")
        Task { @MainActor in
            for _ in 0..<50 {
                if sidebar.rows.map(\.symbol) == ["AAPL"] {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(sidebar.rows.map(\.symbol), ["AAPL"])
    }
}

/// Records the queries it was asked to search and returns a fixed result set, so tests can
/// assert debounce coalescing and map query → results deterministically.
private actor CountingSearchProvider: SymbolSearchProvider {
    private(set) var queries: [String] = []
    private let results: [SymbolSearchResult]

    init(results: [SymbolSearchResult] = []) {
        self.results = results
    }

    func search(matching query: String) async throws -> [SymbolSearchResult] {
        queries.append(query)
        return results
    }
}

/// Always throws, to exercise the failed-search path.
private struct ThrowingSearchProvider: SymbolSearchProvider {
    struct Failure: Error {}
    func search(matching query: String) async throws -> [SymbolSearchResult] {
        throw Failure()
    }
}
