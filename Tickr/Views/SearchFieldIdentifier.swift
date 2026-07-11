import AppKit
import SwiftUI

/// Attaches a stable accessibility identifier to the *single* native `NSSearchField` that
/// SwiftUI's `.searchable(placement: .sidebar)` generates, so the XCUITest can address
/// exactly one interactive search control via `app.searchFields[identifier]`.
///
/// Why an AppKit bridge instead of `.accessibilityIdentifier` on `.searchable`: an
/// identifier placed on the searchable modifier propagates to the searchable *content*
/// (e.g. the empty-state `StaticText` nodes), not to the generated field — which produced a
/// duplicate-identifier / "multiple matching elements" failure in earlier attempts. The
/// real field is created as a split-view accessory (not a toolbar item) under the window's
/// content view, so we reach it directly through the AppKit hierarchy.
///
/// Fails closed: the identifier is applied only when exactly one `NSSearchField` is found.
/// If none exists yet (layout not settled) it retries; it never tags an ambiguous match, so
/// the test fails loudly rather than clicking the wrong node. Behaviorally inert for normal
/// launches — an accessibility identifier changes no user-visible behavior.
struct SearchFieldIdentifier: NSViewRepresentable {
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleTag(from: view, coordinator: context.coordinator, attempt: 0)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleTag(from: nsView, coordinator: context.coordinator, attempt: 0)
    }

    /// Polls the run loop until the sidebar's search field exists and is unique, then tags
    /// it once. The poll is bounded (~30s) so it can never spin forever; the XCUITest's own
    /// `waitForExistence` provides the real timeout budget.
    private func scheduleTag(from anchor: NSView, coordinator: Coordinator, attempt: Int) {
        guard !coordinator.tagged, attempt < 600 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !coordinator.tagged else { return }
            guard let window = anchor.window else {
                self.scheduleTag(from: anchor, coordinator: coordinator, attempt: attempt + 1)
                return
            }

            let fields = Self.searchFields(in: window)
            guard fields.count == 1, let field = fields.first else {
                // Zero (not laid out yet) or more than one (ambiguous): retry, never guess.
                self.scheduleTag(from: anchor, coordinator: coordinator, attempt: attempt + 1)
                return
            }

            field.setAccessibilityIdentifier(self.identifier)
            coordinator.tagged = true
        }
    }

    /// Every unique `NSSearchField` reachable in `window`: the split-view accessory field
    /// under the content view, plus any toolbar search item's field as a fallback for OS
    /// variants that host the sidebar search in the toolbar. Deduplicated by object
    /// identity so a field surfaced by both paths counts once.
    private static func searchFields(in window: NSWindow) -> [NSSearchField] {
        var found: [NSSearchField] = []

        if let content = window.contentView {
            collectSearchFields(in: content, into: &found)
        }
        if let toolbar = window.toolbar {
            for item in toolbar.items {
                if let searchItem = item as? NSSearchToolbarItem {
                    found.append(searchItem.searchField)
                }
            }
        }

        var unique: [NSSearchField] = []
        for field in found where !unique.contains(where: { $0 === field }) {
            unique.append(field)
        }
        return unique
    }

    private static func collectSearchFields(in view: NSView, into found: inout [NSSearchField]) {
        if let searchField = view as? NSSearchField {
            found.append(searchField)
        }
        for subview in view.subviews {
            collectSearchFields(in: subview, into: &found)
        }
    }

    /// Retains the one-shot latch so the poll stops re-arming once the field is tagged.
    final class Coordinator {
        var tagged = false
    }
}
