import SwiftUI
import SwiftData

/// Type-the-answer review session for a single kanji and its associated JLPT
/// vocabulary. The user picks Reading or Meaning mode on entry, then types
/// each answer. Wrong attempts re-queue at the back of the deck and only
/// leave the session once the learner gets them right — same idea as SRS
/// `Again`, but scoped to one sitting.
struct KanjiTypedReviewView: View {
    let kanji: Character
    let info: KanjiInfo?
    let examples: [JLPTWordExample]

    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case reading, meaning, speech
        var id: String { rawValue }
        var label: String {
            switch self {
            case .reading: return "Reading"
            case .meaning: return "Meaning"
            case .speech:  return "Speak"
            }
        }
        var prompt: String {
            switch self {
            case .reading: return "Type the reading"
            case .meaning: return "Type the meaning"
            case .speech:  return "Read aloud, then correct any typos"
            }
        }
    }

    @State private var mode: Mode?

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                if let mode {
                    SessionRunner(kanji: kanji, info: info, examples: examples, mode: mode) {
                        dismiss()
                    }
                } else {
                    modePickerView
                }
            }
            .navigationTitle(mode == nil ? "Quiz" : "Quiz · \(String(kanji))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var modePickerView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(String(kanji))
                .font(.system(size: 128, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.sumi)
            Text("Pick what you want to test")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.mist)
            VStack(spacing: 12) {
                ForEach(Mode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(.headline, design: .rounded).weight(.semibold))
                                Text(subtitle(for: option))
                                    .font(.caption)
                                    .foregroundStyle(Palette.mist)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.mist)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private func subtitle(for option: Mode) -> String {
        switch option {
        case .reading: return "Type ひらがな or romaji"
        case .meaning: return "Type the English meaning"
        case .speech:  return "Speak the reading — the app transcribes it"
        }
    }
}

// MARK: - Session

private struct SessionRunner: View {
    let kanji: Character
    let info: KanjiInfo?
    let examples: [JLPTWordExample]
    let mode: KanjiTypedReviewView.Mode
    let onFinish: () -> Void

    @State private var queue: [TypedReviewItem] = []
    @State private var input: String = ""
    @State private var feedback: Feedback?
    @State private var correctCount: Int = 0
    @State private var attemptCount: Int = 0
    @FocusState private var inputFocused: Bool
    @StateObject private var speech = SpeechRecognitionService()
    @State private var authChecked = false
    @State private var pendingSaveToken: SaveTokenRequest?

    @Query private var allCards: [Flashcard]
    @Query private var allLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    private var strugglingKanjiChars: Set<Character> {
        Set(StatsService.strugglingKanjiReadings(logs: allLogs, cards: allCards, days: 30, limit: 32).map(\.kanji))
    }

    enum Feedback {
        case correct(meaning: String)
        case wrong(expected: String, meaning: String)
        /// Speech-mode rich feedback: lists per-token matches and missed.
        case speech(diff: [TokenDiff], meaning: String, allCorrect: Bool, solvedStrugglingKanji: [Character])
    }

    fileprivate struct TokenDiff: Identifiable {
        let id = UUID()
        let prompt: String        // e.g. "見"
        let expectedReading: String  // normalised hiragana
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
        let context: String  // the original item.prompt as context sentence
    }

