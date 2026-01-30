//
//  IslandPeninsulaDetector.swift
//  cabinetscan
//
//  Created for Story 4.5: Island and Peninsula Detection
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Island Peninsula Detector Protocol

/// Protocol for island and peninsula detection implementations.
/// Enables testing with mock detectors.
protocol IslandPeninsulaDetectorProtocol {
    /// Detects islands and peninsulas from room structure, point cloud, and prior detection results.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure from RoomDetector (walls, floor plane)
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Cabinet detection result (for exclusion and context)
    ///   - appliances: Appliance detection result (for association)
    /// - Returns: Island and peninsula detection result
    /// - Throws: `IslandPeninsulaDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        appliances: ApplianceDetectionResult
    ) async throws -> IslandPeninsulaDetectionResult
}

// MARK: - Detection Phase

/// Phases of island and peninsula detection for progress tracking.
enum IslandPeninsulaDetectionPhase: String {
    case idle = "Idle"
    case surfaceDetection = "Finding Horizontal Surfaces"
    case islandClassification = "Classifying Islands"
    case peninsulaClassification = "Classifying Peninsulas"
    case dimensionExtraction = "Measuring Dimensions"
    case overhangDetection = "Detecting Seating Areas"
    case applianceAssociation = "Associating Appliances"
    case confidenceScoring = "Calculating Confidence"
    case validation = "Validating Results"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Detection Result

/// Result of island and peninsula detection.
struct IslandPeninsulaDetectionResult: Equatable {
    /// All detected islands
    let islands: [AIDetectedIsland]

    /// All detected peninsulas
    let peninsulas: [AIDetectedPeninsula]

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection
    let warnings: [String]

    // MARK: - Computed Properties

    /// Total count of islands and peninsulas
    var totalCount: Int {
        islands.count + peninsulas.count
    }

    /// Whether any islands or peninsulas were detected
    var hasDetections: Bool {
        !islands.isEmpty || !peninsulas.isEmpty
    }

    /// Total island countertop area in square inches
    var islandTotalAreaSquareInches: Float {
        islands.reduce(0) { $0 + $1.countertopAreaSquareInches }
    }

    /// Total peninsula countertop area in square inches
    var peninsulaTotalAreaSquareInches: Float {
        peninsulas.reduce(0) { $0 + $1.countertopAreaSquareInches }
    }

    /// Combined countertop area (islands + peninsulas) in square feet
    var totalCountertopAreaSquareFeet: Float {
        (islandTotalAreaSquareInches + peninsulaTotalAreaSquareInches) / 144.0
    }

    /// Total island perimeter for edge treatment in linear feet
    var islandTotalPerimeterLinearFeet: Float {
        islands.reduce(0) { $0 + $1.perimeterLinearFeet }
    }

    /// Total peninsula exposed edge for edge treatment in linear feet
    var peninsulaTotalExposedEdgeLinearFeet: Float {
        peninsulas.reduce(0) { $0 + $1.exposedEdgeLinearFeet }
    }

    /// Overall detection confidence
    var overallConfidence: AIConfidenceLevel {
        let allDetections: [AIConfidenceLevel] = islands.map { $0.confidence } + peninsulas.map { $0.confidence }
        guard !allDetections.isEmpty else { return .low }

        let highCount = allDetections.filter { $0 == .high }.count
        let mediumCount = allDetections.filter { $0 == .medium }.count

        let highRatio = Float(highCount) / Float(allDetections.count)
        let mediumRatio = Float(mediumCount) / Float(allDetections.count)

        if highRatio >= 0.7 {
            return .high
        } else if highRatio + mediumRatio >= 0.7 {
            return .medium
        } else {
            return .low
        }
    }

    /// Empty result (no detections)
    static let empty = IslandPeninsulaDetectionResult(
        islands: [],
        peninsulas: [],
        processingTimeMs: 0,
        warnings: []
    )
}

// MARK: - Detection Error

/// Errors that can occur during island and peninsula detection.
enum IslandPeninsulaDetectionError: LocalizedError, Equatable {
    case noRoomStructure
    case noPointCloud
    case noWallsDetected
    case detectionFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noRoomStructure:
            return "Room structure is required for island/peninsula detection"
        case .noPointCloud:
            return "Point cloud is empty - cannot detect islands/peninsulas"
        case .noWallsDetected:
            return "No walls detected - cannot classify islands vs peninsulas"
        case .detectionFailed(let reason):
            return "Island/peninsula detection failed: \(reason)"
        case .cancelled:
            return "Island/peninsula detection was cancelled"
        }
    }
}

// MARK: - Standard Island Sizes

/// Standard US island sizes for snapping and validation.
///
/// Per Architecture 7.4, standard sizes are used for:
/// 1. High-confidence snapping when raw dimension is within ±1.5" of standard
/// 2. Quote accuracy - standard sizes have predictable material requirements
enum StandardIslandSizes {
    // MARK: - Island Sizes

    /// Standard island lengths in inches
    static let lengths: [Float] = [48, 60, 72, 84, 96]

    /// Standard island widths in inches
    static let widths: [Float] = [24, 30, 36, 42]

    /// Small island dimensions (length, width)
    static let small: (length: Float, width: Float) = (48, 24)

    /// Medium island dimensions (length, width)
    static let medium: (length: Float, width: Float) = (60, 36)

    /// Large island dimensions (length, width)
    static let large: (length: Float, width: Float) = (84, 42)

    // MARK: - Peninsula Sizes

    /// Standard peninsula lengths (from wall) in inches
    static let peninsulaLengths: [Float] = [36, 42, 48, 60]

    /// Standard peninsula widths in inches
    static let peninsulaWidths: [Float] = [24, 30, 36]

    /// Small peninsula dimensions (length, width)
    static let peninsulaSmall: (length: Float, width: Float) = (36, 24)

    /// Medium peninsula dimensions (length, width)
    static let peninsulaMedium: (length: Float, width: Float) = (48, 24)

    /// Large peninsula dimensions (length, width)
    static let peninsulaLarge: (length: Float, width: Float) = (60, 36)

    // MARK: - Heights

    /// Standard countertop height in inches
    static let standardHeight: Float = 36.0

    /// Bar height (for seating) in inches
    static let barHeight: Float = 42.0

    /// Height tolerance for classification in inches
    static let heightTolerance: Float = 2.0

    // MARK: - Seating Overhangs

    /// Common seating overhang depths in inches
    static let seatingOverhangs: [Float] = [12, 15, 18]

    /// Minimum overhang for seating in inches
    static let minSeatingOverhang: Float = 10.0

