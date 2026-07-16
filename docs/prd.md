# PhotoSweep — PRD

## Problem
iPhones fill up. The Settings storage screen shows huge "System Data" and per-app
usage, but users have no fast, focused tool to reclaim the space they actually *can*
control: their photo library (large videos + screenshots).

## Hard constraint (why the scope is what it is)
iOS sandboxes every app. A third-party App Store app **cannot**:
- read or clear another app's cache (Telegram, Instagram, …),
- see per-app / "System Data" storage breakdown,
- enumerate installed apps.

The **only** storage a sandboxed app can measure and free is the **photo library**
(via PhotoKit). Everything else is out of reach — so we don't pretend otherwise.

## Solution
A focused media cleaner + an honest guide for the rest.

### MVP scope
1. **Storage dashboard** — device free/total (`volumeAvailableCapacityForImportantUsage`)
   + photo-library breakdown (videos / screenshots / other photos).
2. **Large videos** — PHAssets sorted by physical size, thumbnails, multi-select.
3. **Screenshots** — the Screenshots smart album, multi-select.
4. **Bulk delete** — `PHPhotoLibrary.performChanges` → Recently Deleted (iOS shows its
   own confirmation).
5. **App cleanup guide** — curated static list of storage-heavy apps (Telegram,
   Instagram, WhatsApp, TikTok, YouTube, Safari, Spotify, Snapchat) with a deep link
   to open each app + manual steps to clear its cache. Portable to any iPhone.

### Explicitly out of scope (MVP)
- Duplicate detection / Vision / any ML.
- Clearing other apps' caches or "System Data" (impossible on iOS).
- iCloud management.

## Non-goals / honesty
The app never claims to clean "System Data" or other apps. The dashboard says so
explicitly, and the Apps tab explains the iOS limitation.

## Target user
Primary: power user with a full 128 GB iPhone. Later: general audience — the guide
data and media cleaner are device-agnostic.

## Success metric
Median GB freed per session; % of sessions that end in at least one deletion.
