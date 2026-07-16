import Foundation

/// A curated, static entry for the "App cleanup guide".
///
/// AI-NOTE: iOS forbids third-party apps from reading or clearing another app's
/// cache (sandbox). This model powers a GUIDE only: we open the app via its URL
/// scheme (if installed) and show the manual steps to clear its cache. We can
/// neither measure the cache size nor delete it. This data is fully portable —
/// the same list works on any iPhone.
struct AppCacheGuide: Identifiable, Sendable, Hashable {
    var id: String { bundleName }
    /// Display name, e.g. "Telegram".
    let bundleName: String
    /// SF Symbol used as a placeholder icon.
    let symbol: String
    /// URL scheme to open the app (from LSApplicationQueriesSchemes). `nil` = no deep link.
    let urlScheme: String?
    /// Human steps to clear this app's cache from within the app itself.
    let steps: [String]

    var openURL: URL? {
        guard let urlScheme else { return nil }
        return URL(string: "\(urlScheme)://")
    }
}

extension AppCacheGuide {
    /// Top storage-heavy apps and where their in-app cache cleaner lives.
    /// Ordered roughly by how much space they typically hoard.
    static let curated: [AppCacheGuide] = [
        AppCacheGuide(
            bundleName: "Photos & iCloud (Apple)",
            symbol: "photo.on.rectangle.angled",
            urlScheme: nil,
            steps: [
                "Biggest quick win — empty Recently Deleted: deleted items (incl. ones deleted here) sit ~30 days still using space. Photos → Albums → Recently Deleted → Select → Delete All",
                "Turn on Settings → Photos → Optimize iPhone Storage — keeps originals in iCloud, small copies on device",
                "Delete large videos & old screenshots right here in PhotoSweep (Videos / Screens tabs)",
                "The rest of “Photos” storage is iOS caches (thumbnails, analysis) — managed by the system, not clearable by any app",
            ]
        ),
        AppCacheGuide(
            bundleName: "Photos cache still huge?",
            symbol: "exclamationmark.triangle.fill",
            urlScheme: nil,
            steps: [
                "First: restart the iPhone and leave it overnight on Wi-Fi + charger — the Photos cache (thumbnails, iCloud downloads, photo analysis) often shrinks on its own",
                "Check Settings → Photos → Optimize iPhone Storage is ON",
                "Still tens of GB? It's a known iOS bug where the cache never auto-purges — the only reliable fix is Erase + Restore",
                "BEFORE erasing, confirm Photos is fully synced: Photos → scroll to the very bottom → no “Uploading N items” (else you lose photos not yet in iCloud)",
                "Back up twice: an ENCRYPTED Finder backup on a Mac (keeps passwords/Health) + an iCloud backup",
                "Settings → General → Transfer or Reset iPhone → Erase All Content and Settings → then Restore from that backup. Caches rebuild fresh (~5 GB, not 40) and your apps/layout come back",
            ]
        ),
        AppCacheGuide(
            bundleName: "Google Photos",
            symbol: "photo.stack.fill",
            urlScheme: "googlephotos",
            steps: [
                "Its “Documents & Data” is a local cache — often many GB even when everything is backed up",
                "First confirm backup is done: Google Photos → Photos tab → “Backup complete”",
                "Then clear it: Settings → General → iPhone Storage → Google Photos → Delete App → reinstall",
                "You keep every photo — they live in Google’s cloud. NOTE: “Offload App” does NOT help (it keeps the data); you must Delete + reinstall",
                "Bonus: in Google Photos → Settings → “Free up space” removes on-device originals already backed up",
            ]
        ),
        AppCacheGuide(
            bundleName: "Telegram",
            symbol: "paperplane.fill",
            urlScheme: "tg",
            steps: [
                "Open Telegram → Settings",
                "Data and Storage → Storage Usage",
                "Set 'Keep Media' shorter, then tap Clear Entire Cache",
            ]
        ),
        AppCacheGuide(
            bundleName: "Instagram",
            symbol: "camera.fill",
            urlScheme: "instagram",
            steps: [
                "Instagram stores cache invisibly; there is no in-app clear button",
                "To reclaim space: offload the app (Settings → General → iPhone Storage → Instagram → Offload App), then reinstall",
                "Offloading keeps your login and documents, only the cache is dropped",
            ]
        ),
        AppCacheGuide(
            bundleName: "WhatsApp",
            symbol: "phone.bubble.fill",
            urlScheme: "whatsapp",
            steps: [
                "Open WhatsApp → Settings → Storage and Data",
                "Manage Storage → review large chats and forwarded media",
                "Delete large videos/attachments per chat",
            ]
        ),
        AppCacheGuide(
            bundleName: "TikTok",
            symbol: "music.note",
            urlScheme: "tiktok",
            steps: [
                "Open TikTok → Profile → ☰ → Settings and privacy",
                "Cache and cellular data → Free up space",
                "Tap Clear next to Cache",
            ]
        ),
        AppCacheGuide(
            bundleName: "YouTube",
            symbol: "play.rectangle.fill",
            urlScheme: "youtube",
            steps: [
                "YouTube keeps offline downloads + cache",
                "Open YouTube → You → Downloads → remove videos",
                "For cache: offload the app in iPhone Storage, then reinstall",
            ]
        ),
        AppCacheGuide(
            bundleName: "Safari",
            symbol: "safari.fill",
            urlScheme: nil,
            steps: [
                "Open the Settings app → Apps → Safari",
                "Clear History and Website Data",
                "Also: Advanced → Website Data → Remove All",
            ]
        ),
        AppCacheGuide(
            bundleName: "Spotify",
            symbol: "music.note.list",
            urlScheme: "spotify",
            steps: [
                "Open Spotify → Settings → Storage",
                "Tap Clear cache",
                "Downloaded playlists are kept; only cache is freed",
            ]
        ),
        AppCacheGuide(
            bundleName: "Snapchat",
            symbol: "bolt.fill",
            urlScheme: "snapchat",
            steps: [
                "Open Snapchat → Profile → ⚙ Settings",
                "Account Actions → Clear Cache",
                "Confirm Clear All",
            ]
        ),
    ]
}
