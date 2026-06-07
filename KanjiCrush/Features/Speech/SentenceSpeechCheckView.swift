import SwiftUI
import SwiftData

/// Reusable speech-check sheet: shows a Japanese prompt (sentence or word),
/// listens to the learner read it aloud, grades the transcript per-token,
/// and offers congratulation + save-missed-word flows on completion.
///
/// Mirrors the .speech-mode flow from `SessionRunner` in `KanjiTypedReviewView`,
/// but operates over an arbitrary sentence/reading pair rather than the
/// kanji-quiz queue. The two implementations are intentionally kept separate
/// so the kanji-quiz path stays untouched.
struct SentenceSpeechCheckView: View {
    let sentence: String
    let expectedReading: String
    let meaning: String
    var showFurigana: Bool

    @Environment(\.dismiss) private var dismiss

    @Query private var allCards: [Flashcard]
    @Query private var allLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @StateObject private var speech = SpeechRecognitionService()

    @State private var input: String = ""
    @State private var feedback: Feedback?
    @State private var authChecked = false
    @State private var pendingSaveToken: SaveTokenRequest?
    @State private var showFuriganaState: Bool
    @FocusState private var inputFocused: Bool

    init(sentence: String, expectedReading: String, meaning: String, showFurigana: Bool) {
        self.sentence = sentence
        self.expectedReading = expectedReading
        self.meaning = meaning
        self.showFurigana = showFurigana
        _showFuriganaState = State(initialValue: showFurigana)
    }

    private var strugglingKanjiChars: Set<Character> {
        Set(StatsService.strugglingKanjiReadings(logs: allLogs, cards: allCards, days: 30, limit: 32).map(\.kanji))
    }

    private enum Feedback {
        case speech(diff: [TokenDiff], allCorrect: Bool, solvedStrugglingKanji: [Character])
    }

