//
//  ApplianceDetector.swift
//  cabinetscan
//
//  Created for Story 4.4: Appliance Detection
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Appliance Detector Protocol

/// Protocol for appliance detection implementations.
/// Enables testing with mock detectors.
protocol ApplianceDetectorProtocol {
    /// Detects appliances from room structure, point cloud, and cabinet layout.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure from RoomDetector (walls, floor plane)
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Detected cabinets from CabinetDetector
    ///   - islands: Detected islands (if any)
    /// - Returns: Appliance detection result with all detected appliances
    /// - Throws: `ApplianceDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        islands: [AIDetectedIsland]
    ) async throws -> ApplianceDetectionResult
}

// MARK: - Appliance Detection Phase

/// Phases of appliance detection for progress tracking.
enum ApplianceDetectionPhase: String {
    case idle = "Idle"
    case refrigeratorDetection = "Detecting Refrigerators"
    case rangeDetection = "Detecting Ranges"
    case sinkDetection = "Detecting Sinks"
    case microwaveDetection = "Detecting Microwaves"
    case hoodDetection = "Detecting Hoods"
    case dishwasherDetection = "Detecting Dishwashers"
    case dimensionExtraction = "Extracting Dimensions"
    case validation = "Validating Appliances"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Detected Appliance

/// An appliance detected in the kitchen scan.
///
/// **Coordinate System:**
/// - All dimensions are in inches (calibrated via ScaleCalibrator)
/// - `positionOnWallInches` is distance from wall start point
/// - Raw dimensions are NEVER modified after measurement
///
/// **Usage:**
/// ```swift
/// let appliance = AIDetectedAppliance(
///     type: .refrigerator,
///     wallId: wall.id,
///     rawDimensions: SIMD3(36.0, 69.0, 32.0),
///     ...
/// )
/// ```
struct AIDetectedAppliance: Identifiable, Equatable, Codable {
    /// Unique identifier for this appliance
    let id: UUID

    /// 3D bounding box of the appliance
    let boundingBox: AIBoundingBox3D

    /// Appliance type classification
    let type: AIApplianceType

    /// Appliance subtype (more specific classification)
    let subType: AIApplianceSubType?

    /// Raw measured dimensions (width, height, depth) in inches
    /// These are NEVER modified - always preserve original measurements
    let rawDimensions: SIMD3<Float>

    /// Dimensions after standard size snapping (width, height, depth) in inches
    /// May equal rawDimensions if not snapped to standard
    let snappedDimensions: SIMD3<Float>

    /// Position in room (x, z) - center point
    let position: SIMD2<Float>

    /// Reference to the wall this appliance is against (nil for island appliances)
    let wallId: UUID?

    /// Position along the wall from wall start point (inches)
    /// Nil for island or freestanding appliances
    let positionOnWallInches: Float?

    /// Detection confidence level
    let confidence: AIConfidenceLevel

    /// Whether appliance is built-in vs freestanding
    let isBuiltIn: Bool

    /// Whether dimensions match standard appliance sizes
    let isStandardSize: Bool

    /// Whether this is a counter-depth refrigerator (24"-27" depth)
    let isCounterDepth: Bool

    /// Notes about the detection (e.g., "Verify dimensions", "Reflective surface")
    let notes: [String]

    // MARK: - Computed Properties

    /// Raw width in inches
    var rawWidthInches: Float { rawDimensions.x }

    /// Raw height in inches
    var rawHeightInches: Float { rawDimensions.y }

    /// Raw depth in inches
    var rawDepthInches: Float { rawDimensions.z }

    /// Snapped width in inches
    var widthInches: Float { snappedDimensions.x }

    /// Snapped height in inches
    var heightInches: Float { snappedDimensions.y }

    /// Snapped depth in inches
    var depthInches: Float { snappedDimensions.z }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        boundingBox: AIBoundingBox3D,
        type: AIApplianceType,
        subType: AIApplianceSubType? = nil,
        rawDimensions: SIMD3<Float>,
        snappedDimensions: SIMD3<Float>,
        position: SIMD2<Float>,
        wallId: UUID? = nil,
        positionOnWallInches: Float? = nil,
        confidence: AIConfidenceLevel,
        isBuiltIn: Bool = false,
        isStandardSize: Bool = true,
        isCounterDepth: Bool = false,
        notes: [String] = []
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.type = type
        self.subType = subType
        self.rawDimensions = rawDimensions
        self.snappedDimensions = snappedDimensions
        self.position = position
        self.wallId = wallId
        self.positionOnWallInches = positionOnWallInches
        self.confidence = confidence
        self.isBuiltIn = isBuiltIn
        self.isStandardSize = isStandardSize
        self.isCounterDepth = isCounterDepth
        self.notes = notes
    }
}

// MARK: - Appliance Type

/// Classification of appliance type.
enum AIApplianceType: String, Codable, CaseIterable {
    /// Refrigerator (standard, French door, side-by-side)
    case refrigerator

    /// Range/Stove (freestanding, slide-in)
    case range

    /// Cooktop (separate from oven)
    case cooktop

    /// Wall oven (single or double)
    case wallOven

    /// Dishwasher (standard or compact)
    case dishwasher

    /// Microwave (OTR, built-in, countertop)
    case microwave

    /// Hood/Vent (wall-mount, under-cabinet, island)
    case hood

    /// Sink (single, double, farmhouse)
    case sink

    /// Other/unclassified appliance
    case other

    /// Human-readable description
    var displayText: String {
        switch self {
        case .refrigerator: return "Refrigerator"
        case .range: return "Range"
        case .cooktop: return "Cooktop"
        case .wallOven: return "Wall Oven"
        case .dishwasher: return "Dishwasher"
        case .microwave: return "Microwave"
        case .hood: return "Hood/Vent"
        case .sink: return "Sink"
        case .other: return "Other"
        }
    }
}

// MARK: - Appliance Subtype

/// Specific subtype classification for appliances.
enum AIApplianceSubType: String, Codable, CaseIterable {
    // Refrigerator subtypes
    case fridgeFrenchDoor
    case fridgeSideBySide
    case fridgeTopFreezer
    case fridgeBottomFreezer
    case fridgeCounterDepth

    // Range subtypes
    case rangeFreestanding
    case rangeSlideIn
    case rangeProStyle

    // Hood subtypes
    case hoodWallMount
    case hoodUnderCabinet
    case hoodIsland

    // Microwave subtypes
    case microwaveOTR
    case microwaveBuiltIn
    case microwaveCountertop
    case microwaveDrawer

    // Sink subtypes
    case sinkSingleBowl
    case sinkDoubleBowl
    case sinkFarmhouse
    case sinkUndermount
    case sinkDropIn

    // Oven subtypes
    case ovenSingle
    case ovenDouble

    // Dishwasher subtypes
    case dishwasherStandard
    case dishwasherCompact
    case dishwasherPanelReady

    /// Human-readable description
    var displayText: String {
        switch self {
        case .fridgeFrenchDoor: return "French Door"
        case .fridgeSideBySide: return "Side-by-Side"
        case .fridgeTopFreezer: return "Top Freezer"
        case .fridgeBottomFreezer: return "Bottom Freezer"
        case .fridgeCounterDepth: return "Counter Depth"
        case .rangeFreestanding: return "Freestanding"
        case .rangeSlideIn: return "Slide-In"
        case .rangeProStyle: return "Pro Style"
        case .hoodWallMount: return "Wall Mount"
        case .hoodUnderCabinet: return "Under Cabinet"
        case .hoodIsland: return "Island"
        case .microwaveOTR: return "Over-the-Range"
        case .microwaveBuiltIn: return "Built-In"
        case .microwaveCountertop: return "Countertop"
        case .microwaveDrawer: return "Drawer"
        case .sinkSingleBowl: return "Single Bowl"
        case .sinkDoubleBowl: return "Double Bowl"
        case .sinkFarmhouse: return "Farmhouse"
        case .sinkUndermount: return "Undermount"
        case .sinkDropIn: return "Drop-In"
        case .ovenSingle: return "Single Oven"
        case .ovenDouble: return "Double Oven"
        case .dishwasherStandard: return "Standard"
        case .dishwasherCompact: return "Compact"
        case .dishwasherPanelReady: return "Panel Ready"
        }
    }
}

// MARK: - Appliance Detection Result

