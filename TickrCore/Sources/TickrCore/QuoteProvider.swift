public protocol QuoteProvider: Sendable {
    func quote(for symbol: String) async throws -> Quote
}
