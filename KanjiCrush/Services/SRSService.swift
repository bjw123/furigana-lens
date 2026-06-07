import Foundation
import os

/// FSRS-4.5 review grade. Note the rawValues differ from SM-2: FSRS uses
/// 1..4 where Again=1 (not 0). `ReviewLog.quality` stores the rawValue, so
/// legacy SM-2 quality values (0/2/3/5) coexisting in the DB is fine —
/// nothing in the scheduler reads logs back, and the stats service compares
/// `quality < 3` / `>= 3` which classifies both scales consistently.
enum ReviewGrade: Int, CaseIterable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// FSRS-4.5 default weights (the public, generic weights — not user-personalised).
/// Source: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
/// Indexing: w[0..3] → initial stability per first-review grade; w[4..5] →
/// initial difficulty; w[6..7] → difficulty update; w[8..10] → successful-review
/// stability growth; w[11..14] → lapse stability; w[15] → hard penalty; w[16] →
/// easy bonus.
private let fsrsWeights: [Double] = [
    0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234,
    1.616,  0.1544, 1.0824, 1.9813,  0.0953, 0.2975, 2.2042, 0.2407, 2.9466,
]

/// Target recall probability at the next review. 0.9 matches Anki's FSRS default
/// — higher means shorter intervals (study more, forget less); lower the opposite.
private let desiredRetention: Double = 0.9

/// Power-law retrievability constants from FSRS-4.5:
///     R(t, S) = (1 + FACTOR * t / S) ^ DECAY
/// Solving for t at a target R gives the next interval.
private let fsrsDecay: Double = -0.5
private let fsrsFactor: Double = 19.0 / 81.0

/// FSRS-4.5 scheduler. State per card is (`stability`, `difficulty`,
/// `lastReviewed`); the scheduler ignores the legacy SM-2 fields (kept on the
/// schema for migration safety).
final class SRSService {
    static let shared = SRSService()

    func applyReview(to card: Flashcard, grade: ReviewGrade, now: Date = Date()) {
        let g = grade.rawValue
        let isFirstReview = card.stability <= 0

        // Back-fill: cards reviewed under SM-2 have stability == 0 but a real
        // history. Treat them as "review" not "new" by seeding stability from
        // the legacy interval (rough but monotonic — better than re-learning
        // mature cards from scratch).
        let seededStability: Double = {
            if !isFirstReview { return card.stability }
            if card.lastReviewed != nil, card.interval > 0 { return card.interval }
            return 0
        }()
        let treatAsFirstReview = seededStability <= 0

        let newStability: Double
        let newDifficulty: Double

        if treatAsFirstReview {
            newStability = initialStability(grade: g)
            newDifficulty = initialDifficulty(grade: g)
            AppLog.srs.notice("fsrs init expr=\(card.expression, privacy: .private) g=\(g, privacy: .public) S=\(newStability, privacy: .public) D=\(newDifficulty, privacy: .public)")
        } else {
            let elapsedDays = elapsed(from: card.lastReviewed, to: now)
            let r = retrievability(elapsedDays: elapsedDays, stability: seededStability)
            let priorDifficulty = card.difficulty <= 0 ? initialDifficulty(grade: 3) : card.difficulty

            newDifficulty = nextDifficulty(prior: priorDifficulty, grade: g)
            if g == ReviewGrade.again.rawValue {
                newStability = lapseStability(
                    difficulty: priorDifficulty,
                    stability: seededStability,
                    retrievability: r
                )
                AppLog.srs.notice("fsrs lapse expr=\(card.expression, privacy: .private) prevS=\(seededStability, privacy: .public) newS=\(newStability, privacy: .public)")
            } else {
                newStability = successStability(
                    difficulty: priorDifficulty,
                    stability: seededStability,
                    retrievability: r,
                    grade: g
                )
            }
        }

        let intervalDays = max(1, Int((nextInterval(stability: newStability)).rounded()))

        card.stability = newStability
        card.difficulty = newDifficulty
        // Maintain legacy fields so existing views/services keep working.
        card.interval = Double(intervalDays)
        card.repetitions = treatAsFirstReview
            ? (g == ReviewGrade.again.rawValue ? 0 : 1)
            : (g == ReviewGrade.again.rawValue ? 0 : card.repetitions + 1)
        card.dueDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: now) ?? now
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

    // MARK: - FSRS-4.5 internals

    /// First-review stability is just w[g-1].
    private func initialStability(grade: Int) -> Double {
        let idx = max(0, min(3, grade - 1))
        return max(0.1, fsrsWeights[idx])
    }

    /// First-review difficulty: D₀ = w[4] - exp(w[5] * (g - 1)) + 1, clamped 1..10.
    private func initialDifficulty(grade: Int) -> Double {
        let raw = fsrsWeights[4] - exp(fsrsWeights[5] * Double(grade - 1)) + 1
        return clampDifficulty(raw)
    }

    /// Mean-reversion of difficulty toward `initialDifficulty(grade: 3)`,
    /// weighted by w[7]. Tougher grades push D up; easier grades push it down.
    private func nextDifficulty(prior: Double, grade: Int) -> Double {
        let deltaD = -fsrsWeights[6] * Double(grade - 3)
        let postReview = prior + deltaD
        let mean = fsrsWeights[7] * initialDifficulty(grade: 3) + (1 - fsrsWeights[7]) * postReview
        return clampDifficulty(mean)
    }

    /// Retrievability under the power-law decay model.
    private func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + fsrsFactor * elapsedDays / stability, fsrsDecay)
    }

    /// Stability growth after a non-lapse review.
    private func successStability(
        difficulty: Double,
        stability: Double,
        retrievability r: Double,
        grade: Int
    ) -> Double {
        let hardPenalty = grade == ReviewGrade.hard.rawValue ? fsrsWeights[15] : 1.0
        let easyBonus = grade == ReviewGrade.easy.rawValue ? fsrsWeights[16] : 1.0
        let factor = exp(fsrsWeights[8])
            * (11 - difficulty)
            * pow(stability, -fsrsWeights[9])
            * (exp(fsrsWeights[10] * (1 - r)) - 1)
            * hardPenalty
            * easyBonus
        let next = stability * (1 + factor)
        return max(0.1, next)
    }

    /// Stability after a lapse (grade == Again). Drops sharply but not to zero.
    private func lapseStability(difficulty: Double, stability: Double, retrievability r: Double) -> Double {
        let next = fsrsWeights[11]
            * pow(difficulty, -fsrsWeights[12])
            * (pow(stability + 1, fsrsWeights[13]) - 1)
            * exp(fsrsWeights[14] * (1 - r))
        return max(0.1, next)
    }

    /// Days until the card's predicted retrievability reaches `desiredRetention`.
    private func nextInterval(stability: Double) -> Double {
        // R = (1 + FACTOR * t / S) ^ DECAY   →   t = (S / FACTOR) * (R^(1/DECAY) - 1)
        let t = (stability / fsrsFactor) * (pow(desiredRetention, 1.0 / fsrsDecay) - 1)
        return max(1.0, t)
    }

    private func elapsed(from last: Date?, to now: Date) -> Double {
        guard let last else { return 0 }
        return max(0, now.timeIntervalSince(last) / 86_400)
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(10, max(1, value))
    }
}
