import Foundation
import Observation
import TickrCore

/// Drives the detail view for a single selected symbol: the price header (from a
/// ``Quote``) and the range-selectable close-price chart (from a ``CandleProvider``).
///
/// Lives in the app target because it is UI state, but it holds no SwiftUI/AppKit
/// types so it stays easy to unit test. Chart loading tolerates provider failures by
/// surfacing an explicit ``ChartState`` (empty/failed) rather than crashing, mirroring
/// ``SidebarViewModel``'s placeholder-on-failure approach.
@MainActor
@Observable
final class DetailViewModel {
    /// A single plotted point: the close price at a candle's timestamp. This is all the
    /// chart needs, decoupled from the full ``Candle`` so the view stays trivial.
    struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let close: Double

        var id: Date { date }
    }

    /// The chart's load state. Distinguishes "no candles came back" (``empty``) from
    /// "the provider threw" (``failed``) so the view can explain each differently.
    enum ChartState: Equatable {
        case loading
        case loaded([ChartPoint])
        case empty
        case failed
    }

    let symbol: String
    /// The latest quote for the header, or nil while loading or when it failed to load.
    private(set) var quote: Quote?
    /// The currently selected chart range. Change it via ``select(_:)``.
    private(set) var range: ChartRange
    private(set) var state: ChartState = .loading

    private let quoteProvider: QuoteProvider
    private let candleProvider: CandleProvider

    init(
        symbol: String,
        quoteProvider: QuoteProvider,
        candleProvider: CandleProvider,
        range: ChartRange = .day1
    ) {
        self.symbol = symbol
        self.quoteProvider = quoteProvider
        self.candleProvider = candleProvider
        self.range = range
    }

    /// Load the header quote and the chart series concurrently. A failed quote leaves
    /// ``quote`` nil (header shows a placeholder); a failed series is reflected in
    /// ``state`` — neither one blocks or breaks the other.
    func load() async {
        async let quoteLoad: Void = loadQuote()
        async let candleLoad: Void = loadCandles()
        _ = await (quoteLoad, candleLoad)
    }

    /// Switch the chart to a different range and reload its series. No-op if the range
    /// is already selected.
    func select(_ range: ChartRange) async {
        guard range != self.range else { return }
        self.range = range
        await loadCandles()
    }

    private func loadQuote() async {
        // A failed quote is tolerated: the header falls back to a placeholder.
        quote = try? await quoteProvider.quote(for: symbol)
    }

    private func loadCandles() async {
        state = .loading
        let requestedRange = range
        do {
            let series = try await candleProvider.candles(for: symbol, range: requestedRange)
            // Drop a stale response if the range changed while we were awaiting.
            guard requestedRange == range else { return }
            let points = Self.points(from: series)
            state = points.isEmpty ? .empty : .loaded(points)
        } catch {
            guard requestedRange == range else { return }
            state = .failed
        }
    }

    /// Map a series' candles to chart points, one per candle close, preserving order.
    static func points(from series: CandleSeries) -> [ChartPoint] {
        series.candles.map { ChartPoint(date: $0.timestamp, close: $0.close) }
    }
}
