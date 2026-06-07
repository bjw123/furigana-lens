import SwiftUI
import SwiftData

struct DecksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query private var allCards: [Flashcard]
    @Query private var knownWords: [KnownWord]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0
    @State private var showNewDeck = false
    @State private var showArchived = false
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var importError: String?

    private var activeDecks: [Deck] { decks.filter { !$0.isArchived } }
    private var archivedDecks: [Deck] { decks.filter { $0.isArchived } }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Cards whose expression / reading / meaning / deck name match the query.
    private var searchResults: [Flashcard] {
        guard isSearching else { return [] }
        let q = trimmedQuery
        return allCards.filter { card in
            if card.expression.lowercased().contains(q) { return true }
            if card.reading.lowercased().contains(q) { return true }
            if let m = card.meaning?.lowercased(), m.contains(q) { return true }
            if let d = card.deck?.name.lowercased(), d.contains(q) { return true }
            if card.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()

                if isSearching {
                    searchResultsList
                } else if decks.isEmpty {
                    emptyState
                } else {
                    decksList
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showNewDeck = true
                        } label: {
                            Label("New deck", systemImage: "plus")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import .kcdeck file", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Palette.indigo)
                    }
                }
            }
            .sheet(isPresented: $showNewDeck) {
                NewDeckSheet()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.kanjiCrushDeck, .json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
        .searchable(text: $searchText, prompt: "Search cards…")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            // Security-scoped URL when the file is outside the app sandbox.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let existingNames = Set(decks.map { $0.name })
            _ = try DeckExportService.import(
                data: data,
                into: modelContext,
                existingDeckNames: existingNames
            )
        } catch {
            importError = error.localizedDescription
        }
    }

    private var decksList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(activeDecks) { deck in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckRowCard(deck: deck)
                    }
                    .buttonStyle(.plain)
                }

                if !archivedDecks.isEmpty {
                    archivedSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, 4)

                if searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(Palette.mist)
                        Text("No cards match \"\(searchText)\"")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Palette.mist)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 10) {
                        ForEach(searchResults) { card in
                            NavigationLink {
                                CardEditView(card: card)
                            } label: {
                                SearchResultRow(
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
            .padding(.vertical, 8)
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showArchived.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("Archived")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("(\(archivedDecks.count))")
                        .font(.caption2)
                        .foregroundStyle(Palette.mist)
                    Spacer()
                }
                .foregroundStyle(Palette.mist)
                .padding(.top, 12)
            }
            .buttonStyle(.plain)

            if showArchived {
                ForEach(archivedDecks) { deck in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckRowCard(deck: deck)
                            .opacity(0.7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Palette.sakura.opacity(0.18))
                    .frame(width: 96, height: 96)
                MapleGlyph(size: 56)
            }
            VStack(spacing: 6) {
                Text("No decks yet")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text("Save a flashcard from a scan to create your first deck.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
            }
            Button {
                showNewDeck = true
            } label: {
                Label("New deck", systemImage: "plus")
            }
            .buttonStyle(WashiButtonStyle())
        }
        .padding(.horizontal, 32)
    }
}

private struct DeckRowCard: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.indigo.opacity(0.12))
                    .frame(width: 50, height: 50)
                Text(initials)
                    .font(.system(.headline, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Palette.sumi)
                HStack(spacing: 8) {
                    Text(deck.mediaTag)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.sakura)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.sakura.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Palette.sakura.opacity(0.4), lineWidth: 0.5))
                    Text("\(deck.cards.count) cards")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                    if deck.isExcludedFromReviews {
                        statusBadge(
                            text: "Paused",
                            icon: "pause.fill",
                            tint: Palette.gold
                        )
                    }
                    if deck.isArchived {
                        statusBadge(
                            text: "Archived",
                            icon: "archivebox.fill",
                            tint: Palette.mist
                        )
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mist.opacity(0.7))
        }
        .padding(14)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .shadow(color: Palette.sumi.opacity(0.05), radius: 6, y: 3)
    }

    private var initials: String {
        let trimmed = deck.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1))
    }

    private func statusBadge(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8).weight(.semibold))
            Text(text)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

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

