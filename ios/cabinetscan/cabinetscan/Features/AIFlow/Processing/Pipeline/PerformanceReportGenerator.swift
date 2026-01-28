//
//  PerformanceReportGenerator.swift
//  cabinetscan
//
//  Created for Story 3.9: Performance Validation
//  Generates comprehensive performance reports per Architecture 9.3
//

import Foundation
import UIKit

// MARK: - Performance Report Generator (Task 7)

/// Generates comprehensive performance reports with pass/fail analysis and optimization recommendations.
///
/// **Usage:**
/// ```swift
/// let generator = PerformanceReportGenerator()
/// let report = generator.generateReport(from: timeLogger, batteryMonitor: monitor)
/// let json = generator.exportJSON(report)
/// let summary = generator.generateSummary(report)
/// ```
final class PerformanceReportGenerator {

    // MARK: - NFR Thresholds

    /// NFR1: Depth inference <50ms per frame
    static let depthInferenceTargetMs = 50

    /// NFR2: Total processing <15 seconds
    static let totalProcessingTargetMs = 15000

    /// NFR13: Peak memory <1.5GB
    static let peakMemoryTargetMB = 1500.0

    /// NFR4: Battery drain <5%
    static let batteryDrainTargetPercent: Float = 5.0

    // MARK: - Report Generation

    /// Generates a comprehensive performance report.
    ///
    /// - Parameters:
    ///   - timeLogger: ProcessingTimeLogger with captured metrics
    ///   - batteryMonitor: Optional battery monitor with drain data
    ///   - captureMetrics: Optional capture-phase metrics
    /// - Returns: ComprehensiveReport with all analysis
    func generateReport(
        from timeLogger: ProcessingTimeLogger,
        batteryMonitor: BatteryMonitor? = nil,
        captureMetrics: CapturePhaseMetrics? = nil
    ) -> ComprehensiveReport {
        let processingMetrics = timeLogger.getMetrics()
        let bottlenecks = timeLogger.identifyBottlenecks()
        let memoryTrend = timeLogger.getMemoryTrendAnalysis()

        // Determine overall pass/fail status
        let pipelineCompliance = timeLogger.checkPipelineTimeCompliance()
        let memoryCompliance = timeLogger.checkMemoryCompliance()

        // Battery compliance (if available)
        let batteryDrain = batteryMonitor?.stopMonitoring() ?? 0
        let batteryStatus: PassStatus = batteryDrain < Self.batteryDrainTargetPercent ? .pass :
            (batteryDrain < Self.batteryDrainTargetPercent * 1.5 ? .warn : .fail)

        // Build optimization recommendations
        var recommendations: [OptimizationRecommendation] = []

        // Check total time
        if pipelineCompliance.status != .pass {
            recommendations.append(contentsOf: generateTimeOptimizations(bottlenecks: bottlenecks))
        }

        // Check memory
        if memoryCompliance.status != .pass {
            recommendations.append(contentsOf: generateMemoryOptimizations(memoryTrend: memoryTrend))
        }

        // Check battery
        if batteryStatus != .pass {
            recommendations.append(OptimizationRecommendation(
                category: .battery,
                severity: batteryStatus,
                issue: "Battery drain (\(String(format: "%.1f", batteryDrain))%) exceeds 5% target",
                recommendation: "Consider reducing GPU/Neural Engine duty cycle or lowering capture frame rate"
            ))
        }

        // Determine overall status
        let overallStatus: PassStatus = [pipelineCompliance.status, memoryCompliance.status, batteryStatus]
            .contains(.fail) ? .fail :
            ([pipelineCompliance.status, memoryCompliance.status, batteryStatus].contains(.warn) ? .warn : .pass)

        return ComprehensiveReport(
            deviceInfo: PerformanceDeviceInfo.current,
            timestamp: Date(),
            processingMetrics: processingMetrics,
            captureMetrics: captureMetrics,
            batteryDrainPercent: batteryDrain,
            bottlenecks: bottlenecks.map { Bottleneck(stageName: $0.stageName, actualMs: $0.actualMs, budgetMs: $0.budgetMs, overagePercent: $0.overagePercent) },
            memoryTrend: memoryTrend.map { MemoryTrendEntry(stageName: $0.stageName, deltaMB: $0.memoryDeltaMB) },
            pipelineTimeStatus: pipelineCompliance.status,
            memoryStatus: memoryCompliance.status,
            batteryStatus: batteryStatus,
            overallStatus: overallStatus,
            recommendations: recommendations
        )
    }

