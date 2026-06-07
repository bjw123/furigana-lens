import XCTest
@testable import KanjiCrush

/// Unit tests for the SM-2 scheduler in `SRSService`.
///
/// These exercise the full grade matrix (Again / Hard / Good / Easy) across new
/// cards, mid-stream cards (rep == 1 → 6 day step), and mature cards. The
/// scheduler accepts an explicit `now` so tests can pin scheduling against a
/// fixed reference date instead of `Date()` — see `referenceDate` below.
final class SRSServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Fixed reference date used as `now` for every test so absolute due-date
    /// assertions are deterministic. Value is arbitrary; UTC noon avoids any
    /// DST-edge surprises when adding day intervals.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 1
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Build a fresh `Flashcard` in its initial (never-reviewed) state.
    private func newCard() -> Flashcard {
        Flashcard(expression: "猫", reading: "ねこ", meaning: "cat")
    }

    /// Build a card already partway through its review history.
    private func card(
        repetitions: Int,
        interval: Double,
        easeFactor: Double = 2.5
    ) -> Flashcard {
        let c = newCard()
        c.repetitions = repetitions
        c.interval = interval
        c.easeFactor = easeFactor
        return c
    }

    /// Expected due date after adding `days` whole days to `referenceDate`,
    /// using the same calendar arithmetic the service uses.
    private func expectedDueDate(daysAfterNow days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: referenceDate)!
    }

    // MARK: - New-card scheduling

    func testNewCardGood() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        XCTAssertEqual(c.repetitions, 1, "Good on a fresh card should advance reps to 1")
        XCTAssertEqual(c.interval, 1, "First Good interval is 1 day")
        // q=3 → ef change = 0.1 - 2*(0.08 + 2*0.02) = -0.14
        XCTAssertEqual(c.easeFactor, 2.36, accuracy: 1e-9, "Good (q=3) drops ease by 0.14")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 1))
        XCTAssertEqual(c.lastReviewed, referenceDate)
    }

    func testNewCardEasy() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .easy, now: referenceDate)

        XCTAssertEqual(c.repetitions, 1)
        XCTAssertEqual(c.interval, 1, "First-rep interval is 1 day regardless of grade (>= 3)")
        // q=5 → ef change = +0.10
        XCTAssertEqual(c.easeFactor, 2.60, accuracy: 1e-9, "Easy (q=5) bumps ease by 0.10")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 1))
    }

    func testNewCardAgainResetsAndDecrementsEase() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertEqual(c.repetitions, 0, "Again resets repetitions")
        XCTAssertEqual(c.interval, 1, "Failure schedules a short relearn step (1 day)")
        // q=0 → ef change = 0.1 - 5*(0.08 + 5*0.02) = -0.80
        XCTAssertEqual(c.easeFactor, 1.70, accuracy: 1e-9, "Again (q=0) drops ease by 0.80")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 1))
    }

    func testNewCardHardDecrementsEase() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .hard, now: referenceDate)

        // Hard (q=2) is treated as a failure by this implementation —
        // reps reset, interval drops to the relearn step — but ease must
        // still take the SM-2 penalty so repeated Hards eventually shorten
        // future intervals.
        XCTAssertEqual(c.repetitions, 0)
        XCTAssertEqual(c.interval, 1)
        // q=2 → ef change = 0.1 - 3*(0.08 + 3*0.02) = -0.32
        XCTAssertEqual(c.easeFactor, 2.18, accuracy: 1e-9, "Hard (q=2) drops ease by 0.32")
    }

    // MARK: - Multi-step progression

    func testSecondReviewGoodGivesSixDayStep() {
        // After the first successful review the card has reps=1, interval=1.
        let c = card(repetitions: 1, interval: 1)
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        XCTAssertEqual(c.repetitions, 2)
        XCTAssertEqual(c.interval, 6, "Second Good jumps to the 6-day step")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 6))
    }

    func testThirdReviewGoodMultipliesByEase() {
        // reps=2, interval=6 — the situation after the 6-day step.
        let c = card(repetitions: 2, interval: 6, easeFactor: 2.5)
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        XCTAssertEqual(c.repetitions, 3)
        // ceil(6 * 2.5) = 15
        XCTAssertEqual(c.interval, 15, "Third Good = ceil(interval * easeFactor)")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 15))
        // ef drops by 0.14 for q=3
        XCTAssertEqual(c.easeFactor, 2.36, accuracy: 1e-9)
    }

    func testMatureCardAgainResetsAndDropsEase() {
        // A well-learned card: many successful reviews, 30-day interval.
        let c = card(repetitions: 5, interval: 30, easeFactor: 2.5)
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertEqual(c.repetitions, 0, "Lapse on a mature card still resets reps")
        XCTAssertEqual(c.interval, 1, "Lapse schedules the 1-day relearn step")
        XCTAssertEqual(c.easeFactor, 1.70, accuracy: 1e-9, "Lapse drops ease by 0.80 (q=0)")
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 1))
    }

    // MARK: - Boundary conditions

    func testEaseFloorIsRespectedOnFailure() {
        // Card already pinned at the SM-2 ease floor. Another Again must not
        // push it below 1.3 — a bug here would let cards spiral into
        // arbitrarily small ease and effectively never graduate.
        let c = card(repetitions: 3, interval: 10, easeFactor: 1.3)
        SRSService.shared.applyReview(to: c, grade: .again, now: referenceDate)

        XCTAssertEqual(c.easeFactor, 1.3, accuracy: 1e-9, "Ease must clamp at the 1.3 floor")
    }

    func testEaseFloorIsRespectedOnHard() {
        // Hard also decrements ease (-0.32). At the floor it must stay clamped.
        let c = card(repetitions: 3, interval: 10, easeFactor: 1.3)
        SRSService.shared.applyReview(to: c, grade: .hard, now: referenceDate)

        XCTAssertEqual(c.easeFactor, 1.3, accuracy: 1e-9)
    }

    func testDueDateAlwaysAdvancesByIntervalDays() {
        // Spot-check that dueDate == now + interval days for an arbitrary
        // mid-stream Good review, independent of the specific interval math.
        let c = card(repetitions: 4, interval: 20, easeFactor: 2.0)
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)

        // ceil(20 * 2.0) = 40
        XCTAssertEqual(c.interval, 40)
        XCTAssertEqual(c.dueDate, expectedDueDate(daysAfterNow: 40))
    }

    func testLastReviewedRecordsTheProvidedNow() {
        let c = newCard()
        SRSService.shared.applyReview(to: c, grade: .good, now: referenceDate)
        XCTAssertEqual(c.lastReviewed, referenceDate, "lastReviewed must be the injected now, not Date()")
    }

    // MARK: - Due-card filtering

    func testIsDueComparesAgainstNow() {
        let c = newCard()
        c.dueDate = referenceDate.addingTimeInterval(-60) // one minute ago
        XCTAssertTrue(SRSService.shared.isDue(c, now: referenceDate))

        c.dueDate = referenceDate.addingTimeInterval(60) // one minute from now
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
}
