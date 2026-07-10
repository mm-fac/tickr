import Foundation

public final class FavoritesStore {
    public typealias ChangeHandler = ([String]) -> Void

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var favorites: [String]

    public var onChange: ChangeHandler?

    public var symbols: [String] {
        favorites
    }

    public init(fileURL: URL, onChange: ChangeHandler? = nil) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.onChange = onChange
        self.favorites = Self.load(from: fileURL, decoder: decoder)
    }

    @discardableResult
    public func add(_ symbol: String) throws -> Bool {
        let normalizedSymbol = Self.normalized(symbol)
        guard !normalizedSymbol.isEmpty, !favorites.contains(normalizedSymbol) else {
            return false
        }

        favorites.append(normalizedSymbol)
        try persistAndNotify()
        return true
    }

    @discardableResult
    public func remove(_ symbol: String) throws -> Bool {
        let normalizedSymbol = Self.normalized(symbol)
        guard let index = favorites.firstIndex(of: normalizedSymbol) else {
            return false
        }

        favorites.remove(at: index)
        try persistAndNotify()
        return true
    }

    public func contains(_ symbol: String) -> Bool {
        favorites.contains(Self.normalized(symbol))
    }

    @discardableResult
    public func move(from sourceIndex: Int, to destinationIndex: Int) throws -> Bool {
        guard favorites.indices.contains(sourceIndex), sourceIndex != destinationIndex else {
            return false
        }

        let clampedDestination = min(max(destinationIndex, 0), favorites.count - 1)
        let symbol = favorites.remove(at: sourceIndex)
        favorites.insert(symbol, at: clampedDestination)
        try persistAndNotify()
        return true
    }

    private func persistAndNotify() throws {
        let data = try encoder.encode(favorites)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        onChange?(favorites)
    }

    private static func load(from fileURL: URL, decoder: JSONDecoder) -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let decodedSymbols = try? decoder.decode([String].self, from: data)
        else {
            return []
        }

        return normalizedDeduplicated(decodedSymbols)
    }

    private static func normalizedDeduplicated(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedSymbols: [String] = []

        for symbol in symbols {
            let normalizedSymbol = normalized(symbol)
            guard !normalizedSymbol.isEmpty, seen.insert(normalizedSymbol).inserted else {
                continue
            }
            normalizedSymbols.append(normalizedSymbol)
        }

        return normalizedSymbols
    }

    private static func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
