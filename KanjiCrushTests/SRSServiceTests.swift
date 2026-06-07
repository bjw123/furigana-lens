import XCTest
@testable import KanjiCrush

/// Unit tests for the FSRS-4.5 scheduler in `SRSService`.
///
/// FSRS state is `(stability, difficulty, lastReviewed)`. These tests exercise
/// the first-review path (state seeded from `w[0..3]` + `w[4..5]`), the
/// repeat-review growth path, the lapse path (`w[11..14]`), the difficulty
/// clamp, and the legacy-fields back-compat write. The scheduler accepts an
/// explicit `now` so absolute due-date assertions are deterministic against
/// `referenceDate`.
final class SRSServiceTests: XCTestCase {

    // MARK: - Helpers

    /// FSRS-4.5 generic weights, mirrored from `SRSService` so tests can compute
    /// the same expectations the production code does (without importing
    /// private state). If the production constant drifts, these will too — at
    /// which point the relevant test assertion fails loudly.
    private let w: [Double] = [
        0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234,
        1.616,  0.1544, 1.0824, 1.9813,  0.0953, 0.2975, 2.2042, 0.2407, 2.9466,
    ]
    private let desiredRetention: Double = 0.9
    private let decay: Double = -0.5
    private let factor: Double = 19.0 / 81.0

    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 1
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private func newCard() -> Flashcard {
        Flashcard(expression: "猫", reading: "ねこ", meaning: "cat")
    }

    private func expectedInterval(stability s: Double) -> Int {
        let t = (s / factor) * (pow(desiredRetention, 1.0 / decay) - 1)
        return max(1, Int(max(1.0, t).rounded()))
    }

