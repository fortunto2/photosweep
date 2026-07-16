import Photos
import SwiftUI

struct PermissionView: View {
    let status: PHAuthorizationStatus
    /// Async request handler supplied by `RootView`.
    let onRequest: () async -> Void

    @State private var requesting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("PhotoSweep needs your photos")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("We scan your library to find large videos and screenshots you can delete. Everything stays on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if status == .denied || status == .restricted {
                Text("Access was denied. Enable it in Settings → Privacy → Photos.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    requesting = true
                    Task {
                        await onRequest()
                        requesting = false
                    }
                } label: {
                    Text(requesting ? "Requesting…" : "Grant Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(requesting)
            }
        }
        .padding(32)
    }
}
