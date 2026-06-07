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

        // Speech-check sheet via Scan → manual lookup is fiddly, so we grab
        // it instead via the Decks search bar by opening a card edit and the
        // read-aloud action there. Falling back to just capturing what's on
        // screen if it's not reachable.
        tabBar.buttons["Scan"].tap()
        sleep(1)
        let scanMenu = app.navigationBars["Scan"].buttons.firstMatch
        if scanMenu.waitForExistence(timeout: 3) {
            scanMenu.tap()
            sleep(1)
            let typeWord = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Type word'")).firstMatch
            if typeWord.waitForExistence(timeout: 3) {
                typeWord.tap()
                sleep(1)
                snap("10_manual_lookup")
            }
        }
    }

    private func snap(_ name: String) {
        let img = XCUIScreen.main.screenshot()
        try? img.pngRepresentation.write(to: outputDir.appendingPathComponent("\(name).png"))
    }
}
