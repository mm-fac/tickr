import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StooqCandleProviderError: Error, Equatable, Sendable {
    case invalidSymbol
    case invalidURL
    case httpError(statusCode: Int)
    case unsupportedRange(ChartRange)
}

public struct StooqCandleProvider: CandleProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL?
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = StooqCandleProvider.defaultCalendar
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.clock = clock
        self.calendar = calendar
    }

    public func candles(for symbol: String, range: ChartRange) async throws -> CandleSeries {
        guard range != .day1 else {
            throw StooqCandleProviderError.unsupportedRange(range)
        }

        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw StooqCandleProviderError.invalidSymbol
        }

        let request = try makeRequest(for: normalizedSymbol)
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw StooqCandleProviderError.httpError(statusCode: response.statusCode)
        }

        let allCandles = try Self.parseCandles(from: data, calendar: calendar)
        guard !allCandles.isEmpty else {
            throw CandleProviderError.noData(symbol: normalizedSymbol, range: range)
        }

        let window = range.window(endingAt: clock())
        let slicedCandles = allCandles.filter { candle in
            candle.timestamp >= window.from && candle.timestamp <= window.to
        }
        guard !slicedCandles.isEmpty else {
            throw CandleProviderError.noData(symbol: normalizedSymbol, range: range)
        }

        return CandleSeries(symbol: normalizedSymbol, resolution: "D", candles: slicedCandles)
    }

    private func makeRequest(for symbol: String) throws -> URLRequest {
        var components: URLComponents
        if let baseURL {
            guard let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw StooqCandleProviderError.invalidURL
            }
            components = baseComponents
        } else {
            components = URLComponents()
            components.scheme = "https"
            components.host = "stooq.com"
            components.path = "/q/d/l/"
        }
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(symbol.lowercased()).us"),
            URLQueryItem(name: "i", value: "d"),
        ]
        guard let url = components.url else {
            throw StooqCandleProviderError.invalidURL
        }
        return URLRequest(url: url)
    }

    private static func parseCandles(from data: Data, calendar: Calendar) throws -> [Candle] {
        guard let csv = String(data: data, encoding: .utf8) else {
            throw CandleProviderError.invalidData
        }

        return csv
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { parseRow(String($0), calendar: calendar) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static func parseRow(_ row: String, calendar: Calendar) -> Candle? {
        let columns = row.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
        guard columns.count == 6,
              let timestamp = date(from: columns[0], calendar: calendar),
              let open = Double(columns[1]),
              let high = Double(columns[2]),
              let low = Double(columns[3]),
              let close = Double(columns[4]),
              let volume = Double(columns[5]) else {
            return nil
        }

        return Candle(timestamp: timestamp, open: open, high: high, low: low, close: close, volume: volume)
    }

    private static func date(from value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static let defaultCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}
