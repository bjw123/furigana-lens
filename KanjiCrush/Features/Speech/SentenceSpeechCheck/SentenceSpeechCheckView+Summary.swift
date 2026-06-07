import SwiftUI

extension SentenceSpeechCheckView {

    // MARK: - Completion summary

    @ViewBuilder
    var summaryView: some View {
        // All chunks got a `matched: true` result AND none are pending (i.e.
        // every chunk in the list has a corresponding result entry).
        let allMatched = !chunks.isEmpty
            && chunks.allSatisfy { chunk in
                results.contains { $0.id == chunk.id && $0.matched }
            }
        let solvedStruggling: [Character] = allMatched
            ? Array(Set(sentence.filter { isKanji($0) }).intersection(strugglingKanjiChars)).sorted()
            : []
        VStack(spacing: 14) {
            if allMatched {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Read aloud correctly!")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.bamboo)
                if !solvedStruggling.isEmpty {
                    VStack(spacing: 8) {
                        Text("You read kanji you've been struggling with: \(solvedStruggling.map { String($0) }.joined(separator: " "))")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.sumi)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            ForEach(Array(solvedStruggling.enumerated()), id: \.offset) { _, ch in
                                KanjiGemBadge(kanji: String(ch), tint: Palette.gold, size: 36)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.gold.opacity(0.5), lineWidth: 0.75)
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(pendingOrMissedHeadline)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)
                missedChunksSection
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            VStack(spacing: 8) {
                Button {
                    resetSession()
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())
                Button { dismiss() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(WashiButtonStyle())
            }
            .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    /// Chunks the user never matched — either explicit wrong results, or
    /// chunks that simply never got their candidate reading in the suffix
    /// before the session ended. Both end up in the save-list because the
    /// learner cares about the *word*, not how the session ended.
    var unmatchedChunks: [Chunk] {
        chunks.filter { chunk in
            !results.contains { $0.id == chunk.id && $0.matched }
        }
    }

    var pendingOrMissedHeadline: String {
        let unmatchedCount = unmatchedChunks.count
        if unmatchedCount == chunks.count {
            return "Session stopped — nothing matched"
        }
        return unmatchedCount == 1 ? "1 part wasn't heard" : "\(unmatchedCount) parts weren't heard"
    }

    @ViewBuilder
    var missedChunksSection: some View {
        let unmatched = unmatchedChunks
        if !unmatched.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save these as flashcards")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                FlowLayout(spacing: 6) {
                    ForEach(unmatched.filter { containsKanji($0.surface) }) { chunk in
                        Button {
                            pendingSaveToken = SaveTokenRequest(
                                surface: chunk.surface,
                                reading: chunk.reading,
                                context: sentence
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                Text(chunk.surface)
                                    .font(.system(.subheadline, design: .serif))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Palette.indigo.opacity(0.12))
                            )
                            .foregroundStyle(Palette.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
