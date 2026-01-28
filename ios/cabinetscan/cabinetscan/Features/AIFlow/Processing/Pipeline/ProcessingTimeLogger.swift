//
//  ProcessingTimeLogger.swift
//  cabinetscan
//
//  Created for Story 3.8: Processing Pipeline Orchestration
//  Extended for Story 3.9: Performance Validation
//  Per Architecture Section 9.3
//

import Foundation
import UIKit
import os.log

// MARK: - Performance Metrics Structures (Story 3.9 Task 1.2)

/// Comprehensive performance metrics for the pipeline
struct PerformanceMetrics {
    /// Device model (e.g., "iPhone12,1")
    let deviceModel: String

    /// iOS version (e.g., "17.0")
    let iOSVersion: String

    /// Available memory in MB at start
    let availableMemoryMB: Double

    /// Total pipeline time in milliseconds
    let totalTimeMs: Int

    /// Per-stage metrics
    let stageMetrics: [StageMetric]

    /// Memory snapshots at stage boundaries
    let memorySnapshots: [MemorySnapshot]

    /// Peak memory usage in MB
    let peakMemoryMB: Double

    /// Timestamp when metrics were collected
    let timestamp: Date
}

/// Metric for a single pipeline stage
struct StageMetric {
    let name: String
    let durationMs: Int
    let budgetMs: Int
    let memoryBeforeMB: Double
    let memoryAfterMB: Double
    let percentageOfTotal: Double
    let status: PassStatus
}

/// Memory snapshot at a specific point
struct MemorySnapshot {
    let stage: String
    let memoryMB: Double
    let timestamp: Date
}

/// Pass/fail status for performance checks
enum PassStatus: String, Codable {
    case pass
    case warn
    case fail
}

/// Performance report for export (JSON-compatible)
struct PerformanceReport: Codable {
    let deviceModel: String
    let iOSVersion: String
    let timestamp: Date
    let processingMetrics: ProcessingMetrics

    struct ProcessingMetrics: Codable {
        let totalTimeMs: Int
        let stages: [StageMetricCodable]
        let peakMemoryMB: Double
        let memoryTrend: [MemorySnapshotCodable]
    }

    struct StageMetricCodable: Codable {
        let name: String
        let durationMs: Int
        let budgetMs: Int
        let memoryBeforeMB: Double
        let memoryAfterMB: Double
        let percentageOfTotal: Double
        let status: PassStatus
    }

    struct MemorySnapshotCodable: Codable {
        let stage: String
        let memoryMB: Double
    }
}

// MARK: - Processing Time Logger (Task 2)

/// Debug-only logger for tracking processing time per pipeline step.
///
/// **Architecture 9.3 Performance Budget (iPhone 12):**
/// | Step | Budget |
/// |------|--------|
/// | model_loading | 500-1000ms |
/// | frame_extraction | 1000-1500ms |
/// | depth_inference | 1500-2500ms |
/// | point_cloud_generation | 800-1200ms |
/// | tsdf_fusion | 1500-2500ms |
/// | scale_calibration | 300-500ms |
/// | geometric_constraints | 200-400ms |
/// | **TOTAL** | **<15 seconds** |
///
/// **Usage:**
/// ```swift
/// #if DEBUG
/// let timeLogger = ProcessingTimeLogger()
/// timeLogger.startStep(.modelLoading)
/// // ... do work ...
/// timeLogger.endStep(.modelLoading)
/// timeLogger.logSummary()
/// #endif
/// ```
final class ProcessingTimeLogger {

    // MARK: - Step Definition

    /// Pipeline steps to track
    enum Step: String, CaseIterable {
        case modelLoading = "model_loading"
        case frameExtraction = "frame_extraction"
        case depthInference = "depth_inference"
        case pointCloudGeneration = "point_cloud_generation"
        case tsdfFusion = "tsdf_fusion"
        case scaleCalibration = "scale_calibration"
        case geometricConstraints = "geometric_constraints"
        case roomDetection = "room_detection"
        case cabinetDetection = "cabinet_detection"

