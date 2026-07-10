import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FinnhubProviderError: Error, Equatable, Sendable {
    case invalidSymbol
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noData
    case decodingFailed
}

public struct FinnhubProvider: QuoteProvider {
    private let apiKey: String
    private let httpClient: HTTPClient
    private let baseURL: URL?
    private let decoder: JSONDecoder
    private let clock: Clock

    public init(
        apiKey: String,
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        clock: Clock = SystemClock()
    ) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.decoder = decoder
        self.clock = clock
    }

    public func quote(for symbol: String) async throws -> Quote {
        let normalizedSymbol = try normalize(symbol: symbol)
        let request = try makeRequest(path: "/api/v1/quote", queryItems: [
            URLQueryItem(name: "symbol", value: normalizedSymbol),
            URLQueryItem(name: "token", value: apiKey),
        ])
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

    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        let normalizedSymbol = try normalize(symbol: symbol)
        let window = range.window(endingAt: clock.now)
        let request = try makeRequest(path: "/api/v1/stock/candle", queryItems: [
            URLQueryItem(name: "symbol", value: normalizedSymbol),
            URLQueryItem(name: "resolution", value: range.finnhubResolution),
            URLQueryItem(name: "from", value: String(Int(window.from.timeIntervalSince1970))),
            URLQueryItem(name: "to", value: String(Int(window.to.timeIntervalSince1970))),
            URLQueryItem(name: "token", value: apiKey),
        ])
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw FinnhubProviderError.httpError(statusCode: response.statusCode)
        }

        do {
            let candleResponse = try decoder.decode(FinnhubCandleResponse.self, from: data)
            guard candleResponse.status != "no_data" else {
                throw FinnhubProviderError.noData
            }
            guard candleResponse.status == "ok" else {
                throw FinnhubProviderError.invalidResponse
            }
            let candles = try candleResponse.candles()
            return CandleSeries(symbol: normalizedSymbol, resolution: range.finnhubResolution, candles: candles)
        } catch let error as FinnhubProviderError {
            throw error
        } catch {
            throw FinnhubProviderError.decodingFailed
        }
    }

    private func normalize(symbol: String) throws -> String {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw FinnhubProviderError.invalidSymbol
        }
        return normalizedSymbol
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components: URLComponents
        if let baseURL {
            guard let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw FinnhubProviderError.invalidURL
            }
            components = baseComponents
            components.path = path
        } else {
            components = URLComponents()
            components.scheme = "https"
            components.host = "finnhub.io"
            components.path = path
        }
        components.queryItems = queryItems
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

private struct FinnhubCandleResponse: Decodable {
    let close: [Double]
    let high: [Double]
    let low: [Double]
    let open: [Double]
    let status: String
    let timestamps: [Int]
    let volume: [Double]

    private enum CodingKeys: String, CodingKey {
        case close = "c"
        case high = "h"
        case low = "l"
        case open = "o"
        case status = "s"
        case timestamps = "t"
        case volume = "v"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        close = try container.decodeIfPresent([Double].self, forKey: .close) ?? []
        high = try container.decodeIfPresent([Double].self, forKey: .high) ?? []
        low = try container.decodeIfPresent([Double].self, forKey: .low) ?? []
        open = try container.decodeIfPresent([Double].self, forKey: .open) ?? []
        timestamps = try container.decodeIfPresent([Int].self, forKey: .timestamps) ?? []
        volume = try container.decodeIfPresent([Double].self, forKey: .volume) ?? []
    }

    func candles() throws -> [Candle] {
        let count = timestamps.count
        guard close.count == count,
              high.count == count,
              low.count == count,
              open.count == count,
              volume.count == count else {
            throw FinnhubProviderError.invalidResponse
        }

        return (0..<count).map { index in
            Candle(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamps[index])),
                open: open[index],
                high: high[index],
                low: low[index],
                close: close[index],
                volume: volume[index]
            )
        }
    }
}
