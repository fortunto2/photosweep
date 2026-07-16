import SwiftUI
import UIKit

/// Identifiable wrapper so we can drive `.sheet(item:)` with exported file URLs.
struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Thin bridge to the native iOS share sheet (`UIActivityViewController`) — gives
/// AirDrop, Save to Files, and any installed app (YouTube, Google Photos, …).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