/// Result of appliance detection containing all detected appliances and metadata.
struct ApplianceDetectionResult: Equatable {
    /// All detected appliances
    let appliances: [AIDetectedAppliance]

    /// Refrigerators only
    var refrigerators: [AIDetectedAppliance] {
        appliances.filter { $0.type == .refrigerator }
    }

    /// Ranges only
    var ranges: [AIDetectedAppliance] {
        appliances.filter { $0.type == .range }
    }

    /// Cooktops only
    var cooktops: [AIDetectedAppliance] {
        appliances.filter { $0.type == .cooktop }
    }

    /// Dishwashers only
    var dishwashers: [AIDetectedAppliance] {
        appliances.filter { $0.type == .dishwasher }
    }

    /// Microwaves only
    var microwaves: [AIDetectedAppliance] {
        appliances.filter { $0.type == .microwave }
    }

    /// Hoods only
    var hoods: [AIDetectedAppliance] {
        appliances.filter { $0.type == .hood }
    }

    /// Sinks only
    var sinks: [AIDetectedAppliance] {
        appliances.filter { $0.type == .sink }
    }

    /// Total count of all appliances
    var totalCount: Int { appliances.count }

    /// Count by appliance type
    var countByType: [AIApplianceType: Int] {
        Dictionary(grouping: appliances, by: { $0.type })
            .mapValues { $0.count }
    }

    /// Positions of OTR microwaves (used for hood mutual exclusion)
    var otrMicrowavePositions: [SIMD2<Float>] {
        microwaves
            .filter { $0.subType == .microwaveOTR }
            .map { $0.position }
    }

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection
    let warnings: [String]

