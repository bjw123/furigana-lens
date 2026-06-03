#!/usr/bin/env swift
// Renders the FuriganaLens app icon to a 1024x1024 PNG.
// Usage: swift tools/generate_icon.swift [output-path]

import SwiftUI
import AppKit

// MARK: - Palette (matches FuriganaLens/Theme/Theme.swift, light values)
private extension Color {
    static let cream     = Color(red: 0.984, green: 0.965, blue: 0.929)
    static let washi     = Color(red: 1.000, green: 0.992, blue: 0.973)
    static let indigo    = Color(red: 0.180, green: 0.227, blue: 0.420)
    static let sakura    = Color(red: 0.910, green: 0.647, blue: 0.710)
    static let sakuraDeep = Color(red: 0.870, green: 0.486, blue: 0.580)
    static let sumi      = Color(red: 0.157, green: 0.137, blue: 0.118)
    static let gold      = Color(red: 0.722, green: 0.580, blue: 0.353)
}

// MARK: - Sakura petal shape (5-petal flower built from rounded ellipses)
private struct SakuraFlower: View {
    var petalColor: Color = .sakura
    var centerColor: Color = .gold

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let petalLen = size * 0.45
            let petalWid = size * 0.30

            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    let angle = Double(i) / 5.0 * 2 * .pi - .pi / 2
                    Ellipse()
                        .fill(petalColor)
                        .frame(width: petalWid, height: petalLen)
                        .offset(y: -petalLen * 0.42)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(center)
                }
                Circle()
                    .fill(centerColor)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .position(center)
            }
        }
    }
}

// MARK: - Icon artwork

private struct AppIconArtwork: View {
    let side: CGFloat = 1024

    var body: some View {
        ZStack {
            // Warm washi paper base
            LinearGradient(
                colors: [
                    Color.washi,
                    Color.cream,
                    Color(red: 0.984, green: 0.945, blue: 0.918)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Sakura wash from top-right
            RadialGradient(
                colors: [Color.sakura.opacity(0.45), .clear],
                center: UnitPoint(x: 0.85, y: 0.15),
                startRadius: 30,
                endRadius: 720
            )

            // Indigo wash from bottom-left
            RadialGradient(
                colors: [Color.indigo.opacity(0.18), .clear],
                center: UnitPoint(x: 0.10, y: 0.95),
                startRadius: 20,
                endRadius: 760
            )

            // Decorative big petal behind composition
            SakuraFlower(petalColor: Color.sakura.opacity(0.28))
                .frame(width: 720, height: 720)
                .rotationEffect(.degrees(-18))
                .offset(x: 110, y: 100)
                .blur(radius: 1)

            // Tiny sakura accent in the upper-left
            SakuraFlower(
                petalColor: Color.sakuraDeep.opacity(0.85),
                centerColor: Color.gold
            )
            .frame(width: 130, height: 130)
            .rotationEffect(.degrees(28))
            .offset(x: -340, y: -340)

            // Tiny sakura accent in the lower-right
            SakuraFlower(
                petalColor: Color.sakura.opacity(0.65),
                centerColor: Color.gold.opacity(0.85)
            )
            .frame(width: 90, height: 90)
            .rotationEffect(.degrees(-12))
            .offset(x: 360, y: 360)

            // Brush-stroke underline behind the kanji (very subtle)
            Capsule()
                .fill(Color.sumi.opacity(0.08))
                .frame(width: 540, height: 16)
                .offset(y: 280)
                .blur(radius: 4)

            // Furigana ふ + kanji 文 stack — the brand silhouette
            VStack(spacing: -30) {
                Text("ふ")
                    .font(.system(size: 200, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.indigo.opacity(0.92))

                Text("文")
                    .font(.system(size: 620, weight: .bold, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sumi, Color(red: 0.20, green: 0.18, blue: 0.16)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.sumi.opacity(0.18), radius: 18, x: 0, y: 10)
            }
            .offset(y: 30)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Render

@MainActor
func render(to outputURL: URL) throws {
    let view = AppIconArtwork()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0
    renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)

    guard let nsImage = renderer.nsImage else {
        throw NSError(domain: "icon-gen", code: 1, userInfo: [NSLocalizedDescriptionKey: "renderer returned nil"])
    }

    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon-gen", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
    FileHandle.standardOutput.write("wrote \(outputURL.path) (\(pngData.count) bytes)\n".data(using: .utf8)!)
}

let defaultOutput = "FuriganaLens/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
let outArg = CommandLine.arguments.dropFirst().first ?? defaultOutput
let outURL = URL(fileURLWithPath: outArg)

// Top-level scripts run on main — ImageRenderer requires main actor isolation.
MainActor.assumeIsolated {
    do {
        try render(to: outURL)
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}
