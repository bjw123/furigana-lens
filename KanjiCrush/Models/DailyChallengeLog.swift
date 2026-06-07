import Foundation
import SwiftData

/// One row per day the user attempted (and finished) the daily challenge.
/// `day` is stored as a YYYY-MM-DD string in the user's local timezone so
/// "did I do today's challenge" stays an exact-match lookup.
@Model
final class DailyChallengeLog {
    @Attribute(.unique) var day: String
    var correctCount: Int
    var totalCount: Int
    var completedAt: Date

    init(day: String, correctCount: Int, totalCount: Int) {
        self.day = day
        self.correctCount = correctCount
        self.totalCount = totalCount
        self.completedAt = Date()
    }

    static func todayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: now)
    }
}