    /// Overall detection confidence
    var overallConfidence: AIConfidenceLevel {
        guard !appliances.isEmpty else { return .low }

        let highCount = appliances.filter { $0.confidence == .high }.count
        let mediumCount = appliances.filter { $0.confidence == .medium }.count

        let highRatio = Float(highCount) / Float(appliances.count)
        let mediumRatio = Float(mediumCount) / Float(appliances.count)

        if highRatio >= 0.7 {
            return .high
        } else if highRatio + mediumRatio >= 0.7 {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Appliance Detection Error

/// Errors that can occur during appliance detection.
enum ApplianceDetectionError: LocalizedError, Equatable {
    case noRoomStructure
    case noPointCloud
    case noCabinetsDetected
    case detectionFailed(reason: String)
    case cancelled
    case timeout

    var errorDescription: String? {
        switch self {
        case .noRoomStructure:
            return "Room structure is required for appliance detection"
        case .noPointCloud:
            return "Point cloud is empty - cannot detect appliances"
        case .noCabinetsDetected:
            return "Cabinet detection required before appliance detection"
        case .detectionFailed(let reason):
            return "Appliance detection failed: \(reason)"
        case .cancelled:
            return "Appliance detection was cancelled"
        case .timeout:
            return "Appliance detection timed out"
        }
    }
}

// MARK: - Standard Appliance Sizes

/// Standard US appliance sizes for snapping and validation.
enum StandardApplianceSizes {
    // MARK: - Refrigerator Sizes

    /// Standard refrigerator widths in inches
    static let fridgeWidths: [Float] = [30, 33, 36]

    /// Standard refrigerator height range in inches
    static let fridgeHeightRange: ClosedRange<Float> = 66...70

    /// Standard refrigerator depth range (standard depth) in inches
    static let fridgeDepthStandard: ClosedRange<Float> = 30...36

    /// Counter-depth refrigerator depth range in inches
    static let fridgeDepthCounterDepth: ClosedRange<Float> = 24...27

    // MARK: - Range Sizes

    /// Standard range widths in inches
    static let rangeWidths: [Float] = [30, 36]

    /// Standard range height in inches
    static let rangeHeight: Float = 36

    /// Standard range depth range in inches
    static let rangeDepthRange: ClosedRange<Float> = 25...27

    // MARK: - Dishwasher Sizes

    /// Standard dishwasher widths in inches
    static let dishwasherWidths: [Float] = [24, 18]

    /// Standard dishwasher height in inches
    static let dishwasherHeight: Float = 34

    /// Standard dishwasher depth in inches
    static let dishwasherDepth: Float = 24

    /// Maximum distance from sink for dishwasher (inches)
    static let dishwasherMaxDistanceFromSink: Float = 36

    // MARK: - Microwave Sizes

    /// Standard OTR microwave width in inches
    static let microwaveOTRWidth: Float = 30

    /// Standard OTR microwave height range in inches
    static let microwaveOTRHeightRange: ClosedRange<Float> = 16...18

    // MARK: - Hood Sizes

    /// Standard hood widths in inches
    static let hoodWidths: [Float] = [30, 36, 42, 48]

    /// Standard height above cooktop range (inches)
    static let hoodHeightAboveCooktop: ClosedRange<Float> = 24...30

    // MARK: - Sink Sizes

    /// Standard single sink size (width × depth) in inches
    static let sinkSingle: SIMD2<Float> = SIMD2(25, 22)

    /// Standard double sink size (width × depth) in inches
    static let sinkDouble: SIMD2<Float> = SIMD2(33, 22)

    /// Farmhouse sink width range in inches
    static let sinkFarmhouseWidthRange: ClosedRange<Float> = 30...36

    /// Farmhouse sink depth range in inches
    static let sinkFarmhouseDepthRange: ClosedRange<Float> = 20...22

    // MARK: - Snapping Thresholds

    /// Tolerance for HIGH confidence snapping (inches)
    static let snapHighThreshold: Float = 1.5

    /// Tolerance for MEDIUM confidence snapping (inches)
    static let snapMediumThreshold: Float = 3.0

    // MARK: - Helper Methods

    /// Finds the nearest standard refrigerator width.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestFridgeWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = fridgeWidths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard range width.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestRangeWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = rangeWidths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard dishwasher width.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestDishwasherWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = dishwasherWidths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard hood width.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestHoodWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = hoodWidths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Checks if a refrigerator depth indicates counter-depth variant.
    ///
    /// - Parameter depth: Measured depth in inches
    /// - Returns: True if depth is within counter-depth range
    static func isCounterDepthFridge(_ depth: Float) -> Bool {
        fridgeDepthCounterDepth.contains(depth)
    }
}

// Note: AIDetectedIsland and AIDetectedPeninsula are defined in
// Features/AIFlow/Detection/AIDetectedIsland.swift (Story 4.5)

// MARK: - Appliance Detector

/// Detects kitchen appliances from calibrated 3D point cloud.
///
/// **Algorithm Pipeline:**
/// 1. Refrigerator Detection - Find tall units at cabinet run ends
/// 2. Range/Cooktop Detection - Find gaps in base cabinets
/// 3. Sink Detection - Find depressions in countertop
/// 4. Microwave Detection - Find above range position
/// 5. Hood Detection - Find above range (with mutual exclusion)
/// 6. Dishwasher Detection - Find near sink position
/// 7. Dimension Extraction - Measure width, height, depth
/// 8. Standard Size Snapping - Snap to standard sizes
/// 9. Cross-Validation - Verify appliance relationships
///
/// **Performance Budget:** <500ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = ApplianceDetector()
/// let result = try await detector.detect(
///     roomStructure: room,
///     pointCloud: cloud,
///     cabinets: cabinetResult,
///     islands: []
/// )
/// ```
@MainActor
final class ApplianceDetector: ObservableObject, ApplianceDetectorProtocol {

    // MARK: - Constants

    /// Minimum height for refrigerator detection (inches)
    private static let fridgeMinHeight: Float = 60.0

    /// Maximum height for refrigerator detection (inches)
    private static let fridgeMaxHeight: Float = 70.0

    /// Minimum depth for standard refrigerator (inches)
    private static let fridgeMinDepthStandard: Float = 30.0

    /// Maximum depth for standard refrigerator (inches)
    private static let fridgeMaxDepthStandard: Float = 36.0

    /// Minimum depth for counter-depth refrigerator (inches)
    private static let fridgeMinDepthCounterDepth: Float = 24.0

    /// Maximum depth for counter-depth refrigerator (inches)
    private static let fridgeMaxDepthCounterDepth: Float = 27.0

    /// Height range for base cabinet level appliances (inches)
    private static let baseCabinetHeightRange: ClosedRange<Float> = 34...36

    /// Countertop height (inches)
    private static let countertopHeight: Float = 36.0

    /// Distance from wall to consider "against wall" (inches)
    private static let wallProximityThreshold: Float = 6.0

    /// Minimum points for appliance detection
    private static let minPointsForAppliance: Int = 30

    /// Performance timeout (milliseconds)
    private static let timeoutMs: Int = 500

    // MARK: - Refrigerator Size Constants

    /// Minimum valid refrigerator width (inches)
    private static let fridgeMinWidth: Float = 28.0

    /// Maximum valid refrigerator width (inches)
    private static let fridgeMaxWidth: Float = 38.0

    // MARK: - Range Size Constants

    /// Minimum valid range width (inches)
    private static let rangeMinWidth: Float = 28.0

    /// Maximum valid range width (inches)
    private static let rangeMaxWidth: Float = 38.0

    // MARK: - Sink Size Constants

    /// Minimum valid sink width (inches)
    private static let sinkMinWidth: Float = 20.0

    /// Maximum valid sink width (inches)
    private static let sinkMaxWidth: Float = 40.0

    /// Minimum valid sink depth (inches)
    private static let sinkMinDepth: Float = 18.0

    /// Maximum valid sink depth (inches)
    private static let sinkMaxDepth: Float = 25.0

    // MARK: - Microwave Size Constants

    /// Minimum valid OTR microwave width (inches)
    private static let microwaveOTRMinWidth: Float = 28.0

    /// Maximum valid OTR microwave width (inches)
    private static let microwaveOTRMaxWidth: Float = 32.0

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: ApplianceDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "ApplianceDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("ApplianceDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all appliances from room structure, point cloud, and cabinet layout.
    ///
    /// **Detection Order (per AC12 dependency requirements):**
    /// 1. Refrigerator (independent)
    /// 2. Range/Cooktop (independent)
    /// 3. Sink (independent, but needed for dishwasher)
    /// 4. Microwave (needs range positions)
    /// 5. Hood (needs range AND microwave for mutual exclusion)
    /// 6. Dishwasher (needs sink positions)
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and floor plane
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Cabinet detection result
    ///   - islands: Detected islands
    /// - Returns: Appliance detection result with all detected appliances
    /// - Throws: `ApplianceDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        islands: [AIDetectedIsland]
    ) async throws -> ApplianceDetectionResult {
        #if DEBUG
        logger.info("Starting appliance detection with \(pointCloud.count) points, \(cabinets.totalCount) cabinets")
        #endif

        guard !pointCloud.isEmpty else {
            throw ApplianceDetectionError.noPointCloud
        }

        isProcessing = true
        progress = 0.0
        currentPhase = .refrigeratorDetection

        let startTime = CFAbsoluteTimeGetCurrent()
        var warnings: [String] = []
        var allAppliances: [AIDetectedAppliance] = []

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Get points from point cloud
        var mutablePointCloud = pointCloud
        let points = mutablePointCloud.getPoints()
        let floorY: Float = -roomStructure.floorPlane.distance

        // 1. Detect refrigerators (independent)
        try Task.checkCancellation()
        currentPhase = .refrigeratorDetection
        let refrigerators = detectRefrigerators(
            points: points,
            roomStructure: roomStructure,
            cabinets: cabinets,
            floorY: floorY
        )
        allAppliances.append(contentsOf: refrigerators)
        progress = 0.15
        #if DEBUG
        logger.info("Detected \(refrigerators.count) refrigerators")
        #endif

        // 2. Detect ranges/cooktops (independent)
        try Task.checkCancellation()
        currentPhase = .rangeDetection
        let ranges = detectRanges(
            points: points,
            roomStructure: roomStructure,
            cabinets: cabinets,
            floorY: floorY
        )
        allAppliances.append(contentsOf: ranges)
        progress = 0.30
        #if DEBUG
        logger.info("Detected \(ranges.count) ranges/cooktops")
        #endif

        // 3. Detect sinks (needed for dishwasher)
        try Task.checkCancellation()
        currentPhase = .sinkDetection
        let sinks = detectSinks(
            points: points,
            roomStructure: roomStructure,
            islands: islands,
            floorY: floorY
        )
        allAppliances.append(contentsOf: sinks)
        progress = 0.45
        #if DEBUG
        logger.info("Detected \(sinks.count) sinks")
        #endif

        // 4. Detect microwaves (needs range positions)
        try Task.checkCancellation()
        currentPhase = .microwaveDetection
        let microwaves = detectMicrowaves(
            points: points,
            ranges: ranges,
            floorY: floorY
        )
        allAppliances.append(contentsOf: microwaves)
        progress = 0.60
        #if DEBUG
        logger.info("Detected \(microwaves.count) microwaves")
        #endif

        // Get OTR microwave positions for mutual exclusion
        let otrMicrowavePositions = microwaves
            .filter { $0.subType == .microwaveOTR }
            .map { $0.position }

        // 5. Detect hoods (needs range AND microwave for mutual exclusion per AC11)
        try Task.checkCancellation()
        currentPhase = .hoodDetection
        let hoods = detectHoods(
            points: points,
            ranges: ranges,
            islands: islands,
            otrMicrowavePositions: otrMicrowavePositions,
            roomStructure: roomStructure,
            floorY: floorY
        )
        allAppliances.append(contentsOf: hoods)
        progress = 0.75
        #if DEBUG
        logger.info("Detected \(hoods.count) hoods")
        #endif

        // 6. Detect dishwashers (needs sink positions per AC12)
        try Task.checkCancellation()
        currentPhase = .dishwasherDetection
        let dishwashers = detectDishwashers(
            points: points,
            cabinets: cabinets,
            sinks: sinks,
            floorY: floorY
        )
        allAppliances.append(contentsOf: dishwashers)
        progress = 0.85
        #if DEBUG
        logger.info("Detected \(dishwashers.count) dishwashers")
        #endif

        // 7. Validation phase (AC12, AC13, AC14)
        try Task.checkCancellation()
        currentPhase = .validation

        // Deduplication (AC14)
        allAppliances = deduplicateAppliances(allAppliances)

        // Cross-validation (AC12)
        let validationWarnings = validateApplianceRelationships(
            appliances: allAppliances,
            cabinets: cabinets
        )
        warnings.append(contentsOf: validationWarnings)

        progress = 0.95

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        #if DEBUG
        logger.info("Appliance detection complete in \(processingTimeMs)ms: \(allAppliances.count) appliances")
        #endif

        return ApplianceDetectionResult(
            appliances: allAppliances,
            processingTimeMs: processingTimeMs,
            warnings: warnings
        )
    }

    // MARK: - Refrigerator Detection

    /// Detects refrigerators by height and depth characteristics.
    ///
    /// **Algorithm (Task 3):**
    /// 1. Filter points to tall unit height range (60"-70")
    /// 2. Cluster points into potential refrigerator regions
    /// 3. Validate depth (30"-36" standard, 24"-27" counter-depth)
    /// 4. Check position at cabinet run ends or alcoves
    /// 5. Validate no overlap with detected tall cabinets
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - roomStructure: Room structure with walls
    ///   - cabinets: Detected cabinets
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected refrigerators
    private func detectRefrigerators(
        points: [SIMD3<Float>],
        roomStructure: AIRoomStructure,
        cabinets: CabinetDetectionResult,
        floorY: Float
    ) -> [AIDetectedAppliance] {
        var refrigerators: [AIDetectedAppliance] = []

        // 1. Find potential refrigerator regions by clustering tall points
        let tallPointClusters = clusterTallPoints(
            points: points,
            floorY: floorY,
            minHeight: Self.fridgeMinHeight,
            maxHeight: Self.fridgeMaxHeight
        )

        for cluster in tallPointClusters {
            guard cluster.count >= Self.minPointsForAppliance else { continue }

            // 2. Calculate bounding box for this cluster
            let boundingBox = calculateBoundingBox(points: cluster)

            let width = boundingBox.size.x
            let height = boundingBox.size.y
            let depth = boundingBox.size.z
            let position = SIMD2<Float>(boundingBox.center.x, boundingBox.center.z)

            // 3. Validate height is in refrigerator range
            guard Self.fridgeMinHeight...Self.fridgeMaxHeight ~= height else { continue }

            // 4. Validate width is reasonable for refrigerator
            guard width >= Self.fridgeMinWidth && width <= Self.fridgeMaxWidth else { continue }

            // 5. Determine if counter-depth or standard based on depth
            let isCounterDepth = StandardApplianceSizes.isCounterDepthFridge(depth)
            let isStandardDepth = StandardApplianceSizes.fridgeDepthStandard.contains(depth)

            // If depth doesn't match either range, lower confidence
            var confidence: AIConfidenceLevel = .high
            var notes: [String] = []

            if !isCounterDepth && !isStandardDepth {
                confidence = .medium
                notes.append("Non-standard depth: \(String(format: "%.1f", depth))\"")
            }

            // 6. Check for overlap with existing tall cabinets (AC13)
            let tallCabinets = cabinets.cabinets.filter { $0.type == .tall }
            let overlapsWithTallCabinet = tallCabinets.contains { cabinet in
                let cabinetPos = SIMD2<Float>(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
                let distance = simd_length(position - cabinetPos)
                return distance < 12  // Within 12 inches = likely same object
            }

            // Per Task 3.8: If overlaps with tall cabinet AND depth is shallow,
            // flag as uncertain but DON'T skip - let user verify (MEDIUM-2 fix)
            if overlapsWithTallCabinet && isCounterDepth {
                confidence = .low
                notes.append("Verify: may be tall cabinet (shallow depth, overlaps detected cabinet)")
            } else if overlapsWithTallCabinet {
                // Standard depth fridge overlapping with tall cabinet - unusual, flag it
                confidence = min(confidence, .medium)
                notes.append("Verify: position overlaps with detected tall cabinet")
            }

            // 7. Snap width to standard size
            let (snappedWidth, widthDiff) = StandardApplianceSizes.nearestFridgeWidth(to: width)
            let isStandardWidth = widthDiff <= StandardApplianceSizes.snapHighThreshold

            if !isStandardWidth && widthDiff <= StandardApplianceSizes.snapMediumThreshold {
                confidence = min(confidence, .medium)
            } else if !isStandardWidth {
                notes.append("Non-standard width: \(String(format: "%.1f", width))\"")
                confidence = min(confidence, .low)
            }

            // 8. Classify subtype based on dimensions
            let subType = classifyRefrigeratorSubtype(width: width, height: height, depth: depth)

            // 9. Find nearest wall
            let (wallId, positionOnWall) = findNearestWall(
                position: position,
                roomStructure: roomStructure
            )

            // 10. Create snapped dimensions
            let snappedDepth: Float = isCounterDepth ? 26.0 : 32.0  // Standard counter-depth or standard
            let snappedDimensions = SIMD3<Float>(snappedWidth, round(height), snappedDepth)
            let rawDimensions = SIMD3<Float>(width, height, depth)

            // 11. Create refrigerator appliance
            let refrigerator = AIDetectedAppliance(
                boundingBox: boundingBox,
                type: .refrigerator,
                subType: subType,
                rawDimensions: rawDimensions,
                snappedDimensions: snappedDimensions,
                position: position,
                wallId: wallId,
                positionOnWallInches: positionOnWall,
                confidence: confidence,
                isBuiltIn: false,
                isStandardSize: isStandardWidth && (isCounterDepth || isStandardDepth),
                isCounterDepth: isCounterDepth,
                notes: notes
            )

            refrigerators.append(refrigerator)
        }

        return refrigerators
    }

    /// Classifies refrigerator subtype based on dimensions.
    ///
    /// - Parameters:
    ///   - width: Refrigerator width in inches
    ///   - height: Refrigerator height in inches
    ///   - depth: Refrigerator depth in inches
    /// - Returns: Detected subtype or nil if uncertain
    private func classifyRefrigeratorSubtype(
        width: Float,
        height: Float,
        depth: Float
    ) -> AIApplianceSubType? {
        // Counter-depth is a specific subtype
        if StandardApplianceSizes.isCounterDepthFridge(depth) {
            return .fridgeCounterDepth
        }

        // Without visual features, default to nil (generic refrigerator)
        // Subtypes like French door vs side-by-side require door detection
        // which is beyond geometric analysis
        return nil
    }

    /// Clusters points that are at tall unit height.
    ///
    /// - Parameters:
    ///   - points: All points in point cloud
    ///   - floorY: Y coordinate of floor
    ///   - minHeight: Minimum height from floor in inches
    ///   - maxHeight: Maximum height from floor in inches
    /// - Returns: Array of point clusters
    private func clusterTallPoints(
        points: [SIMD3<Float>],
        floorY: Float,
        minHeight: Float,
        maxHeight: Float
    ) -> [[SIMD3<Float>]] {
        // Filter points to target height range
        let tallPoints = points.filter { point in
            let heightFromFloor = point.y - floorY
            return heightFromFloor >= minHeight && heightFromFloor <= maxHeight
        }

        guard !tallPoints.isEmpty else { return [] }

        // Simple grid-based clustering for tall points
        // Group points within 6" horizontally
        let clusterRadius: Float = 6.0
        var clusters: [[SIMD3<Float>]] = []
        var assigned = Set<Int>()

        for (i, point) in tallPoints.enumerated() {
            guard !assigned.contains(i) else { continue }

            var cluster = [point]
            assigned.insert(i)

            // Find all points within cluster radius (XZ plane)
            for (j, otherPoint) in tallPoints.enumerated() where j != i {
                guard !assigned.contains(j) else { continue }

                let dx = point.x - otherPoint.x
                let dz = point.z - otherPoint.z
                let horizontalDistance = sqrt(dx * dx + dz * dz)

                if horizontalDistance <= clusterRadius {
                    cluster.append(otherPoint)
                    assigned.insert(j)
                }
            }

            if cluster.count >= Self.minPointsForAppliance / 2 {
                // Expand cluster to include all related points (including lower points of same object)
                let expandedCluster = expandClusterVertically(
                    seed: cluster,
                    allPoints: points,
                    floorY: floorY,
                    radius: clusterRadius
                )
                clusters.append(expandedCluster)
            }
        }

        return clusters
    }

    /// Expands a cluster vertically to capture full object height.
    ///
    /// - Parameters:
    ///   - seed: Initial cluster of tall points
    ///   - allPoints: All points in point cloud
    ///   - floorY: Y coordinate of floor
    ///   - radius: Horizontal clustering radius
    /// - Returns: Expanded cluster with full vertical extent
    private func expandClusterVertically(
        seed: [SIMD3<Float>],
        allPoints: [SIMD3<Float>],
        floorY: Float,
        radius: Float
    ) -> [SIMD3<Float>] {
        // Find center of seed cluster in XZ
        let sumX = seed.reduce(0) { $0 + $1.x }
        let sumZ = seed.reduce(0) { $0 + $1.z }
        let centerX = sumX / Float(seed.count)
        let centerZ = sumZ / Float(seed.count)

        // Include all points within radius of center XZ, from floor upward
        return allPoints.filter { point in
            let dx = point.x - centerX
            let dz = point.z - centerZ
            let horizontalDistance = sqrt(dx * dx + dz * dz)
            let heightFromFloor = point.y - floorY

            return horizontalDistance <= radius * 2 && heightFromFloor >= 0
        }
    }

    /// Calculates a 3D bounding box for a set of points.
    ///
    /// - Parameter points: Points to calculate bounding box for
    /// - Returns: AIBoundingBox3D enclosing all points
    private func calculateBoundingBox(points: [SIMD3<Float>]) -> AIBoundingBox3D {
        guard !points.isEmpty else {
            return AIBoundingBox3D(center: .zero, size: .zero)
        }

        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        var minZ = points[0].z, maxZ = points[0].z

        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }

        let center = SIMD3<Float>(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )

        let size = SIMD3<Float>(
            maxX - minX,
            maxY - minY,
            maxZ - minZ
        )

        return AIBoundingBox3D(center: center, size: size)
    }

    /// Finds the nearest wall to a position.
    ///
    /// - Parameters:
    ///   - position: 2D position (x, z) in room coordinates
    ///   - roomStructure: Room structure with walls
    /// - Returns: Tuple of (wall ID, position along wall in inches)
    private func findNearestWall(
        position: SIMD2<Float>,
        roomStructure: AIRoomStructure
    ) -> (UUID?, Float?) {
        guard !roomStructure.walls.isEmpty else { return (nil, nil) }

        var nearestWall: AIWall?
        var nearestDistance: Float = .infinity
        var positionOnWall: Float = 0

        for wall in roomStructure.walls {
            // Calculate distance from position to wall line segment
            // Note: wall.startPoint and wall.endPoint are already SIMD2<Float>
            let wallStart = wall.startPoint
            let wallEnd = wall.endPoint

            let (distance, projectionRatio) = distanceToLineSegment(
                point: position,
                lineStart: wallStart,
                lineEnd: wallEnd
            )

            if distance < nearestDistance && distance <= Self.wallProximityThreshold {
                nearestDistance = distance
                nearestWall = wall

                // Calculate position along wall
                let wallLength = Float(wall.lengthInches)
                positionOnWall = projectionRatio * wallLength
            }
        }

        return (nearestWall?.id, nearestWall != nil ? positionOnWall : nil)
    }

    /// Calculates distance from a point to a line segment.
    ///
    /// - Parameters:
    ///   - point: 2D point
    ///   - lineStart: Start of line segment
    ///   - lineEnd: End of line segment
    /// - Returns: Tuple of (distance, projection ratio along line 0-1)
    private func distanceToLineSegment(
        point: SIMD2<Float>,
        lineStart: SIMD2<Float>,
        lineEnd: SIMD2<Float>
    ) -> (Float, Float) {
        let lineVec = lineEnd - lineStart
        let lineLengthSq = simd_length_squared(lineVec)

        guard lineLengthSq > 0 else {
            return (simd_length(point - lineStart), 0)
        }

        // Project point onto line, clamped to segment
        let t = max(0, min(1, simd_dot(point - lineStart, lineVec) / lineLengthSq))
        let projection = lineStart + t * lineVec
        let distance = simd_length(point - projection)

        return (distance, t)
    }

    // MARK: - Range/Cooktop Detection

    /// Detects ranges and cooktops by position in cabinet gaps.
    ///
    /// **Algorithm (Task 4):**
    /// 1. Find gaps in base cabinet runs (30" or 36" wide)
    /// 2. Verify point density at cooktop height (36")
    /// 3. Snap width to standard sizes ONLY (30" or 36")
    /// 4. Classify as range (full height) or cooktop (surface only)
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - roomStructure: Room structure with walls
    ///   - cabinets: Detected cabinets
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected ranges/cooktops
    private func detectRanges(
        points: [SIMD3<Float>],
        roomStructure: AIRoomStructure,
        cabinets: CabinetDetectionResult,
        floorY: Float
    ) -> [AIDetectedAppliance] {
        var ranges: [AIDetectedAppliance] = []

        // Get base cabinets for gap detection
        let baseCabinets = cabinets.cabinets.filter { $0.type == .base }
        guard !baseCabinets.isEmpty else { return [] }

        // Find gaps in base cabinet runs
        let gaps = findBaseCabinetGaps(baseCabinets: baseCabinets, roomStructure: roomStructure)

        for gap in gaps {
            // Validate gap width is range-sized
            guard gap.width >= Self.rangeMinWidth && gap.width <= Self.rangeMaxWidth else { continue }

            // Check for point density at countertop height
            let pointsInGap = findPointsInRegion(
                points: points,
                center: SIMD2<Float>(gap.centerX, gap.centerZ),
                width: gap.width + 4,  // Slight margin
                depth: 28,
                minY: floorY,
                maxY: floorY + Self.countertopHeight + 6
            )

            // Require minimum points to avoid false positives from empty gaps
            guard pointsInGap.count >= Self.minPointsForAppliance else {
                continue
            }

            // Calculate actual bounding box from points
            let boundingBox = calculateBoundingBox(points: pointsInGap)
            let rawWidth = boundingBox.size.x
            let height = boundingBox.size.y
            let depth = boundingBox.size.z

            // Snap to standard range widths ONLY (30" or 36")
            let (snappedWidth, widthDiff) = StandardApplianceSizes.nearestRangeWidth(to: rawWidth)

            var confidence: AIConfidenceLevel = .high
            var notes: [String] = []

            if widthDiff > StandardApplianceSizes.snapHighThreshold {
                confidence = .medium
            }
            if widthDiff > StandardApplianceSizes.snapMediumThreshold {
                confidence = .low
                notes.append("Non-standard width: \(String(format: "%.1f", rawWidth))\"")
            }

            // Determine if range (full height ~36") or cooktop (surface only ~4")
            let isCooktop = height < 10
            let type: AIApplianceType = isCooktop ? .cooktop : .range

            // Classify subtype based on surrounding cabinets
            var subType: AIApplianceSubType?
            if !isCooktop {
                // Check if slide-in (flush with cabinets) or freestanding (visible sides)
                let hasVisibleSides = gap.hasVisibleSides
                subType = hasVisibleSides ? .rangeFreestanding : .rangeSlideIn
            }

            // Determine snapped depth
            let snappedDepth: Float = 26  // Standard range depth
            let snappedDimensions = SIMD3<Float>(snappedWidth, StandardApplianceSizes.rangeHeight, snappedDepth)

            // Find wall and position
            let position = SIMD2<Float>(gap.centerX, gap.centerZ)
            let (wallId, positionOnWall) = findNearestWall(position: position, roomStructure: roomStructure)

            let range = AIDetectedAppliance(
                boundingBox: boundingBox,
                type: type,
                subType: subType,
                rawDimensions: SIMD3<Float>(rawWidth, height, depth),
                snappedDimensions: snappedDimensions,
                position: position,
                wallId: wallId,
                positionOnWallInches: positionOnWall,
                confidence: confidence,
                isBuiltIn: false,
                isStandardSize: widthDiff <= StandardApplianceSizes.snapHighThreshold,
                isCounterDepth: false,
                notes: notes
            )

            ranges.append(range)
        }

        return ranges
    }

    /// Represents a gap between base cabinets where a range might be located.
    private struct CabinetGap {
        let centerX: Float
        let centerZ: Float
        let width: Float
        let leftCabinetId: UUID?
        let rightCabinetId: UUID?
        let hasVisibleSides: Bool

        init(centerX: Float, centerZ: Float, width: Float, leftCabinetId: UUID? = nil, rightCabinetId: UUID? = nil) {
            self.centerX = centerX
            self.centerZ = centerZ
            self.width = width
            self.leftCabinetId = leftCabinetId
            self.rightCabinetId = rightCabinetId
            self.hasVisibleSides = (leftCabinetId == nil) || (rightCabinetId == nil)
        }
    }

    /// Finds gaps in base cabinet runs that could contain ranges.
    ///
    /// - Parameters:
    ///   - baseCabinets: All detected base cabinets
    ///   - roomStructure: Room structure with walls
    /// - Returns: Array of gaps that could contain ranges
    private func findBaseCabinetGaps(
        baseCabinets: [AIDetectedCabinet],
        roomStructure: AIRoomStructure
    ) -> [CabinetGap] {
        var gaps: [CabinetGap] = []

        // Group cabinets by wall
        let cabinetsByWall = Dictionary(grouping: baseCabinets, by: { $0.wallId })

        for (_, cabinets) in cabinetsByWall {
            // Sort cabinets by position along wall
            let sortedCabinets = cabinets.sorted { $0.positionOnWallInches < $1.positionOnWallInches }

            // Find gaps between adjacent cabinets
            for i in 0..<(sortedCabinets.count - 1) {
                let leftCabinet = sortedCabinets[i]
                let rightCabinet = sortedCabinets[i + 1]

                let leftEnd = leftCabinet.positionOnWallInches + leftCabinet.widthInches / 2
                let rightStart = rightCabinet.positionOnWallInches - rightCabinet.widthInches / 2
                let gapWidth = rightStart - leftEnd

                // Range-sized gap
                if gapWidth >= Self.rangeMinWidth && gapWidth <= Self.rangeMaxWidth {
                    let gapCenter = (leftEnd + rightStart) / 2

                    // Calculate 2D position from wall and position
                    let centerX = (leftCabinet.boundingBox.center.x + rightCabinet.boundingBox.center.x) / 2
                    let centerZ = (leftCabinet.boundingBox.center.z + rightCabinet.boundingBox.center.z) / 2

                    gaps.append(CabinetGap(
                        centerX: centerX,
                        centerZ: centerZ,
                        width: gapWidth,
                        leftCabinetId: leftCabinet.id,
                        rightCabinetId: rightCabinet.id
                    ))
                }
            }
        }

        return gaps
    }

    /// Finds points within a 2D region at specified height range.
    ///
    /// - Parameters:
    ///   - points: All points
    ///   - center: Center of region (x, z)
    ///   - width: Region width
    ///   - depth: Region depth
    ///   - minY: Minimum Y coordinate
    ///   - maxY: Maximum Y coordinate
    /// - Returns: Points within the region
    private func findPointsInRegion(
        points: [SIMD3<Float>],
        center: SIMD2<Float>,
        width: Float,
        depth: Float,
        minY: Float,
        maxY: Float
    ) -> [SIMD3<Float>] {
        let halfWidth = width / 2
        let halfDepth = depth / 2

        return points.filter { point in
            let inX = abs(point.x - center.x) <= halfWidth
            let inZ = abs(point.z - center.y) <= halfDepth  // center.y is z in SIMD2
            let inY = point.y >= minY && point.y <= maxY
            return inX && inZ && inY
        }
    }

    // MARK: - Sink Detection

    /// Detects sinks by countertop depressions.
    ///
    /// **Algorithm (Task 8):**
    /// 1. Find depressions in countertop surface (points below 36" counter level)
    /// 2. Position hint: often centered under window
    /// 3. Classify: single bowl, double bowl, farmhouse
    /// 4. Task 8.8: Check for island sinks
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - roomStructure: Room structure with walls
    ///   - islands: Detected islands
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected sinks
    private func detectSinks(
        points: [SIMD3<Float>],
        roomStructure: AIRoomStructure,
        islands: [AIDetectedIsland],
        floorY: Float
    ) -> [AIDetectedAppliance] {
        var sinks: [AIDetectedAppliance] = []

        let countertopY = floorY + Self.countertopHeight

        // Find points that form depressions below countertop level
        // Sink basin is typically 8"-10" deep from countertop surface
        let sinkMinY = countertopY - 12
        let sinkMaxY = countertopY - 4

        let depressionPoints = points.filter { point in
            point.y >= sinkMinY && point.y <= sinkMaxY
        }

        guard depressionPoints.count >= Self.minPointsForAppliance else {
            return []
        }

        // Cluster depression points to find distinct sinks
        let sinkClusters = clusterDepressionPoints(points: depressionPoints)

        for cluster in sinkClusters {
            guard cluster.count >= Self.minPointsForAppliance / 2 else { continue }

            let boundingBox = calculateBoundingBox(points: cluster)
            let width = boundingBox.size.x
            let depth = boundingBox.size.z
            let position = SIMD2<Float>(boundingBox.center.x, boundingBox.center.z)

            // Validate sink dimensions
            guard width >= Self.sinkMinWidth && width <= Self.sinkMaxWidth else { continue }
            guard depth >= Self.sinkMinDepth && depth <= Self.sinkMaxDepth else { continue }

            var confidence: AIConfidenceLevel = .high
            var notes: [String] = []

            // Classify sink subtype based on dimensions
            var subType: AIApplianceSubType?
            var snappedDimensions: SIMD3<Float>

            // Check for farmhouse sink (apron front - extends below counter line)
            let hasApronFront = points.contains { point in
                let inX = abs(point.x - boundingBox.center.x) <= width / 2
                let inZ = abs(point.z - boundingBox.center.z) <= depth / 2
                let belowCounter = point.y < sinkMinY && point.y > floorY + 30
                return inX && inZ && belowCounter
            }

            if hasApronFront && StandardApplianceSizes.sinkFarmhouseWidthRange.contains(width) {
                subType = .sinkFarmhouse
                snappedDimensions = SIMD3<Float>(
                    max(30, min(36, round(width))),
                    10,  // Approximate basin depth
                    21   // Standard farmhouse depth
                )
            } else if width >= 30 {
                // Double bowl sink
                subType = .sinkDoubleBowl
                snappedDimensions = SIMD3<Float>(
                    StandardApplianceSizes.sinkDouble.x,
                    10,
                    StandardApplianceSizes.sinkDouble.y
                )
            } else {
                // Single bowl sink
                subType = .sinkSingleBowl
                snappedDimensions = SIMD3<Float>(
                    StandardApplianceSizes.sinkSingle.x,
                    10,
                    StandardApplianceSizes.sinkSingle.y
                )
            }

            // Check if this is an island sink (Task 8.8)
            let isIslandSink = islands.contains { island in
                island.contains(point: position, tolerance: 6)
            }

            if isIslandSink {
                notes.append("Island sink")
            }

            // Find nearest wall (nil for island sinks)
            let (wallId, positionOnWall): (UUID?, Float?)
            if isIslandSink {
                wallId = nil
                positionOnWall = nil
            } else {
                (wallId, positionOnWall) = findNearestWall(position: position, roomStructure: roomStructure)
            }

            let sink = AIDetectedAppliance(
                boundingBox: boundingBox,
                type: .sink,
                subType: subType,
                rawDimensions: SIMD3<Float>(width, boundingBox.size.y, depth),
                snappedDimensions: snappedDimensions,
                position: position,
                wallId: wallId,
                positionOnWallInches: positionOnWall,
                confidence: confidence,
                isBuiltIn: true,
                isStandardSize: true,
                isCounterDepth: false,
                notes: notes
            )

            sinks.append(sink)
        }

        return sinks
    }

    /// Clusters depression points to find distinct sink basins.
    ///
    /// - Parameter points: Points in depression region
    /// - Returns: Array of point clusters representing distinct sinks
    private func clusterDepressionPoints(points: [SIMD3<Float>]) -> [[SIMD3<Float>]] {
        guard !points.isEmpty else { return [] }

        let clusterRadius: Float = 12.0  // Sinks are larger than typical cluster radius
        var clusters: [[SIMD3<Float>]] = []
        var assigned = Set<Int>()

        for (i, point) in points.enumerated() {
            guard !assigned.contains(i) else { continue }

            var cluster = [point]
            assigned.insert(i)

            for (j, otherPoint) in points.enumerated() where j != i {
                guard !assigned.contains(j) else { continue }

                let dx = point.x - otherPoint.x
                let dz = point.z - otherPoint.z
                let horizontalDistance = sqrt(dx * dx + dz * dz)

                if horizontalDistance <= clusterRadius {
                    cluster.append(otherPoint)
                    assigned.insert(j)
                }
            }

            if cluster.count >= Self.minPointsForAppliance / 3 {
                clusters.append(cluster)
            }
        }

        return clusters
    }

    // MARK: - Microwave Detection

    /// Detects microwaves by position relative to ranges.
    ///
    /// **Algorithm (Task 6):**
    /// 1. OTR Microwave: Above range position, 30" width
    /// 2. Built-in: Within upper/tall cabinet bounds
    /// 3. Task 6.6: If OTR detected, flag for hood mutual exclusion
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - ranges: Detected ranges
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected microwaves
    private func detectMicrowaves(
        points: [SIMD3<Float>],
        ranges: [AIDetectedAppliance],
        floorY: Float
    ) -> [AIDetectedAppliance] {
        var microwaves: [AIDetectedAppliance] = []

        // 1. Detect OTR microwaves above each range
        for range in ranges {
            // OTR microwave position: above range, typically 54"-66" from floor
            let otrMinY = floorY + Self.countertopHeight + 18  // ~54" from floor
            let otrMaxY = floorY + 66  // ~66" from floor

            let pointsAboveRange = findPointsInRegion(
                points: points,
                center: range.position,
                width: StandardApplianceSizes.microwaveOTRWidth + 4,
                depth: 18,
                minY: otrMinY,
                maxY: otrMaxY
            )

            guard pointsAboveRange.count >= Self.minPointsForAppliance / 2 else {
                continue
            }

            // Calculate bounding box for microwave
            let boundingBox = calculateBoundingBox(points: pointsAboveRange)
            let width = boundingBox.size.x
            let height = boundingBox.size.y

            // Validate OTR microwave dimensions
            guard width >= Self.microwaveOTRMinWidth && width <= Self.microwaveOTRMaxWidth else { continue }
            guard StandardApplianceSizes.microwaveOTRHeightRange.contains(height) ||
                  height >= 14 && height <= 20 else { continue }

            var confidence: AIConfidenceLevel = .high
            var notes: [String] = []

            // OTR microwave should be ~30" wide
            if abs(width - StandardApplianceSizes.microwaveOTRWidth) > 2 {
                confidence = .medium
            }

            let snappedDimensions = SIMD3<Float>(
                StandardApplianceSizes.microwaveOTRWidth,
                17,  // Standard OTR height
                16   // Standard OTR depth
            )

            let microwave = AIDetectedAppliance(
                boundingBox: boundingBox,
                type: .microwave,
                subType: .microwaveOTR,
                rawDimensions: SIMD3<Float>(width, height, boundingBox.size.z),
                snappedDimensions: snappedDimensions,
                position: range.position,  // Same position as range
                wallId: range.wallId,
                positionOnWallInches: range.positionOnWallInches,
                confidence: confidence,
                isBuiltIn: true,
                isStandardSize: abs(width - StandardApplianceSizes.microwaveOTRWidth) <= 1,
                isCounterDepth: false,
                notes: notes
            )

            microwaves.append(microwave)
        }

        return microwaves
    }

    // MARK: - Hood Detection

    /// Detects hoods with mutual exclusion for OTR microwaves.
    ///
    /// **Algorithm (Task 7):**
    /// 1. Check above each range position (24"-30" above cooktop)
    /// 2. AC11: Skip if OTR microwave already at that position
    /// 3. Width should match or exceed range width (AC12)
    /// 4. Classify: wall-mount chimney, under-cabinet, island
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - ranges: Detected ranges
    ///   - islands: Detected islands
    ///   - otrMicrowavePositions: Positions of OTR microwaves (for mutual exclusion)
    ///   - roomStructure: Room structure with walls
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected hoods
    private func detectHoods(
        points: [SIMD3<Float>],
        ranges: [AIDetectedAppliance],
        islands: [AIDetectedIsland],
        otrMicrowavePositions: [SIMD2<Float>],
        roomStructure: AIRoomStructure,
        floorY: Float
    ) -> [AIDetectedAppliance] {
        var hoods: [AIDetectedAppliance] = []

        for range in ranges {
            // AC11: Check mutual exclusion - skip if OTR microwave at this position
            let hasOTRMicrowave = otrMicrowavePositions.contains { pos in
                simd_length(pos - range.position) < 12
            }

            if hasOTRMicrowave {
                #if DEBUG
                logger.debug("Skipping hood detection at range position - OTR microwave present")
                #endif
                continue
            }

            // Hood position: 24"-30" above cooktop surface (which is at ~36" from floor)
            let hoodMinY = floorY + Self.countertopHeight + Float(StandardApplianceSizes.hoodHeightAboveCooktop.lowerBound)
            let hoodMaxY = floorY + Self.countertopHeight + Float(StandardApplianceSizes.hoodHeightAboveCooktop.upperBound) + 12

            let pointsAboveRange = findPointsInRegion(
                points: points,
                center: range.position,
                width: 50,  // Hoods can be up to 48"
                depth: 24,
                minY: hoodMinY,
                maxY: hoodMaxY
            )

            guard pointsAboveRange.count >= Self.minPointsForAppliance / 2 else {
                continue
            }

            // Calculate bounding box for hood
            let boundingBox = calculateBoundingBox(points: pointsAboveRange)
            let width = boundingBox.size.x
            let height = boundingBox.size.y
            let depth = boundingBox.size.z

            // Snap to standard hood widths
            let (snappedWidth, widthDiff) = StandardApplianceSizes.nearestHoodWidth(to: width)

            var confidence: AIConfidenceLevel = .high
            var notes: [String] = []

            // AC12: Hood width must match or exceed range width
            if snappedWidth < range.widthInches {
                confidence = .medium
                notes.append("Hood width (\(Int(snappedWidth))\") smaller than range (\(Int(range.widthInches))\")")
            }

            if widthDiff > StandardApplianceSizes.snapHighThreshold {
                confidence = min(confidence, .medium)
            }

            // Determine hood subtype
            let subType: AIApplianceSubType?

            // Check if island hood (above island cooktop)
            let isAboveIsland = islands.contains { island in
                island.contains(point: range.position, tolerance: 12)
            }

            if isAboveIsland {
                subType = .hoodIsland
            } else if height > 20 {
                // Tall hood = chimney style wall-mount
                subType = .hoodWallMount
            } else {
                // Short hood = under-cabinet
                subType = .hoodUnderCabinet
            }

            let snappedDimensions = SIMD3<Float>(
                snappedWidth,
                height,
                min(depth, 24)  // Standard hood depth
            )

            let hood = AIDetectedAppliance(
                boundingBox: boundingBox,
                type: .hood,
                subType: subType,
                rawDimensions: SIMD3<Float>(width, height, depth),
                snappedDimensions: snappedDimensions,
                position: range.position,
                wallId: range.wallId,
                positionOnWallInches: range.positionOnWallInches,
                confidence: confidence,
                isBuiltIn: false,
                isStandardSize: widthDiff <= StandardApplianceSizes.snapHighThreshold,
                isCounterDepth: false,
                notes: notes
            )

            hoods.append(hood)
        }

        return hoods
    }

    // MARK: - Dishwasher Detection

    /// Detects dishwashers by proximity to sinks.
    ///
    /// **Algorithm (Task 5):**
    /// 1. REQUIRES sink detection first (per AC12)
    /// 2. Search within 36" of each detected sink
    /// 3. Look for 24" or 18" width base cabinet gaps
    /// 4. Support dual dishwashers (luxury kitchens)
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - cabinets: Detected cabinets
    ///   - sinks: Detected sinks
    ///   - floorY: Y coordinate of floor
    /// - Returns: Array of detected dishwashers
    private func detectDishwashers(
        points: [SIMD3<Float>],
        cabinets: CabinetDetectionResult,
        sinks: [AIDetectedAppliance],
        floorY: Float
    ) -> [AIDetectedAppliance] {
        // Per AC12: Dishwasher detection requires sink
        guard !sinks.isEmpty else {
            #if DEBUG
            logger.info("Skipping dishwasher detection - no sinks detected")
            #endif
            return []
        }

        var dishwashers: [AIDetectedAppliance] = []
        let baseCabinets = cabinets.cabinets.filter { $0.type == .base }

        // Search near each sink (Task 5.6: check BOTH sides for dual dishwashers)
        for sink in sinks {
            // Find cabinets within 36" of sink
            let nearbyCabinets = baseCabinets.filter { cabinet in
                let cabinetPos = SIMD2<Float>(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
                let distance = simd_length(cabinetPos - sink.position)
                return distance <= StandardApplianceSizes.dishwasherMaxDistanceFromSink
            }

            // Look for dishwasher-sized gaps (24" standard, 18" compact)
            for cabinet in nearbyCabinets {
                let width = cabinet.widthInches

                // Check if width matches dishwasher sizes
                let (snappedWidth, widthDiff) = StandardApplianceSizes.nearestDishwasherWidth(to: width)
                guard widthDiff <= 3 else { continue }

                // Check for points at dishwasher location
                let cabinetPos = SIMD2<Float>(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
                let pointsAtLocation = findPointsInRegion(
                    points: points,
                    center: cabinetPos,
                    width: width + 2,
                    depth: 26,
                    minY: floorY,
                    maxY: floorY + StandardApplianceSizes.dishwasherHeight + 2
                )

                var confidence: AIConfidenceLevel
                var subType: AIApplianceSubType?
                var notes: [String] = []

                // Determine confidence based on detection method
                if pointsAtLocation.count >= Self.minPointsForAppliance {
                    // Good point density - likely visible dishwasher
                    confidence = widthDiff <= 1 ? .high : .medium
                    subType = width >= 22 ? .dishwasherStandard : .dishwasherCompact
                } else {
                    // Task 5.5: Panel-ready dishwasher (looks like cabinet)
                    confidence = .low
                    subType = .dishwasherPanelReady
                    notes.append("Possible panel-ready dishwasher")
                }

                // Create bounding box
                let boundingBox = AIBoundingBox3D(
                    center: SIMD3<Float>(cabinetPos.x, floorY + StandardApplianceSizes.dishwasherHeight / 2, cabinetPos.y),
                    size: SIMD3<Float>(snappedWidth, StandardApplianceSizes.dishwasherHeight, StandardApplianceSizes.dishwasherDepth)
                )

                // Check we're not creating a duplicate
                let isDuplicate = dishwashers.contains { existing in
                    simd_length(existing.position - cabinetPos) < 12
                }
                guard !isDuplicate else { continue }

                let dishwasher = AIDetectedAppliance(
                    boundingBox: boundingBox,
                    type: .dishwasher,
                    subType: subType,
                    rawDimensions: SIMD3<Float>(width, StandardApplianceSizes.dishwasherHeight, StandardApplianceSizes.dishwasherDepth),
                    snappedDimensions: SIMD3<Float>(snappedWidth, StandardApplianceSizes.dishwasherHeight, StandardApplianceSizes.dishwasherDepth),
                    position: cabinetPos,
                    wallId: cabinet.wallId,
                    positionOnWallInches: cabinet.positionOnWallInches,
                    confidence: confidence,
                    isBuiltIn: true,
                    isStandardSize: widthDiff <= 1,
                    isCounterDepth: false,
                    notes: notes
                )

                dishwashers.append(dishwasher)
            }
        }

        return dishwashers
    }

    // MARK: - Deduplication (AC14)

    /// Deduplicates overlapping appliance detections.
    ///
    /// - Parameter appliances: All detected appliances
    /// - Returns: Deduplicated appliances (higher confidence kept)
    private func deduplicateAppliances(_ appliances: [AIDetectedAppliance]) -> [AIDetectedAppliance] {
        guard appliances.count > 1 else { return appliances }

        var result: [AIDetectedAppliance] = []
        var processed: Set<UUID> = []

        for appliance in appliances {
            if processed.contains(appliance.id) { continue }

            // Find overlapping appliances
            let overlapping = appliances.filter { other in
                guard other.id != appliance.id else { return false }
                guard !processed.contains(other.id) else { return false }
                return boundingBoxOverlap(appliance.boundingBox, other.boundingBox) > 0.5
            }

            if overlapping.isEmpty {
                result.append(appliance)
            } else {
                // Keep highest confidence
                let allCandidates = [appliance] + overlapping
                if let best = allCandidates.max(by: { $0.confidence < $1.confidence }) {
                    result.append(best)
                    allCandidates.forEach { processed.insert($0.id) }
                }
            }

            processed.insert(appliance.id)
        }

        return result
    }

    /// Calculates overlap ratio between two bounding boxes.
    ///
    /// - Parameters:
    ///   - box1: First bounding box
    ///   - box2: Second bounding box
    /// - Returns: Overlap ratio (0.0 to 1.0)
    private func boundingBoxOverlap(_ box1: AIBoundingBox3D, _ box2: AIBoundingBox3D) -> Float {
        let overlapX = max(0, min(box1.max.x, box2.max.x) - max(box1.min.x, box2.min.x))
        let overlapY = max(0, min(box1.max.y, box2.max.y) - max(box1.min.y, box2.min.y))
        let overlapZ = max(0, min(box1.max.z, box2.max.z) - max(box1.min.z, box2.min.z))

        let overlapVolume = overlapX * overlapY * overlapZ
        let box1Volume = box1.size.x * box1.size.y * box1.size.z
        let box2Volume = box2.size.x * box2.size.y * box2.size.z
        let minVolume = min(box1Volume, box2Volume)

        guard minVolume > 0 else { return 0 }
        return overlapVolume / minVolume
    }

    // MARK: - Cross-Validation (AC12, AC13)

    /// Validates appliance relationships and positions.
    ///
    /// - Parameters:
    ///   - appliances: All detected appliances
    ///   - cabinets: Detected cabinets
    /// - Returns: Warning messages for validation issues
    private func validateApplianceRelationships(
        appliances: [AIDetectedAppliance],
        cabinets: CabinetDetectionResult
    ) -> [String] {
        var warnings: [String] = []

        // Validate hood-range width relationship (AC12)
        let ranges = appliances.filter { $0.type == .range || $0.type == .cooktop }
        let hoods = appliances.filter { $0.type == .hood }

        for hood in hoods {
            // Find associated range (nearest)
            if let nearestRange = ranges.min(by: {
                simd_length($0.position - hood.position) < simd_length($1.position - hood.position)
            }) {
                if hood.widthInches < nearestRange.widthInches {
                    warnings.append("Hood width (\(Int(hood.widthInches))\") is smaller than range width (\(Int(nearestRange.widthInches))\")")
                }
            }
        }

        // Validate dishwasher-sink proximity (AC12)
        let sinks = appliances.filter { $0.type == .sink }
        let dishwashers = appliances.filter { $0.type == .dishwasher }

        for dishwasher in dishwashers {
            let nearestSinkDistance = sinks.map { simd_length($0.position - dishwasher.position) }.min() ?? Float.infinity
            if nearestSinkDistance > StandardApplianceSizes.dishwasherMaxDistanceFromSink {
                warnings.append("Dishwasher detected \(Int(nearestSinkDistance))\" from nearest sink (expected ≤36\")")
            }
        }

        // AC13: Validate appliance-cabinet alignment
        let cabinetAlignmentWarnings = validateApplianceCabinetAlignment(
            appliances: appliances,
            cabinets: cabinets
        )
        warnings.append(contentsOf: cabinetAlignmentWarnings)

        return warnings
    }

    // MARK: - Cabinet Alignment Validation (AC13)

    /// Validates that appliance positions align with gaps in cabinet layout.
    ///
    /// **AC13 Requirements:**
    /// - Appliance positions must align with gaps in cabinet detection
    /// - Range/cooktop position must match gap in base cabinet run
    /// - Refrigerator position must not overlap with detected cabinets
    ///
    /// - Parameters:
    ///   - appliances: All detected appliances
    ///   - cabinets: Detected cabinets
    /// - Returns: Warning messages for alignment issues
    private func validateApplianceCabinetAlignment(
        appliances: [AIDetectedAppliance],
        cabinets: CabinetDetectionResult
    ) -> [String] {
        var warnings: [String] = []
        let overlapThreshold: Float = 6.0  // Inches of acceptable overlap

        // Check ranges/cooktops are in cabinet gaps
        let rangesAndCooktops = appliances.filter { $0.type == .range || $0.type == .cooktop }
        let baseCabinets = cabinets.cabinets.filter { $0.type == .base }

        for range in rangesAndCooktops {
            // Check if range overlaps with any base cabinet
            let overlappingCabinets = baseCabinets.filter { cabinet in
                let cabinetPos = SIMD2<Float>(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
                let distance = simd_length(cabinetPos - range.position)
                let combinedHalfWidth = (cabinet.widthInches + range.widthInches) / 2
                return distance < combinedHalfWidth - overlapThreshold
            }

            if !overlappingCabinets.isEmpty {
                warnings.append("Range at position (\(Int(range.position.x)), \(Int(range.position.y))) overlaps with \(overlappingCabinets.count) base cabinet(s)")
            }
        }

        // Check refrigerators don't overlap with cabinets
        let refrigerators = appliances.filter { $0.type == .refrigerator }
        let allCabinets = cabinets.cabinets

        for fridge in refrigerators {
            let overlappingCabinets = allCabinets.filter { cabinet in
                let cabinetPos = SIMD2<Float>(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
                let distance = simd_length(cabinetPos - fridge.position)
                let combinedHalfWidth = (cabinet.widthInches + fridge.widthInches) / 2
                return distance < combinedHalfWidth - overlapThreshold
            }

            if !overlappingCabinets.isEmpty {
                warnings.append("Refrigerator at position (\(Int(fridge.position.x)), \(Int(fridge.position.y))) overlaps with \(overlappingCabinets.count) cabinet(s)")
            }
        }

        // Check dishwashers are at base cabinet positions (they replace a cabinet)
        for dishwasher in appliances.filter({ $0.type == .dishwasher }) {
            // Dishwasher should be at a position where a base cabinet could be
            // This is already validated by the proximity to sink check
            // Additional check: verify it's along a wall with base cabinets
            if let wallId = dishwasher.wallId {
                let cabinetsOnSameWall = baseCabinets.filter { $0.wallId == wallId }
                if cabinetsOnSameWall.isEmpty {
                    warnings.append("Dishwasher detected on wall with no base cabinets")
                }
            }
        }

        return warnings
    }
}
