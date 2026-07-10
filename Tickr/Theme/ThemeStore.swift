import Foundation
import Observation

/// Holds the user's selected ``Theme`` and persists the choice across launches.
///
/// Only the theme's ``Theme/id`` is stored (via ``ThemeDefaults``, normally `UserDefaults`);
/// the concrete theme is resolved back through ``BuiltInTheme`` on load, so an unknown or
/// removed id degrades gracefully to ``BuiltInTheme/fallback`` instead of crashing. UI
/// state, so it lives in the app target, but it holds no SwiftUI types and stays
/// unit-testable. Persistence is injected as a non-optional ``ThemeDefaults`` so the
/// UI-testing launch mode can supply isolated in-memory storage with no fall-through to
/// `UserDefaults.standard`.
@MainActor
@Observable
final class ThemeStore {
    /// The currently selected theme.
    private(set) var selected: any Theme

    private let defaults: ThemeDefaults
    private let storageKey: String

    init(defaults: ThemeDefaults = UserDefaults.standard, storageKey: String = "selectedThemeID") {
        self.defaults = defaults
        self.storageKey = storageKey
        let storedID = defaults.themeID(forKey: storageKey) ?? BuiltInTheme.fallback.id
        self.selected = BuiltInTheme.theme(id: storedID)
    }

    /// Select `theme` and persist its id so the choice survives relaunch.
    func select(_ theme: any Theme) {
        selected = theme
        defaults.setThemeID(theme.id, forKey: storageKey)
    }
}
