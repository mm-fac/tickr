import Foundation
import Observation
import TickrCore

/// Drives the sidebar's symbol-search field: debounces the query, runs it through a
/// ``SymbolSearchProvider``, and adds a chosen result to the ``FavoritesStore``.
///
/// Lives in the app target (it is UI state) but holds no SwiftUI/AppKit types so it
/// stays unit-testable. Mirrors ``SidebarViewModel``'s tolerance of provider failures:
/// a failed search surfaces an explicit ``SearchState/failed`` rather than throwing.
///
/// Does not claim ``FavoritesStore/onChange`` (``SidebarViewModel`` owns that). Instead
/// it snapshots the favorited set when searching and after adding, so results can be
/// marked as already-added without fighting the sidebar for the single change handler.
@MainActor
@Observable
final class SymbolSearchViewModel {
    /// The search field's load state. Distinguishes "understood but matched nothing"
    /// (``empty``) from "the provider threw" (``failed``) so the view explains each.
    enum SearchState: Equatable {
        case idle
        case searching
        case results([SymbolSearchResult])
        case empty
        case failed
    }

    /// The live query text. Bound to the search field; each change (re)arms the debounce.
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var state: SearchState = .idle
    /// Symbols already in favorites, so the results list can show them as added.
    private(set) var favoritedSymbols: Set<String>

    private let provider: SymbolSearchProvider
    private let store: FavoritesStore
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(provider: SymbolSearchProvider, store: FavoritesStore, debounce: Duration = .milliseconds(300)) {
        self.provider = provider
        self.store = store
        self.debounce = debounce
        self.favoritedSymbols = Set(store.symbols)
    }

    /// Whether `result` is already favorited, so the view can disable its add button.
    func isFavorited(_ result: SymbolSearchResult) -> Bool {
        favoritedSymbols.contains(Self.normalized(result.symbol))
    }

    /// Add a search result to favorites. Returns whether it was newly added (false if it
    /// was already there). Updates ``favoritedSymbols`` so the results list reflects it
    /// immediately; the sidebar updates via the store's own change handler.
    @discardableResult
    func add(_ result: SymbolSearchResult) -> Bool {
        let added = (try? store.add(result.symbol)) ?? false
        favoritedSymbols = Set(store.symbols)
        return added
    }

    /// Awaits the currently-scheduled search, if any. Test hook so specs can observe the
    /// debounced result deterministically instead of sleeping.
    func awaitPendingSearch() async {
        await searchTask?.value
    }

    private func scheduleSearch() {
        // Cancel any in-flight debounce/search so only the latest query survives.
        searchTask?.cancel()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            state = .idle
            searchTask = nil
            return
        }
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(for: trimmedQuery)
        }
    }

    private func runSearch(for query: String) async {
        state = .searching
        favoritedSymbols = Set(store.symbols)
        do {
            let results = try await provider.search(matching: query)
            // Drop a stale response if the query changed while we were awaiting.
            guard isCurrent(query) else { return }
            state = results.isEmpty ? .empty : .results(results)
        } catch {
            guard isCurrent(query) else { return }
            state = .failed
        }
    }

    private func isCurrent(_ query: String) -> Bool {
        query == self.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
