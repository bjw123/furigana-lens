import Foundation
import SQLite3
import Compression

/// SQLite-backed offline JMdict + Tanaka Corpus lookup. The DB is preprocessed
/// by `tools/build_jmdict.py`, gzipped, and bundled at `Resources/jmdict.sqlite.gz`.
/// On first launch we decompress it into the app's Application Support directory
/// and open it read-only from there.
struct DictionaryEntry: Equatable {
    let id: Int64
    let kanji: [String]
    let kana: [String]
    let senses: [Sense]

    struct Sense: Equatable, Decodable {
        let pos: [String]
        let gloss: [String]
    }

    /// Best single reading for the requested surface form (kana form preferred).
    var reading: String { kana.first ?? kanji.first ?? "" }

    /// Flat list of all glosses across senses, capped for display.
    func glosses(limit: Int = 6) -> [String] {
        var out: [String] = []
        for sense in senses {
            for g in sense.gloss {
                out.append(g)
                if out.count >= limit { return out }
            }
        }
        return out
    }
}

struct ExampleSentence: Equatable, Hashable {
    let japanese: String
    let english: String
}

/// Per-kanji metadata sourced from Kanjidic2 at build time.
/// `jlpt` is the new JLPT level (1..5; 5 == N5) when known.
struct KanjiInfo: Equatable {
    let character: String
    let on: [String]
    let kun: [String]
    let meanings: [String]
    let jlpt: Int?
}

/// A word containing a target kanji, tagged with its JLPT level (5..1).
/// Used to populate the JLPT examples list on the kanji detail screen.
struct JLPTWordExample: Equatable, Hashable, Identifiable {
    let form: String
    let reading: String
    let gloss: String
    let level: Int
    var id: String { "\(level)-\(form)" }
}

enum DictionaryServiceError: LocalizedError {
    case bundleMissing
    case openFailed(Int32)
    case noResults

    var errorDescription: String? {
        switch self {
        case .bundleMissing: return "Bundled dictionary not found."
        case .openFailed(let code): return "Could not open dictionary (sqlite \(code))."
        case .noResults: return "No dictionary entry found."
        }
    }
}

