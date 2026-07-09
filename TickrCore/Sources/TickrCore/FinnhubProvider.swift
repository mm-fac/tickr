import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FinnhubProviderError: Error, Equatable, Sendable {
    case invalidSymbol
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed
}

public struct FinnhubProvider: QuoteProvider {
    private let apiKey: String
    private let httpClient: HTTPClient
    private let baseURL: URL?
    private let decoder: JSONDecoder

    public init(
        apiKey: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.decoder = decoder
    }

    public func quote(for symbol: String) async throws -> Quote {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw FinnhubProviderError.invalidSymbol
        }

        let request = try makeRequest(for: normalizedSymbol)
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FinnhubProviderError.httpError(statusCode: response.statusCode)
        }

        do {
            let finnhubQuote = try decoder.decode(FinnhubQuoteResponse.self, from: data)
            return Quote(
                symbol: normalizedSymbol,
                currentPrice: finnhubQuote.currentPrice,
                change: finnhubQuote.change,
                percentChange: finnhubQuote.percentChange,
                high: finnhubQuote.high,
                low: finnhubQuote.low,
                open: finnhubQuote.open,
                previousClose: finnhubQuote.previousClose,
                timestamp: Date(timeIntervalSince1970: TimeInterval(finnhubQuote.timestamp))
            )
        } catch {
            throw FinnhubProviderError.decodingFailed
        }
    }

    private func makeRequest(for symbol: String) throws -> URLRequest {
        var components: URLComponents
        if let baseURL {
            guard let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw FinnhubProviderError.invalidURL
            }
            components = baseComponents
        } else {
            components = URLComponents()
            components.scheme = "https"
            components.host = "finnhub.io"
            components.path = "/api/v1/quote"
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "token", value: apiKey),
        ]
        guard let url = components.url else {
            throw FinnhubProviderError.invalidURL
        }
        return URLRequest(url: url)
    }
}

private struct FinnhubQuoteResponse: Decodable {
    let currentPrice: Double
    let change: Double
    let percentChange: Double
    let high: Double
    let low: Double
    let open: Double
    let previousClose: Double
    let timestamp: Int

    private enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case change = "d"
        case percentChange = "dp"
        case high = "h"
        case low = "l"
        case open = "o"
        case previousClose = "pc"
        case timestamp = "t"
    }
}
