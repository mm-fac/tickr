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
    private let clock: @Sendable () -> Date

    public init(
        apiKey: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.decoder = decoder
        self.clock = clock
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

extension FinnhubProvider: CandleProvider {
    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw FinnhubProviderError.invalidSymbol
        }

        let window = range.window(endingAt: clock())
        let request = try makeCandleRequest(for: normalizedSymbol, window: window)
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FinnhubProviderError.httpError(statusCode: response.statusCode)
        }

        do {
            let response = try decoder.decode(FinnhubCandleResponse.self, from: data)
            switch response.status {
            case "ok":
                return try response.series(symbol: normalizedSymbol, resolution: window.resolution)
            case "no_data":
                throw CandleProviderError.noData(symbol: normalizedSymbol, range: range)
            default:
                throw CandleProviderError.invalidData
            }
        } catch let error as CandleProviderError {
            throw error
        } catch {
            throw FinnhubProviderError.decodingFailed
        }
    }

    private func makeCandleRequest(for symbol: String, window: ChartWindow) throws -> URLRequest {
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
            components.path = "/api/v1/stock/candle"
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "resolution", value: window.resolution),
            URLQueryItem(name: "from", value: String(Int(window.from.timeIntervalSince1970))),
            URLQueryItem(name: "to", value: String(Int(window.to.timeIntervalSince1970))),
            URLQueryItem(name: "token", value: apiKey),
        ]
        guard let url = components.url else {
            throw FinnhubProviderError.invalidURL
        }
        return URLRequest(url: url)
    }
}

extension FinnhubProvider: SymbolSearchProvider {
    public func search(matching query: String) async throws -> [SymbolSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let request = try makeSearchRequest(for: trimmedQuery)
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FinnhubProviderError.httpError(statusCode: response.statusCode)
        }

        do {
            let searchResponse = try decoder.decode(FinnhubSearchResponse.self, from: data)
            return searchResponse.result.map { $0.asSymbolSearchResult }
        } catch {
            throw FinnhubProviderError.decodingFailed
        }
    }

    private func makeSearchRequest(for query: String) throws -> URLRequest {
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
            components.path = "/api/v1/search"
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "token", value: apiKey),
        ]
        guard let url = components.url else {
            throw FinnhubProviderError.invalidURL
        }
        return URLRequest(url: url)
    }
}

private struct FinnhubSearchResponse: Decodable {
    let count: Int
    let result: [Item]

    struct Item: Decodable {
        let description: String
        let displaySymbol: String
        let symbol: String
        let type: String

        var asSymbolSearchResult: SymbolSearchResult {
            SymbolSearchResult(
                symbol: symbol,
                description: description,
                displaySymbol: displaySymbol,
                type: type
            )
        }
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

private struct FinnhubCandleResponse: Decodable {
    let close: [Double]?
    let high: [Double]?
    let low: [Double]?
    let open: [Double]?
    let status: String
    let timestamps: [Int]?
    let volume: [Double]?

    private enum CodingKeys: String, CodingKey {
        case close = "c"
        case high = "h"
        case low = "l"
        case open = "o"
        case status = "s"
        case timestamps = "t"
        case volume = "v"
    }

    func series(symbol: String, resolution: String) throws -> CandleSeries {
        guard let close, let high, let low, let open, let timestamps, let volume else {
            throw CandleProviderError.invalidData
        }

        let count = timestamps.count
        guard [close.count, high.count, low.count, open.count, volume.count].allSatisfy({ $0 == count }) else {
            throw CandleProviderError.invalidData
        }

        let candles = timestamps.indices.map { index in
            Candle(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamps[index])),
                open: open[index],
                high: high[index],
                low: low[index],
                close: close[index],
                volume: volume[index]
            )
        }
        return CandleSeries(symbol: symbol, resolution: resolution, candles: candles)
    }
}
