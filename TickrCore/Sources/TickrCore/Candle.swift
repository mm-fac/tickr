import Foundation

public struct Candle: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double

    public init(
        timestamp: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double
    ) {
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

public struct CandleSeries: Codable, Equatable, Sendable {
    public let symbol: String
    public let resolution: String
    public let candles: [Candle]

    public init(symbol: String, resolution: String, candles: [Candle]) {
        self.symbol = symbol
        self.resolution = resolution
        self.candles = candles
    }
}

public enum ChartRange: String, Codable, CaseIterable, Equatable, Sendable {
    case day1
    case week1
    case month1
    case year1

    public var finnhubResolution: String {
        switch self {
        case .day1:
            return "5"
        case .week1:
            return "30"
        case .month1:
            return "D"
        case .year1:
            return "W"
        }
    }

    public func window(endingAt endDate: Date) -> ChartWindow {
        let duration: TimeInterval
        switch self {
        case .day1:
            duration = 24 * 60 * 60
        case .week1:
            duration = 7 * 24 * 60 * 60
        case .month1:
            duration = 30 * 24 * 60 * 60
        case .year1:
            duration = 365 * 24 * 60 * 60
        }
        return ChartWindow(from: endDate.addingTimeInterval(-duration), to: endDate)
    }
}

public struct ChartWindow: Equatable, Sendable {
    public let from: Date
    public let to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }
}
