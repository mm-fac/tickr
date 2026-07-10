import SwiftUI

/// Settings pane for the Finnhub API key. The key is written straight through to
/// ``APIKeyStore`` (and thus the Keychain); the app's routing providers read it live, so
/// entering or removing a key switches between live and sample data without a restart.
///
/// When no key is present the pane shows a gentle hint explaining that the app is on
/// sample data; once a key is stored it confirms live data is on.
struct APIKeySettingsView: View {
    let store: APIKeyStore

    /// Draft text for the field. Kept local so the actual key is only committed on Save
    /// and never mirrored into any other storage.
    @State private var draft: String = ""

    var body: some View {
        // Read `hasKey` here so this view observes the @Observable store and re-renders
        // the hint/buttons the moment a key is saved or cleared.
        let hasKey = store.hasKey
        return Form {
            Section {
                SecureField("Finnhub API key", text: $draft)
                    .accessibilityLabel("Finnhub API key")
                HStack {
                    Button("Save") {
                        store.save(draft)
                        draft = ""
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasKey {
                        Button("Remove Key", role: .destructive) {
                            store.clear()
                            draft = ""
                        }
                    }
                }
            } footer: {
                if hasKey {
                    Label("Live market data is on.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add a free Finnhub API key to switch from sample data to live quotes, charts, and search. Your key is stored in the macOS Keychain.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 220)
    }
}

#Preview {
    APIKeySettingsView(store: APIKeyStore(store: InMemoryPreviewSecretStore()))
}

/// Preview-only ``SecretStore`` so the pane renders without touching the Keychain.
private final class InMemoryPreviewSecretStore: SecretStore {
    private var storage: [String: String] = [:]
    func secret(for account: String) throws -> String? { storage[account] }
    func setSecret(_ secret: String?, for account: String) throws { storage[account] = secret }
}
