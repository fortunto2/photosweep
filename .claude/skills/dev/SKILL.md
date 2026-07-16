---
name: photosweep-dev
description: Dev workflow for PhotoSweep — run, test, build, deploy the iOS media cleaner. Use when working on PhotoSweep features, fixing bugs, or deploying. Do NOT use for other projects.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# PhotoSweep Dev Workflow

iOS media-library cleaner. Swift 6 (strict concurrency), SwiftUI, iOS 17+, XcodeGen.
No third-party SPM deps (PhotoKit is system). `.xcodeproj` is generated, never committed.

## The constraint (read first)
iOS sandbox: an app can only measure/free the **photo library**. It CANNOT read or
clear other apps' caches or "System Data". Never add features that imply otherwise.

## Commands
- `make generate` — regenerate `PhotoSweep.xcodeproj` from `project.yml`
- `make build` — compile for simulator (no signing) — the fastest error check
- `make sim` — build + run on the iOS Simulator
- `make test` / `make integration` — Swift Testing (fake-backed)
- `make lint` / `make format`
- `make archive` — Release archive for App Store distribution

If a build freezes: the Makefile `GUARD_ON` watchdog handles the Xcode 26 clang
macro-probe hang; explicit modules are disabled in `project.yml`.

## Architecture
- `Sources/Models` — Sendable value types (MediaAsset, StorageInfo, AppCacheGuide)
- `Sources/Services` — `PhotoLibraryService` (**actor**, PHAsset stays inside),
  `StorageService`, `ThumbnailProvider` (@MainActor); protocols in `Services/Protocols`
- `Sources/ViewModels` — `@Observable @MainActor`, depend on protocols (fake-testable)
- `Sources/Views` — SwiftUI, no logic
- Full rules: `docs/ARCHITECTURE.md`

## Common tasks
- **Add a cleanable category** (e.g. "large photos"): add a `MediaFilter` case + a
  fetch method on `PhotoLibraryServiceProtocol` + actor impl; reuse `MediaListView`.
- **Add an app to the cleanup guide**: append to `AppCacheGuide.curated` and add its
  URL scheme to `LSApplicationQueriesSchemes` in `project.yml`.
- **New model**: put it in `Sources/Models`, make it `Sendable`.

## Testing conventions
Swift Testing (`@Test`, `#expect`). ViewModels tested via `FakeLibrary` in
`Tests/PhotoSweepTests`. Keep pure logic (formatting, math, selection) unit-covered.
