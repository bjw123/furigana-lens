import XCTest
@testable import KanjiCrush

/// Verifies the per-kanji JLPT fallback in `DictionaryService.jlptLevel(forWord:)`.
///
/// Background: the bundled `word_jlpt` table only carries dictionary-form
/// entries, so surface forms like 見て (conjugated) or 見かけ (compound) used to
/// return nil even though every kanji in them is an N5 character. The fallback
/// extracts kanji from the word, looks each one up in the `kanji` table, and
/// returns the MINIMUM (hardest) JLPT level when every kanji has a rating.
final class JLPTFallbackTests: XCTestCase {

    func testConjugatedFormFallsBackToKanjiLevel() {
        // 見て conjugates 見る; only 見 carries the JLPT load and it's N5.
        let level = DictionaryService.shared.jlptLevel(forWord: "見て")
        XCTAssertNotNil(level, "Expected kanji-fallback to classify 見て")
        XCTAssertEqual(level, 5, "見 is an N5 kanji, so 見て should resolve to N5 (level 5)")
    }

    func testSingleKanjiResolves() {
        let level = DictionaryService.shared.jlptLevel(forWord: "見")
        XCTAssertEqual(level, 5, "見 alone is an N5 kanji")
    }

    func testCompoundFallsBackToHardestKanji() {
        // 見かけ isn't in the per-word JLPT list; the only kanji is 見 (N5),
        // so the fallback should resolve to level 5.
        let level = DictionaryService.shared.jlptLevel(forWord: "見かけ")
        XCTAssertEqual(level, 5, "見かけ contains only N5 kanji (見), expected N5 (level 5)")
    }

    func testExactFormStillBeatsFallback() {
        // Sanity-check: 見学 IS in `word_jlpt` at level 2 (N2) even though its
        // kanji are both N5. The exact-form path must win, NOT the kanji
        // fallback — otherwise we'd silently relax the official JLPT word
        // classification for everyone.
        let level = DictionaryService.shared.jlptLevel(forWord: "見学")
        XCTAssertEqual(level, 2, "見学 is classified N2 in the per-word list; exact-form path must take precedence")
    }

    func testKanaOnlyWordReturnsNil() {
        // Pure kana — fallback must bail out and keep current behaviour.
        XCTAssertNil(DictionaryService.shared.jlptLevel(forWord: "あいうえお"))
    }
}
