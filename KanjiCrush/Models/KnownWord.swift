import Foundation
import SwiftData

/// A word's explicit knownness override. Lives independently from `Flashcard`
/// so a word can be marked known without owning a flashcard, and existing
/// flashcards can stay in-progress without being treated as mastered.
///
/// `isKnown == false` means the user explicitly marked this word as unknown,
/// overriding a "should be known by your JLPT level" implicit-known. We only
/// store a row when the user wants to override the JLPT-implied default — so
/// the table stays small even at high JLPT levels.
@Model
final class KnownWord {
    @Attribute(.unique) var expression: String
    var markedAt: Date
    var isKnown: Bool = true

    init(expression: String, isKnown: Bool = true) {
        self.expression = expression
        self.markedAt = Date()
        self.isKnown = isKnown
    }
}
