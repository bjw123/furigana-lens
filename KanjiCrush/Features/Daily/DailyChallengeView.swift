import SwiftUI
import SwiftData

/// Once-per-day 5-question typed quiz pulled from the user's struggling
/// kanji + their JLPT-level vocabulary. Wrong answers requeue until correct;
/// completion writes a DailyChallengeLog and refreshes the streak.
struct DailyChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [Flashcard]
    @Query private var allLogs: [ReviewLog]
    @Query private var dailyLogs: [DailyChallengeLog]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0

    @State private var questions: [DailyQuestion] = []
    @State private var queue: [DailyQuestion] = []
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
        NavigationStack {
            ZStack {
                WashiBackground()
                if questions.isEmpty {
                    emptyView
                } else if let current = queue.first {
                    sessionCard(item: current)
                } else {
                    completeView
                }
            }
            .navigationTitle("Daily challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { prepareQuestions() }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.mist)
            Text("Nothing to drill yet")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.sumi)
            Text("Save some flashcards from a scan or set your JLPT level in Settings to seed today's challenge.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    @ViewBuilder
    private func sessionCard(item: DailyQuestion) -> some View {
        VStack(spacing: 18) {
            progressBar
            Text(item.prompt)
                .font(.system(size: 80, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.sumi)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Text("Type the reading")
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

            Spacer()

            actionButton(item: item)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(correctCount) / \(questions.count) correct")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                Spacer()
                Text("\(queue.count) left")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sakura)
            }
            ProgressView(
                value: Double(correctCount),
                total: Double(max(questions.count, 1))
            )
            .tint(Palette.sakura)
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
                    Text("Correct")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
                Text("Try again later")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
    private func actionButton(item: DailyQuestion) -> some View {
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
            Text("Today's challenge complete")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.sumi)
            Text("\(correctCount) of \(questions.count) right · \(attemptCount) attempt\(attemptCount == 1 ? "" : "s")")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.mist)
            Button("Done") { dismiss() }
                .buttonStyle(WashiButtonStyle())
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Logic

    private func prepareQuestions() {
        guard questions.isEmpty else { return }
        questions = DailyChallengePool.questions(
            cards: allCards,
            logs: allLogs,
            userJLPTLevel: jlptLevel,
            limit: 5
        )
        queue = questions
        inputFocused = true
    }

    private func submit(item: DailyQuestion) {
        guard feedback == nil else { return }
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        attemptCount += 1
        let normalized = JapaneseMatching.normalize(answer)
        let accepted = item.acceptedReadings
        let isMatch = accepted.contains { normalized == $0 || normalized.contains($0) || $0.contains(normalized) }

        if isMatch {
            correctCount += 1
            feedback = .correct(meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            feedback = .wrong(expected: item.readingDisplay, meaning: item.meaningDisplay)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func advance() {
        guard let current = queue.first else { return }
        switch feedback {
        case .correct:
            queue.removeFirst()
            // First time we drop to zero questions left, log completion.
            if queue.isEmpty {
                recordCompletion()
            }
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

    private func recordCompletion() {
        let today = DailyChallengeLog.todayKey()
        guard !dailyLogs.contains(where: { $0.day == today }) else { return }
        let log = DailyChallengeLog(
            day: today,
            correctCount: correctCount,
            totalCount: questions.count
        )
        modelContext.insert(log)
        try? modelContext.save()
    }
}

/// One typed question. Always reading-style for V1 — meaning quizzes get
/// taken care of by the per-kanji typed quiz from KanjiTypedReviewView.
struct DailyQuestion: Identifiable {
    let id = UUID()
    let prompt: String
    let acceptedReadings: [String]
    let readingDisplay: String
    let meaningDisplay: String
}

/// Builds the question pool. Priority order:
///   1. Cards the user has struggled with in the past 30 days
///   2. JLPT example words for kanji the user is struggling with
///   3. Random JLPT-level vocabulary the user hasn't seen yet
///   4. Random saved cards (filler)
enum DailyChallengePool {
    @MainActor
    static func questions(
        cards: [Flashcard],
        logs: [ReviewLog],
        userJLPTLevel: Int,
        limit: Int
    ) -> [DailyQuestion] {
        var seenPrompts = Set<String>()
        var out: [DailyQuestion] = []

        func add(prompt: String, reading: String, meaning: String) {
            let normalized = JapaneseMatching.normalize(reading)
            guard !normalized.isEmpty, !seenPrompts.contains(prompt) else { return }
            seenPrompts.insert(prompt)
            out.append(DailyQuestion(
                prompt: prompt,
                acceptedReadings: [normalized],
                readingDisplay: reading,
                meaningDisplay: meaning
            ))
        }

        // 1. Struggling cards
        for struggle in StatsService.strugglingCards(logs: logs, cards: cards, days: 30, limit: 8) {
            if out.count >= limit { return out }
            let meaning = struggle.card.meaning ?? ""
            add(prompt: struggle.card.expression, reading: struggle.card.reading, meaning: meaning)
        }

        // 2. JLPT examples for the user's struggling kanji
        for entry in StatsService.strugglingKanjiReadings(logs: logs, cards: cards, days: 30, limit: 4) {
            if out.count >= limit { return out }
            let examples = DictionaryService.shared.jlptExamples(forKanji: entry.kanji, perLevel: 2)
            for ex in examples {
                if out.count >= limit { return out }
                add(prompt: ex.form, reading: ex.reading, meaning: ex.gloss)
            }
        }

        // 3. Fall back to saved cards if we still need filler
        for card in cards.shuffled() {
            if out.count >= limit { return out }
            let meaning = card.meaning ?? ""
            add(prompt: card.expression, reading: card.reading, meaning: meaning)
        }

        return out
    }
}
