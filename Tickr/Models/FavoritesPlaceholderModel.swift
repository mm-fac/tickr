import Foundation

/// A single favorited symbol placeholder.
///
/// This is a temporary stand-in used only to shape the sidebar layout. The real
/// favorites model lives in TickrCore and lands in a later issue.
struct FavoritePlaceholder: Identifiable, Hashable {
    let id: UUID
    let symbol: String
}

/// Temporary favorites model backing the sidebar.
///
/// Starts empty so the sidebar renders its empty state. Persistence and the
/// TickrCore-backed favorites store arrive in later issues; nothing here does
/// any networking or storage.
@Observable
final class FavoritesPlaceholderModel {
    var favorites: [FavoritePlaceholder] = []
}
