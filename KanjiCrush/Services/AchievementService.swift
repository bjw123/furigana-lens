import Foundation
import SwiftData

/// Static catalogue of achievements. Definitions live in code so adding a new
/// one is a single Swift edit; only the unlock state lives in SwiftData (in
/// `UnlockedAchievement`).
struct Achievement: Identifiable, Hashable {
    let key: String
    let title: String
    let summary: String
    let symbol: String         // SF Symbol
    /// Closure evaluated against current app state; returns true if the
    /// achievement is now earned.
    let isMet: (AchievementContext) -> Bool

    var id: String { key }

    static func == (lhs: Achievement, rhs: Achievement) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// Snapshot of the inputs every achievement predicate needs. Building this
/// once per evaluation keeps the predicates trivial.
struct AchievementContext {
    let cards: [Flashcard]
    let reviewLogs: [ReviewLog]
    let bestCombo: Int

    /// Streak length in consecutive days ending today (matches
    /// `StatsService.currentStreak`).
    let streak: Int

    /// Count of cards currently considered "mature" by SRS (reps ≥ 3,
    /// interval ≥ 21d).
    var matureCount: Int {
        cards.filter { $0.repetitions >= 3 && $0.interval >= 21 }.count
    }
}

enum AchievementCatalog {
    /// Order here is the order shown in the Settings list. Newer entries
    /// should go at the bottom unless logically grouped.
    static let all: [Achievement] = [
        Achievement(
            key: "first_card",
            title: "First card",
            summary: "Save your first flashcard.",
            symbol: "rectangle.fill.badge.plus",
            isMet: { !$0.cards.isEmpty }
        ),
        Achievement(
            key: "first_mature",
            title: "First crush",
            summary: "Graduate your first card to mature.",
            symbol: "sparkles",
            isMet: { $0.matureCount >= 1 }
        ),
        Achievement(
            key: "combo_5",
            title: "Combo ×5",
            summary: "Grade five reviews in a row good or better.",
            symbol: "flame.fill",
            isMet: { $0.bestCombo >= 5 }
        ),
        Achievement(
            key: "combo_10",
            title: "Combo ×10",
            summary: "Grade ten reviews in a row good or better.",
            symbol: "flame.fill",
            isMet: { $0.bestCombo >= 10 }
        ),
        Achievement(
            key: "streak_7",
            title: "Week of kanji",
            summary: "Review for seven days in a row.",
            symbol: "calendar.badge.clock",
            isMet: { $0.streak >= 7 }
        ),
        Achievement(
            key: "streak_30",
            title: "Sakura streak",
            summary: "Review for thirty days in a row.",
            symbol: "leaf.fill",
            isMet: { $0.streak >= 30 }
        ),
        Achievement(
            key: "mature_100",
            title: "Centurion",
            summary: "Mature 100 cards.",
            symbol: "100.circle.fill",
            isMet: { $0.matureCount >= 100 }
        ),
        Achievement(
            key: "reviews_1000",
            title: "Bookworm",
            summary: "Log 1,000 reviews.",
            symbol: "books.vertical.fill",
            isMet: { $0.reviewLogs.count >= 1_000 }
        )
    ]
}

enum AchievementService {
    /// Persisted high-water mark for combo length. Streak-of-the-session
    /// combo is volatile; we want the *best* combo ever for the
    /// `combo_5` / `combo_10` predicates.
    private static let bestComboKey = "achievementBestCombo"

    static var bestCombo: Int {
        get { UserDefaults.standard.integer(forKey: bestComboKey) }
        set { UserDefaults.standard.set(newValue, forKey: bestComboKey) }
    }

    /// Push the current run's combo length into the all-time best store so
    /// the predicates pick it up on the next evaluation.
    static func recordCombo(_ count: Int) {
        if count > bestCombo { bestCombo = count }
    }

    /// Walk the catalog, insert `UnlockedAchievement` rows for newly-met
    /// definitions, and return them so the UI can banner the first one.
    @MainActor
    static func evaluate(
        modelContext: ModelContext,
        cards: [Flashcard],
        reviewLogs: [ReviewLog],
        unlocked: [UnlockedAchievement],
        streak: Int
    ) -> [Achievement] {
        let context = AchievementContext(
            cards: cards,
            reviewLogs: reviewLogs,
            bestCombo: bestCombo,
            streak: streak
        )
        let knownKeys = Set(unlocked.map { $0.key })
        var newlyUnlocked: [Achievement] = []
        for achievement in AchievementCatalog.all
            where !knownKeys.contains(achievement.key) && achievement.isMet(context) {
            modelContext.insert(UnlockedAchievement(key: achievement.key))
            newlyUnlocked.append(achievement)
        }
        if !newlyUnlocked.isEmpty {
            try? modelContext.save()
        }
        return newlyUnlocked
    }
}
