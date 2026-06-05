import Foundation
import SwiftData

/// Seeds the SwiftData store with realistic decks, flashcards (across the SM-2
/// lifecycle), review logs, and known words. Triggered by launching the app
/// with `-seedMockData reset` or `-seedMockData append`:
///
/// • `reset`  — wipe existing decks/flashcards/known words first
/// • `append` — only seed if the store has no decks yet
///
/// Activated automatically from `FuriganaLensApp` when the matching launch
/// argument is present.
enum MockDataSeeder {
    enum Mode: String { case reset, append }

    @MainActor
    static func seedIfRequested(container: ModelContainer) {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "-seedMockData"),
              idx + 1 < args.count,
              let mode = Mode(rawValue: args[idx + 1])
        else { return }

        let ctx = ModelContext(container)
        do {
            try seed(into: ctx, mode: mode)
            try ctx.save()
        } catch {
            print("MockDataSeeder: \(error)")
        }
    }

    private static func seed(into ctx: ModelContext, mode: Mode) throws {
        if mode == .reset {
            try wipe(ctx)
        } else {
            let existing = try ctx.fetch(FetchDescriptor<Deck>())
            if !existing.isEmpty { return }
        }

        let now = Date()
        let cal = Calendar.current

        // MARK: Decks

        let trails = Deck(name: "Trails Through Daybreak", mediaTag: "Game", accentColorHex: "4A90D9")
        let persona = Deck(name: "Persona 5 Royal",          mediaTag: "Game", accentColorHex: "D94A6A")
        let manga   = Deck(name: "Chainsaw Man",             mediaTag: "Manga", accentColorHex: "E0A040")
        let archived = Deck(
            name: "Yakuza 0 (finished)",
            mediaTag: "Game",
            accentColorHex: "8067A8",
            isArchived: true
        )

        [trails, persona, manga, archived].forEach { ctx.insert($0) }

        // MARK: Trails — mix of due/learning/mature cards

        let trailsSeeds: [CardSeed] = [
            .init(expression: "中年男", reading: "ちゅうねんおとこ", meaning: "middle-aged man",
                  context: "ハンチング帽の中年男", kind: .reading, dueOffsetDays: -1, reps: 0, ease: 2.5,
                  struggled: true),
            .init(expression: "連中", reading: "れんちゅう", meaning: "those guys; the bunch",
                  context: "連中には悟られてねえ筈だし", kind: .meaning, dueOffsetDays: -2, reps: 1, ease: 2.5),
            .init(expression: "悟る", reading: "さとる", meaning: "to realise; to perceive",
                  context: "連中には悟られてねえ筈だし", kind: .reading, dueOffsetDays: 3, reps: 3, ease: 2.45,
                  struggled: true),
            .init(expression: "稼ぎ時", reading: "かせぎどき", meaning: "peak earning time",
                  context: "カフェバーの稼ぎ時は夜だからな。", kind: .sentence, dueOffsetDays: -1, reps: 2, ease: 2.4),
            .init(expression: "情報屋", reading: "じょうほうや", meaning: "informant",
                  context: "情報屋ジャコモが現れるのを待とう", kind: .reading, dueOffsetDays: 14, reps: 5, ease: 2.6),
            .init(expression: "周囲", reading: "しゅうい", meaning: "surroundings",
                  context: "周囲の地形や各種位置情報を", kind: .reading, dueOffsetDays: 0, reps: 4, ease: 2.5),
            .init(expression: "地形", reading: "ちけい", meaning: "terrain",
                  context: "周囲の地形や各種位置情報を", kind: .meaning, dueOffsetDays: 21, reps: 6, ease: 2.7),
        ]

        // MARK: Persona — newer, mostly young cards

        let personaSeeds: [CardSeed] = [
            .init(expression: "改心", reading: "かいしん", meaning: "change of heart",
                  context: "改心マジすげえな！", kind: .reading, dueOffsetDays: -1, reps: 0, ease: 2.5,
                  struggled: true),
            .init(expression: "警察", reading: "けいさつ", meaning: "the police",
                  context: "マジで警察来てるな…", kind: .meaning, dueOffsetDays: 0, reps: 1, ease: 2.5,
                  struggled: true),
            .init(expression: "玄関", reading: "げんかん", meaning: "entranceway",
                  context: "玄関の所で見たぜ", kind: .reading, dueOffsetDays: -3, reps: 0, ease: 2.5),
            .init(expression: "観察", reading: "かんさつ", meaning: "observation; surveillance",
                  context: "観察も解ける。", kind: .reading, dueOffsetDays: 7, reps: 3, ease: 2.5,
                  struggled: true),
            .init(expression: "大人しく", reading: "おとなしく", meaning: "quietly; obediently",
                  context: "向こう1年は、大人しく暮らせ。", kind: .meaning, dueOffsetDays: 1, reps: 2, ease: 2.5),
        ]

        // MARK: Manga — mostly mature

        let mangaSeeds: [CardSeed] = [
            .init(expression: "悪魔", reading: "あくま", meaning: "devil",
                  context: "悪魔と契約した", kind: .reading, dueOffsetDays: 30, reps: 7, ease: 2.65),
            .init(expression: "契約", reading: "けいやく", meaning: "contract",
                  context: "悪魔と契約した", kind: .meaning, dueOffsetDays: 45, reps: 8, ease: 2.7),
            .init(expression: "心臓", reading: "しんぞう", meaning: "heart (organ)",
                  context: "心臓を捧げよ", kind: .reading, dueOffsetDays: -1, reps: 4, ease: 2.5),
        ]

        // MARK: Archived — old, all due (but excluded from queue)

        let archivedSeeds: [CardSeed] = [
            .init(expression: "極道", reading: "ごくどう", meaning: "yakuza; gangster",
                  context: "極道の道は厳しい", kind: .reading, dueOffsetDays: -90, reps: 9, ease: 2.8),
        ]

        let now0 = now
        insert(seeds: trailsSeeds,   into: trails,   at: now0, calendar: cal, ctx: ctx)
        insert(seeds: personaSeeds,  into: persona,  at: now0, calendar: cal, ctx: ctx)
        insert(seeds: mangaSeeds,    into: manga,    at: now0, calendar: cal, ctx: ctx)
        insert(seeds: archivedSeeds, into: archived, at: now0, calendar: cal, ctx: ctx)

        // MARK: Known words (not all of these need flashcards)

        let knownExpressions = ["猫", "犬", "学校", "先生", "本", "水", "食べる", "見る", "言う", "行く"]
        for expr in knownExpressions {
            let kw = KnownWord(expression: expr)
            // Stagger markedAt so the "recently learned" UI has shape.
            kw.markedAt = cal.date(byAdding: .day, value: -Int.random(in: 0...60), to: now0) ?? now0
            ctx.insert(kw)
        }
    }

    private static func wipe(_ ctx: ModelContext) throws {
        try ctx.delete(model: ReviewLog.self)
        try ctx.delete(model: Flashcard.self)
        try ctx.delete(model: Deck.self)
        try ctx.delete(model: KnownWord.self)
    }

    private static func insert(
        seeds: [CardSeed],
        into deck: Deck,
        at now: Date,
        calendar: Calendar,
        ctx: ModelContext
    ) {
        for seed in seeds {
            let card = Flashcard(
                expression: seed.expression,
                reading: seed.reading,
                meaning: seed.meaning,
                meaningSource: "mock",
                contextSentence: seed.context,
                cardType: seed.kind,
                deck: deck
            )
            card.repetitions = seed.reps
            card.easeFactor = seed.ease
            card.interval = max(1, Double(abs(seed.dueOffsetDays)))
            card.dueDate = calendar.date(byAdding: .day, value: seed.dueOffsetDays, to: now) ?? now
            card.lastReviewed = seed.reps > 0
                ? calendar.date(byAdding: .day, value: -Int(card.interval), to: now)
                : nil
            card.createdAt = calendar.date(byAdding: .day, value: -(seed.reps * 3 + 1), to: now) ?? now
            ctx.insert(card)

            // Synthesize prior review logs so streak/stats views have data.
            // Cards flagged `struggled` get interleaved Again (0) / Hard (2) grades
            // so the struggling-kanji and struggling-card panels have content.
            for n in 0..<seed.reps {
                let reviewedAt = calendar.date(byAdding: .day, value: -(seed.reps - n) * 2, to: now) ?? now
                let quality: Int
                if seed.struggled && (n == 0 || n == seed.reps / 2) {
                    quality = (n == 0) ? 0 : 2     // Again, then Hard
                } else {
                    quality = (n == 0) ? 3 : 4     // Good first, Easy after
                }
                let log = ReviewLog(flashcardId: card.id, quality: quality)
                log.reviewedAt = reviewedAt
                ctx.insert(log)
            }

            // Also seed a recent "today" Again log for some struggling cards so the
            // 30-day struggle window is hit even when reps is small.
            if seed.struggled && seed.reps < 3 {
                let recent = ReviewLog(flashcardId: card.id, quality: 0)
                recent.reviewedAt = calendar.date(byAdding: .day, value: -1, to: now) ?? now
                ctx.insert(recent)
            }
        }
    }

    private struct CardSeed {
        let expression: String
        let reading: String
        let meaning: String
        let context: String
        let kind: CardType
        /// Negative = overdue, 0 = due today, positive = future.
        let dueOffsetDays: Int
        let reps: Int
        let ease: Double
        /// When true, the synthesized review history includes Again (q=0) and Hard (q=2) grades
        /// so the Review tab's struggling-cards / struggling-kanji panels have content.
        var struggled: Bool = false
    }
}