struct CardEditView: View {
    @Bindable var card: Flashcard

    var body: some View {
        ZStack {
            WashiBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Expression")
                        VStack(spacing: 0) {
                            row(label: "Word", text: $card.expression)
                            Divider().padding(.leading, 16).overlay(Palette.hairline)
                            row(label: "Reading", text: $card.reading)
                                .onChange(of: card.reading) { _, newValue in
                                    ReadingOverrideStore.shared.setReading(newValue, for: card.expression)
                                }
                        }
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Meaning")
                        TextField("Meaning", text: Binding(
                            get: { card.meaning ?? "" },
                            set: { card.meaning = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Palette.sumi)
                            .padding(12)
                            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
                            )
                    }
                    .padding(.horizontal)

                    if let sentence = card.contextSentence {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Context")
                            Text(sentence)
                                .font(.system(.callout, design: .serif))
                                .foregroundStyle(Palette.sumi.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .washiCard()
                        .padding(.horizontal)
                    }

                    TagEditor(tags: $card.tags)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Review")
                        VStack(spacing: 10) {
                            HStack {
                                Text("Type")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Picker("Type", selection: $card.cardType) {
                                    ForEach(CardType.allCases) { type in
                                        Text(type.label).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Palette.indigo)
                            }
                            HStack {
                                Text("Due")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Text(card.dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Palette.sumi)
                            }
                            HStack {
                                Text("Interval")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Text("\(Int(card.interval))d")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Palette.sumi)
                            }
                        }
                        .padding(14)
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.mist)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.sumi)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct NewDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var tag = "Game"

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "New deck")
                        textField(placeholder: "Deck name", text: $name)
                        textField(placeholder: "Tag (Game, Anime, …)", text: $tag)
                    }
                    .washiCard()
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let deck = Deck(name: name.trimmingCharacters(in: .whitespaces), mediaTag: tag)
                        modelContext.insert(deck)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func textField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
    }
}

/// One row in the cross-deck search results. Compact card row with the deck
/// label so the user can tell where the match lives.
private struct SearchResultRow: View {
    let card: Flashcard
    var isKnown: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(card.expression)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Palette.sumi)
                    if let deck = card.deck {
                        Text(deck.name)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.indigo.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.indigo.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.3), lineWidth: 0.5))
                    }
                    if isKnown {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.gold)
                    }
                }
                if !card.reading.isEmpty, card.reading != card.expression {
                    Text(card.reading)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
                if let meaning = card.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .lineLimit(2)
                }
                if !card.tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(Palette.sakura)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.sakura.opacity(0.14)))
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.mist.opacity(0.6))
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

/// Editable chip-list of tags. Tap × on a chip to remove; tap "+ Add tag" to
/// open an alert with a text field. Lowercase + trim on insert so tags dedupe.
struct TagEditor: View {
    @Binding var tags: [String]
    @State private var showingAdd = false
    @State private var pending = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tags", trailing: tags.isEmpty ? nil : "\(tags.count)")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    tagChip(tag)
                }
                Button {
                    pending = ""
                    showingAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.semibold))
                        Text("Add tag")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                    }
                    .foregroundStyle(Palette.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.indigo.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.4), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
            if tags.isEmpty {
                Text("Tag this card for quick search (e.g. verbs, particles, JLPT-tricky).")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .washiCard()
        .alert("New tag", isPresented: $showingAdd) {
            TextField("Tag name", text: $pending)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add") { addPending() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Examples: verbs, particles, manga, JLPT-tricky")
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(.caption, design: .rounded).weight(.medium))
            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .foregroundStyle(Palette.sakura)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.sakura.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Palette.sakura.opacity(0.4), lineWidth: 0.5))
    }

    private func addPending() {
        let normalized = pending
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty, !tags.contains(normalized) else { return }
        tags.append(normalized)
    }
}

/// Thin SwiftUI wrapper around UIActivityViewController used for the
/// .kcdeck export Share sheet (and any other ad-hoc share targets later).
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