    var body: some View {
        VStack(spacing: 16) {
            progressBar
            if let current = queue.first {
                sessionCard(item: current)
            } else {
                completeView
            }
        }
        .padding(.vertical, 12)
        .onAppear {
            if queue.isEmpty {
                queue = TypedReviewItem.build(
                    kanji: kanji,
                    info: info,
                    examples: examples
                )
                inputFocused = true
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

    private var progressBar: some View {
        let total = max(attemptCount + queue.count, 1)
        return VStack(spacing: 4) {
            HStack {
                Text("\(correctCount) correct · \(queue.count) left")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                Spacer()
                Text(mode.label.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.indigo.opacity(0.12)))
            }
            ProgressView(value: Double(correctCount), total: Double(total))
                .tint(Palette.sakura)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func sessionCard(item: TypedReviewItem) -> some View {
        VStack(spacing: 18) {
            Text(item.prompt)
                .font(.system(size: 72, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.sumi)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            if mode == .meaning, !item.readingDisplay.isEmpty {
                Text(item.readingDisplay)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Palette.indigo.opacity(0.85))
            }

            Text(mode.prompt)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)

            if mode == .speech {
                HStack {
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

            TextField("Answer", text: $input)
                .focused($inputFocused)
                .submitLabel(.go)
                .onSubmit { submit(item: item) }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.title2, design: .rounded))
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

            if mode == .speech {
                Text("Edit the transcript above if needed, then Submit")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Palette.mist)
            }

            feedbackView

            Spacer(minLength: 12)

            actionButton(item: item)
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .padding(.horizontal)
    }

    private var strokeColor: Color {
        switch feedback {
        case .correct: return Palette.bamboo.opacity(0.85)
        case .wrong: return Palette.vermillion.opacity(0.85)
        case .speech(_, _, let allCorrect, _):
            return allCorrect ? Palette.bamboo.opacity(0.85) : Palette.vermillion.opacity(0.85)
        case nil: return Palette.hairline
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        switch feedback {
        case .correct(let meaning):
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Correct").font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.bamboo)
                if !meaning.isEmpty {
                    Text(meaning)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        case .wrong(let expected, let meaning):
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Try again later").font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)
                Text("Expected: \(expected)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.sumi)
                if !meaning.isEmpty {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        case .speech(let diff, let meaning, let allCorrect, let solvedStrugglingKanji):
            speechFeedback(
                diff: diff,
                meaning: meaning,
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
        meaning: String,
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
                                    if let item = queue.first {
                                        pendingSaveToken = SaveTokenRequest(token: token, context: item.prompt)
                                    }
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

    @ViewBuilder
    private func actionButton(item: TypedReviewItem) -> some View {
        if feedback == nil {
            Button { submit(item: item) } label: {
                Text("Submit").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        } else if case .speech(_, _, let allCorrect, _) = feedback, !allCorrect {
            VStack(spacing: 8) {
                Button {
                    input = ""
                    feedback = nil
                    inputFocused = true
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())

                Button { advance() } label: {
                    Text("Move on").frame(maxWidth: .infinity)
                }
                .buttonStyle(WashiButtonStyle())
            }
        } else {
            Button { advance() } label: {
                Text(queue.count > 1 ? "Next" : "Finish").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
        }
    }

    private var completeView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(Palette.sakura.opacity(0.20)).frame(width: 120, height: 120)
                MapleGlyph(size: 64)
            }
            VStack(spacing: 4) {
                Text("お疲れさま")
                    .font(.system(.title2, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.sumi)
                Text("\(correctCount) correct in \(attemptCount) attempt\(attemptCount == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.mist)
            }
            Button("Done") { onFinish() }
                .buttonStyle(WashiButtonStyle())
                .padding(.top, 6)
            Spacer()
        }
    }

    // MARK: Actions

    private func submit(item: TypedReviewItem) {
        guard feedback == nil else { return }
        if mode == .speech, speech.isListening { speech.stop() }
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        attemptCount += 1
        let normalized = AnswerNormalizer.normalize(answer, mode: mode)
        let accepted = mode == .meaning ? item.acceptedMeanings : item.acceptedReadings
        let isMatch = accepted.contains { normalized == $0 || normalized.contains($0) || $0.contains(normalized) }

        if mode == .speech {
            let diff = computeDiff(item: item, transcript: answer)
            let allMatched = !diff.isEmpty && diff.allSatisfy(\.matched)
            let allCorrect = isMatch || allMatched

            let promptKanji = Set(item.prompt.filter { isKanji($0) })
            let solved = allCorrect ? Array(promptKanji.intersection(strugglingKanjiChars)).sorted() : []

            if allCorrect {
                correctCount += 1
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            feedback = .speech(
                diff: diff,
                meaning: item.meaningDisplay,
                allCorrect: allCorrect,
                solvedStrugglingKanji: solved
            )
            return
        }

        if isMatch {
            correctCount += 1
            feedback = .correct(meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            let expected = mode == .meaning ? item.meaningDisplay : item.readingDisplay
            feedback = .wrong(expected: expected, meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func computeDiff(item: TypedReviewItem, transcript: String) -> [TokenDiff] {
        let normalisedTranscript = JapaneseMatching.normalize(transcript)
        let segments = JapaneseAnalysisService.shared.segments(item.prompt)
        var diff: [TokenDiff] = []
        for token in segments where token.hasKanji || (token.hasKana && token.surface.count >= 1) {
            let dictEntries = DictionaryService.shared.lookup(token.surface, limit: 3)
            let candidates = JapaneseMatching.candidates(
                forExpression: token.surface,
                tokenReading: token.reading,
                jmdictEntries: dictEntries
            )
            guard !candidates.isEmpty else { continue }
            // Bidirectional containment so the transcript matches whether it's
            // narrower or wider than the candidate.
            let matched = candidates.contains { cand in
                normalisedTranscript == cand
                    || normalisedTranscript.contains(cand)
                    || cand.contains(normalisedTranscript)
            }
            let displayReading = JapaneseMatching.normalize(token.reading)
            diff.append(TokenDiff(prompt: token.surface, expectedReading: displayReading, matched: matched))
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
            // Per-kanji speech reads are one-shot — flip the recognizer out of
            // continuous mode so a silence pause cleanly ends the recording
            // instead of restarting the task.
            speech.continuousMode = false
            do { try speech.start() } catch {
                // Service exposes error; UI shows it via the existing feedback path.
            }
        }
    }

    private func advance() {
        guard let current = queue.first else { return }
        switch feedback {
        case .correct:
            queue.removeFirst()
        case .wrong:
            queue.removeFirst()
            queue.append(current)
        case .speech(_, _, let allCorrect, _):
            queue.removeFirst()
            if !allCorrect { queue.append(current) }
        case nil:
            return
        }
        input = ""
        feedback = nil
        inputFocused = true
    }
}

// MARK: - Items

private struct TypedReviewItem: Identifiable {
    let id = UUID()
    let prompt: String
    /// Normalized hiragana strings considered correct readings.
    let acceptedReadings: [String]
    /// Normalized lowercase strings considered correct meanings.
    let acceptedMeanings: [String]
    /// Pretty reading to display when the user gets it right (or runs out of guesses).
    let readingDisplay: String
    /// Pretty meaning to display when the user gets it right.
    let meaningDisplay: String

    var meaningSuffix: String { meaningDisplay }

    static func build(
        kanji: Character,
        info: KanjiInfo?,
        examples: [JLPTWordExample]
    ) -> [TypedReviewItem] {
        var items: [TypedReviewItem] = []
        let kanjiMeaning = (info?.meanings.prefix(3).joined(separator: "; ")) ?? ""
        let kanjiMeaningsNormalized = AnswerNormalizer.normalizeMeanings(info?.meanings ?? [])

        // One item per distinct on/kun reading — lets the learner be drilled
        // on each reading independently.
        for raw in (info?.on ?? []) + (info?.kun ?? []) {
            let normalized = JapaneseMatching.normalize(raw)
            if normalized.isEmpty { continue }
            items.append(TypedReviewItem(
                prompt: String(kanji),
                acceptedReadings: [normalized],
                acceptedMeanings: kanjiMeaningsNormalized,
                readingDisplay: raw,
                meaningDisplay: kanjiMeaning
            ))
        }

        // Then JLPT-tagged words containing the kanji.
        for ex in examples {
            let readingNormalized = JapaneseMatching.normalize(ex.reading)
            let glossParts = ex.gloss
                .split(whereSeparator: { ";,".contains($0) })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            items.append(TypedReviewItem(
                prompt: ex.form,
                acceptedReadings: readingNormalized.isEmpty ? [] : [readingNormalized],
                acceptedMeanings: AnswerNormalizer.normalizeMeanings(glossParts),
                readingDisplay: ex.reading,
                meaningDisplay: ex.gloss
            ))
        }

        // Drop unanswerable items (no accepted readings/meanings) and shuffle.
        return items
            .filter { !($0.acceptedReadings.isEmpty && $0.acceptedMeanings.isEmpty) }
            .shuffled()
    }
}

// MARK: - Normalization

private enum AnswerNormalizer {
    static func normalize(_ raw: String, mode: KanjiTypedReviewView.Mode) -> String {
        switch mode {
        case .reading, .speech: return JapaneseMatching.normalize(raw)
        case .meaning:          return normalizeMeaning(raw)
        }
    }

    static func normalizeMeaning(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["a ", "an ", "the ", "to "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        s = s.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        return s
    }

    static func normalizeMeanings(_ list: [String]) -> [String] {
        list
            .flatMap { $0.split(whereSeparator: { ";,".contains($0) }) }
            .map { normalizeMeaning(String($0)) }
            .filter { !$0.isEmpty }
    }
}
