import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query private var allCards: [Flashcard]
    @Query private var reviewLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Environment(\.modelContext) private var modelContext

    @State private var sessionQueue: [Flashcard]?
    @State private var sessionTitle: String = "Review"

    private var dueAll: [Flashcard] {
        SRSService.shared.dueCards(from: allCards)
    }

    private func dueIn(_ deck: Deck) -> [Flashcard] {
        SRSService.shared.dueCards(from: deck.cards)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                reviewHome
            }
            .navigationTitle("Review")
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { sessionQueue != nil },
                set: { if !$0 { sessionQueue = nil } }
            )
        ) {
            if let queue = sessionQueue {
                ReviewSessionView(queue: queue, title: sessionTitle)
            }
        }
    }

    // MARK: - Home

    private var reviewHome: some View {
        ScrollView {
            VStack(spacing: 18) {
                dueHero
                    .padding(.top, 8)

                if dueAll.count > 0 {
                    Button {
                        start(queue: dueAll, title: "Review")
                    } label: {
                        Label("Review all (\(dueAll.count))", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SumiButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }

                if !deckRows.isEmpty {
                    byDeckCard
                }

                if hasStats {
                    statsGrid
                    forecastCard
                    if !strugglingKanji.isEmpty {
                        strugglingKanjiCard
                    }
                    if !struggling.isEmpty {
                        strugglingCard
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(.vertical, 12)
        }
    }

    private var dueHero: some View {
        VStack(spacing: 18) {
            ZStack {
                // Tiny twinkles around the gem board — same accent the icon uses.
                SparkleAccent(size: 6, tint: Palette.cream)
                    .offset(x: -110, y: -90)
                SparkleAccent(size: 5, tint: Palette.sakura)
                    .offset(x: 120, y: -70)
                SparkleAccent(size: 4, tint: Palette.gold)
                    .offset(x: 100, y: 100)

                KanjiGemBoard(
                    sideTiles: 60,
                    spacing: 7,
                    centreSize: 124
                ) {
                    dueCentre
                }
            }
            .frame(height: 230)

            VStack(spacing: 4) {
                Text(dueAll.isEmpty ? "Nothing due" : "Time to crush kanji")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text(
                    dueAll.isEmpty
                        ? "Come back when cards are scheduled, or save new flashcards from a scan."
                        : "Review all decks at once, or pick a single deck below."
                )
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
    }

    @ViewBuilder
    private var dueCentre: some View {
        if dueAll.isEmpty {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.cream)
        } else {
            VStack(spacing: -2) {
                Text("\(dueAll.count)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.cream)
                Text("DUE")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.cream.opacity(0.85))
                    .tracking(1.4)
            }
        }
    }

    // MARK: - By deck

    private struct DeckRow: Identifiable {
        let deck: Deck
        let dueCount: Int
        var id: UUID { deck.id }
    }

    private var deckRows: [DeckRow] {
        decks
            .filter { !$0.isArchived && !$0.isExcludedFromReviews && !$0.cards.isEmpty }
            .map { DeckRow(deck: $0, dueCount: dueIn($0).count) }
    }

    private var byDeckCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "By deck",
                trailing: "\(deckRows.count) active"
            )
            BrushDivider()
            VStack(spacing: 8) {
                ForEach(deckRows) { row in
                    Button {
                        let queue = dueIn(row.deck)
                        guard !queue.isEmpty else { return }
                        start(queue: queue, title: row.deck.name)
                    } label: {
                        deckRowLabel(row)
                    }
                    .buttonStyle(.plain)
                    .disabled(row.dueCount == 0)
                    .opacity(row.dueCount == 0 ? 0.55 : 1.0)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func deckRowLabel(_ row: DeckRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.deck.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Palette.sumi)
                Text(row.deck.mediaTag)
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("\(row.dueCount)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(row.dueCount == 1 ? "due" : "due")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(row.dueCount == 0 ? Palette.mist : Palette.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    row.dueCount == 0
                        ? Palette.hairline
                        : Palette.indigo.opacity(0.12)
                )
            )
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mist.opacity(0.7))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Stats

    private var hasStats: Bool {
        !allCards.isEmpty || !reviewLogs.isEmpty
    }

    private var forecast: [StatsService.ForecastDay] {
        StatsService.forecast(days: 7, from: allCards)
    }

    private var successRate: Double? {
        StatsService.successRate(logs: reviewLogs, days: 30)
    }

    private var totalReviews: Int {
        StatsService.totalReviews(logs: reviewLogs)
    }

    private var streak: Int {
        StatsService.currentStreak(logs: reviewLogs)
    }

    private var struggling: [StatsService.StrugglingCard] {
        StatsService.strugglingCards(logs: reviewLogs, cards: allCards, days: 30, limit: 5)
    }

    private var strugglingKanji: [StatsService.StrugglingKanjiReading] {
        StatsService.strugglingKanjiReadings(logs: reviewLogs, cards: allCards, days: 30, limit: 8)
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statBox(
                value: successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                label: "Success",
                subtitle: totalReviews > 0 ? "\(totalReviews) reviews" : "no reviews yet",
                tint: Palette.bamboo
            )
            statBox(
                value: "\(streak)",
                label: "Day streak",
                subtitle: streak == 0 ? "start today" : (streak == 1 ? "keep it up" : "🌸 nice"),
                tint: Palette.sakura
            )
        }
        .padding(.horizontal)
    }

    private func statBox(value: String, label: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.sumi)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Palette.mist)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
    }

    private var forecastCard: some View {
        let days = forecast
        let maxCount = max(days.map(\.count).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Next 7 days",
                trailing: "\(days.map(\.count).reduce(0, +)) cards"
            )
            BrushDivider()

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.count > 0 ? "\(day.count)" : "·")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(day.count > 0 ? Palette.sumi : Palette.mist)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.hairline)
                                .frame(width: 22, height: 70)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(day.isToday ? Palette.sakura : Palette.indigo)
                                .frame(
                                    width: 22,
                                    height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 70)
                                )
                                .opacity(day.count == 0 ? 0.0 : 1.0)
                        }
                        Text(dayLabel(for: day.date))
                            .font(.system(.caption2, design: .rounded).weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? Palette.indigo : Palette.mist)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private var strugglingKanjiCard: some View {
        let maxAgain = strugglingKanji.map(\.againCount).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Struggling kanji", trailing: "last 30 days · by reading")
            BrushDivider()

            let columns = [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(strugglingKanji) { item in
                    NavigationLink {
                        KanjiDetailView(overview: StatsService.StrugglingKanji(
                            kanji: item.kanji,
                            againCount: item.againCount,
                            cards: item.cards,
                            strugglingCards: item.strugglingCards
                        ))
                    } label: {
                        kanjiTile(item: item, maxAgain: maxAgain)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func kanjiTile(item: StatsService.StrugglingKanjiReading, maxAgain: Int) -> some View {
        let intensity = max(0.25, min(1.0, Double(item.againCount) / Double(max(maxAgain, 1))))
        return VStack(spacing: 2) {
            Text(item.reading ?? "—")
                .font(.system(size: 11, design: .rounded).weight(.medium))
                .foregroundStyle(item.reading == nil ? Palette.mist : Palette.indigo.opacity(0.85))
                .padding(.top, 6)

            Text(String(item.kanji))
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.sumi)

            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9).weight(.semibold))
                Text("\(item.againCount)×")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(Palette.vermillion)

            Text("\(item.cards.count) word\(item.cards.count == 1 ? "" : "s")")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Palette.mist)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.vermillion.opacity(0.05 + 0.15 * intensity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.vermillion.opacity(0.25 + 0.35 * intensity), lineWidth: 0.75)
        )
    }

    private var strugglingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Struggling words", trailing: "last 30 days")
            BrushDivider()
            VStack(spacing: 8) {
                ForEach(struggling) { item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.card.expression)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Palette.sumi)
                            if !item.card.reading.isEmpty, item.card.reading != item.card.expression {
                                Text(item.card.reading)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Palette.indigo.opacity(0.85))
                            }
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2.weight(.semibold))
                            Text("\(item.againCount)×")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .foregroundStyle(Palette.vermillion)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.vermillion.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Palette.vermillion.opacity(0.35), lineWidth: 0.5))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func start(queue: [Flashcard], title: String) {
        guard !queue.isEmpty else { return }
        sessionTitle = title
        sessionQueue = queue
    }
}
