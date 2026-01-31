//
//  MeasurementExtractor.swift
//  cabinetscan
//
//  Created for Story 4.7: Measurement Extraction and Standard Size Snapping
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Measurement Extractor Protocol

/// Protocol for measurement extraction implementations.
/// Enables testing with mock extractors.
protocol MeasurementExtractorProtocol {
    /// Extracts measurements from all detected objects and formats for quotes.
    ///
    /// **Pipeline Order:** This extractor runs AFTER all detection phases:
    /// RoomDetector → CabinetDetector → ApplianceDetector → IslandPeninsulaDetector → CountertopDetector → MeasurementExtractor
    ///
    /// - Parameters:
    ///   - cabinetResult: Cabinet detection result with raw/snapped dimensions
    ///   - applianceResult: Appliance detection result with dimensions
    ///   - islandPeninsulaResult: Island/peninsula detection result
    ///   - countertopResult: Countertop detection result
    /// - Returns: Measurement extraction result with quote-ready output
    /// - Throws: `MeasurementExtractionError` if extraction fails
    func extract(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?
    ) async throws -> MeasurementExtractionResult
}

// MARK: - Extraction Phase

/// Phases of measurement extraction for progress tracking.
enum MeasurementExtractionPhase: String {
    case idle = "Idle"
    case cabinetExtraction = "Extracting Cabinet Measurements"
    case applianceExtraction = "Extracting Appliance Measurements"
    case islandExtraction = "Extracting Island Measurements"
    case peninsulaExtraction = "Extracting Peninsula Measurements"
    case snappingValidation = "Validating Snapping"
    case customSizeDetection = "Detecting Custom Sizes"
    case totalCalculation = "Calculating Totals"
    case quoteFormatting = "Formatting Quote Output"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Measured Object Type

/// Type of object being measured.
enum MeasuredObjectType: String, Codable, CaseIterable {
    case baseCabinet = "Base Cabinet"
    case upperCabinet = "Upper Cabinet"
    case tallCabinet = "Tall Cabinet"
    case cornerCabinet = "Corner Cabinet"
    case appliance = "Appliance"
    case island = "Island"
    case peninsula = "Peninsula"
    case countertop = "Countertop"

    var shortName: String {
        switch self {
        case .baseCabinet: return "Base"
        case .upperCabinet: return "Upper"
        case .tallCabinet: return "Tall"
        case .cornerCabinet: return "Corner"
        case .appliance: return "Appliance"
        case .island: return "Island"
        case .peninsula: return "Peninsula"
        case .countertop: return "Countertop"
        }
    }
}

// MARK: - Extracted Measurement (AC5, AC6)

/// A single extracted measurement with raw and snapped values.
///
/// **Critical for Quotes (AC5):**
/// - Raw values are NEVER discarded or rounded prematurely
/// - All measurements preserved at 0.1" precision
/// - Dual values enable quote flexibility
///
/// **Usage:**
/// ```swift
/// let measurement = AIExtractedMeasurement(
///     objectId: cabinet.id,
///     objectType: .baseCabinet,
///     rawDimensions: SIMD3(35.8, 34.5, 24.1),
///     snappedDimensions: SIMD3(36.0, 34.5, 24.0),
///     isStandardSize: true,
///     confidence: .high
/// )
/// print(measurement.displayString) // "36" [raw: 35.8"]"
/// ```
struct AIExtractedMeasurement: Identifiable, Equatable, Codable {
    /// Unique identifier for this measurement
    let id: UUID

    /// Reference to the source object (cabinet, appliance, island, etc.)
    let objectId: UUID

    /// Type of object measured
    let objectType: MeasuredObjectType

    /// Wall ID if applicable (nil for islands)
    let wallId: UUID?

    /// Human-readable label (e.g., "Base Cabinet 1")
    let label: String

    /// Raw measured width in inches (full precision, NEVER rounded)
    let rawWidthInches: Float

    /// Raw measured height in inches (full precision)
    let rawHeightInches: Float

    /// Raw measured depth in inches (full precision)
    let rawDepthInches: Float

    /// Snapped width in inches (after standard size snapping)
    let snappedWidthInches: Float

    /// Snapped height in inches (after standard size snapping)
    let snappedHeightInches: Float

    /// Snapped depth in inches (after standard size snapping)
    let snappedDepthInches: Float

