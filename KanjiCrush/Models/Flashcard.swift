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
    /// Stable, value-typed identifier used for cross-record references — most
    /// importantly `ReviewLog.flashcardId`. We keep this alongside SwiftData's
    /// built-in `persistentModelID` because `persistentModelID` is awkward to
    /// serialise and can change before a model's first save, which would break
    /// logs written during an unsaved review session. Marked `.unique` so
    /// SwiftData indexes it and rejects collisions at the store level.
    @Attribute(.unique) var id: UUID
    var expression: String
    var reading: String
    var meaning: String?
    var meaningSource: String?
    var contextSentence: String?
    var hint: String?
    var cardTypeRaw: String
    var createdAt: Date

    // Legacy SM-2 fields. Kept on the schema so SwiftData lightweight
    // migration doesn't drop existing user data, but no longer consulted by
    // the scheduler (now FSRS-4.5). `interval`, `repetitions`, `dueDate`,
    // `lastReviewed` continue to be written for back-compat with views/services
    // that read them (e.g. maturity heuristic in ReviewSessionView, StatsService).
    var interval: Double
    var easeFactor: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewed: Date?

    // FSRS-4.5 state. `stability` (S) is the memory half-life in days at
    // R=0.9; `difficulty` (D) is the per-card challenge, on a 1..10 scale.
    // Both default to 0 for new cards — SRSService detects "first review" by
    // `stability == 0`.
    var stability: Double = 0
    var difficulty: Double = 0

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
        self.stability = 0
        self.difficulty = 0
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
