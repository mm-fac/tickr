import SwiftUI

/// Carries the active ``Theme`` down the view tree. Defaults to ``BuiltInTheme/fallback``
/// so any view reads a valid theme even outside an explicitly themed hierarchy (e.g.
/// previews and tests).
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: any Theme = BuiltInTheme.fallback
}

extension EnvironmentValues {
    /// The theme in effect for this view. Set once near the app root via
    /// `.environment(\.theme, ...)`; read with `@Environment(\.theme)`.
    var theme: any Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}