    /// Whether dimensions match standard cabinet sizes
    let isStandardSize: Bool

    /// Whether this is a custom/non-standard size (AC7)
    let isCustomSize: Bool

    /// Absolute difference between raw and snapped width (for validation)
    let snapDifferenceInches: Float

    /// Detection/measurement confidence level
    let confidence: AIConfidenceLevel

    /// Notes about this measurement (e.g., "CUSTOM SIZE", "verify dimensions")
    let notes: [String]

    // MARK: - Computed Properties

    /// Raw dimensions as SIMD3 (width, height, depth)
    var rawDimensions: SIMD3<Float> {
        SIMD3(rawWidthInches, rawHeightInches, rawDepthInches)
    }

    /// Snapped dimensions as SIMD3 (width, height, depth)
    var snappedDimensions: SIMD3<Float> {
        SIMD3(snappedWidthInches, snappedHeightInches, snappedDepthInches)
    }

    /// Display string for quotes (e.g., "36" [raw: 35.8"]") (AC6)
    var displayString: String {
        if isCustomSize {
            return String(format: "%.1f\" CUSTOM SIZE", rawWidthInches)
        } else if abs(snapDifferenceInches) < 0.05 {
            // Exact match - no need to show raw
            return String(format: "%.0f\"", snappedWidthInches)
        } else {
            // Show both values
            return String(format: "%.0f\" [raw: %.1f\"]", snappedWidthInches, rawWidthInches)
        }
    }

    /// Short display for lists
    var shortDisplayString: String {
        if isCustomSize {
            return String(format: "%.1f\"*", rawWidthInches)
        } else {
            return String(format: "%.0f\"", snappedWidthInches)
        }
    }

    /// Width in linear feet (snapped value)
    var widthLinearFeet: Float {
        snappedWidthInches / 12.0
    }

    /// Raw width in linear feet
    var rawWidthLinearFeet: Float {
        rawWidthInches / 12.0
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        objectId: UUID,
        objectType: MeasuredObjectType,
        wallId: UUID? = nil,
        label: String,
        rawWidthInches: Float,
        rawHeightInches: Float,
        rawDepthInches: Float,
        snappedWidthInches: Float,
        snappedHeightInches: Float,
        snappedDepthInches: Float,
        isStandardSize: Bool,
        isCustomSize: Bool,
        snapDifferenceInches: Float,
        confidence: AIConfidenceLevel,
        notes: [String] = []
    ) {
        self.id = id
        self.objectId = objectId
        self.objectType = objectType
        self.wallId = wallId
        self.label = label
        self.rawWidthInches = rawWidthInches
        self.rawHeightInches = rawHeightInches
        self.rawDepthInches = rawDepthInches
        self.snappedWidthInches = snappedWidthInches
        self.snappedHeightInches = snappedHeightInches
        self.snappedDepthInches = snappedDepthInches
        self.isStandardSize = isStandardSize
        self.isCustomSize = isCustomSize
        self.snapDifferenceInches = snapDifferenceInches
        self.confidence = confidence
        self.notes = notes
    }
}

// MARK: - Quote Output (AC6)

/// Quote-ready output format for a single measurement.
struct MeasurementQuoteOutput: Equatable {
    /// Snapped value display (e.g., "36"")
    let snappedValueDisplay: String

    /// Raw value display (e.g., "35.8"")
    let rawValueDisplay: String

    /// Combined display (e.g., "36" [raw: 35.8"]")
    let combinedDisplay: String

    /// Difference display (e.g., "±0.2"" or nil if exact)
    let differenceDisplay: String?

    /// Whether this is a custom size
    let isCustomSize: Bool

    /// Notes for this item
    let notes: [String]
}

// MARK: - Linear Footage Summary (AC8, AC9)

/// Summary of linear footage totals with discrepancy tracking.
///
/// **Quote Accuracy (AC8):**
/// - Both raw and snapped totals are calculated
/// - Discrepancy is flagged if >2"
///
/// **Validation (AC9):**
/// - Sum of individuals vs total measurement checked
/// - Warning generated if discrepancy >3"
struct LinearFootageSummary: Equatable {
    /// Total raw width in inches (sum of all raw measurements)
    let rawTotalInches: Float

    /// Total snapped width in inches (sum of all snapped measurements)
    let snappedTotalInches: Float

    /// Discrepancy between raw and snapped totals (absolute value)
    let discrepancyInches: Float

