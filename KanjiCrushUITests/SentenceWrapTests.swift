import XCTest

/// Regression coverage for the sentence-card front layout: long sentences
/// must wrap to the available width instead of overflowing horizontally past
/// the screen edge (the kind of bug where you only see the left half of the
/// sentence and the rest is clipped off the right edge of the device).
final class SentenceWrapTests: XCTestCase {
    private var app: XCUIApplication!

    /// The seeded sentence card in the "Trails Through Daybreak" deck that's
    /// long enough to overflow at `.title2`. If the front doesn't wrap, this
    /// `staticText` ends up wider than the screen and its bounding frame
    /// extends beyond `app.windows.firstMatch.frame`.
    private let targetSentence = "カフェバーの稼ぎ時は夜だからな。"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-seedMockData", "reset",
        ]
        app.launch()
    }

    func test_sentenceCardFront_wrapsWithinScreenWidth() throws {
        // 1) Navigate Decks tab → "Trails Through Daybreak".
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Decks"].tap()
        XCTAssertTrue(app.navigationBars["Decks"].waitForExistence(timeout: 5))

        let deckRow = app.staticTexts["Trails Through Daybreak"]
        XCTAssertTrue(deckRow.waitForExistence(timeout: 5), "Seeded deck should be present")
        deckRow.tap()

        // 2) Start Cram study.
        let cramButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Cram study'")).firstMatch
        XCTAssertTrue(cramButton.waitForExistence(timeout: 5), "Cram study action row should be tappable")
        cramButton.tap()

        // 3) Iterate through the cram queue until we land on the sentence
        //    card whose expression matches `targetSentence`. The cram queue
        //    is shuffled, so we may have to grade through several cards.
        //    Use the "Sentence" type pill + the static-text presence to
        //    detect the right card; grade "Good" on anything else.
        //
        //    The Trails deck has 7 seeded cards, so the target must show up
        //    inside 7 iterations. Loop with a small headroom anyway.
        let maxCardsToCycle = 10
        var found = false
        for iteration in 0..<maxCardsToCycle {
            // Wait for any card to render — the "Show answer" button is a
            // good signal that the front is ready. If the session has
            // completed, no front will exist; bail out of the loop in that
            // case so the assertion below fires with a useful message.
            let showAnswer = app.buttons["Show answer"]
            guard showAnswer.waitForExistence(timeout: 8) else {
                // Dump the current UI hierarchy so a failed run gives us
                // enough context to figure out what state we ended in.
                let debug = app.debugDescription
                XCTFail("Cram session ran out of cards on iteration \(iteration) without ever showing target sentence. UI tree:\n\(debug)")
                break
            }

            let sentencePillVisible = app.staticTexts["Sentence"].exists
            let targetVisible = app.staticTexts[targetSentence].exists

            if sentencePillVisible && targetVisible {
                found = true
                break
            }

            // Not the card we want — reveal the back and grade Good to advance.
            showAnswer.tap()
            let good = app.buttons["Good"]
            XCTAssertTrue(good.waitForExistence(timeout: 3), "Good grade button should appear after revealing answer")
            good.tap()
        }
        XCTAssertTrue(found, "Should reach the target sentence card within \(maxCardsToCycle) iterations")

        // 4) Assert the sentence text is on screen and its frame sits inside
        //    the window bounds — this is the actual wrapping regression check.
        let sentenceText = app.staticTexts[targetSentence]
        XCTAssertTrue(sentenceText.exists, "Sentence front text should exist")
        XCTAssertTrue(sentenceText.isHittable, "Sentence front text should be hittable (visible on screen)")

        let windowFrame = app.windows.firstMatch.frame
        let textFrame = sentenceText.frame
        XCTAssertGreaterThanOrEqual(textFrame.minX, windowFrame.minX - 0.5,
                                    "Sentence front should not extend past the left edge")
        XCTAssertLessThanOrEqual(textFrame.maxX, windowFrame.maxX + 0.5,
                                 "Sentence front should not extend past the right edge — this is the wrap bug")
        XCTAssertGreaterThan(textFrame.width, 0, "Sentence frame should have non-zero width")
        XCTAssertLessThanOrEqual(textFrame.width, windowFrame.width + 0.5,
                                 "Sentence text width should not exceed window width")

        // 5) Take a screenshot, attach it to the test result, and also drop
        //    a copy on disk for the agent to inspect.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "sentence-front-wrap"
        attachment.lifetime = .keepAlways
        add(attachment)

        let outPath = "/tmp/kc_wrap_test.png"
        do {
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: outPath))
        } catch {
            XCTFail("Could not write screenshot to \(outPath): \(error)")
        }
    }
}
