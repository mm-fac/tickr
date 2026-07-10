import SwiftUI

/// Settings pane letting the user pick the app theme. The selection is written straight
/// through to ``ThemeStore`` (and thus persisted); the app root observes the store and
/// re-injects the chosen theme into the environment, so the whole UI recolors live.
struct ThemeSettingsView: View {
    let store: ThemeStore

    var body: some View {
        // Read the selected id here so this view observes the @Observable store and
        // re-renders (updating the highlighted row) when the selection changes.
        let selectedID = store.selected.id
        return Form {
            Picker("Theme", selection: themeIDBinding(current: selectedID)) {
                ForEach(BuiltInTheme.all, id: \.id) { theme in
                    Text(theme.name).tag(theme.id)
                        // Stable, non-localized handle keyed by the theme id.
                        .accessibilityIdentifier("settings.theme.\(theme.id)")
                }
            }
            .pickerStyle(.inline)
            // Container so the picker is one findable element carrying the current theme id
            // as its accessibility value, while each option keeps its own selectable id.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Theme")
            // Stable handle plus the current theme id as the picker's accessibility value,
            // so UI tests assert semantic selection (`system` → `ocean`), not pixel color.
            .accessibilityIdentifier("settings.themePicker")
            .accessibilityValue(selectedID)
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 200)
    }

    /// Bridges the picker's `String` tags to the store, resolving the id back to a theme
    /// on selection.
    private func themeIDBinding(current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { store.select(BuiltInTheme.theme(id: $0)) }
        )
    }
}

#Preview {
    ThemeSettingsView(store: ThemeStore())
}
