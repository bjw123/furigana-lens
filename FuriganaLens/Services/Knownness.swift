import Foundation
import SwiftData

/// Single source of truth for "is this word known?". Two signals stack:
///
/// 1. `KnownWord` rows are the *override*. If a row exists for the expression,
///    its `isKnown` flag wins (the user has explicitly clicked known/unknown).
/// 2. Otherwise, the user's JLPT level (`@AppStorage("jlptLevel")`) implies
///    knownness for any word the bundled JLPT vocab table places at the same
///    level or easier (numerically ≥ the user's level — N5=5, N1=1).
///
/// Storing an override row only when the desired state diverges from the
/// JLPT default keeps the table small even when the user is at N1.
enum Knownness {

    /// User-facing knownness for an expression — combines explicit override
    /// rows with the JLPT-implied default.
    static func isKnown(
        expression: String,
        knownWords: [KnownWord],
        userJLPTLevel: Int
    ) -> Bool {
        if let row = knownWords.first(where: { $0.expression == expression }) {
            return row.isKnown
        }
        return jlptImplies(known: expression, userJLPTLevel: userJLPTLevel)
    }

    /// True when `expression` is at-or-below the user's JLPT level (i.e. its
    /// JMdict-derived level number is ≥ the user's). Returns false when no
    /// level is configured or the word isn't in the JLPT vocab table.
    static func jlptImplies(
        known expression: String,
        userJLPTLevel: Int
    ) -> Bool {
        guard (1...5).contains(userJLPTLevel),
              let wordLevel = DictionaryService.shared.jlptLevel(forWord: expression)
        else { return false }
        return wordLevel >= userJLPTLevel
    }

    /// Mutates the `KnownWord` table so `isKnown(expression:…)` will return
    /// `desired` next time. Only persists a row when the desired state differs
    /// from what the user's JLPT level would imply on its own.
    @MainActor
    static func setKnown(
        _ desired: Bool,
        expression: String,
        userJLPTLevel: Int,
        existing: [KnownWord],
        modelContext: ModelContext
    ) {
        for row in existing where row.expression == expression {
            modelContext.delete(row)
        }
        let jlptDefault = jlptImplies(known: expression, userJLPTLevel: userJLPTLevel)
        if desired != jlptDefault {
            modelContext.insert(KnownWord(expression: expression, isKnown: desired))
        }
        try? modelContext.save()
    }
}
