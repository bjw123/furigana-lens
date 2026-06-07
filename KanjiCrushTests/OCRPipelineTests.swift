import XCTest
import UIKit
@testable import KanjiCrush

/// E2E tests for the OCR + tokenization pipeline using real game screenshots
/// as fixtures. Each fixture is a frame the app realistically sees when the
/// user points the camera at a TV; assertions list a handful of expected
/// tokens that should survive both Vision recognition and the local Japanese
/// analyzer.
final class OCRPipelineTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let resource: String
        /// Words that must appear in the combined OCR text. Picked to be
        /// distinctive enough to catch regressions, lenient enough that
        /// single missed glyphs in Vision don't fail the suite.
        let expectedSubstrings: [String]
    }

    private let fixtures: [Fixture] = [
        Fixture(resource: "trails_hatman", expectedSubstrings: ["中年男", "連中"]),
        Fixture(resource: "trails_cafebar", expectedSubstrings: ["カフェバー", "夜"]),
        Fixture(resource: "trails_tutorial", expectedSubstrings: ["周囲", "活用"]),
        Fixture(resource: "trails_navigation", expectedSubstrings: ["ナビゲーション", "情報屋"]),
        Fixture(resource: "persona_sns", expectedSubstrings: ["警察", "改心"]),
        Fixture(resource: "persona_sojiro", expectedSubstrings: ["観察", "大人しく"]),
    ]

    // MARK: - Tests

    func test_allFixtures_produceAtLeastOneLine() async throws {
        for fixture in fixtures {
            let image = try loadFixture(fixture.resource)
            let lines = try await OCRService.shared.recognize(in: image)
            XCTAssertFalse(
                lines.isEmpty,
                "OCR returned no lines for \(fixture.resource)"
            )
        }
    }

    func test_allFixtures_recognizeExpectedSubstrings() async throws {
        for fixture in fixtures {
            let image = try loadFixture(fixture.resource)
            let lines = try await OCRService.shared.recognize(in: image)
            let combined = lines.map(\.text).joined(separator: " ")

            for expected in fixture.expectedSubstrings {
                XCTAssertTrue(
                    combined.contains(expected),
                    "[\(fixture.resource)] expected to find '\(expected)' in: \(combined)"
                )
            }
        }
    }

    func test_allFixtures_tokenizeIntoKanjiWords() async throws {
        for fixture in fixtures {
            let image = try loadFixture(fixture.resource)
            let lines = try await OCRService.shared.recognize(in: image)
            let combined = lines.map(\.text).joined(separator: " ")
            let tokens = JapaneseAnalysisService.shared.tokenize(combined)

            XCTAssertFalse(tokens.isEmpty, "No tokens for \(fixture.resource)")

            let kanjiTokens = tokens.filter { $0.surface.containsKanji }
            XCTAssertFalse(
                kanjiTokens.isEmpty,
                "[\(fixture.resource)] tokenizer produced no kanji words from: \(combined)"
            )
        }
    }

    func test_tokens_haveNonEmptyReadings() async throws {
        let image = try loadFixture("persona_sojiro")
        let lines = try await OCRService.shared.recognize(in: image)
        let combined = lines.map(\.text).joined(separator: " ")
        let tokens = JapaneseAnalysisService.shared.tokenize(combined)

        let kanjiTokens = tokens.filter { $0.surface.containsKanji }
        for token in kanjiTokens {
            XCTAssertFalse(
                token.reading.isEmpty,
                "Kanji token '\(token.surface)' should have a reading"
            )
        }
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> UIImage {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            throw XCTSkip("Fixture \(name).png missing from test bundle")
        }
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
            throw XCTSkip("Fixture \(name).png could not be decoded")
        }
        return image
    }
}

// Local mirror of the String.containsKanji helper that lives in ScanView.swift
// as a private extension, so tests don't need to reach into that file.
private extension String {
    var containsKanji: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }
    }
}
