import Foundation

/// Backoff exponentiel `2^n` secondes avec gigue, 5 tentatives maximum (§5.8).
public enum BackoffPolicy {
    public static let maxAttempts = 5

    public static func delaySeconds(forAttempt attempt: Int, jitter: Double = Double.random(in: 0...1)) -> Double {
        pow(2.0, Double(max(attempt, 0))) + jitter
    }
}

/// État système pertinent pour la suspension automatique de la file (§5.8). Toujours injecté,
/// jamais lu directement depuis `ProcessInfo`/`IOKit` par la politique elle-même — sinon elle ne
/// serait pas testable.
public enum ThermalState: Sendable, Equatable {
    case nominal, fair, serious, critical
}

public struct PowerState: Sendable, Equatable {
    public let thermalState: ThermalState
    public let isLowPowerModeEnabled: Bool
    public let isOnACPower: Bool
    /// `nil` si l'appareil n'a pas de batterie (n'arrive jamais sur Mac portable, mais un Mac de
    /// bureau n'a pas cette notion).
    public let batteryLevel: Double?

    public init(thermalState: ThermalState, isLowPowerModeEnabled: Bool, isOnACPower: Bool, batteryLevel: Double?) {
        self.thermalState = thermalState
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isOnACPower = isOnACPower
        self.batteryLevel = batteryLevel
    }
}

/// §5.8 : concurrence 2 travaux au maximum, 1 seul pour l'OCR et l'inférence. Suspension
/// automatique si `thermalState ≥ serious`, mode économie d'énergie actif, ou batterie < 20 %
/// hors alimentation. Reprise automatique dès que l'état redevient normal.
public enum SchedulingPolicy {
    public static let maxConcurrentJobs = 2

    public static func maxConcurrentJobs(forKind kind: JobKind) -> Int {
        switch kind {
        case .ocr, .insight: return 1
        default: return maxConcurrentJobs
        }
    }

    public static func shouldSuspend(_ state: PowerState) -> Bool {
        if state.thermalState == .serious || state.thermalState == .critical { return true }
        if state.isLowPowerModeEnabled { return true }
        if !state.isOnACPower, let level = state.batteryLevel, level < 0.20 { return true }
        return false
    }
}
