import os

enum AppLog {
    static let subsystem = "com.kanjicrush.app"

    static let dictionary = Logger(subsystem: subsystem, category: "dictionary")
    static let ocr = Logger(subsystem: subsystem, category: "ocr")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let srs = Logger(subsystem: subsystem, category: "srs")
    static let deckExport = Logger(subsystem: subsystem, category: "deck-export")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