        /// Performance budget in milliseconds (iPhone 12 baseline)
        var budgetMs: ClosedRange<Int> {
            switch self {
            case .modelLoading: return 500...1000
            case .frameExtraction: return 1000...1500
            case .depthInference: return 1500...2500
            case .pointCloudGeneration: return 800...1200
            case .tsdfFusion: return 1500...2500
            case .scaleCalibration: return 300...500
            case .geometricConstraints: return 200...400
            case .roomDetection: return 300...500
            case .cabinetDetection: return 500...1000
            }
        }

        /// Maximum budget (upper bound)
        var maxBudgetMs: Int {
            budgetMs.upperBound
        }
    }

    // MARK: - Timing Data

    /// Start time for each step
    private var stepStartTimes: [Step: CFAbsoluteTime] = [:]

    /// Elapsed time for each step
    private var stepElapsedTimes: [Step: Int] = [:]

    /// Overall pipeline start time
    private var pipelineStartTime: CFAbsoluteTime?

    private let logger = Logger(subsystem: "com.cabinetscan", category: "ProcessingTimeLogger")

    // MARK: - Memory Tracking (Story 3.9)

    /// Memory snapshots at stage boundaries
    private var memorySnapshotsData: [MemorySnapshot] = []

    /// Memory before each step
    private var stepMemoryBefore: [Step: Double] = [:]

    /// Memory after each step
    private var stepMemoryAfter: [Step: Double] = [:]

    /// Peak memory usage in MB
    private var peakMemoryUsage: Double = 0

