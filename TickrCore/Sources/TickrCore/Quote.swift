import Foundation

public struct Quote: Codable, Equatable, Sendable {
    public let symbol: String
    public let currentPrice: Double
    public let change: Double
    public let percentChange: Double
    public let high: Double
    public let low: Double
    public let open: Double
    public let previousClose: Double
    public let timestamp: Date

    public init(
        symbol: String,
        currentPrice: Double,
        change: Double,
        percentChange: Double,
        high: Double,
        low: Double,
        open: Double,
        previousClose: Double,
        timestamp: Date
    ) {
        self.symbol = symbol
        self.currentPrice = currentPrice
        self.change = change
        self.percentChange = percentChange
        self.high = high
        self.low = low
        self.open = open
        self.previousClose = previousClose
        self.timestamp = timestamp
    }
}
