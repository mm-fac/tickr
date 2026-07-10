import Foundation
import TickrCore

/// Generates a deterministic synthetic ``CandleSeries`` for any symbol and range.
///
/// Stands in for a real ``CandleProvider`` until Settings wires the live provider (a
/// later issue), mirroring how ``MockQuoteProvider`` backs the sidebar. Also used by
/// SwiftUI previews so the chart renders a plausible series for every range without
/// hitting the network. The series is a function of the symbol and range only, so the
/// same inputs always produce the same curve.
struct PreviewCandleProvider: CandleProvider {
    /// Symbols listed here throw instead of returning data, so callers can exercise the
    /// chart's error state in previews and manual testing.
    private let failingSymbols: Set<String>

    init(failingSymbols: Set<String> = []) {
        self.failingSymbols = Set(failingSymbols.map { Self.normalize($0) })
    }

    func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        let normalized = Self.normalize(symbol)
        if failingSymbols.contains(normalized) {
            throw CandleProviderError.noData(symbol: normalized, range: range)
        }
        return Self.series(for: normalized, range: range)
    }

    /// Build a synthetic series whose point count and spacing reflect the range, and
    /// whose price curve is seeded from the symbol so different symbols look different.
    static func series(for symbol: String, range: ChartRange) -> CandleSeries {
        let normalized = normalize(symbol)
        let window = range.window(endingAt: referenceDate)
        let count = pointCount(for: range)

        // Seed a base price and phase from the symbol so each looks distinct but stable.
        let seed = normalized.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let basePrice = 80.0 + Double(seed % 320)
        let phase = Double(seed % 7)
        let amplitude = basePrice * 0.06
        let trendPerStep = basePrice * 0.0015

        let span = window.to.timeIntervalSince(window.from)
        let step = count > 1 ? span / Double(count - 1) : 0

        let candles: [Candle] = (0..<count).map { i in
            let progress = Double(i)
            let wave = sin(progress * 0.35 + phase)
            let close = basePrice + amplitude * wave + trendPerStep * progress
            let open = close - amplitude * 0.1 * cos(progress * 0.35 + phase)
            let high = max(open, close) + amplitude * 0.12
            let low = min(open, close) - amplitude * 0.12
            let volume = 1_000_000 + Double((seed + i) % 500) * 1_000
            return Candle(
                timestamp: window.from.addingTimeInterval(step * progress),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume
            )
        }

        return CandleSeries(symbol: normalized, resolution: window.resolution, candles: candles)
    }

    /// Fixed reference "now" so previews and tests are deterministic.
    static let referenceDate = Date(timeIntervalSince1970: 1_709_596_800)

    private static func pointCount(for range: ChartRange) -> Int {
        switch range {
        case .day1: return 78
        case .week1: return 56
        case .month1: return 30
        case .year1: return 52
        }
    }

    private static func normalize(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
