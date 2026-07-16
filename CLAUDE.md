# CLAUDE.md — PhotoSweep

iOS media-library cleaner. Frees storage a sandboxed app can *actually* touch (photos
/ videos / screenshots via PhotoKit) + an honest guide for clearing other apps' caches
manually. This file is a map, not a manual — details live in `docs/`.

## The one constraint that shapes everything
iOS sandboxes apps. We **cannot** read/clear other apps' caches or "System Data", and
cannot see per-app storage. The only freeable storage is the photo library. Don't add
features that pretend otherwise — the UI states the limit plainly. See `docs/prd.md`.

## Stack
- Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`), SwiftUI, iOS 17+
- No third-party SPM deps (PhotoKit is system) — offline-first, privacy-first
- XcodeGen (`project.yml` is source of truth; `.xcodeproj` is generated & git-ignored)
- SwiftLint + swift-format · Swift Testing

## Commands (see `make help`)
- `make build` — compile for simulator (no signing)
- `make test` / `make integration` — unit tests (fake-backed pipeline check)
- `make sim` — build + run on simulator
- `make lint` / `make format`
- `make archive` — Release archive for App Store

Note: the Makefile has a `GUARD_ON` watchdog that self-heals the Xcode 26 clang
macro-probe hang. If a build ever freezes, that's the known culprit — it's handled.

## Layout
```
Sources/App        @main entry
Sources/Models     MediaAsset, StorageInfo, LibraryBreakdown, AppCacheGuide (Sendable)
Sources/Services   PhotoLibraryService (actor), StorageService, ThumbnailProvider + Protocols/
Sources/ViewModels DashboardViewModel, MediaCleanupViewModel (@Observable @MainActor)
Sources/Views      Root, Dashboard, MediaList, AppGuide, Permission + Components/
Tests/             Swift Testing, FakeLibrary
```

## Architecture rules (full: `docs/ARCHITECTURE.md`)
- `PHAsset` never leaves the `PhotoLibraryService` actor; UI sees only `MediaAsset`.
- ViewModels depend on **protocols**, not concrete services — keeps them fake-testable.
- Views hold no logic.

## Do
- Add new cleanable categories behind `PhotoLibraryServiceProtocol` + a `MediaFilter` case.
- Keep asset size reads in `PhotoLibraryService.byteSize` (KVC `"fileSize"`, documented).
- Grep `# AI-` before editing a file.

## Don't
- Don't claim to clean other apps / System Data.
- Don't commit `.xcodeproj` (regenerate with `make generate`).
- Don't move PhotoKit calls onto the main actor — scanning stays on the service actor.

## Deploy
App Store via `asc` CLI (see stack template). Team `J6JLR9Y684`, bundle
`co.superduperai.photosweep`.
