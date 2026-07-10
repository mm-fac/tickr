import SwiftUI

/// The app's Settings window: a small tab bar (Data / Appearance) above the selected pane.
///
/// A custom, explicitly identified tab bar is used instead of `TabView` so each tab is a
/// real interactive control carrying a stable, non-localized accessibility identifier
/// (`settings.dataTab`, `settings.appearanceTab`). macOS `TabView` tab buttons can only be
/// addressed by localized title or positional index in UI tests — both of which the smoke
/// contract forbids — so they are unusable for a deterministic, id-based journey.
struct AppSettingsView: View {
    let apiKeyStore: APIKeyStore
    let themeStore: ThemeStore

    @State private var section: SettingsSection = .data

    enum SettingsSection: Hashable {
        case data
        case appearance
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SettingsTabButton(
                    title: "Data",
                    systemImage: "key",
                    isSelected: section == .data,
                    identifier: "settings.dataTab",
                    select: { section = .data }
                )
                SettingsTabButton(
                    title: "Appearance",
                    systemImage: "paintbrush",
                    isSelected: section == .appearance,
                    identifier: "settings.appearanceTab",
                    select: { section = .appearance }
                )
            }
            .padding(10)
            Divider()
            content
        }
        .frame(width: 380)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .data:
            APIKeySettingsView(store: apiKeyStore)
        case .appearance:
            ThemeSettingsView(store: themeStore)
        }
    }
}

/// A single tab in ``AppSettingsView``'s bar. One interactive ``Button`` element carrying
/// the given non-localized identifier, highlighted when it is the active section.
private struct SettingsTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let identifier: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(minWidth: 64)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.secondary.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    AppSettingsView(
        apiKeyStore: APIKeyStore(store: PreviewSettingsSecretStore()),
        themeStore: ThemeStore(defaults: InMemoryThemeDefaults())
    )
}

/// Preview-only ``SecretStore`` so the settings preview never touches the Keychain.
private final class PreviewSettingsSecretStore: SecretStore {
    private var storage: [String: String] = [:]
    func secret(for account: String) throws -> String? { storage[account] }
    func setSecret(_ secret: String?, for account: String) throws { storage[account] = secret }
}
