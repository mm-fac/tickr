import SwiftUI

/// Settings pane letting the user pick the app theme. The selection is written straight
/// through to ``ThemeStore`` (and thus persisted); the app root observes the store and
/// re-injects the chosen theme into the environment, so the whole UI recolors live.
///
/// The list of themes is exposed as one accessibility container, `settings.themePicker`,
/// whose accessibility *value* is the currently selected theme id (`system`, `ocean`, …).
/// Each row is a distinct control identified by `settings.theme.<id>`, so a UI test can
/// select a theme and then assert semantic state (the picker's value) rather than color.
struct ThemeSettingsView: View {
    let store: ThemeStore

    var body: some View {
        // Read the selected id here so this view observes the @Observable store and
        // re-renders (updating the highlighted row and the exposed value) on change.
        let selectedID = store.selected.id
        return Form {
            Section("Theme") {
                ForEach(BuiltInTheme.all, id: \.id) { theme in
                    ThemeRow(
                        name: theme.name,
                        id: theme.id,
                        isSelected: theme.id == selectedID,
                        select: { store.select(theme) }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 240)
        // One container element carrying the picker id, with its value tracking the
        // selected theme id so the smoke can wait for `ocean` without reading pixels.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.themePicker")
        .accessibilityValue(selectedID)
    }
}

/// A single selectable theme row: the theme name with a checkmark when selected. A plain
/// button so it stays one interactive element identified by `settings.theme.<id>`.
private struct ThemeRow: View {
    let name: String
    let id: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.theme.\(id)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ThemeSettingsView(store: ThemeStore(defaults: InMemoryThemeDefaults()))
}
