import SwiftUI

/// A UI-only visual theme: the small set of colors and the corner style that give the
/// app its look. Themes are display-layer only, so they live in the app target rather
/// than TickrCore. Each theme is a value type identified by a stable ``id`` that is what
/// gets persisted (see ``ThemeStore``) and mapped back through ``BuiltInTheme``.
///
/// Views read the active theme from the environment (`@Environment(\.theme)`) rather than
/// reaching for `.green`/`.red`/`.accentColor` directly, so a single selection recolors
/// the whole app.
protocol Theme: Sendable {
    /// Stable identifier used for persistence and lookup. Never localize this.
    var id: String { get }
    /// Human-readable name shown in the theme picker.
    var name: String { get }
    /// Accent/tint color applied app-wide (controls, selection).
    var accent: Color { get }
    /// Surface background used behind chart content.
    var background: Color { get }
    /// Default line color for the price chart when direction is flat.
    var chartLine: Color { get }
    /// Color for a positive daily change.
    var positiveChange: Color { get }
    /// Color for a negative daily change.
    var negativeChange: Color { get }
    /// How sharply surfaces (chart panel) round their corners.
    var cornerStyle: ThemeCornerStyle { get }
}

/// The corner treatment a theme applies to its surfaces.
enum ThemeCornerStyle: String, CaseIterable, Sendable {
    case sharp
    case soft
    case round

    /// Corner radius in points for this style.
    var radius: CGFloat {
        switch self {
        case .sharp: return 0
        case .soft: return 8
        case .round: return 16
        }
    }
}

/// The default look: system accent and semantic red/green, matching stock macOS.
struct SystemTheme: Theme {
    let id = "system"
    let name = "System"
    let accent = Color.accentColor
    // Clear lets the platform's own window background show through.
    let background = Color.clear
    let chartLine = Color.accentColor
    let positiveChange = Color.green
    let negativeChange = Color.red
    let cornerStyle = ThemeCornerStyle.soft
}

/// A restrained monochrome look with sharp corners.
struct GraphiteTheme: Theme {
    let id = "graphite"
    let name = "Graphite"
    let accent = Color(red: 0.45, green: 0.47, blue: 0.50)
    let background = Color(red: 0.14, green: 0.15, blue: 0.16)
    let chartLine = Color(red: 0.82, green: 0.84, blue: 0.86)
    let positiveChange = Color(red: 0.56, green: 0.72, blue: 0.58)
    let negativeChange = Color(red: 0.80, green: 0.55, blue: 0.55)
    let cornerStyle = ThemeCornerStyle.sharp
}

/// Cool blues and teals with generously rounded corners.
struct OceanTheme: Theme {
    let id = "ocean"
    let name = "Ocean"
    let accent = Color(red: 0.16, green: 0.55, blue: 0.75)
    let background = Color(red: 0.06, green: 0.13, blue: 0.19)
    let chartLine = Color(red: 0.30, green: 0.72, blue: 0.82)
    let positiveChange = Color(red: 0.32, green: 0.78, blue: 0.64)
    let negativeChange = Color(red: 0.90, green: 0.45, blue: 0.44)
    let cornerStyle = ThemeCornerStyle.round
}

/// Warm oranges and pinks with generously rounded corners.
struct SunsetTheme: Theme {
    let id = "sunset"
    let name = "Sunset"
    let accent = Color(red: 0.92, green: 0.45, blue: 0.28)
    let background = Color(red: 0.16, green: 0.09, blue: 0.12)
    let chartLine = Color(red: 0.96, green: 0.62, blue: 0.35)
    let positiveChange = Color(red: 0.85, green: 0.73, blue: 0.36)
    let negativeChange = Color(red: 0.87, green: 0.35, blue: 0.44)
    let cornerStyle = ThemeCornerStyle.round
}

/// Registry of the shipped themes and lookup by persisted id.
enum BuiltInTheme {
    /// All built-in themes, in picker display order.
    static let all: [any Theme] = [SystemTheme(), GraphiteTheme(), OceanTheme(), SunsetTheme()]

    /// The theme used when nothing is persisted or a stored id is unknown.
    static let fallback: any Theme = SystemTheme()

    /// The built-in theme with `id`, or ``fallback`` if none matches.
    static func theme(id: String) -> any Theme {
        all.first { $0.id == id } ?? fallback
    }
}
