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

    // MARK: - Exact-form path takes priority

    func testExactDictionaryFormHitsBeforeFallback() {
        // 見る IS in `word_jlpt` (dictionary form) at N5. We expect the exact
        // lookup to return level 5 — same answer the kanji fallback would give,
        // but for the right reason. This guards against accidentally removing
        // the exact-form branch and relying entirely on fallback.
        let level = DictionaryService.shared.jlptLevel(forWord: "見る")
        XCTAssertEqual(level, 5, "見る is in the JLPT vocab list at N5; must resolve via direct lookup")
    }

    // MARK: - Pure-kana words must short-circuit before fallback

    func testCommonKanaPhraseUsesExactLookup() {
        // こんにちは contains zero kanji, so the fallback path is structurally
        // incapable of classifying it — a non-nil result here can only come
        // from the exact-form (word_jlpt) path. We don't pin the exact level
        // (the bundled Tanos-style vocab list has it at N3, not N5 as casual
        // intuition suggests), just that the lookup succeeds and returns a
        // valid 1..5 level.
        let level = DictionaryService.shared.jlptLevel(forWord: "こんにちは")
        let unwrapped = try? XCTUnwrap(level, "こんにちは is in the JLPT vocab list; exact-form lookup must hit since there are no kanji to fall back on")
        XCTAssertNotNil(unwrapped)
        if let unwrapped { XCTAssertTrue((1...5).contains(unwrapped), "got level \(unwrapped) outside 1..5") }
    }

    // MARK: - Conjugated kanji-bearing forms

    func testConjugatedFormWithMultipleKanji() {
        // 食べる is N5 in the vocab list; 食べた (past tense) is not.
        // The fallback should classify it via 食 (N5) → level 5.
        let level = DictionaryService.shared.jlptLevel(forWord: "食べた")
        XCTAssertEqual(level, 5, "食 is N5; conjugated 食べた should fall back to N5")
    }

    // MARK: - All-kanji must have a level

    func testFallbackReturnsNilWhenAnyKanjiIsUnrated() {
        // The fallback is intentionally strict: if even ONE kanji in the word
        // has no JLPT classification, we must return nil rather than silently
        // grading the word by its easier neighbours. 鬱 (depression) is a
        // jouyou kanji but not in any JLPT level, while 見 is N5. Combining
        // them in a non-existent surface forces the all-rated guard and
        // should return nil — NOT N5.
        let level = DictionaryService.shared.jlptLevel(forWord: "鬱見")
        XCTAssertNil(level, "鬱 has no JLPT rating; presence of an unrated kanji must veto the fallback")
    }

    func testFallbackReturnsNilWhenAllKanjiUnrated() {
        // 鬱鬱 — every kanji is unrated → nil. (Also exercises the per-row
        // SQLite reset/clear_bindings loop with duplicate characters.)
        let level = DictionaryService.shared.jlptLevel(forWord: "鬱鬱")
        XCTAssertNil(level)
    }
}
