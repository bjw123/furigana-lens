import Foundation

struct JapaneseToken: Identifiable, Hashable {
    let id: UUID
    let surface: String
    var reading: String
    let range: Range<String.Index>
    /// OCRLine.id this token was extracted from (nil for manual / non-OCR sources).
    var lineId: UUID? = nil
    /// Character index range within the source line (NOT byte offsets). Half-open.
    var lineCharRange: Range<Int>? = nil

    init(surface: String, reading: String, range: Range<String.Index>, lineId: UUID? = nil, lineCharRange: Range<Int>? = nil) {
        self.id = UUID()
        self.surface = surface
        self.reading = reading
        self.range = range
        self.lineId = lineId
        self.lineCharRange = lineCharRange
    }

    var hasKanji: Bool {
        surface.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }
    }

    var hasKana: Bool {
        surface.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) ||   // Hiragana
            (0x30A0...0x30FF).contains(scalar.value) ||   // Katakana
            (0xFF66...0xFF9D).contains(scalar.value)      // Halfwidth katakana
        }
    }
}
