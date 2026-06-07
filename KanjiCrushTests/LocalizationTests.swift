import XCTest

/// Lint guard for `KanjiCrush/Resources/Localizable.xcstrings`.
///
/// The String Catalog drifts silently: Xcode marks entries `stale` when it
/// can't see them during auto-extraction, and new source strings land without
/// a Japanese translation. Both states ship without complaint.
///
/// This suite reads the .xcstrings JSON directly from the source tree (via
/// `#file`-relative path) and asserts:
///   1. No `extractionState: "stale"` entries remain.
///   2. Every entry either has a `ja` translation OR is explicitly opted
///      out with `shouldTranslate: false`.
///
/// Run via the standard test scheme; failures point at the exact keys that
/// drifted so you can either re-translate, delete, or opt-out.
final class LocalizationTests: XCTestCase {

    private func loadCatalog() throws -> [String: Any] {
        // KanjiCrushTests/LocalizationTests.swift -> repo root -> Resources/.xcstrings
        let testFile = URL(fileURLWithPath: #file)
        let repoRoot = testFile
            .deletingLastPathComponent()   // KanjiCrushTests/
            .deletingLastPathComponent()   // repo root
        let url = repoRoot
            .appendingPathComponent("KanjiCrush")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LocalizationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "xcstrings not a JSON object"])
        }
        return json
    }

    func test_noStaleEntriesRemain() throws {
        let json = try loadCatalog()
        guard let strings = json["strings"] as? [String: [String: Any]] else {
            XCTFail("xcstrings missing 'strings' object")
            return
        }

        let stale = strings.compactMap { key, value -> String? in
            (value["extractionState"] as? String) == "stale" ? key : nil
        }.sorted()

        XCTAssertTrue(
            stale.isEmpty,
            "Stale localization entries detected. Re-extract in Xcode or delete them:\n  - "
                + stale.joined(separator: "\n  - ")
        )
    }

    func test_everyEntryHasJapaneseOrOptsOut() throws {
        let json = try loadCatalog()
        guard let strings = json["strings"] as? [String: [String: Any]] else {
            XCTFail("xcstrings missing 'strings' object")
            return
        }

        let missing = strings.compactMap { key, value -> String? in
            // Explicit opt-out is fine.
            if let shouldTranslate = value["shouldTranslate"] as? Bool, shouldTranslate == false {
                return nil
            }
            let localizations = value["localizations"] as? [String: Any] ?? [:]
            return localizations["ja"] == nil ? key : nil
        }.sorted()

        XCTAssertTrue(
            missing.isEmpty,
            "Entries missing Japanese translation (set `shouldTranslate: false` to opt out):\n  - "
                + missing.joined(separator: "\n  - ")
        )
    }
}
