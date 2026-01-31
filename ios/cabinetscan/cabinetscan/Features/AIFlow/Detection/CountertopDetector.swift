//
//  CountertopDetector.swift
//  cabinetscan
//
//  Created for Story 4.6: Countertop Detection and Measurement
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Countertop Detector Protocol

/// Protocol for countertop detection implementations.
/// Enables testing with mock detectors.
protocol CountertopDetectorProtocol {
    /// Detects all countertops and calculates totals for quotes.
    ///
    /// **Pipeline Order:** This detector runs AFTER IslandPeninsulaDetector:
    /// RoomDetector → CabinetDetector → ApplianceDetector → IslandPeninsulaDetector → CountertopDetector
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure from RoomDetector (walls, floor plane)
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Cabinet detection result (base cabinets define countertop locations)
    ///   - appliances: Appliance detection result (for cutout detection)
    ///   - islandPeninsulaResult: Island/peninsula result (already has countertop areas)
    /// - Returns: Countertop detection result with all measurements
    /// - Throws: `CountertopDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        appliances: ApplianceDetectionResult,
        islandPeninsulaResult: IslandPeninsulaDetectionResult
    ) async throws -> CountertopDetectorResult
}

// MARK: - Detection Phase

/// Phases of countertop detection for progress tracking.
enum CountertopDetectionPhase: String {
    case idle = "Idle"
    case wallCountertopDetection = "Detecting Wall Countertops"
    case segmentation = "Segmenting Countertops"
    case cutoutDetection = "Detecting Cutouts"
    case backsplashCalculation = "Calculating Backsplash"
    case edgeTreatment = "Calculating Edge Treatment"
    case aggregation = "Building Summary"
    case confidenceScoring = "Calculating Confidence"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Detection Result

/// Result of countertop detection.
///
/// Contains wall countertops detected by this detector plus aggregated
/// summary including islands and peninsulas from Story 4.5.
struct CountertopDetectorResult: Equatable {
    /// All detected wall countertops
    let wallCountertops: [AIWallCountertop]

    /// Aggregated summary for quote generation
    let countertopSummary: AICountertopSummary

    /// Backsplash calculation details
    let backsplashSummary: AIBacksplashSummary

    /// Edge treatment summary
    let edgeTreatmentSummary: AIEdgeTreatmentSummary

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection
    let warnings: [String]

    /// Overall detection confidence
    let overallConfidence: AIConfidenceLevel

    // MARK: - Computed Properties

    /// Total countertop count (wall + island + peninsula)
    var totalCountertopCount: Int {
        wallCountertops.count +
        countertopSummary.islandCountertops.count +
        countertopSummary.peninsulaCountertops.count
    }

    /// Whether any countertops were detected
    var hasDetections: Bool {
        !wallCountertops.isEmpty ||
        !countertopSummary.islandCountertops.isEmpty ||
        !countertopSummary.peninsulaCountertops.isEmpty
    }

    /// Empty result (no detections)
    static let empty = CountertopDetectorResult(
        wallCountertops: [],
        countertopSummary: AICountertopSummary.empty,
        backsplashSummary: AIBacksplashSummary.empty,
        edgeTreatmentSummary: AIEdgeTreatmentSummary.empty,
        processingTimeMs: 0,
        warnings: [],
        overallConfidence: .low
    )
}

// MARK: - Detection Error

/// Errors that can occur during countertop detection.
enum CountertopDetectionError: LocalizedError, Equatable {
    case noRoomStructure
    case noPointCloud
    case noCabinetsDetected
    case detectionFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noRoomStructure:
            return "Room structure is required for countertop detection"
        case .noPointCloud:
            return "Point cloud is empty - cannot detect countertops"
        case .noCabinetsDetected:
            return "No base cabinets detected - cannot infer wall countertops"
        case .detectionFailed(let reason):
            return "Countertop detection failed: \(reason)"
        case .cancelled:
            return "Countertop detection was cancelled"
        }
    }
}

// MARK: - Wall Countertop

/// A wall countertop section above base cabinets.
///
/// **Coordinate System:**
/// - All dimensions are in inches (calibrated via ScaleCalibrator)
/// - `wallId` identifies which wall this countertop is against
/// - `startPositionInches` and `endPositionInches` are distances along the wall
///
/// **Quote Impact (CRITICAL):**
/// - Area = length × depth
/// - Cutouts are subtracted for net area
/// - Backsplash calculated from total wall countertop lengths
struct AIWallCountertop: Identifiable, Equatable, Codable {
    /// Unique identifier for this countertop
    let id: UUID

    /// ID of the wall this countertop is against
    let wallId: UUID

    /// Length along the wall in inches
    let lengthInches: Float

    /// Depth from wall in inches (standard: 25.5")
    let depthInches: Float

    /// Start position along wall in inches (from wall start)
    let startPositionInches: Float

    /// End position along wall in inches (from wall start)
    let endPositionInches: Float

    /// Height from floor in inches (typically 36")
    let heightFromFloorInches: Float

    /// Sections if countertop is segmented (L-shaped, depth changes)
    let sections: [AICountertopSection]

    /// Cutouts for sink, cooktop, etc.
    let cutouts: [AICountertopCutout]

    /// Detection confidence
    let confidence: AIConfidenceLevel

    /// Raw measured dimensions before any adjustment
    let rawDimensions: SIMD2<Float>  // (length, depth)

    /// Whether depth matches standard (25.5" ±2")
    let isStandardDepth: Bool

    /// Notes about the detection
    let notes: [String]

    // MARK: - Computed Properties

    /// Gross area (before cutouts) in square inches
    var grossAreaSquareInches: Float {
        if sections.isEmpty {
            return lengthInches * depthInches
        }
        return sections.reduce(0) { $0 + $1.areaSquareInches }
    }

    /// Total cutout area in square inches
    var cutoutAreaSquareInches: Float {
        cutouts.reduce(0) { $0 + $1.areaSquareInches }
    }

    /// Net area (gross - cutouts) in square inches
    var netAreaSquareInches: Float {
        grossAreaSquareInches - cutoutAreaSquareInches
    }

    /// Gross area in square feet
    var grossAreaSquareFeet: Float {
        grossAreaSquareInches / 144.0
    }

    /// Net area in square feet
    var netAreaSquareFeet: Float {
        netAreaSquareInches / 144.0
    }

