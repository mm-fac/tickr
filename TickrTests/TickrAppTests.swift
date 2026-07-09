import XCTest
@testable import Tickr

final class TickrAppTests: XCTestCase {
    func testFavoritesPlaceholderStartsEmpty() {
        let model = FavoritesPlaceholderModel()
        XCTAssertTrue(model.favorites.isEmpty)
    }
}
