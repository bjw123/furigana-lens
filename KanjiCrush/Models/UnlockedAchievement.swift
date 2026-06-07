import Foundation
import SwiftData

/// Persistent marker that the user has earned a given achievement. Achievement
/// definitions live in `AchievementCatalog` (code, not data) — this table just
/// records which keys have been unlocked and when.
@Model
final class UnlockedAchievement {
    @Attribute(.unique) var key: String
    var unlockedAt: Date

    init(key: String, unlockedAt: Date = Date()) {
        self.key = key
        self.unlockedAt = unlockedAt
    }
}