    /// Front edge length in inches (for edge treatment)
    var frontEdgeInches: Float {
        lengthInches  // Only front edge exposed, wall side is not
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        wallId: UUID,
        lengthInches: Float,
        depthInches: Float,
        startPositionInches: Float,
        endPositionInches: Float,
        heightFromFloorInches: Float = 36.0,
        sections: [AICountertopSection] = [],
        cutouts: [AICountertopCutout] = [],
        confidence: AIConfidenceLevel = .medium,
        rawDimensions: SIMD2<Float>? = nil,
        isStandardDepth: Bool = true,
        notes: [String] = []
    ) {
        self.id = id
        self.wallId = wallId
        self.lengthInches = lengthInches
        self.depthInches = depthInches
        self.startPositionInches = startPositionInches
        self.endPositionInches = endPositionInches
        self.heightFromFloorInches = heightFromFloorInches
        self.sections = sections
        self.cutouts = cutouts
        self.confidence = confidence
        self.rawDimensions = rawDimensions ?? SIMD2(lengthInches, depthInches)
        self.isStandardDepth = isStandardDepth
        self.notes = notes
    }

    /// Checks if a 2D position is on this countertop.
    ///
    /// - Parameters:
    ///   - positionAlongWall: Position along wall in inches
    ///   - positionFromWall: Position perpendicular from wall in inches
    ///   - tolerance: Tolerance in inches
    /// - Returns: True if position is on countertop
    func contains(
        positionAlongWall: Float,
        positionFromWall: Float,
        tolerance: Float = 2.0
    ) -> Bool {
        let inLengthRange = positionAlongWall >= (startPositionInches - tolerance) &&
                           positionAlongWall <= (endPositionInches + tolerance)
        let inDepthRange = positionFromWall >= 0 && positionFromWall <= (depthInches + tolerance)
        return inLengthRange && inDepthRange
    }
}

// MARK: - Countertop Section

/// A section of countertop for L-shaped or depth-varied countertops.
///
/// Used when countertop has discontinuities (corners, windows, depth changes).
struct AICountertopSection: Identifiable, Equatable, Codable {
    /// Unique identifier
    let id: UUID

    /// Start position along countertop in inches
    let startPositionInches: Float

    /// End position along countertop in inches
    let endPositionInches: Float

    /// Depth of this section in inches
    let depthInches: Float

    /// Reason for section break (corner, window, depth change)
    let segmentReason: CountertopSegmentReason

    // MARK: - Computed Properties

    /// Length of this section in inches
    var lengthInches: Float {
        endPositionInches - startPositionInches
    }

    /// Area in square inches
    var areaSquareInches: Float {
        lengthInches * depthInches
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        startPositionInches: Float,
        endPositionInches: Float,
        depthInches: Float,
        segmentReason: CountertopSegmentReason = .continuous
    ) {
        self.id = id
        self.startPositionInches = startPositionInches
        self.endPositionInches = endPositionInches
        self.depthInches = depthInches
        self.segmentReason = segmentReason
    }
}

/// Reason for countertop segmentation.
enum CountertopSegmentReason: String, Codable, CaseIterable {
    /// Continuous section (no break)
    case continuous

    /// Break at corner transition
    case cornerTransition

    /// Break at window
    case window

    /// Break due to depth change
    case depthChange

    /// Break at appliance location
    case appliance

    var displayText: String {
        switch self {
        case .continuous: return "Continuous"
        case .cornerTransition: return "Corner Transition"
        case .window: return "Window"
        case .depthChange: return "Depth Change"
        case .appliance: return "Appliance"
        }
    }
}

// MARK: - Countertop Summary

/// Aggregated countertop totals for quote generation.
///
/// **ADR-2:** CountertopDetector owns aggregation into this struct.
/// Contains wall countertops (detected here) plus island/peninsula
/// countertops (from IslandPeninsulaDetectionResult).
struct AICountertopSummary: Equatable, Codable {
    /// All wall countertop sections
    let wallCountertops: [AIWallCountertop]

    /// Island countertop details (from Story 4.5)
    let islandCountertops: [AIIslandCountertop]

    /// Peninsula countertop details (from Story 4.5)
    let peninsulaCountertops: [AIPeninsulaCountertop]

    // MARK: - Wall Countertop Totals

    /// Total wall countertop length in inches
    let wallTotalLinearInches: Float

    /// Total wall countertop gross area in square inches
    let wallGrossAreaSquareInches: Float

    /// Total wall countertop net area (after cutouts) in square inches
    let wallNetAreaSquareInches: Float

    // MARK: - Island Totals

    /// Total island countertop area in square inches
    let islandTotalSquareInches: Float

    // MARK: - Peninsula Totals

    /// Total peninsula countertop area in square inches
    let peninsulaTotalSquareInches: Float

    // MARK: - Backsplash

    /// Total backsplash length in inches
    let backsplashLinearInches: Float

    /// Backsplash height in inches (default 18")
    let backsplashHeightInches: Float

    // MARK: - Edge Treatment

    /// Total exposed edge length in inches
    let exposedEdgeTotalInches: Float

    // MARK: - Cutouts

    /// Total number of cutouts
    let cutoutCount: Int

    /// All cutout details
    let allCutouts: [AICountertopCutout]

    // MARK: - Computed Properties

    /// Total gross countertop area in square inches (wall + island + peninsula)
    var totalGrossAreaSquareInches: Float {
        wallGrossAreaSquareInches + islandTotalSquareInches + peninsulaTotalSquareInches
    }

    /// Total net countertop area (after cutouts) in square inches
    var totalNetAreaSquareInches: Float {
        let cutoutArea = allCutouts.reduce(0) { $0 + $1.areaSquareInches }
        return totalGrossAreaSquareInches - cutoutArea
    }

    /// Total countertop in square feet (net)
    var totalSquareFeet: Float {
        totalNetAreaSquareInches / 144.0
    }

    /// Wall countertop linear feet
    var wallLinearFeet: Float {
        wallTotalLinearInches / 12.0
    }

    /// Backsplash linear feet
    var backsplashLinearFeet: Float {
        backsplashLinearInches / 12.0
    }

    /// Backsplash area in square inches
    var backsplashAreaSquareInches: Float {
        backsplashLinearInches * backsplashHeightInches
    }

    /// Backsplash area in square feet
    var backsplashAreaSquareFeet: Float {
        backsplashAreaSquareInches / 144.0
    }

    /// Exposed edge in linear feet
    var exposedEdgeLinearFeet: Float {
        exposedEdgeTotalInches / 12.0
    }

