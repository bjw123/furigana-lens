import SwiftUI

/// Inline, dismissible-looking error banner used to surface degraded-service
/// states (dictionary unavailable, speech recognition unauthorised, etc.) at
/// the top of a screen without taking over the whole view.
///
/// Visual: washi card surface with a tinted left accent bar, an SF Symbol icon
/// in `tint`, a bold title, and a wrapped explanation. Matches the existing
/// `WashiCard` + `SectionHeader` style so banners read as "part of the page"
/// rather than a system alert. An optional action button mounts on the right
/// for recovery affordances ("Open Settings", "Retry", …).
struct ErrorBanner: View {
    let title: String
    let message: String
    /// SF Symbol name (e.g. `"exclamationmark.triangle.fill"`).
    let icon: String
    /// Accent tint — typically `Palette.vermillion` (.red), `Palette.gold`
    /// (.orange) or `Palette.sakura` (.pink) depending on severity.
    let tint: Color
    /// Optional inline call-to-action. The label sits on the trailing edge of
    /// the banner; `perform` is called on tap.
    var action: (label: String, perform: () -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Accent bar on the leading edge — mirrors the SectionHeader maple
            // glyph idiom but uses a coloured rule so the banner reads as
            // attention-grabbing even at a glance.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 2)

            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Palette.sumi.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action {
                Button(action: action.perform) {
                    Text(action.label)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                        .overlay(
                            Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.washi)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .shadow(color: Palette.sumi.opacity(0.06), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("errorBanner.\(icon)")
    }
}

// MARK: - Dictionary degraded banner

/// Conventional copy + iconography for the dictionary-degraded banner. Used by
/// every view that depends on the bundled JMdict cache so the message stays
/// consistent. Plain helper rather than a wrapper view because each call-site
/// has its own padding/layout requirements.
extension ErrorBanner {
    static func dictionaryDegraded() -> ErrorBanner {
        ErrorBanner(
            title: "Dictionary unavailable",
            message: "Readings, meanings, and JLPT lookup are disabled. Reinstalling the app usually fixes this.",
            icon: "books.vertical.fill",
            tint: Palette.vermillion
        )
    }

    static func speechUnavailable(reason: SpeechUnavailableReason, openSettings: (() -> Void)? = nil) -> ErrorBanner {
        let action: (label: String, perform: () -> Void)?
        if let openSettings, reason.canOpenSettings {
            action = (label: "Settings", perform: openSettings)
        } else {
            action = nil
        }
        return ErrorBanner(
            title: reason.title,
            message: reason.message,
            icon: "mic.slash.fill",
            tint: Palette.gold,
            action: action
        )
    }
}

/// Why the speech-check sheet can't run a recognition session. Drives the
/// copy + action affordance in the speech-unavailable banner.
enum SpeechUnavailableReason {
    case notAuthorized
    case restricted
    case recognizerUnavailable

    var title: String {
        switch self {
        case .notAuthorized:        return "Speech recognition off"
        case .restricted:           return "Speech recognition restricted"
        case .recognizerUnavailable:return "Japanese speech unavailable"
        }
    }

    var message: String {
        switch self {
        case .notAuthorized:
            return "Grant Speech Recognition and Microphone access in Settings to read this sentence aloud."
        case .restricted:
            return "Speech recognition is restricted on this device, so the read-aloud check is disabled."
        case .recognizerUnavailable:
            return "Your device doesn't support Japanese speech recognition right now. Try again later or check your network."
        }
    }

    /// Only the user-flippable states surface a Settings button — the others
    /// can't be resolved from the in-app settings sheet.
    var canOpenSettings: Bool {
        switch self {
        case .notAuthorized: return true
        case .restricted, .recognizerUnavailable: return false
        }
    }
}

// MARK: - Observable degraded mirror

/// SwiftUI view modifier that mirrors `DictionaryService.degraded` into a
/// `@State` binding. Subscribes when the modified view first appears and stays
/// alive for its lifetime. Used by `.observingDictionaryDegraded($flag)`.
private struct DictionaryDegradedObserver: ViewModifier {
    @Binding var isDegraded: Bool

    func body(content: Content) -> some View {
        content
            .task {
                // Seed with the current value so the banner shows immediately
                // if the service degraded before this view mounted.
                isDegraded = DictionaryService.isDegraded
                for await value in DictionaryService.degraded.values {
                    isDegraded = value
                }
            }
    }
}

extension View {
    /// Mirrors `DictionaryService.isDegraded` into the bound flag for the
    /// lifetime of this view. Use with a `@State var isDictionaryDegraded =
    /// false` and conditionally render `ErrorBanner.dictionaryDegraded()` at
    /// the top of your content.
    func observingDictionaryDegraded(_ flag: Binding<Bool>) -> some View {
        modifier(DictionaryDegradedObserver(isDegraded: flag))
    }
}

#Preview {
    VStack(spacing: 12) {
        ErrorBanner(
            title: "Dictionary unavailable",
            message: "Readings, meanings, and JLPT lookup are disabled. Reinstalling the app usually fixes this.",
            icon: "books.vertical.fill",
            tint: Palette.vermillion
        )
        ErrorBanner(
            title: "Speech recognition off",
            message: "Grant Speech Recognition and Microphone access in Settings to use this drill.",
            icon: "mic.slash.fill",
            tint: Palette.gold,
            action: (label: "Settings", perform: {})
        )
    }
    .padding()
    .background(WashiBackground())
}
