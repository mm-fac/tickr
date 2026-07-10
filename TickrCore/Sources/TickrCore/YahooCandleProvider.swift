import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum YahooCandleProviderError: Error, Equatable, Sendable {
    case invalidSymbol
    case invalidURL
    case httpError(statusCode: Int)
    case chartError(description: String)
}

public struct YahooCandleProvider: CandleProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL?

    public init(httpClient: HTTPClient = URLSessionHTTPClient(), baseURL: URL? = nil) {
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw YahooCandleProviderError.invalidSymbol
        }

        let mapping = Self.mapping(for: range)
        let request = try makeRequest(for: normalizedSymbol, mapping: mapping)
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw YahooCandleProviderError.httpError(statusCode: response.statusCode)
        }

        let series = try Self.parseSeries(
            from: data,
            symbol: normalizedSymbol,
            range: range,
            resolution: mapping.interval
        )
        guard !series.candles.isEmpty else {
            throw CandleProviderError.noData(symbol: normalizedSymbol, range: range)
        }
        return series
    }

    private func makeRequest(for symbol: String, mapping: RangeMapping) throws -> URLRequest {
        var components: URLComponents
        if let baseURL {
            guard let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw YahooCandleProviderError.invalidURL
            }
            components = baseComponents
            components.path = components.path + "/\(symbol)"
        } else {
            components = URLComponents()
            components.scheme = "https"
            components.host = "query1.finance.yahoo.com"
            components.path = "/v8/finance/chart/\(symbol)"
        }
        components.queryItems = [
            URLQueryItem(name: "range", value: mapping.range),
            URLQueryItem(name: "interval", value: mapping.interval),
        ]
        guard let url = components.url else {
            throw YahooCandleProviderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func parseSeries(from data: Data, symbol: String, range: ChartRange, resolution: String) throws -> CandleSeries {
        let response: YahooChartResponse
        do {
            response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        } catch {
            throw CandleProviderError.invalidData
        }

        if let description = response.chart.error?.description {
            throw YahooCandleProviderError.chartError(description: description)
        }

        guard let result = response.chart.result?.first,
              let quote = result.indicators.quote.first else {
            throw CandleProviderError.noData(symbol: symbol, range: range)
        }

        let candles = result.timestamp.enumerated().compactMap { index, timestamp -> Candle? in
            guard let open = quote.open.value(at: index),
                  let high = quote.high.value(at: index),
                  let low = quote.low.value(at: index),
                  let close = quote.close.value(at: index),
                  let volume = quote.volume.value(at: index) else {
                return nil
            }
            return Candle(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: Double(volume)
            )
        }

        return CandleSeries(symbol: symbol, resolution: resolution, candles: candles)
    }

    private static func mapping(for range: ChartRange) -> RangeMapping {
        switch range {
        case .day1:
            RangeMapping(range: "1d", interval: "5m")
        case .week1:
            RangeMapping(range: "5d", interval: "30m")
        case .month1:
            RangeMapping(range: "1mo", interval: "1d")
        case .year1:
            RangeMapping(range: "1y", interval: "1wk")
        }
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

private struct RangeMapping: Sendable {
    let range: String
    let interval: String
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChart
}

private struct YahooChart: Decodable {
    let result: [YahooChartResult]?
    let error: YahooChartError?
}

private struct YahooChartError: Decodable {
    let description: String
}

private struct YahooChartResult: Decodable {
    let timestamp: [Int]
    let indicators: YahooIndicators
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuote]
}

private struct YahooQuote: Decodable {
    let open: [Double?]
    let high: [Double?]
    let low: [Double?]
    let close: [Double?]
    let volume: [Int?]
}

private extension Array where Element == Double? {
    func value(at index: Int) -> Double? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension Array where Element == Int? {
    func value(at index: Int) -> Int? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
