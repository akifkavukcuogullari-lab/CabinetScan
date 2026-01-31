//
//  AIOutputAdapter.swift
//  cabinetscan
//
//  Created for Story 5.6: AI Output Adapter
//

import Foundation
import os.log

// MARK: - Output Adapter Result

/// Result of AI output adaptation process.
///
/// Contains the adapted MeasurementData, floor plan URL, and validation status.
/// Used to bridge AI pipeline output to downstream app screens.
struct AIOutputAdapterResult {
    /// Adapted measurement data ready for downstream use
    let measurementData: MeasurementData

    /// URL to the generated floor plan PNG (in temp directory)
    let floorPlanURL: URL?

    /// Validation result with errors and warnings
    let validationResult: AIOutputValidationResult

    /// Whether the output is valid for downstream use
    var isValid: Bool { validationResult.isValid }

    /// Validation warnings (non-blocking issues)
    var warnings: [String] { validationResult.warnings }
}

// MARK: - Validation Result

/// Validation result for AI output.
///
/// Contains validation status, errors (blocking), and warnings (non-blocking).
struct AIOutputValidationResult {
    /// Whether the output passed validation (no errors)
    let isValid: Bool

    /// Validation errors (blocking - prevent downstream use)
    let errors: [String]

    /// Validation warnings (non-blocking - may need user attention)
    let warnings: [String]

    /// Convenience for valid result with no issues
    static let valid = AIOutputValidationResult(isValid: true, errors: [], warnings: [])

    /// Convenience for invalid result with specified errors
    static func invalid(errors: [String]) -> AIOutputValidationResult {
        AIOutputValidationResult(isValid: false, errors: errors, warnings: [])
    }
}

// MARK: - Output Adapter Errors

/// Errors specific to AI output adaptation.
///
/// Each error has a user-friendly description suitable for UI display.
enum AIOutputError: LocalizedError {
    /// Floor plan rendering failed
    case renderingFailed(String)

    /// JSON generation failed
    case jsonGenerationFailed(String)

    /// Output validation failed
    case validationFailed([String])

    /// No room structure detected in pipeline result
    case noRoomStructure

    var errorDescription: String? {
        switch self {
        case .renderingFailed(let reason):
            return "Could not generate floor plan: \(reason)"
        case .jsonGenerationFailed(let reason):
            return "Could not prepare measurement data: \(reason)"
        case .validationFailed(let errors):
            return "Output validation failed: \(errors.joined(separator: ", "))"
        case .noRoomStructure:
            return "No room structure detected - please try scanning again"
        }
    }
}

// MARK: - AI Output Adapter

/// Adapts AI pipeline output for downstream app consumption.
///
/// This adapter orchestrates the conversion of AI pipeline results into
/// the MeasurementData format expected by Selection, Review, and Submission screens.
/// It ensures AI scans are indistinguishable from LiDAR scans in downstream processing.
///
/// **Architecture Pattern:** Facade Pattern - simplifies complex subsystem operations.
///
/// **Data Flow:**
/// ```
/// AIPipelineResult (from Epic 3/4)
///         ↓
/// AIOutputAdapter.adapt()
///         ↓
/// ┌───────┴───────┐
/// ↓               ↓
/// Renderer    JSONGenerator
/// (PNG)         (JSON)
/// └───────┬───────┘
///         ↓
/// MeasurementDataBuilder
///         ↓
/// validateOutput()
///         ↓
/// AIOutputAdapterResult
/// ```
///
/// **Usage:**
/// ```swift
/// let adapter = AIOutputAdapter()
/// let result = try await adapter.adapt(
///     pipelineResult: pipelineResult,
///     captureSession: captureSessionData
/// )
/// appState.setMeasurementData(result.measurementData)
/// ```
final class AIOutputAdapter {

    // MARK: - Dependencies

    private let renderer: AIFloorPlanRenderer
    private let jsonGenerator: AIFloorPlanJSONGenerator
    private let measurementBuilder: AIMeasurementDataBuilder
    private let logger = Logger(subsystem: "com.cabinetscan.aiflow", category: "OutputAdapter")

