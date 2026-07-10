import Foundation

/// Minimal string key–value persistence backing ``ThemeStore``.
///
/// Abstracted behind a protocol so the UI-testing launch mode can inject fully isolated
/// in-memory storage. Crucially, there is **no** code path from `--ui-testing` to
/// `UserDefaults.standard`: the app injects ``InMemoryThemeDefaults`` directly, so a
/// test-mode construction can never fall through to production defaults.
protocol ThemeDefaults: AnyObject {
    /// The persisted theme id for `key`, or nil when nothing is stored.
    func themeID(forKey key: String) -> String?
    /// Persist `id` for `key`; a nil `id` removes the stored value.
    func setThemeID(_ id: String?, forKey key: String)
}

/// Production persistence: the real ``UserDefaults`` (normally `.standard`). Distinct method
/// names avoid clashing with `UserDefaults`' own `string(forKey:)` / `set(_:forKey:)` API.
extension UserDefaults: ThemeDefaults {
    func themeID(forKey key: String) -> String? {
        string(forKey: key)
    }

    func setThemeID(_ id: String?, forKey key: String) {
        set(id, forKey: key)
    }
}

/// Isolated, in-memory ``ThemeDefaults`` used under `--ui-testing`. Starts empty (so
/// ``ThemeStore`` resolves the ``BuiltInTheme/fallback`` `system` theme) and never touches
/// `UserDefaults`, so the smoke test can drive theme selection without reading, writing, or
/// snapshotting any production defaults.
final class InMemoryThemeDefaults: ThemeDefaults {
    private var storage: [String: String]

    init(seed: [String: String] = [:]) {
        self.storage = seed
    }

    func themeID(forKey key: String) -> String? {
        storage[key]
    }

    func setThemeID(_ id: String?, forKey key: String) {
        storage[key] = id
    }
}
