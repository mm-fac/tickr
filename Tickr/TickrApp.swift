import SwiftUI

@main
struct TickrApp: App {
    @State private var favorites = FavoritesPlaceholderModel()
    @State private var selection: FavoritePlaceholder.ID?

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(model: favorites, selection: $selection)
            } detail: {
                DetailPlaceholderView()
            }
            .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 900, height: 600)
    }
}
