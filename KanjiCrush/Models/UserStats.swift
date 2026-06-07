import Foundation
import SwiftData

/// Singleton-style SwiftData row holding cross-cutting user stats that aren't
/// naturally attached to a `Flashcard` or `ReviewLog`. Today this just holds
/// the all-time best combo length used by `AchievementService`; new "global"
/// stats should land here so they participate in the same backup/restore
/// lifecycle as the rest of the SwiftData store.
@Model
final class UserStats {
    var bestCombo: Int
    var updatedAt: Date

    init() {
        self.bestCombo = 0
        self.updatedAt = Date()
    }
}

extension UserStats {
    /// Fetch-or-create the singleton row. Callers pass in their model context
    /// so this stays usable from both `@MainActor` views and background
    /// `ModelContext` instances (e.g. seeding / migration).
    static func current(in context: ModelContext) -> UserStats {
        let descriptor = FetchDescriptor<UserStats>()
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let new = UserStats()
        context.insert(new)
        try? context.save()
        return new
    }
}
