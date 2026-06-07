import SwiftUI
import UIKit

/// Design tokens for the playful-Japanese aesthetic.
///
/// Palette names borrow from traditional Japanese colours so usage stays semantic
/// (e.g. `sakura` is always the soft pink accent, `sumi` is always the ink-black text).
enum Palette {
    /// Washi paper background.
    static let cream = Color(
        light: UIColor(red: 0.984, green: 0.965, blue: 0.929, alpha: 1.0),
        dark:  UIColor(red: 0.102, green: 0.086, blue: 0.071, alpha: 1.0)
    )

    /// Subtle elevated surface on top of `cream`.
    static let washi = Color(
        light: UIColor(red: 1.000, green: 0.992, blue: 0.973, alpha: 1.0),
        dark:  UIColor(red: 0.157, green: 0.137, blue: 0.118, alpha: 1.0)
    )

    /// Deep indigo — the primary brand accent (藍 / ai).
    static let indigo = Color(
        light: UIColor(red: 0.180, green: 0.227, blue: 0.420, alpha: 1.0),
        dark:  UIColor(red: 0.541, green: 0.627, blue: 0.878, alpha: 1.0)
    )

    /// Cherry-blossom pink — used for highlights and decorative flourish (桜 / sakura).
    static let sakura = Color(
        light: UIColor(red: 0.910, green: 0.647, blue: 0.710, alpha: 1.0),
        dark:  UIColor(red: 0.949, green: 0.714, blue: 0.776, alpha: 1.0)
    )

    /// Sumi ink — primary text (墨 / sumi).
    static let sumi = Color(
        light: UIColor(red: 0.157, green: 0.137, blue: 0.118, alpha: 1.0),
        dark:  UIColor(red: 0.918, green: 0.890, blue: 0.847, alpha: 1.0)
    )

    /// Faded ink — secondary text.
    static let mist = Color(
        light: UIColor(red: 0.420, green: 0.388, blue: 0.353, alpha: 1.0),
        dark:  UIColor(red: 0.659, green: 0.624, blue: 0.580, alpha: 1.0)
    )

    /// Vermillion — destructive / "again" semantic (朱 / shu).
    static let vermillion = Color(
        light: UIColor(red: 0.769, green: 0.271, blue: 0.271, alpha: 1.0),
        dark:  UIColor(red: 0.878, green: 0.439, blue: 0.439, alpha: 1.0)
    )

    /// Bamboo green — positive / "known" semantic (竹 / take).
    static let bamboo = Color(
        light: UIColor(red: 0.420, green: 0.557, blue: 0.353, alpha: 1.0),
        dark:  UIColor(red: 0.561, green: 0.690, blue: 0.478, alpha: 1.0)
    )

    /// Gold — gentle highlight for "easy" semantic (金 / kin).
    static let gold = Color(
        light: UIColor(red: 0.722, green: 0.580, blue: 0.353, alpha: 1.0),
        dark:  UIColor(red: 0.835, green: 0.706, blue: 0.475, alpha: 1.0)
    )

    /// Soft hairline used for borders and dividers.
    static let hairline = Color(
        light: UIColor(red: 0.157, green: 0.137, blue: 0.118, alpha: 0.12),
        dark:  UIColor(red: 0.918, green: 0.890, blue: 0.847, alpha: 0.18)
    )
}

extension Color {
    /// Light/dark dynamic colour helper.
    init(light: UIColor, dark: UIColor) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Backgrounds

/// Soft warm gradient that evokes washi paper. Use on root screens.
struct WashiBackground: View {
    /// Override the user's preference. Defaults to the user's setting.
    var showWavePattern: Bool? = nil

    @AppStorage("showWavePattern") private var userShowWavePattern: Bool = true

    private var displayWavePattern: Bool {
        showWavePattern ?? userShowWavePattern
    }

