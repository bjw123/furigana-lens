import Foundation

enum ReviewGrade: Int, CaseIterable {
    case again = 0
    case hard = 2
    case good = 3
    case easy = 5

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// SuperMemo SM-2 scheduler (Anki-compatible quality scale 0–5).
final class SRSService {
    static let shared = SRSService()

    func applyReview(to card: Flashcard, grade: ReviewGrade, now: Date = Date()) {
        let q = grade.rawValue
        var ef = card.easeFactor
        var reps = card.repetitions
        var interval = card.interval

        if q < 3 {
            reps = 0
            interval = 1
        } else {
            if reps == 0 {
                interval = 1
            } else if reps == 1 {
                interval = 6
            } else {
                interval = ceil(interval * ef)
            }
            reps += 1
        }
        // SM-2 updates ease for every review, including failures — without
        // this, repeated lapses never reduce the ease factor and the card
        // keeps the same difficulty forever.
        ef = max(1.3, ef + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)))

        card.easeFactor = ef
        card.repetitions = reps
        card.interval = interval
        card.dueDate = Calendar.current.date(byAdding: .day, value: Int(interval), to: now) ?? now
        card.lastReviewed = now
    }

    func isDue(_ card: Flashcard, now: Date = Date()) -> Bool {
        card.dueDate <= now
    }

    func dueCards(from cards: [Flashcard], now: Date = Date()) -> [Flashcard] {
        cards
            .filter { card in
                if card.deck?.isExcludedFromReviews == true { return false }
                if card.deck?.isArchived == true { return false }
                return isDue(card, now: now)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }
}
