import Foundation

/// Lightweight stats derived from `Flashcard` + `ReviewLog`. Pure functions — no state.
enum StatsService {

    struct ForecastDay: Identifiable {
        var id: Date { date }
        let date: Date
        let count: Int
        let isToday: Bool
    }

    struct StrugglingCard: Identifiable {
        var id: UUID { card.id }
        let card: Flashcard
        let againCount: Int
    }

    // MARK: - Forecast

    /// Number of cards due each of the next `days` days (including today).
    static func forecast(days: Int = 7, from cards: [Flashcard], now: Date = Date()) -> [ForecastDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let dayBuckets: [Date] = (0..<days).compactMap {
            cal.date(byAdding: .day, value: $0, to: today)
        }

        // Cards whose due date falls within the window — clamp overdue to "today".
        var counts: [Date: Int] = [:]
        for day in dayBuckets { counts[day] = 0 }

        for card in cards {
            let bucket = card.dueDate < today ? today : cal.startOfDay(for: card.dueDate)
            guard counts[bucket] != nil else { continue }
            counts[bucket, default: 0] += 1
        }

        return dayBuckets.map { day in
            ForecastDay(date: day, count: counts[day] ?? 0, isToday: day == today)
        }
    }

    // MARK: - Success rate

    /// Fraction of reviews (in the window) graded `good` or `easy` — i.e. quality >= 3.
    /// Returns `nil` when there are no reviews to score.
    static func successRate(logs: [ReviewLog], days: Int = 30, now: Date = Date()) -> Double? {
        let scoped = logs.filter { isWithin(days: days, of: $0.reviewedAt, now: now) }
        guard !scoped.isEmpty else { return nil }
        let successes = scoped.filter { $0.quality >= 3 }.count
        return Double(successes) / Double(scoped.count)
    }

    /// Total reviews logged (lifetime).
    static func totalReviews(logs: [ReviewLog]) -> Int {
        logs.count
    }

    // MARK: - Struggling cards