    /// Empty summary (no countertops)
    static let empty = AICountertopSummary(
        wallCountertops: [],
        islandCountertops: [],
        peninsulaCountertops: [],
        wallTotalLinearInches: 0,
        wallGrossAreaSquareInches: 0,
        wallNetAreaSquareInches: 0,
        islandTotalSquareInches: 0,
        peninsulaTotalSquareInches: 0,
        backsplashLinearInches: 0,
        backsplashHeightInches: 18,
        exposedEdgeTotalInches: 0,
        cutoutCount: 0,
        allCutouts: []
    )
}

// MARK: - Backsplash Summary

/// Backsplash calculation details.
struct AIBacksplashSummary: Equatable, Codable {
    /// Total linear inches of backsplash
    let linearInches: Float

    /// Height of backsplash in inches
    let heightInches: Float

    /// Area in square inches
    var areaSquareInches: Float {
        linearInches * heightInches
    }

    /// Linear feet
    var linearFeet: Float {
        linearInches / 12.0
    }

    /// Area in square feet
    var areaSquareFeet: Float {
        areaSquareInches / 144.0
    }

    /// Sections that were excluded (windows, etc.)
    let excludedSections: [BacksplashExclusion]

    /// Empty summary
    static let empty = AIBacksplashSummary(
        linearInches: 0,
        heightInches: 18,
        excludedSections: []
    )
}

/// A section excluded from backsplash (window, etc.)
struct BacksplashExclusion: Equatable, Codable {
    /// Reason for exclusion
    let reason: String

    /// Length excluded in inches
    let lengthInches: Float
}

// MARK: - Edge Treatment Summary

/// Edge treatment calculation details.
struct AIEdgeTreatmentSummary: Equatable, Codable {
    /// Wall countertop front edges (only exposed edge) in inches
    let wallFrontEdgeInches: Float

    /// Island perimeter (all 4 sides exposed) in inches
    let islandPerimeterInches: Float

    /// Peninsula exposed edges (3 sides) in inches
    let peninsulaExposedEdgeInches: Float

    /// Total exposed edge in inches
    var totalExposedEdgeInches: Float {
        wallFrontEdgeInches + islandPerimeterInches + peninsulaExposedEdgeInches
    }

    /// Total in linear feet
    var totalLinearFeet: Float {
        totalExposedEdgeInches / 12.0
    }

    /// Empty summary
    static let empty = AIEdgeTreatmentSummary(
        wallFrontEdgeInches: 0,
        islandPerimeterInches: 0,
        peninsulaExposedEdgeInches: 0
    )
}

// MARK: - Standard Countertop Sizes

/// Standard US countertop dimensions for snapping and validation.
///
/// Per Architecture 7.4, standard sizes are used for:
/// 1. Depth validation (25.5" is standard)
/// 2. Height validation (36" is standard counter height)
/// 3. Backsplash heights (4" standard, 18" full height)
enum StandardCountertopSizes {
    // MARK: - Depths

    /// Standard countertop depth in inches (1.5" overhang over 24" base cabinet)
    static let standardDepth: Float = 25.5

    /// Peninsula/island depth (same as base cabinet)
    static let peninsulaDepth: Float = 24.0

    /// Depth tolerance for standard classification in inches
    static let depthTolerance: Float = 2.0

    /// Minimum valid countertop depth
    static let minDepth: Float = 20.0

    /// Maximum valid countertop depth
    static let maxDepth: Float = 36.0

    // MARK: - Heights

    /// Standard countertop height from floor in inches
    static let standardHeight: Float = 36.0

    /// Counter height detection range
    static let heightRange: ClosedRange<Float> = 34...38

    /// Height tolerance for detection
    static let heightTolerance: Float = 2.0

    // MARK: - Backsplash

    /// Standard backsplash height (small)
    static let backsplashStandard: Float = 4.0

    /// Full-height backsplash (countertop to upper cabinets)
    static let backsplashFullHeight: Float = 18.0

    /// Default backsplash height for calculations
    static let backsplashDefault: Float = 18.0

    // MARK: - Detection Thresholds

    /// Maximum distance from wall to be considered wall countertop
    static let maxWallDistance: Float = 6.0

    /// Minimum countertop length to detect
    static let minLength: Float = 12.0

    /// Snapping tolerance for standard depth
    static let snapTolerance: Float = 1.5

    /// Minimum number of points required for reliable depth measurement
    static let minPointsForDepthMeasurement: Int = 20

    /// Maximum gap between cabinets to be considered contiguous (for countertop runs)
    static let maxCabinetGap: Float = 6.0

    // MARK: - Standard Cutout Sizes

    /// Standard sink cutout dimensions
    static let sinkCutoutWidth: Float = 33.0
    static let sinkCutoutDepth: Float = 22.0

    /// Standard cooktop cutout dimensions
    static let cooktopCutoutWidth: Float = 30.0
    static let cooktopCutoutDepth: Float = 21.0

    // MARK: - Helper Methods

    /// Checks if depth is within standard range.
    ///
    /// - Parameter depth: Measured depth in inches
    /// - Returns: True if within standard depth ±tolerance
    static func isStandardDepth(_ depth: Float) -> Bool {
        abs(depth - standardDepth) <= depthTolerance
    }

    /// Checks if height is within counter height range.
    ///
    /// - Parameter height: Measured height in inches
    /// - Returns: True if within counter height range
    static func isCounterHeight(_ height: Float) -> Bool {
        heightRange.contains(height)
    }

    /// Snaps depth to standard if within tolerance.
    ///
    /// - Parameter rawDepth: Raw measured depth
    /// - Returns: Snapped depth (standard if close, raw otherwise)
    static func snapDepth(_ rawDepth: Float) -> Float {
        if abs(rawDepth - standardDepth) <= snapTolerance {
            return standardDepth
        }
        return rawDepth
    }
}

// MARK: - Countertop Detector