    // MARK: - JSON Export

    /// Exports report as JSON string.
    ///
    /// - Parameter report: Report to export
    /// - Returns: JSON string, or nil if encoding fails
    func exportJSON(_ report: ComprehensiveReport) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(report)
            return String(data: data, encoding: .utf8)
        } catch {
            #if DEBUG
            print("⚠️ PerformanceReportGenerator: Failed to encode report to JSON: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Human-Readable Summary

    /// Generates a human-readable summary of the report.
    ///
    /// - Parameter report: Report to summarize
    /// - Returns: Multi-line string summary
    func generateSummary(_ report: ComprehensiveReport) -> String {
        var lines: [String] = []

        lines.append("═══════════════════════════════════════════════════════════")
        lines.append("           PERFORMANCE VALIDATION REPORT")
        lines.append("═══════════════════════════════════════════════════════════")
        lines.append("")

        // Device info
        lines.append("Device: \(report.deviceInfo.model) (\(report.deviceInfo.iOSVersion))")
        lines.append("Date: \(ISO8601DateFormatter().string(from: report.timestamp))")
        lines.append("")

        // Overall status
        let statusEmoji = report.overallStatus == .pass ? "✅" : (report.overallStatus == .warn ? "⚠️" : "❌")
        lines.append("\(statusEmoji) OVERALL STATUS: \(report.overallStatus.rawValue.uppercased())")
        lines.append("")

        // NFR compliance table
        lines.append("───────────────────────────────────────────────────────────")
        lines.append("                   NFR COMPLIANCE")
        lines.append("───────────────────────────────────────────────────────────")

        let timeEmoji = report.pipelineTimeStatus == .pass ? "✅" : (report.pipelineTimeStatus == .warn ? "⚠️" : "❌")
        lines.append("\(timeEmoji) Total Processing Time: \(report.processingMetrics.totalTimeMs)ms (target: <\(Self.totalProcessingTargetMs)ms)")

        let memEmoji = report.memoryStatus == .pass ? "✅" : (report.memoryStatus == .warn ? "⚠️" : "❌")
        lines.append("\(memEmoji) Peak Memory: \(String(format: "%.0f", report.processingMetrics.peakMemoryMB))MB (target: <\(Int(Self.peakMemoryTargetMB))MB)")

        let batEmoji = report.batteryStatus == .pass ? "✅" : (report.batteryStatus == .warn ? "⚠️" : "❌")
        lines.append("\(batEmoji) Battery Drain: \(String(format: "%.1f", report.batteryDrainPercent))% (target: <\(Self.batteryDrainTargetPercent)%)")

        lines.append("")

        // Stage breakdown
        lines.append("───────────────────────────────────────────────────────────")
        lines.append("                   STAGE BREAKDOWN")
        lines.append("───────────────────────────────────────────────────────────")

        for stage in report.processingMetrics.stageMetrics {
            let stageEmoji = stage.status == .pass ? "✅" : (stage.status == .warn ? "⚠️" : "❌")
            let name = stage.name.padding(toLength: 25, withPad: " ", startingAt: 0)
            lines.append("\(stageEmoji) \(name): \(stage.durationMs)ms (\(String(format: "%.1f", stage.percentageOfTotal))%)")
        }

        lines.append("")

        // Bottlenecks
        if !report.bottlenecks.isEmpty {
            lines.append("───────────────────────────────────────────────────────────")
            lines.append("                   BOTTLENECKS")
            lines.append("───────────────────────────────────────────────────────────")

            for bottleneck in report.bottlenecks {
                lines.append("❌ \(bottleneck.stageName): \(bottleneck.actualMs)ms (budget: \(bottleneck.budgetMs)ms, +\(String(format: "%.0f", bottleneck.overagePercent))%)")
            }

            lines.append("")
        }

        // Recommendations
        if !report.recommendations.isEmpty {
            lines.append("───────────────────────────────────────────────────────────")
            lines.append("                   RECOMMENDATIONS")
            lines.append("───────────────────────────────────────────────────────────")

            for (index, rec) in report.recommendations.enumerated() {
                let emoji = rec.severity == .fail ? "🔴" : "🟡"
                lines.append("\(emoji) [\(rec.category.rawValue.uppercased())] \(rec.issue)")
                lines.append("   → \(rec.recommendation)")
                if index < report.recommendations.count - 1 {
                    lines.append("")
                }
            }

            lines.append("")
        }

        lines.append("═══════════════════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Optimization Recommendations

    private func generateTimeOptimizations(bottlenecks: [(stageName: String, actualMs: Int, budgetMs: Int, overagePercent: Double)]) -> [OptimizationRecommendation] {
        var recommendations: [OptimizationRecommendation] = []

        for bottleneck in bottlenecks {
            let recommendation: String

            switch bottleneck.stageName {
            case "depth_inference":
                recommendation = "Verify Neural Engine is being used (MLComputeUnits.all). Check model is FP16. Consider async batching."

            case "tsdf_fusion":
                recommendation = "Consider reducing voxel resolution. Enable Metal GPU acceleration. Process in batches."

            case "point_cloud_generation":
                recommendation = "Reduce frame count if over 60. Apply early downsampling. Use Metal compute shaders."

            case "model_loading":
                recommendation = "Pre-load model on app launch. Use lazy loading for secondary models."

            case "frame_extraction":
                recommendation = "Reduce extraction frame rate. Use hardware video decoding."

            default:
                recommendation = "Profile stage with Instruments to identify specific bottlenecks."
            }

            recommendations.append(OptimizationRecommendation(
                category: .timing,
                severity: bottleneck.overagePercent > 100 ? .fail : .warn,
                issue: "\(bottleneck.stageName) exceeds budget by \(String(format: "%.0f", bottleneck.overagePercent))%",
                recommendation: recommendation
            ))
        }

        return recommendations
    }

    private func generateMemoryOptimizations(memoryTrend: [(stageName: String, memoryDeltaMB: Double)]) -> [OptimizationRecommendation] {
        var recommendations: [OptimizationRecommendation] = []

        let highMemoryStages = memoryTrend.filter { $0.memoryDeltaMB > 100 }

        for stage in highMemoryStages {
            let recommendation: String

            switch stage.stageName {
            case "depth_inference":
                recommendation = "Release depth frames after point cloud generation. Use autoreleasepool around batch operations."

            case "point_cloud_generation":
                recommendation = "Downsample point clouds earlier. Release source depth data after conversion."

            case "tsdf_fusion":
                recommendation = "Use streaming fusion instead of batch. Release point clouds after integration."

            default:
                recommendation = "Use autoreleasepool around memory-intensive operations. Consider progressive processing."
            }

            recommendations.append(OptimizationRecommendation(
                category: .memory,
                severity: stage.memoryDeltaMB > 200 ? .fail : .warn,
                issue: "\(stage.stageName) uses \(String(format: "%.0f", stage.memoryDeltaMB))MB",
                recommendation: recommendation
            ))
        }

        return recommendations
    }
}

// MARK: - Report Data Structures

/// Comprehensive performance report with all metrics and analysis.
struct ComprehensiveReport: Codable {
    let deviceInfo: PerformanceDeviceInfo
    let timestamp: Date
    let processingMetrics: PerformanceMetrics
    let captureMetrics: CapturePhaseMetrics?
    let batteryDrainPercent: Float
    let bottlenecks: [Bottleneck]
    let memoryTrend: [MemoryTrendEntry]
    let pipelineTimeStatus: PassStatus
    let memoryStatus: PassStatus
    let batteryStatus: PassStatus
    let overallStatus: PassStatus
    let recommendations: [OptimizationRecommendation]
}

/// Device information for performance report context.
struct PerformanceDeviceInfo: Codable {
    let model: String
    let iOSVersion: String
    let availableMemoryMB: Double
    let isSimulator: Bool

    static var current: PerformanceDeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }

        // Thread-safe access to UIDevice (must be accessed from main thread)
        let iOSVersion: String
        if Thread.isMainThread {
            iOSVersion = UIDevice.current.systemVersion
        } else {
            iOSVersion = DispatchQueue.main.sync {
                UIDevice.current.systemVersion
            }
        }

        return PerformanceDeviceInfo(
            model: model,
            iOSVersion: iOSVersion,
            availableMemoryMB: Double(os_proc_available_memory()) / (1024 * 1024),
            isSimulator: ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
        )
    }
}

/// Capture phase metrics (video/photo capture).
struct CapturePhaseMetrics: Codable {
    let videoDurationSeconds: Double
    let framesCaptured: Int
    let photosCount: Int
    let averageFrameRate: Double
}

/// Bottleneck stage information.
struct Bottleneck: Codable {
    let stageName: String
    let actualMs: Int
    let budgetMs: Int
    let overagePercent: Double
}

/// Memory trend entry for a single stage.
struct MemoryTrendEntry: Codable {
    let stageName: String
    let deltaMB: Double
}

/// Optimization recommendation.
struct OptimizationRecommendation: Codable {
    let category: OptimizationCategory
    let severity: PassStatus
    let issue: String
    let recommendation: String
}

/// Category of optimization.
enum OptimizationCategory: String, Codable {
    case timing
    case memory
    case battery
}

// MARK: - PerformanceMetrics Codable Extension

extension PerformanceMetrics: Codable {
    enum CodingKeys: String, CodingKey {
        case deviceModel, iOSVersion, availableMemoryMB, totalTimeMs
        case stageMetrics, memorySnapshots, peakMemoryMB, timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(iOSVersion, forKey: .iOSVersion)
        try container.encode(availableMemoryMB, forKey: .availableMemoryMB)
        try container.encode(totalTimeMs, forKey: .totalTimeMs)
        try container.encode(stageMetrics.map { StageMetricCodable(from: $0) }, forKey: .stageMetrics)
        try container.encode(memorySnapshots.map { MemorySnapshotCodable(from: $0) }, forKey: .memorySnapshots)
        try container.encode(peakMemoryMB, forKey: .peakMemoryMB)
        try container.encode(timestamp, forKey: .timestamp)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        iOSVersion = try container.decode(String.self, forKey: .iOSVersion)
        availableMemoryMB = try container.decode(Double.self, forKey: .availableMemoryMB)
        totalTimeMs = try container.decode(Int.self, forKey: .totalTimeMs)
        let stageMetricsCodable = try container.decode([StageMetricCodable].self, forKey: .stageMetrics)
        stageMetrics = stageMetricsCodable.map { $0.toStageMetric() }
        let memorySnapshotsCodable = try container.decode([MemorySnapshotCodable].self, forKey: .memorySnapshots)
        memorySnapshots = memorySnapshotsCodable.map { $0.toMemorySnapshot() }
        peakMemoryMB = try container.decode(Double.self, forKey: .peakMemoryMB)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

// Helper for Codable
private struct StageMetricCodable: Codable {
    let name: String
    let durationMs: Int
    let budgetMs: Int
    let memoryBeforeMB: Double
    let memoryAfterMB: Double
    let percentageOfTotal: Double
    let status: PassStatus

    init(from metric: StageMetric) {
        name = metric.name
        durationMs = metric.durationMs
        budgetMs = metric.budgetMs
        memoryBeforeMB = metric.memoryBeforeMB
        memoryAfterMB = metric.memoryAfterMB
        percentageOfTotal = metric.percentageOfTotal
        status = metric.status
    }

    func toStageMetric() -> StageMetric {
        StageMetric(name: name, durationMs: durationMs, budgetMs: budgetMs,
                    memoryBeforeMB: memoryBeforeMB, memoryAfterMB: memoryAfterMB,
                    percentageOfTotal: percentageOfTotal, status: status)
    }
}

private struct MemorySnapshotCodable: Codable {
    let stage: String
    let memoryMB: Double
    let timestamp: Date

    init(from snapshot: MemorySnapshot) {
        stage = snapshot.stage
        memoryMB = snapshot.memoryMB
        timestamp = snapshot.timestamp
    }

    func toMemorySnapshot() -> MemorySnapshot {
        MemorySnapshot(stage: stage, memoryMB: memoryMB, timestamp: timestamp)
    }
}