    fileprivate struct TokenDiff: Identifiable {
        let id = UUID()
        let prompt: String
        let expectedReading: String
        let matched: Bool

        var hasKanji: Bool {
            prompt.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value) ||
                (0x20000...0x2A6DF).contains(scalar.value)
            }
        }
    }

    fileprivate struct SaveTokenRequest: Identifiable {
        let id = UUID()
        let token: TokenDiff
        let context: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        promptView
                        furiganaToggle
                        micRow
                        transcriptField
                        Text("Edit the transcript above if needed, then Submit")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Palette.mist)
                        feedbackView
                        actionButton
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Read aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: speech.transcript) { _, new in
                input = new
            }
            .sheet(item: $pendingSaveToken) { req in
                let meaningLookup = DictionaryService.shared.lookup(req.token.prompt, limit: 1).first
                    .map { $0.glosses().joined(separator: "; ") } ?? ""
                SaveFlashcardSheet(
                    expression: req.token.prompt,
                    reading: req.token.expectedReading,
                    meaning: meaningLookup.isEmpty ? nil : meaningLookup,
                    meaningSource: meaningLookup.isEmpty ? nil : "JMdict",
                    contextSentence: req.context,
                    decks: decks
                )
            }
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private var promptView: some View {
        if showFuriganaState {
            FuriganaSentenceView(sentence: sentence, fontSize: 24)
                .frame(maxWidth: .infinity)
        } else {
            Text(sentence)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.sumi)
        }
    }

    private var furiganaToggle: some View {
        Toggle("Show furigana", isOn: $showFuriganaState)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Palette.mist)
            .tint(Palette.indigo)
            .padding(.horizontal, 16)
    }

    private var micRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleListening() }
            } label: {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(speech.isListening ? Palette.vermillion : Palette.indigo)
            }
            .disabled(!speech.isAvailable && !speech.isListening)
            if speech.isListening {
                Text("Listening…")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.vermillion)
            }
        }
    }

    private var transcriptField: some View {
        TextField("What you said", text: $input)
            .focused($inputFocused)
            .submitLabel(.go)
            .onSubmit { submit() }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.title3, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .padding(.horizontal)
            .disabled(feedback != nil)
    }

    private var strokeColor: Color {
        switch feedback {
        case .speech(_, let allCorrect, _):
            return allCorrect ? Palette.bamboo.opacity(0.85) : Palette.vermillion.opacity(0.85)
        case nil:
            return Palette.hairline
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackView: some View {
        switch feedback {
        case .speech(let diff, let allCorrect, let solvedStrugglingKanji):
            speechFeedback(
                diff: diff,
                allCorrect: allCorrect,
                solvedStrugglingKanji: solvedStrugglingKanji
            )
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func speechFeedback(
        diff: [TokenDiff],
        allCorrect: Bool,
        solvedStrugglingKanji: [Character]
    ) -> some View {
        if allCorrect {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Read aloud correctly!")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.bamboo)

                if !solvedStrugglingKanji.isEmpty {
                    VStack(spacing: 8) {
                        Text("You read kanji you've been struggling with: \(solvedStrugglingKanji.map { String($0) }.joined(separator: " "))")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.sumi)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            ForEach(Array(solvedStrugglingKanji.enumerated()), id: \.offset) { _, ch in
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

                if !meaning.isEmpty {
                    Text(meaning)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Some words were missed")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)

                FlowLayout(spacing: 6) {
                    ForEach(diff) { token in
                        HStack(spacing: 4) {
                            Image(systemName: token.matched ? "checkmark" : "xmark")
                                .font(.caption2.weight(.bold))
                            Text(token.prompt)
                                .font(.system(.subheadline, design: .serif))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                token.matched
                                    ? Palette.bamboo.opacity(0.15)
                                    : Palette.vermillion.opacity(0.18)
                            )
                        )
                        .foregroundStyle(token.matched ? Palette.bamboo : Palette.vermillion)
                    }
                }

                let missedKanjiTokens = diff.filter { !$0.matched && $0.hasKanji }
                if !missedKanjiTokens.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Save missed words as flashcards")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.sumi.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        FlowLayout(spacing: 6) {
                            ForEach(missedKanjiTokens) { token in
                                Button {
                                    pendingSaveToken = SaveTokenRequest(token: token, context: sentence)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bookmark.fill")
                                            .font(.caption2)
                                        Text(token.prompt)
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
                }

                if !meaning.isEmpty {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionButton: some View {
        if feedback == nil {
            Button { submit() } label: {
                Text("Submit").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        } else if case .speech(_, let allCorrect, _) = feedback, !allCorrect {
            VStack(spacing: 8) {
                Button {
                    input = ""
                    feedback = nil
                    inputFocused = true
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())

                Button { dismiss() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(WashiButtonStyle())
            }
        } else {
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
        }
    }

    // MARK: - Logic

    private func submit() {
        guard feedback == nil else { return }
        if speech.isListening { speech.stop() }
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        let diff = computeDiff(transcript: answer)
        let normalizedAnswer = AnswerNormalizer.normalizeReading(answer)
        let normalizedExpected = AnswerNormalizer.normalizeReading(expectedReading)
        let exactMatch = !normalizedExpected.isEmpty
            && (normalizedAnswer == normalizedExpected
                || normalizedAnswer.contains(normalizedExpected)
                || normalizedExpected.contains(normalizedAnswer))
        let allMatched = !diff.isEmpty && diff.allSatisfy(\.matched)
        let allCorrect = exactMatch || allMatched

        let promptKanji = Set(sentence.filter { isKanji($0) })
        let solved = allCorrect ? Array(promptKanji.intersection(strugglingKanjiChars)).sorted() : []

        if allCorrect {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        feedback = .speech(
            diff: diff,
            allCorrect: allCorrect,
            solvedStrugglingKanji: solved
        )
    }

    private func computeDiff(transcript: String) -> [TokenDiff] {
        let normalisedTranscript = AnswerNormalizer.normalizeReading(transcript)
        let segments = JapaneseAnalysisService.shared.segments(sentence)
        var diff: [TokenDiff] = []
        for token in segments where token.hasKanji || (token.hasKana && token.surface.count >= 1) {
            let expected = AnswerNormalizer.normalizeReading(token.reading)
            guard !expected.isEmpty else { continue }
            let matched = normalisedTranscript.contains(expected)
            diff.append(TokenDiff(prompt: token.surface, expectedReading: expected, matched: matched))
        }
        return diff
    }

    private func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }
    }

    private func toggleListening() async {
        if !authChecked {
            _ = await speech.requestAuthorization()
            authChecked = true
        }
        if speech.isListening {
            speech.stop()
        } else {
            input = ""
            feedback = nil
            do { try speech.start() } catch {
                // Service exposes the error on its own publisher; the UI will
                // surface it through subsequent state once we add inline error
                // rendering. For now, the mic toggle simply doesn't engage.
            }
        }
    }
}

// MARK: - Normalization

private enum AnswerNormalizer {
    /// Strip okurigana markers (`.`, `-`), then convert any Latin runs to
    /// hiragana (CFStringTransform) and any katakana to hiragana so a single
    /// hiragana string matches typing "hito", "ヒト", or "ひと".
    static func normalizeReading(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.filter { $0 != "." && $0 != "-" }
        if s.isEmpty { return "" }

        if s.unicodeScalars.contains(where: { $0.isASCII && $0.value > 32 }) {
            let lowered = s.lowercased() as NSString
            let mutable = NSMutableString(string: lowered)
            CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
            s = mutable as String
        }

        var folded = ""
        for scalar in s.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let mapped = Unicode.Scalar(scalar.value - 0x60) {
                folded.unicodeScalars.append(mapped)
            } else {
                folded.unicodeScalars.append(scalar)
            }
        }
        s = folded

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
