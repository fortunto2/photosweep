# Architecture

MVVM + Clean-ish layering. Dependencies point inward: Views → ViewModels → Service
protocols. Concrete services depend on PhotoKit; nothing else does.

```
Views (SwiftUI)         DashboardView, MediaListView, AppGuideView, PermissionView
   │  observe
ViewModels (@MainActor) DashboardViewModel, MediaCleanupViewModel
   │  call (async)
Service Protocols       PhotoLibraryServiceProtocol, StorageServiceProtocol   ← Sendable
   │  implemented by
Services                PhotoLibraryService (actor), StorageService (struct),
                        ThumbnailProvider (@MainActor)
   │  wrap
Frameworks              Photos / PhotoKit, Foundation volume keys
```

## Rules
- **PHAsset never leaves the actor.** `PhotoLibraryService` is an `actor`; it returns
  only `Sendable` `MediaAsset` snapshots. Deletion re-fetches live `PHAsset`s by
  `localIdentifier` inside the actor.
- **ViewModels are `@Observable @MainActor`** and hold only value types + a protocol
  reference — so they're driven by a `FakeLibrary` in tests with no real library.
- **Views own no logic.** Selection, sizing, deletion all live in the ViewModel.

## Concurrency
`SWIFT_STRICT_CONCURRENCY: complete`. Heavy PHAsset scanning runs on the actor (off
main). `ThumbnailProvider` is `@MainActor` because `PHCachingImageManager` isn't an
actor and its results feed SwiftUI directly.

## Testability / CLI-First
Pure logic (formatting, storage math, selection) is covered by Swift Testing with an
in-memory `FakeLibrary`. `make integration` runs these. A headless CLI over PhotoKit
is impractical on-device; the fake-backed tests are the deterministic pipeline check.

## Known limits (by iOS design, not TODOs)
- No access to other apps' caches or "System Data".
- `PHAssetResource` size read via KVC `"fileSize"` (see `PhotoLibraryService`).
- **Shared Photo Library is opaque.** PhotoKit exposes no way to tell whether a
  `PHAsset` is in the personal vs. iCloud *Shared* library, nor who contributed it.
  Supported predicate keys are only: localIdentifier, creationDate, modificationDate,
  mediaType, mediaSubtypes, duration, pixelWidth, pixelHeight, favorite, hidden,
  burstIdentifier. So a "mine vs. spouse's" split is impossible for any app.
  (`PHAssetCollectionSubtype.albumCloudShared` is the *old* Shared Albums, not this.)
- **Deletion timing.** `PHPhotoLibrary.performChanges` returns after the *local*
  commit + the system confirmation dialog; iCloud propagation is background and does
  not block. We update the cache locally on success and skip the self-induced rescan.

## Launch and scanning (1.1)

v1.0 read `PHAssetResource` sizes for every asset before the dashboard showed anything:
229–239 s on Rustam's iPhone 14 Pro Max (69,364 photos + 32,307 videos).

1.1:
- `PhotoLibraryService.scanUpdates(force:)` is one shared scan, broadcast to every screen. Its
  first element carries exact counts (`PHFetchResult.count`), then cached sizes from `SizeIndex`,
  then measured progress every 4096 assets, videos first.
- `LibraryScanner` does the walk outside the actor (`concurrentPerform` chunks). Measured: the
  cold pass stays ~234 s — `assetResources` is serialized by the photo library service, so
  parallelism does not help; the index is what makes later launches fast.
- `SizeIndex` (Application Support, TSV) keys entries by id + modificationDate. Lists (largest
  videos, screenshots) are read from it while it fills.

| iPhone 14 Pro Max, 101k assets | v1.0 | 1.1 cold | 1.1 warm |
|---|---|---|---|
| first library content | 229 s | 1.4 s | 1.5 s |
| sizes complete | 229 s | 234 s (in background) | 3.4 s |

## Similar photos (1.1)

`SimilarPhotoFinder` (ported from PhotoSift) runs Vision feature prints + Crete-Roffet blur
(from life2film va-features) on 320 px local thumbnails, 4 at a time; `PhotoGrouper` (pure,
unit-tested) groups exact copies (same pixels + bytes) and retakes (≤5 min apart, distance
< 0.45) with union-find. Vision quality (aesthetics, face capture) runs only for group members.
`FeatureStore` caches vectors as Float16 so rescans only analyze new photos. Favorites are never
suggested for deletion.
