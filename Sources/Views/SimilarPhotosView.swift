import SwiftUI

/// Duplicates + similar shots, grouped, with "keep best of each" in one tap.
struct SimilarPhotosView: View {
    @State private var vm: SimilarPhotosViewModel
    @State private var previewAsset: MediaAsset?
    @State private var blurrySelection: Set<String> = []

    init(finder: SimilarPhotoFinderProtocol, library: PhotoLibraryServiceProtocol,
         track: @escaping PhotoLibraryService.Track, keeps: KeepStore = .shared) {
        _vm = State(initialValue: SimilarPhotosViewModel(finder: finder, library: library, track: track,
                                                         keeps: keeps))
    }

    var body: some View {
        NavigationStack {
            List {
                if let started = vm.deleteStarted { deleteStatus(started) }
                controls
                if !vm.groups.isEmpty { quickClean }
                ForEach(vm.groups) { group in groupSection(group) }
                if !vm.blurry.isEmpty { blurrySection }
                if vm.hasScanned && vm.groups.isEmpty && vm.blurry.isEmpty {
                    ContentUnavailableView("No duplicates found", systemImage: "checkmark.seal",
                                           description: Text("Nothing similar in \(vm.scope.rawValue.lowercased())."))
                }
            }
            .navigationTitle("Similar")
            .task { if !vm.hasScanned { await vm.scan() } }
            .sheet(item: $previewAsset) { asset in MediaPreviewView(asset: asset) }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var controls: some View {
        Section {
            Picker("Look at", selection: $vm.scope) {
                ForEach(SimilarScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(vm.isScanning)
            .onChange(of: vm.scope) { Task { await vm.scan() } }

            if vm.isScanning {
                ProgressView(value: vm.fraction) {
                    Text(vm.progressText).font(.caption)
                }
            }
        } footer: {
            Text("On-device. Favorites are never deleted.")
        }
    }

    private var quickClean: some View {
        Section {
            Picker("How much", selection: $vm.cleanLevel) {
                ForEach(CleanLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            Button {
                Task { await vm.quickClean() }
            } label: {
                HStack {
                    if vm.deletingSource == "quick_clean" { ProgressView().tint(.white) }
                    VStack(spacing: 2) {
                        Text("Keep best · delete \(vm.quickCleanIDs.count)").fontWeight(.semibold)
                        Text("frees \(Format.bytes(vm.quickCleanLocalBytes)) on iPhone · \(Format.bytes(vm.quickCleanBytes - vm.quickCleanLocalBytes)) in iCloud")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.isDeleting || vm.quickCleanIDs.isEmpty || !vm.quickCleanReady)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(vm.groups.count) groups · tap a photo to keep it · Keep all saves the row. Remembered.")
                Text("Shared Library: deleting removes it for everyone.")
                if !vm.quickCleanReady {
                    Text("Unlocks after the phone check.").foregroundStyle(.orange)
                }
                if vm.freedBytes > 0 {
                    Text("Freed \(Format.bytes(vm.freedBytes)). Empty Recently Deleted to reclaim it.")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func groupSection(_ group: SimilarGroup) -> some View {
        let kept = vm.isKept(group)
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.items) { asset in
                        AssetGridItem(asset: asset, isSelected: vm.isMarked(asset.id, in: group))
                            .overlay(alignment: .topLeading) {
                                if asset.id == group.bestID { badge("★ Best", .green) }
                                else if group.favoriteIDs.contains(asset.id) { badge("♥", .pink) }
                            }
                            .opacity(!kept && vm.isKept(asset.id) && asset.id != group.bestID ? 0.5 : 1)
                            .onTapGesture { vm.toggle(asset.id, in: group) }
                            .contextMenu {
                                Button("View", systemImage: "eye") { previewAsset = asset }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(asset.id == group.bestID ? "Best photo" : "Photo")
                            .accessibilityValue(vm.isMarked(asset.id, in: group) ? "Will be deleted" : "Kept")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(.default) { vm.toggle(asset.id, in: group) }
                    }
                }
                .padding(.vertical, 4)
            }
            .opacity(kept ? 0.35 : 1)
            .saturation(kept ? 0 : 1)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if kept {
                    Button("Undo", systemImage: "arrow.uturn.backward") { vm.undoKeep(group) }.tint(.gray)
                } else {
                    Button("Keep all", systemImage: "hand.raised") { vm.keepAll(group) }.tint(.green)
                }
            }
        } header: {
            HStack(spacing: 12) {
                Text("\(group.kind == .duplicate ? "Duplicates" : "Similar") · \(group.items.count)")
                Spacer()
                let marked = vm.marked[group.id]?.count ?? 0
                if kept {
                    Button("Kept · Undo") { vm.undoKeep(group) }.font(.caption.weight(.semibold))
                } else {
                    Button("Keep all") { vm.keepAll(group) }.font(.caption.weight(.semibold))
                    if vm.deletingSource == group.id {
                        ProgressView().controlSize(.mini)
                    } else if marked > 0 {
                        Button("Delete \(marked)", role: .destructive) { Task { await vm.deleteMarked(in: group) } }
                            .font(.caption.weight(.semibold))
                            .disabled(vm.isDeleting)
                    }
                }
            }
        }
    }

    private var blurrySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(vm.blurry) { asset in
                    AssetGridItem(asset: asset, isSelected: blurrySelection.contains(asset.id))
                        .onTapGesture {
                            if blurrySelection.contains(asset.id) { blurrySelection.remove(asset.id) }
                            else { blurrySelection.insert(asset.id) }
                        }
                        .contextMenu { Button("View", systemImage: "eye") { previewAsset = asset } }
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Out of focus · \(vm.blurry.count)")
                Spacer()
                if !blurrySelection.isEmpty {
                    Button("Delete \(blurrySelection.count)", role: .destructive) {
                        let ids = Array(blurrySelection)
                        Task {
                            await vm.deleteBlurry(ids)
                            blurrySelection.subtract(ids)
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        } footer: {
            Text("Nothing preselected.")
        }
    }

    /// iOS asks for confirmation itself; until it does, say so instead of a silent spinner.
    private func deleteStatus(_ started: Date) -> some View {
        Section {
            TimelineView(.periodic(from: started, by: 1)) { context in
                let waited = Int(context.date.timeIntervalSince(started))
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for iOS to confirm… \(waited) s").font(.subheadline)
                        if waited >= 20 {
                            Text("No dialog? iOS Photos is stuck. Restart the iPhone and try again.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
            .padding(6)
    }
}
