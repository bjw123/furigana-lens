import SwiftUI
import Translation

// MARK: - Sentence card

struct SentenceCard: View {
    let sentence: String
    var strugglingKanji: Set<Character> = []
    let onDoubleTap: () -> Void
    var onTapKanaWord: ((JapaneseToken) -> Void)? = nil

    @State private var revealedTokenIds: Set<UUID> = []
    @State private var segments: [JapaneseToken]
    @State private var translation: String?
    @State private var translationError: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var showReadAloud = false
    @ObservedObject private var speech = SpeechService.shared

    init(
        sentence: String,
        strugglingKanji: Set<Character> = [],
        onDoubleTap: @escaping () -> Void,
        onTapKanaWord: ((JapaneseToken) -> Void)? = nil
    ) {
        self.sentence = sentence
        self.strugglingKanji = strugglingKanji
        self.onDoubleTap = onDoubleTap
        self.onTapKanaWord = onTapKanaWord
        _segments = State(initialValue: JapaneseAnalysisService.shared.segments(sentence))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sentence")
            BrushDivider()

            FlowLayout(spacing: 1) {
                ForEach(segments) { token in
                    tokenView(for: token)
                }
            }

            translationView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        }
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(sentence)
                await MainActor.run {
                    translation = response.targetText
                    translationError = nil
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
        .sheet(isPresented: $showReadAloud) {
            SentenceSpeechCheckView(
                sentence: sentence,
                expectedReading: JapaneseAnalysisService.shared.localReading(for: sentence),
                meaning: "",
                showFurigana: false
            )
        }
    }

    @ViewBuilder
    private var translationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                playButton
                if translation == nil && !isTranslating && translationError == nil {
                    translateButton
                }
                saveButton
                readAloudButton
                Spacer()
            }
            .padding(.top, 6)

            if let translation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translation")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(translation)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isTranslating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
            } else if let translationError {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translation failed")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.vermillion.opacity(0.85))
                        Text(translationError)
                            .font(.caption2)
                            .foregroundStyle(Palette.mist)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        startTranslation()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                            .foregroundStyle(Palette.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playButton: some View {
        let isActive = speech.isSpeaking(sentence)
        return Button {
            if isActive {
                speech.stop()
            } else {
                speech.speak(sentence)
            }
        } label: {
            Image(systemName: isActive ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                .foregroundStyle(Palette.indigo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Stop audio" : "Play sentence audio")
    }

    private var translateButton: some View {
        Button {
            startTranslation()
        } label: {
            Label("Show translation", systemImage: "character.bubble")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                .foregroundStyle(Palette.indigo)
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        } label: {
            Label("Save flashcard", systemImage: "bookmark.fill")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.sakura.opacity(0.18)))
                .foregroundStyle(Palette.sakura)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save sentence as flashcard")
    }

    private var readAloudButton: some View {
        Button {
            showReadAloud = true
        } label: {
            Label("Read aloud", systemImage: "mic.fill")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.sumi.opacity(0.12)))
                .foregroundStyle(Palette.sumi)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read sentence aloud")
    }

    private func startTranslation() {
        isTranslating = true
        translationError = nil
        // Force a new configuration so .translationTask re-fires even if same languages.
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ja"),
            target: Locale.Language(identifier: "en")
        )
    }

    @ViewBuilder
    private func tokenView(for token: JapaneseToken) -> some View {
        if token.hasKanji {
            let revealed = revealedTokenIds.contains(token.id)
            let isStruggling = token.surface.contains(where: { strugglingKanji.contains($0) })
            Button {
                toggle(token.id)
            } label: {
                if revealed, !token.reading.isEmpty, token.reading != token.surface {
                    VStack(spacing: 0) {
                        Text(token.reading)
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(isStruggling ? Palette.vermillion : Palette.indigo.opacity(0.85))
                        Text(token.surface)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(isStruggling ? Palette.vermillion : Palette.sumi)
                    }
                    .fixedSize()
                } else {
                    Text(token.surface)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(isStruggling ? Palette.vermillion : Palette.indigo)
                        .underline(true, pattern: .dot)
                }
            }
            .buttonStyle(.plain)
        } else if isLookupableKana(token) {
            Button {
                onTapKanaWord?(token)
            } label: {
                Text(token.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                    .underline(true, pattern: .dot, color: Palette.mist.opacity(0.45))
            }
            .buttonStyle(.plain)
        } else {
            Text(token.surface)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.sumi)
        }
    }

    /// Kana tokens that look like content words (not single-mora particles).
    private func isLookupableKana(_ token: JapaneseToken) -> Bool {
        token.hasKana && !token.hasKanji && token.surface.count >= 2
    }

    private func toggle(_ id: UUID) {
        if revealedTokenIds.contains(id) {
            revealedTokenIds.remove(id)
        } else {
            revealedTokenIds.insert(id)
        }
    }
}
