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
- `make archive` / `make ipa` — Release archive; `ipa` exports via the ASC API key
- `make ship-dry` — dry run of upload + submit (drop `--dry-run`, add `--confirm` to ship)

Note: the Makefile has a `GUARD_ON` watchdog that self-heals the Xcode 26 clang
macro-probe hang. If a build ever freezes, that's the known culprit — it's handled.

## Layout
```
Sources/App        @main entry
Sources/Models     MediaAsset, StorageInfo, LibraryBreakdown, LibraryScanProgress, SimilarGroup, AppCacheGuide (Sendable)
Sources/Services   PhotoLibraryService (actor, shared size scan) · LibraryScanner + SizeIndex (sizes, cached on disk)
                   SimilarPhotoFinder + PhotoGrouper + FeatureStore (duplicates, Vision) · LaunchClock · Protocols/
Sources/ViewModels Dashboard, MediaCleanup, SimilarPhotos (@Observable @MainActor)
Sources/Views      Root, Dashboard, SimilarPhotos, MediaList, AppGuide, Permission + Components/
Tests/             Swift Testing, FakeLibrary
```

## Architecture rules (full: `docs/ARCHITECTURE.md`)
- `PHAsset` stays inside the services (`PhotoLibraryService`, `LibraryScanner`, `SimilarPhotoFinder`); UI sees only `MediaAsset`.
- ViewModels depend on **protocols**, not concrete services — keeps them fake-testable.
- Views hold no logic.

## Performance contract (measured on a 101k-asset iPhone, see docs/ARCHITECTURE.md)
- First frame never waits for sizes: counts come from `PHFetchResult.count` (1.5 s to content).
- Sizes are read once and cached in `SizeIndex` (id + modificationDate); warm launch verifies in ~3 s.
  A cold size pass is ~230 s and bound by PhotoKit, not CPU: parallel chunks did not shorten it.
- `make` + `_work/measure-launch.sh` style: `[launch] <mark> ms=` lines on stdout via `devicectl --console`.

## Do
- Add new cleanable categories behind `PhotoLibraryServiceProtocol` + a `MediaFilter` case.
- Keep asset size reads in `LibraryScanner.measure` (KVC `"fileSize"`/`"locallyAvailable"`, documented).
- Grep `# AI-` before editing a file.

## Don't
- Don't claim to clean other apps / System Data.
- Don't commit `.xcodeproj` (regenerate with `make generate`).
- Don't move PhotoKit calls onto the main actor — scanning stays on the service actor.

## Deploy
App Store via `asc` CLI (see stack template). Team `J6JLR9Y684`, bundle
`co.superduperai.photosweep`.
