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
