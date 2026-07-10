import SwiftUI
import TickrCore

@main
struct TickrApp: App {
    @State private var sidebar: SidebarViewModel
    @State private var selection: SidebarViewModel.Row.ID?

    init() {
        let store = FavoritesStore(fileURL: Self.favoritesFileURL())
        // MockQuoteProvider stands in until Settings wires the real provider (later issue).
        _sidebar = State(initialValue: SidebarViewModel(store: store, provider: MockQuoteProvider()))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(model: sidebar, selection: $selection)
            } detail: {
                DetailPlaceholderView()
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
