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

    @State private var currentIndex = 0
    @State private var showBack = false

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
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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

            VStack(spacing: 18) {
                front(for: card)
                if showBack {
                    BrushDivider().frame(width: 120)
                    back(for: card)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 20)
            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
            .shadow(color: Palette.sumi.opacity(0.08), radius: 14, y: 6)
            .padding(.horizontal)

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
        switch card.cardType {
        case .reading:
            Text(card.expression)
                .font(.system(size: 56, weight: .medium, design: .serif))
                .foregroundStyle(Palette.sumi)
                .multilineTextAlignment(.center)
        case .meaning:
            FuriganaWordView(expression: card.expression, reading: card.reading, fontSize: 48)
        case .sentence:
            Text(card.contextSentence ?? card.expression)
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Palette.sumi)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func back(for card: Flashcard) -> some View {
        switch card.cardType {
        case .reading:
            Text(card.reading)
                .font(.system(.title, design: .rounded))
                .foregroundStyle(Palette.indigo)
        case .meaning:
            Text(card.meaning ?? "No meaning saved")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Palette.sumi.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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
        if sessionKind == .review {
            SRSService.shared.applyReview(to: card, grade: grade)
        }
        let log = ReviewLog(flashcardId: card.id, quality: grade.rawValue)
        modelContext.insert(log)
        try? modelContext.save()

        withAnimation(.easeInOut(duration: 0.15)) {
            showBack = false
            currentIndex += 1
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
