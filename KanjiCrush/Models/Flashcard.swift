import Foundation
import SwiftData

enum CardType: String, Codable, CaseIterable, Identifiable {
    case word
    case sentence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .word: return "Word"
        case .sentence: return "Sentence"
        }
    }

    /// Map any stored raw value — including legacy `reading`/`meaning` from the
    /// old three-way split — onto the current two-card model.
    static func from(rawValue raw: String) -> CardType {
        switch raw {
        case "sentence": return .sentence
        default: return .word
        }
    }
}

@Model
final class Flashcard {
    var id: UUID
    var expression: String
    var reading: String
    var meaning: String?
    var meaningSource: String?
    var contextSentence: String?
    var cardTypeRaw: String
    var createdAt: Date

    // SM-2 fields
    var interval: Double
    var easeFactor: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewed: Date?

    var deck: Deck?

    /// User-defined tags. Per-card, arbitrary strings (e.g. "verbs",
    /// "particles", "tricky"). Independent of `deck.mediaTag`, which is the
    /// per-deck broad category. Empty by default.
    var tags: [String] = []

    var cardType: CardType {
        get { CardType.from(rawValue: cardTypeRaw) }
        set { cardTypeRaw = newValue.rawValue }
    }

    init(
        expression: String,
        reading: String,
        meaning: String? = nil,
        meaningSource: String? = nil,
        contextSentence: String? = nil,
        cardType: CardType = .word,
        deck: Deck? = nil
    ) {
        self.id = UUID()
        self.expression = expression
        self.reading = reading
        self.meaning = meaning
        self.meaningSource = meaningSource
        self.contextSentence = contextSentence
        self.cardTypeRaw = cardType.rawValue
        self.createdAt = Date()
        self.interval = 0
        self.easeFactor = 2.5
        self.repetitions = 0
        self.dueDate = Date()
        self.lastReviewed = nil
        self.deck = deck
    }
}

@Model
final class ReviewLog {
    var id: UUID
    var reviewedAt: Date
    var quality: Int
    var flashcardId: UUID

    init(flashcardId: UUID, quality: Int) {
        self.id = UUID()
        self.reviewedAt = Date()
        self.quality = quality
        self.flashcardId = flashcardId
    }
}
