//
//  DevicePerformanceProfile.swift
//  cabinetscan
//
//  Created for Story 6.9: End-to-End Performance Validation
//  Device-specific performance thresholds (Task 3)
//

import Foundation

// MARK: - Device Tier

/// Device performance tier classification.
enum DeviceTier: String, Codable {
    /// Minimum supported device (iPhone XR, 2018)
    /// Relaxed thresholds: 20s processing, 1.8GB memory, 7% battery
    case minimum

    /// Baseline device (iPhone 12, 2020)
    /// Standard NFR thresholds: 15s processing, 1.5GB memory, 5% battery
    case baseline

    /// Optimal device (iPhone 14+, 2022+)
    /// Expected performance: 10s processing, 1.2GB memory, 3% battery
    case optimal
}

// MARK: - Device Performance Profile (Task 3.1)

/// Performance thresholds specific to device capabilities.
///
/// **Device Tier Expectations:**
/// - **Minimum (XR):** Processing <20s, memory <1.8GB, battery <7%
/// - **Baseline (12):** Processing <15s, memory <1.5GB, battery <5%
/// - **Optimal (14+):** Processing <10s, memory <1.2GB, battery <3%
struct DevicePerformanceProfile {

    // MARK: - Properties

    /// Device tier classification
    let tier: DeviceTier

    /// Maximum acceptable processing time in milliseconds (NFR2)
    let maxProcessingTimeMs: Int

    /// Maximum acceptable peak memory in MB (NFR13)
    let maxMemoryMB: Double

    /// Maximum acceptable battery drain percentage (NFR4)
    let maxBatteryDrainPercent: Float

    /// Target depth inference time per frame in milliseconds (NFR1)
    let depthInferenceTargetMs: Int

    /// Minimum free memory required before starting processing (Task 3.5)
    let minimumFreeMemoryMB: Double

    // MARK: - Static Profiles (Task 3.2)

    /// Profile for minimum supported devices (iPhone XR)
    static let minimum = DevicePerformanceProfile(
        tier: .minimum,
        maxProcessingTimeMs: 20000,     // 20 seconds (relaxed from 15s)
        maxMemoryMB: 1800.0,            // 1.8GB (relaxed from 1.5GB)
        maxBatteryDrainPercent: 7.0,    // 7% (relaxed from 5%)
        depthInferenceTargetMs: 80,     // 80ms (relaxed from 50ms)
        minimumFreeMemoryMB: 400.0      // 400MB minimum headroom
    )

    /// Profile for baseline devices (iPhone 12)
    static let baseline = DevicePerformanceProfile(
        tier: .baseline,
        maxProcessingTimeMs: 15000,     // 15 seconds (NFR2)
        maxMemoryMB: 1500.0,            // 1.5GB (NFR13)
        maxBatteryDrainPercent: 5.0,    // 5% (NFR4)
        depthInferenceTargetMs: 50,     // 50ms (NFR1)
        minimumFreeMemoryMB: 500.0      // 500MB minimum headroom
    )

    /// Profile for optimal devices (iPhone 14+)
    static let optimal = DevicePerformanceProfile(
        tier: .optimal,
        maxProcessingTimeMs: 10000,     // 10 seconds (expected better)
        maxMemoryMB: 1200.0,            // 1.2GB (lower usage expected)
        maxBatteryDrainPercent: 3.0,    // 3% (efficient processing)
        depthInferenceTargetMs: 35,     // 35ms (faster Neural Engine)
        minimumFreeMemoryMB: 600.0      // 600MB minimum headroom
    )

    // MARK: - Device Detection (Task 3.3)

    /// Returns the appropriate profile for the current device.
    ///
    /// Uses device model identifier to classify into tiers.
    static func forCurrentDevice() -> DevicePerformanceProfile {
        let model = currentDeviceModel()

        // iPhone XR and similar (2018-2019, no LiDAR, A12)
        if isMinimumTierDevice(model) {
            return .minimum
        }

        // iPhone 14+ and Pro models (2022+, A16+)
        if isOptimalTierDevice(model) {
            return .optimal
        }

        // iPhone 11-13 series (baseline, A13-A15)
        return .baseline
    }

    /// Gets the current device model identifier.
    private static func currentDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    /// Checks if device is minimum tier (iPhone XR, 11, SE 2nd/3rd gen).
    private static func isMinimumTierDevice(_ model: String) -> Bool {
        let minimumDevices = [
            "iPhone11,8",  // iPhone XR
            "iPhone12,1",  // iPhone 11
            "iPhone12,8",  // iPhone SE 2nd gen
            "iPhone14,6",  // iPhone SE 3rd gen
        ]
        return minimumDevices.contains(model) || model.hasPrefix("iPhone11,") || model.hasPrefix("iPhone10,")
    }

    /// Checks if device is optimal tier (iPhone 14+).
    private static func isOptimalTierDevice(_ model: String) -> Bool {
        // iPhone 14 series: iPhone15,x
        // iPhone 15 series: iPhone16,x
        // iPhone 16 series: iPhone17,x
        if model.hasPrefix("iPhone15,") ||
           model.hasPrefix("iPhone16,") ||
           model.hasPrefix("iPhone17,") {
            return true
        }
        return false
    }

    // MARK: - Memory Headroom Check (Task 3.5)

    /// Checks if there's sufficient free memory to begin processing.
    ///
    /// - Returns: Tuple with (hasEnoughMemory, availableMB, requiredMB)
    func checkMemoryHeadroom() -> (sufficient: Bool, availableMB: Double, requiredMB: Double) {
        let availableMB = Double(os_proc_available_memory()) / (1024 * 1024)
        return (
            sufficient: availableMB >= minimumFreeMemoryMB,
            availableMB: availableMB,
            requiredMB: minimumFreeMemoryMB
        )
    }

    /// Returns a user-friendly message for insufficient memory.
    func insufficientMemoryMessage() -> String {
        let check = checkMemoryHeadroom()
        return """
        Insufficient memory to start processing.
        Available: \(String(format: "%.0f", check.availableMB))MB
        Required: \(String(format: "%.0f", check.requiredMB))MB
        Please close other apps and try again.
        """
    }
}

// MARK: - Profile Comparison

extension DevicePerformanceProfile {
    /// Returns whether current device meets baseline NFR requirements.
    var meetsBaselineRequirements: Bool {
        return maxProcessingTimeMs <= DevicePerformanceProfile.baseline.maxProcessingTimeMs
    }

    /// Returns a description of the profile's thresholds.
    var thresholdDescription: String {
        return """
        Device Tier: \(tier.rawValue)
        Max Processing: \(maxProcessingTimeMs)ms
        Max Memory: \(String(format: "%.0f", maxMemoryMB))MB
        Max Battery: \(maxBatteryDrainPercent)%
        Depth Target: \(depthInferenceTargetMs)ms
        Min Free Memory: \(String(format: "%.0f", minimumFreeMemoryMB))MB
        """
    }
}
