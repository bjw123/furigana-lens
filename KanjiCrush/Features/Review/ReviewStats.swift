import Foundation
import SwiftUI

@MainActor
final class ReviewStats: ObservableObject {
    @Published var forecast: [StatsService.ForecastDay] = []
    @Published var successRate: Double? = nil
    @Published var totalReviews: Int = 0
    @Published var streak: Int = 0
    @Published var struggling: [StatsService.StrugglingCard] = []
    @Published var strugglingKanji: [StatsService.StrugglingKanjiReading] = []

    func refresh(logs: [ReviewLog], cards: [Flashcard]) {
        forecast = StatsService.forecast(days: 7, from: cards)
        successRate = StatsService.successRate(logs: logs, days: 30)
        totalReviews = StatsService.totalReviews(logs: logs)
        streak = StatsService.currentStreak(logs: logs)
        struggling = StatsService.strugglingCards(logs: logs, cards: cards, days: 30, limit: 5)
        strugglingKanji = StatsService.strugglingKanjiReadings(logs: logs, cards: cards, days: 30, limit: 8)
    }
}
