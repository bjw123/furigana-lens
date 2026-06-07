import SwiftUI
import SwiftData

/// Per-kanji breakdown panel — one row per kanji in the expression with its
/// on'yomi / kun'yomi / meaning / JLPT level pulled from Kanjidic2. Each row
/// is tappable: tapping opens `KanjiDetailView` for that character in a
/// sheet so the user can drill into readings, JLPT examples, and the
/// per-reading drill without leaving their current flow.
///
/// Used from `WordDetailView` (when the user reveals a word's meaning) and
/// from the back of a word card in `ReviewSessionView`.
struct KanjiBreakdownView: View {
    let expression: String

    @Query private var reviewLogs: [ReviewLog]
    @Query private var allCards: [Flashcard]

    @State private var selection: KanjiSelection?

    private var kanjiCharacters: [Character] {
        // Preserve order, deduplicate (a word like 中年男 has 3 distinct).
        var seen = Set<Character>()
        var result: [Character] = []
        for ch in expression where Self.isKanji(ch) && !seen.contains(ch) {
            seen.insert(ch)
            result.append(ch)
        }
        return result
    }

    var body: some View {
        if !kanjiCharacters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Kanji breakdown", trailing: "tap for more")
                BrushDivider()
                VStack(spacing: 8) {
                    ForEach(kanjiCharacters, id: \.self) { ch in
                        Button {
                            selection = KanjiSelection(character: ch)
                        } label: {
                            KanjiBreakdownRow(kanji: ch)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .washiCard()
            .sheet(item: $selection) { sel in
                NavigationStack {
                    KanjiDetailView(
                        overview: StatsService.kanjiOverview(
                            sel.character,
                            logs: reviewLogs,
                            cards: allCards
                        )
                    )
                }
            }
        }
    }

    private struct KanjiSelection: Identifiable {
        let id: String
        let character: Character
        init(character: Character) {
            self.character = character
            self.id = String(character)
        }
    }

    static func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x20000...0x2A6DF).contains(scalar.value)
        }
    }
}

/// One row in the breakdown — kanji glyph on the left, on/kun + meaning to
/// the right, optional JLPT pill, chevron to indicate it pushes a sheet.
private struct KanjiBreakdownRow: View {
    let kanji: Character

    private var info: KanjiInfo? {
        DictionaryService.shared.kanjiInfo(kanji)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(kanji))
                .font(.system(size: 38, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.sumi)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .frame(width: 52, height: 52)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                if let info {
                    if !info.on.isEmpty {
                        readingLine(label: "on", readings: info.on, tint: Palette.vermillion)
                    }
                    if !info.kun.isEmpty {
                        readingLine(label: "kun", readings: info.kun, tint: Palette.indigo)
                    }
                    if !info.meanings.isEmpty {
                        Text(info.meanings.prefix(4).joined(separator: "; "))
                            .font(.caption)
                            .foregroundStyle(Palette.sumi.opacity(0.78))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("No Kanjidic entry — tap for more")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                if let level = info?.jlpt {
                    Text("N\(level)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.sakura)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.sakura.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Palette.sakura.opacity(0.4), lineWidth: 0.5))
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.mist.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func readingLine(label: String, readings: [String], tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint.opacity(0.85))
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(width: 24, alignment: .leading)
            Text(readings.prefix(4).joined(separator: " · "))
                .font(.system(.caption, design: .serif))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["Kanji \(kanji)."]
        if let info {
            if !info.meanings.isEmpty {
                parts.append("Meaning: \(info.meanings.prefix(3).joined(separator: ", ")).")
            }
            if !info.on.isEmpty {
                parts.append("On'yomi: \(info.on.joined(separator: ", ")).")
            }
            if !info.kun.isEmpty {
                parts.append("Kun'yomi: \(info.kun.joined(separator: ", ")).")
            }
            if let level = info.jlpt {
                parts.append("JLPT N\(level).")
            }
        }
        parts.append("Tap for the full kanji page.")
        return parts.joined(separator: " ")
    }
}