/// Detects wall countertops and calculates countertop totals for quotes.
///
/// **Algorithm Pipeline (per ADR-1 - Cabinet-Inferred Detection):**
/// 1. For each wall with base cabinets, infer countertop exists above
/// 2. Measure depth from point cloud (expected 25.5" ±2")
/// 3. Segment at discontinuities (corners, windows, depth changes)
/// 4. Detect cutouts from appliance positions (sink, cooktop)
/// 5. Calculate backsplash linear feet
/// 6. Calculate edge treatment linear feet
/// 7. Aggregate with island/peninsula countertops for summary
///
/// **Performance Budget:** <200ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = CountertopDetector()
/// let result = try await detector.detect(
///     roomStructure: room,
///     pointCloud: cloud,
///     cabinets: cabinetResult,
///     appliances: applianceResult,
///     islandPeninsulaResult: islandResult
/// )
/// ```
@MainActor
final class CountertopDetector: ObservableObject, CountertopDetectorProtocol {

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: CountertopDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "CountertopDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("CountertopDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all countertops and builds summary for quotes.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and floor plane
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Cabinet detection result (base cabinets = countertop locations)
    ///   - appliances: Appliance detection result (for cutout detection)
    ///   - islandPeninsulaResult: Island/peninsula result (already has countertop areas)
    /// - Returns: Countertop detection result with all measurements
    /// - Throws: `CountertopDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        appliances: ApplianceDetectionResult,
        islandPeninsulaResult: IslandPeninsulaDetectionResult
    ) async throws -> CountertopDetectorResult {
        let startTime = Date()

        #if DEBUG
        logger.info("Starting countertop detection with \(pointCloud.count) points, \(cabinets.cabinets.count) cabinets")
        #endif

        guard !pointCloud.isEmpty else {
            throw CountertopDetectionError.noPointCloud
        }

        // Check if there are base cabinets (required for wall countertop inference)
        let baseCabinets = cabinets.cabinets.filter { $0.type == .base }

        isProcessing = true
        progress = 0.0
        var warnings: [String] = []

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Phase 1: Detect wall countertops (above base cabinets)
        currentPhase = .wallCountertopDetection
        progress = 0.1

        var wallCountertops: [AIWallCountertop] = []

        if baseCabinets.isEmpty {
            warnings.append("No base cabinets detected - wall countertops not inferred")
        } else {
            wallCountertops = detectWallCountertops(
                pointCloud: pointCloud,
                roomStructure: roomStructure,
                baseCabinets: baseCabinets
            )

            #if DEBUG
            logger.info("Detected \(wallCountertops.count) wall countertops")
            #endif
        }

        progress = 0.3

        // Phase 2: Detect window sections for backsplash exclusion (AC6)
        currentPhase = .segmentation
        progress = 0.4

        // Detect window sections in each countertop for backsplash calculation
        wallCountertops = wallCountertops.map { countertop in
            detectWindowSectionsForCountertop(
                countertop: countertop,
                pointCloud: pointCloud,
                roomStructure: roomStructure
            )
        }

        progress = 0.5

        // Phase 3: Detect cutouts (sink, cooktop)
        currentPhase = .cutoutDetection
        progress = 0.55

        wallCountertops = wallCountertops.map { countertop in
            associateCutouts(with: countertop, appliances: appliances)
        }

        progress = 0.65

        // Phase 4: Calculate backsplash
        currentPhase = .backsplashCalculation
        progress = 0.7

        let backsplashSummary = calculateBacksplash(wallCountertops: wallCountertops)

        progress = 0.75

        // Phase 5: Calculate edge treatment
        currentPhase = .edgeTreatment
        progress = 0.8

        let edgeTreatmentSummary = calculateEdgeTreatment(
            wallCountertops: wallCountertops,
            islandResult: islandPeninsulaResult
        )

        progress = 0.85

        // Phase 6: Build countertop summary (ADR-2: CountertopDetector owns aggregation)
        currentPhase = .aggregation
        progress = 0.9

        let countertopSummary = buildCountertopSummary(
            wallCountertops: wallCountertops,
            islandResult: islandPeninsulaResult,
            backsplashSummary: backsplashSummary,
            edgeTreatmentSummary: edgeTreatmentSummary
        )

        // Phase 7: Calculate confidence
        currentPhase = .confidenceScoring
        progress = 0.95

        let overallConfidence = calculateOverallConfidence(
            wallCountertops: wallCountertops,
            islandResult: islandPeninsulaResult
        )

        // Add warning if confidence is low
        if overallConfidence == .low {
            warnings.append("Countertop measurements have low confidence - field verification strongly recommended")
        } else if overallConfidence == .medium {
            warnings.append("Some countertop measurements may need verification")
        }

        let processingTimeMs = Int((Date().timeIntervalSince(startTime) * 1000).rounded())

        #if DEBUG
        logger.info("Countertop detection complete in \(processingTimeMs)ms: \(wallCountertops.count) wall countertops, total \(String(format: "%.1f", countertopSummary.totalSquareFeet)) sq ft")
        #endif

        progress = 1.0
        currentPhase = .complete

        return CountertopDetectorResult(
            wallCountertops: wallCountertops,
            countertopSummary: countertopSummary,
            backsplashSummary: backsplashSummary,
            edgeTreatmentSummary: edgeTreatmentSummary,
            processingTimeMs: processingTimeMs,
            warnings: warnings,
            overallConfidence: overallConfidence
        )
    }

    // MARK: - Wall Countertop Detection (ADR-1: Cabinet-Inferred)

    /// Detects wall countertops by inferring from base cabinet positions.
    ///
    /// Per ADR-1, we assume countertop exists above every base cabinet.
    /// This is simpler and follows the pattern that wall countertops
    /// are ALWAYS above base cabinets by kitchen definition.
    ///
    /// - Parameters:
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - roomStructure: Room structure with walls
    ///   - baseCabinets: Base cabinets from cabinet detection
    /// - Returns: Array of detected wall countertops
    private func detectWallCountertops(
        pointCloud: AIPointCloud,
        roomStructure: AIRoomStructure,
        baseCabinets: [AIDetectedCabinet]
    ) -> [AIWallCountertop] {
        var countertops: [AIWallCountertop] = []

        // Group base cabinets by wall
        let cabinetsByWall = Dictionary(grouping: baseCabinets) { $0.wallId }

        for (wallId, wallCabinets) in cabinetsByWall {
            guard let wall = roomStructure.walls.first(where: { $0.id == wallId }) else {
                continue
            }

            // Sort cabinets by position on wall
            let sortedCabinets = wallCabinets.sorted { $0.positionOnWallInches < $1.positionOnWallInches }

            // Find contiguous cabinet runs
            let runs = findContiguousCabinetRuns(sortedCabinets)

            for run in runs {
                guard let firstCabinet = run.first,
                      let lastCabinet = run.last else {
                    continue
                }

                let startPosition = firstCabinet.positionOnWallInches
                let endPosition = lastCabinet.positionOnWallInches + lastCabinet.widthInches
                let length = endPosition - startPosition

                guard length >= StandardCountertopSizes.minLength else {
                    continue
                }

                // Measure depth from point cloud (or use standard if not measurable)
                let measuredDepth = measureCountertopDepth(
                    pointCloud: pointCloud,
                    wall: wall,
                    startPosition: startPosition,
                    endPosition: endPosition
                )

                let depth = measuredDepth ?? StandardCountertopSizes.standardDepth
                let isStandardDepth = StandardCountertopSizes.isStandardDepth(depth)

                // Segment countertop for depth variance and shape handling (AC3, AC7)
                let sections = segmentCountertop(
                    pointCloud: pointCloud,
                    wall: wall,
                    startPosition: startPosition,
                    endPosition: endPosition,
                    baseDepth: depth
                )

                // Calculate confidence based on segmentation
                var confidence: AIConfidenceLevel = isStandardDepth ? .high : .medium
                var notes: [String] = isStandardDepth ? [] : ["Non-standard depth: \(String(format: "%.1f", depth))\""]

                // Lower confidence if significant depth variance detected
                if sections.count > 1 {
                    let hasDepthChange = sections.contains { $0.segmentReason == .depthChange }
                    if hasDepthChange {
                        confidence = .medium
                        notes.append("Depth variance detected - \(sections.count) sections")
                    }
                }

                // Create countertop
                let countertop = AIWallCountertop(
                    wallId: wallId,
                    lengthInches: length,
                    depthInches: depth,
                    startPositionInches: startPosition,
                    endPositionInches: endPosition,
                    heightFromFloorInches: StandardCountertopSizes.standardHeight,
                    sections: sections,
                    cutouts: [],   // Cutouts added in associateCutouts
                    confidence: confidence,
                    rawDimensions: SIMD2(length, measuredDepth ?? depth),
                    isStandardDepth: isStandardDepth,
                    notes: notes
                )

                countertops.append(countertop)
            }
        }

        return countertops
    }

    /// Finds contiguous runs of cabinets along a wall.
    ///
    /// Cabinets are contiguous if gap between them is less than `maxCabinetGap`.
    private func findContiguousCabinetRuns(_ cabinets: [AIDetectedCabinet]) -> [[AIDetectedCabinet]] {
        guard !cabinets.isEmpty else { return [] }

        var runs: [[AIDetectedCabinet]] = []
        var currentRun: [AIDetectedCabinet] = [cabinets[0]]

        for i in 1..<cabinets.count {
            let prevCabinet = cabinets[i - 1]
            let currentCabinet = cabinets[i]

            let prevEnd = prevCabinet.positionOnWallInches + prevCabinet.widthInches
            let currentStart = currentCabinet.positionOnWallInches
            let gap = currentStart - prevEnd

            if gap <= StandardCountertopSizes.maxCabinetGap {
                // Contiguous - add to current run
                currentRun.append(currentCabinet)
            } else {
                // Gap found - start new run
                runs.append(currentRun)
                currentRun = [currentCabinet]
            }
        }

        // Don't forget last run
        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        return runs
    }

    /// Measures countertop depth from point cloud.
    ///
    /// - Parameters:
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - wall: Wall the countertop is against
    ///   - startPosition: Start position along wall
    ///   - endPosition: End position along wall
    /// - Returns: Measured depth in inches, or nil if not measurable
    private func measureCountertopDepth(
        pointCloud: AIPointCloud,
        wall: AIWall,
        startPosition: Float,
        endPosition: Float
    ) -> Float? {
        // Get points from point cloud
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()

        guard !points.isEmpty else { return nil }

        // Wall direction and normal
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

        // Find points at counter height, within the countertop region
        var depthValues: [Float] = []

        for point in points {
            // Check height (counter height range)
            guard StandardCountertopSizes.heightRange.contains(point.y) else { continue }

            // Project to wall coordinates
            let point2D = SIMD2<Float>(point.x, point.z)
            let toPoint = point2D - wall.startPoint

            let alongWall = simd_dot(toPoint, wallDir)
            let fromWall = simd_dot(toPoint, wallNormal)

            // Check if within countertop bounds
            guard alongWall >= startPosition && alongWall <= endPosition else { continue }
            guard fromWall >= 0 && fromWall <= StandardCountertopSizes.maxDepth else { continue }

            depthValues.append(fromWall)
        }

        // Need enough points for reliable measurement
        guard depthValues.count >= StandardCountertopSizes.minPointsForDepthMeasurement else { return nil }

        // Use 90th percentile as depth (accounts for noise/outliers)
        let sorted = depthValues.sorted()
        let percentile90Index = Int(Double(sorted.count) * 0.9)
        let measuredDepth = sorted[percentile90Index]

        // Snap to standard if close
        return StandardCountertopSizes.snapDepth(measuredDepth)
    }

    // MARK: - Countertop Segmentation (AC3, AC7)

    /// Segments countertop into sections based on depth variance and shape.
    ///
    /// Handles AC3 (Irregular Shape Handling) and AC7 (Depth Variance Handling):
    /// - Detects depth changes >2" along the countertop
    /// - Creates sections for L-shaped and U-shaped countertops
    /// - Returns single section if countertop is uniform
    ///
    /// - Parameters:
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - wall: Wall the countertop is against
    ///   - startPosition: Start position along wall
    ///   - endPosition: End position along wall
    ///   - baseDepth: Base depth for comparison
    /// - Returns: Array of countertop sections
    private func segmentCountertop(
        pointCloud: AIPointCloud,
        wall: AIWall,
        startPosition: Float,
        endPosition: Float,
        baseDepth: Float
    ) -> [AICountertopSection] {
        let length = endPosition - startPosition

        // For short countertops, don't segment
        guard length >= StandardCountertopSizes.minLength * 2 else {
            return [AICountertopSection(
                startPositionInches: startPosition,
                endPositionInches: endPosition,
                depthInches: baseDepth,
                segmentReason: .continuous
            )]
        }

        // Sample depth along the countertop at regular intervals
        let sampleInterval: Float = 12.0  // Sample every 12 inches
        let sampleCount = Int(length / sampleInterval)

        guard sampleCount >= 2 else {
            return [AICountertopSection(
                startPositionInches: startPosition,
                endPositionInches: endPosition,
                depthInches: baseDepth,
                segmentReason: .continuous
            )]
        }

        // Measure depth at each sample point
        var depthSamples: [(position: Float, depth: Float)] = []

        for i in 0..<sampleCount {
            let samplePosition = startPosition + Float(i) * sampleInterval + sampleInterval / 2
            let sampleEndPosition = min(samplePosition + sampleInterval, endPosition)

            if let depth = measureCountertopDepth(
                pointCloud: pointCloud,
                wall: wall,
                startPosition: samplePosition,
                endPosition: sampleEndPosition
            ) {
                depthSamples.append((samplePosition, depth))
            }
        }

        // If not enough samples, return single section
        guard depthSamples.count >= 2 else {
            return [AICountertopSection(
                startPositionInches: startPosition,
                endPositionInches: endPosition,
                depthInches: baseDepth,
                segmentReason: .continuous
            )]
        }

        // Find depth changes (>2" difference = significant variance per AC7)
        let depthChangeThreshold: Float = 2.0
        var sections: [AICountertopSection] = []
        var currentSectionStart = startPosition
        var currentDepth = depthSamples[0].depth

        for i in 1..<depthSamples.count {
            let sample = depthSamples[i]
            let depthDifference = abs(sample.depth - currentDepth)

            if depthDifference > depthChangeThreshold {
                // Close current section
                sections.append(AICountertopSection(
                    startPositionInches: currentSectionStart,
                    endPositionInches: sample.position,
                    depthInches: currentDepth,
                    segmentReason: sections.isEmpty ? .continuous : .depthChange
                ))

                // Start new section
                currentSectionStart = sample.position
                currentDepth = sample.depth
            }
        }

        // Add final section
        sections.append(AICountertopSection(
            startPositionInches: currentSectionStart,
            endPositionInches: endPosition,
            depthInches: currentDepth,
            segmentReason: sections.isEmpty ? .continuous : .depthChange
        ))

        // If only one section, mark as continuous
        if sections.count == 1 {
            return [AICountertopSection(
                startPositionInches: startPosition,
                endPositionInches: endPosition,
                depthInches: baseDepth,
                segmentReason: .continuous
            )]
        }

        return sections
    }

    // MARK: - Window Section Detection (AC6)

    /// Detects windows in the backsplash area and updates countertop sections.
    ///
    /// Per AC6, window areas should be excluded from backsplash linear feet.
    /// This method analyzes point cloud gaps at backsplash height to identify windows.
    ///
    /// - Parameters:
    ///   - countertop: The wall countertop to analyze
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - roomStructure: Room structure with walls
    /// - Returns: Updated countertop with window sections marked
    private func detectWindowSectionsForCountertop(
        countertop: AIWallCountertop,
        pointCloud: AIPointCloud,
        roomStructure: AIRoomStructure
    ) -> AIWallCountertop {
        // Find the wall for this countertop
        guard let wall = roomStructure.walls.first(where: { $0.id == countertop.wallId }) else {
            return countertop
        }

        // Detect window sections using point cloud analysis
        let windowSections = detectWindowSections(
            pointCloud: pointCloud,
            wall: wall,
            countertop: countertop
        )

        // If no windows detected, return original countertop
        let hasWindows = windowSections.contains { $0.segmentReason == .window }
        if !hasWindows {
            return countertop
        }

        // Update countertop with window sections
        var updatedNotes = countertop.notes
        let windowCount = windowSections.filter { $0.segmentReason == .window }.count
        updatedNotes.append("Detected \(windowCount) window section(s) in backsplash area")

        return AIWallCountertop(
            id: countertop.id,
            wallId: countertop.wallId,
            lengthInches: countertop.lengthInches,
            depthInches: countertop.depthInches,
            startPositionInches: countertop.startPositionInches,
            endPositionInches: countertop.endPositionInches,
            heightFromFloorInches: countertop.heightFromFloorInches,
            sections: windowSections,
            cutouts: countertop.cutouts,
            confidence: countertop.confidence,
            rawDimensions: countertop.rawDimensions,
            isStandardDepth: countertop.isStandardDepth,
            notes: updatedNotes
        )
    }

    // MARK: - Cutout Detection (ADR-3: Proximity + Type check)

    /// Associates appliance cutouts with a countertop.
    ///
    /// Per ADR-3, only sink and cooktop require cutouts.
    /// Uses proximity + type check following IslandPeninsulaDetector pattern.
    private func associateCutouts(
        with countertop: AIWallCountertop,
        appliances: ApplianceDetectionResult
    ) -> AIWallCountertop {
        var cutouts: [AICountertopCutout] = []

        for appliance in appliances.appliances {
            // Only sink and cooktop require cutouts
            guard appliance.type == .sink || appliance.type == .cooktop else { continue }

            // Check if appliance is on this countertop
            // Use wall-relative coordinates
            guard let wallInfo = findApplianceWallPosition(appliance: appliance, countertop: countertop) else {
                continue
            }

            // Check if within countertop bounds
            guard countertop.contains(
                positionAlongWall: wallInfo.alongWall,
                positionFromWall: wallInfo.fromWall
            ) else {
                continue
            }

            // Create cutout
            // Use snapped dimensions for consistency with island/peninsula cutout handling
            let cutoutType: AICutoutType = appliance.type == .sink ? .sink : .cooktop
            let width = appliance.widthInches
            let depth = appliance.depthInches

            let cutout = AICountertopCutout(
                type: cutoutType,
                positionFromStartInches: wallInfo.alongWall - countertop.startPositionInches,
                positionFromFrontInches: wallInfo.fromWall,
                widthInches: width,
                depthInches: depth
            )

            cutouts.append(cutout)
        }

        // Return updated countertop with cutouts
        return AIWallCountertop(
            id: countertop.id,
            wallId: countertop.wallId,
            lengthInches: countertop.lengthInches,
            depthInches: countertop.depthInches,
            startPositionInches: countertop.startPositionInches,
            endPositionInches: countertop.endPositionInches,
            heightFromFloorInches: countertop.heightFromFloorInches,
            sections: countertop.sections,
            cutouts: cutouts,
            confidence: countertop.confidence,
            rawDimensions: countertop.rawDimensions,
            isStandardDepth: countertop.isStandardDepth,
            notes: countertop.notes
        )
    }

    /// Finds appliance position relative to countertop's wall.
    ///
    /// - Note: Returns approximate values when exact wall projection is not available.
    ///   `alongWall` uses the appliance's `positionOnWallInches` if set, otherwise 0.
    ///   `fromWall` is approximated as half the appliance depth (center-to-edge estimate).
    ///   These approximations are sufficient for cutout association within typical tolerances.
    ///
    /// - Parameters:
    ///   - appliance: The appliance to locate
    ///   - countertop: The countertop to check against
    /// - Returns: Position tuple (alongWall, fromWall) in inches, or nil if not on same wall
    private func findApplianceWallPosition(
        appliance: AIDetectedAppliance,
        countertop: AIWallCountertop
    ) -> (alongWall: Float, fromWall: Float)? {
        // Simplified: Use appliance's wallId if available
        guard appliance.wallId == countertop.wallId else { return nil }

        // Approximate position along wall from appliance positionOnWall
        // Note: These are approximate values - see method documentation
        let alongWall = appliance.positionOnWallInches ?? 0
        let fromWall = appliance.boundingBox.size.z / 2  // Approximate center-to-edge

        return (alongWall, fromWall)
    }

    // MARK: - Backsplash Calculation

    /// Calculates backsplash linear feet from wall countertops.
    ///
    /// Backsplash = sum of all wall countertop lengths, excluding window sections.
    /// Windows are detected via countertop sections with `.window` segment reason.
    ///
    /// - Parameter wallCountertops: Wall countertops to calculate backsplash for
    /// - Returns: Backsplash summary with exclusions
    private func calculateBacksplash(wallCountertops: [AIWallCountertop]) -> AIBacksplashSummary {
        var totalLinearInches: Float = 0
        var exclusions: [BacksplashExclusion] = []

        for countertop in wallCountertops {
            if countertop.sections.isEmpty {
                // No sections - use full countertop length
                totalLinearInches += countertop.lengthInches
            } else {
                // Process sections, excluding windows
                for section in countertop.sections {
                    if section.segmentReason == .window {
                        // Exclude window areas from backsplash
                        exclusions.append(BacksplashExclusion(
                            reason: "Window",
                            lengthInches: section.lengthInches
                        ))
                    } else {
                        // Include non-window sections
                        totalLinearInches += section.lengthInches
                    }
                }
            }
        }

        return AIBacksplashSummary(
            linearInches: totalLinearInches,
            heightInches: StandardCountertopSizes.backsplashDefault,
            excludedSections: exclusions
        )
    }

    /// Detects window sections in a countertop run by analyzing point cloud gaps.
    ///
    /// Windows above countertops create gaps in the point cloud at backsplash height.
    /// This method identifies such gaps and marks them as window sections.
    ///
    /// - Parameters:
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - wall: Wall the countertop is against
    ///   - countertop: The countertop to check for windows
    /// - Returns: Array of sections with windows marked
    private func detectWindowSections(
        pointCloud: AIPointCloud,
        wall: AIWall,
        countertop: AIWallCountertop
    ) -> [AICountertopSection] {
        // Backsplash height range (from countertop to upper cabinets)
        let backsplashBottomHeight = countertop.heightFromFloorInches
        let backsplashTopHeight = backsplashBottomHeight + StandardCountertopSizes.backsplashDefault

        // Wall direction
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

        // Get points from point cloud
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()

        // Sample positions along the countertop
        let sampleInterval: Float = 6.0  // Sample every 6 inches for window detection
        let sampleCount = Int(countertop.lengthInches / sampleInterval)

        guard sampleCount >= 2 else {
            return countertop.sections
        }

        // Track point density at backsplash height for each sample
        var hasPointsAtBacksplash: [Bool] = []

        for i in 0..<sampleCount {
            let samplePosition = countertop.startPositionInches + Float(i) * sampleInterval

            // Count points at this position at backsplash height
            var pointCount = 0
            let positionTolerance: Float = sampleInterval / 2

            for point in points {
                // Check height is in backsplash range
                guard point.y >= backsplashBottomHeight && point.y <= backsplashTopHeight else { continue }

                // Project to wall coordinates
                let point2D = SIMD2<Float>(point.x, point.z)
                let toPoint = point2D - wall.startPoint

                let alongWall = simd_dot(toPoint, wallDir)
                let fromWall = simd_dot(toPoint, wallNormal)

                // Check if within sample region and close to wall
                guard alongWall >= samplePosition - positionTolerance &&
                      alongWall <= samplePosition + positionTolerance else { continue }
                guard fromWall >= 0 && fromWall <= 6.0 else { continue }  // Close to wall

                pointCount += 1
            }

            // Threshold for "has points" (at least 3 points)
            hasPointsAtBacksplash.append(pointCount >= 3)
        }

        // Find gaps (potential windows) - consecutive false values
        var sections: [AICountertopSection] = []
        var currentSectionStart = countertop.startPositionInches
        var inGap = !hasPointsAtBacksplash[0]

        for i in 1..<hasPointsAtBacksplash.count {
            let hasPoints = hasPointsAtBacksplash[i]
            let position = countertop.startPositionInches + Float(i) * sampleInterval

            if inGap && hasPoints {
                // End of gap (window)
                sections.append(AICountertopSection(
                    startPositionInches: currentSectionStart,
                    endPositionInches: position,
                    depthInches: countertop.depthInches,
                    segmentReason: .window
                ))
                currentSectionStart = position
                inGap = false
            } else if !inGap && !hasPoints {
                // Start of gap (window)
                if position > currentSectionStart {
                    sections.append(AICountertopSection(
                        startPositionInches: currentSectionStart,
                        endPositionInches: position,
                        depthInches: countertop.depthInches,
                        segmentReason: .continuous
                    ))
                }
                currentSectionStart = position
                inGap = true
            }
        }

        // Add final section
        let finalReason: CountertopSegmentReason = inGap ? .window : .continuous
        sections.append(AICountertopSection(
            startPositionInches: currentSectionStart,
            endPositionInches: countertop.endPositionInches,
            depthInches: countertop.depthInches,
            segmentReason: finalReason
        ))

        // If no windows detected, return original sections or single continuous section
        let hasWindows = sections.contains { $0.segmentReason == .window }
        if !hasWindows {
            return countertop.sections.isEmpty ? [AICountertopSection(
                startPositionInches: countertop.startPositionInches,
                endPositionInches: countertop.endPositionInches,
                depthInches: countertop.depthInches,
                segmentReason: .continuous
            )] : countertop.sections
        }

        return sections
    }

    // MARK: - Edge Treatment Calculation

    /// Calculates edge treatment linear feet.
    ///
    /// - Wall countertops: front edge only (wall side not exposed)
    /// - Islands: full perimeter (all 4 sides)
    /// - Peninsulas: 3 sides (2 lengths + 1 width, not attached side)
    private func calculateEdgeTreatment(
        wallCountertops: [AIWallCountertop],
        islandResult: IslandPeninsulaDetectionResult
    ) -> AIEdgeTreatmentSummary {
        // Wall countertops: only front edge
        let wallFrontEdge = wallCountertops.reduce(0) { $0 + $1.frontEdgeInches }

        // Islands: full perimeter
        let islandPerimeter = islandResult.islands.reduce(0) { $0 + $1.perimeterInches }

        // Peninsulas: 3 exposed sides (2 lengths + 1 width)
        let peninsulaExposed = islandResult.peninsulas.reduce(0) { $0 + $1.exposedEdgeInches }

        return AIEdgeTreatmentSummary(
            wallFrontEdgeInches: wallFrontEdge,
            islandPerimeterInches: islandPerimeter,
            peninsulaExposedEdgeInches: peninsulaExposed
        )
    }

    // MARK: - Summary Builder (ADR-2: CountertopDetector owns aggregation)

    /// Builds the complete countertop summary for quotes.
    ///
    /// Per ADR-2, CountertopDetector owns aggregation of all countertop
    /// data (wall + island + peninsula) into AICountertopSummary.
    private func buildCountertopSummary(
        wallCountertops: [AIWallCountertop],
        islandResult: IslandPeninsulaDetectionResult,
        backsplashSummary: AIBacksplashSummary,
        edgeTreatmentSummary: AIEdgeTreatmentSummary
    ) -> AICountertopSummary {
        // Wall countertop totals
        let wallLinear = wallCountertops.reduce(0) { $0 + $1.lengthInches }
        let wallGross = wallCountertops.reduce(0) { $0 + $1.grossAreaSquareInches }
        let wallNet = wallCountertops.reduce(0) { $0 + $1.netAreaSquareInches }

        // Island countertops (from Story 4.5)
        let islandCountertops = islandResult.islands.map { island -> AIIslandCountertop in
            // Collect cutouts from appliances on island
            let cutouts = island.appliancesOnIsland.compactMap { appliance -> AICountertopCutout? in
                guard appliance.type.requiresCutout else { return nil }
                return AICountertopCutout(
                    type: appliance.type == .sink ? .sink : .cooktop,
                    positionFromStartInches: appliance.positionOnSurface.x + island.lengthInches / 2,
                    positionFromFrontInches: appliance.positionOnSurface.y + island.widthInches / 2,
                    widthInches: appliance.widthInches,
                    depthInches: appliance.depthInches
                )
            }

            return AIIslandCountertop(
                islandId: island.id,
                lengthInches: island.lengthInches,
                widthInches: island.widthInches,
                heightFromFloorInches: island.heightInches,
                overhangInches: island.seatingOverhangInches,
                cutouts: cutouts,
                confidence: island.confidence
            )
        }
        let islandTotal = islandResult.islandTotalAreaSquareInches

        // Peninsula countertops (from Story 4.5)
        let peninsulaCountertops = islandResult.peninsulas.map { peninsula -> AIPeninsulaCountertop in
            // Collect cutouts from appliances on peninsula
            let cutouts = peninsula.appliancesOnPeninsula.compactMap { appliance -> AICountertopCutout? in
                guard appliance.type.requiresCutout else { return nil }
                return AICountertopCutout(
                    type: appliance.type == .sink ? .sink : .cooktop,
                    positionFromStartInches: appliance.positionOnSurface.x + peninsula.lengthInches / 2,
                    positionFromFrontInches: appliance.positionOnSurface.y + peninsula.widthInches / 2,
                    widthInches: appliance.widthInches,
                    depthInches: appliance.depthInches
                )
            }

            return AIPeninsulaCountertop(
                peninsulaId: peninsula.id,
                lengthInches: peninsula.lengthInches,
                widthInches: peninsula.widthInches,
                heightFromFloorInches: peninsula.heightInches,
                overhangInches: peninsula.seatingOverhangInches,
                cutouts: cutouts,
                confidence: peninsula.confidence
            )
        }
        let peninsulaTotal = islandResult.peninsulaTotalAreaSquareInches

        // Collect all cutouts
        var allCutouts: [AICountertopCutout] = []
        allCutouts.append(contentsOf: wallCountertops.flatMap { $0.cutouts })
        allCutouts.append(contentsOf: islandCountertops.flatMap { $0.cutouts })
        allCutouts.append(contentsOf: peninsulaCountertops.flatMap { $0.cutouts })

        return AICountertopSummary(
            wallCountertops: wallCountertops,
            islandCountertops: islandCountertops,
            peninsulaCountertops: peninsulaCountertops,
            wallTotalLinearInches: wallLinear,
            wallGrossAreaSquareInches: wallGross,
            wallNetAreaSquareInches: wallNet,
            islandTotalSquareInches: islandTotal,
            peninsulaTotalSquareInches: peninsulaTotal,
            backsplashLinearInches: backsplashSummary.linearInches,
            backsplashHeightInches: backsplashSummary.heightInches,
            exposedEdgeTotalInches: edgeTreatmentSummary.totalExposedEdgeInches,
            cutoutCount: allCutouts.count,
            allCutouts: allCutouts
        )
    }

    // MARK: - Confidence Scoring

    /// Calculates overall confidence for countertop detection.
    ///
    /// Per AC9:
    /// - HIGH (≥85%): Standard depths + continuous surfaces + clear boundaries
    /// - MEDIUM (60-85%): Non-standard depth OR segmented OR boundary uncertain
    /// - LOW (<60%): Irregular shape OR significant gaps OR unclear surface
    private func calculateOverallConfidence(
        wallCountertops: [AIWallCountertop],
        islandResult: IslandPeninsulaDetectionResult
    ) -> AIConfidenceLevel {
        // Collect all confidence levels
        var confidences: [AIConfidenceLevel] = []

        for countertop in wallCountertops {
            confidences.append(countertop.confidence)
        }

        for island in islandResult.islands {
            confidences.append(island.confidence)
        }

        for peninsula in islandResult.peninsulas {
            confidences.append(peninsula.confidence)
        }

        guard !confidences.isEmpty else {
            return .low
        }

        // Calculate based on distribution
        let highCount = confidences.filter { $0 == .high }.count
        let mediumCount = confidences.filter { $0 == .medium }.count
        let total = confidences.count

        let highRatio = Float(highCount) / Float(total)
        let mediumRatio = Float(mediumCount) / Float(total)

        if highRatio >= 0.7 {
            return .high
        } else if highRatio + mediumRatio >= 0.7 {
            return .medium
        } else {
            return .low
        }
    }
}
