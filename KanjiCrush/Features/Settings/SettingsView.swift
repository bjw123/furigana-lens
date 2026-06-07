import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var allCards: [Flashcard]
    @Query private var decks: [Deck]
    @Query private var reviewLogs: [ReviewLog]
    @Query private var knownWords: [KnownWord]
    @Query private var unlockedAchievements: [UnlockedAchievement]

    @AppStorage("hideKanaOnlyTokens") private var hideKanaOnlyTokens = true
    @AppStorage("hideKnownWords") private var hideKnownWords = false
    @AppStorage("autoCaptureEnabled") private var autoCaptureEnabled = true
    @AppStorage("appAccent") private var appAccentRaw: String = AppAccent.indigo.rawValue
    @AppStorage("showWavePattern") private var showWavePattern: Bool = true
    /// JLPT level the user is at: 0 = none, 5..1 maps to N5..N1.
    /// Words at this level or easier are auto-marked as known.
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0


    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground(showWavePattern: showWavePattern)

                ScrollView {
                    VStack(spacing: 16) {
                        headerHero
                        jlptLevelCard
                        readingFiltersCard
                        appearanceCard
                        libraryCard
                        achievementsCard
                        storyCard
                        aboutCard
                        Spacer(minLength: 24)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var accent: AppAccent {
        AppAccent(rawValue: appAccentRaw) ?? .indigo
    }

    // MARK: - Hero

    private var headerHero: some View {
        ZStack {
            // Decorative seigaiha + petals on a sakura→indigo gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Palette.sakura.opacity(0.35),
                            Palette.indigo.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 130)
                .overlay(alignment: .top) {
                    SeigaihaPattern(color: Palette.indigo, opacity: 0.16, radius: 26)
                        .frame(height: 70)
                        .mask(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.4), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay(alignment: .topTrailing) {
                    MapleGlyph(size: 36)
                        .opacity(0.55)
                        .padding(14)
                }
                .overlay(alignment: .bottomLeading) {
                    MapleGlyph(size: 22)
                        .opacity(0.40)
                        .offset(x: 20, y: 12)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.75)
                )

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    KanjiGemBadge(
                        kanji: "漢",
                        tint: Palette.sakura,
                        deeperTint: Color(red: 0.870, green: 0.486, blue: 0.580),
                        size: 64,
                        foreground: Palette.cream
                    )
                    SparkleAccent(size: 5, tint: Palette.cream)
                        .offset(x: 24, y: -22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kanji Crush")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Palette.sumi)
                    Text("Read Japanese from anything")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.75))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal)
    }

    // MARK: - JLPT level

    private var jlptLevelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Your JLPT level",
                trailing: jlptLevel == 0 ? "not set" : "N\(jlptLevel)"
            )
            BrushDivider()

            Text("Words at this level or easier are auto-marked as known. You can still mark individual words unknown to override.")
                .font(.caption)
                .foregroundStyle(Palette.mist)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                jlptLevelChip(level: 0, label: "None")
                ForEach([5, 4, 3, 2, 1], id: \.self) { level in
                    jlptLevelChip(level: level, label: "N\(level)")
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func jlptLevelChip(level: Int, label: String) -> some View {
        let selected = jlptLevel == level
        return Button {
            jlptLevel = level
        } label: {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? .white : Palette.indigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? Palette.indigo : Palette.cream)
                )
                .overlay(
                    Capsule().strokeBorder(Palette.indigo.opacity(0.4), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "None" ? "No JLPT level selected" : "JLPT level \(label)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Reading filters

    private var readingFiltersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Scan & reading")
            BrushDivider()

            settingsToggleRow(
                title: "Kanji words only",
                subtitle: "Hide hiragana-only tokens after a scan.",
                icon: "character.book.closed.fill",
                tint: Palette.indigo,
                isOn: $hideKanaOnlyTokens
            )
            divider
            settingsToggleRow(
                title: "Hide known words",
                subtitle: "Skip words you've already marked as known.",
                icon: "checkmark.seal.fill",
                tint: Palette.bamboo,
                isOn: $hideKnownWords
            )
            divider
            settingsToggleRow(
                title: "Auto-capture",
                subtitle: "Snap the photo when the framed text holds still.",
                icon: "viewfinder",
                tint: Palette.sakura,
                isOn: $autoCaptureEnabled
            )
        }
        .washiCard()
        .padding(.horizontal)
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Appearance")
            BrushDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Accent colour")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                HStack(spacing: 12) {
                    ForEach(AppAccent.allCases) { option in
                        Button {
                            appAccentRaw = option.rawValue
                        } label: {
                            accentSwatch(option: option, selected: option == accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accent colour: \(option.label)")
                        .accessibilityAddTraits(option == accent ? [.isSelected, .isButton] : .isButton)
                    }
                }
                Text(accent.label)
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }

            divider

            settingsToggleRow(
                title: "Wave pattern",
                subtitle: "Show a soft seigaiha (青海波) motif at the top of each screen.",
                icon: "water.waves",
                tint: Palette.indigo,
                isOn: $showWavePattern
            )
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func accentSwatch(option: AppAccent, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 44, height: 44)
                if selected {
                    Circle()
                        .strokeBorder(option.color, lineWidth: 2.5)
                        .frame(width: 54, height: 54)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .shadow(color: option.color.opacity(selected ? 0.4 : 0), radius: 6, y: 2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Library stats

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Library")
            BrushDivider()

            HStack(spacing: 10) {
                libraryTile(value: "\(decks.count)", label: "Decks", tint: Palette.indigo, icon: "books.vertical.fill")
                libraryTile(value: "\(allCards.count)", label: "Cards", tint: Palette.sakura, icon: "rectangle.stack.fill")
                libraryTile(value: "\(reviewLogs.count)", label: "Reviews", tint: Palette.bamboo, icon: "checkmark.circle.fill")
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.bamboo)
                Text("\(knownWords.count) known word\(knownWords.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                Spacer()
            }
            .padding(.top, 2)
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func libraryTile(value: String, label: String, tint: Color, icon: String) -> some View {
        let pair = Palette.gradientPair(for: tint)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [pair.0, pair.1], startPoint: .top, endPoint: .bottom)
                    )
                Spacer()
            }
            Text(value)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(
                    LinearGradient(colors: [pair.0, pair.1], startPoint: .top, endPoint: .bottom)
                )
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.sumi)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [pair.0.opacity(0.16), pair.1.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(pair.0.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: pair.1.opacity(0.18), radius: 8, y: 4)
    }

    // MARK: - Achievements

    private var achievementsCard: some View {
        let unlockedKeys = Set(unlockedAchievements.map { $0.key })
        let unlockedCount = unlockedKeys.count
        let total = AchievementCatalog.all.count
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Achievements",
                trailing: "\(unlockedCount) / \(total)"
            )
            BrushDivider()

            let columns = [GridItem(.adaptive(minimum: 88, maximum: 130), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AchievementCatalog.all) { achievement in
                    achievementTile(achievement, isUnlocked: unlockedKeys.contains(achievement.key))
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func achievementTile(_ achievement: Achievement, isUnlocked: Bool) -> some View {
        Group {
            if isUnlocked {
                unlockedAchievementTile(achievement)
            } else {
                lockedAchievementTile(achievement)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUnlocked ? "Unlocked: " : "Locked: ")\(achievement.title). \(achievement.summary)")
    }

    /// Bright candy-gem variant — gold gradient surface with a glossy top
    /// highlight, mirroring the `GemTile` pattern.
    private func unlockedAchievementTile(_ achievement: Achievement) -> some View {
        let pair = Palette.gradientPair(for: Palette.gold)
        let cornerRadius: CGFloat = 14
        return VStack(spacing: 6) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, Palette.cream.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.top, 6)
            Text(achievement.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.cream)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(achievement.summary)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Palette.cream.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [pair.0, pair.1],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Glossy white highlight near the top edge — the "candy coat".
                RoundedRectangle(cornerRadius: cornerRadius * 0.55, style: .continuous)
                    .fill(Color.white.opacity(0.40))
                    .blur(radius: 4)
                    .padding(.horizontal, cornerRadius * 0.5)
                    .padding(.top, cornerRadius * 0.35)
                    .padding(.bottom, cornerRadius * 1.4)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: Palette.goldDeep.opacity(0.40), radius: 12, x: 0, y: 6)
    }

    /// Subtle greyed-out variant for achievements the user hasn't earned yet.
    private func lockedAchievementTile(_ achievement: Achievement) -> some View {
        VStack(spacing: 6) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.mist.opacity(0.6))
                .padding(.top, 6)
            Text(achievement.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(achievement.summary)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Palette.mist.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.cream.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
        .opacity(0.65)
    }

    // MARK: - Story

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Why this exists")
            BrushDivider()

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Palette.sakura.opacity(0.25), Palette.indigo.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.indigo)
                }

                VStack(alignment: .leading, spacing: 8) {
                    storyParagraph("As a non-native speaker who's lived in Japan, I know the struggle of figuring out obscure kanji on the fly. I bought Elden Ring when it was only available in Japanese — couldn't read a lot of the readings at the time, but I powered through with grit and Google Lens.")
                    storyParagraph("There are a number of alternative apps in this space — most of them freemium. I wanted my own: built by me, actively used by me, no ads, no subscription. Feel free to use it.")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            MapleGlyph(size: 10)
                            Text("広告なし、課金なし。自分のために作った。")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(Palette.indigo)
                        }
                        Text("no ads, no paywall — made for myself")
                            .font(.caption2)
                            .foregroundStyle(Palette.mist)
                            .italic()
                            .padding(.leading, 20)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func storyParagraph(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Palette.sumi.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "About")
            BrushDivider()

            aboutRow(
                label: "Version",
                value: appVersion,
                icon: "info.circle.fill",
                tint: Palette.indigo
            )
            divider
            aboutRow(
                label: "Dictionary data",
                value: "JMdict",
                icon: "book.closed.fill",
                tint: Palette.gold
            )
            divider
            aboutRow(
                label: "Example sentences",
                value: "Tanaka Corpus",
                icon: "text.quote",
                tint: Palette.sakura
            )
            divider
            aboutRow(
                label: "OCR",
                value: "Apple Vision",
                icon: "camera.viewfinder",
                tint: Palette.bamboo
            )

            HStack(spacing: 6) {
                MapleGlyph(size: 10)
                Text("Made for personal study · 個人学習用")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }
            .padding(.top, 8)
        }
        .washiCard()
        .padding(.horizontal)
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func aboutRow(label: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.sumi)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.mist)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Shared helpers

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.75)
            .padding(.vertical, 2)
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 6)
    }
}
