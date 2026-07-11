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
                }
            }
            .pickerStyle(.inline)
            .accessibilityLabel("Theme")
            // Non-interactive value container: exposes the current selection as its
            // accessibility value so a test can assert semantic state, not pixel color.
            .accessibilityIdentifier("settings.themePicker")
            .accessibilityValue(selectedID)
            // Tags each native inline-picker option (a real AXRadioButton) with
            // `settings.theme.<id>`; see AccessibilityBridge for why.
            .background(ThemeOptionsAccessibilityTag(themeIDs: BuiltInTheme.all.map(\.id)))
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
