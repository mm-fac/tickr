import SwiftUI

/// Sidebar column of the app shell: the favorites list, or an empty state when
/// there are no favorites yet. Layout only — no logic beyond binding.
struct SidebarView: View {
    let model: FavoritesPlaceholderModel
    @Binding var selection: FavoritePlaceholder.ID?

    var body: some View {
        Group {
            if model.favorites.isEmpty {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "star",
                    description: Text("Add a symbol to start tracking it.")
                )
            } else {
                List(model.favorites, selection: $selection) { favorite in
                    Text(favorite.symbol)
                }
            }
        }
        .navigationTitle("Tickr")
    }
}
