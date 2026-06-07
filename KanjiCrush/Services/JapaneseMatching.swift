import Foundation

/// Shared kana-folding, candidate-building, and fuzzy-matching primitives used
/// by the typed-review, daily-challenge, and sentence-speech surfaces. All
/// three previously carried their own slightly-different forks of this logic;
/// the speech variant — which adds long-vowel-mark stripping, small-kana
/// collapse, and fuzzy substring matching — is the superset and the basis of
/// this consolidated implementation.
enum JapaneseMatching {

    // MARK: - Normalisation

    /// Fold a raw user / recogniser string into a canonical hiragana stem
    /// suitable for direct equality / contains comparison.
    ///
    /// Composes (in order):
    ///   1. trim whitespace + okurigana markers (`.`, `-`) and common JP/ASCII
    ///      punctuation (`・`, `、`, `。`, `「`, `」`, `?` / `!` half/full-width)
    ///   2. romaji → hiragana via `CFStringTransform`
    ///   3. katakana → hiragana
    ///   4. drop the long-vowel mark `ー` and the small-kana the recogniser
    ///      occasionally emits but a written reading omits
    ///      (ぁぃぅぇぉ っ ゃゅょ, plus standalone ゛/゜)
    ///
    /// Step 4 is intentionally lossy: `コーヒー` reduces to `こひ`. The fold
    /// direction is consistent for both sides of any comparison, so equality
    /// is preserved while transcription drift collapses.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.filter { ch in
            ch != "." && ch != "-" && ch != "・"
                && ch != "、" && ch != "。" && ch != "「" && ch != "」"
                && ch != "?" && ch != "!" && ch != "?" && ch != "!"
        }
        if s.isEmpty { return "" }

        if s.unicodeScalars.contains(where: { $0.isASCII && $0.value > 32 }) {
            let lowered = s.lowercased() as NSString
            let mutable = NSMutableString(string: lowered)
            CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
            s = mutable as String
        }

        var folded = ""
        for scalar in s.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let mapped = Unicode.Scalar(scalar.value - 0x60) {
                folded.unicodeScalars.append(mapped)
            } else {
                folded.unicodeScalars.append(scalar)
            }
        }
        s = folded

        var compact = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x30FC: continue                          // ー long-vowel mark
            case 0x3041, 0x3043, 0x3045, 0x3047, 0x3049: continue  // ぁぃぅぇぉ
            case 0x3063: continue                          // っ small tsu
            case 0x3083, 0x3085, 0x3087: continue          // ゃゅょ
            case 0x309B, 0x309C: continue                  // ゛ ゜ standalone marks
            default:
                compact.unicodeScalars.append(scalar)
            }
        }

        return compact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Candidate building

    /// Build the deduped union of every reading + spelling that should count
    /// as "correct" for a single surface form. JMdict groups every accepted
    /// spelling of a word under one entry (kanji + kana arrays) — including
    /// BOTH covers the case where Apple's Japanese speech recogniser writes
    /// a different-but-equivalent kanji (e.g. `判る` for `分かる`) or falls
    /// back to plain kana.
    ///
    /// All candidates are passed through `normalize` and the result is
    /// deduped while preserving first-seen ordering.
    static func candidates(
        forExpression expression: String,
        tokenReading: String?,
        jmdictEntries: [DictionaryEntry]
    ) -> [String] {
        var raw: [String] = []
        if let tokenReading, !tokenReading.isEmpty {
            raw.append(tokenReading)
        }
        raw.append(expression)
        raw.append(contentsOf: jmdictEntries.flatMap { $0.kana })
        raw.append(contentsOf: jmdictEntries.flatMap { $0.kanji })

        var seen = Set<String>()
        var out: [String] = []
        for candidate in raw {
            let normalised = normalize(candidate)
            guard !normalised.isEmpty, seen.insert(normalised).inserted else { continue }
            out.append(normalised)
        }
        return out
    }

    // MARK: - Levenshtein + fuzzy match

    static func levenshtein(_ a: String, _ b: String) -> Int {
        levenshtein(Array(a), Array(b))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    /// Find the earliest range anchored at the start of `transcript` whose
    /// content is within edit distance ≈ `candidate.count / 4` of `candidate`
    /// (minimum 1, capped at `toleranceCap`). Anchoring at the start matters
    /// for the speech auto-advance loop — we don't want a candidate matching
    /// somewhere mid-suffix, only as a prefix of the un-consumed audio.
    ///
    /// Returns nil for candidates shorter than 2 chars (the tolerance would
    /// be larger than the candidate itself, making any string match) or when
    /// nothing matches within tolerance.
    static func fuzzyMatchEnd(
        in transcript: String,
        against candidate: String,
        toleranceCap: Int = 3
    ) -> Range<String.Index>? {
        guard candidate.count >= 2, !transcript.isEmpty else { return nil }
        let transcriptArr = Array(transcript)
        let candArr = Array(candidate)
        let tolerance = min(toleranceCap, max(1, candArr.count / 4))
        let minLen = max(1, candArr.count - tolerance)
        let maxLen = min(candArr.count + tolerance, transcriptArr.count)
        guard minLen <= maxLen else { return nil }
        for windowLen in minLen...maxLen {
            let window = Array(transcriptArr.prefix(windowLen))
            if levenshtein(candArr, window) <= tolerance {
                let endIndex = transcript.index(transcript.startIndex, offsetBy: windowLen)
                return transcript.startIndex..<endIndex
            }
        }
        return nil
    }
}