    /// Whether discrepancy exceeds 2" threshold (AC8)
    let hasSignificantDiscrepancy: Bool

    /// Validation warnings
    let warnings: [String]

    // MARK: - Computed Properties

    /// Raw total in linear feet
    var rawTotalLinearFeet: Float {
        rawTotalInches / 12.0
    }

    /// Snapped total in linear feet
    var snappedTotalLinearFeet: Float {
        snappedTotalInches / 12.0
    }

    /// Discrepancy description for display
    var discrepancyDescription: String {
        if discrepancyInches < 0.5 {
            return "within tolerance"
        } else if hasSignificantDiscrepancy {
            return String(format: "%.1f\" discrepancy (verify)", discrepancyInches)
        } else {
            return String(format: "%.1f\" difference", discrepancyInches)
        }
    }
}

// MARK: - Extraction Result

/// Result of measurement extraction containing all measurements and summaries.
struct MeasurementExtractionResult: Equatable {
    /// All extracted cabinet measurements
    let cabinetMeasurements: [AIExtractedMeasurement]

    /// All extracted appliance measurements
    let applianceMeasurements: [AIExtractedMeasurement]

    /// All extracted island measurements
    let islandMeasurements: [AIExtractedMeasurement]

    /// All extracted peninsula measurements
    let peninsulaMeasurements: [AIExtractedMeasurement]

    /// Base cabinet linear footage summary
    let baseLinearFootage: LinearFootageSummary

    /// Upper cabinet linear footage summary
    let upperLinearFootage: LinearFootageSummary

    /// Tall cabinet linear footage summary
    let tallLinearFootage: LinearFootageSummary

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during extraction
    let warnings: [String]

    // MARK: - Computed Properties

    /// All measurements combined
    var allMeasurements: [AIExtractedMeasurement] {
        cabinetMeasurements + applianceMeasurements + islandMeasurements + peninsulaMeasurements
    }

    /// Count of custom-size items requiring verification
    var customSizeCount: Int {
        allMeasurements.filter { $0.isCustomSize }.count
    }

    /// Count of standard-size items
    var standardSizeCount: Int {
        allMeasurements.filter { $0.isStandardSize }.count
    }

    /// Whether any significant discrepancies exist
    var hasDiscrepancies: Bool {
        baseLinearFootage.hasSignificantDiscrepancy ||
        upperLinearFootage.hasSignificantDiscrepancy ||
        tallLinearFootage.hasSignificantDiscrepancy
    }

    /// Overall extraction confidence based on measurement confidences
    var overallConfidence: AIConfidenceLevel {
        guard !allMeasurements.isEmpty else { return .low }

        let highCount = allMeasurements.filter { $0.confidence == .high }.count
        let mediumCount = allMeasurements.filter { $0.confidence == .medium }.count
        let highRatio = Float(highCount) / Float(allMeasurements.count)
        let mediumRatio = Float(mediumCount) / Float(allMeasurements.count)

        if highRatio >= 0.7 {
            return .high
        } else if highRatio + mediumRatio >= 0.7 {
            return .medium
        } else {
            return .low
        }
    }

    // MARK: - Quote Formatting

    /// Generates quote outputs for all measurements
    func generateQuoteOutputs() -> [MeasurementQuoteOutput] {
        allMeasurements.map { measurement in
            generateQuoteOutput(from: measurement)
        }
    }

    /// Generates quote output for a single measurement
    func generateQuoteOutput(from measurement: AIExtractedMeasurement) -> MeasurementQuoteOutput {
        let snappedDisplay = String(format: "%.0f\"", measurement.snappedWidthInches)
        let rawDisplay = String(format: "%.1f\"", measurement.rawWidthInches)
        let combinedDisplay = measurement.displayString

        let differenceDisplay: String?
        if abs(measurement.snapDifferenceInches) < 0.05 {
            differenceDisplay = nil
        } else {
            differenceDisplay = String(format: "±%.1f\"", measurement.snapDifferenceInches)
        }

        return MeasurementQuoteOutput(
            snappedValueDisplay: snappedDisplay,
            rawValueDisplay: rawDisplay,
            combinedDisplay: combinedDisplay,
            differenceDisplay: differenceDisplay,
            isCustomSize: measurement.isCustomSize,
            notes: measurement.notes
        )
    }
}

// MARK: - Extraction Error

/// Errors that can occur during measurement extraction.
enum MeasurementExtractionError: LocalizedError, Equatable {
    case noInputData
    case extractionFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noInputData:
            return "No detection data available for measurement extraction"
        case .extractionFailed(let reason):
            return "Measurement extraction failed: \(reason)"
        case .cancelled:
            return "Measurement extraction was cancelled"
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .noInputData:
            return "No cabinets or appliances detected to measure."
        case .extractionFailed:
            return "Couldn't extract measurements. Manual entry may be required."
        case .cancelled:
            return "Measurement extraction was cancelled."
        }
    }
}

