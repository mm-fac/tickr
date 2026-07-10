import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var selection: SidebarViewModel.Row.ID?

    // MockQuoteProvider / PreviewCandleProvider stand in until Settings wires the real
    // providers (later issue).
    private let quoteProvider: QuoteProvider = MockQuoteProvider()
    private let candleProvider: CandleProvider = PreviewCandleProvider()

    init() {
        let store = FavoritesStore(fileURL: Self.favoritesFileURL())
        _sidebar = State(initialValue: SidebarViewModel(store: store, provider: MockQuoteProvider()))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(model: sidebar, selection: $selection)
            } detail: {
                if let symbol = selection {
                    DetailView(model: DetailViewModel(
                        symbol: symbol,
                        quoteProvider: quoteProvider,
                        candleProvider: candleProvider
                    ))
                    // Rebuild the detail (and its view model) when the selection changes.
                    .id(symbol)
                } else {
                    DetailPlaceholderView()
                }
            }
            .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 600)
    }

    private static func favoritesFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tickr", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }
}
