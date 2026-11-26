import SwiftUI

/// Duplicates + similar shots, grouped, with "keep best of each" in one tap.
struct SimilarPhotosView: View {
    @State private var vm: SimilarPhotosViewModel
    @State private var previewAsset: MediaAsset?
    @State private var blurrySelection: Set<String> = []

    init(finder: SimilarPhotoFinderProtocol, library: PhotoLibraryServiceProtocol,
         track: @escaping PhotoLibraryService.Track) {
        _vm = State(initialValue: SimilarPhotosViewModel(finder: finder, library: library, track: track))
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Text(vm.total == 0 ? "Finding photos…"
                         : "Comparing \(vm.analyzed.formatted()) of \(vm.total.formatted()) photos")
                        .font(.caption)
                }
            }
        } footer: {
            Text("Compared on this iPhone with Apple’s Vision. Nothing is uploaded. Favorites are never suggested for deletion.")
        }
    }

    private var quickClean: some View {
        Section {
            Button {
                Task { await vm.quickClean() }
            } label: {
                HStack {
                    if vm.isDeleting { ProgressView().tint(.white) }
                    Text("Keep best · delete \(vm.quickCleanIDs.count) · \(Format.bytes(vm.quickCleanBytes))")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.isDeleting || vm.quickCleanIDs.isEmpty)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(vm.groups.count) groups. ★ marks the photo kept; tap any photo to change what goes. iOS asks before anything is deleted.")
                if vm.freedBytes > 0 {
                    Text("Freed so far: \(Format.bytes(vm.freedBytes)). Empty Recently Deleted in Photos to reclaim it.")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func groupSection(_ group: SimilarGroup) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.items) { asset in
                        AssetGridItem(asset: asset, isSelected: vm.isMarked(asset.id, in: group))
                            .overlay(alignment: .topLeading) {
                                if asset.id == group.bestID { badge("★ Best", .green) }
                                else if group.favoriteIDs.contains(asset.id) { badge("♥", .pink) }
                            }
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
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        } header: {
            HStack {
                Text("\(group.kind == .duplicate ? "Duplicates" : "Similar") · \(group.items.count)")
                Spacer()
                let marked = vm.marked[group.id]?.count ?? 0
                if marked > 0 {
                    Button("Delete \(marked)", role: .destructive) { Task { await vm.deleteMarked(in: group) } }
                        .font(.caption.weight(.semibold))
                        .disabled(vm.isDeleting)
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
            Text("Nothing here is selected for you: a soft photo can still be the only one of its moment.")
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
