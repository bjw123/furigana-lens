import XCTest
import SwiftData
@testable import KanjiCrush

/// Truth-table coverage for `Knownness.isKnown`. Three axes — user JLPT level,
/// the word's bundled JLPT level (via `DictionaryService`), and the optional
/// `KnownWord` override row. Override always wins; otherwise a word is known
/// iff its level is numerically >= the user's level (N5=5, N1=1).
final class KnownnessTests: XCTestCase {

    private enum Override {
        case absent
        case known
        case unknown

        var label: String {
            switch self {
            case .absent: return "absent"
            case .known: return "known"
            case .unknown: return "unknown"
            }
        }
    }

    private struct WordProbe {
        let expression: String
        let level: Int?
        let label: String
    }

    private let n5Probe = WordProbe(expression: "水", level: 5, label: "N5")
    private let n4Probe = WordProbe(expression: "意見", level: 4, label: "N4")
    private let n3Probe = WordProbe(expression: "参加", level: 3, label: "N3")
    private let n1Probe = WordProbe(expression: "原則", level: 1, label: "N1")
    private let nilProbe = WordProbe(expression: "あいうえお", level: nil, label: "nil")

    private let userLevels: [(Int, String)] = [(5, "N5"), (3, "N3"), (1, "N1")]

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Schema([
                Deck.self,
                Flashcard.self,
                ReviewLog.self,
                KnownWord.self,
                UnlockedAchievement.self,
                DailyChallengeLog.self
            ]),
            configurations: [config]
        )
    }

    @MainActor
    private func runCase(
        user: (level: Int, label: String),
        word: WordProbe,
        override: Override,
        context: ModelContext
    ) {
        let dictLevel = DictionaryService.shared.jlptLevel(forWord: word.expression)
        XCTAssertEqual(
            dictLevel,
            word.level,
            "Test fixture drift: \(word.expression) expected level \(String(describing: word.level)), got \(String(describing: dictLevel))"
        )

        var knownWords: [KnownWord] = []
        switch override {
        case .absent:
            break
        case .known:
            knownWords = [KnownWord(expression: word.expression, isKnown: true)]
        case .unknown:
            knownWords = [KnownWord(expression: word.expression, isKnown: false)]
        }

        let expected: Bool
        switch override {
        case .known:
            expected = true
        case .unknown:
            expected = false
        case .absent:
            if let wl = word.level {
                expected = wl >= user.level
            } else {
                expected = false
            }
        }

        let actual = Knownness.isKnown(
            expression: word.expression,
            knownWords: knownWords,
            userJLPTLevel: user.level
        )

        XCTAssertEqual(
            actual,
            expected,
            "user=\(user.label) word=\(word.label) override=\(override.label) should be \(expected ? "known" : "not-known")"
        )

        for row in knownWords { context.delete(row) }
    }

    @MainActor
    func testTruthTable_userLevelsByWordLevelsByOverride() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let wordProbes = [n5Probe, n3Probe, n1Probe]
        let overrides: [Override] = [.absent, .known, .unknown]

        for user in userLevels {
            for word in wordProbes {
                for override in overrides {
                    runCase(user: user, word: word, override: override, context: context)
                }
            }
        }
    }

    @MainActor
    func testTruthTable_n4WordAcrossUserLevels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        for user in userLevels {
            for override in [Override.absent, .known, .unknown] {
                runCase(user: user, word: n4Probe, override: override, context: context)
            }
        }
    }

    @MainActor
    func testTruthTable_nilWordLevelDefaultsUnknown() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        for user in userLevels {
            for override in [Override.absent, .known, .unknown] {
                runCase(user: user, word: nilProbe, override: override, context: context)
            }
        }
    }
}
