import XCTest
@testable import TickrCore

final class TickrCoreTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(TickrCore.version.isEmpty)
    }
}
