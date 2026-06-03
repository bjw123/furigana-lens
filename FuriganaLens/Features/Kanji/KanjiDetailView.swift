import SwiftUI
import SwiftData

/// Drill-in for a single kanji — shows every card in the user's decks that contains it
/// (so they can see all the readings/meanings that character has shown up with), plus
/// "Cram these" actions.
struct KanjiDetailView: View {
    let overview: StatsService.StrugglingKanji

    @Environment(\.modelContext) private var modelContext
    @State private var cramQueue: [Flashcard]?
    @State private var cramTitle: String = ""

    var body: some View {
        ZStack {
            WashiBackground()

            ScrollView {
                VStack(spacing: 16) {
                    heroCard

                    if !overview.cards.isEmpty {
                        cramActions
                        wordsCard
                    } else {
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                FuriganaWordView(
                    expression: card.expression,
                    reading: card.reading,
                    fontSize: 26
                )
                .fixedSize()
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
        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