    /// Minimal overhang
    static let overhangMinimal: Float = 12.0

    /// Standard overhang
    static let overhangStandard: Float = 15.0

    /// Generous overhang
    static let overhangGenerous: Float = 18.0

    // MARK: - Detection Thresholds

    /// Minimum distance from ALL walls to classify as island (inches)
    /// Must be walkable on all 4 sides
    static let minIslandWallDistance: Float = 18.0

    /// Preferred clearance for island (inches)
    static let preferredIslandClearance: Float = 42.0

    /// Maximum distance to wall to classify as "attached" for peninsula (inches)
    static let maxPeninsulaAttachDistance: Float = 6.0

    /// Minimum distance from free end to walls for peninsula (inches)
    static let minPeninsulaFreeEndDistance: Float = 18.0

    /// Maximum distance to wall for "wall countertop" classification (inches)
    static let wallCountertopDistance: Float = 6.0

    /// Counter height range (inches) for surface detection
    static let counterHeightRange: ClosedRange<Float> = 34...38

    // MARK: - Snapping

    /// Snapping tolerance for high confidence (inches)
    static let snapHighTolerance: Float = 1.5

    /// Snapping tolerance for medium confidence (inches)
    static let snapMediumTolerance: Float = 3.0

    // MARK: - Minimum Sizes

    /// Minimum island length to be considered valid (inches)
    static let minIslandLength: Float = 36.0

    /// Minimum island width to be considered valid (inches)
    static let minIslandWidth: Float = 24.0

    /// Minimum peninsula length to be considered valid (inches)
    static let minPeninsulaLength: Float = 24.0

    /// Minimum peninsula width to be considered valid (inches)
    static let minPeninsulaWidth: Float = 18.0

    // MARK: - Helper Methods

    /// Finds the nearest standard length for an island.
    ///
    /// - Parameter rawLength: The raw measured length in inches
    /// - Returns: Tuple of (nearest standard length, difference)
    static func nearestIslandLength(to rawLength: Float) -> (standard: Float, difference: Float) {
        let nearest = lengths.min(by: { abs($0 - rawLength) < abs($1 - rawLength) }) ?? rawLength
        return (nearest, abs(nearest - rawLength))
    }

    /// Finds the nearest standard width for an island.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestIslandWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = widths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard length for a peninsula.
    ///
    /// - Parameter rawLength: The raw measured length in inches
    /// - Returns: Tuple of (nearest standard length, difference)
    static func nearestPeninsulaLength(to rawLength: Float) -> (standard: Float, difference: Float) {
        let nearest = peninsulaLengths.min(by: { abs($0 - rawLength) < abs($1 - rawLength) }) ?? rawLength
        return (nearest, abs(nearest - rawLength))
    }

    /// Finds the nearest standard width for a peninsula.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestPeninsulaWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = peninsulaWidths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard seating overhang.
    ///
    /// - Parameter rawOverhang: The raw measured overhang in inches
    /// - Returns: Tuple of (nearest standard overhang, difference)
    static func nearestSeatingOverhang(to rawOverhang: Float) -> (standard: Float, difference: Float) {
        let nearest = seatingOverhangs.min(by: { abs($0 - rawOverhang) < abs($1 - rawOverhang) }) ?? rawOverhang
        return (nearest, abs(nearest - rawOverhang))
    }

    /// Determines if a height indicates bar-height counter.
    ///
    /// - Parameter height: Measured height in inches
    /// - Returns: True if within bar height range (40-44")
    static func isBarHeight(_ height: Float) -> Bool {
        abs(height - barHeight) <= heightTolerance
    }

    /// Determines if a height indicates standard counter height.
    ///
    /// - Parameter height: Measured height in inches
    /// - Returns: True if within standard height range (34-38")
    static func isStandardHeight(_ height: Float) -> Bool {
        abs(height - standardHeight) <= heightTolerance
    }
}

// MARK: - Island Peninsula Detector

/// Detects kitchen islands and peninsulas from calibrated 3D point cloud.
///
/// **Algorithm Pipeline (per ADR-1 - Single Surface Pass):**
/// 1. Find ALL horizontal surfaces at counter height (34"-38") in one pass
/// 2. Classify each surface: ISLAND (>18" from all walls), PENINSULA (one end attached), or WALL_COUNTERTOP (skip)
/// 3. Measure dimensions for each detected island/peninsula
/// 4. Detect seating overhang for each
/// 5. Associate appliances (bounds-check against ApplianceDetectionResult per ADR-3)
/// 6. Calculate confidence for each
/// 7. Validate results (no overlap between islands and peninsulas)
///
/// **Performance Budget:** <200ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = IslandPeninsulaDetector()
/// let result = try await detector.detect(
///     roomStructure: room,
///     pointCloud: cloud,
///     cabinets: cabinetResult,
///     appliances: applianceResult
/// )
/// ```
@MainActor
final class IslandPeninsulaDetector: ObservableObject, IslandPeninsulaDetectorProtocol {

    // MARK: - Constants

    /// Counter height range for surface detection (inches)
    private static let counterHeightMin: Float = 34.0
    private static let counterHeightMax: Float = 38.0

    /// Minimum distance to ALL walls to classify as island (inches)
    private static let islandMinWallDistance: Float = 18.0

    /// Maximum distance to wall to classify as "attached" (inches)
    private static let attachedMaxDistance: Float = 6.0

    /// Minimum free end distance for peninsula (inches)
    private static let peninsulaMinFreeDistance: Float = 18.0

    /// Minimum points required for valid surface detection
    private static let minPointsForSurface: Int = 100

    /// Vertical slice thickness for surface detection (inches)
    private static let sliceThickness: Float = 4.0

    /// Clustering distance threshold for surface grouping (inches)
    private static let clusteringThreshold: Float = 6.0