    // MARK: - Constants

    private enum Constants {
        /// Confidence threshold below which warnings are generated
        static let lowConfidenceThreshold: Double = 0.6

        /// Very low confidence threshold for stronger warning
        static let veryLowConfidenceThreshold: Double = 0.5
    }

    // MARK: - Initialization

    /// Creates an output adapter with default dependencies.
    init() {
        self.renderer = AIFloorPlanRenderer()
        self.jsonGenerator = AIFloorPlanJSONGenerator()
        self.measurementBuilder = AIMeasurementDataBuilder()
    }

    /// Creates an output adapter with custom dependencies (for testing).
    ///
    /// - Parameters:
    ///   - renderer: Floor plan renderer
    ///   - jsonGenerator: JSON generator
    ///   - measurementBuilder: Measurement data builder
    init(
        renderer: AIFloorPlanRenderer,
        jsonGenerator: AIFloorPlanJSONGenerator,
        measurementBuilder: AIMeasurementDataBuilder
    ) {
        self.renderer = renderer
        self.jsonGenerator = jsonGenerator
        self.measurementBuilder = measurementBuilder
    }

    // MARK: - Main Adaptation Method

    /// Adapts AI pipeline results for downstream consumption.
    ///
    /// This method:
    /// 1. Validates minimum required data exists
    /// 2. Generates floor plan PNG via renderer
    /// 3. Generates floor plan JSON via generator
    /// 4. Builds MeasurementData via builder
    /// 5. Validates output completeness
    /// 6. Returns result with validation status
    ///
    /// - Parameters:
    ///   - pipelineResult: Completed AI pipeline result
    ///   - captureSession: Optional capture session with video/photo data
    /// - Returns: Adapted result with MeasurementData and validation status
    /// - Throws: AIOutputError if critical adaptation steps fail
    func adapt(
        pipelineResult: AIPipelineResult,
        captureSession: AICaptureSessionData? = nil
    ) async throws -> AIOutputAdapterResult {
        logger.info("Starting output adaptation")
        let startTime = Date()

        // 1. Validate minimum required data
        guard let roomStructure = pipelineResult.roomStructure else {
            logger.error("No room structure in pipeline result")
            throw AIOutputError.noRoomStructure
        }

        // 2. Generate floor plan PNG
        // Story 6.2: Pass uncaptured zones for hatched area rendering
        let floorPlanURL: URL?
        do {
            let renderResult = try await renderer.render(
                roomStructure: roomStructure,
                cabinets: pipelineResult.detectedCabinets,
                appliances: pipelineResult.detectedAppliances,
                islandsPeninsulas: pipelineResult.detectedIslandsPeninsulas,
                openings: pipelineResult.detectedOpenings,
                countertops: pipelineResult.detectedCountertops,
                uncapturedZones: pipelineResult.uncapturedZones,
                coveragePercentage: pipelineResult.coveragePercentage
            )

            // Save PNG to temp directory
            floorPlanURL = try saveFloorPlanToTemp(pngData: renderResult.pngData)
            logger.info("Floor plan rendered: \(floorPlanURL?.lastPathComponent ?? "nil")")
        } catch {
            logger.error("Floor plan rendering failed: \(error.localizedDescription)")
            throw AIOutputError.renderingFailed(error.localizedDescription)
        }

        // 3. Generate floor plan JSON
        let floorPlanJSON: FloorPlanJSON?
        do {
            floorPlanJSON = try jsonGenerator.generate(from: pipelineResult)
            logger.info("Floor plan JSON generated")
        } catch {
            // JSON generation is non-critical - builder handles nil gracefully
            logger.warning("Floor plan JSON generation failed: \(error.localizedDescription)")
            floorPlanJSON = nil
        }

        // 4. Build MeasurementData
        let measurementData = measurementBuilder.build(
            from: pipelineResult,
            captureSession: captureSession,
            floorPlanImageURL: floorPlanURL,
            floorPlanJSON: floorPlanJSON
        )

        // 5. Validate output
        let validationResult = validateOutput(
            measurementData: measurementData,
            floorPlanURL: floorPlanURL
        )

        if !validationResult.isValid {
            logger.error("Output validation failed: \(validationResult.errors)")
            throw AIOutputError.validationFailed(validationResult.errors)
        }

        if !validationResult.warnings.isEmpty {
            logger.warning("Output validation warnings: \(validationResult.warnings)")
        }

        let processingTimeMs = Int((Date().timeIntervalSince(startTime) * 1000).rounded())
        logger.info("Output adaptation completed in \(processingTimeMs)ms")

        return AIOutputAdapterResult(
            measurementData: measurementData,
            floorPlanURL: floorPlanURL,
            validationResult: validationResult
        )
    }

