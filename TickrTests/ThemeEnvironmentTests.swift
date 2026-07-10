import SwiftUI
import XCTest
@testable import Tickr

/// Smoke tests for theme propagation through the SwiftUI environment: the key defaults to
/// the fallback theme, and an assigned theme reads back through `EnvironmentValues.theme`
/// (the same value the app root sets and every view reads).
final class ThemeEnvironmentTests: XCTestCase {
    func testEnvironmentDefaultsToFallbackTheme() {
        let values = EnvironmentValues()
        XCTAssertEqual(values.theme.id, BuiltInTheme.fallback.id)
    }

    func testEnvironmentPropagatesAssignedTheme() {
        var values = EnvironmentValues()
        values.theme = SunsetTheme()
        XCTAssertEqual(values.theme.id, SunsetTheme().id)
    }

    func testEnvironmentCarriesEachBuiltInTheme() {
        for theme in BuiltInTheme.all {
            var values = EnvironmentValues()
            values.theme = theme
            XCTAssertEqual(values.theme.id, theme.id)
            XCTAssertEqual(values.theme.cornerStyle, theme.cornerStyle)
        }
    }
}
