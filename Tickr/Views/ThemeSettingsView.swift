import AppKit
import SwiftUI

/// Settings pane letting the user pick the app theme. The selection is written straight
/// through to ``ThemeStore`` (and thus persisted); the app root observes the store and
/// re-injects the chosen theme into the environment, so the whole UI recolors live.
///
/// The native inline ``Picker`` carries `settings.themePicker` as a container identifier
/// whose accessibility *value* is the currently selected theme id (`system`, `ocean`, …),
/// so a UI test can assert semantic state rather than color. Each row keeps its native
/// selectable behavior and additionally carries `settings.theme.<id>`.
struct ThemeSettingsView: View {
    let store: ThemeStore

    var body: some View {
        // Read the selected id here so this view observes the @Observable store and
        // re-renders (updating the highlighted row and the exposed value) on change.
        let selectedID = store.selected.id
        return Form {
            Picker("Theme", selection: themeIDBinding(current: selectedID)) {
                ForEach(BuiltInTheme.all, id: \.id) { theme in
                    Text(theme.name)
                        // The inline Picker wraps this label in a native radio NSButton.
                        // Tag that actual actionable control without replacing its UI.
                        .background(NativeButtonIdentifierBridge(
                            identifier: "settings.theme.\(theme.id)"
                        ))
                        .tag(theme.id)
                }
            }
            .pickerStyle(.inline)
            .accessibilityLabel("Theme")
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

/// Applies a stable identifier to the native `NSButton` SwiftUI creates for one inline
/// Picker option. Pairing the embedded label bridge with its adjacent native option avoids
/// localized labels, UI-test indexes, global view-tree searches, and replacement controls.
private struct NativeButtonIdentifierBridge: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> TaggingView {
        TaggingView(identifier: identifier)
    }

    func updateNSView(_ nsView: TaggingView, context: Context) {
        nsView.identifierToApply = identifier
        nsView.tagAssociatedButtonIfAvailable()
    }

    final class TaggingView: NSView {
        var identifierToApply: String

        init(identifier: String) {
            self.identifierToApply = identifier
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            tagAssociatedButtonIfAvailable()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tagAssociatedButtonIfAvailable()
            DispatchQueue.main.async { [weak self] in self?.tagAssociatedButtonIfAvailable() }
        }

        func tagAssociatedButtonIfAvailable() {
            // SwiftUI materializes an inline Picker option and this label bridge as
            // adjacent platform-view hosts. Walk outward until our branch has a previous
            // sibling, then tag the nearest preceding native button subtree. This keeps
            // each stable id paired with its own option without labels or global indexes.
            var branch: NSView = self
            while let parent = branch.superview {
                if let index = parent.subviews.firstIndex(where: { $0 === branch }), index > 0 {
                    for sibling in parent.subviews[..<index].reversed() {
                        if let button = Self.buttons(in: sibling).last {
                            button.setAccessibilityIdentifier(identifierToApply)
                            return
                        }
                    }
                }
                branch = parent
            }
        }

        private static func buttons(in view: NSView) -> [NSButton] {
            let current = (view as? NSButton).map { [$0] } ?? []
            return current + view.subviews.flatMap(buttons(in:))
        }
    }
}

#Preview {
    ThemeSettingsView(store: ThemeStore(defaults: InMemoryThemeDefaults()))
}
