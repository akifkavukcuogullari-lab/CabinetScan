//
//  BatteryMonitor.swift
//  cabinetscan
//
//  Created for Story 3.9: Performance Validation
//  Implements battery monitoring per NFR4
//

import UIKit

// MARK: - Battery Monitor (Task 6)

/// Monitors battery consumption during AI pipeline operations.
///
/// **NFR4:** Battery consumption shall be less than 5% per scan.
///
/// **Usage:**
/// ```swift
/// let monitor = BatteryMonitor()
/// monitor.startMonitoring()
/// // ... perform scan and processing ...
/// let drainPercent = monitor.stopMonitoring()
/// ```
///
/// **Important Notes:**
/// - iOS reports battery level with ~5% granularity
/// - Accurate measurement requires physical device
/// - For reliable results, average multiple scans
/// - Returns 0 on simulator or when battery state is unknown
final class BatteryMonitor {

    // MARK: - Properties

    /// Battery level at start of monitoring (0.0 to 1.0)
    private var startLevel: Float = 0

    /// Whether battery monitoring was enabled before we started
    private var wasMonitoringEnabled: Bool = false

    /// Whether monitoring is currently active
    private(set) var isMonitoring: Bool = false

    /// Start timestamp for duration tracking
    private var startTime: CFAbsoluteTime?

    // MARK: - Monitoring

    /// Starts battery monitoring.
    ///
    /// Enables battery monitoring on the device and captures the current level.
    /// Call `stopMonitoring()` when done to get the drain percentage.
    func startMonitoring() {
        guard !isMonitoring else { return }

        wasMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        startLevel = UIDevice.current.batteryLevel
        startTime = CFAbsoluteTimeGetCurrent()
        isMonitoring = true
    }

    /// Stops monitoring and returns battery drain percentage.
    ///
    /// - Returns: Battery drain as percentage (0-100).
    ///   Returns 0 if monitoring wasn't started, on simulator, or if battery state is unknown.
    @discardableResult
    func stopMonitoring() -> Float {
        guard isMonitoring else { return 0 }

        let endLevel = UIDevice.current.batteryLevel

        // Restore previous monitoring state
        if !wasMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }

        isMonitoring = false

        // Handle simulator or unknown battery state
        // Battery level is -1.0 when state is unknown
        if startLevel < 0 || endLevel < 0 {
            return 0
        }

        let drain = (startLevel - endLevel) * 100
        return max(0, drain) // Drain should be non-negative
    }

    /// Returns the duration of monitoring in seconds.
    ///
    /// - Returns: Duration in seconds, or nil if not monitoring
    func monitoringDuration() -> TimeInterval? {
        guard let start = startTime else { return nil }
        return CFAbsoluteTimeGetCurrent() - start
    }

    /// Returns the current battery level (0-100%).
    ///
    /// - Returns: Battery percentage, or -1 if unknown
    static var currentBatteryPercent: Float {
        let wasEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel * 100
        if !wasEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        return level
    }

    /// Returns whether the device is currently charging.
    static var isCharging: Bool {
        let wasEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        if !wasEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        return state == .charging || state == .full
    }

    /// Stops monitoring and returns comprehensive battery metrics.
    ///
    /// - Returns: BatteryMetrics with full details, or nil if monitoring wasn't active
    func stopMonitoringWithMetrics() -> BatteryMetrics? {
        guard isMonitoring else { return nil }

        let endLevel = UIDevice.current.batteryLevel
        let wasCharging = Self.isCharging
        let duration = monitoringDuration() ?? 0

        // Restore previous monitoring state
        if !wasMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }

        isMonitoring = false

        // Handle simulator or unknown battery state
        if startLevel < 0 || endLevel < 0 {
            return BatteryMetrics(
                drainPercent: 0,
                durationSeconds: duration,
                startLevelPercent: -1,
                endLevelPercent: -1,
                wasCharging: wasCharging
            )
        }

        let drain = max(0, (startLevel - endLevel) * 100)

        return BatteryMetrics(
            drainPercent: drain,
            durationSeconds: duration,
            startLevelPercent: startLevel * 100,
            endLevelPercent: endLevel * 100,
            wasCharging: wasCharging
        )
    }
}

// MARK: - Battery Metrics

/// Battery metrics captured during a scan operation.
struct BatteryMetrics: Codable {
    /// Battery drain as percentage (0-100)
    let drainPercent: Float

    /// Duration of the operation in seconds
    let durationSeconds: TimeInterval

    /// Battery level at start (0-100)
    let startLevelPercent: Float

    /// Battery level at end (0-100)
    let endLevelPercent: Float

    /// Whether device was charging during scan
    let wasCharging: Bool

    /// Pass/fail status based on NFR4 (<5% drain)
    var passStatus: PassStatus {
        if drainPercent < 5.0 {
            return .pass
        } else if drainPercent < 7.5 {
            return .warn
        } else {
            return .fail
        }
    }
}