    /// Device info (captured once, thread-safe)
    private lazy var deviceModel: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        return machine
    }()

    /// iOS version (cached at init to avoid main thread issues)
    private var _iOSVersion: String?
    private var iOSVersion: String {
        if let cached = _iOSVersion {
            return cached
        }
        // Access UIDevice on main thread if needed
        if Thread.isMainThread {
            _iOSVersion = UIDevice.current.systemVersion
            return _iOSVersion!
        } else {
            var version = ""
            DispatchQueue.main.sync {
                version = UIDevice.current.systemVersion
            }
            _iOSVersion = version
            return version
        }
    }

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.debug("ProcessingTimeLogger initialized")
        #endif
    }

    // MARK: - Step Tracking (Task 2.2)

    /// Starts timing for a step.
    ///
    /// - Parameter step: The step to start timing
    func startStep(_ step: Step) {
        if pipelineStartTime == nil {
            pipelineStartTime = CFAbsoluteTimeGetCurrent()
        }

        stepStartTimes[step] = CFAbsoluteTimeGetCurrent()

        // Capture memory before step (Story 3.9)
        let memoryMB = getCurrentMemoryMB()
        stepMemoryBefore[step] = memoryMB
        peakMemoryUsage = max(peakMemoryUsage, memoryMB)

        #if DEBUG
        logger.debug("⏱️ Started: \(step.rawValue)")
        #endif
    }

    /// Ends timing for a step and records elapsed time.
    ///
    /// - Parameter step: The step to end timing
    /// - Returns: Elapsed time in milliseconds
    @discardableResult
    func endStep(_ step: Step) -> Int {
        guard let startTime = stepStartTimes[step] else {
            #if DEBUG
            logger.warning("⚠️ endStep called for \(step.rawValue) without startStep")
            #endif
            return 0
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let elapsedMs = Int(elapsed * 1000)
        stepElapsedTimes[step] = elapsedMs

        // Capture memory after step (Story 3.9)
        let memoryMB = getCurrentMemoryMB()
        stepMemoryAfter[step] = memoryMB
        peakMemoryUsage = max(peakMemoryUsage, memoryMB)

        #if DEBUG
        // Log with budget comparison
        let budget = step.budgetMs
        let status: String
        if elapsedMs <= budget.upperBound {
            status = "✅"
        } else if elapsedMs <= budget.upperBound * 2 {
            status = "⚠️"
        } else {
            status = "❌"
        }

        logger.debug("\(status) Completed: \(step.rawValue) in \(elapsedMs)ms (budget: \(budget.lowerBound)-\(budget.upperBound)ms)")
        #endif

        return elapsedMs
    }

    // MARK: - Summary Logging (Task 2.3)

    /// Logs a summary of all step times and total pipeline time.
    func logSummary() {
        #if DEBUG
        guard let startTime = pipelineStartTime else {
            logger.warning("logSummary called but pipeline was never started")
            return
        }

        let totalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalMs = Int(totalElapsed * 1000)
        let targetMs = 15000  // 15 seconds per NFR2

        logger.info("═══════════════════════════════════════")
        logger.info("      PROCESSING TIME SUMMARY          ")
        logger.info("═══════════════════════════════════════")

        // Log each step
        for step in Step.allCases {
            if let elapsed = stepElapsedTimes[step] {
                let budget = step.budgetMs
                let ratio = Double(elapsed) / Double(budget.upperBound)
                let bar = createProgressBar(ratio: ratio)

                let status: String
                if elapsed <= budget.upperBound {
                    status = "✅"
                } else if elapsed <= budget.upperBound * 2 {
                    status = "⚠️"
                } else {
                    status = "❌"
                }

                let stepName = step.rawValue.padding(toLength: 25, withPad: " ", startingAt: 0)
                logger.info("\(status) \(stepName): \(elapsed)ms \(bar)")
            }
        }

        logger.info("───────────────────────────────────────")

        // Log total
        let totalStatus = totalMs <= targetMs ? "✅" : "❌"
        logger.info("\(totalStatus) TOTAL: \(totalMs)ms / \(targetMs)ms target")

        if totalMs > targetMs {
            let overBy = totalMs - targetMs
            logger.warning("⚠️ Pipeline exceeded budget by \(overBy)ms (\(String(format: "%.1f", Double(overBy) / Double(targetMs) * 100))%)")
        }

        logger.info("═══════════════════════════════════════")
        #endif
    }

    // MARK: - Helpers

    /// Creates a visual progress bar for logging.
    private func createProgressBar(ratio: Double) -> String {
        #if DEBUG
        let totalWidth = 20
        let filled = min(Int(ratio * Double(totalWidth)), totalWidth)
        let filledBar = String(repeating: "█", count: filled)
        let emptyBar = String(repeating: "░", count: max(0, totalWidth - filled))
        return "[\(filledBar)\(emptyBar)]"
        #else
        return ""
        #endif
    }

    /// Resets all timing data.
    func reset() {
        stepStartTimes.removeAll()
        stepElapsedTimes.removeAll()
        pipelineStartTime = nil
        memorySnapshotsData.removeAll()
        stepMemoryBefore.removeAll()
        stepMemoryAfter.removeAll()
        peakMemoryUsage = 0
        #if DEBUG
        logger.debug("ProcessingTimeLogger reset")
        #endif
    }

    // MARK: - Metrics Export (Story 3.9 Task 1.2-1.4)

    /// Returns comprehensive performance metrics.
    ///
    /// - Returns: PerformanceMetrics struct with all timing and memory data
    func getMetrics() -> PerformanceMetrics {
        let totalMs = getTotalTime() ?? 0

        var stageMetrics: [StageMetric] = []

        for step in Step.allCases {
            if let elapsed = stepElapsedTimes[step] {
                let percentageOfTotal = totalMs > 0 ? Double(elapsed) / Double(totalMs) * 100 : 0
                let memBefore = stepMemoryBefore[step] ?? 0
                let memAfter = stepMemoryAfter[step] ?? 0
                let status = determinePassStatus(elapsed: elapsed, budget: step.budgetMs)

                stageMetrics.append(StageMetric(
                    name: step.rawValue,
                    durationMs: elapsed,
                    budgetMs: step.maxBudgetMs,
                    memoryBeforeMB: memBefore,
                    memoryAfterMB: memAfter,
                    percentageOfTotal: percentageOfTotal,
                    status: status
                ))
            }
        }

        return PerformanceMetrics(
            deviceModel: deviceModel,
            iOSVersion: iOSVersion,
            availableMemoryMB: getAvailableMemoryMB(),
            totalTimeMs: totalMs,
            stageMetrics: stageMetrics,
            memorySnapshots: memorySnapshotsData,
            peakMemoryMB: peakMemoryUsage,
            timestamp: Date()
        )
    }

    /// Exports a JSON-compatible performance report.
    ///
    /// - Returns: PerformanceReport struct suitable for JSON encoding
    func exportReport() -> PerformanceReport {
        let metrics = getMetrics()

        let stageCodables = metrics.stageMetrics.map { stage in
            PerformanceReport.StageMetricCodable(
                name: stage.name,
                durationMs: stage.durationMs,
                budgetMs: stage.budgetMs,
                memoryBeforeMB: stage.memoryBeforeMB,
                memoryAfterMB: stage.memoryAfterMB,
                percentageOfTotal: stage.percentageOfTotal,
                status: stage.status
            )
        }

        let memoryTrend = metrics.memorySnapshots.map { snapshot in
            PerformanceReport.MemorySnapshotCodable(
                stage: snapshot.stage,
                memoryMB: snapshot.memoryMB
            )
        }

        return PerformanceReport(
            deviceModel: metrics.deviceModel,
            iOSVersion: metrics.iOSVersion,
            timestamp: metrics.timestamp,
            processingMetrics: PerformanceReport.ProcessingMetrics(
                totalTimeMs: metrics.totalTimeMs,
                stages: stageCodables,
                peakMemoryMB: metrics.peakMemoryMB,
                memoryTrend: memoryTrend
            )
        )
    }

    /// Returns total pipeline time in milliseconds.
    ///
    /// - Returns: Total time in ms, or nil if pipeline not started
    func getTotalTime() -> Int? {
        guard let startTime = pipelineStartTime else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    /// Returns peak memory usage in MB.
    ///
    /// - Returns: Peak memory in MB
    func getPeakMemory() -> Double {
        return peakMemoryUsage
    }

    // MARK: - Memory Helpers (Story 3.9)

    /// Gets current memory usage in MB.
    private func getCurrentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024) : 0
    }

    /// Gets available memory in MB.
    private func getAvailableMemoryMB() -> Double {
        return Double(os_proc_available_memory()) / (1024 * 1024)
    }

    /// Determines pass/warn/fail status based on elapsed time and budget.
    private func determinePassStatus(elapsed: Int, budget: ClosedRange<Int>) -> PassStatus {
        if elapsed <= budget.upperBound {
            return .pass
        } else if elapsed <= budget.upperBound * 2 {
            return .warn
        } else {
            return .fail
        }
    }

    // MARK: - Pipeline Analysis (Story 3.9 Task 4)

    /// Returns per-stage breakdown with percentage of total time.
    ///
    /// - Returns: Array of tuples (stageName, durationMs, percentOfTotal, budgetMs, status)
    func getStageBreakdown() -> [(name: String, durationMs: Int, percentOfTotal: Double, budgetMs: Int, status: PassStatus)] {
        let totalMs = getTotalTime() ?? 1 // Avoid divide by zero

        return Step.allCases.compactMap { step in
            guard let elapsed = stepElapsedTimes[step] else { return nil }
            let percentOfTotal = Double(elapsed) / Double(totalMs) * 100
            let status = determinePassStatus(elapsed: elapsed, budget: step.budgetMs)

            return (
                name: step.rawValue,
                durationMs: elapsed,
                percentOfTotal: percentOfTotal,
                budgetMs: step.maxBudgetMs,
                status: status
            )
        }
    }

    /// Identifies stages that exceed their budget (bottlenecks).
    ///
    /// - Returns: Array of bottleneck stage names with their overage percentage
    func identifyBottlenecks() -> [(stageName: String, actualMs: Int, budgetMs: Int, overagePercent: Double)] {
        var bottlenecks: [(stageName: String, actualMs: Int, budgetMs: Int, overagePercent: Double)] = []

        for step in Step.allCases {
            guard let elapsed = stepElapsedTimes[step] else { continue }
            let budget = step.maxBudgetMs

            if elapsed > budget {
                let overagePercent = Double(elapsed - budget) / Double(budget) * 100
                bottlenecks.append((
                    stageName: step.rawValue,
                    actualMs: elapsed,
                    budgetMs: budget,
                    overagePercent: overagePercent
                ))
            }
        }

        return bottlenecks.sorted { $0.overagePercent > $1.overagePercent }
    }

    /// Returns total pipeline time in milliseconds (alias for compatibility).
    ///
    /// - Returns: Total pipeline time in ms
    func getTotalPipelineTime() -> Int {
        return getTotalTime() ?? 0
    }

    /// Checks if total pipeline time meets NFR2 (<15 seconds).
    ///
    /// - Returns: PassStatus based on NFR2 compliance
    func checkPipelineTimeCompliance() -> (status: PassStatus, totalMs: Int, budgetMs: Int, message: String?) {
        let budgetMs = 15000 // NFR2: 15 seconds
        let totalMs = getTotalPipelineTime()

        let status: PassStatus
        let message: String?

        if totalMs < 12000 {
            status = .pass
            message = nil
        } else if totalMs < budgetMs {
            status = .warn
            message = "Pipeline time (\(totalMs)ms) is approaching 15s limit"
        } else {
            status = .fail
            message = "Pipeline time (\(totalMs)ms) exceeds 15s limit by \(totalMs - budgetMs)ms"
        }

        return (status: status, totalMs: totalMs, budgetMs: budgetMs, message: message)
    }

    // MARK: - Memory Analysis (Story 3.9 Task 5)

    /// Returns memory trend analysis showing stages with largest memory increase.
    ///
    /// - Returns: Array of (stageName, memoryDeltaMB) sorted by delta descending
    func getMemoryTrendAnalysis() -> [(stageName: String, memoryDeltaMB: Double)] {
        var deltas: [(stageName: String, memoryDeltaMB: Double)] = []

        for step in Step.allCases {
            if let before = stepMemoryBefore[step], let after = stepMemoryAfter[step] {
                let delta = after - before
                deltas.append((stageName: step.rawValue, memoryDeltaMB: delta))
            }
        }

        return deltas.sorted { $0.memoryDeltaMB > $1.memoryDeltaMB }
    }

    /// Checks if peak memory usage meets NFR13 (<1.5GB).
    ///
    /// - Returns: (status, peakMB, limitMB, message)
    func checkMemoryCompliance() -> (status: PassStatus, peakMB: Double, limitMB: Double, message: String?) {
        let limitMB = 1500.0 // NFR13: 1.5GB
        let warnThresholdMB = 1200.0 // 1.2GB warning threshold
        let peakMB = peakMemoryUsage

        let status: PassStatus
        let message: String?

        if peakMB < warnThresholdMB {
            status = .pass
            message = nil
        } else if peakMB < limitMB {
            status = .warn
            message = "Peak memory (\(String(format: "%.0f", peakMB))MB) is approaching 1.5GB limit"
        } else {
            status = .fail
            message = "Peak memory (\(String(format: "%.0f", peakMB))MB) exceeds 1.5GB limit"
        }

        return (status: status, peakMB: peakMB, limitMB: limitMB, message: message)
    }

    /// Identifies stages with high memory usage (>100MB increase).
    ///
    /// - Returns: Array of stages that caused significant memory increase
    func identifyHighMemoryStages(thresholdMB: Double = 100.0) -> [(stageName: String, memoryDeltaMB: Double)] {
        return getMemoryTrendAnalysis().filter { $0.memoryDeltaMB > thresholdMB }
    }

    // MARK: - Accessors

    /// Returns the elapsed time for a step, or nil if not recorded.
    func elapsedTime(for step: Step) -> Int? {
        return stepElapsedTimes[step]
    }

    /// Returns total pipeline time in milliseconds, or nil if not complete.
    func totalTime() -> Int? {
        guard let startTime = pipelineStartTime else { return nil }
        return Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    /// Returns dictionary of all recorded step times.
    var allStepTimes: [Step: Int] {
        return stepElapsedTimes
    }
}

// MARK: - Convenience Extension for Memory Logging

#if DEBUG
extension ProcessingTimeLogger {
    /// Logs current memory usage at a step boundary.
    func logMemory(at step: Step) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usageMB = Double(info.resident_size) / (1024 * 1024)
            let peakMB = Double(info.resident_size_max) / (1024 * 1024)

            // Record snapshot (Story 3.9)
            memorySnapshotsData.append(MemorySnapshot(
                stage: step.rawValue,
                memoryMB: usageMB,
                timestamp: Date()
            ))
            peakMemoryUsage = max(peakMemoryUsage, usageMB)

            logger.debug("📊 Memory at \(step.rawValue): \(Int(usageMB))MB (peak: \(Int(peakMB))MB)")
        }
    }
}
#endif
