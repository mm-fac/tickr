import SwiftUI
import TickrCore

/// The Settings scene (⌘,): a secure field for the Finnhub API key plus a status line
/// explaining whether the app is on live data or sample data. Layout only — all state
/// and persistence live in ``SettingsModel``. Saving takes effect immediately.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                SecureField(
                    "API key",
                    text: $model.keyDraft,
                    prompt: Text("Paste your Finnhub API key")
                )
                .textContentType(.password)
                .onSubmit { save() }

                HStack {
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                    statusLabel
                }
            } header: {
                Text("Finnhub API key")
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }

    private func save() {
        Task { await model.save() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if model.isLive {
            Label("Live data", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else {
            Label("Sample data", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let saveError = model.saveError {
            Text(saveError)
                .foregroundStyle(.red)
        } else if model.isLive {
            Text("Tickr is loading live quotes, charts, and search from Finnhub. Clear the field and save to return to sample data.")
        } else {
            Text("Add a free Finnhub API key to load live quotes, charts, and search. The key is stored in your macOS Keychain. Until then, Tickr shows sample data.")
        }
    }
}
