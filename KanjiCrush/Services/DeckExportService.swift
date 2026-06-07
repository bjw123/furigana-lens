import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Versioned JSON payload for sharing decks between Kanji Crush users.
///
/// File extension: `.kcdeck`. UTType is declared in Info.plist via xcodegen so
/// the system file picker recognises it and the Share sheet shows other apps
/// only when relevant.
///
/// Schema version 1: deck metadata + flat list of cards. SM-2 progress is
/// deliberately *not* exported — the receiver should learn the deck fresh.
struct DeckPayload: Codable {
    static let currentVersion = 1

    var version: Int
    var deck: DeckRecord
    var cards: [CardRecord]

    struct DeckRecord: Codable {
        var name: String
        var mediaTag: String
        var accentColorHex: String
    }

    struct CardRecord: Codable {
        var expression: String
        var reading: String
        var meaning: String?
        var meaningSource: String?
        var contextSentence: String?
        var cardType: String        // "word" | "sentence"
        var tags: [String]
    }
}

extension UTType {
    /// Files saved with the `.kcdeck` extension are plain JSON internally —
    /// accept `.json` in pickers and let the user share/import any JSON-looking
    /// file. A future commit can declare a proper UTI via Info.plist if we
    /// want the system to filter pickers more tightly.
    static let kanjiCrushDeck: UTType = .json
}

enum DeckExportService {

    /// Build a `.kcdeck` JSON blob for the given deck. Pretty-printed so it's
    /// human-inspectable; gzipping isn't worth the complexity at this scale.
    static func export(deck: Deck) throws -> Data {
        let cards = deck.cards.map { card in
            DeckPayload.CardRecord(
                expression: card.expression,
                reading: card.reading,
                meaning: card.meaning,
                meaningSource: card.meaningSource,
                contextSentence: card.contextSentence,
                cardType: card.cardType.rawValue,
                tags: card.tags
            )
        }
        let payload = DeckPayload(
            version: DeckPayload.currentVersion,
            deck: DeckPayload.DeckRecord(
                name: deck.name,
                mediaTag: deck.mediaTag,
                accentColorHex: deck.accentColorHex
            ),
            cards: cards
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    /// File name suggestion for sharing — sanitises the deck name so the
    /// resulting filename is safe across iOS / macOS / Android share targets.
    static func suggestedFilename(for deck: Deck) -> String {
        let cleaned = deck.name
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let safe = cleaned.isEmpty ? "deck" : cleaned
        return "\(safe).kcdeck"
    }

    /// Decode a `.kcdeck` blob and insert a new `Deck` + its cards into the
    /// given model context. Returns the inserted deck. Handles deck-name
    /// collisions by suffixing " (imported)".
    @MainActor
    static func `import`(
        data: Data,
        into modelContext: ModelContext,
        existingDeckNames: Set<String>
    ) throws -> Deck {
        let decoder = JSONDecoder()
        let payload = try decoder.decode(DeckPayload.self, from: data)

        guard payload.version <= DeckPayload.currentVersion else {
            throw NSError(
                domain: "DeckExportService", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "This deck was made with a newer version of Kanji Crush. Update the app to import it."]
            )
        }

        let baseName = payload.deck.name
        var deckName = baseName
        if existingDeckNames.contains(deckName) {
            deckName = "\(baseName) (imported)"
            var n = 2
            while existingDeckNames.contains(deckName) {
                deckName = "\(baseName) (imported \(n))"
                n += 1
            }
        }

        let deck = Deck(
            name: deckName,
            mediaTag: payload.deck.mediaTag,
            accentColorHex: payload.deck.accentColorHex
        )
        modelContext.insert(deck)

        for record in payload.cards {
            let card = Flashcard(
                expression: record.expression,
                reading: record.reading,
                meaning: record.meaning,
                meaningSource: record.meaningSource,
                contextSentence: record.contextSentence,
                cardType: CardType.from(rawValue: record.cardType),
                deck: deck
            )
            card.tags = record.tags
            deck.cards.append(card)
            modelContext.insert(card)
        }

        try modelContext.save()
        return deck
    }
}