// MARK: - Measurement Extractor Implementation

/// Extracts and standardizes measurements from all detected objects.
///
/// **Architecture Notes:**
/// - Aggregates measurements from all detectors (cabinets, appliances, islands, peninsulas)
/// - Provides quote-ready output format with raw and snapped values
/// - Validates totals and flags discrepancies
///
/// **Performance Budget:** <100ms per Architecture 9.3
///
/// **Usage:**
/// ```swift
/// let extractor = MeasurementExtractor()
/// let result = try await extractor.extract(
///     cabinetResult: cabinets,
///     applianceResult: appliances,
///     islandPeninsulaResult: islands,
///     countertopResult: countertops
/// )
/// ```
@MainActor
final class MeasurementExtractor: ObservableObject, MeasurementExtractorProtocol {

    // MARK: - Constants

    /// Custom size flag text
    private static let customSizeFlag = "CUSTOM SIZE"

    /// Custom size verification note
    private static let customSizeVerifyNote = "verify custom cabinet dimensions"

    /// Discrepancy threshold for flagging (AC8)
    private static let discrepancyThresholdInches: Float = 2.0

    /// Sum validation threshold for warnings (AC9)
    private static let sumValidationThresholdInches: Float = 3.0

    /// Snapping thresholds per Architecture 7.3
    private static let snapHighThreshold: Float = 1.5  // ±1.5" for HIGH confidence
    private static let snapMediumThreshold: Float = 3.0  // ±3.0" for MEDIUM confidence

    // MARK: - Published Properties

    /// Current extraction progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current extraction phase
    @Published private(set) var currentPhase: MeasurementExtractionPhase = .idle

    // MARK: - Private Properties

    private let logger: Logger

    // MARK: - Initialization

    init() {
        self.logger = Logger(subsystem: "com.cabinetscan", category: "MeasurementExtractor")
        #if DEBUG
        logger.debug("MeasurementExtractor initialized")
        #endif
    }

    // MARK: - Main Extraction (AC: All)

    /// Extracts measurements from all detected objects.
    func extract(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?
    ) async throws -> MeasurementExtractionResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.info("Starting measurement extraction")

        // Validate we have some input data
        let hasData = (cabinetResult?.cabinets.isEmpty == false) ||
                      (applianceResult?.appliances.isEmpty == false) ||
                      (islandPeninsulaResult?.islands.isEmpty == false) ||
                      (islandPeninsulaResult?.peninsulas.isEmpty == false)

        guard hasData else {
            logger.warning("No detection data available for measurement extraction")
            // Return empty result instead of throwing - this is not a fatal error
            return MeasurementExtractionResult(
                cabinetMeasurements: [],
                applianceMeasurements: [],
                islandMeasurements: [],
                peninsulaMeasurements: [],
                baseLinearFootage: LinearFootageSummary(
                    rawTotalInches: 0, snappedTotalInches: 0,
                    discrepancyInches: 0, hasSignificantDiscrepancy: false, warnings: []
                ),
                upperLinearFootage: LinearFootageSummary(
                    rawTotalInches: 0, snappedTotalInches: 0,
                    discrepancyInches: 0, hasSignificantDiscrepancy: false, warnings: []
                ),
                tallLinearFootage: LinearFootageSummary(
                    rawTotalInches: 0, snappedTotalInches: 0,
                    discrepancyInches: 0, hasSignificantDiscrepancy: false, warnings: []
                ),
                processingTimeMs: 0,
                warnings: ["No objects detected for measurement extraction"]
            )
        }

        var warnings: [String] = []

        // Step 1: Extract cabinet measurements (AC1, AC2, AC3)
        currentPhase = .cabinetExtraction
        progress = 0.1

        let cabinetMeasurements = extractCabinetMeasurements(from: cabinetResult)

