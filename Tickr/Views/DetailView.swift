import Charts
import SwiftUI
import TickrCore

/// Detail column shown when a symbol is selected: a price header (symbol, current
/// price, color-coded daily change) above a range-selectable line chart of closes.
/// Layout only — all state lives in ``DetailViewModel``.
struct DetailView: View {
    @State private var model: DetailViewModel

    init(model: DetailViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PriceHeader(symbol: model.symbol, quote: model.quote)
            rangePicker
            chart
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(model.symbol)
        .task { await model.load() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: rangeBinding) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Chart range")
    }

    /// Bridges the view model's read-only ``DetailViewModel/range`` to the picker,
    /// kicking off a reload when the user changes it.
    private var rangeBinding: Binding<ChartRange> {
        Binding(
            get: { model.range },
            set: { newRange in Task { await model.select(newRange) } }
        )
    }

    @ViewBuilder
    private var chart: some View {
        switch model.state {
        case .loading:
            centered { ProgressView() }
        case .empty:
            centered {
                ContentUnavailableView(
                    "No chart data",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("No prices are available for \(model.symbol) over this range.")
                )
            }
        case .failed(let reason):
            centered {
                ContentUnavailableView(
                    "Couldn't load chart",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason ?? "Something went wrong loading prices for \(model.symbol).")
                )
            }
        case .loaded(let points):
            CloseChart(points: points)
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Symbol, current price, and color-coded daily change. Falls back to a placeholder
/// when the quote hasn't loaded or failed, so the header never blocks the chart.
private struct PriceHeader: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let quote: Quote?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(symbol)
                .font(.largeTitle.weight(.semibold))
            if let quote {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(quote.currentPrice, format: .number.precision(.fractionLength(2)))
                        .font(.title2)
                        .monospacedDigit()
                    Text(changeText(for: quote))
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(changeColor(for: quote))
                }
            } else {
                Text("Price unavailable")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changeText(for quote: Quote) -> String {
        String(format: "%+.2f (%+.2f%%)", quote.change, quote.percentChange)
    }

    private func changeColor(for quote: Quote) -> Color {
        if quote.percentChange > 0 { return theme.positiveChange }
        if quote.percentChange < 0 { return theme.negativeChange }
        return .secondary
    }
}

/// The line chart of close prices, drawn on the theme's surface. Colored by overall
/// direction (up/down use the theme's change colors), falling back to the theme's chart
/// line color when flat.
private struct CloseChart: View {
    @Environment(\.theme) private var theme
    let points: [DetailViewModel.ChartPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value("Close", point.close)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineColor)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(theme.background == .clear ? 0 : 12)
        .background(theme.background, in: RoundedRectangle(cornerRadius: theme.cornerStyle.radius))
        // Collapse the chart's data elements into a single, stably-identified element so
        // UI tests can assert the chart rendered without depending on pixel color.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Close price chart")
        .accessibilityIdentifier("detail.chart")
    }

    private var lineColor: Color {
        guard let first = points.first?.close, let last = points.last?.close else { return theme.chartLine }
        if last > first { return theme.positiveChange }
        if last < first { return theme.negativeChange }
        return theme.chartLine
    }
}

// MARK: - Range labels

extension ChartRange {
    /// Short label for the range picker (e.g. "1D", "1W").
    var displayName: String {
        switch self {
        case .day1: return "1D"
        case .week1: return "1W"
        case .month1: return "1M"
        case .year1: return "1Y"
        }
    }
}

#Preview("Loaded") {
    DetailView(model: DetailViewModel(
        symbol: "AAPL",
        quoteProvider: MockQuoteProvider(),
        candleProvider: PreviewCandleProvider()
    ))
    .frame(width: 640, height: 480)
}

#Preview("Error") {
    DetailView(model: DetailViewModel(
        symbol: "AAPL",
        quoteProvider: MockQuoteProvider(quotes: [:]),
        candleProvider: PreviewCandleProvider(failingSymbols: ["AAPL"])
    ))
    .frame(width: 640, height: 480)
}
