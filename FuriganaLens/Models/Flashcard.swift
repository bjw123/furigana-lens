import Foundation
import SwiftData

enum CardType: String, Codable, CaseIterable, Identifiable {
    case reading
    case meaning
    case sentence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reading: return "Reading"
        case .meaning: return "Meaning"
        case .sentence: return "Sentence"
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

    var cardType: CardType {
        get { CardType(rawValue: cardTypeRaw) ?? .reading }
        set { cardTypeRaw = newValue.rawValue }
    }

    init(
        expression: String,
        reading: String,
        meaning: String? = nil,
        meaningSource: String? = nil,
        contextSentence: String? = nil,
        cardType: CardType = .reading,
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
