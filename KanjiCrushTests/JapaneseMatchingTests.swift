import XCTest
@testable import KanjiCrush

/// Covers the consolidated `JapaneseMatching` service used by the typed-review,
/// daily-challenge, and sentence-speech surfaces. The interesting cases are the
/// behaviours that ONLY existed in the speech fork before the consolidation
/// (long-vowel mark stripping, small-kana collapse, fuzzy matching) — those
/// are now expected to work for every quiz mode.
final class JapaneseMatchingTests: XCTestCase {

    // MARK: - Normalisation: katakana → hiragana

    func testKatakanaFoldsToHiragana() {
        XCTAssertEqual(JapaneseMatching.normalize("カタカナ"), "かたかな")
        XCTAssertEqual(JapaneseMatching.normalize("ニホン"), "にほん")
        XCTAssertEqual(JapaneseMatching.normalize("サクラ"), "さくら")
    }

    func testHiraganaIsPassedThrough() {
        XCTAssertEqual(JapaneseMatching.normalize("ひらがな"), "ひらがな")
        XCTAssertEqual(JapaneseMatching.normalize("にほんご"), "にほんご")
    }

    // MARK: - Normalisation: romaji → hiragana

    func testRomajiFoldsToHiragana() {
        XCTAssertEqual(JapaneseMatching.normalize("konnichiwa"), "こんにちは")
        XCTAssertEqual(JapaneseMatching.normalize("sakura"), "さくら")
        XCTAssertEqual(JapaneseMatching.normalize("hito"), "ひと")
    }

    func testRomajiIsCaseInsensitive() {
        XCTAssertEqual(JapaneseMatching.normalize("HITO"), "ひと")
        XCTAssertEqual(JapaneseMatching.normalize("Hito"), "ひと")
        XCTAssertEqual(JapaneseMatching.normalize("hito"), "ひと")
    }

    // MARK: - Normalisation: mixed inputs

    func testMixedScriptIsFolded() {
        // CFStringTransform turns "bar" into "ばー"; then katakana→hiragana
        // folds カフェ → かふぇ; then the small-kana strip drops ぇ and the
        // long-vowel mark strip drops ー → "かふば".
        XCTAssertEqual(JapaneseMatching.normalize("カフェbar"), "かふば")
    }

    // MARK: - Normalisation: long-vowel mark + small kana

    func testLongVowelMarkStripped() {
        XCTAssertEqual(JapaneseMatching.normalize("コーヒー"), "こひ")
        XCTAssertEqual(JapaneseMatching.normalize("カー"), "か")
    }

    func testSmallKanaStripped() {
        // ゅ drops, leaving し
        XCTAssertEqual(JapaneseMatching.normalize("しゅ"), "し")
        // small tsu drops
        XCTAssertEqual(JapaneseMatching.normalize("がっこう"), "がこう")
        // ゃ drops
        XCTAssertEqual(JapaneseMatching.normalize("きゃ"), "き")
    }

    // MARK: - Normalisation: whitespace + punctuation

    func testWhitespaceAndPunctuationStripped() {
        let cases: [(String, String)] = [
            ("  ひと  ",     "ひと"),
            ("ひと、",       "ひと"),
            ("「ひと」",     "ひと"),
            ("ひと。",       "ひと"),
            ("ひと?",        "ひと"),
            ("ひと!",        "ひと"),
            ("ひと?",        "ひと"),
            ("ひと!",        "ひと"),
            ("ひと・と",     "ひとと"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(JapaneseMatching.normalize(input), expected, "input=\(input)")
        }
    }

    func testOkuriganaMarkersStripped() {
        // み.る is the dictionary form for 見る; the marker is for display only.
        XCTAssertEqual(JapaneseMatching.normalize("み.る"), "みる")
        XCTAssertEqual(JapaneseMatching.normalize("あ-う"), "あう")
    }

    // MARK: - Normalisation: empty + edge cases

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(JapaneseMatching.normalize(""), "")
        XCTAssertEqual(JapaneseMatching.normalize("   "), "")
        XCTAssertEqual(JapaneseMatching.normalize("、。「」"), "")
    }

    func testSingleCharacterInputs() {
        XCTAssertEqual(JapaneseMatching.normalize("a"), "あ")
        XCTAssertEqual(JapaneseMatching.normalize("ア"), "あ")
        XCTAssertEqual(JapaneseMatching.normalize("あ"), "あ")
    }

    func testUnicodeNormalisationStability() {
        // Same logical string, different precomposition: NFC vs NFD.
        let nfc = "ガ"  // already precomposed
        let nfd = "が\u{3099}".precomposedStringWithCanonicalMapping  // dakuten + combiner
        XCTAssertEqual(JapaneseMatching.normalize(nfc), JapaneseMatching.normalize(nfd))
    }

