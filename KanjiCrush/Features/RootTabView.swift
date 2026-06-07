import SwiftUI

struct RootTabView: View {
    @AppStorage("appAccent") private var appAccentRaw: String = AppAccent.indigo.rawValue

    private var accent: AppAccent {
        AppAccent(rawValue: appAccentRaw) ?? .indigo
    }

    var body: some View {
        TabView {
            ScanView()
                .tabItem {
                    Label { Text("Scan") } icon: { Image("ScanTab") }
                }

            DecksView()
                .tabItem {
                    Label { Text("Decks") } icon: { Image("DecksTab") }
                }

            ReviewView()
                .tabItem {
                    Label { Text("Review") } icon: { Image("ReviewTab") }
                }

            SettingsView()
                .tabItem {
                    Label { Text("Settings") } icon: { Image("SettingsTab") }
                }
        }
        .tint(accent.color)
    }
}
