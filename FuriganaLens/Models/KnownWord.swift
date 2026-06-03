import Foundation
import SwiftData

/// A word the user has explicitly marked as known. Lives independently from
/// `Flashcard` so a word can be marked known without owning a flashcard, and
/// existing flashcards can stay in-progress without being treated as mastered.
@Model
final class KnownWord {
    @Attribute(.unique) var expression: String
    var markedAt: Date

    init(expression: String) {
        self.expression = expression
        self.markedAt = Date()
    }
}