    // MARK: - Validation

    /// Validates adapted output meets downstream requirements.
    ///
    /// Checks:
    /// - Required fields present (roomName, roomType)
    /// - Measurement sanity (non-negative values)
    /// - scanMethod is .aiFlow (Story 5.4)
    /// - aiMetadata is populated (Story 5.4)
    /// - Floor plan file exists
    ///
    /// - Parameters:
    ///   - measurementData: The adapted measurement data
    ///   - floorPlanURL: URL to floor plan PNG (may be nil)
    /// - Returns: Validation result with errors and warnings
    func validateOutput(
        measurementData: MeasurementData,
        floorPlanURL: URL?
    ) -> AIOutputValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Required fields (AC5)
        if measurementData.roomName?.isEmpty ?? true {
            errors.append("Room name is empty")
        }

        if measurementData.roomType?.isEmpty ?? true {
            errors.append("Room type is empty")
        }

        // Scan method must be .aiFlow (Story 5.4)
        if measurementData.scanMethod != .aiFlow {
            errors.append("Scan method not set to aiFlow")
        }

        // AI metadata must be present (Story 5.4)
        if measurementData.aiMetadata == nil {
            errors.append("AI metadata is missing")
        }

        // Floor plan validation
        if floorPlanURL == nil {
            errors.append("No floor plan image generated")
        } else if let url = floorPlanURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                errors.append("Floor plan file does not exist at path")
            }
        }

        // Measurement sanity checks
        if let totalLinearFt = measurementData.totalLinearFt, totalLinearFt < 0 {
            errors.append("Total linear feet is negative")
        }

        if let totalSqFt = measurementData.totalSqFt, totalSqFt < 0 {
            errors.append("Total square feet is negative")
        }

        // Generate warnings for low confidence (AC5)
        if let aiMetadata = measurementData.aiMetadata {
            if aiMetadata.needsVerification {
                warnings.append("Overall confidence is low - measurements may need verification")
            }

            if aiMetadata.overallConfidence < Constants.veryLowConfidenceThreshold {
                warnings.append("Very low confidence (\(Int(aiMetadata.overallConfidence * 100))%) - consider rescanning")
            }
        }

        // Story 6.1: Clear warning for empty kitchen scenario (AC3)
        if measurementData.totalLinearFt == nil || measurementData.totalLinearFt == 0 {
            warnings.append("No cabinets detected - room dimensions only")
        }

        // Warning for no walls
        if measurementData.wallCount == nil || measurementData.wallCount == 0 {
            warnings.append("No walls detected - room boundary may be incomplete")
        }

        return AIOutputValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    /// Public validation method for testing.
    ///
    /// Exposes validateOutput for unit testing without needing full adapt() flow.
    func validateOutputPublic(
        measurementData: MeasurementData,
        floorPlanURL: URL?
    ) -> AIOutputValidationResult {
        return validateOutput(measurementData: measurementData, floorPlanURL: floorPlanURL)
    }

    // MARK: - File Management

    /// Saves floor plan PNG data to temporary directory.
    ///
    /// - Parameter pngData: PNG image data
    /// - Returns: URL to saved file
    /// - Throws: Error if file cannot be written
    private func saveFloorPlanToTemp(pngData: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "floor_plan_\(UUID().uuidString).png"
        let fileURL = tempDir.appendingPathComponent(filename)

        try pngData.write(to: fileURL)
        logger.debug("Floor plan saved to: \(fileURL.path)")

        return fileURL
    }
}
