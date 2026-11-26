import Darwin
import Foundation
import os

/// Measures launch from the moment the kernel created the process (includes dyld and
/// `App.init`), not from some point inside our own code that already flatters us.
///
/// AI-NOTE: lines go to stdout as `[launch] <mark> ms=<n>` so `devicectl device process
/// launch --console` can read them on a real phone; `_work/measure-launch.sh` parses them.
enum LaunchClock {
    /// Process start time from `sysctl(KERN_PROC_PID)`; falls back to first use.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }()

    private static let logger = Logger(subsystem: "co.superduperai.photosweep", category: "launch")
    private nonisolated(unsafe) static var marked: Set<String> = []
    private static let lock = NSLock()

    /// Milliseconds since process start.
    static var elapsedMs: Int { Int(Date().timeIntervalSince(processStart) * 1000) }

    /// Records a mark once per process; later calls with the same name are ignored.
    @discardableResult
    static func mark(_ name: String) -> Int {
        let ms = elapsedMs
        let first = lock.withLock { marked.insert(name).inserted }
        guard first else { return ms }
        print("[launch] \(name) ms=\(ms)")
        fflush(stdout)
        logger.info("\(name, privacy: .public) ms=\(ms)")
        return ms
    }
}
