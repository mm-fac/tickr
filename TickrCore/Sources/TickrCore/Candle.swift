import Foundation

public struct Candle: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double

    public init(timestamp: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
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

public struct ChartWindow: Equatable, Sendable {
    public let resolution: String
    public let from: Date
    public let to: Date

    public init(resolution: String, from: Date, to: Date) {
        self.resolution = resolution
        self.from = from
        self.to = to
    }
}

public enum ChartRange: String, CaseIterable, Codable, Equatable, Sendable {
    case day1
    case week1
    case month1
    case year1

    public func window(endingAt endDate: Date = Date()) -> ChartWindow {
        let interval: TimeInterval
        let resolution: String

        switch self {
        case .day1:
            interval = 24 * 60 * 60
            resolution = "5"
        case .week1:
            interval = 7 * 24 * 60 * 60
            resolution = "30"
        case .month1:
            interval = 30 * 24 * 60 * 60
            resolution = "60"
        case .year1:
            interval = 365 * 24 * 60 * 60
            resolution = "D"
        }

        return ChartWindow(resolution: resolution, from: endDate.addingTimeInterval(-interval), to: endDate)
    }
}
