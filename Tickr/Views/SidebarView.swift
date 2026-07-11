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
                    FavoriteRow(row: row, select: { selection = row.id })
                }
            }
        }
        .searchable(text: $search.query, placement: .sidebar, prompt: "Search symbols")
        // Tags the one real NSSearchField `.searchable` generates with a stable id;
        // see AccessibilityBridge — a plain modifier on this tree isn't sufficient.
        .background(SearchFieldAccessibilityTag(identifier: "sidebar.search"))
        .navigationTitle("Tickr")
        .task { await model.refresh() }
    }

    /// The search field is driving the sidebar whenever it has produced any non-idle
    /// state (searching, results, empty, or error).
    private var isSearching: Bool {
        search.state != .idle
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
/// on the right that reads as already-added once the symbol is a favorite.
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
        // `.contain` keeps the add button individually queryable while still giving the
        // row itself one stable, unambiguous identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.result.\(result.symbol)")
    }
}

/// A single favorites row: symbol on the left, price and color-coded daily change
/// on the right. Shows a placeholder when the quote hasn't loaded or failed.
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
        // Collapses the row into one stable, clickable accessibility element (rather
        // than leaking its symbol/price/change children as separate nodes sharing the
        // identifier) and wires a default action to the same selection the List's own
        // click already performs, so an AX-driven press opens the detail too.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("favorites.row.\(row.symbol)")
        .accessibilityLabel(Text(row.symbol))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
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
