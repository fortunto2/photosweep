# PhotoSweep

A focused iOS storage cleaner. It frees the space you actually control — **large
videos and screenshots** in your photo library — and gives honest, step-by-step
guidance for everything iOS won't let an app touch (other apps' caches, "System Data").

> Why not clear Telegram/Instagram cache automatically? iOS sandboxes every app: no
> third-party app can read or clear another app's cache. Apps that claim to are only
> clearing their own. PhotoSweep doesn't pretend — it cleans your media and guides you
> for the rest.

## Features (MVP)
- **Storage dashboard** — device free/used + photo-library breakdown.
- **Large Videos** — sorted by size, tap to select, delete in bulk.
- **Screenshots** — clear the Screenshots album fast.
- **App Cleanup guide** — deep-links + steps for the top storage-heavy apps.

Deletions go to **Recently Deleted** (iOS shows its own confirmation) — nothing is
gone for 30 days. Everything runs on-device; nothing leaves your phone.

## Requirements
- Xcode 26+, iOS 17+ target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- (optional) SwiftLint, swift-format

## Setup
```bash
make generate     # project.yml → PhotoSweep.xcodeproj
make sim          # build + run on the iOS Simulator
make test         # run unit tests
make open         # open in Xcode
```

## Architecture
MVVM, Swift 6 strict concurrency. See `docs/ARCHITECTURE.md` and `CLAUDE.md`.

## License
MIT © fortunto2
