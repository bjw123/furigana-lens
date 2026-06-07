import SwiftUI

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
        case reading, meaning
        var id: String { rawValue }
        var label: String {
            switch self {
            case .reading: return "Reading"
            case .meaning: return "Meaning"
            }
        }
        var prompt: String {
            switch self {
            case .reading: return "Type the reading"
            case .meaning: return "Type the meaning"
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
            .navigationTitle(mode == nil ? "Typed review" : "Review · \(String(kanji))")
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
                                Text(option == .reading
                                     ? "Type ひらがな or romaji"
                                     : "Type the English meaning")
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

    enum Feedback {
        case correct(meaning: String)
        case wrong(expected: String, meaning: String)
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
        case nil:
            EmptyView()
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
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        attemptCount += 1
        let normalized = AnswerNormalizer.normalize(answer, mode: mode)
        let accepted = mode == .reading ? item.acceptedReadings : item.acceptedMeanings
        let isMatch = accepted.contains { normalized == $0 || normalized.contains($0) || $0.contains(normalized) }

        if isMatch {
            correctCount += 1
            feedback = .correct(meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            let expected = mode == .reading ? item.readingDisplay : item.meaningDisplay
            feedback = .wrong(expected: expected, meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
            let normalized = AnswerNormalizer.normalizeReading(raw)
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
            let readingNormalized = AnswerNormalizer.normalizeReading(ex.reading)
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
        case .reading: return normalizeReading(raw)
        case .meaning: return normalizeMeaning(raw)
        }
    }

    /// Strip okurigana markers (`.`, `-`), then convert any Latin runs to
    /// hiragana (CFStringTransform) and any katakana to hiragana so a single
    /// hiragana string matches typing "hito", "ヒト", or "ひと".
    static func normalizeReading(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.filter { $0 != "." && $0 != "-" }
        if s.isEmpty { return "" }

        // Romaji → hiragana via Apple's transliteration.
        if s.unicodeScalars.contains(where: { $0.isASCII && $0.value > 32 }) {
            let lowered = s.lowercased() as NSString
            let mutable = NSMutableString(string: lowered)
            CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
            s = mutable as String
        }

        // Katakana → hiragana.
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

    static func normalizeMeaning(_ raw: String) -> String {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["a ", "an ", "the ", "to "] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        // Strip surrounding punctuation/quotes; keep internal spaces.
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
