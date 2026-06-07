import Foundation

/// On-device Japanese tokenization + reading lookup.
/// Uses CFStringTokenizer with `kCFStringTokenizerAttributeLatinTranscription` —
/// the same Japanese analyzer the OS uses for VoiceOver / TTS. Reading is
/// produced by transliterating the romaji output to hiragana with CFStringTransform.
final class JapaneseAnalysisService {
    static let shared = JapaneseAnalysisService()

    private let locale = Locale(identifier: "ja_JP") as CFLocale

    func tokenize(_ text: String) -> [JapaneseToken] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = makeTokenizer(for: trimmed)
        var tokens: [JapaneseToken] = []

        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
            guard let range = Range(nsRange, in: trimmed) else { continue }

            let surface = String(trimmed[range])
            guard surface.containsJapanese else { continue }

            let reading = readingForCurrentToken(tokenizer, surface: surface)
            tokens.append(JapaneseToken(surface: surface, reading: reading, range: range))
        }

        return tokens
    }

    /// Like `tokenize` but keeps every segment (including punctuation, spaces, and
    /// non-Japanese runs) so a sentence can be rendered intact with per-token tap targets.
    func segments(_ text: String) -> [JapaneseToken] {
        guard !text.isEmpty else { return [] }
        let tokenizer = makeTokenizer(for: text)
        var out: [JapaneseToken] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
            guard let range = Range(nsRange, in: text) else { continue }
            let surface = String(text[range])
            let reading = surface.containsJapanese
                ? readingForCurrentToken(tokenizer, surface: surface)
                : surface
            out.append(JapaneseToken(surface: surface, reading: reading, range: range))
        }
        return out
    }

    func localReading(for surface: String) -> String {
        if let override = ReadingOverrideStore.shared.reading(for: surface) {
            return override
        }
        if surface.allKana { return surface }

        let tokenizer = makeTokenizer(for: surface)
        var combined = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
            guard let range = Range(nsRange, in: surface) else { continue }
            let part = String(surface[range])
            combined += readingForCurrentToken(tokenizer, surface: part)
        }
        return combined.isEmpty ? surface : combined
    }

    /// Kept for API compatibility. Always false now — readings are produced locally.
    func needsRemoteReading(_ surface: String) -> Bool { false }

    private func makeTokenizer(for text: String) -> CFStringTokenizer {
        let nsLength = (text as NSString).length
        return CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            CFRangeMake(0, nsLength),
            kCFStringTokenizerUnitWord,
            locale
        )
    }

    private func readingForCurrentToken(_ tokenizer: CFStringTokenizer, surface: String) -> String {
        if let override = ReadingOverrideStore.shared.reading(for: surface) {
            return override
        }
        if surface.allKana { return surface }

        guard let romaji = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer,
            kCFStringTokenizerAttributeLatinTranscription
        ) as? String, !romaji.isEmpty else {
            return surface
        }

        let mutable = NSMutableString(string: romaji)
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        let hiragana = mutable as String
        return hiragana.isEmpty ? surface : hiragana
    }
}

private extension String {
    var allKana: Bool {
        !isEmpty && unicodeScalars.allSatisfy { $0.isHiragana || $0.isKatakana }
    }

    var containsJapanese: Bool {
        unicodeScalars.contains { $0.isHiragana || $0.isKatakana || $0.isKanji }
    }
}

private extension UnicodeScalar {
    var isHiragana: Bool { (0x3040...0x309F).contains(value) }
    var isKatakana: Bool { (0x30A0...0x30FF).contains(value) || (0xFF66...0xFF9D).contains(value) }
    var isKanji: Bool {
        (0x4E00...0x9FFF).contains(value) ||
        (0x3400...0x4DBF).contains(value) ||
        (0xF900...0xFAFF).contains(value)
    }
}
