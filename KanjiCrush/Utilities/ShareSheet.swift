import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around UIActivityViewController. Used for any
/// ad-hoc share-sheet surface (deck export, progress image, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
