import Foundation

/// Heavy library passes (cold size scan, Vision) run flat out on every core. On a hot
/// phone or in Low Power Mode they rest after each batch for a share of the time the
/// batch took, so the work still finishes but the duty cycle drops: 1:1 when serious,
/// 1:3 when critical, 2:1 in Low Power Mode. A cool phone on normal power never waits.
enum HeatGuard {
    /// Rest per second of work, from the phone's current state.
    static func restRatio(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Double {
        switch thermal {
        case .critical: 3
        case .serious: 1
        default: lowPower ? 0.5 : 0
        }
    }

    /// Call after a batch that took `worked` seconds.
    static func cooldown(after worked: TimeInterval) async {
        let info = ProcessInfo.processInfo
        let rest = worked * restRatio(thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled)
        guard rest > 0.05 else { return }
        print("[heat] state=\(info.thermalState.rawValue) lowPower=\(info.isLowPowerModeEnabled) rest=\(rest)")
        try? await Task.sleep(for: .seconds(min(rest, 30)))
    }
}
