import XCTest

final class TargetWiringCanaryTests: XCTestCase {
    func testUITestTargetIsExecuted() {
        XCTFail("INTENTIONAL_XCUITEST_TARGET_CANARY")
    }
}
