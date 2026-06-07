import XCTest

final class KanjiCrushUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: - Smoke

    func test_launch_showsScanTab() {
        XCTAssertTrue(
            app.navigationBars["Scan"].waitForExistence(timeout: 5),
            "Scan nav title should be visible on launch"
        )
    }

    func test_tabBar_navigatesBetweenTabs() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Decks"].tap()
        XCTAssertTrue(app.navigationBars["Decks"].waitForExistence(timeout: 3))

        tabBar.buttons["Review"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 3))

        tabBar.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 3))
    }

    // MARK: - Manual lookup (no camera/photos required)

    func test_manualLookup_opensWordDetail() {
        // Open the "⋯" menu from the Scan toolbar.
        let menuButton = app.navigationBars["Scan"].buttons.element(boundBy: 0)
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()

        // Tap "Type word" in the menu.
        let typeWord = app.buttons["Type word"]
        XCTAssertTrue(typeWord.waitForExistence(timeout: 3))
        typeWord.tap()

        // Enter a kanji word.
        let textField = app.textFields["Japanese word"]
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        textField.tap()
        textField.typeText("猫")

        // Confirm.
        app.buttons["Look up"].tap()

        // The word detail sheet should surface the queried surface form.
        XCTAssertTrue(
            app.staticTexts["猫"].waitForExistence(timeout: 5),
            "Word detail sheet should appear with the looked-up word"
        )
    }
}
