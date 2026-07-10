import XCTest
@testable import TickrCore

final class FavoritesStoreTests: XCTestCase {
    func testAddUppercasesAndDeduplicatesSymbols() throws {
        let store = FavoritesStore(fileURL: temporaryFileURL())

        XCTAssertTrue(try store.add("aapl"))
        XCTAssertFalse(try store.add(" AAPL "))
        XCTAssertTrue(try store.add("msft"))

        XCTAssertEqual(store.symbols, ["AAPL", "MSFT"])
        XCTAssertTrue(store.contains("aapl"))
        XCTAssertTrue(store.contains(" MSFT "))
    }

    func testRemoveDeletesSymbols() throws {
        let store = FavoritesStore(fileURL: temporaryFileURL())
        try store.add("AAPL")
        try store.add("MSFT")

        XCTAssertTrue(try store.remove("aapl"))
        XCTAssertFalse(try store.remove("GOOG"))

        XCTAssertEqual(store.symbols, ["MSFT"])
        XCTAssertFalse(store.contains("AAPL"))
    }

    func testMoveReordersSymbols() throws {
        let store = FavoritesStore(fileURL: temporaryFileURL())
        try store.add("AAPL")
        try store.add("MSFT")
        try store.add("GOOG")

        XCTAssertTrue(try store.move(from: 0, to: 2))
        XCTAssertEqual(store.symbols, ["MSFT", "GOOG", "AAPL"])
        XCTAssertFalse(try store.move(from: 9, to: 0))
    }

    func testPersistenceRoundTrip() throws {
        let fileURL = temporaryFileURL()
        let store = FavoritesStore(fileURL: fileURL)
        try store.add("aapl")
        try store.add("msft")
        try store.move(from: 1, to: 0)

        let reloadedStore = FavoritesStore(fileURL: fileURL)

        XCTAssertEqual(reloadedStore.symbols, ["MSFT", "AAPL"])
    }

    func testMissingFileStartsEmpty() {
        let store = FavoritesStore(fileURL: temporaryFileURL())

        XCTAssertEqual(store.symbols, [])
    }

    func testCorruptFileStartsEmptyAndDoesNotCrash() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: fileURL)

        let store = FavoritesStore(fileURL: fileURL)

        XCTAssertEqual(store.symbols, [])
    }

    func testChangeHandlerReceivesUpdatedSymbols() throws {
        let fileURL = temporaryFileURL()
        var changes: [[String]] = []
        let store = FavoritesStore(fileURL: fileURL) { symbols in
            changes.append(symbols)
        }

        try store.add("aapl")
        try store.add("msft")
        try store.remove("aapl")

        XCTAssertEqual(changes, [["AAPL"], ["AAPL", "MSFT"], ["MSFT"]])
    }

    private func temporaryFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("favorites.json")
    }
}
