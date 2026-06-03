import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID
    var name: String
    var mediaTag: String
    var createdAt: Date
    var accentColorHex: String
    /// When true, cards from this deck are skipped by the SRS due queue.
    var isExcludedFromReviews: Bool = false
    /// When true, the deck is hidden from the main list and surfaced under "Archived".
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    var cards: [Flashcard]

    init(
        name: String,
        mediaTag: String = "General",
        accentColorHex: String = "4A90D9",
        isExcludedFromReviews: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.mediaTag = mediaTag
        self.createdAt = Date()
        self.accentColorHex = accentColorHex
        self.isExcludedFromReviews = isExcludedFromReviews
        self.isArchived = isArchived
        self.cards = []
    }
}
