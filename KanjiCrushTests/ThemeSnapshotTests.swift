import XCTest
import SwiftUI
import SnapshotTesting
@testable import KanjiCrush

/// Snapshot tests for the visual primitives in `KanjiCrush/Theme/Theme.swift`.
///
/// Baselines live in `KanjiCrushTests/__Snapshots__/ThemeSnapshotTests/`.
/// To regenerate baselines (e.g. after an intentional visual change), flip
/// `isRecording = true` in `setUp`, run once, then flip back to false and
/// commit the new PNGs alongside the code change.
final class ThemeSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // isRecording = true  // <- only set this temporarily when adding new tests
    }

    // MARK: - Helpers

    /// Wraps a view in a fixed-size container with the cream washi background so
    /// the rendered PNG is deterministic regardless of the host environment.
    private func framed<V: View>(_ width: CGFloat, _ height: CGFloat, @ViewBuilder _ view: () -> V) -> some View {
        ZStack {
            Palette.cream
            view()
        }
        .frame(width: width, height: height)
    }

    // MARK: - GemTile

    func test_gemTile_vermillion() {
        let view = framed(120, 120) {
            GemTile(tint: Palette.vermillion, size: 96) {
                Text("龍")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 120, height: 120)))
    }

    func test_gemTile_sakura() {
        let view = framed(120, 120) {
            GemTile(tint: Palette.sakura, size: 96) {
                Text("桜")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 120, height: 120)))
    }

    func test_gemTile_indigo() {
        let view = framed(120, 120) {
            GemTile(tint: Palette.indigo, size: 96) {
                Text("藍")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 120, height: 120)))
    }

    func test_gemTile_bamboo() {
        let view = framed(120, 120) {
            GemTile(tint: Palette.bamboo, size: 96) {
                Text("竹")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 120, height: 120)))
    }

    func test_gemTile_gold() {
        let view = framed(120, 120) {
            GemTile(tint: Palette.gold, size: 96) {
                Text("金")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 120, height: 120)))
    }

    // MARK: - WashiCard

    func test_washiCard_empty() {
        let view = framed(220, 120) {
            WashiCard {
                Color.clear.frame(width: 160, height: 60)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 220, height: 120)))
    }

    func test_washiCard_withContent() {
        let view = framed(220, 120) {
            WashiCard {
                Text("中")
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.sumi)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 220, height: 120)))
    }

    // MARK: - KanjiGemBadge (stands in for the GemBadge primitive)

    func test_gemBadge_indigo() {
        let view = framed(100, 100) {
            KanjiGemBadge(kanji: "N5", tint: Palette.indigo, size: 72)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 100, height: 100)))
    }

    func test_gemBadge_sakura() {
        let view = framed(100, 100) {
            KanjiGemBadge(kanji: "桜", tint: Palette.sakura, size: 72)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 100, height: 100)))
    }

    func test_gemBadge_bamboo() {
        let view = framed(100, 100) {
            KanjiGemBadge(kanji: "竹", tint: Palette.bamboo, size: 72)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 100, height: 100)))
    }

    func test_gemBadge_gold() {
        let view = framed(100, 100) {
            KanjiGemBadge(kanji: "金", tint: Palette.gold, size: 72)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 100, height: 100)))
    }

    // MARK: - BrushDivider

    func test_brushDivider_default() {
        let view = framed(280, 24) {
            BrushDivider()
                .frame(width: 240)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 280, height: 24)))
    }

    // MARK: - SectionHeader

    func test_sectionHeader_withTrailing() {
        let view = framed(320, 40) {
            SectionHeader(title: "Today's review", trailing: "5 left")
                .padding(.horizontal, 16)
                .frame(width: 320)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 320, height: 40)))
    }

    func test_sectionHeader_titleOnly() {
        let view = framed(320, 40) {
            SectionHeader(title: "Today's review")
                .padding(.horizontal, 16)
                .frame(width: 320)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 320, height: 40)))
    }

    // MARK: - MapleGlyph

    func test_mapleGlyph_size60() {
        let view = framed(80, 80) {
            MapleGlyph(size: 60)
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 80, height: 80)))
    }

    // MARK: - KanjiGemBoard

    func test_kanjiGemBoard_default() {
        // The board takes 8 surrounding kanji + a centre slot; the task asked
        // for a 9-glyph composition, so pass 8 as the surround and use the
        // remaining glyph as the centre hero.
        let view = framed(260, 260) {
            KanjiGemBoard(
                surroundingKanji: ["龍", "雷", "炎", "剣", "魂", "神", "月", "桜"]
            ) {
                Text("漢")
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.cream)
            }
        }
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 260, height: 260)))
    }
}