        try Task.checkCancellation()

        // Step 2: Extract appliance measurements
        currentPhase = .applianceExtraction
        progress = 0.3

        let applianceMeasurements = extractApplianceMeasurements(from: applianceResult)

        try Task.checkCancellation()

        // Step 3: Extract island measurements
        currentPhase = .islandExtraction
        progress = 0.45

        let islandMeasurements = extractIslandMeasurements(from: islandPeninsulaResult)

        try Task.checkCancellation()

        // Step 4: Extract peninsula measurements
        currentPhase = .peninsulaExtraction
        progress = 0.55

        let peninsulaMeasurements = extractPeninsulaMeasurements(from: islandPeninsulaResult)

        try Task.checkCancellation()

        // Step 5: Detect custom sizes (AC7)
        currentPhase = .customSizeDetection
        progress = 0.65

        let customSizeCount = (cabinetMeasurements + applianceMeasurements + islandMeasurements + peninsulaMeasurements)
            .filter { $0.isCustomSize }.count

        if customSizeCount > 0 {
            warnings.append("\(customSizeCount) custom-size item(s) detected - field verification recommended")
        }

        try Task.checkCancellation()

        // Step 6: Calculate linear footage totals (AC8, AC9)
        currentPhase = .totalCalculation
        progress = 0.8

        let baseLinearFootage = calculateLinearFootage(
            measurements: cabinetMeasurements.filter {
                $0.objectType == .baseCabinet || ($0.objectType == .cornerCabinet && !$0.notes.contains("Upper"))
            },
            label: "base"
        )

        let upperLinearFootage = calculateLinearFootage(
            measurements: cabinetMeasurements.filter {
                $0.objectType == .upperCabinet || ($0.objectType == .cornerCabinet && $0.notes.contains("Upper"))
            },
            label: "upper"
        )

        let tallLinearFootage = calculateLinearFootage(
            measurements: cabinetMeasurements.filter { $0.objectType == .tallCabinet },
            label: "tall"
        )

        // Add discrepancy warnings
        if baseLinearFootage.hasSignificantDiscrepancy {
            warnings.append("Base cabinet linear footage has \(String(format: "%.1f", baseLinearFootage.discrepancyInches))\" discrepancy between raw and snapped totals")
        }
        if upperLinearFootage.hasSignificantDiscrepancy {
            warnings.append("Upper cabinet linear footage has \(String(format: "%.1f", upperLinearFootage.discrepancyInches))\" discrepancy between raw and snapped totals")
        }
        if tallLinearFootage.hasSignificantDiscrepancy {
            warnings.append("Tall cabinet linear footage has \(String(format: "%.1f", tallLinearFootage.discrepancyInches))\" discrepancy between raw and snapped totals")
        }

        try Task.checkCancellation()

        // Step 7: Format for quote output
        currentPhase = .quoteFormatting
        progress = 0.95

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        currentPhase = .complete
        progress = 1.0

        logger.info("Measurement extraction complete in \(processingTimeMs)ms: \(cabinetMeasurements.count) cabinets, \(applianceMeasurements.count) appliances, \(islandMeasurements.count) islands, \(peninsulaMeasurements.count) peninsulas")

