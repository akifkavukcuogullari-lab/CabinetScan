//
//  AIMeasurementDataBuilder.swift
//  cabinetscan
//
//  Created for Story 5.3: MeasurementData Builder
//  Updated for Story 5.4: MeasurementData Model Extension
//

import Foundation
import UIKit
import os.log

// MARK: - AI Measurement Data Builder

/// Converts AI pipeline results to MeasurementData format.
///
/// This builder is the critical bridge between AI detection outputs and
/// the existing app infrastructure. It produces a `MeasurementData` object
/// identical in structure to the LiDAR flow, ensuring downstream screens
/// (Selection, Review, Submission) work unchanged.
///
/// **Usage:**
/// ```swift
/// let builder = AIMeasurementDataBuilder()
/// let measurementData = builder.build(
///     from: pipelineResult,
///     captureSession: sessionData,
///     floorPlanImageURL: pngURL,
///     floorPlanJSON: jsonData
/// )
/// ```
///
/// **Key Design Decisions:**
/// - Story 5.4: Populates top-level `scanMethod` and `aiMetadata` fields on MeasurementData
/// - AI metadata is ALSO embedded in `measurements` dictionary for webhook backward compatibility
/// - Never throws - always produces valid (possibly incomplete) MeasurementData
/// - Handles nil inputs gracefully
final class AIMeasurementDataBuilder {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "com.cabinetscan.aiflow", category: "MeasurementDataBuilder")

    // MARK: - Constants

    private enum Constants {
        static let defaultRoomName = "Kitchen"
        static let defaultRoomType = "kitchen"
        static let scanMethod = "aiFlow"
        static let lowConfidenceThreshold: Float = 0.6
        static let schemaVersion = "1.0"
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Main Build Method

    /// Builds MeasurementData from AI pipeline results.
    ///
    /// This is the primary entry point for converting AI detection results
    /// to the MeasurementData format used by downstream screens.
    ///
    /// - Parameters:
    ///   - pipelineResult: The completed AI pipeline result
    ///   - captureSession: Optional capture session with video/photo URLs
    ///   - floorPlanImageURL: URL to the generated floor plan PNG
    ///   - floorPlanJSON: The generated floor plan JSON structure
    /// - Returns: MeasurementData ready for downstream use
    func build(
        from pipelineResult: AIPipelineResult,
        captureSession: AICaptureSessionData? = nil,
        floorPlanImageURL: URL? = nil,
        floorPlanJSON: FloorPlanJSON? = nil
    ) -> MeasurementData {
        // 1. Extract room data
        let roomName = Constants.defaultRoomName
        let roomType = Constants.defaultRoomType

        // 2. Calculate totals
        let totalLinearFt = calculateTotalLinearFeet(from: pipelineResult)
        let totalSqFt = calculateTotalSquareFeet(from: pipelineResult.roomStructure)

        // 3. Extract counts
        let wallCount = extractWallCount(from: pipelineResult)
        let windowCount = pipelineResult.detectedOpenings?.windows.count ?? 0
        let doorCount = pipelineResult.detectedOpenings?.doors.count ?? 0

        // 4. Build roomplanData dictionary
        let roomplanData = buildRoomplanData(from: pipelineResult)

        // 5. Build measurements dictionary (includes AI metadata)
        let measurements = buildMeasurements(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // 6. Extract video metadata from capture session
        let videoMetadata = extractVideoMetadata(from: captureSession)

        // 7. Build AIMetadata struct (Story 5.4)
        let aiMetadata = buildAIMetadata(from: pipelineResult)

        // 8. Build and return MeasurementData
        return MeasurementData(
            roomName: roomName,
            roomType: roomType,
            roomplanData: roomplanData,
            totalLinearFt: totalLinearFt,
            totalSqFt: totalSqFt,
            wallCount: wallCount,
            windowCount: windowCount,
            doorCount: doorCount,
            measurements: measurements,
            usdzFileUrl: nil,  // AI flow doesn't generate USDZ
            glbFileUrl: nil,   // AI flow doesn't generate GLB
            previewImageUrl: floorPlanImageURL?.absoluteString,
            videoUrl: captureSession?.videoURL?.absoluteString,
            videoThumbnailUrl: videoMetadata.thumbnailUrl,
            videoDurationSeconds: videoMetadata.durationSeconds,
            videoSizeBytes: videoMetadata.sizeBytes,
            videoResolution: videoMetadata.resolution,
            videoFormat: videoMetadata.format,
            visualizationPhotoUrls: extractPhotoUrls(from: captureSession),
            scanMethod: .aiFlow,  // Story 5.4: AI flow identification
            aiMetadata: aiMetadata  // Story 5.4: Type-safe AI metadata
        )
    }

    // MARK: - AI Metadata Building (Story 5.4)

    /// Builds type-safe AIMetadata struct from pipeline result.
    ///
    /// This method creates the AIMetadata struct for the top-level MeasurementData field.
    /// Note: The measurements dictionary still contains `ai_metadata` for webhook compatibility.
    ///
    /// - Parameter pipelineResult: Pipeline result with all detection data
    /// - Returns: AIMetadata struct with all fields populated
    private func buildAIMetadata(from pipelineResult: AIPipelineResult) -> AIMetadata {
        let overallConfidence = calculateOverallConfidence(from: pipelineResult)

        // Story 6.2: Prefer capture phase coverage (from zones) over fusion quality coverage
        // Capture coverage reflects user scanning behavior, fusion coverage reflects 3D data quality
        let coverageValue: Double
        if let captureCoverage = pipelineResult.coveragePercentage {
            coverageValue = Double(captureCoverage)
        } else {
            coverageValue = Double(pipelineResult.fusionQuality.coveragePercentage)
        }

        // Story 6.2: Collect all warnings including confidence scorer coverage warnings
        var allWarnings = pipelineResult.warnings.map { $0.message }
        if let confidenceResult = pipelineResult.confidenceScores {
            allWarnings.append(contentsOf: confidenceResult.warnings)
        }

        return AIMetadata(
            calibrationMethod: calibrationMethodString(pipelineResult.calibration.calibrationMethod),
            calibrationConfidence: Double(pipelineResult.calibration.confidenceLevel.numericValue),
            overallConfidence: Double(overallConfidence.numericValue),
            processingTimeMs: pipelineResult.processingTimeMs,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: overallConfidence.numericValue < Constants.lowConfidenceThreshold,
            frameCount: pipelineResult.frameCount,
            photoCount: pipelineResult.photoCount,
            scaleFactor: Double(pipelineResult.calibration.scaleFactor),
            coveragePercentage: coverageValue,
            warnings: allWarnings.isEmpty ? nil : allWarnings
        )
    }

    // MARK: - Calculation Methods

    /// Calculates total linear feet from cabinet detection.
    ///
    /// Total linear feet = base cabinets + upper cabinets (per existing formula).
    /// Note: Tall cabinets are NOT included in this total per the original spec.
    ///
    /// - Parameter pipelineResult: Pipeline result with cabinet detection
    /// - Returns: Total linear feet, or 0 if no cabinets detected
    private func calculateTotalLinearFeet(from pipelineResult: AIPipelineResult) -> Double {
        guard let cabinets = pipelineResult.detectedCabinets else { return 0 }
        return Double(cabinets.baseLinearFeetTotal + cabinets.upperLinearFeetTotal)
    }

    /// Calculates total square feet from room structure.
    ///
    /// - Parameter roomStructure: Room structure with dimensions
    /// - Returns: Total square feet, or 0 if no room structure
    private func calculateTotalSquareFeet(from roomStructure: AIRoomStructure?) -> Double {
        guard let room = roomStructure else { return 0 }
        return room.dimensions.areaSquareFeet
    }

    /// Extracts wall count from room structure or opening detection.
    ///
    /// - Parameter pipelineResult: Pipeline result
    /// - Returns: Wall count, or nil if unknown
    private func extractWallCount(from pipelineResult: AIPipelineResult) -> Int? {
        // Prefer room structure walls
        if let roomStructure = pipelineResult.roomStructure {
            return roomStructure.walls.count
        }
        // Fallback to walls array from constraints
        return pipelineResult.walls.isEmpty ? nil : pipelineResult.walls.count
    }

    // MARK: - Dictionary Building Methods

    /// Builds roomplanData dictionary matching LiDAR format.
    ///
    /// - Parameter pipelineResult: Pipeline result
    /// - Returns: Dictionary with wall, door, window, floor, opening counts
    private func buildRoomplanData(from pipelineResult: AIPipelineResult) -> [String: AnyCodable] {
        let walls = pipelineResult.roomStructure?.walls.count ?? pipelineResult.walls.count
        let doors = pipelineResult.detectedOpenings?.doors.count ?? 0
        let windows = pipelineResult.detectedOpenings?.windows.count ?? 0
        let openings = pipelineResult.roomStructure?.openBoundaries.count ?? 0

        return [
            "walls": AnyCodable(walls),
            "doors": AnyCodable(doors),
            "windows": AnyCodable(windows),
            "floors": AnyCodable(1),
            "openings": AnyCodable(openings)
        ]
    }

    /// Builds measurements dictionary from FloorPlanJSON or pipeline result.
    ///
    /// If FloorPlanJSON is available, converts it to dictionary format.
    /// Otherwise, builds minimal measurements from pipeline result.
    /// AI metadata is always embedded under "ai_metadata" key (per Story 5.3 spec).
    /// Countertop totals are always included under "countertop_totals" key (per Story 5.5 spec).
    ///
    /// - Parameters:
    ///   - pipelineResult: Pipeline result
    ///   - floorPlanJSON: Optional floor plan JSON from Story 5.2
    /// - Returns: Measurements dictionary
    private func buildMeasurements(
        from pipelineResult: AIPipelineResult,
        floorPlanJSON: FloorPlanJSON?
    ) -> [String: AnyCodable] {
        var measurements: [String: AnyCodable]

        // If we have FloorPlanJSON, use its measurements
        if let json = floorPlanJSON {
            measurements = convertFloorPlanJSONToMeasurements(json, pipelineResult: pipelineResult)
        } else {
            // Fallback: Build minimal measurements
            measurements = buildMinimalMeasurements(from: pipelineResult)
        }

        // Story 5.5: Add countertop totals (AC7)
        // Always add countertop_totals for consistent downstream access
        let countertopTotals = buildCountertopTotalsRaw(from: pipelineResult.detectedCountertops)
        measurements["countertop_totals"] = AnyCodable(countertopTotals)

        return measurements
    }

    /// Converts FloorPlanJSON to measurements dictionary.
    ///
    /// - Parameters:
    ///   - json: FloorPlanJSON from Story 5.2
    ///   - pipelineResult: Pipeline result for additional metadata
    /// - Returns: Measurements dictionary
    private func convertFloorPlanJSONToMeasurements(
        _ json: FloorPlanJSON,
        pipelineResult: AIPipelineResult
    ) -> [String: AnyCodable] {
        // Convert FloorPlanJSON.measurements to dictionary
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        // Try to encode the measurements section
        if let data = try? encoder.encode(json.measurements),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result = dict.mapValues { AnyCodable($0) }

            // Ensure scan_method is set
            result["scan_method"] = AnyCodable(Constants.scanMethod)

            // Ensure AI metadata is present with additional pipeline info
            result["ai_metadata"] = buildAIMetadataAnyCodable(from: pipelineResult)

            return result
        }

        // If encoding fails, fall back to minimal measurements
        return buildMinimalMeasurements(from: pipelineResult)
    }

    /// Builds minimal measurements dictionary when FloorPlanJSON is not available.
    ///
    /// - Parameter pipelineResult: Pipeline result
    /// - Returns: Minimal measurements dictionary
    private func buildMinimalMeasurements(from pipelineResult: AIPipelineResult) -> [String: AnyCodable] {
        var measurements: [String: AnyCodable] = [:]

        // Scan method (AC2)
        measurements["scan_method"] = AnyCodable(Constants.scanMethod)

        // AI metadata (AC2, AC4, AC5)
        measurements["ai_metadata"] = buildAIMetadataAnyCodable(from: pipelineResult)

        // Room dimensions
        if let room = pipelineResult.roomStructure {
            measurements["room"] = AnyCodable([
                "width_ft": room.dimensions.widthFeet,
                "depth_ft": room.dimensions.lengthFeet,
                "ceiling_height_ft": room.dimensions.ceilingHeightInches / 12.0,
                "area_sq_ft": room.dimensions.areaSquareFeet,
                "shape": room.roomShape.rawValue,
                "confidence": room.confidence.level.rawValue
            ])
        }

        // Cabinet summary (AC3)
        if let cabinets = pipelineResult.detectedCabinets {
            // Calculate tall cabinet linear feet manually (not a property on CabinetDetectionResult)
            let tallLinearFeet = cabinets.tallCabinets.reduce(0.0) { $0 + Double($1.widthInches) / 12.0 }

            measurements["ai_summary"] = AnyCodable([
                "cabinet_counts": [
                    "upper": cabinets.upperCabinets.count,
                    "lower": cabinets.baseCabinets.count,
                    "tall": cabinets.tallCabinets.count,
                    "corner": cabinets.cornerCabinets.count
                ],
                "linear_feet": [
                    "upper": cabinets.upperLinearFeetTotal,
                    "lower": cabinets.baseLinearFeetTotal,
                    "tall": tallLinearFeet
                ]
            ])
        }

        // Countertop summary (AC3)
        // NOTE: This creates measurements["countertops"] with area totals.
        // Story 5.5 also adds measurements["countertop_totals"] with linear feet and backsplash.
        // Both keys intentionally coexist per ADR-5.5:
        // - "countertops": Legacy format for webhook backward compatibility
        // - "countertop_totals": Complete totals for downstream quote screens (FR28)
        if let countertops = pipelineResult.detectedCountertops {
            let wallNetSqFt = Double(countertops.countertopSummary.wallNetAreaSquareInches) / 144.0
            let islandSqFt = Double(countertops.countertopSummary.islandTotalSquareInches) / 144.0
            let peninsulaSqFt = Double(countertops.countertopSummary.peninsulaTotalSquareInches) / 144.0
            let totalSqFt = wallNetSqFt + islandSqFt + peninsulaSqFt

            measurements["countertops"] = AnyCodable([
                "wall_net_area_sq_ft": wallNetSqFt,
                "island_total_sq_ft": islandSqFt,
                "peninsula_total_sq_ft": peninsulaSqFt,
                "total_sq_ft": totalSqFt
            ])
        }

        return measurements
    }

    /// Builds AI metadata dictionary for embedding in measurements.
    ///
    /// Per AC2, AC4, AC5: includes scan method, confidence scores, calibration,
    /// device info, and needsVerification flag.
    ///
    /// - Parameter pipelineResult: Pipeline result
    /// - Returns: AI metadata as AnyCodable
    private func buildAIMetadataAnyCodable(from pipelineResult: AIPipelineResult) -> AnyCodable {
        var metadata: [String: Any] = [:]

        // Schema version (ADR-005)
        metadata["schema_version"] = Constants.schemaVersion

        // Scan method (AC2)
        metadata["scan_method"] = Constants.scanMethod

        // Overall confidence (AC4)
        let overallConfidence = calculateOverallConfidence(from: pipelineResult)
        metadata["overall_confidence"] = overallConfidence.rawValue
        metadata["confidence_score"] = overallConfidence.numericValue

        // Component confidence scores
        if let roomStructure = pipelineResult.roomStructure {
            metadata["room_confidence_score"] = roomStructure.confidence.overall
        }
        if let cabinets = pipelineResult.detectedCabinets {
            metadata["cabinet_confidence_score"] = cabinets.overallConfidence.numericValue
        }
        if let appliances = pipelineResult.detectedAppliances {
            metadata["appliance_confidence_score"] = appliances.overallConfidence.numericValue
        }

        // Calibration method (AC5)
        metadata["calibration_method"] = calibrationMethodString(pipelineResult.calibration.calibrationMethod)

        // Processing time (AC5)
        metadata["processing_time_ms"] = pipelineResult.processingTimeMs

        // Device info (AC5)
        metadata["device_model"] = UIDevice.current.model
        metadata["ios_version"] = UIDevice.current.systemVersion
        metadata["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // Frame and photo counts
        metadata["frame_count"] = pipelineResult.frameCount
        metadata["photo_count"] = pipelineResult.photoCount

        // Needs verification flag (AC4)
        let needsVerification = overallConfidence.numericValue < Constants.lowConfidenceThreshold
        metadata["needs_verification"] = needsVerification

        // Scale factor
        metadata["scale_factor"] = pipelineResult.calibration.scaleFactor

        // Fusion quality metrics
        metadata["coverage_percentage"] = pipelineResult.fusionQuality.coveragePercentage
        metadata["coverage_quality"] = pipelineResult.coverageQuality.displayText

        // Warnings
        if !pipelineResult.warnings.isEmpty {
            metadata["warnings"] = pipelineResult.warnings.map { $0.message }
        }

        return AnyCodable(metadata)
    }

    /// Converts calibration method to string for JSON output.
    ///
    /// - Parameter method: Calibration method
    /// - Returns: String representation
    private func calibrationMethodString(_ method: AICalibrationMethod) -> String {
        switch method {
        case .autoCountertop: return "autoCountertop"
        case .autoCeiling: return "autoCeiling"
        case .manualDoor: return "manualDoor"
        case .manualCeiling: return "manualCeiling"
        case .failed: return "failed"
        }
    }

    /// Calculates overall confidence from pipeline result.
    ///
    /// Considers room structure, cabinet detection, and other detection confidences.
    ///
    /// - Parameter pipelineResult: Pipeline result
    /// - Returns: Overall confidence level
    private func calculateOverallConfidence(from pipelineResult: AIPipelineResult) -> AIConfidenceLevel {
        var confidenceScores: [Float] = []

        // Room structure confidence
        if let room = pipelineResult.roomStructure {
            confidenceScores.append(room.confidence.overall)
        }

        // Cabinet detection confidence
        if let cabinets = pipelineResult.detectedCabinets {
            confidenceScores.append(cabinets.overallConfidence.numericValue)
        }

        // Appliance detection confidence
        if let appliances = pipelineResult.detectedAppliances {
            confidenceScores.append(appliances.overallConfidence.numericValue)
        }

        // Countertop detection confidence
        if let countertops = pipelineResult.detectedCountertops {
            confidenceScores.append(countertops.overallConfidence.numericValue)
        }

        // If no confidence scores, return low
        guard !confidenceScores.isEmpty else { return .low }

        // Calculate average
        let average = confidenceScores.reduce(0, +) / Float(confidenceScores.count)

        // Map to confidence level
        if average >= 0.8 {
            return .high
        } else if average >= 0.6 {
            return .medium
        } else {
            return .low
        }
    }

    // MARK: - Countertop Totals Calculation (Story 5.5)

    /// Builds countertop totals summary for MeasurementData (raw dictionary).
    ///
    /// Per FR28, provides summary totals for quote generation:
    /// - Wall countertop linear feet and square feet (AC1, AC2)
    /// - Island countertop square feet (AC3)
    /// - Peninsula countertop square feet (AC4)
    /// - Backsplash linear feet (AC5)
    /// - Total countertop square feet (AC6)
    ///
    /// - Parameter countertopResult: Result from CountertopDetector (Story 4.6)
    /// - Returns: Dictionary with countertop totals in feet units
    private func buildCountertopTotalsRaw(from countertopResult: CountertopDetectorResult?) -> [String: Double] {
        // Handle nil/empty - return zeros (AC8)
        guard let result = countertopResult, result.hasDetections else {
            // Task 3.4: Log warning when no countertops detected (not surfaced to user)
            if countertopResult == nil {
                Self.logger.info("No countertop detection result available - returning zero totals")
            } else {
                Self.logger.info("Countertop detection has no detections (empty arrays) - returning zero totals")
            }
            return [
                "wall_linear_ft": 0.0,
                "wall_sq_ft": 0.0,
                "island_sq_ft": 0.0,
                "peninsula_sq_ft": 0.0,
                "backsplash_linear_ft": 0.0,
                "total_sq_ft": 0.0
            ]
        }

        let summary = result.countertopSummary

        // Wall countertop totals (use NET area - after cutouts) (AC1, AC2)
        let wallLinearFt = Double(summary.wallTotalLinearInches) / 12.0
        let wallSqFt = Double(summary.wallNetAreaSquareInches) / 144.0

        // Island and peninsula totals (from Story 4.5) (AC3, AC4)
        let islandSqFt = Double(summary.islandTotalSquareInches) / 144.0
        let peninsulaSqFt = Double(summary.peninsulaTotalSquareInches) / 144.0

        // Backsplash (windows already excluded by CountertopDetector) (AC5)
        let backsplashLinearFt = Double(result.backsplashSummary.linearInches) / 12.0

        // Total countertop (net total) (AC6)
        let totalSqFt = wallSqFt + islandSqFt + peninsulaSqFt

        return [
            "wall_linear_ft": wallLinearFt,
            "wall_sq_ft": wallSqFt,
            "island_sq_ft": islandSqFt,
            "peninsula_sq_ft": peninsulaSqFt,
            "backsplash_linear_ft": backsplashLinearFt,
            "total_sq_ft": totalSqFt
        ]
    }

    // MARK: - Video Metadata Extraction

    /// Video metadata tuple
    private struct VideoMetadata {
        let thumbnailUrl: String?
        let durationSeconds: Int?
        let sizeBytes: Int64?
        let resolution: String?
        let format: String?
    }

    /// Extracts video metadata from capture session.
    ///
    /// - Parameter captureSession: Capture session data
    /// - Returns: Video metadata
    private func extractVideoMetadata(from captureSession: AICaptureSessionData?) -> VideoMetadata {
        guard let session = captureSession,
              let metadata = session.metadata else {
            return VideoMetadata(
                thumbnailUrl: nil,
                durationSeconds: nil,
                sizeBytes: nil,
                resolution: nil,
                format: nil
            )
        }

        // Calculate video size if video URL is available
        var sizeBytes: Int64?
        if let videoURL = session.videoURL {
            sizeBytes = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size]) as? Int64
        }

        return VideoMetadata(
            thumbnailUrl: nil,  // Thumbnail URL would be generated separately
            durationSeconds: Int(metadata.videoDuration),
            sizeBytes: sizeBytes,
            resolution: nil,  // Resolution would need to be extracted from video file
            format: "mp4"
        )
    }

    /// Extracts photo URLs from capture session.
    ///
    /// - Parameter captureSession: Capture session data
    /// - Returns: Array of photo URL strings, or nil
    private func extractPhotoUrls(from captureSession: AICaptureSessionData?) -> [String]? {
        guard let session = captureSession, !session.photos.isEmpty else {
            return nil
        }
        return session.photos.map { $0.url.absoluteString }
    }
}

// MARK: - AIConfidenceLevel Extension

extension AIConfidenceLevel {
    /// Numeric value for confidence level (for calculations)
    var numericValue: Float {
        switch self {
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.4
        }
    }
}

