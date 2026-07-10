import XCTest
import TickrCore
@testable import Tickr

@MainActor
final class TickrAppTests: XCTestCase {
    func testSidebarStartsEmptyWithNoFavorites() throws {
        let store = FavoritesStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TickrAppTests-\(UUID().uuidString).json")
        )
        let viewModel = SidebarViewModel(store: store, provider: MockQuoteProvider())
        XCTAssertTrue(viewModel.rows.isEmpty)
    }
}
