import SwiftUI
import SwiftData
import UIKit

@main
struct FuriganaLensApp: App {
    init() {
        configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Palette.indigo)
        }
        .modelContainer(for: [Deck.self, Flashcard.self, ReviewLog.self, KnownWord.self])
    }

    private func configureGlobalAppearance() {
        let creamBG = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.086, blue: 0.071, alpha: 1.0)
                : UIColor(red: 0.984, green: 0.965, blue: 0.929, alpha: 1.0)
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = creamBG.withAlphaComponent(0.88)
        nav.shadowColor = .clear
        let titleColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.918, green: 0.890, blue: 0.847, alpha: 1.0)
                : UIColor(red: 0.157, green: 0.137, blue: 0.118, alpha: 1.0)
        }
        nav.titleTextAttributes = [
            .foregroundColor: titleColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: titleColor,
            .font: UIFont.systemFont(ofSize: 32, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundColor = creamBG.withAlphaComponent(0.92)
        tab.shadowColor = UIColor.label.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
