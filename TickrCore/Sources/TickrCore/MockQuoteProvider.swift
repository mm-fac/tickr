public actor MockQuoteProvider: QuoteProvider {
    public var quoteResult: Result<Quote, Error>
    public var candlesResult: Result<CandleSeries, Error>

    public init(
        quoteResult: Result<Quote, Error>,
        candlesResult: Result<CandleSeries, Error>
    ) {
        self.quoteResult = quoteResult
        self.candlesResult = candlesResult
    }

    public func quote(for symbol: String) async throws -> Quote {
        try quoteResult.get()
    }

    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        try candlesResult.get()
    }
}
