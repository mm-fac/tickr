import AppKit
import SwiftUI
import TickrCore

/// Sidebar column of the app shell: a symbol search field over the favorites list (or an
/// empty state when there are no favorites yet). Typing shows live search results with an
/// add-to-favorites button; clearing the field returns to the favorites list. Layout only
/// — favorites state lives in ``SidebarViewModel``, search state in ``SymbolSearchViewModel``.
struct SidebarView: View {
    let model: SidebarViewModel
    @Bindable var search: SymbolSearchViewModel
    @Binding var selection: SidebarViewModel.Row.ID?

    var body: some View {
        Group {
            if isSearching {
                SearchResultsList(search: search)
            } else if model.rows.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Search above to add a symbol to track.")
                )
            } else {
                List(model.rows, selection: $selection) { row in
                    FavoriteRow(row: row) {
                        selection = row.id
                    }
                }
            }
        }
        .searchable(text: $search.query, placement: .sidebar, prompt: "Search symbols")
        // `.searchable` renders its own `NSSearchField` inside the window's toolbar; this
        // tags that real field with a stable identifier without replacing it (see
        // `SearchFieldIdentifierBridge` below).
        .background(SearchFieldIdentifierBridge(identifier: "sidebar.search"))
        .navigationTitle("Tickr")
        .task { await model.refresh() }
    }

    /// The search field is driving the sidebar whenever it has produced any non-idle
    /// state (searching, results, empty, or error).
    private var isSearching: Bool {
        search.state != .idle
    }
}

/// Bridges the real `NSSearchField` behind SwiftUI's native `.searchable` toolbar item to a
/// stable, non-localized accessibility identifier.
///
/// macOS has no SwiftUI modifier that reaches the field `.searchable` generates — it is
/// rendered through `NSSearchToolbarItem`, a public AppKit class. This drops one invisible,
/// zero-drawing `NSView` into the hierarchy that, once it has a window, looks up that
/// toolbar item and tags its `searchField` directly: the narrowest AppKit bridge that
/// reaches the single already-existing control, rather than attaching the identifier to the
/// `.searchable` container/content tree or substituting a custom text field.
private struct SearchFieldIdentifierBridge: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> TaggingView {
        TaggingView(accessibilityIdentifier: identifier)
    }

    func updateNSView(_ nsView: TaggingView, context: Context) {
        nsView.accessibilityIdentifierToApply = identifier
        nsView.tagSearchFieldIfNeeded()
    }

    // Named `accessibilityIdentifierToApply` (rather than `identifier`) because `NSView`
    // already declares its own `identifier: NSUserInterfaceItemIdentifier?`.
    final class TaggingView: NSView {
        var accessibilityIdentifierToApply: String

        init(accessibilityIdentifier: String) {
            self.accessibilityIdentifierToApply = accessibilityIdentifier
            super.init(frame: .zero)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate),
                name: NSWindow.didUpdateNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(toolbarWillAddItem),
                name: NSToolbar.willAddItemNotification,
                object: nil
            )
            tagSearchFieldIfNeeded()
            DispatchQueue.main.async { [weak self] in self?.tagSearchFieldIfNeeded() }
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            tagSearchFieldIfNeeded()
        }

        @objc private func toolbarWillAddItem(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in self?.tagSearchFieldIfNeeded() }
        }

        func tagSearchFieldIfNeeded() {
            let searchItems = window?.toolbar?.items.compactMap { $0 as? NSSearchToolbarItem } ?? []
            guard searchItems.count == 1, let searchItem = searchItems.first else { return }
            searchItem.searchField.setAccessibilityIdentifier(accessibilityIdentifierToApply)
        }
    }
}

/// Renders the search view model's current state: a spinner while loading, the results
/// with add buttons, or an explanation when nothing matched or the search failed.
private struct SearchResultsList: View {
    let search: SymbolSearchViewModel

    var body: some View {
        switch search.state {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results(let results):
            List(results) { result in
                SearchResultRow(
                    result: result,
                    isFavorited: search.isFavorited(result),
                    add: { search.add(result) }
                )
            }
        case .empty:
            ContentUnavailableView.search
        case .failed:
            ContentUnavailableView(
                "Search unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Couldn't search right now. Try again.")
            )
        }
    }
}

/// A single search hit: symbol and company name on the left, an add-to-favorites button
/// on the right that reads as already-added once the symbol is a favorite. The row is one
/// accessibility container (`search.result.<symbol>`); the still-separately-interactive add
/// button carries `search.addFavorite.<symbol>`.
private struct SearchResultRow: View {
    let result: SymbolSearchResult
    let isFavorited: Bool
    let add: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displaySymbol)
                    .font(.headline)
                Text(result.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isFavorited {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Added to favorites")
            } else {
                Button(action: add) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add \(result.displaySymbol) to favorites")
                .accessibilityLabel("Add \(result.displaySymbol) to favorites")
                .accessibilityIdentifier("search.addFavorite.\(result.symbol)")
            }
        }
        // Treat the row as a container: it exposes `search.result.<symbol>` as one element
        // without the id leaking onto the symbol/name text, while the add button stays a
        // distinct interactive child.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.result.\(result.symbol)")
    }
}

/// A single favorites row: symbol on the left, price and color-coded daily change
/// on the right. Shows a placeholder when the quote hasn't loaded or failed. Combined into
/// one accessibility element (`favorites.row.<symbol>`) so selecting it is unambiguous and
/// the id never propagates to its price/change descendants. It exposes both a button role and
/// a real default accessibility action that drives the same selection as clicking the List row.
private struct FavoriteRow: View {
    @Environment(\.theme) private var theme
    let row: SidebarViewModel.Row
    let select: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.symbol)
                .font(.headline)
            Spacer()
            if let quote = row.quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote.currentPrice, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                    Text(changeText(for: quote))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(changeColor(for: quote))
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Quote unavailable")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("favorites.row.\(row.symbol)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            select()
        }
    }

    private func changeText(for quote: Quote) -> String {
        String(format: "%+.2f%%", quote.percentChange)
    }

    private func changeColor(for quote: Quote) -> Color {
        if quote.percentChange > 0 { return theme.positiveChange }
        if quote.percentChange < 0 { return theme.negativeChange }
        return .secondary
    }
}
