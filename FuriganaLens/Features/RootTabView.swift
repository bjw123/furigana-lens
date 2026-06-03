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
                    Label("Scan", systemImage: "camera.viewfinder")
                }

            DecksView()
                .tabItem {
                    Label("Decks", systemImage: "books.vertical.fill")
                }

            ReviewView()
                .tabItem {
                    Label("Review", systemImage: "leaf.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(accent.color)
    }
}