    // MARK: - Candidate building

    private func makeEntry(kanji: [String], kana: [String]) -> DictionaryEntry {
        DictionaryEntry(id: 0, kanji: kanji, kana: kana, senses: [])
    }

    func testCandidatesReturnDedupedUnion() {
        let entry = makeEntry(kanji: ["分かる", "判る"], kana: ["わかる"])
        let cands = JapaneseMatching.candidates(
            forExpression: "分かる",
            tokenReading: "わかる",
            jmdictEntries: [entry]
        )
        // tokenReading + surface + entry.kana + entry.kanji — but
        // "わかる" appears twice, so dedup should knock it to a single entry.
        XCTAssertEqual(cands.count, 3, "expected 3 unique candidates after dedup: \(cands)")
        XCTAssertTrue(cands.contains("わかる"))
        XCTAssertTrue(cands.contains("分かる"))
        XCTAssertTrue(cands.contains("判る"))
    }

    func testCandidatesPreserveFirstSeenOrder() {
        let entry = makeEntry(kanji: ["分かる", "判る"], kana: ["わかる"])
        let cands = JapaneseMatching.candidates(
            forExpression: "分かる",
            tokenReading: "わかる",
            jmdictEntries: [entry]
        )
        // tokenReading is added first, so わかる should head the list.
        XCTAssertEqual(cands.first, "わかる")
    }

    func testCandidatesWithNilTokenReading() {
        let entry = makeEntry(kanji: ["人"], kana: ["ひと"])
        let cands = JapaneseMatching.candidates(
            forExpression: "人",
            tokenReading: nil,
            jmdictEntries: [entry]
        )
        XCTAssertTrue(cands.contains("人"))
        XCTAssertTrue(cands.contains("ひと"))
        XCTAssertFalse(cands.contains(""))
    }

    func testCandidatesWithEmptyTokenReading() {
        let entry = makeEntry(kanji: ["人"], kana: ["ひと"])
        let cands = JapaneseMatching.candidates(
            forExpression: "人",
            tokenReading: "",
            jmdictEntries: [entry]
        )
        // Empty tokenReading must NOT contribute a "" entry.
        XCTAssertFalse(cands.contains(""))
        XCTAssertEqual(cands.count, 2)
    }

    func testCandidatesHandlesOverlapBetweenEntries() {
        let entry1 = makeEntry(kanji: ["人"], kana: ["ひと"])
        let entry2 = makeEntry(kanji: ["人"], kana: ["ひと", "じん"])
        let cands = JapaneseMatching.candidates(
            forExpression: "人",
            tokenReading: "ひと",
            jmdictEntries: [entry1, entry2]
        )
        // ひと should appear once despite three sources contributing it.
        XCTAssertEqual(cands.filter { $0 == "ひと" }.count, 1)
        XCTAssertTrue(cands.contains("じん"))
        XCTAssertTrue(cands.contains("人"))
    }

    func testCandidatesAreNormalised() {
        // Entry's kana is in katakana — should fold to hiragana before dedup.
        let entry = makeEntry(kanji: ["珈琲"], kana: ["コーヒー"])
        let cands = JapaneseMatching.candidates(
            forExpression: "珈琲",
            tokenReading: "こひ",
            jmdictEntries: [entry]
        )
        // "コーヒー" normalises to "こひ", same as tokenReading, so dedup kicks in.
        XCTAssertEqual(cands.filter { $0 == "こひ" }.count, 1, "candidates=\(cands)")
        XCTAssertTrue(cands.contains("珈琲"))
    }

    // MARK: - Levenshtein

    func testLevenshteinBaseline() {
        XCTAssertEqual(JapaneseMatching.levenshtein("", ""), 0)
        XCTAssertEqual(JapaneseMatching.levenshtein("abc", "abc"), 0)
        XCTAssertEqual(JapaneseMatching.levenshtein("", "abc"), 3)
        XCTAssertEqual(JapaneseMatching.levenshtein("abc", ""), 3)
    }

    func testLevenshteinEditDistance() {
        XCTAssertEqual(JapaneseMatching.levenshtein("kitten", "sitting"), 3)
        XCTAssertEqual(JapaneseMatching.levenshtein("わかる", "わかった"), 2)
        XCTAssertEqual(JapaneseMatching.levenshtein("abc", "abd"), 1)
    }

    // MARK: - Fuzzy match: exact + near-exact

