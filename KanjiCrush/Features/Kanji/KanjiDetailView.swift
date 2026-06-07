import SwiftUI
import SwiftData

/// Drill-in for a single kanji — shows every card in the user's decks that contains it
/// (so they can see all the readings/meanings that character has shown up with), plus
/// "Cram these" actions.
struct KanjiDetailView: View {
    let overview: StatsService.StrugglingKanji

    @Environment(\.modelContext) private var modelContext
    @Query private var knownWords: [KnownWord]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0
    @State private var cramQueue: [Flashcard]?
    @State private var cramTitle: String = ""
    @State private var showTypedReview = false

    private var kanjiInfo: KanjiInfo? {
        DictionaryService.shared.kanjiInfo(overview.kanji)
    }

    private var jlptExamples: [JLPTWordExample] {
        DictionaryService.shared.jlptExamples(forKanji: overview.kanji, perLevel: 4)
    }

    var body: some View {
        ZStack {
            WashiBackground()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard

                    if let info = kanjiInfo {
                        readingsCard(info: info)
                    }

                    if !jlptExamples.isEmpty {
                        jlptExamplesCard(examples: jlptExamples)
                    }

                    if hasTypedReviewContent {
                        typedReviewActionCard
                    }

                    if !overview.cards.isEmpty {
                        cramActions
                        wordsCard
                    } else if kanjiInfo == nil && jlptExamples.isEmpty {
                        emptyHint
                    }

                    Spacer(minLength: 24)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(String(overview.kanji))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(
            isPresented: Binding(
                get: { cramQueue != nil },
                set: { if !$0 { cramQueue = nil } }
            )
        ) {
            if let queue = cramQueue {
                ReviewSessionView(
                    queue: queue,
                    title: cramTitle,
                    sessionKind: .cram
                )
            }
        }
        .fullScreenCover(isPresented: $showTypedReview) {
            KanjiTypedReviewView(
                kanji: overview.kanji,
                info: kanjiInfo,
                examples: jlptExamples
            )
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            Text(String(overview.kanji))
                .font(.system(size: 160, weight: .bold, design: .serif))
                .foregroundStyle(Palette.sumi)
                .padding(.top, 6)

            HStack(spacing: 8) {
                infoChip(
                    label: "\(overview.cards.count) word\(overview.cards.count == 1 ? "" : "s")",
                    icon: "text.book.closed.fill",
                    tint: Palette.indigo
                )
                if overview.againCount > 0 {
                    infoChip(
                        label: "\(overview.againCount)× again",
                        icon: "arrow.counterclockwise",
                        tint: Palette.vermillion
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .washiCard(padding: 22, cornerRadius: 24)
        .padding(.horizontal)
    }

    private func infoChip(label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }

    // MARK: - Cram actions

    private var cramActions: some View {
        VStack(spacing: 10) {
            if !overview.strugglingCards.isEmpty {
                Button {
                    cramTitle = "Struggles · \(overview.kanji)"
                    cramQueue = overview.strugglingCards.shuffled()
                } label: {
                    Label(
                        "Cram \(overview.strugglingCards.count) struggling word\(overview.strugglingCards.count == 1 ? "" : "s")",
                        systemImage: "flame.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle(tint: Palette.vermillion))
            }

            Button {
                cramTitle = "All · \(overview.kanji)"
                cramQueue = overview.cards.shuffled()
            } label: {
                Label(
                    "Cram all \(overview.cards.count) word\(overview.cards.count == 1 ? "" : "s")",
                    systemImage: "shuffle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WashiButtonStyle())
        }
        .padding(.horizontal)
    }

    // MARK: - Words list

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Words you've saved",
                trailing: "\(overview.cards.count)"
            )
            BrushDivider()

            VStack(spacing: 10) {
                ForEach(overview.cards.sorted(by: { $0.expression.count < $1.expression.count })) { card in
                    NavigationLink {
                        CardEditView(card: card)
                    } label: {
                        wordRow(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func wordRow(card: Flashcard) -> some View {
        let isKnown = Knownness.isKnown(
            expression: card.expression,
            knownWords: knownWords,
            userJLPTLevel: jlptLevel
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                FuriganaWordView(
                    expression: card.expression,
                    reading: card.reading,
                    fontSize: 26
                )
                .fixedSize()
                if isKnown {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Known")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.gold.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.4), lineWidth: 0.5))
                }
                if let deck = card.deck {
                    Text(deck.name)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.indigo.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.3), lineWidth: 0.5))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.mist.opacity(0.6))
            }
            if let meaning = card.meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .lineLimit(2)
            }
            if let sentence = card.contextSentence, !sentence.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.mist)
                    Text(sentence)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Palette.mist)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            (isKnown ? Palette.gold.opacity(0.07) : Palette.cream),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isKnown ? Palette.gold.opacity(0.45) : Palette.hairline,
                    lineWidth: isKnown ? 1 : 0.5
                )
        )
    }

    // MARK: - Typed review

    private var hasTypedReviewContent: Bool {
        let readings = (kanjiInfo?.on.count ?? 0) + (kanjiInfo?.kun.count ?? 0)
        return readings > 0 || !jlptExamples.isEmpty
    }

    private var typedReviewActionCard: some View {
        Button {
            showTypedReview = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Palette.sakura.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.sakura)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiz this kanji")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.sumi)
                    Text("Type the reading or meaning — wrong answers retry.")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mist.opacity(0.7))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .washiCard(padding: 8)
        .padding(.horizontal)
    }

    // MARK: - Readings + JLPT (Kanjidic2-backed)

    private func readingsCard(info: KanjiInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Readings",
                trailing: info.jlpt.map { "N\($0)" }
            )
            BrushDivider()

            if !info.on.isEmpty {
                readingRow(label: "On'yomi", readings: info.on, tint: Palette.vermillion)
            }
            if !info.kun.isEmpty {
                readingRow(label: "Kun'yomi", readings: info.kun, tint: Palette.indigo)
            }
            if !info.meanings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meaning")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(info.meanings.prefix(6).joined(separator: "; "))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func readingRow(label: String, readings: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
            FlowLayout(spacing: 6) {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                    Text(reading)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
                }
            }
        }
    }

    private func jlptExamplesCard(examples: [JLPTWordExample]) -> some View {
        let grouped = Dictionary(grouping: examples, by: \.level)
        // Display N5 → N1 so easier examples come first.
        let levels = grouped.keys.sorted(by: >)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "JLPT examples", trailing: "N5 → N1")
            BrushDivider()

            VStack(alignment: .leading, spacing: 12) {
                ForEach(levels, id: \.self) { level in
                    jlptLevelBlock(level: level, items: grouped[level] ?? [])
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func jlptLevelBlock(level: Int, items: [JLPTWordExample]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("N\(level)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.sakura)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.sakura.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Palette.sakura.opacity(0.4), lineWidth: 0.5))
                Spacer()
            }
            VStack(spacing: 6) {
                ForEach(items) { item in
                    jlptExampleRow(item: item)
                }
            }
        }
    }

    private func jlptExampleRow(item: JLPTWordExample) -> some View {
        let showReading = !item.reading.isEmpty && item.reading != item.form
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if showReading {
                    Text(item.reading)
                        .font(.system(size: 11, design: .rounded).weight(.medium))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
                Text(item.form)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Palette.sumi)
            }
            .fixedSize(horizontal: true, vertical: false)
            if !item.gloss.isEmpty {
                Text(item.gloss)
                    .font(.caption)
                    .foregroundStyle(Palette.sumi.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            MapleGlyph(size: 28)
            Text("No saved words contain this kanji yet.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
    }
}
