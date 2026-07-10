import SwiftUI
import TickrCore

/// Sidebar column of the app shell: the favorites list with live quotes, or an
/// empty state when there are no favorites yet. Layout only — all state lives in
/// ``SidebarViewModel``.
struct SidebarView: View {
    let model: SidebarViewModel
    @Binding var selection: SidebarViewModel.Row.ID?

    var body: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Add a symbol to start tracking it.")
                )
            } else {
                List(model.rows, selection: $selection) { row in
                    FavoriteRow(row: row)
                }
            }
        }
        .navigationTitle("Tickr")
        .task { await model.refresh() }
    }
}

/// A single favorites row: symbol on the left, price and color-coded daily change
/// on the right. Shows a placeholder when the quote hasn't loaded or failed.
private struct FavoriteRow: View {
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
    }

    private func changeText(for quote: Quote) -> String {
        String(format: "%+.2f%%", quote.percentChange)
    }

    private func changeColor(for quote: Quote) -> Color {
        if quote.percentChange > 0 { return .green }
        if quote.percentChange < 0 { return .red }
        return .secondary
    }
}
