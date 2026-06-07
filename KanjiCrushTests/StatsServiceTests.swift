import XCTest
import SwiftData
@testable import KanjiCrush

/// Unit tests for `StatsService` — the pure-function stats layer that powers
/// the Home / Stats / KanjiDetail views.
///
/// All fixtures live in an in-memory `ModelContainer` so we exercise the same
/// `@Model` machinery the app uses at runtime, without touching disk.
/// A deterministic `now` is threaded through every call so streak / window
/// assertions don't depend on wall-clock time.
final class StatsServiceTests: XCTestCase {

    // MARK: - Fixture wiring

    private var container: ModelContainer!
    private var context: ModelContext!

    /// Frozen "now" used for every call into StatsService. Picked far enough
    /// from any DST boundary that day-bucketing is unambiguous.
    private let now: Date = {
        var c = DateComponents()
        c.year = 2025
        c.month = 6
        c.day = 15
        c.hour = 12
        c.minute = 0
        return Calendar.current.date(from: c)!
    }()

    private var cal: Calendar { Calendar.current }

    /// Cards keyed by their kanji surface so individual tests can pull the
    /// one they care about without re-ordering brittleness.
    private var cards: [String: Flashcard] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema = Schema([Flashcard.self, Deck.self, ReviewLog.self, KnownWord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        cards = [:]
    }

    override func tearDown() {
        cards = [:]
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Build + insert a flashcard. Reading is the surface (hiragana) reading
    /// as it would appear on the card front — `readingForKanji` uses this to
    /// infer which on/kun variant the user is drilling.
    @discardableResult
    private func makeCard(expression: String, reading: String) -> Flashcard {
        let card = Flashcard(expression: expression, reading: reading)
        context.insert(card)
        cards[expression] = card
        return card
    }

    /// Build + insert a review log at `dayOffset` days from `now` (negative =
    /// past). `quality` follows the SM-2 grading: 0–2 == Again/Hard (failure),
    /// 3–5 == Good/Easy (success).
    @discardableResult
    private func makeLog(for card: Flashcard, quality: Int, dayOffset: Int, hour: Int = 9) -> ReviewLog {
        let log = ReviewLog(flashcardId: card.id, quality: quality)
        let base = cal.date(byAdding: .day, value: dayOffset, to: now)!
        log.reviewedAt = cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        context.insert(log)
        return log
    }

    private func allCards() -> [Flashcard] { Array(cards.values) }

    private func allLogs() throws -> [ReviewLog] {
        try context.fetch(FetchDescriptor<ReviewLog>())
    }

    // MARK: - successRate

    func test_successRate_returnsSuccessFractionOverWindow() throws {
        let card = makeCard(expression: "見る", reading: "みる")
        // 10 reviews — 3 fails (quality 1) + 7 passes (quality 4) → 0.7 success rate.
        for i in 0..<3 { makeLog(for: card, quality: 1, dayOffset: -i) }
        for i in 0..<7 { makeLog(for: card, quality: 4, dayOffset: -(i + 3)) }

        let rate = try XCTUnwrap(StatsService.successRate(logs: allLogs(), now: now))
        XCTAssertEqual(rate, 0.7, accuracy: 0.0001)
    }

    func test_successRate_isNilWhenNoLogsInWindow() throws {
        let card = makeCard(expression: "見る", reading: "みる")
        // 60 days back — outside the default 30-day window.
        makeLog(for: card, quality: 4, dayOffset: -60)
        XCTAssertNil(StatsService.successRate(logs: try allLogs(), now: now))
    }

    func test_successRate_treatsQuality3AsSuccess() throws {
        // Quality == 3 is "Good" in SM-2 — must count toward the success bucket
        // since the algorithm advances the card on grade ≥ 3.
        let card = makeCard(expression: "見る", reading: "みる")
        makeLog(for: card, quality: 3, dayOffset: -1)
        makeLog(for: card, quality: 1, dayOffset: -2)

        let rate = try XCTUnwrap(StatsService.successRate(logs: allLogs(), now: now))
        XCTAssertEqual(rate, 0.5, accuracy: 0.0001)
    }

    // MARK: - currentStreak

    func test_currentStreak_countsConsecutiveDaysWithReviews() throws {
        let card = makeCard(expression: "見る", reading: "みる")
        // Reviews today, yesterday, day before → streak = 3.
        for offset in 0...2 { makeLog(for: card, quality: 4, dayOffset: -offset) }

        XCTAssertEqual(StatsService.currentStreak(logs: try allLogs(), now: now), 3)
    }

    func test_currentStreak_resetsAtGap() throws {
        let card = makeCard(expression: "見る", reading: "みる")
        // Yesterday + day before (no review today is OK), then GAP at -3, then -4.
        // Streak should walk back from yesterday → 2 then stop at the gap.
        makeLog(for: card, quality: 4, dayOffset: -1)
        makeLog(for: card, quality: 4, dayOffset: -2)
        makeLog(for: card, quality: 4, dayOffset: -4) // before the gap at -3

        XCTAssertEqual(StatsService.currentStreak(logs: try allLogs(), now: now), 2)
    }

    func test_currentStreak_isZeroWithNoLogs() {
        XCTAssertEqual(StatsService.currentStreak(logs: [], now: now), 0)
    }

    // MARK: - strugglingKanji bucketing

    /// Builds the canonical 3-card / mixed-grade fixture used by the
    /// struggling-kanji tests. `見` accumulates 2 fails out of 3 reviews
    /// across two cards (見る + 見える); `食` gets 4 passes and zero fails;
    /// `行` gets 1 fail to act as a tie-breaker / second-place check.
    private func seedStrugglingFixture() {
        let miru   = makeCard(expression: "見る", reading: "みる")    // 見
        let mieru  = makeCard(expression: "見える", reading: "みえる")  // 見
        let taberu = makeCard(expression: "食べる", reading: "たべる")  // 食
        let iku    = makeCard(expression: "行く", reading: "いく")    // 行

        // 見る: 2 fails, 1 pass — 見 racks up 2 again-counts.
        makeLog(for: miru, quality: 1, dayOffset: -1)
        makeLog(for: miru, quality: 0, dayOffset: -2)
        makeLog(for: miru, quality: 4, dayOffset: -3)

        // 見える: 2 passes — keeps 見える reading clean.
        makeLog(for: mieru, quality: 5, dayOffset: -1)
        makeLog(for: mieru, quality: 4, dayOffset: -2)

        // 食べる: 4 passes — should never appear in struggling output.
        for offset in 1...4 { makeLog(for: taberu, quality: 4, dayOffset: -offset) }

        // 行く: 1 fail — second-place struggling kanji.
        makeLog(for: iku, quality: 1, dayOffset: -1)
    }

    func test_strugglingKanji_bucketsFailsByKanjiAndExcludesCleanOnes() throws {
        seedStrugglingFixture()

        let result = StatsService.strugglingKanji(logs: try allLogs(), cards: allCards(), now: now)
        let byKanji = Dictionary(uniqueKeysWithValues: result.map { (String($0.kanji), $0) })

        // 見: 2 fails (both on 見る) — must be present and count == 2.
        let mi = try XCTUnwrap(byKanji["見"], "見 should appear in struggling kanji")
        XCTAssertEqual(mi.againCount, 2)
        // Both 見る and 見える contain 見, so `cards` carries both;
        // only 見る triggered a fail so `strugglingCards` is just that one.
        XCTAssertEqual(Set(mi.cards.map(\.expression)), ["見る", "見える"])
        XCTAssertEqual(mi.strugglingCards.map(\.expression), ["見る"])

        // 行: 1 fail.
        let i = try XCTUnwrap(byKanji["行"])
        XCTAssertEqual(i.againCount, 1)

        // 食 has zero fails — must not surface.
        XCTAssertNil(byKanji["食"], "食 has no failed reviews and should not appear")

        // Sort order: highest againCount first.
        XCTAssertEqual(result.first?.kanji, Character("見"))
    }

    // MARK: - strugglingKanjiReadings — the (kanji × reading) decomposition.

    func test_strugglingKanjiReadings_separatesReadingsOfSameKanji() throws {
        // 見る (reading "みる") fails twice. 見える (reading "みえる") passes
        // twice. Both surface 見, but the reading-aware bucket must only flag
        // the "みる" variant — the "みえる" variant has zero fails and should
        // not appear at all.
        let miru  = makeCard(expression: "見る", reading: "みる")
        let mieru = makeCard(expression: "見える", reading: "みえる")

        makeLog(for: miru, quality: 1, dayOffset: -1)
        makeLog(for: miru, quality: 0, dayOffset: -2)
        makeLog(for: mieru, quality: 5, dayOffset: -1)
        makeLog(for: mieru, quality: 4, dayOffset: -2)

        let rows = StatsService.strugglingKanjiReadings(logs: try allLogs(), cards: allCards(), now: now)

        // Exactly one row, for 見 with the failing reading. The exact reading
        // string is whatever `readingForKanji` picks from Kanjidic2; we assert
        // (a) only one row, (b) it's for 見, (c) its struggling-card list is
        // just 見る — never 見える.
        XCTAssertEqual(rows.count, 1, "Only the failing reading should surface")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.kanji, Character("見"))
        XCTAssertEqual(row.againCount, 2)
        XCTAssertEqual(row.strugglingCards.map(\.expression), ["見る"])
        XCTAssertFalse(
            row.strugglingCards.contains { $0.expression == "見える" },
            "見える never failed — it must not appear in the struggling list for the failing reading"
        )

        // The reading inferred for 見 inside "みる" should not match the
        // reading inferred for 見 inside "みえる" — otherwise the
        // decomposition would have collapsed both back into one row.
        let miruReading  = StatsService.readingForKanji("見", inCardReading: "みる")
        let mieruReading = StatsService.readingForKanji("見", inCardReading: "みえる")
        XCTAssertNotEqual(miruReading, mieruReading,
                          "readingForKanji must distinguish みる from みえる; got \(miruReading ?? "nil") vs \(mieruReading ?? "nil")")
        XCTAssertEqual(row.reading, miruReading, "Failing row should carry the reading inferred from the failing card")
    }

    // MARK: - kanjiOverview

    func test_kanjiOverview_returnsFullRollupForKnownKanji() throws {
        seedStrugglingFixture()
        let overview = StatsService.kanjiOverview("見", logs: try allLogs(), cards: allCards())

        XCTAssertEqual(overview.kanji, Character("見"))
        XCTAssertEqual(overview.againCount, 2)
        XCTAssertEqual(Set(overview.cards.map(\.expression)), ["見る", "見える"])
        XCTAssertEqual(overview.strugglingCards.map(\.expression), ["見る"])
        XCTAssertEqual(overview.id, "見")
    }

    func test_kanjiOverview_emptyForUnknownKanji() throws {
        seedStrugglingFixture()
        // 鯖 doesn't appear in any card.
        let overview = StatsService.kanjiOverview("鯖", logs: try allLogs(), cards: allCards())

        XCTAssertEqual(overview.kanji, Character("鯖"))
        XCTAssertEqual(overview.againCount, 0)
        XCTAssertTrue(overview.cards.isEmpty)
        XCTAssertTrue(overview.strugglingCards.isEmpty)
    }

    // MARK: - forecast

    func test_forecast_bucketsDueCardsByDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Helper to build cards with a controlled dueDate; we bypass the
        // makeCard helper so the cards don't pollute the shared fixture map.
        func dueCard(_ name: String, dayOffset: Int) -> Flashcard {
            let card = Flashcard(expression: name, reading: name)
            card.dueDate = cal.date(byAdding: .day, value: dayOffset, to: today)!
            return card
        }

        let cards = [
            dueCard("overdue1", dayOffset: -3),
            dueCard("overdue2", dayOffset: -1),
            dueCard("today",    dayOffset:  0),
            dueCard("tomorrow", dayOffset:  1),
            dueCard("d2",       dayOffset:  2),
            dueCard("d2_b",     dayOffset:  2),
            dueCard("far_future", dayOffset: 30),
        ]

        let days = StatsService.forecast(days: 7, from: cards, now: now)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days[0].isToday)
        // Overdue (2) + today (1) all collapse into today's bucket.
        XCTAssertEqual(days[0].count, 3, "today's bucket should include overdue cards clamped forward")
        XCTAssertEqual(days[1].count, 1, "tomorrow has one card")
        XCTAssertEqual(days[2].count, 2, "+2 days has two cards")
        // Day 3..6 should be empty; far_future is outside the 7-day window.
        for i in 3..<7 { XCTAssertEqual(days[i].count, 0, "day +\(i) should be empty") }
    }
}
