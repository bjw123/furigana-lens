import XCTest

/// Captures one screenshot per primary surface for the README. Writes them
/// to `/tmp/kc_readme/` as numbered PNGs. Not part of the regular test run
/// — invoke with `-only-testing:KanjiCrushUITests/ReadmeScreenshotsTests`.
final class ReadmeScreenshotsTests: XCTestCase {
    private var app: XCUIApplication!
    private var outputDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-seedMockData", "reset"
        ]
        app.launch()
        outputDir = URL(fileURLWithPath: "/tmp/kc_readme", isDirectory: true)
        try? FileManager.default.removeItem(at: outputDir)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    func test_capture() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        snap("01_scan_idle")

        tabBar.buttons["Decks"].tap()
        sleep(1)
        snap("02_decks_list")

        // Drill into the first deck so we can grab the deck-detail screen.
        if let firstDeck = app.scrollViews
            .descendants(matching: .button)
            .allElementsBoundByIndex
            .first(where: { $0.isHittable && $0.label.count > 0 }) {
            firstDeck.tap()
            sleep(1)
            snap("03_deck_detail")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        tabBar.buttons["Review"].tap()
        sleep(1)
        snap("04_review_home")
        app.swipeUp()
        sleep(1)
        snap("05_review_stats")
        app.swipeUp()
        sleep(1)
        snap("06_struggling_kanji")

        // Drill into a struggling-kanji tile if available.
        if let kanjiTile = app.buttons.allElementsBoundByIndex.first(where: { btn in
            btn.isHittable
                && btn.label.count >= 1
                && btn.label.count <= 12
                && btn.label.contains(where: { ch in
                    let v = ch.unicodeScalars.first?.value ?? 0
                    return v >= 0x4E00 && v <= 0x9FFF
                })
        }) {
            kanjiTile.tap()
            sleep(2)
            snap("07_kanji_detail")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        tabBar.buttons["Settings"].tap()
        sleep(1)
        snap("08_settings_top")
        app.swipeUp()
        sleep(1)
        snap("09_settings_achievements")

        // --- Flashcards in action: cram the Trails deck to capture word
        // card front + back and a sentence card front. Trails has a long
        // sentence ("カフェバーの稼ぎ時は夜だからな。") seeded as a
        // sentence-type card.
        tabBar.buttons["Decks"].tap()
        sleep(1)
        let trails = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Trails'")).firstMatch
        if trails.waitForExistence(timeout: 3) {
            trails.tap()
            sleep(1)
            // Tap the "Cram study" row to launch a full cram session.
            let cram = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cram study'")).firstMatch
            if cram.waitForExistence(timeout: 3) {
                cram.tap()
                sleep(2)

                // Word card front: take a snapshot of whatever card came up
                // first (cram shuffles, so the deck-level guarantee is enough).
                snap("09_card_front")

                // Tap "Show answer" to reveal the back.
                let showAnswer = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Show answer'")).firstMatch
                if showAnswer.waitForExistence(timeout: 3) {
                    showAnswer.tap()
                    sleep(1)
                    snap("10_card_back")
                }

                // Advance through cards to find a sentence-type one (the
                // chip near the top reads "Sentence"). Up to 10 attempts.
                var foundSentence = false
                for _ in 0..<10 {
                    if app.staticTexts["Sentence"].exists {
                        foundSentence = true
                        break
                    }
                    // Tap "Good" to advance the SRS queue.
                    let good = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Good'")).firstMatch
                    if good.waitForExistence(timeout: 2) {
                        good.tap()
                        sleep(1)
                        let nextShowAnswer = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Show answer'")).firstMatch
                        if nextShowAnswer.waitForExistence(timeout: 2) {
                            nextShowAnswer.tap()
                            sleep(1)
                        }
                    } else {
                        break
                    }
                }
                if foundSentence {
                    snap("11_sentence_card")

                    // From the sentence card back, the "Read aloud" capsule
                    // is reachable. Tap it to capture the speech-check sheet.
                    let readAloud = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Read aloud'")).firstMatch
                    if readAloud.waitForExistence(timeout: 3) {
                        readAloud.tap()
                        sleep(2)
                        snap("12_read_aloud")
                    }
                }
            }
        }
    }

    private func snap(_ name: String) {
        let img = XCUIScreen.main.screenshot()
        try? img.pngRepresentation.write(to: outputDir.appendingPathComponent("\(name).png"))
    }
}
