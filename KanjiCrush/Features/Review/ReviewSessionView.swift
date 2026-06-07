import SwiftUI
import SwiftData

/// A self-contained review session over a fixed queue of cards.
/// Used both by the normal Review tab (queue = due cards) and by deck Cram study
/// (queue = all cards in a deck, ignoring due dates).
struct ReviewSessionView: View {
    let queue: [Flashcard]
    let title: String
    var sessionKind: SessionKind = .review

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allCards: [Flashcard]
    @Query private var allLogs: [ReviewLog]
    @Query private var unlockedAchievements: [UnlockedAchievement]

    @State private var currentIndex = 0
    @State private var showBack = false
    @State private var seeMoreExpanded = false
    @State private var editingCard: Flashcard?
    @State private var comboCount: Int = 0
    @State private var comboBurstId: UUID?      // changes to trigger animation
    @State private var crushKanji: String?      // non-nil while crush animation runs
    @State private var achievementBanner: Achievement?
    @ObservedObject private var speech = SpeechService.shared

    enum SessionKind {
        case review   // applies SRS + writes a ReviewLog
        case cram     // doesn't mutate SRS; still writes a ReviewLog for stats
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                if currentIndex >= queue.count {
                    completeView
                } else {
                    sessionView
                }
                ComboOverlay(count: comboCount, triggerId: comboBurstId)
                    .allowsHitTesting(false)
                if let kanji = crushKanji {
                    CrushOverlay(kanji: kanji)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let achievement = achievementBanner {
                    AchievementBanner(achievement: achievement)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if currentIndex < queue.count {
                        Button {
                            editingCard = queue[currentIndex]
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                        .accessibilityLabel("Edit this card")
                    }
                }
            }
            .sheet(item: $editingCard) { card in
                NavigationStack {
                    CardEditView(card: card)
                        .navigationTitle("Edit card")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { editingCard = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Session

    private var sessionView: some View {
        let card = queue[currentIndex]
        return VStack(spacing: 16) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(currentIndex + 1) / \(queue.count)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    if sessionKind == .cram {
                        Text("Cram")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.sakura)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.sakura.opacity(0.12)))
                    }
                    Text(card.cardType.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                }
                ProgressView(value: Double(currentIndex), total: Double(max(queue.count, 1)))
                    .tint(Palette.sakura)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            ScrollView {
                VStack(spacing: 18) {
                    front(for: card)
                    if showBack {
                        BrushDivider().frame(width: 120)
                        back(for: card)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        seeMoreSection(for: card)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Palette.washi,
                                    Color(
                                        light: UIColor(red: 0.992, green: 0.974, blue: 0.945, alpha: 1.0),
                                        dark:  UIColor(red: 0.135, green: 0.118, blue: 0.100, alpha: 1.0)
                                    )
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                // Subtle sakura wash from the bottom when the answer is
                // revealed, so the reveal-state feels distinct from front-only.
                .overlay(
                    Group {
                        if showBack {
                            LinearGradient(
                                colors: [Color.clear, Palette.sakura.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .allowsHitTesting(false)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.75)
                )
                // Inner top highlight — gives the card a subtle "lifted" edge.
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .blur(radius: 0.5)
                        .mask(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(lineWidth: 2)
                                .padding(.bottom, 44)
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: Palette.sumi.opacity(0.10), radius: 18, x: 0, y: 10)
                .shadow(color: Palette.sumi.opacity(0.04), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            Spacer()

            if !showBack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showBack = true }
                } label: {
                    Label("Show answer", systemImage: "eye.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                gradeButtons(for: card)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func front(for card: Flashcard) -> some View {
        VStack(spacing: 14) {
            if let hint = card.hint, !hint.isEmpty {
                hintBanner(hint: hint)
            }
            switch card.cardType {
            case .word:
                VStack(spacing: 14) {
                    Text(card.expression)
                        .font(.system(size: 56, weight: .medium, design: .serif))
                        .foregroundStyle(Palette.sumi)
                        .multilineTextAlignment(.center)
                    if let sentence = frontExampleSentence(for: card) {
                        WordCardExampleSentence(sentence: sentence, highlightSurface: card.expression)
                            .padding(.horizontal, 8)
                    }
                }
            case .sentence:
                Text(card.expression)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }
        }
    }

    private func hintBanner(hint: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.gold)
            Text(hint)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.gold)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.gold.opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.gold.opacity(0.35), lineWidth: 0.75)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func back(for card: Flashcard) -> some View {
        switch card.cardType {
        case .word:
            let displayReading = backReading(for: card)
            VStack(spacing: 14) {
                FuriganaWordView(expression: card.expression, reading: displayReading, fontSize: 48)
                if !displayReading.isEmpty && displayReading != card.expression {
                    Text(displayReading)
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .foregroundStyle(Palette.indigo)
                        .multilineTextAlignment(.center)
                }
                if let meaning = card.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                audioButton(for: displayReading.isEmpty ? card.expression : displayReading)
                if let sentence = frontExampleSentence(for: card) {
                    contextSentenceBlock(sentence: sentence)
                }
            }
        case .sentence:
            VStack(spacing: 12) {
                FuriganaSentenceView(sentence: card.expression, fontSize: 22)
                if let meaning = card.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                audioButton(for: card.expression)
                sentenceBreakdown(for: card)
            }
        }
    }

    /// Captured / example sentence shown on the back of a word card with full
    /// per-token furigana, so the learner sees the target word in its real
    /// context with the readings of the surrounding kanji also revealed.
    private func contextSentenceBlock(sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In context")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            FuriganaSentenceView(sentence: sentence, fontSize: 17, textAlignment: .left)
                .frame(maxWidth: .infinity, alignment: .leading)
            audioButton(for: sentence)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }

    /// Inline per-token breakdown shown on the back of a sentence card. Each
    /// kanji-containing token is rendered as a chip with surface, reading, and
    /// (when JMdict has an entry) a short gloss.
    @ViewBuilder
    private func sentenceBreakdown(for card: Flashcard) -> some View {
        let tokens = JapaneseAnalysisService.shared.segments(card.expression)
            .filter { $0.hasKanji || ($0.hasKana && $0.surface.count >= 2) }
        if !tokens.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Word breakdown")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    ForEach(tokens) { token in
                        sentenceBreakdownRow(token: token)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func sentenceBreakdownRow(token: JapaneseToken) -> some View {
        let gloss = DictionaryService.shared
            .lookup(token.surface, limit: 1)
            .first?
            .glosses()
            .joined(separator: "; ")
        let showReading = token.hasKanji && !token.reading.isEmpty && token.reading != token.surface
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                if showReading {
                    Text(token.reading)
                        .font(.system(size: 10, design: .rounded).weight(.medium))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
                Text(token.surface)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Palette.sumi)
            }
            .frame(minWidth: 70, alignment: .leading)
            if let gloss, !gloss.isEmpty {
                Text(gloss)
                    .font(.caption)
                    .foregroundStyle(Palette.sumi.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }

    /// Reading to render as furigana on the back of a word card.
    /// `card.reading` is preferred, but legacy or hand-saved cards sometimes
    /// have an empty reading or one that mirrors the expression — in those
    /// cases fall back to a locally synthesized reading so the back still
    /// teaches the kana.
    private func backReading(for card: Flashcard) -> String {
        let trimmed = card.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != card.expression {
            return trimmed
        }
        return JapaneseAnalysisService.shared.localReading(for: card.expression)
    }

    /// Front of a word card shows an example sentence under the kanji.
    /// Prefer the OCR context the card was saved with; fall back to a JMdict
    /// example so the front still has something to read.
    private func frontExampleSentence(for card: Flashcard) -> String? {
        if let ctx = card.contextSentence?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ctx.isEmpty,
           ctx != card.expression {
            return ctx
        }
        return DictionaryService.shared.examples(for: [card.expression], limit: 1).first?.japanese
    }

    private func audioButton(for text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActive = speech.isSpeaking(trimmed)
        return Button {
            if isActive {
                speech.stop()
            } else {
                speech.speak(trimmed)
            }
        } label: {
            Label(isActive ? "Stop" : "Play audio", systemImage: isActive ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                .foregroundStyle(Palette.indigo)
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
        .opacity(trimmed.isEmpty ? 0.4 : 1.0)
    }

    private struct SeeMoreData {
        let extraGlosses: [String]
        let examples: [ExampleSentence]
        var hasExtraMeaning: Bool { !extraGlosses.isEmpty }
        var hasExamples: Bool { !examples.isEmpty }
        var hasContent: Bool { hasExtraMeaning || hasExamples }
    }

    private func seeMoreData(for card: Flashcard) -> SeeMoreData {
        let entries = DictionaryService.shared.lookup(card.expression, limit: 2)
        // Only surface extra glosses when they add something beyond the meaning
        // already shown on the back. Same joined string → suppress as duplicate.
        let candidateGlosses = entries.first.map { $0.glosses() } ?? []
        let savedMeaning = card.meaning?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let extraGlosses = candidateGlosses.joined(separator: "; ") == savedMeaning
            ? []
            : candidateGlosses
        let kanjiForms = entries.flatMap { $0.kanji }
        let kanaForms = entries.flatMap { $0.kana }
        let headwords = ([card.expression] + kanjiForms + kanaForms).filter { !$0.isEmpty }
        let examples = headwords.isEmpty
            ? []
            : DictionaryService.shared.examples(for: headwords, limit: 2)
        return SeeMoreData(extraGlosses: extraGlosses, examples: examples)
    }

    @ViewBuilder
    private func seeMoreSection(for card: Flashcard) -> some View {
        // Sentence cards already show the per-token breakdown inline on the
        // back; the JMdict-driven see-more block isn't meaningful for them.
        if card.cardType == .word {
            let data = seeMoreData(for: card)
            if data.hasContent {
                seeMoreToggle
                if seeMoreExpanded {
                    seeMoreExpandedContent(data: data)
                }
            }
        }
    }

    private var seeMoreToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                seeMoreExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: seeMoreExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                Text(seeMoreExpanded ? "Hide details" : "See more")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(Palette.indigo)
            .background(Capsule().fill(Palette.indigo.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func seeMoreExpandedContent(data: SeeMoreData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if data.hasExtraMeaning {
                meaningBlock(glosses: data.extraGlosses)
            }
            if data.hasExamples {
                examplesBlock(examples: data.examples)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func meaningBlock(glosses: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meaning")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(glosses.joined(separator: "; "))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.sumi.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func examplesBlock(examples: [ExampleSentence]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
            ForEach(examples, id: \.self) { ex in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.japanese)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Palette.sumi)
                    Text(ex.english)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func gradeButtons(for card: Flashcard) -> some View {
        HStack(spacing: 8) {
            ForEach(ReviewGrade.allCases, id: \.rawValue) { grade in
                Button {
                    apply(grade, to: card)
                } label: {
                    Text(grade.label)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionGradeButtonStyle(tint: tint(for: grade)))
            }
        }
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Palette.vermillion
        case .hard: return Palette.gold
        case .good: return Palette.bamboo
        case .easy: return Palette.indigo
        }
    }

    private var completeView: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Palette.sakura.opacity(0.20))
                    .frame(width: 132, height: 132)
                MapleGlyph(size: 78)
            }
            VStack(spacing: 6) {
                Text("お疲れさま")
                    .font(.system(.title2, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.sumi)
                Text("Session complete — nice work.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.mist)
            }
            Button("Done") { dismiss() }
                .buttonStyle(WashiButtonStyle())
                .padding(.top, 4)
            Spacer()
        }
    }

    // MARK: - Actions

    private func apply(_ grade: ReviewGrade, to card: Flashcard) {
        // Capture maturity *before* applying so we can detect a learning →
        // mature transition and fire the crush effect.
        let wasMature = card.repetitions >= 3 && card.interval >= 21

        if sessionKind == .review {
            SRSService.shared.applyReview(to: card, grade: grade)
        }
        let log = ReviewLog(flashcardId: card.id, quality: grade.rawValue)
        modelContext.insert(log)
        try? modelContext.save()

        let isMature = card.repetitions >= 3 && card.interval >= 21
        let graduated = !wasMature && isMature
        let crushChar = graduated ? String(card.expression.first ?? Character(" ")) : nil

        // Combo bookkeeping: Good (3) / Easy (4) extend the streak; Again /
        // Hard reset it. Only fire the burst on extensions of length ≥ 2.
        if grade.rawValue >= 3 {
            comboCount += 1
            AchievementService.recordCombo(comboCount)
            if comboCount >= 2 {
                comboBurstId = UUID()
            }
        } else {
            comboCount = 0
        }

        if let crushChar {
            crushKanji = crushChar
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                crushKanji = nil
            }
        }

        // Check for newly-unlocked achievements after this grade has been
        // logged. Show the first one as a banner; subsequent unlocks in the
        // same tick still get stored, just not bannered.
        let streak = StatsService.currentStreak(logs: allLogs)
        let newlyUnlocked = AchievementService.evaluate(
            modelContext: modelContext,
            cards: allCards,
            reviewLogs: allLogs,
            unlocked: unlockedAchievements,
            streak: streak
        )
        if let first = newlyUnlocked.first {
            achievementBanner = first
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    achievementBanner = nil
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            showBack = false
            seeMoreExpanded = false
            currentIndex += 1
        }
    }
}

/// Example sentence shown on the front of a Word card. Every kanji-containing
/// token can be tapped to toggle inline furigana, and the token matching the
/// card's target word is highlighted so the learner sees it in context.
private struct WordCardExampleSentence: View {
    let sentence: String
    let highlightSurface: String

    @State private var revealedTokenIds: Set<UUID> = []
    @State private var segments: [JapaneseToken]

    init(sentence: String, highlightSurface: String) {
        self.sentence = sentence
        self.highlightSurface = highlightSurface
        _segments = State(initialValue: JapaneseAnalysisService.shared.segments(sentence))
    }

    var body: some View {
        FlowLayout(spacing: 1) {
            ForEach(segments) { token in
                tokenView(for: token)
            }
        }
    }

    @ViewBuilder
    private func tokenView(for token: JapaneseToken) -> some View {
        let isTarget = token.surface == highlightSurface
        if token.hasKanji {
            // The target word's reading is the thing the learner is trying to
            // recall — never reveal it on the front, even via tap.
            let revealed = !isTarget && revealedTokenIds.contains(token.id)
            Button {
                guard !isTarget else { return }
                toggle(token.id)
            } label: {
                tokenLabel(token: token, revealed: revealed, isTarget: isTarget)
            }
            .buttonStyle(.plain)
            .disabled(isTarget)
        } else {
            Text(token.surface)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Palette.sumi.opacity(0.7))
        }
    }

    @ViewBuilder
    private func tokenLabel(token: JapaneseToken, revealed: Bool, isTarget: Bool) -> some View {
        let showReading = revealed && !token.reading.isEmpty && token.reading != token.surface
        VStack(spacing: 0) {
            if showReading {
                Text(token.reading)
                    .font(.system(size: 9, design: .rounded).weight(.medium))
                    .foregroundStyle(Palette.indigo.opacity(0.85))
            }
            Text(token.surface)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(isTarget ? Palette.sakura : Palette.sumi.opacity(0.85))
                .underline(!revealed && !isTarget, pattern: .dot)
        }
        .padding(.horizontal, isTarget ? 4 : 0)
        .padding(.vertical, isTarget ? 1 : 0)
        .background(
            isTarget
                ? Capsule().fill(Palette.sakura.opacity(0.18))
                : Capsule().fill(Color.clear)
        )
        .fixedSize()
    }

    private func toggle(_ id: UUID) {
        if revealedTokenIds.contains(id) {
            revealedTokenIds.remove(id)
        } else {
            revealedTokenIds.insert(id)
        }
    }
}

private struct SessionGradeButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 0.75)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Gamification overlays

/// Transient "Combo ×N" pill that animates in from the top and fades out.
/// `triggerId` changes (via a new UUID) each time we want to re-run the
/// animation — the `.id(...)` modifier on the inner view forces SwiftUI to
/// remount it so the transition replays even for the same count.
private struct ComboOverlay: View {
    let count: Int
    let triggerId: UUID?

    @State private var visible = false

    var body: some View {
        VStack {
            if let triggerId, count >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Combo ×\(count)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
                .foregroundStyle(Palette.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.sakura))
                .overlay(Capsule().strokeBorder(Palette.cream.opacity(0.4), lineWidth: 1))
                .shadow(color: Palette.sakura.opacity(0.5), radius: 12, y: 4)
                .id(triggerId)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .onAppear {
                    visible = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeOut(duration: 0.3)) { visible = false }
                    }
                }
                .opacity(visible ? 1 : 0)
            }
            Spacer()
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: triggerId)
    }
}

/// "Crush" effect when a card graduates from learning → mature: the kanji
/// blooms outward from the centre with a burst of sakura petals scattering,
/// then fades. Lives ~0.9s.
private struct CrushOverlay: View {
    let kanji: String

    @State private var hero = false
    @State private var burst = false

    var body: some View {
        ZStack {
            Color.black.opacity(hero ? 0.10 : 0.0)
                .ignoresSafeArea()

            Text(kanji)
                .font(.system(size: 220, weight: .heavy, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Palette.sakura, Color(red: 0.870, green: 0.486, blue: 0.580)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Palette.sakura.opacity(0.6), radius: 24)
                .scaleEffect(hero ? 1.0 : 0.4)
                .opacity(hero ? 0.95 : 0.0)

            // Scattered sakura petals
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10.0 * 2 * .pi
                let radius: CGFloat = burst ? 220 : 0
                Circle()
                    .fill(Palette.sakura)
                    .frame(width: 14, height: 14)
                    .offset(
                        x: cos(angle) * Double(radius),
                        y: sin(angle) * Double(radius)
                    )
                    .opacity(burst ? 0.0 : 0.9)
                    .scaleEffect(burst ? 0.5 : 1.0)
            }

            VStack {
                Spacer()
                Text("MATURE!")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Palette.cream)
                    .tracking(2.0)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.indigo))
                    .shadow(color: Palette.indigo.opacity(0.5), radius: 12, y: 6)
                    .opacity(hero ? 1 : 0)
                    .scaleEffect(hero ? 1.0 : 0.7)
                    .padding(.bottom, 120)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                hero = true
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.05)) {
                burst = true
            }
        }
    }
}

/// Banner shown when a new achievement is unlocked during a review.
/// Appears at the top, lingers for ~2s, then dismisses itself.
private struct AchievementBanner: View {
    let achievement: Achievement

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Palette.gold.opacity(0.20))
                        .frame(width: 44, height: 44)
                    Image(systemName: achievement.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.gold)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Achievement unlocked")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(achievement.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.sumi)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Palette.sumi.opacity(0.20), radius: 16, y: 8)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer()
        }
    }
}