        return MeasurementExtractionResult(
            cabinetMeasurements: cabinetMeasurements,
            applianceMeasurements: applianceMeasurements,
            islandMeasurements: islandMeasurements,
            peninsulaMeasurements: peninsulaMeasurements,
            baseLinearFootage: baseLinearFootage,
            upperLinearFootage: upperLinearFootage,
            tallLinearFootage: tallLinearFootage,
            processingTimeMs: processingTimeMs,
            warnings: warnings
        )
    }

    // MARK: - Cabinet Extraction (AC1, AC2, AC3, AC4, AC5)

    /// Extracts measurements from detected cabinets.
    private func extractCabinetMeasurements(from result: CabinetDetectionResult?) -> [AIExtractedMeasurement] {
        guard let result = result else { return [] }

        var measurements: [AIExtractedMeasurement] = []
        var baseCabinetIndex = 1
        var upperCabinetIndex = 1
        var tallCabinetIndex = 1
        var cornerCabinetIndex = 1

        for cabinet in result.cabinets {
            let objectType: MeasuredObjectType
            let label: String
            var notes = cabinet.notes

            // Determine type and label
            if cabinet.isCornerCabinet {
                objectType = .cornerCabinet
                label = "Corner Cabinet \(cornerCabinetIndex)"
                if let cornerType = cabinet.cornerType {
                    notes.append(cornerType.displayText)
                }
                if cabinet.type == .upper {
                    notes.append("Upper")
                }
                cornerCabinetIndex += 1
            } else {
                switch cabinet.type {
                case .base:
                    objectType = .baseCabinet
                    label = "Base Cabinet \(baseCabinetIndex)"
                    baseCabinetIndex += 1
                case .upper:
                    objectType = .upperCabinet
                    label = "Upper Cabinet \(upperCabinetIndex)"
                    upperCabinetIndex += 1
                case .tall:
                    objectType = .tallCabinet
                    label = "Tall Cabinet \(tallCabinetIndex)"
                    tallCabinetIndex += 1
                }
            }

            // Calculate snap difference
            let snapDifference = abs(cabinet.rawWidthInches - cabinet.widthInches)

            // Determine if custom size (AC7)
            // A cabinet is custom if:
            // 1. It's not a standard size (snapping didn't find a match within tolerance), OR
            // 2. It has LOW confidence (detector flagged it as non-standard)
            let isCustomSize = !cabinet.isStandardSize && cabinet.confidence == .low

            // Add custom size notes
            if isCustomSize && !notes.contains(Self.customSizeFlag) {
                notes.append(Self.customSizeFlag)
                notes.append(Self.customSizeVerifyNote)
            }

            let measurement = AIExtractedMeasurement(
                objectId: cabinet.id,
                objectType: objectType,
                wallId: cabinet.wallId,
                label: label,
                rawWidthInches: cabinet.rawWidthInches,
                rawHeightInches: cabinet.rawHeightInches,
                rawDepthInches: cabinet.rawDepthInches,
                snappedWidthInches: cabinet.widthInches,
                snappedHeightInches: cabinet.heightInches,
                snappedDepthInches: cabinet.depthInches,
                isStandardSize: cabinet.isStandardSize,
                isCustomSize: isCustomSize,
                snapDifferenceInches: snapDifference,
                confidence: cabinet.confidence,
                notes: notes
            )

            measurements.append(measurement)
        }

        return measurements
    }

    // MARK: - Appliance Extraction

    /// Extracts measurements from detected appliances.
    private func extractApplianceMeasurements(from result: ApplianceDetectionResult?) -> [AIExtractedMeasurement] {
        guard let result = result else { return [] }

        return result.appliances.enumerated().map { index, appliance in
            let label = "\(appliance.type.displayText) \(index + 1)"

            // Appliances don't snap to standard sizes - use raw dimensions
            let rawWidth = appliance.rawDimensions.x
            let rawHeight = appliance.rawDimensions.y
            let rawDepth = appliance.rawDimensions.z

            return AIExtractedMeasurement(
                objectId: appliance.id,
                objectType: .appliance,
                wallId: appliance.wallId,
                label: label,
                rawWidthInches: rawWidth,
                rawHeightInches: rawHeight,
                rawDepthInches: rawDepth,
                snappedWidthInches: rawWidth,  // No snapping for appliances
                snappedHeightInches: rawHeight,
                snappedDepthInches: rawDepth,
                isStandardSize: false,  // Appliances don't have standard sizes
                isCustomSize: false,
                snapDifferenceInches: 0,
                confidence: appliance.confidence,
                notes: appliance.notes
            )
        }
    }

    // MARK: - Island Extraction

    /// Extracts measurements from detected islands.
    private func extractIslandMeasurements(from result: IslandPeninsulaDetectionResult?) -> [AIExtractedMeasurement] {
        guard let result = result else { return [] }

        return result.islands.enumerated().map { index, island in
            let label = "Island \(index + 1)"

            // Islands use their countertop dimensions
            let rawWidth = island.lengthInches
            let rawDepth = island.widthInches
            let rawHeight = island.heightInches

            return AIExtractedMeasurement(
                objectId: island.id,
                objectType: .island,
                wallId: nil,  // Islands are not attached to walls
                label: label,
                rawWidthInches: rawWidth,
                rawHeightInches: rawHeight,
                rawDepthInches: rawDepth,
                snappedWidthInches: rawWidth,  // No standard snapping for islands
                snappedHeightInches: rawHeight,
                snappedDepthInches: rawDepth,
                isStandardSize: false,
                isCustomSize: false,  // Islands are always custom
                snapDifferenceInches: 0,
                confidence: island.confidence,
                notes: island.notes
            )
        }
    }

    // MARK: - Peninsula Extraction

    /// Extracts measurements from detected peninsulas.
    private func extractPeninsulaMeasurements(from result: IslandPeninsulaDetectionResult?) -> [AIExtractedMeasurement] {
        guard let result = result else { return [] }

        return result.peninsulas.enumerated().map { index, peninsula in
            let label = "Peninsula \(index + 1)"

            // Peninsulas use their countertop dimensions
            let rawWidth = peninsula.lengthInches
            let rawDepth = peninsula.widthInches
            let rawHeight = peninsula.heightInches

            return AIExtractedMeasurement(
                objectId: peninsula.id,
                objectType: .peninsula,
                wallId: peninsula.attachedWallId,
                label: label,
                rawWidthInches: rawWidth,
                rawHeightInches: rawHeight,
                rawDepthInches: rawDepth,
                snappedWidthInches: rawWidth,  // No standard snapping for peninsulas
                snappedHeightInches: rawHeight,
                snappedDepthInches: rawDepth,
                isStandardSize: false,
                isCustomSize: false,
                snapDifferenceInches: 0,
                confidence: peninsula.confidence,
                notes: peninsula.notes
            )
        }
    }

    // MARK: - Linear Footage Calculation (AC8, AC9)

    /// Calculates linear footage summary for a set of measurements.
    private func calculateLinearFootage(
        measurements: [AIExtractedMeasurement],
        label: String
    ) -> LinearFootageSummary {
        guard !measurements.isEmpty else {
            return LinearFootageSummary(
                rawTotalInches: 0,
                snappedTotalInches: 0,
                discrepancyInches: 0,
                hasSignificantDiscrepancy: false,
                warnings: []
            )
        }

        let rawTotal = measurements.reduce(0) { $0 + $1.rawWidthInches }
        let snappedTotal = measurements.reduce(0) { $0 + $1.snappedWidthInches }
        let discrepancy = abs(rawTotal - snappedTotal)
        let hasSignificant = discrepancy > Self.discrepancyThresholdInches

        var warnings: [String] = []

        // AC8: Flag if >2" discrepancy between totals
        if hasSignificant {
            warnings.append("Total \(label) cabinet linear footage discrepancy: snapped (\(String(format: "%.1f", snappedTotal))\") differs from raw (\(String(format: "%.1f", rawTotal))\") by \(String(format: "%.1f", discrepancy))\"")
        }

        // AC9: Sum validation - would need external total measurement to compare
        // For now, we just track the internal consistency

        return LinearFootageSummary(
            rawTotalInches: rawTotal,
            snappedTotalInches: snappedTotal,
            discrepancyInches: discrepancy,
            hasSignificantDiscrepancy: hasSignificant,
            warnings: warnings
        )
    }
}

