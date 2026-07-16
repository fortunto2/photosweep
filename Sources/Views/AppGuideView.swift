import SwiftUI

/// Guide for clearing OTHER apps' caches.
///
/// AI-NOTE: iOS sandboxing means we cannot read or clear another app's cache.
/// This screen only opens the app (via its URL scheme, if installed) and shows
/// the manual steps. `canOpenURL` requires each scheme in LSApplicationQueriesSchemes.
struct AppGuideView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iOS won’t let any app clear another app’s cache. These are the manual steps — tap Open to jump straight into the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(AppCacheGuide.curated) { guide in
                    Section {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            Label {
                                Text(step)
                            } icon: {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 20, height: 20)
                                    .background(.tint, in: Circle())
                                    .foregroundStyle(.white)
                            }
                        }
                    } header: {
                        HStack {
                            Label(guide.bundleName, systemImage: guide.symbol)
                                .font(.headline)
                                .textCase(nil)
                            Spacer()
                            if let url = guide.openURL, canOpen(url) {
                                Button("Open") { openURL(url) }
                                    .font(.subheadline.weight(.semibold))
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("App Cleanup")
        }
    }

    private func canOpen(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }
}