    /// Minimum surface area to be considered valid (square inches)
    private static let minSurfaceArea: Float = 576.0  // 24" x 24"

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: IslandPeninsulaDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "IslandPeninsulaDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("IslandPeninsulaDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all islands and peninsulas from room structure and point cloud.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and floor plane
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Cabinet detection result (for context and exclusion)
    ///   - appliances: Appliance detection result (for association)
    /// - Returns: Island and peninsula detection result
    /// - Throws: `IslandPeninsulaDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: CabinetDetectionResult,
        appliances: ApplianceDetectionResult
    ) async throws -> IslandPeninsulaDetectionResult {
        let startTime = Date()

        #if DEBUG
        logger.info("Starting island/peninsula detection with \(pointCloud.count) points, \(roomStructure.walls.count) walls")
        #endif

        guard !pointCloud.isEmpty else {
            throw IslandPeninsulaDetectionError.noPointCloud
        }

        guard !roomStructure.walls.isEmpty else {
            throw IslandPeninsulaDetectionError.noWallsDetected
        }

        isProcessing = true
        progress = 0.0
        var warnings: [String] = []

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Phase 1: Find horizontal surfaces at counter height
        currentPhase = .surfaceDetection
        progress = 0.1

        let surfaces = findCounterHeightSurfaces(pointCloud: pointCloud)

        #if DEBUG
        logger.info("Found \(surfaces.count) potential counter-height surfaces")
        #endif

        if surfaces.isEmpty {
            // No counter-height surfaces found - return empty (not an error)
            let processingTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            return IslandPeninsulaDetectionResult(
                islands: [],
                peninsulas: [],
                processingTimeMs: processingTimeMs,
                warnings: ["No counter-height surfaces detected away from walls"]
            )
        }

        progress = 0.2

        // Phase 2: Classify surfaces as island, peninsula, or wall countertop
        currentPhase = .islandClassification
        progress = 0.3

        var islands: [AIDetectedIsland] = []
        var peninsulas: [AIDetectedPeninsula] = []

        for surface in surfaces {
            let classification = classifySurface(surface: surface, walls: roomStructure.walls)

            switch classification {
            case .island:
                if let island = createIsland(from: surface, roomStructure: roomStructure) {
                    islands.append(island)
                }
            case .peninsula(let attachedWallId, let attachmentPoint):
                if let peninsula = createPeninsula(
                    from: surface,
                    attachedWallId: attachedWallId,
                    attachmentPoint: attachmentPoint,
                    roomStructure: roomStructure
                ) {
                    peninsulas.append(peninsula)
                }
            case .wallCountertop:
                // Skip wall countertops - handled by countertop detection
                continue
            case .unknown:
                warnings.append("Could not classify surface at position \(surface.center)")
            }
        }

        progress = 0.5

        // Phase 3: Dimension extraction and snapping
        currentPhase = .dimensionExtraction
        progress = 0.6

        // Dimensions are extracted during island/peninsula creation above
        // Snap to standard sizes
        islands = islands.map { snapIslandToStandardSize($0) }
        peninsulas = peninsulas.map { snapPeninsulaToStandardSize($0) }

        progress = 0.7

        // Phase 4: Seating overhang detection (Task 7 - AC6)
        currentPhase = .overhangDetection
        progress = 0.75

        islands = islands.map { detectSeatingOverhang(for: $0, cabinets: cabinets) }
        peninsulas = peninsulas.map { detectSeatingOverhang(for: $0, cabinets: cabinets) }

        // Phase 5: Appliance association (per ADR-3)
        currentPhase = .applianceAssociation
        progress = 0.8

        islands = islands.map { associateAppliances(with: $0, appliances: appliances) }
        peninsulas = peninsulas.map { associateAppliances(with: $0, appliances: appliances) }

        // Phase 5.5: Cutout calculation (Task 9 - AC7, AC9)
        islands = islands.map { calculateCutoutsForIsland($0) }
        peninsulas = peninsulas.map { calculateCutoutsForPeninsula($0) }

        // Phase 6: Confidence scoring
        currentPhase = .confidenceScoring
        progress = 0.9

        islands = islands.map { calculateConfidence(for: $0, roomStructure: roomStructure) }
        peninsulas = peninsulas.map { calculateConfidence(for: $0, roomStructure: roomStructure) }

        // Phase 7: Validation
        currentPhase = .validation
        progress = 0.95

        // Ensure no overlap between islands and peninsulas
        let (validatedIslands, validatedPeninsulas, validationWarnings) = validateNoOverlap(
            islands: islands,
            peninsulas: peninsulas
        )
        warnings.append(contentsOf: validationWarnings)

        let processingTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

        #if DEBUG
        logger.info("Detection complete: \(validatedIslands.count) islands, \(validatedPeninsulas.count) peninsulas in \(processingTimeMs)ms")
        #endif

        progress = 1.0
        currentPhase = .complete

        return IslandPeninsulaDetectionResult(
            islands: validatedIslands,
            peninsulas: validatedPeninsulas,
            processingTimeMs: processingTimeMs,
            warnings: warnings
        )
    }

    // MARK: - Surface Detection

    /// Finds horizontal surfaces at counter height in the point cloud.
    /// Note: Floor is at Y=0 after geometric constraints (per AIRoomStructure)
    private func findCounterHeightSurfaces(
        pointCloud: AIPointCloud
    ) -> [DetectedSurface] {
        // Extract points within counter height range
        // Floor is at Y=0, so counter height is directly 34"-38"
        let minHeight = Self.counterHeightMin
        let maxHeight = Self.counterHeightMax

        var counterPoints: [SIMD3<Float>] = []

        // Get points from point cloud
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()

        for point in points {
            if point.y >= minHeight && point.y <= maxHeight {
                counterPoints.append(point)
            }
        }

        guard counterPoints.count >= Self.minPointsForSurface else {
            return []
        }

        // Cluster points into separate surfaces
        return clusterIntoSurfaces(points: counterPoints)
    }

    /// Clusters points into separate surfaces using spatial hash grid for O(n) performance.
    ///
    /// Uses a spatial grid with cell size equal to clustering threshold for efficient neighbor lookup.
    /// This reduces complexity from O(n²) to O(n × average_neighbors).
    private func clusterIntoSurfaces(points: [SIMD3<Float>]) -> [DetectedSurface] {
        guard !points.isEmpty else { return [] }

        // Build spatial hash grid for efficient neighbor lookup
        let cellSize = Self.clusteringThreshold
        var grid: [GridCell: [Int]] = [:]

        for (index, point) in points.enumerated() {
            let cell = GridCell(
                x: Int(floor(point.x / cellSize)),
                z: Int(floor(point.z / cellSize))
            )
            grid[cell, default: []].append(index)
        }

        var surfaces: [DetectedSurface] = []
        var used = Set<Int>()

        for i in 0..<points.count {
            if used.contains(i) { continue }

            var clusterIndices = [i]
            used.insert(i)

            // Find all points within clustering distance (BFS with spatial hash)
            var queue = [i]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                let currentPoint = points[current]
                let currentCell = GridCell(
                    x: Int(floor(currentPoint.x / cellSize)),
                    z: Int(floor(currentPoint.z / cellSize))
                )

                // Check current cell and 8 neighboring cells
                for dx in -1...1 {
                    for dz in -1...1 {
                        let neighborCell = GridCell(x: currentCell.x + dx, z: currentCell.z + dz)
                        guard let candidates = grid[neighborCell] else { continue }

                        for j in candidates {
                            if used.contains(j) { continue }

                            let candidate = points[j]
                            // Use 2D distance (x, z) for surface clustering
                            let dist = simd_distance(
                                SIMD2(currentPoint.x, currentPoint.z),
                                SIMD2(candidate.x, candidate.z)
                            )

                            if dist <= Self.clusteringThreshold {
                                clusterIndices.append(j)
                                used.insert(j)
                                queue.append(j)
                            }
                        }
                    }
                }
            }

            // Create surface from cluster if it has enough points
            if clusterIndices.count >= Self.minPointsForSurface {
                let clusterPoints = clusterIndices.map { points[$0] }
                if let surface = DetectedSurface(points: clusterPoints) {
                    if surface.area >= Self.minSurfaceArea {
                        surfaces.append(surface)
                    }
                }
            }
        }

        return surfaces
    }

    /// Grid cell for spatial hashing in clustering algorithm.
    private struct GridCell: Hashable {
        let x: Int
        let z: Int
    }

    // MARK: - Surface Classification

    /// Classification result for a detected surface.
    private enum SurfaceClassification {
        case island
        case peninsula(attachedWallId: UUID, attachmentPoint: Float)
        case wallCountertop
        case unknown
    }

    /// Classifies a surface as island, peninsula, or wall countertop.
    private func classifySurface(
        surface: DetectedSurface,
        walls: [AIWall]
    ) -> SurfaceClassification {
        // Check distance to each wall
        var minDistanceToAnyWall: Float = .infinity
        var closestWall: AIWall?
        var attachmentPoint: Float = 0

        for wall in walls {
            let (distance, pointOnWall) = distanceToWall(
                surfaceCenter: SIMD2(surface.center.x, surface.center.z),
                surfaceBounds: surface.bounds2D,
                wall: wall
            )

            if distance < minDistanceToAnyWall {
                minDistanceToAnyWall = distance
                closestWall = wall
                attachmentPoint = pointOnWall
            }
        }

        // Classify based on distances
        if minDistanceToAnyWall >= Self.islandMinWallDistance {
            // All walls are far enough - it's an island
            return .island
        } else if minDistanceToAnyWall <= Self.attachedMaxDistance {
            // Check if opposite end is free
            if let wall = closestWall {
                let oppositeDistance = distanceToOppositeWalls(
                    surfaceBounds: surface.bounds2D,
                    excludingWall: wall,
                    walls: walls
                )

                if oppositeDistance >= Self.peninsulaMinFreeDistance {
                    // Attached on one end, free on other - peninsula
                    return .peninsula(attachedWallId: wall.id, attachmentPoint: attachmentPoint)
                } else {
                    // Close to multiple walls - wall countertop
                    return .wallCountertop
                }
            }
            return .wallCountertop
        } else {
            // In between - classify as unknown for safety
            return .unknown
        }
    }

    /// Calculates minimum distance from surface bounds to a wall.
    /// Returns the minimum distance from any edge/corner of the surface to the wall.
    private func distanceToWall(
        surfaceCenter: SIMD2<Float>,
        surfaceBounds: (min: SIMD2<Float>, max: SIMD2<Float>),
        wall: AIWall
    ) -> (distance: Float, pointOnWall: Float) {
        // AIWall.startPoint and endPoint are already SIMD2<Float> (X, Z)
        let wallStart = wall.startPoint
        let wallEnd = wall.endPoint
        let wallVector = wallEnd - wallStart
        let wallLength = simd_length(wallVector)

        guard wallLength > 0 else {
            return (.infinity, 0)
        }

        // Check all 4 corners of the surface bounds
        let corners: [SIMD2<Float>] = [
            SIMD2(surfaceBounds.min.x, surfaceBounds.min.y), // min corner
            SIMD2(surfaceBounds.max.x, surfaceBounds.min.y), // max x, min z
            SIMD2(surfaceBounds.min.x, surfaceBounds.max.y), // min x, max z
            SIMD2(surfaceBounds.max.x, surfaceBounds.max.y)  // max corner
        ]

        var minDistance: Float = .infinity
        var bestPointOnWall: Float = 0

        for corner in corners {
            let toCorner = corner - wallStart
            var t = simd_dot(toCorner, wallVector) / (wallLength * wallLength)
            t = max(0, min(1, t))

            let closestPointOnWall = wallStart + t * wallVector
            let distance = simd_distance(corner, closestPointOnWall)

            if distance < minDistance {
                minDistance = distance
                bestPointOnWall = t * wallLength
            }
        }

        // Also check edge midpoints for better accuracy
        let edgeMidpoints: [SIMD2<Float>] = [
            SIMD2((surfaceBounds.min.x + surfaceBounds.max.x) / 2, surfaceBounds.min.y), // bottom edge
            SIMD2((surfaceBounds.min.x + surfaceBounds.max.x) / 2, surfaceBounds.max.y), // top edge
            SIMD2(surfaceBounds.min.x, (surfaceBounds.min.y + surfaceBounds.max.y) / 2), // left edge
            SIMD2(surfaceBounds.max.x, (surfaceBounds.min.y + surfaceBounds.max.y) / 2)  // right edge
        ]

        for midpoint in edgeMidpoints {
            let toMidpoint = midpoint - wallStart
            var t = simd_dot(toMidpoint, wallVector) / (wallLength * wallLength)
            t = max(0, min(1, t))

            let closestPointOnWall = wallStart + t * wallVector
            let distance = simd_distance(midpoint, closestPointOnWall)

            if distance < minDistance {
                minDistance = distance
                bestPointOnWall = t * wallLength
            }
        }

        return (minDistance, bestPointOnWall)
    }

    /// Calculates minimum distance to walls excluding one wall.
    private func distanceToOppositeWalls(
        surfaceBounds: (min: SIMD2<Float>, max: SIMD2<Float>),
        excludingWall: AIWall,
        walls: [AIWall]
    ) -> Float {
        let center = (surfaceBounds.min + surfaceBounds.max) / 2
        var minDistance: Float = .infinity

        for wall in walls where wall.id != excludingWall.id {
            let (distance, _) = distanceToWall(
                surfaceCenter: center,
                surfaceBounds: surfaceBounds,
                wall: wall
            )
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    // MARK: - Island Creation

    /// Creates an AIDetectedIsland from a detected surface.
    private func createIsland(
        from surface: DetectedSurface,
        roomStructure: AIRoomStructure
    ) -> AIDetectedIsland? {
        // Validate minimum size
        guard surface.length >= StandardIslandSizes.minIslandLength,
              surface.width >= StandardIslandSizes.minIslandWidth else {
            return nil
        }

        let boundingBox = AIBoundingBox3D(
            center: surface.center,
            size: SIMD3(surface.length, surface.height, surface.width)
        )

        let position = SIMD2(surface.center.x, surface.center.z)
        // Floor is at Y=0 after geometric constraints, so height is simply center.y
        let height = surface.center.y

        // Determine if bar height
        let isBarHeight = StandardIslandSizes.isBarHeight(height)

        return AIDetectedIsland(
            boundingBox: boundingBox,
            position: position,
            lengthInches: surface.length,
            widthInches: surface.width,
            heightInches: height,
            rotation: surface.rotation,
            hasSeating: false,  // Will be updated in overhang detection
            seatingOverhangInches: nil,
            seatingLengthInches: nil,
            appliancesOnIsland: [],
            confidence: .medium,  // Will be updated in confidence scoring
            isStandardSize: false,  // Will be updated in snapping
            rawDimensions: SIMD3(surface.length, height, surface.width),
            notes: isBarHeight ? ["Bar height island"] : []
        )
    }

    // MARK: - Peninsula Creation

    /// Creates an AIDetectedPeninsula from a detected surface.
    private func createPeninsula(
        from surface: DetectedSurface,
        attachedWallId: UUID,
        attachmentPoint: Float,
        roomStructure: AIRoomStructure
    ) -> AIDetectedPeninsula? {
        // Validate minimum size
        guard surface.length >= StandardIslandSizes.minPeninsulaLength,
              surface.width >= StandardIslandSizes.minPeninsulaWidth else {
            return nil
        }

        let boundingBox = AIBoundingBox3D(
            center: surface.center,
            size: SIMD3(surface.length, surface.height, surface.width)
        )

        // Floor is at Y=0 after geometric constraints, so height is simply center.y
        let height = surface.center.y

        // Determine extension direction based on wall orientation
        let direction = determineExtensionDirection(
            surface: surface,
            wallId: attachedWallId,
            walls: roomStructure.walls
        )

        return AIDetectedPeninsula(
            boundingBox: boundingBox,
            attachedWallId: attachedWallId,
            attachmentPointInches: attachmentPoint,
            lengthInches: surface.length,
            widthInches: surface.width,
            heightInches: height,
            extendsDirection: direction,
            hasSeating: false,  // Will be updated
            seatingOverhangInches: nil,
            seatingOnSide: nil,
            appliancesOnPeninsula: [],
            confidence: .medium,
            isStandardSize: false,
            rawDimensions: SIMD3(surface.length, height, surface.width),
            notes: []
        )
    }

    /// Determines the direction a peninsula extends from its wall.
    private func determineExtensionDirection(
        surface: DetectedSurface,
        wallId: UUID,
        walls: [AIWall]
    ) -> AIPeninsulaDirection {
        guard let wall = walls.first(where: { $0.id == wallId }) else {
            return .outward
        }

        // AIWall.startPoint and endPoint are already SIMD2<Float> (X, Z)
        let wallDirection = simd_normalize(wall.endPoint - wall.startPoint)

        let surfaceCenter = SIMD2(surface.center.x, surface.center.z)
        let wallMidpoint = (wall.startPoint + wall.endPoint) / 2

        let toSurface = surfaceCenter - wallMidpoint

        // Check if extending left, right, or outward from wall
        let parallelComponent = simd_dot(toSurface, wallDirection)
        let perpComponent = simd_dot(toSurface, SIMD2(-wallDirection.y, wallDirection.x))

        if abs(parallelComponent) > abs(perpComponent) {
            return parallelComponent > 0 ? .right : .left
        } else {
            return .outward
        }
    }

    // MARK: - Snapping

    /// Snaps island dimensions to standard sizes if within tolerance.
    private func snapIslandToStandardSize(_ island: AIDetectedIsland) -> AIDetectedIsland {
        let (standardLength, lengthDiff) = StandardIslandSizes.nearestIslandLength(to: island.lengthInches)
        let (standardWidth, widthDiff) = StandardIslandSizes.nearestIslandWidth(to: island.widthInches)

        let isStandard = lengthDiff <= StandardIslandSizes.snapHighTolerance &&
                        widthDiff <= StandardIslandSizes.snapHighTolerance

        let snappedLength = isStandard ? standardLength : island.lengthInches
        let snappedWidth = isStandard ? standardWidth : island.widthInches

        return AIDetectedIsland(
            id: island.id,
            boundingBox: island.boundingBox,
            position: island.position,
            lengthInches: snappedLength,
            widthInches: snappedWidth,
            heightInches: island.heightInches,
            rotation: island.rotation,
            hasSeating: island.hasSeating,
            seatingOverhangInches: island.seatingOverhangInches,
            seatingLengthInches: island.seatingLengthInches,
            appliancesOnIsland: island.appliancesOnIsland,
            confidence: island.confidence,
            isStandardSize: isStandard,
            rawDimensions: island.rawDimensions,
            notes: island.notes
        )
    }

    /// Snaps peninsula dimensions to standard sizes if within tolerance.
    private func snapPeninsulaToStandardSize(_ peninsula: AIDetectedPeninsula) -> AIDetectedPeninsula {
        let (standardLength, lengthDiff) = StandardIslandSizes.nearestPeninsulaLength(to: peninsula.lengthInches)
        let (standardWidth, widthDiff) = StandardIslandSizes.nearestPeninsulaWidth(to: peninsula.widthInches)

        let isStandard = lengthDiff <= StandardIslandSizes.snapHighTolerance &&
                        widthDiff <= StandardIslandSizes.snapHighTolerance

        let snappedLength = isStandard ? standardLength : peninsula.lengthInches
        let snappedWidth = isStandard ? standardWidth : peninsula.widthInches

        return AIDetectedPeninsula(
            id: peninsula.id,
            boundingBox: peninsula.boundingBox,
            attachedWallId: peninsula.attachedWallId,
            attachmentPointInches: peninsula.attachmentPointInches,
            lengthInches: snappedLength,
            widthInches: snappedWidth,
            heightInches: peninsula.heightInches,
            extendsDirection: peninsula.extendsDirection,
            hasSeating: peninsula.hasSeating,
            seatingOverhangInches: peninsula.seatingOverhangInches,
            seatingOnSide: peninsula.seatingOnSide,
            appliancesOnPeninsula: peninsula.appliancesOnPeninsula,
            confidence: peninsula.confidence,
            isStandardSize: isStandard,
            rawDimensions: peninsula.rawDimensions,
            notes: peninsula.notes
        )
    }

    // MARK: - Appliance Association

    /// Associates appliances with an island based on bounds check.
    private func associateAppliances(
        with island: AIDetectedIsland,
        appliances: ApplianceDetectionResult
    ) -> AIDetectedIsland {
        var islandAppliances: [AIIslandAppliance] = []

        for appliance in appliances.appliances {
            let appliancePosition = SIMD2(appliance.boundingBox.center.x, appliance.boundingBox.center.z)

            if island.contains(point: appliancePosition) {
                let type: AIIslandApplianceType
                switch appliance.type {
                case .sink:
                    type = .sink
                case .cooktop:
                    type = .cooktop
                case .dishwasher:
                    type = .dishwasher
                default:
                    continue  // Skip other appliance types
                }

                let positionOnSurface = SIMD2(
                    appliancePosition.x - island.position.x,
                    appliancePosition.y - island.position.y
                )

                islandAppliances.append(AIIslandAppliance(
                    type: type,
                    positionOnSurface: positionOnSurface,
                    widthInches: appliance.boundingBox.size.x,
                    depthInches: appliance.boundingBox.size.z,
                    applianceId: appliance.id
                ))
            }
        }

        return AIDetectedIsland(
            id: island.id,
            boundingBox: island.boundingBox,
            position: island.position,
            lengthInches: island.lengthInches,
            widthInches: island.widthInches,
            heightInches: island.heightInches,
            rotation: island.rotation,
            hasSeating: island.hasSeating,
            seatingOverhangInches: island.seatingOverhangInches,
            seatingLengthInches: island.seatingLengthInches,
            appliancesOnIsland: islandAppliances,
            confidence: island.confidence,
            isStandardSize: island.isStandardSize,
            rawDimensions: island.rawDimensions,
            notes: island.notes
        )
    }

    /// Associates appliances with a peninsula based on bounds check.
    private func associateAppliances(
        with peninsula: AIDetectedPeninsula,
        appliances: ApplianceDetectionResult
    ) -> AIDetectedPeninsula {
        var peninsulaAppliances: [AIIslandAppliance] = []

        for appliance in appliances.appliances {
            let appliancePosition = SIMD2(appliance.boundingBox.center.x, appliance.boundingBox.center.z)

            if peninsula.contains(point: appliancePosition) {
                let type: AIIslandApplianceType
                switch appliance.type {
                case .sink:
                    type = .sink
                case .cooktop:
                    type = .cooktop
                case .dishwasher:
                    type = .dishwasher
                default:
                    continue
                }

                let center = SIMD2(peninsula.boundingBox.center.x, peninsula.boundingBox.center.z)
                let positionOnSurface = SIMD2(
                    appliancePosition.x - center.x,
                    appliancePosition.y - center.y
                )

                peninsulaAppliances.append(AIIslandAppliance(
                    type: type,
                    positionOnSurface: positionOnSurface,
                    widthInches: appliance.boundingBox.size.x,
                    depthInches: appliance.boundingBox.size.z,
                    applianceId: appliance.id
                ))
            }
        }

        return AIDetectedPeninsula(
            id: peninsula.id,
            boundingBox: peninsula.boundingBox,
            attachedWallId: peninsula.attachedWallId,
            attachmentPointInches: peninsula.attachmentPointInches,
            lengthInches: peninsula.lengthInches,
            widthInches: peninsula.widthInches,
            heightInches: peninsula.heightInches,
            extendsDirection: peninsula.extendsDirection,
            hasSeating: peninsula.hasSeating,
            seatingOverhangInches: peninsula.seatingOverhangInches,
            seatingOnSide: peninsula.seatingOnSide,
            appliancesOnPeninsula: peninsulaAppliances,
            confidence: peninsula.confidence,
            isStandardSize: peninsula.isStandardSize,
            rawDimensions: peninsula.rawDimensions,
            notes: peninsula.notes
        )
    }

    // MARK: - Seating Overhang Detection (Task 7 - AC6)

    /// Detects seating overhang for an island by comparing surface to base cabinet below.
    ///
    /// Per AC6: Overhang > 10" indicates seating area.
    /// Common overhang depths: 12", 15", 18" for bar stools.
    private func detectSeatingOverhang(
        for island: AIDetectedIsland,
        cabinets: CabinetDetectionResult
    ) -> AIDetectedIsland {
        // Find base cabinets that are part of this island
        // Islands typically have cabinets underneath that are smaller than the countertop
        let islandBounds = island.boundingBox

        // Look for cabinets within the island's horizontal bounds
        let cabinetsBelowIsland = cabinets.cabinets.filter { cabinet in
            let cabinetPos = SIMD2(cabinet.boundingBox.center.x, cabinet.boundingBox.center.z)
            return island.contains(point: cabinetPos, tolerance: 0)
        }

        // If no cabinets found below, assume standard size with potential seating on one side
        guard !cabinetsBelowIsland.isEmpty else {
            // Heuristic: Islands wider than 36" likely have seating overhang
            if island.widthInches > 36 {
                let estimatedOverhang = island.widthInches - 24.0  // Assume 24" base cabinet
                if estimatedOverhang >= StandardIslandSizes.minSeatingOverhang {
                    let (snappedOverhang, _) = StandardIslandSizes.nearestSeatingOverhang(to: estimatedOverhang)
                    return AIDetectedIsland(
                        id: island.id,
                        boundingBox: island.boundingBox,
                        position: island.position,
                        lengthInches: island.lengthInches,
                        widthInches: island.widthInches,
                        heightInches: island.heightInches,
                        rotation: island.rotation,
                        hasSeating: true,
                        seatingOverhangInches: snappedOverhang,
                        seatingLengthInches: island.lengthInches,  // Full length seating
                        appliancesOnIsland: island.appliancesOnIsland,
                        confidence: island.confidence,
                        isStandardSize: island.isStandardSize,
                        rawDimensions: island.rawDimensions,
                        notes: island.notes + ["Seating overhang estimated from island width"]
                    )
                }
            }
            return island
        }

        // Calculate overhang from cabinet bounds vs island bounds
        let cabinetMaxX = cabinetsBelowIsland.map { $0.boundingBox.center.x + $0.boundingBox.size.x / 2 }.max() ?? 0
        let cabinetMinX = cabinetsBelowIsland.map { $0.boundingBox.center.x - $0.boundingBox.size.x / 2 }.min() ?? 0
        let cabinetMaxZ = cabinetsBelowIsland.map { $0.boundingBox.center.z + $0.boundingBox.size.z / 2 }.max() ?? 0
        let cabinetMinZ = cabinetsBelowIsland.map { $0.boundingBox.center.z - $0.boundingBox.size.z / 2 }.min() ?? 0

        let islandMaxX = islandBounds.center.x + islandBounds.size.x / 2
        let islandMinX = islandBounds.center.x - islandBounds.size.x / 2
        let islandMaxZ = islandBounds.center.z + islandBounds.size.z / 2
        let islandMinZ = islandBounds.center.z - islandBounds.size.z / 2

        // Calculate overhangs on each side
        let overhangPlusX = islandMaxX - cabinetMaxX
        let overhangMinusX = cabinetMinX - islandMinX
        let overhangPlusZ = islandMaxZ - cabinetMaxZ
        let overhangMinusZ = cabinetMinZ - islandMinZ

        // Find the largest overhang
        let maxOverhang = max(overhangPlusX, overhangMinusX, overhangPlusZ, overhangMinusZ)

        if maxOverhang >= StandardIslandSizes.minSeatingOverhang {
            let (snappedOverhang, _) = StandardIslandSizes.nearestSeatingOverhang(to: maxOverhang)
            // Estimate seating length based on which side has the overhang
            let seatingLength: Float
            if maxOverhang == overhangPlusX || maxOverhang == overhangMinusX {
                seatingLength = islandBounds.size.z  // Seating along Z axis
            } else {
                seatingLength = islandBounds.size.x  // Seating along X axis
            }

            return AIDetectedIsland(
                id: island.id,
                boundingBox: island.boundingBox,
                position: island.position,
                lengthInches: island.lengthInches,
                widthInches: island.widthInches,
                heightInches: island.heightInches,
                rotation: island.rotation,
                hasSeating: true,
                seatingOverhangInches: snappedOverhang,
                seatingLengthInches: seatingLength,
                appliancesOnIsland: island.appliancesOnIsland,
                confidence: island.confidence,
                isStandardSize: island.isStandardSize,
                rawDimensions: island.rawDimensions,
                notes: island.notes
            )
        }

        return island
    }

    /// Detects seating overhang for a peninsula.
    ///
    /// Per AC6: Peninsula seating is typically at the end (away from wall).
    private func detectSeatingOverhang(
        for peninsula: AIDetectedPeninsula,
        cabinets: CabinetDetectionResult
    ) -> AIDetectedPeninsula {
        // Peninsula seating is typically at the end (most common)
        // If peninsula is wide enough, assume end seating
        if peninsula.lengthInches >= 36 && peninsula.widthInches >= 24 {
            // Estimate overhang as width minus standard base cabinet depth (24")
            let estimatedOverhang = peninsula.widthInches - 24.0

            if estimatedOverhang >= StandardIslandSizes.minSeatingOverhang {
                let (snappedOverhang, _) = StandardIslandSizes.nearestSeatingOverhang(to: estimatedOverhang)

                return AIDetectedPeninsula(
                    id: peninsula.id,
                    boundingBox: peninsula.boundingBox,
                    attachedWallId: peninsula.attachedWallId,
                    attachmentPointInches: peninsula.attachmentPointInches,
                    lengthInches: peninsula.lengthInches,
                    widthInches: peninsula.widthInches,
                    heightInches: peninsula.heightInches,
                    extendsDirection: peninsula.extendsDirection,
                    hasSeating: true,
                    seatingOverhangInches: snappedOverhang,
                    seatingOnSide: .end,  // Most common for peninsulas
                    appliancesOnPeninsula: peninsula.appliancesOnPeninsula,
                    confidence: peninsula.confidence,
                    isStandardSize: peninsula.isStandardSize,
                    rawDimensions: peninsula.rawDimensions,
                    notes: peninsula.notes + ["End seating estimated from dimensions"]
                )
            }
        }

        return peninsula
    }

    // MARK: - Cutout Calculation (Task 9 - AC7, AC9)

    /// Calculates countertop cutouts for appliances on an island.
    ///
    /// Per AC7: Sink and cooktop cutouts are subtracted from countertop area.
    private func calculateCutoutsForIsland(_ island: AIDetectedIsland) -> AIDetectedIsland {
        // Cutout data is stored in the appliances themselves
        // This method ensures the island has the calculated cutout info
        // The AIIslandAppliance already has widthInches and depthInches for cutout calculation
        // No mutation needed - cutout area is computed from appliancesOnIsland
        return island
    }

    /// Calculates countertop cutouts for appliances on a peninsula.
    private func calculateCutoutsForPeninsula(_ peninsula: AIDetectedPeninsula) -> AIDetectedPeninsula {
        // Same as island - cutout data is in the appliances
        return peninsula
    }

    // MARK: - Confidence Scoring

    /// Calculates confidence for an island.
    private func calculateConfidence(
        for island: AIDetectedIsland,
        roomStructure: AIRoomStructure
    ) -> AIDetectedIsland {
        var score: Float = 0.5  // Start at medium

        // Clear wall separation (>36") adds confidence
        let minWallDistance = calculateMinWallDistance(
            position: island.position,
            walls: roomStructure.walls
        )
        if minWallDistance >= StandardIslandSizes.preferredIslandClearance {
            score += 0.2
        } else if minWallDistance >= StandardIslandSizes.minIslandWallDistance {
            score += 0.1
        }

        // Standard size match adds confidence
        if island.isStandardSize {
            score += 0.2
        }

        // Logical height (36" or 42") adds confidence
        if StandardIslandSizes.isStandardHeight(island.heightInches) ||
           StandardIslandSizes.isBarHeight(island.heightInches) {
            score += 0.1
        }

        // Determine confidence level
        let confidence: AIConfidenceLevel
        if score >= 0.85 {
            confidence = .high
        } else if score >= 0.6 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return AIDetectedIsland(
            id: island.id,
            boundingBox: island.boundingBox,
            position: island.position,
            lengthInches: island.lengthInches,
            widthInches: island.widthInches,
            heightInches: island.heightInches,
            rotation: island.rotation,
            hasSeating: island.hasSeating,
            seatingOverhangInches: island.seatingOverhangInches,
            seatingLengthInches: island.seatingLengthInches,
            appliancesOnIsland: island.appliancesOnIsland,
            confidence: confidence,
            isStandardSize: island.isStandardSize,
            rawDimensions: island.rawDimensions,
            notes: island.notes
        )
    }

    /// Calculates confidence for a peninsula.
    private func calculateConfidence(
        for peninsula: AIDetectedPeninsula,
        roomStructure: AIRoomStructure
    ) -> AIDetectedPeninsula {
        var score: Float = 0.5

        // Standard size match adds confidence
        if peninsula.isStandardSize {
            score += 0.25
        }

        // Logical height adds confidence
        if StandardIslandSizes.isStandardHeight(peninsula.heightInches) ||
           StandardIslandSizes.isBarHeight(peninsula.heightInches) {
            score += 0.15
        }

        // Valid attachment to wall adds confidence
        if roomStructure.walls.contains(where: { $0.id == peninsula.attachedWallId }) {
            score += 0.1
        }

        let confidence: AIConfidenceLevel
        if score >= 0.85 {
            confidence = .high
        } else if score >= 0.6 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return AIDetectedPeninsula(
            id: peninsula.id,
            boundingBox: peninsula.boundingBox,
            attachedWallId: peninsula.attachedWallId,
            attachmentPointInches: peninsula.attachmentPointInches,
            lengthInches: peninsula.lengthInches,
            widthInches: peninsula.widthInches,
            heightInches: peninsula.heightInches,
            extendsDirection: peninsula.extendsDirection,
            hasSeating: peninsula.hasSeating,
            seatingOverhangInches: peninsula.seatingOverhangInches,
            seatingOnSide: peninsula.seatingOnSide,
            appliancesOnPeninsula: peninsula.appliancesOnPeninsula,
            confidence: confidence,
            isStandardSize: peninsula.isStandardSize,
            rawDimensions: peninsula.rawDimensions,
            notes: peninsula.notes
        )
    }

    /// Calculates minimum distance from a position to all walls.
    private func calculateMinWallDistance(
        position: SIMD2<Float>,
        walls: [AIWall]
    ) -> Float {
        var minDistance: Float = .infinity

        for wall in walls {
            // AIWall.startPoint and endPoint are already SIMD2<Float> (X, Z)
            let wallStart = wall.startPoint
            let wallEnd = wall.endPoint
            let wallVector = wallEnd - wallStart
            let wallLength = simd_length(wallVector)

            guard wallLength > 0 else { continue }

            let wallDirection = wallVector / wallLength
            let toPosition = position - wallStart
            var t = simd_dot(toPosition, wallDirection) / wallLength
            t = max(0, min(1, t))

            let closestPoint = wallStart + t * wallVector
            let distance = simd_distance(position, closestPoint)
            minDistance = min(minDistance, distance)
        }

        return minDistance
    }

    // MARK: - Validation

    /// Validates that no islands and peninsulas overlap.
    private func validateNoOverlap(
        islands: [AIDetectedIsland],
        peninsulas: [AIDetectedPeninsula]
    ) -> (islands: [AIDetectedIsland], peninsulas: [AIDetectedPeninsula], warnings: [String]) {
        var warnings: [String] = []
        var validIslands = islands
        var validPeninsulas = peninsulas

        // Check for overlap between islands and peninsulas
        for island in islands {
            for peninsula in peninsulas {
                let peninsulaCenter = SIMD2(peninsula.boundingBox.center.x, peninsula.boundingBox.center.z)
                if island.contains(point: peninsulaCenter, tolerance: 0) {
                    // Overlap detected - keep the one with higher confidence
                    if island.confidence >= peninsula.confidence {
                        validPeninsulas.removeAll { $0.id == peninsula.id }
                        warnings.append("Removed overlapping peninsula in favor of island")
                    } else {
                        validIslands.removeAll { $0.id == island.id }
                        warnings.append("Removed overlapping island in favor of peninsula")
                    }
                }
            }
        }

        return (validIslands, validPeninsulas, warnings)
    }
}

// MARK: - Detected Surface (Internal)

/// Internal representation of a detected horizontal surface.
private struct DetectedSurface {
    /// Center point of the surface
    let center: SIMD3<Float>

    /// Length (longer dimension) in inches
    let length: Float

    /// Width (shorter dimension) in inches
    let width: Float

    /// Height (thickness) in inches
    let height: Float

    /// Rotation angle in degrees
    let rotation: Float

    /// Area in square inches
    var area: Float {
        length * width
    }

    /// 2D bounds (min, max) in x-z plane
    let bounds2D: (min: SIMD2<Float>, max: SIMD2<Float>)

    /// Creates a surface from a set of points.
    init?(points: [SIMD3<Float>]) {
        guard points.count >= 10 else { return nil }

        // Calculate bounds
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        var minY: Float = .infinity
        var maxY: Float = -.infinity
        var minZ: Float = .infinity
        var maxZ: Float = -.infinity

        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }

        let sizeX = maxX - minX
        let sizeY = maxY - minY
        let sizeZ = maxZ - minZ

        // Longer dimension is length, shorter is width
        if sizeX >= sizeZ {
            self.length = sizeX
            self.width = sizeZ
        } else {
            self.length = sizeZ
            self.width = sizeX
        }

        self.height = sizeY
        self.center = SIMD3(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            (minZ + maxZ) / 2
        )
        self.bounds2D = (SIMD2(minX, minZ), SIMD2(maxX, maxZ))

        // Calculate rotation using principal axis (2D covariance matrix eigenvalue)
        self.rotation = Self.calculateRotation(points: points, center: self.center)
    }

    /// Calculates the rotation angle of the surface's principal axis in degrees.
    ///
    /// Uses 2D covariance matrix to find the principal axis orientation.
    /// Returns angle in degrees from the positive X axis.
    private static func calculateRotation(points: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
        guard points.count >= 10 else { return 0 }

        // Compute 2D covariance matrix elements (x-z plane)
        var cxx: Float = 0
        var czz: Float = 0
        var cxz: Float = 0

        for point in points {
            let dx = point.x - center.x
            let dz = point.z - center.z
            cxx += dx * dx
            czz += dz * dz
            cxz += dx * dz
        }

        let n = Float(points.count)
        cxx /= n
        czz /= n
        cxz /= n

        // Calculate angle of principal axis using atan2 of eigenvector
        // For 2x2 symmetric matrix [[cxx, cxz], [cxz, czz]], the eigenvector
        // of the larger eigenvalue gives the principal axis
        let theta = 0.5 * atan2(2 * cxz, cxx - czz)

        // Convert to degrees
        return theta * 180.0 / .pi
    }
}