// MARK: - Standard Cabinet Sizes Extension

extension StandardCabinetSizes {
    /// Standard tall cabinet widths in inches (AC3)
    static let tallCabinetWidths: [Float] = [18, 24, 30, 36]

    /// Checks if a width is a custom (non-standard) size.
    ///
    /// - Parameters:
    ///   - width: The measured width in inches
    ///   - type: The cabinet type
    ///   - tolerance: Snap tolerance (default 1.5")
    /// - Returns: True if the width doesn't match any standard size within tolerance
    static func isCustomSize(width: Float, type: AICabinetType, tolerance: Float = 1.5) -> Bool {
        let standardWidths: [Float]
        switch type {
        case .tall:
            standardWidths = tallCabinetWidths
        case .base, .upper:
            standardWidths = widths
        }

        // Check if any standard width is within tolerance
        return !standardWidths.contains { abs($0 - width) <= tolerance }
    }

    /// Generates a description of the difference between raw and snapped values.
    ///
    /// - Parameters:
    ///   - raw: Raw measured value in inches
    ///   - snapped: Snapped value in inches
    /// - Returns: Description string, or nil if values are equal
    static func snapDifferenceDescription(raw: Float, snapped: Float) -> String? {
        let difference = abs(raw - snapped)
        if difference < 0.1 {
            return nil
        }
        return String(format: "%.1f\" difference from %.1f\" to %.0f\"", difference, raw, snapped)
    }
}
