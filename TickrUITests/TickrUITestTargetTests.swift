import XCTest

final class TickrUITestTargetTests: XCTestCase {
    func testTargetLoads() {
        XCTAssertEqual(Bundle(for: Self.self).bundleURL.pathExtension, "xctest")
    }
}