    var body: some View {
        ZStack {
            // Cream → faint sakura → faint gold base for warmth.
            LinearGradient(
                colors: [
                    Palette.cream,
                    Color(
                        light: UIColor(red: 0.992, green: 0.953, blue: 0.929, alpha: 1.0),
                        dark:  UIColor(red: 0.118, green: 0.102, blue: 0.086, alpha: 1.0)
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Sakura wash from the top-right — feels like light hitting paper.
            RadialGradient(
                colors: [Palette.sakura.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            // Indigo wash from the bottom-left for balance.
            RadialGradient(
                colors: [Palette.indigo.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 460
            )
            .ignoresSafeArea()

            if displayWavePattern {
                SeigaihaPattern(color: Palette.indigo, opacity: 0.10, radius: 32)
                    .frame(height: 180)
                    .mask(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.65), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Surfaces

/// Rounded card with a faint ink border and gentle shadow.
struct WashiCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Palette.washi, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
            .shadow(color: Palette.sumi.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// Wraps the view in a `WashiCard` surface.
    func washiCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        WashiCard(padding: padding, cornerRadius: cornerRadius) { self }
    }
}

// MARK: - Candy-tile primitives (Kanji-Crush identity)

/// Single glossy "candy gem" tile used throughout the app — the same building
/// block that appears in the app icon. A vertical gradient gives it the
/// jelly-candy sheen; the top highlight is what reads as "glossy" at all sizes.
struct GemTile<Content: View>: View {
    var tint: Color = Palette.sakura
    var deeperTint: Color? = nil
    var cornerRadius: CGFloat = 18
    var size: CGFloat? = nil
    var shadowStrength: Double = 1.0
    @ViewBuilder let content: () -> Content

    private var bottomTint: Color {
        deeperTint ?? tint.opacity(0.78)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint, bottomTint],
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

            content()
        }
        .frame(width: size, height: size)
        .shadow(color: Palette.sumi.opacity(0.20 * shadowStrength), radius: 14 * shadowStrength, x: 0, y: 8 * shadowStrength)
    }
}

/// Kanji glyph painted on a `GemTile`. Used as the brand mark and in hero
/// grids. The default cream foreground matches the app icon.
struct KanjiGemBadge: View {
    let kanji: String
    var tint: Color = Palette.sakura
    var deeperTint: Color? = nil
    var size: CGFloat = 56
    var foreground: Color = Palette.cream
    var fontWeight: Font.Weight = .bold

    var body: some View {
        GemTile(tint: tint, deeperTint: deeperTint, cornerRadius: size * 0.22, size: size) {
            Text(kanji)
                .font(.system(size: size * 0.58, weight: fontWeight, design: .serif))
                .foregroundStyle(foreground)
                .minimumScaleFactor(0.6)
        }
    }
}

/// 3×3 grid of small kanji gems with a single hero gem in the centre —
/// the same composition as the app icon. The 8 background tiles cycle the
/// brand palette; the centre slot is whatever caller provides.
struct KanjiGemBoard<Centre: View>: View {
    var sideTiles: CGFloat = 56
    var spacing: CGFloat = 6
    var centreSize: CGFloat = 116
    /// 8 surrounding kanji (row-major, skipping centre):
    /// row 1: 0 1 2 / row 2: 3 [centre] 4 / row 3: 5 6 7
    var surroundingKanji: [String] = ["龍", "雷", "炎", "剣", "魂", "神", "月", "桜"]
    @ViewBuilder let centre: () -> Centre

    private let surroundingTints: [(Color, Color)] = [
        (Palette.sakura, Color(red: 0.870, green: 0.486, blue: 0.580)),
        (Palette.indigo, Color(red: 0.135, green: 0.165, blue: 0.310)),
        (Palette.gold,   Color(red: 0.580, green: 0.460, blue: 0.270)),
        (Palette.bamboo, Color(red: 0.330, green: 0.460, blue: 0.270)),
        (Palette.indigo, Color(red: 0.135, green: 0.165, blue: 0.310)),
        (Palette.bamboo, Color(red: 0.330, green: 0.460, blue: 0.270)),
        (Palette.gold,   Color(red: 0.580, green: 0.460, blue: 0.270)),
        (Palette.sakura, Color(red: 0.870, green: 0.486, blue: 0.580))
    ]

    var body: some View {
        let kanji = surroundingKanji
        let total = sideTiles * 3 + spacing * 2
        ZStack {
            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { col in
                            if row == 1 && col == 1 {
                                Color.clear.frame(width: sideTiles, height: sideTiles)
                            } else {
                                let idx = surroundingIndex(row: row, col: col)
                                let tints = surroundingTints[idx % surroundingTints.count]
                                KanjiGemBadge(
                                    kanji: kanji[idx % kanji.count],
                                    tint: tints.0.opacity(0.55),
                                    deeperTint: tints.1.opacity(0.55),
                                    size: sideTiles,
                                    foreground: Palette.cream.opacity(0.95)
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: total, height: total)

            // Centre hero tile sits on top of the grid, slightly larger.
            GemTile(
                tint: Palette.sakura,
                deeperTint: Color(red: 0.870, green: 0.486, blue: 0.580),
                cornerRadius: centreSize * 0.26,
                size: centreSize,
                shadowStrength: 1.4
            ) {
                centre()
            }
        }
        .frame(width: max(total, centreSize), height: max(total, centreSize))
    }

    /// Map a (row, col) position to an index into the 8-element surrounding list,
    /// skipping the centre tile.
    private func surroundingIndex(row: Int, col: Int) -> Int {
        let flat = row * 3 + col
        return flat < 4 ? flat : flat - 1
    }
}

/// Twinkle accent used to decorate kanji-gem compositions. Tiny circle with
/// a soft glow — sprinkle a few around hero surfaces.
struct SparkleAccent: View {
    var size: CGFloat = 8
    var tint: Color = Palette.cream

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .shadow(color: tint.opacity(0.9), radius: size * 0.6)
            .opacity(0.85)
    }
}

// MARK: - Brush divider

/// Hand-drawn horizontal brush stroke. Pairs with `SectionHeader`.
/// Default colours land softer than pure sumi — a teal-indigo body with a sakura tail —
/// so the page reads as airy and Japanese instead of a hard black bar.
struct BrushDivider: View {
    var color: Color = Palette.indigo
    var tailColor: Color = Palette.sakura

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: 4, y: mid))
            path.addCurve(
                to: CGPoint(x: size.width - 12, y: mid),
                control1: CGPoint(x: size.width * 0.3, y: mid - 3),
                control2: CGPoint(x: size.width * 0.7, y: mid + 3)
            )
            context.stroke(
                path,
                with: .color(color.opacity(0.40)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            // tapered tail in sakura for a touch of warmth
            var tail = Path()
            tail.move(to: CGPoint(x: size.width - 12, y: mid))
            tail.addQuadCurve(
                to: CGPoint(x: size.width - 1, y: mid + 1),
                control: CGPoint(x: size.width - 6, y: mid - 1)
            )
            context.stroke(
                tail,
                with: .color(tailColor.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
            )
        }
        .frame(height: 8)
    }
}

// MARK: - Seigaiha (青海波) wave pattern

/// Traditional Japanese wave pattern — overlapping concentric arcs.
/// Use as a subtle backdrop in section headers / hero panels.
struct SeigaihaPattern: View {
    var color: Color = Palette.indigo
    var opacity: Double = 0.12
    /// Radius of one wave (the pattern's "tile" is roughly 2r wide, r tall).
    var radius: CGFloat = 28
    var lineWidth: CGFloat = 1.0

    var body: some View {
        Canvas { context, size in
            let r = radius
            let stepX = r * 2
            let stepY = r
            let rings = 3

            var y: CGFloat = 0
            var row = 0
            while y < size.height + r {
                let xOffset: CGFloat = (row % 2 == 0) ? 0 : r
                var x: CGFloat = -r + xOffset
                while x < size.width + r {
                    for i in 0..<rings {
                        let ringR = r - CGFloat(i) * (r / CGFloat(rings + 1))
                        let arcRect = CGRect(
                            x: x - ringR,
                            y: y - ringR,
                            width: ringR * 2,
                            height: ringR * 2
                        )
                        let arcPath = Path { p in
                            p.addArc(
                                center: CGPoint(x: x, y: y),
                                radius: ringR,
                                startAngle: .degrees(0),
                                endAngle: .degrees(180),
                                clockwise: true
                            )
                        }
                        _ = arcRect  // silence unused warning if any
                        context.stroke(
                            arcPath,
                            with: .color(color.opacity(opacity * (1.0 - Double(i) * 0.2))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                    }
                    x += stepX
                }
                y += stepY
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - App accent

/// User-selectable accent colour. Drives the app `.tint` and small motifs in Settings.
enum AppAccent: String, CaseIterable, Identifiable {
    case indigo, sakura, bamboo, gold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .indigo: return "Indigo · 藍"
        case .sakura: return "Sakura · 桜"
        case .bamboo: return "Bamboo · 竹"
        case .gold:   return "Gold · 金"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return Palette.indigo
        case .sakura: return Palette.sakura
        case .bamboo: return Palette.bamboo
        case .gold:   return Palette.gold
        }
    }
}

// MARK: - Petal accent

/// Decorative little Japanese maple leaf (紅葉 / kouyou) — used in empty states and headers.
///
/// Seven sharply-pointed lobes radiating in a fan from a small stem, drawn with
/// angular paths and filled with an autumn gradient that runs crimson → vermillion →
/// burnt orange → amber from leaf-tip to stem. Crisp at section-header sizes (~10pt)
/// and richly toned at hero sizes (40pt+).
struct MapleGlyph: View {
    var size: CGFloat = 14
    /// When true, fills with the kouyou autumn gradient. When false, falls back to a flat `color`.
    var autumnTint: Bool = true
    var color: Color = Palette.vermillion

    /// Reference kouyou palette — used for both the leaf gradient and motif accents.
    static let crimson    = Color(red: 0.58, green: 0.10, blue: 0.10)
    static let vermillion = Color(red: 0.81, green: 0.24, blue: 0.18)
    static let orange     = Color(red: 0.88, green: 0.46, blue: 0.16)
    static let amber      = Color(red: 0.93, green: 0.72, blue: 0.30)
    static let veinGold   = Color(red: 0.96, green: 0.82, blue: 0.38)
    static let stemBrown  = Color(red: 0.40, green: 0.22, blue: 0.10)

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            // Leaf "base" sits low so the stem can dangle below.
            let baseY = h * 0.82

            // 7 lobes — outermost pair, two mid pairs, single longest top.
            let lobeAngles: [Double] = [-122, -82, -40, 0, 40, 82, 122]
            let lobeLens: [CGFloat]  = [0.32, 0.44, 0.56, 0.66, 0.56, 0.44, 0.32]
            // 6 notches between adjacent lobes.
            let notchAngles: [Double] = [-102, -62, -20, 20, 62, 102]
            let notchDepth: CGFloat = 0.18

            func point(angleDeg: Double, length: CGFloat) -> CGPoint {
                // 0° = up, 90° = right (clockwise like a clock face).
                let rad = (angleDeg - 90) * .pi / 180
                let dx = CGFloat(cos(rad))
                let dy = CGFloat(sin(rad))
                return CGPoint(x: cx + dx * length, y: baseY + dy * length)
            }

            var path = Path()
            path.move(to: CGPoint(x: cx, y: baseY))
            for i in 0..<7 {
                let tip = point(angleDeg: lobeAngles[i], length: lobeLens[i] * h)
                path.addLine(to: tip)
                if i < 6 {
                    let notch = point(angleDeg: notchAngles[i], length: notchDepth * h)
                    path.addLine(to: notch)
                }
            }
            path.closeSubpath()

            if autumnTint {
                let topY = baseY - lobeLens[3] * h     // top of the leaf (longest lobe tip)
                let bottomY = baseY                     // stem joint
                let gradient = Gradient(stops: [
                    .init(color: Self.crimson,    location: 0.00),
                    .init(color: Self.vermillion, location: 0.32),
                    .init(color: Self.orange,     location: 0.66),
                    .init(color: Self.amber,      location: 1.00)
                ])
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: cx, y: topY),
                        endPoint:   CGPoint(x: cx, y: bottomY)
                    )
                )

                // Subtle rim — slightly deeper crimson outline lifts the silhouette
                // against the cream background.
                context.stroke(
                    path,
                    with: .color(Self.crimson.opacity(0.35)),
                    style: StrokeStyle(lineWidth: max(0.4, w * 0.018), lineJoin: .round)
                )
            } else {
                context.fill(path, with: .color(color.opacity(0.95)))
            }

            // Veins — gold lines from base into the three central lobes.
            // Skipped on outer lobes so small sizes don't clutter.
            for i in [2, 3, 4] {
                let tip = point(angleDeg: lobeAngles[i], length: lobeLens[i] * h * 0.78)
                var vein = Path()
                vein.move(to: CGPoint(x: cx, y: baseY))
                vein.addLine(to: tip)
                context.stroke(
                    vein,
                    with: .color(Self.veinGold.opacity(0.65)),
                    style: StrokeStyle(lineWidth: max(0.45, w * 0.025), lineCap: .round)
                )
            }

            // Stem — warm brown, gently kinked so the leaf doesn't look stamped on.
            var stem = Path()
            stem.move(to: CGPoint(x: cx, y: baseY))
            stem.addQuadCurve(
                to: CGPoint(x: cx + w * 0.04, y: h * 0.97),
                control: CGPoint(x: cx - w * 0.02, y: h * 0.92)
            )
            context.stroke(
                stem,
                with: .color(Self.stemBrown.opacity(0.85)),
                style: StrokeStyle(lineWidth: max(1, w * 0.07), lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Button styles

/// Primary action — filled indigo with a soft pressed state.
struct SumiButtonStyle: ButtonStyle {
    var tint: Color = Palette.indigo
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.78 : 1.0))
            )
            .shadow(
                color: tint.opacity(configuration.isPressed ? 0.10 : 0.25),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined secondary action — sumi border with washi fill.
struct WashiButtonStyle: ButtonStyle {
    var tint: Color = Palette.indigo
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.washi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(configuration.isPressed ? 0.6 : 0.35), lineWidth: 1.25)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Pill/chip style — used for word chips and tag indicators.
struct ChipButtonStyle: ButtonStyle {
    var tint: Color
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(emphasized ? 0.18 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(emphasized ? 0.55 : 0.30), lineWidth: 0.75)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Section header

/// Small section header with a petal glyph + label. Pairs with `BrushDivider`.
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            MapleGlyph(size: 13)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.indigo)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }
        }
    }
}