    private func expectedDueDate(daysAfterNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: referenceDate)!
    }

    // MARK: - First review per grade

    func testFirstReviewAgainSetsInitialStabilityFromW0() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertEqual(c.stability, w[0], accuracy: 1e-9, "First Again → S = w[0]")
        XCTAssertGreaterThanOrEqual(c.difficulty, 1)
        XCTAssertLessThanOrEqual(c.difficulty, 10)
        XCTAssertEqual(c.lastReviewed, referenceDate)
    }

    func testFirstReviewHardSetsInitialStabilityFromW1() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .hard, now: referenceDate)

        XCTAssertEqual(c.stability, w[1], accuracy: 1e-9, "First Hard → S = w[1]")
        XCTAssertGreaterThanOrEqual(c.difficulty, 1)
        XCTAssertLessThanOrEqual(c.difficulty, 10)
    }

    func testFirstReviewGoodSetsInitialStabilityFromW2() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        XCTAssertEqual(c.stability, w[2], accuracy: 1e-9, "First Good → S = w[2]")
        // For grade=3: D = w[4] - exp(w[5]*2) + 1 ≈ 5.31
        let expectedD = w[4] - exp(w[5] * 2) + 1
        XCTAssertEqual(c.difficulty, min(10, max(1, expectedD)), accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(c.difficulty, 1)
        XCTAssertLessThanOrEqual(c.difficulty, 10)
    }

    func testFirstReviewEasySetsInitialStabilityFromW3() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .easy, now: referenceDate)

        XCTAssertEqual(c.stability, w[3], accuracy: 1e-9, "First Easy → S = w[3]")
        XCTAssertGreaterThanOrEqual(c.difficulty, 1)
        XCTAssertLessThanOrEqual(c.difficulty, 10)
    }

    // MARK: - Second review

    func testSecondGoodIncreasesStability() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)
        let s1 = c.stability

        // Review exactly when the card was due — retrievability ≈ desiredRetention.
        let due = c.dueDate
        SRSService.shared.applyReview(to: c, grade: .good, now: due)

        XCTAssertGreaterThan(c.stability, s1, "A successful repeat review must grow stability")
    }

    func testSecondEasyGrowsMoreThanSecondGood() {
        let cGood = newCard()
        let cEasy = newCard()
        SRSService.shared.applyReview(to: cGood, grade: .good, now: referenceDate)
        SRSService.shared.applyReview(to: cEasy, grade: .good, now: referenceDate)

        // Force identical state so the only difference is the 2nd-review grade.
        cEasy.stability = cGood.stability
        cEasy.difficulty = cGood.difficulty
        cEasy.lastReviewed = cGood.lastReviewed

        let due = cGood.dueDate
        SRSService.shared.applyReview(to: cGood, grade: .good, now: due)
        SRSService.shared.applyReview(to: cEasy, grade: .easy, now: due)

        XCTAssertGreaterThan(cEasy.stability, cGood.stability,
                             "Easy bonus (w[16]) should multiply success stability above Good")
    }

    // MARK: - Lapse path

    func testLapseOnMatureCardResetsStability() {
        let c = newCard()
        // Hand-build a mature state instead of cycling through reviews.
        c.stability = 30
        c.difficulty = 5
        c.lastReviewed = referenceDate.addingTimeInterval(-30 * 86_400)
        c.dueDate = referenceDate

        let prevStability = c.stability
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertLessThan(c.stability, prevStability, "Lapse must drop stability")
        XCTAssertGreaterThan(c.stability, 0, "Lapse stability is bounded below by 0.1")
        XCTAssertEqual(c.repetitions, 0, "Lapse resets the legacy repetitions field")
    }

    func testLapseRaisesDifficulty() {
        let c = newCard()
        c.stability = 30
        c.difficulty = 5
        c.lastReviewed = referenceDate.addingTimeInterval(-30 * 86_400)

        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertGreaterThan(c.difficulty, 5, "Again should push difficulty upward")
        XCTAssertLessThanOrEqual(c.difficulty, 10)
    }

    // MARK: - Difficulty clamp

    func testDifficultyClampsAtTen() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        // Beat the card with Again repeatedly. Difficulty should saturate at 10
        // and never overshoot.
        var now = c.dueDate
        for _ in 0..<30 {
            SRSService.shared.applyReview(to: c, grade: .again, now: now)
            now = c.dueDate
        }
        XCTAssertEqual(c.difficulty, 10, accuracy: 1e-9, "Difficulty must clamp at the 10 ceiling")
    }

    func testDifficultyClampsAtOne() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        var now = c.dueDate
        for _ in 0..<30 {
            SRSService.shared.applyReview(to: c, grade: .easy, now: now)
            now = c.dueDate
        }
        XCTAssertEqual(c.difficulty, 1, accuracy: 1e-9, "Difficulty must clamp at the 1 floor")
    }

    // MARK: - Interval / due date

    func testDueDateMatchesStabilityRoundedToDays() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        // S = w[2] = 3.1262, formula yields ≈ 3.1262 days → rounded to 3.
        let expected = expectedInterval(stability: w[2])
        XCTAssertEqual(c.interval, Double(expected), "Legacy interval reflects FSRS days")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: expected))
    }

    func testIntervalMinimumIsOneDay() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        // S = w[0] = 0.4072 → raw interval < 1, must clamp to 1.
        XCTAssertEqual(c.interval, 1)
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 1))
    }

    // MARK: - Due-card filtering (kept identical to SM-2 contract)

    func testIsDueComparesAgainstNow() {
        let c = newCard()
        c.dueDate = referenceDate.addingTimeInterval(-60)
        XCTAssertTrue(SRSService.shared.isDue(c, now: referenceDate))

        c.dueDate = referenceDate.addingTimeInterval(60)
        XCTAssertFalse(SRSService.shared.isDue(c, now: referenceDate))
    }

    func testDueCardsSkipsArchivedAndExcludedDecks() {
        let activeDeck = Deck(name: "Active")
        let archivedDeck = Deck(name: "Old", isArchived: true)
        let excludedDeck = Deck(name: "Paused", isExcludedFromReviews: true)

        let due = newCard()
        due.deck = activeDeck
        due.dueDate = referenceDate.addingTimeInterval(-1)

        let dueButArchived = newCard()
        dueButArchived.deck = archivedDeck
        dueButArchived.dueDate = referenceDate.addingTimeInterval(-1)

        let dueButExcluded = newCard()
        dueButExcluded.deck = excludedDeck
        dueButExcluded.dueDate = referenceDate.addingTimeInterval(-1)

        let result = SRSService.shared.dueCards(
            from: [due, dueButArchived, dueButExcluded],
            now: referenceDate
        )
        XCTAssertEqual(result.map(\.id), [due.id])
    }

    // MARK: - SM-2 → FSRS back-fill

    func testLegacySM2CardSkipsFirstReviewSeeding() {
        // A card with no FSRS state but real SM-2 history (interval > 0,
        // lastReviewed set) should be treated as a *repeat* review, seeded
        // from the legacy interval — not re-initialised from w[0..3].
        let c = newCard()
        c.interval = 10
        c.repetitions = 3
        c.lastReviewed = referenceDate.addingTimeInterval(-10 * 86_400)
        // stability/difficulty still 0 — pre-FSRS persisted state.

        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        // Repeat-review path bumps stability *above* the seeded 10, so we
        // assert > 10 (init path would yield 3.1262, which we explicitly
        // don't want for an existing mature card).
        XCTAssertGreaterThan(c.stability, 10, "Back-filled stability should grow, not collapse to w[2]")
    }
}