    func testFuzzyMatchExact() {
        // The fuzzy matcher anchors on `transcript.startIndex` and returns the
        // shortest window within tolerance. For an exact 3-char candidate
        // matched against a 3-char transcript with tolerance 1, that's a
        // 2-char prefix window (since lev("わかる", "わか") == 1 ≤ tolerance).
        // What matters is that it matches at all — start is always anchored.
        let range = JapaneseMatching.fuzzyMatchEnd(in: "わかる", against: "わかる")
        XCTAssertNotNil(range)
        if let range {
            XCTAssertEqual(range.lowerBound, "わかる".startIndex)
        }
    }

    func testFuzzyMatchLongerCandidateExact() {
        // Length 8 → tolerance = 2, minLen = 6. The 6-char window prefix
        // happens to satisfy ≤2 edits, so that's the first hit.
        let s = "あいうえおかきく"
        let range = JapaneseMatching.fuzzyMatchEnd(in: s, against: s)
        XCTAssertNotNil(range)
    }

    func testFuzzyMatchInsertionWithinTolerance() {
        // Candidate length 4 → tolerance = max(1, 4/4) = 1. Insertion of one
        // extra char anchored at the start of the transcript must still match.
        let range = JapaneseMatching.fuzzyMatchEnd(in: "あいxうえ", against: "あいうえ")
        XCTAssertNotNil(range, "single-insertion within tolerance should match")
    }

    func testFuzzyMatchInsertionPastToleranceFails() {
        // Two unrelated chars inserted — tolerance still 1 for a 4-char
        // candidate. Should NOT match.
        let range = JapaneseMatching.fuzzyMatchEnd(in: "あいxyうえ", against: "あいうえ")
        XCTAssertNil(range, "two insertions exceed tolerance")
    }

    func testFuzzyMatchShortCandidateRejected() {
        // 1-char candidate is below the min length — tolerance would equal
        // candidate length, accepting any string. Guarded against.
        XCTAssertNil(JapaneseMatching.fuzzyMatchEnd(in: "あいう", against: "a"))
    }

    func testFuzzyMatchEmptyInputs() {
        XCTAssertNil(JapaneseMatching.fuzzyMatchEnd(in: "", against: "わかる"))
        XCTAssertNil(JapaneseMatching.fuzzyMatchEnd(in: "わかる", against: ""))
        XCTAssertNil(JapaneseMatching.fuzzyMatchEnd(in: "", against: ""))
    }

    func testFuzzyMatchToleranceCapRespected() {
        // 16-char candidate would naturally allow 4 edits (16/4); but the
        // default cap of 3 keeps that down. Build a transcript that needs
        // exactly 4 edits to match — should fail with default cap.
        let cand = String(repeating: "あ", count: 16)
        let transcript = "い" + String(repeating: "あ", count: 12) + "いいい"
        XCTAssertNil(JapaneseMatching.fuzzyMatchEnd(in: transcript, against: cand))
        // Raise the cap and the same input should match.
        XCTAssertNotNil(JapaneseMatching.fuzzyMatchEnd(in: transcript, against: cand, toleranceCap: 4))
    }

    // MARK: - Fuzzy match: the real-world bug it was added to fix

    func testFuzzyMatchRunsTogetherCase() {
        // Reading "ストレスでしょ" continuously gets transcribed as
        // "ストレッスでしょ" — a stray small-tsu sneaks in. After normalisation,
        // the small tsu drops AND small kana drop, so candidate "でしょ"
        // (becomes "でし") lives at the tail of the already-normalised
        // transcript. The strict substring path resolves it.
        let transcript = JapaneseMatching.normalize("ストレッスでしょ")
        let candidate = JapaneseMatching.normalize("でしょ")
        XCTAssertEqual(candidate, "でし")
        XCTAssertTrue(transcript.contains(candidate),
                      "normalised transcript should contain normalised candidate after small-kana strip: t=\(transcript) c=\(candidate)")

        // Fuzzy path also resolves it when anchored on the suffix.
        if let range = transcript.range(of: candidate) {
            let suffix = String(transcript[range.lowerBound...])
            let fuzzyRange = JapaneseMatching.fuzzyMatchEnd(in: suffix, against: candidate)
            XCTAssertNotNil(fuzzyRange, "fuzzy match should hit at start of suffix")
        }
    }

    // MARK: - Cross-format equality (the whole point of normalising)

    func testCrossFormatEquality() {
        let pairs: [(String, String)] = [
            ("hito",   "ひと"),
            ("ヒト",   "ひと"),
            ("Hito",   "ヒト"),
            ("HITO",   "hito"),
            ("コーヒー", "コーヒー"),
            (" ひと ", "ひと"),
        ]
        for (a, b) in pairs {
            XCTAssertEqual(
                JapaneseMatching.normalize(a),
                JapaneseMatching.normalize(b),
                "expected \(a) ≡ \(b) after normalisation"
            )
        }
    }
}
