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
        VStack(spacing: 0) {
            // A dedicated search field (rather than `.searchable`) so exactly one
            // interactive control carries the `sidebar.search` identifier — the macOS
            // `.searchable` field cannot be uniquely identified without third-party
            // introspection, and decorating its container leaks the id onto sibling text.
            SidebarSearchField(text: $search.query)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            Divider()
            content
        }
        .navigationTitle("Tickr")
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
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
                FavoriteRow(row: row)
            }
        }
    }

    /// The search field is driving the sidebar whenever it has produced any non-idle
    /// state (searching, results, empty, or error).
    private var isSearching: Bool {
        search.state != .idle
    }
}

/// A single interactive search field for the sidebar. A magnifying-glass affordance and a
/// clear button flank a plain ``TextField`` that carries the `sidebar.search` identifier as
/// one accessibility element, preserving type-to-search / clear-to-return behavior.
private struct SidebarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search symbols", text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("sidebar.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
/// one interactive accessibility element (`favorites.row.<symbol>`) so selecting it is
/// unambiguous and the id never propagates to its price/change descendants.
private struct FavoriteRow: View {
    @Environment(\.theme) private var theme
    let row: SidebarViewModel.Row

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
