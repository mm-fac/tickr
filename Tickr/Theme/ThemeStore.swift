import Foundation
import Observation

/// Minimal string key-value persistence backing ``ThemeStore``.
///
/// Introduced so the theme selection can persist to `UserDefaults` in production yet be
/// fully isolated to an in-memory store in unit tests and the deterministic UI-testing
/// launch — with *no* code path that falls back to `UserDefaults.standard`. The two
/// members are deliberately named so they don't collide with `UserDefaults`' own API,
/// keeping the conformance a trivial, unambiguous forward.
protocol ThemeDefaults: AnyObject {
    /// The persisted theme id for `key`, or nil when none is stored.
    func themeID(forKey key: String) -> String?
    /// Persist `id` for `key`.
    func setThemeID(_ id: String, forKey key: String)
}

extension UserDefaults: ThemeDefaults {
    func themeID(forKey key: String) -> String? { string(forKey: key) }
    func setThemeID(_ id: String, forKey key: String) { set(id, forKey: key) }
}

/// In-memory ``ThemeDefaults`` used by the UI-testing launch and unit tests. Starts empty
/// (so ``ThemeStore`` resolves to ``BuiltInTheme/fallback`` — `system`) and never touches
/// `UserDefaults`, giving each launch/test isolated, reset theme persistence.
final class InMemoryThemeDefaults: ThemeDefaults {
    private var storage: [String: String]

    init(storage: [String: String] = [:]) {
        self.storage = storage
    }

    func themeID(forKey key: String) -> String? { storage[key] }
    func setThemeID(_ id: String, forKey key: String) { storage[key] = id }
}

/// Holds the user's selected ``Theme`` and persists the choice across launches.
///
/// Only the theme's ``Theme/id`` is stored (via a ``ThemeDefaults``); the concrete theme is
/// resolved back through ``BuiltInTheme`` on load, so an unknown or removed id degrades
/// gracefully to ``BuiltInTheme/fallback`` instead of crashing. UI state, so it lives in
/// the app target, but it holds no SwiftUI types and stays unit-testable. Persistence is a
/// non-optional injected ``ThemeDefaults``, so a test/UI-testing store can never fall
/// through to `UserDefaults.standard`.
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