    /// Cards with the most `Again` grades (quality < 3) over the window. Returns at most `limit`.
    static func strugglingCards(
        logs: [ReviewLog],
        cards: [Flashcard],
        days: Int = 30,
        limit: Int = 5,
        now: Date = Date()
    ) -> [StrugglingCard] {
        let cardById = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let scoped = logs.filter {
            $0.quality < 3 && isWithin(days: days, of: $0.reviewedAt, now: now)
        }

        var counts: [UUID: Int] = [:]
        for log in scoped { counts[log.flashcardId, default: 0] += 1 }

        return counts
            .compactMap { id, count -> StrugglingCard? in
                guard let card = cardById[id] else { return nil }
                return StrugglingCard(card: card, againCount: count)
            }
            .sorted { lhs, rhs in
                if lhs.againCount != rhs.againCount { return lhs.againCount > rhs.againCount }
                return lhs.card.expression < rhs.card.expression
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Streak

    /// Consecutive days (counting back from today) with at least one review.
    static func currentStreak(logs: [ReviewLog], now: Date = Date()) -> Int {
        guard !logs.isEmpty else { return 0 }
        let cal = Calendar.current
        let reviewDays = Set(logs.map { cal.startOfDay(for: $0.reviewedAt) })

        var streak = 0
        var cursor = cal.startOfDay(for: now)
        // If today has no reviews, the streak may still be valid yesterday-and-back —
        // start counting from yesterday in that case so a single missed afternoon
        // doesn't reset the streak.
        if !reviewDays.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        while reviewDays.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Struggling kanji

    struct StrugglingKanji: Identifiable {
        let kanji: Character
        /// Number of `Again` grades on cards containing this kanji, in the window.
        let againCount: Int
        /// Every card in the user's collection that contains this kanji (regardless of grade).
        let cards: [Flashcard]
        /// Subset of `cards` that triggered an `Again` grade in the window — most relevant for cram.
        let strugglingCards: [Flashcard]
        var id: String { String(kanji) }
    }

    static func strugglingKanji(
        logs: [ReviewLog],
        cards: [Flashcard],
        days: Int = 30,
        limit: Int = 6,
        now: Date = Date()
    ) -> [StrugglingKanji] {
        let cardById = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let scoped = logs.filter {
            $0.quality < 3 && isWithin(days: days, of: $0.reviewedAt, now: now)
        }

        var againByKanji: [Character: Int] = [:]
        var strugglingCardsByKanji: [Character: Set<UUID>] = [:]
        for log in scoped {
            guard let card = cardById[log.flashcardId] else { continue }
            let kanjiInCard = Set(kanjiCharacters(in: card.expression))
            for ch in kanjiInCard {
                againByKanji[ch, default: 0] += 1
                strugglingCardsByKanji[ch, default: []].insert(card.id)
            }
        }

        var allCardsByKanji: [Character: [Flashcard]] = [:]
        for card in cards {
            let kanjiInCard = Set(kanjiCharacters(in: card.expression))
            for ch in kanjiInCard {
                allCardsByKanji[ch, default: []].append(card)
            }
        }

        return againByKanji
            .map { kanji, count in
                let allCards = allCardsByKanji[kanji] ?? []
                let strugglingIds = strugglingCardsByKanji[kanji] ?? []
                return StrugglingKanji(
                    kanji: kanji,
                    againCount: count,
                    cards: allCards,
                    strugglingCards: allCards.filter { strugglingIds.contains($0.id) }
                )
            }
            .sorted { lhs, rhs in
                if lhs.againCount != rhs.againCount { return lhs.againCount > rhs.againCount }
                return String(lhs.kanji) < String(rhs.kanji)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Build a `StrugglingKanji`-shaped view of an arbitrary kanji — used when navigating from
    /// a card detail to look at every word in the user's decks containing that character.
    static func kanjiOverview(
        _ kanji: Character,
        logs: [ReviewLog],
        cards: [Flashcard]
    ) -> StrugglingKanji {
        let cardsWithIt = cards.filter { kanjiCharacters(in: $0.expression).contains(kanji) }
        let cardIds = Set(cardsWithIt.map(\.id))
        let scoped = logs.filter { cardIds.contains($0.flashcardId) }
        let againCount = scoped.filter { $0.quality < 3 }.count
        let strugglingIds = Set(scoped.filter { $0.quality < 3 }.map(\.flashcardId))
        return StrugglingKanji(
            kanji: kanji,
            againCount: againCount,
            cards: cardsWithIt,
            strugglingCards: cardsWithIt.filter { strugglingIds.contains($0.id) }
        )
    }

    static func kanjiCharacters(in text: String) -> [Character] {
        text.filter { ch in
            ch.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||  // CJK Unified Ideographs
                (0x3400...0x4DBF).contains(scalar.value) ||  // Extension A
                (0xF900...0xFAFF).contains(scalar.value) ||  // Compatibility
                (0x20000...0x2A6DF).contains(scalar.value)   // Extension B
            }
        }
    }

    // MARK: - Per-deck stats

    struct DeckStats {
        let total: Int
        let new: Int        // never studied
        let learning: Int   // 1–2 successful reps
        let mature: Int     // 3+ reps and interval >= 21d
        let dueNow: Int
        let successRate: Double?  // last 30 days within this deck; nil if no reviews
        let reviewCount: Int       // lifetime reviews within this deck
        let againCount: Int        // lifetime "again" grades within this deck
    }

    static func deckStats(
        deck: Deck,
        logs: [ReviewLog],
        now: Date = Date(),
        windowDays: Int = 30,
        matureIntervalDays: Double = 21
    ) -> DeckStats {
        let cards = deck.cards
        let cardIds = Set(cards.map(\.id))
        let deckLogs = logs.filter { cardIds.contains($0.flashcardId) }

        var new = 0, learning = 0, mature = 0, dueNow = 0
        for card in cards {
            if card.repetitions == 0 { new += 1 }
            else if card.repetitions >= 3, card.interval >= matureIntervalDays { mature += 1 }
            else { learning += 1 }
            if card.dueDate <= now { dueNow += 1 }
        }

        let scoped = deckLogs.filter { isWithin(days: windowDays, of: $0.reviewedAt, now: now) }
        let successes = scoped.filter { $0.quality >= 3 }.count
        let rate = scoped.isEmpty ? nil : Double(successes) / Double(scoped.count)
        let again = deckLogs.filter { $0.quality < 3 }.count

        return DeckStats(
            total: cards.count,
            new: new,
            learning: learning,
            mature: mature,
            dueNow: dueNow,
            successRate: rate,
            reviewCount: deckLogs.count,
            againCount: again
        )
    }

    // MARK: - Helpers

    private static func isWithin(days: Int, of date: Date, now: Date) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return true
        }
        return date >= cutoff
    }
}
