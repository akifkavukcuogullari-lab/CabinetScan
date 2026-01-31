//
//  EndToEndPerformanceValidator.swift
//  cabinetscan
//
//  Created for Story 6.9: End-to-End Performance Validation
//  Validates NFR1-4 and NFR13 for production readiness
//

import Foundation
import os.log

// MARK: - End-to-End Performance Validator

/// Validates complete AI pipeline performance against NFR requirements.
///
/// **NFRs Validated:**
/// - NFR1: Depth inference <50ms per frame (iPhone 12)
/// - NFR2: Total processing time <15 seconds
/// - NFR4: Battery consumption <5% per scan
/// - NFR13: Peak memory <1.5GB
///
/// **Usage:**
/// ```swift
/// let validator = EndToEndPerformanceValidator()
/// validator.startValidation()
/// // ... run pipeline ...
/// let result = validator.finishValidation(timeLogger: logger, batteryMetrics: metrics)
/// ```
final class EndToEndPerformanceValidator {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "PerformanceValidator")

    /// Battery monitor for NFR4 validation
    private let batteryMonitor = BatteryMonitor()

    /// Device profile for tier-specific thresholds
    private lazy var deviceProfile = DevicePerformanceProfile.forCurrentDevice()

    /// Start timestamp for duration tracking
    private var startTime: CFAbsoluteTime?

    /// Capture phase duration (video + photo capture time)
    private var captureDuration: TimeInterval = 0

    /// Total frame count processed (video frames + photo frames)
    private var frameCount: Int = 0

    /// Whether validation is currently active
    private(set) var isValidating: Bool = false

    // MARK: - Initialization

    init() {}

    // MARK: - Validation Lifecycle (Task 1.2)

    /// Starts performance validation.
    ///
    /// Call this before starting the AI pipeline.
    func startValidation() {
        guard !isValidating else {
            logger.warning("Validation already in progress - ignoring duplicate start")
            return
        }

        isValidating = true
        startTime = CFAbsoluteTimeGetCurrent()
        batteryMonitor.startMonitoring()

        logger.info("Started end-to-end performance validation")
        logger.info("Device tier: \(self.deviceProfile.tier.rawValue)")
    }

    /// Records capture phase duration.
    ///
    /// - Parameter duration: Total capture time (video + photo)
    func recordCaptureDuration(_ duration: TimeInterval) {
        captureDuration = duration
        logger.debug("Capture duration recorded: \(String(format: "%.1f", duration))s")
    }

    /// Records actual frame count for accurate per-frame timing calculations.
    ///
    /// - Parameter count: Total frames processed (video + photo frames)
    func recordFrameCount(_ count: Int) {
        frameCount = count
        logger.debug("Frame count recorded: \(count)")
    }

    /// Finishes validation and returns comprehensive results.
    ///
    /// - Parameters:
    ///   - timeLogger: ProcessingTimeLogger with stage metrics
    ///   - depthInferenceAvgMs: Average depth inference time per frame (optional, calculated from timeLogger if nil)
    /// - Returns: PerformanceValidationResult with all NFR status
    func finishValidation(
        timeLogger: ProcessingTimeLogger,
        depthInferenceAvgMs: Double? = nil
    ) -> PerformanceValidationResult {
        guard isValidating else {
            logger.error("finishValidation called without startValidation")
            return createErrorResult(message: "Validation not started")
        }

        isValidating = false

        // Get battery metrics
        let batteryMetrics = batteryMonitor.stopMonitoringWithMetrics()

        // Get processing metrics
        let processingMetrics = timeLogger.getMetrics()
        let pipelineCompliance = timeLogger.checkPipelineTimeCompliance()
        let memoryCompliance = timeLogger.checkMemoryCompliance()
        let bottlenecks = timeLogger.identifyBottlenecks()

        // Calculate depth inference average (Task 1.3)
        // Use recorded frame count if available for accurate per-frame timing
        let depthAvgMs = depthInferenceAvgMs ?? calculateDepthInferenceAverage(
            from: processingMetrics,
            frameCount: frameCount > 0 ? frameCount : nil
        )

        // Validate against device-specific thresholds
        let validationResult = validateAgainstProfile(
            processingMetrics: processingMetrics,
            batteryMetrics: batteryMetrics,
            depthInferenceAvgMs: depthAvgMs,
            pipelineCompliance: pipelineCompliance,
            memoryCompliance: memoryCompliance,
            bottlenecks: bottlenecks
        )

        // Log summary
        logValidationSummary(validationResult)

        return validationResult
    }

    // MARK: - Validation Logic

    /// Validates metrics against device-specific profile.
    private func validateAgainstProfile(
        processingMetrics: PerformanceMetrics,
        batteryMetrics: BatteryMetrics?,
        depthInferenceAvgMs: Double,
        pipelineCompliance: (status: PassStatus, totalMs: Int, budgetMs: Int, message: String?),
        memoryCompliance: (status: PassStatus, peakMB: Double, limitMB: Double, message: String?),
        bottlenecks: [(stageName: String, actualMs: Int, budgetMs: Int, overagePercent: Double)]
    ) -> PerformanceValidationResult {

        let profile = deviceProfile

        // NFR1: Depth inference timing (Task 1.3)
        let depthInferenceStatus = evaluateDepthInference(avgMs: depthInferenceAvgMs, profile: profile)

        // NFR2: Total processing time (use device profile thresholds)
        let totalProcessingStatus = evaluateProcessingTime(
            totalMs: processingMetrics.totalTimeMs,
            profile: profile
        )

        // NFR4: Battery consumption (Task 1.4)
        let batteryDrain = batteryMetrics?.drainPercent ?? 0
        let batteryStatus = evaluateBatteryDrain(drain: batteryDrain, profile: profile)

        // NFR13: Memory usage (Task 1.5)
        let memoryStatus = evaluateMemoryUsage(
            peakMB: processingMetrics.peakMemoryMB,
            profile: profile
        )

        // Overall status
        let allStatuses = [depthInferenceStatus, totalProcessingStatus, batteryStatus, memoryStatus]
        let overallStatus: PassStatus
        if allStatuses.contains(.fail) {
            overallStatus = .fail
        } else if allStatuses.contains(.warn) {
            overallStatus = .warn
        } else {
            overallStatus = .pass
        }

        // Generate recommendations based on failures
        let recommendations = generateRecommendations(
            depthStatus: depthInferenceStatus,
            processingStatus: totalProcessingStatus,
            batteryStatus: batteryStatus,
            memoryStatus: memoryStatus,
            bottlenecks: bottlenecks,
            profile: profile
        )

        return PerformanceValidationResult(
            timestamp: Date(),
            deviceInfo: PerformanceDeviceInfo.current,
            deviceTier: profile.tier,
            depthInferenceAvgMs: depthInferenceAvgMs,
            depthInferenceStatus: depthInferenceStatus,
            totalProcessingMs: processingMetrics.totalTimeMs,
            totalProcessingStatus: totalProcessingStatus,
            batteryDrainPercent: batteryDrain,
            batteryStatus: batteryStatus,
            peakMemoryMB: processingMetrics.peakMemoryMB,
            memoryStatus: memoryStatus,
            overallStatus: overallStatus,
            captureDurationSeconds: captureDuration,
            bottlenecks: bottlenecks.map { BottleneckInfo(stageName: $0.stageName, actualMs: $0.actualMs, budgetMs: $0.budgetMs, overagePercent: $0.overagePercent) },
            recommendations: recommendations
        )
    }

    // MARK: - Individual NFR Evaluation

    /// Evaluates NFR1: Depth inference timing.
    private func evaluateDepthInference(avgMs: Double, profile: DevicePerformanceProfile) -> PassStatus {
        if avgMs <= Double(profile.depthInferenceTargetMs) {
            return .pass
        } else if avgMs <= Double(profile.depthInferenceTargetMs) * 1.5 {
            return .warn
        } else {
            return .fail
        }
    }

    /// Evaluates NFR2: Total processing time.
    private func evaluateProcessingTime(totalMs: Int, profile: DevicePerformanceProfile) -> PassStatus {
        if totalMs <= profile.maxProcessingTimeMs {
            return .pass
        } else if totalMs <= Int(Double(profile.maxProcessingTimeMs) * 1.2) {
            return .warn
        } else {
            return .fail
        }
    }

    /// Evaluates NFR4: Battery consumption.
    private func evaluateBatteryDrain(drain: Float, profile: DevicePerformanceProfile) -> PassStatus {
        // Skip battery validation on simulator (always returns 0)
        if PerformanceDeviceInfo.current.isSimulator {
            return .pass
        }

        if drain <= profile.maxBatteryDrainPercent {
            return .pass
        } else if drain <= profile.maxBatteryDrainPercent * 1.5 {
            return .warn
        } else {
            return .fail
        }
    }

    /// Evaluates NFR13: Memory usage.
    private func evaluateMemoryUsage(peakMB: Double, profile: DevicePerformanceProfile) -> PassStatus {
        if peakMB <= profile.maxMemoryMB {
            return .pass
        } else if peakMB <= profile.maxMemoryMB * 1.2 {
            return .warn
        } else {
            return .fail
        }
    }

    // MARK: - Helpers

    /// Calculates average depth inference time from stage metrics.
    ///
    /// - Parameters:
    ///   - metrics: Performance metrics containing stage data
    ///   - frameCount: Optional actual frame count (if nil, estimates from capture duration)
    /// - Returns: Average depth inference time per frame in milliseconds
    private func calculateDepthInferenceAverage(from metrics: PerformanceMetrics, frameCount: Int? = nil) -> Double {
        // Find depth_inference stage
        if let depthStage = metrics.stageMetrics.first(where: { $0.name == "depth_inference" }) {
            // Use actual frame count if provided, otherwise estimate from capture duration
            let actualFrameCount: Int
            if let count = frameCount, count > 0 {
                actualFrameCount = count
            } else {
                // Estimate: ~2 frames per second of capture + photo frames
                // With typical 15s video at 2fps = 30 frames + ~5 photos = ~35 frames
                let estimatedFromCapture = max(1, Int(captureDuration * 2) + 5)
                actualFrameCount = estimatedFromCapture
                logger.debug("Using estimated frame count: \(estimatedFromCapture) (capture: \(String(format: "%.1f", self.captureDuration))s)")
            }
            return Double(depthStage.durationMs) / Double(actualFrameCount)
        }

        // Log warning when depth inference stage is missing - this could indicate a pipeline issue
        logger.warning("⚠️ depth_inference stage not found in metrics - NFR1 validation may be inaccurate")
        return 0
    }

    /// Generates recommendations based on validation failures.
    private func generateRecommendations(
        depthStatus: PassStatus,
        processingStatus: PassStatus,
        batteryStatus: PassStatus,
        memoryStatus: PassStatus,
        bottlenecks: [(stageName: String, actualMs: Int, budgetMs: Int, overagePercent: Double)],
        profile: DevicePerformanceProfile
    ) -> [String] {
        var recommendations: [String] = []

        if depthStatus != .pass {
            recommendations.append("NFR1: Optimize depth inference - verify Neural Engine usage, consider FP16 model")
        }

        if processingStatus != .pass {
            if !bottlenecks.isEmpty {
                let topBottleneck = bottlenecks[0]
                recommendations.append("NFR2: Top bottleneck is \(topBottleneck.stageName) (+\(String(format: "%.0f", topBottleneck.overagePercent))% over budget)")
            }
            recommendations.append("NFR2: Consider reducing frame count or enabling Metal acceleration")
        }

        if batteryStatus != .pass && !PerformanceDeviceInfo.current.isSimulator {
            recommendations.append("NFR4: Reduce GPU/Neural Engine duty cycle or lower capture frame rate")
        }

        if memoryStatus != .pass {
            recommendations.append("NFR13: Release intermediate data earlier, use autoreleasepool around batch operations")
        }

        if profile.tier == .minimum {
            recommendations.append("Device is at minimum tier (iPhone XR) - relaxed thresholds applied")
        }

        return recommendations
    }

    /// Creates an error result when validation wasn't properly started.
    private func createErrorResult(message: String) -> PerformanceValidationResult {
        return PerformanceValidationResult(
            timestamp: Date(),
            deviceInfo: PerformanceDeviceInfo.current,
            deviceTier: deviceProfile.tier,
            depthInferenceAvgMs: 0,
            depthInferenceStatus: .fail,
            totalProcessingMs: 0,
            totalProcessingStatus: .fail,
            batteryDrainPercent: 0,
            batteryStatus: .fail,
            peakMemoryMB: 0,
            memoryStatus: .fail,
            overallStatus: .fail,
            captureDurationSeconds: 0,
            bottlenecks: [],
            recommendations: ["Error: \(message)"]
        )
    }

    /// Logs validation summary to console.
    private func logValidationSummary(_ result: PerformanceValidationResult) {
        #if DEBUG
        logger.info("═══════════════════════════════════════")
        logger.info("    END-TO-END VALIDATION SUMMARY")
        logger.info("═══════════════════════════════════════")
        logger.info("Device: \(result.deviceInfo.model) (Tier: \(result.deviceTier.rawValue))")
        logger.info("Overall: \(result.overallStatus.rawValue.uppercased())")
        logger.info("─────────────────────────────────────")
        logger.info("NFR1 Depth Inference: \(String(format: "%.1f", result.depthInferenceAvgMs))ms → \(result.depthInferenceStatus.rawValue)")
        logger.info("NFR2 Processing Time: \(result.totalProcessingMs)ms → \(result.totalProcessingStatus.rawValue)")
        logger.info("NFR4 Battery Drain: \(String(format: "%.1f", result.batteryDrainPercent))% → \(result.batteryStatus.rawValue)")
        logger.info("NFR13 Peak Memory: \(String(format: "%.0f", result.peakMemoryMB))MB → \(result.memoryStatus.rawValue)")
        logger.info("═══════════════════════════════════════")
        #endif
    }

    // MARK: - Convenience Method

    /// Validates a full pipeline run (combines start and finish).
    ///
    /// - Parameters:
    ///   - timeLogger: ProcessingTimeLogger with captured metrics
    ///   - batteryMetrics: Optional pre-captured battery metrics
    ///   - captureDuration: Total capture phase duration
    /// - Returns: PerformanceValidationResult with all NFR status
    func validateFullPipeline(
        timeLogger: ProcessingTimeLogger,
        batteryMetrics: BatteryMetrics? = nil,
        captureDuration: TimeInterval = 0
    ) -> PerformanceValidationResult {
        // If not already validating, use provided battery metrics directly
        if !isValidating {
            self.captureDuration = captureDuration

            let processingMetrics = timeLogger.getMetrics()
            let pipelineCompliance = timeLogger.checkPipelineTimeCompliance()
            let memoryCompliance = timeLogger.checkMemoryCompliance()
            let bottlenecks = timeLogger.identifyBottlenecks()

            let depthAvgMs = calculateDepthInferenceAverage(from: processingMetrics)
            let batteryDrain = batteryMetrics?.drainPercent ?? 0

            return validateAgainstProfile(
                processingMetrics: processingMetrics,
                batteryMetrics: batteryMetrics,
                depthInferenceAvgMs: depthAvgMs,
                pipelineCompliance: pipelineCompliance,
                memoryCompliance: memoryCompliance,
                bottlenecks: bottlenecks
            )
        }

        // Otherwise, use the standard finish flow
        return finishValidation(timeLogger: timeLogger)
    }
}