final class DictionaryService {
    static let shared = DictionaryService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "DictionaryService.sqlite")
    private var cache: [String: [DictionaryEntry]] = [:]

    private init() {
        openDatabase()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func openDatabase() {
        do {
            let dbURL = try ensureDatabaseUnpacked()
            let result = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
            if result != SQLITE_OK {
                assertionFailure("sqlite open failed: \(result)")
                db = nil
            }
        } catch {
            assertionFailure("dictionary unpack failed: \(error)")
            db = nil
        }
    }

    /// On first launch, decompress the bundled `jmdict.sqlite.gz` into Application
    /// Support so we can open the SQLite file with read-only paths. Subsequent
    /// launches see the unpacked file and skip the work.
    private func ensureDatabaseUnpacked() throws -> URL {
        let fm = FileManager.default
        let supportDir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = supportDir.appendingPathComponent("jmdict.sqlite")
        let stampURL = supportDir.appendingPathComponent("jmdict.sqlite.version")

        let bundleStamp = bundleDatabaseStamp()
        let installedStamp = (try? String(contentsOf: stampURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if fm.fileExists(atPath: dbURL.path), installedStamp == bundleStamp {
            return dbURL
        }

        guard let gzURL = Bundle.main.url(forResource: "jmdict.sqlite", withExtension: "gz") else {
            throw NSError(domain: "DictionaryService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "jmdict.sqlite.gz missing from bundle"])
        }

        let gzData = try Data(contentsOf: gzURL)
        let raw = try decompressGzip(gzData)
        try raw.write(to: dbURL, options: .atomic)
        try bundleStamp.write(to: stampURL, atomically: true, encoding: .utf8)
        return dbURL
    }

    /// Identifier we use to detect when a fresh app build ships a different DB.
    /// Bundle URL fingerprint + file size is plenty for our offline-only case.
    private func bundleDatabaseStamp() -> String {
        guard let gzURL = Bundle.main.url(forResource: "jmdict.sqlite", withExtension: "gz"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: gzURL.path),
              let size = attrs[.size] as? Int else {
            return "missing"
        }
        return "size=\(size)"
    }

    private func decompressGzip(_ data: Data) throws -> Data {
        // Inflate using the Compression framework's zlib (raw deflate). gzip wraps
        // a raw deflate stream with a variable-length header (10 bytes fixed plus
        // optional FEXTRA / FNAME / FCOMMENT / FHCRC fields) and an 8-byte
        // trailer (CRC32 + uncompressed-size). Parse the header so we feed only
        // the deflate payload into the decoder.
        let payloadStart = try gzipPayloadOffset(data)
        guard data.count > payloadStart + 8 else {
            throw NSError(domain: "DictionaryService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "gzip payload too small"])
        }
        let payload = data.subdata(in: payloadStart..<(data.count - 8))

        // Trailer ends with ISIZE (uncompressed size mod 2^32) — use it to size
        // the output buffer exactly so larger dictionaries still fit.
        let isize = UInt32(data[data.count - 4])
                  | (UInt32(data[data.count - 3]) << 8)
                  | (UInt32(data[data.count - 2]) << 16)
                  | (UInt32(data[data.count - 1]) << 24)
        let destinationSize = max(Int(isize), 64 * 1024 * 1024) + 1024 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }

        let written = payload.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, destinationSize,
                srcBase, payload.count,
                nil, COMPRESSION_ZLIB
            )
        }

        guard written > 0 else {
            throw NSError(domain: "DictionaryService", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "gzip decompression failed"])
        }
        return Data(bytes: destination, count: written)
    }

    /// Returns the byte index where the deflate payload begins after a valid
    /// gzip header. Throws if the magic/method bytes look wrong.
    private func gzipPayloadOffset(_ data: Data) throws -> Int {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else {
            throw NSError(domain: "DictionaryService", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "not a gzip stream"])
        }
        guard data[2] == 0x08 else {
            throw NSError(domain: "DictionaryService", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "unsupported gzip compression method"])
        }
        let flags = data[3]
        var offset = 10  // fixed header

        // FEXTRA — 2-byte little-endian length, then that many bytes.
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { throw gzipHeaderTruncated() }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME — null-terminated original filename.
        if flags & 0x08 != 0 {
            offset = try indexAfterNullTerminator(in: data, from: offset)
        }
        // FCOMMENT — null-terminated comment.
        if flags & 0x10 != 0 {
            offset = try indexAfterNullTerminator(in: data, from: offset)
        }
        // FHCRC — 2-byte header CRC.
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset < data.count else { throw gzipHeaderTruncated() }
        return offset
    }

    private func indexAfterNullTerminator(in data: Data, from start: Int) throws -> Int {
        var i = start
        while i < data.count {
            if data[i] == 0 { return i + 1 }
            i += 1
        }
        throw gzipHeaderTruncated()
    }

    private func gzipHeaderTruncated() -> NSError {
        NSError(domain: "DictionaryService", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "gzip header truncated"])
    }

    /// Returns matches for the given form (kanji or kana), ordered by commonness then entry id.
    func lookup(_ keyword: String, limit: Int = 5) -> [DictionaryEntry] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db else { return [] }

        return queue.sync {
            if let hit = cache[trimmed] { return hit }

            let sql = """
                SELECT e.id, e.kanji_json, e.kana_json, e.senses_json
                FROM forms f JOIN entries e ON e.id = f.entry_id
                WHERE f.form = ?
                ORDER BY f.is_common DESC, e.id ASC
                LIMIT ?;
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [DictionaryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard
                    let kanjiCStr = sqlite3_column_text(stmt, 1),
                    let kanaCStr = sqlite3_column_text(stmt, 2),
                    let sensesCStr = sqlite3_column_text(stmt, 3)
                else { continue }

                let kanji = decodeStringArray(String(cString: kanjiCStr))
                let kana = decodeStringArray(String(cString: kanaCStr))
                let senses = decodeSenses(String(cString: sensesCStr))
                results.append(DictionaryEntry(id: id, kanji: kanji, kana: kana, senses: senses))
            }

            cache[trimmed] = results
            return results
        }
    }

    /// Convenience: top match only, or nil.
    func first(_ keyword: String) -> DictionaryEntry? {
        lookup(keyword, limit: 1).first
    }

    /// Example sentences from the Tanaka Corpus for any of the given headword forms.
    /// Pass the entry's kanji + kana forms (plus the originally-tapped surface) to maximize hits.
    func examples(for headwords: [String], limit: Int = 4) -> [ExampleSentence] {
        let unique = Array(Set(headwords.filter { !$0.isEmpty }))
        guard !unique.isEmpty, let db else { return [] }

        return queue.sync {
            let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ",")
            let sql = """
                SELECT DISTINCT e.ja, e.en
                FROM examples e
                JOIN word_examples we ON we.example_id = e.id
                WHERE we.headword IN (\(placeholders))
                ORDER BY length(e.ja) ASC
                LIMIT ?;
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            for (i, hw) in unique.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), hw, -1, SQLITE_TRANSIENT)
            }
            sqlite3_bind_int(stmt, Int32(unique.count + 1), Int32(limit))

            var out: [ExampleSentence] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let jaCStr = sqlite3_column_text(stmt, 0),
                    let enCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                out.append(ExampleSentence(
                    japanese: String(cString: jaCStr),
                    english: String(cString: enCStr)
                ))
            }
            return out
        }
    }

    /// JLPT level (1..5, where 5 = N5) of the given word form. Returns the
    /// easiest level (highest number) when the word is listed at multiple,
    /// or nil when the word isn't tagged in the JLPT vocab table.
    func jlptLevel(forWord word: String) -> Int? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db else { return nil }

        return queue.sync { () -> Int? in
            let sql = "SELECT MAX(level) FROM word_jlpt WHERE form = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
            let level = Int(sqlite3_column_int(stmt, 0))
            return (1...5).contains(level) ? level : nil
        }
    }

    /// On/kun readings + meanings + JLPT level for a single kanji character.
    /// Returns nil when the DB doesn't carry Kanjidic2 data (older builds) or
    /// when the character isn't a kanji we have an entry for.
    func kanjiInfo(_ character: Character) -> KanjiInfo? {
        let key = String(character)
        guard let db else { return nil }

        return queue.sync { () -> KanjiInfo? in
            let sql = "SELECT on_json, kun_json, meanings_json, jlpt FROM kanji WHERE char = ? LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let onCStr = sqlite3_column_text(stmt, 0),
                  let kunCStr = sqlite3_column_text(stmt, 1),
                  let meaningsCStr = sqlite3_column_text(stmt, 2)
            else { return nil }

            let jlptColType = sqlite3_column_type(stmt, 3)
            let jlpt: Int? = jlptColType == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int(stmt, 3))

            return KanjiInfo(
                character: key,
                on: decodeStringArray(String(cString: onCStr)),
                kun: decodeStringArray(String(cString: kunCStr)),
                meanings: decodeStringArray(String(cString: meaningsCStr)),
                jlpt: jlpt
            )
        }
    }

    /// JLPT-tagged example words containing the given kanji, ordered easiest
    /// first (N5 → N1) then by common-ness then alphabetically. Capped per
    /// level via `perLevel` to keep the UI bounded.
    ///
    /// Only returns entries that have a JMdict sense (so we can show a gloss)
    /// AND a JLPT classification (from the word list ingested at build time).
    func jlptExamples(forKanji character: Character, perLevel: Int = 4) -> [JLPTWordExample] {
        let key = String(character)
        guard let db else { return [] }

        return queue.sync { () -> [JLPTWordExample] in
            let sql = """
                SELECT e.kanji_json, e.kana_json, e.senses_json, wj.level, kw.is_common
                FROM kanji_words kw
                JOIN entries e ON e.id = kw.entry_id
                JOIN word_jlpt wj ON wj.form IN (
                    SELECT value FROM json_each(e.kanji_json)
                    UNION ALL
                    SELECT value FROM json_each(e.kana_json)
                )
                WHERE kw.char = ?
                ORDER BY wj.level DESC, kw.is_common DESC, e.id ASC;
                """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

            var perLevelCount: [Int: Int] = [:]
            var seenForms = Set<String>()
            var out: [JLPTWordExample] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let kanjiCStr = sqlite3_column_text(stmt, 0),
                    let kanaCStr = sqlite3_column_text(stmt, 1),
                    let sensesCStr = sqlite3_column_text(stmt, 2)
                else { continue }

                let level = Int(sqlite3_column_int(stmt, 3))
                let kanjiList = decodeStringArray(String(cString: kanjiCStr))
                let kanaList = decodeStringArray(String(cString: kanaCStr))
                guard let form = kanjiList.first(where: { $0.contains(character) }) ?? kanjiList.first
                else { continue }
                if seenForms.contains(form) { continue }

                let count = perLevelCount[level, default: 0]
                if count >= perLevel { continue }

                let senses = decodeSenses(String(cString: sensesCStr))
                let gloss = senses.first?.gloss.prefix(2).joined(separator: "; ") ?? ""

                out.append(JLPTWordExample(
                    form: form,
                    reading: kanaList.first ?? form,
                    gloss: gloss,
                    level: level
                ))
                seenForms.insert(form)
                perLevelCount[level] = count + 1
            }

            return out
        }
    }
}

// SQLite needs SQLITE_TRANSIENT to copy the bound text — Swift bridges it as this sentinel.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func decodeStringArray(_ json: String) -> [String] {
    guard let data = json.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}

private func decodeSenses(_ json: String) -> [DictionaryEntry.Sense] {
    guard let data = json.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([DictionaryEntry.Sense].self, from: data)) ?? []
}
