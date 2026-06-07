import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var modelContext
    @Query private var reviewLogs: [ReviewLog]
    @Query private var knownWords: [KnownWord]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0

    @State private var cramQueue: [Flashcard]?
    @State private var showDeleteConfirm = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?

    private var stats: StatsService.DeckStats {
        StatsService.deckStats(deck: deck, logs: reviewLogs)
    }

    var body: some View {
        ZStack {
            WashiBackground()

            ScrollView {
                VStack(spacing: 16) {
                    statsCard
                    actionsCard
                    infoCard
                    cardsCard
                    Spacer(minLength: 24)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? modelContext.save() }
        .fullScreenCover(
            isPresented: Binding(
                get: { cramQueue != nil },
                set: { if !$0 { cramQueue = nil } }
            )
        ) {
            if let queue = cramQueue {
                ReviewSessionView(
                    queue: queue,
                    title: "Cram · \(deck.name)",
                    sessionKind: .cram
                )
            }
        }
        .confirmationDialog(
            "Delete this deck?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(deck.cards.count) card\(deck.cards.count == 1 ? "" : "s")", role: .destructive) {
                modelContext.delete(deck)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the deck and all of its cards. Reviews you've logged stay in your history.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Export failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    /// Serialise the deck to a `.kcdeck` JSON file in tmp, then surface the
    /// system Share sheet so the user can AirDrop / Files / Mail it.
    private func prepareExport() {
        do {
            let data = try DeckExportService.export(deck: deck)
            let filename = DeckExportService.suggestedFilename(for: deck)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Anki TSV variant. Anki's docs say `.txt` is the canonical extension
    /// for the importer, so we use that and let the Share sheet stash it
    /// wherever the user wants.
    private func prepareAnkiExport() {
        do {
            let data = DeckExportService.exportAnkiTSV(deck: deck)
            let filename = DeckExportService.suggestedAnkiFilename(for: deck)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Cards

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Overview",
                trailing: stats.successRate.map { "\(Int(($0 * 100).rounded()))% success" } ?? "no reviews yet"
            )
            BrushDivider()

            HStack(spacing: 10) {
                statTile(label: "Total", value: "\(stats.total)", tint: Palette.indigo)
                statTile(label: "Due", value: "\(stats.dueNow)", tint: stats.dueNow > 0 ? Palette.sakura : Palette.mist)
            }

            HStack(spacing: 10) {
                miniTile(label: "New", value: stats.new, tint: Palette.indigo)
                miniTile(label: "Learning", value: stats.learning, tint: Palette.gold)
                miniTile(label: "Mature", value: stats.mature, tint: Palette.bamboo)
            }

            if stats.reviewCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundStyle(Palette.mist)
                    Text("\(stats.reviewCount) reviews · \(stats.againCount) again")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
                .padding(.top, 2)
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func statTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }

    private func miniTile(label: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Palette.mist)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 0.5)
        )
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            actionRow(
                title: deck.isExcludedFromReviews ? "Include in reviews" : "Pause from reviews",
                subtitle: deck.isExcludedFromReviews
                    ? "Cards from this deck will appear in your due queue again."
                    : "Hide this deck's cards from the due queue without deleting them.",
                icon: deck.isExcludedFromReviews ? "play.circle.fill" : "pause.circle.fill",
                tint: deck.isExcludedFromReviews ? Palette.bamboo : Palette.gold
            ) {
                deck.isExcludedFromReviews.toggle()
                try? modelContext.save()
            }

            Divider().overlay(Palette.hairline)

            actionRow(
                title: "Cram study",
                subtitle: deck.cards.isEmpty
                    ? "Add some cards first."
                    : "Run through every card in this deck (no SRS changes).",
                icon: "flame.fill",
                tint: Palette.sakura,
                disabled: deck.cards.isEmpty
            ) {
                cramQueue = deck.cards.shuffled()
            }

            Divider().overlay(Palette.hairline)

            actionRow(
                title: "Export deck",
                subtitle: "Share as a .kcdeck file — friends with Kanji Crush can import it.",
                icon: "square.and.arrow.up.fill",
                tint: Palette.indigo,
                disabled: deck.cards.isEmpty
            ) {
                prepareExport()
            }

            Divider().overlay(Palette.hairline)

            actionRow(
                title: "Export for Anki",
                subtitle: "Tab-separated text file you import via Anki → File → Import.",
                icon: "arrow.up.doc.fill",
                tint: Palette.bamboo,
                disabled: deck.cards.isEmpty
            ) {
                prepareAnkiExport()
            }

            Divider().overlay(Palette.hairline)

            actionRow(
                title: deck.isArchived ? "Unarchive deck" : "Archive deck",
                subtitle: deck.isArchived
                    ? "Move back to your active decks."
                    : "Hide the deck from the main list (you can restore it later).",
                icon: deck.isArchived ? "tray.and.arrow.up.fill" : "archivebox.fill",
                tint: Palette.mist
            ) {
                deck.isArchived.toggle()
                if deck.isArchived { deck.isExcludedFromReviews = true }
                try? modelContext.save()
            }

            Divider().overlay(Palette.hairline)

            actionRow(
                title: "Delete deck",
                subtitle: "Permanently removes the deck and its cards.",
                icon: "trash.fill",
                tint: Palette.vermillion
            ) {
                showDeleteConfirm = true
            }
        }
        .washiCard(padding: 8)
        .padding(.horizontal)
    }

    private func actionRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.sumi)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Info")
            VStack(spacing: 0) {
                inlineField(label: "Name", text: $deck.name)
                Divider().padding(.leading, 16).overlay(Palette.hairline)
                inlineField(label: "Tag", text: $deck.mediaTag)
            }
            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
        }
        .padding(.horizontal)
    }

    private var cardsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cards", trailing: "\(deck.cards.count)")
            BrushDivider()

            if deck.cards.isEmpty {
                Text("No cards in this deck yet.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(deck.cards.sorted(by: { $0.createdAt > $1.createdAt })) { card in
                        NavigationLink {
                            CardEditView(card: card)
                        } label: {
                            CardRow(
                                card: card,
                                isKnown: Knownness.isKnown(
                                    expression: card.expression,
                                    knownWords: knownWords,
                                    userJLPTLevel: jlptLevel
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func inlineField(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.mist)
                .frame(width: 70, alignment: .leading)
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.sumi)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct CardRow: View {
    let card: Flashcard
    /// True when the card's word is considered known (manual mark or JLPT
    /// level implies it). Surfaces as a yellow "should be known" warning so
    /// the user can see at a glance which deck entries are likely overkill.
    var isKnown: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.expression)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                Text(card.reading)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.indigo.opacity(0.85))
                if let meaning = card.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .lineLimit(2)
                }
                if isKnown {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Should be known")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Palette.gold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.gold.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.4), lineWidth: 0.5))
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(card.cardType.label)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.3), lineWidth: 0.5))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.mist.opacity(0.6))
            }
        }
        .padding(14)
        .background(
            (isKnown ? Palette.gold.opacity(0.07) : Palette.washi),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isKnown ? Palette.gold.opacity(0.45) : Palette.hairline,
                    lineWidth: isKnown ? 1 : 0.75
                )
        )
    }
}
