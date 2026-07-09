import SwiftUI

/// Detail column of the app shell shown when no symbol is selected. Layout only.
struct DetailPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a symbol",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("Choose a favorite from the sidebar to see its details.")
        )
    }
}