// MARK: - Performance Validation Result (Task 1.6)

/// Comprehensive result of end-to-end performance validation.
struct PerformanceValidationResult: Codable {
    let timestamp: Date
    let deviceInfo: PerformanceDeviceInfo
    let deviceTier: DeviceTier

    // NFR1: Depth inference timing
    let depthInferenceAvgMs: Double
    let depthInferenceStatus: PassStatus

    // NFR2: Total processing time
    let totalProcessingMs: Int
    let totalProcessingStatus: PassStatus

    // NFR4: Battery consumption
    let batteryDrainPercent: Float
    let batteryStatus: PassStatus

    // NFR13: Memory usage
    let peakMemoryMB: Double
    let memoryStatus: PassStatus

    // Overall
    let overallStatus: PassStatus

    // Capture phase
    let captureDurationSeconds: TimeInterval

    // Analysis
    let bottlenecks: [BottleneckInfo]
    let recommendations: [String]

    /// Returns true if all NFRs pass
    var allNFRsPass: Bool {
        return overallStatus == .pass
    }

    /// Returns true if any NFR fails (not just warns)
    var hasFailures: Bool {
        return overallStatus == .fail
    }
}

// MARK: - Bottleneck Info

/// Information about a performance bottleneck.
struct BottleneckInfo: Codable {
    let stageName: String
    let actualMs: Int
    let budgetMs: Int
    let overagePercent: Double
}
