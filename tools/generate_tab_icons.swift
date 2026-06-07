#!/usr/bin/env swift
// Renders four tab-bar kanji glyph icons as template PNGs.
// Each tab gets an imageset with @1x / @2x / @3x scales (32 / 48 / 96 px)
// containing a single kanji centred on a transparent background, drawn solid
// black so iOS template-image tinting can colour it with the accent.
//
// Usage: swift tools/generate_tab_icons.swift
// (writes into KanjiCrush/Resources/Assets.xcassets/<Name>Tab.imageset/)

import SwiftUI
import AppKit

// MARK: - Glyph artwork

private struct TabGlyph: View {
    let character: String
    let side: CGFloat

    var body: some View {
        // Solid black kanji on transparent ground — alpha-only template image.
        Text(character)
            .font(.system(size: side * 0.82, weight: .heavy, design: .serif))
            .foregroundStyle(Color.black)
            .frame(width: side, height: side, alignment: .center)
            .background(Color.clear)
    }
}

// MARK: - Render helpers

@MainActor
private func renderPNG(character: String, side: CGFloat, to outputURL: URL) throws {
    let view = TabGlyph(character: character, side: side)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.proposedSize = ProposedViewSize(width: side, height: side)
    renderer.isOpaque = false

    guard let nsImage = renderer.nsImage else {
        throw NSError(domain: "tab-icon-gen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "renderer returned nil for \(character)"])
    }

    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "tab-icon-gen", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed for \(character)"])
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
    FileHandle.standardOutput.write("wrote \(outputURL.path) (\(pngData.count) bytes)\n".data(using: .utf8)!)
}

private func writeContentsJSON(in imagesetDir: URL) throws {
    let json = """
    {
      "images" : [
        {
          "filename" : "Icon-32.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "Icon-48.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "Icon-96.png",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "template-rendering-intent" : "template"
      }
    }

    """
    let url = imagesetDir.appendingPathComponent("Contents.json")
    try json.data(using: .utf8)!.write(to: url)
    FileHandle.standardOutput.write("wrote \(url.path)\n".data(using: .utf8)!)
}

// MARK: - Tab manifest

private struct TabIcon {
    let name: String
    let character: String
}

private let tabs: [TabIcon] = [
    TabIcon(name: "ScanTab",     character: "写"),
    TabIcon(name: "DecksTab",    character: "札"),
    TabIcon(name: "ReviewTab",   character: "復"),
    TabIcon(name: "SettingsTab", character: "設"),
]

private let scales: [(filename: String, side: CGFloat)] = [
    ("Icon-32.png", 32),
    ("Icon-48.png", 48),
    ("Icon-96.png", 96),
]

// MARK: - Entry point

let assetsRoot = URL(fileURLWithPath: "KanjiCrush/Resources/Assets.xcassets")

MainActor.assumeIsolated {
    do {
        for tab in tabs {
            let imagesetDir = assetsRoot.appendingPathComponent("\(tab.name).imageset")
            for (filename, side) in scales {
                let outURL = imagesetDir.appendingPathComponent(filename)
                try renderPNG(character: tab.character, side: side, to: outURL)
            }
            try writeContentsJSON(in: imagesetDir)
        }
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}
