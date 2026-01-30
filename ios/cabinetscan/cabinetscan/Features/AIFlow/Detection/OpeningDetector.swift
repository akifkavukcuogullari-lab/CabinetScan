//
//  OpeningDetector.swift
//  cabinetscan
//
//  Created for Story 4.9: Window and Door Detection
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Opening Detector Protocol

/// Protocol for opening detection implementations.
/// Enables testing with mock detectors.
protocol OpeningDetectorProtocol {
    /// Detects windows and doors from room structure, point cloud, and existing cabinets.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure from RoomDetector (walls, floor plane)
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Detected cabinets for clearance calculation
    /// - Returns: Opening detection result with all detected windows and doors
    /// - Throws: `OpeningDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: [AIDetectedCabinet]
    ) async throws -> OpeningDetectionResult
}

// MARK: - Opening Detection Phase

/// Phases of opening detection for progress tracking.
enum OpeningDetectionPhase: String {
    case idle = "Idle"
    case windowDetection = "Detecting Windows"
    case doorDetection = "Detecting Doors"
    case measurementExtraction = "Extracting Dimensions"
    case clearanceCalculation = "Calculating Clearances"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Opening Detection Error

/// Errors that can occur during opening detection.
enum OpeningDetectionError: LocalizedError, Equatable {
    case noPointCloud
    case noWallsDetected
    case detectionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .noPointCloud:
            return "No point cloud data available for opening detection"
        case .noWallsDetected:
            return "No walls detected in room structure"
        case .detectionFailed(let reason):
            return "Opening detection failed: \(reason)"
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .noPointCloud:
            return "Couldn't detect openings. Please scan again with better coverage."
        case .noWallsDetected:
            return "Couldn't detect wall openings. Ensure walls are visible in scan."
        case .detectionFailed:
            return "Couldn't detect windows and doors. You can add them manually."
        }
    }
}

// MARK: - Opening Detection Result

/// Result of opening detection containing all detected windows and doors.
struct OpeningDetectionResult {
    /// Detected windows
    let windows: [AIDetectedWindow]

    /// Detected doors
    let doors: [AIDetectedDoor]

    /// Cabinet clearances for each opening
    let clearances: [OpeningClearance]

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection
    let warnings: [String]

    // MARK: - Computed Properties

    /// Total number of detected openings
    var totalCount: Int { windows.count + doors.count }

    /// Windows detected above countertop level (sink windows)
    var windowsAboveCountertop: [AIDetectedWindow] {
        windows.filter { $0.sillHeightInches >= StandardOpeningSizes.typicalWindowSillHeight }
    }

    /// Doors with clearance issues (require fillers)
    var doorsWithClearanceIssues: [AIDetectedDoor] {
        let doorIds = Set(clearances.filter { $0.requiresFiller }.map { $0.openingId })
        return doors.filter { doorIds.contains($0.id) }
    }
}

// MARK: - Opening Clearance

/// Represents clearance between an opening and adjacent cabinet.
struct OpeningClearance {
    /// ID of the opening
    let openingId: UUID

    /// ID of the nearest cabinet (nil if no adjacent cabinet)
    let nearestCabinetId: UUID?

    /// Clearance distance in inches
    let clearanceInches: Float

    /// Which side(s) the clearance applies to
    let side: ClearanceSide

    /// Whether a filler is required (clearance < 3")
    let requiresFiller: Bool
}

/// Side of an opening for clearance calculation.
enum ClearanceSide: String, Codable {
    case left
    case right
    case both
}

// MARK: - Standard Opening Sizes

/// Standard opening sizes for windows and doors.
/// Used for dimension snapping and validation.
struct StandardOpeningSizes {
    // MARK: - Window Widths (inches)

    /// Standard kitchen window widths
    static let windowWidths: [Float] = [24, 30, 36, 42, 48, 60, 72]

    // MARK: - Window Heights (inches)

    /// Standard kitchen window heights
    static let windowHeights: [Float] = [24, 30, 36, 42, 48]

    // MARK: - Door Widths (inches)

    /// Standard interior door widths
    static let doorWidths: [Float] = [24, 28, 30, 32, 36]

    // MARK: - Door Heights (inches)

    /// Standard door height (6'8")
    static let standardDoorHeight: Float = 80.0

    /// Minimum height for full height door
    static let fullHeightDoorMin: Float = 84.0

    // MARK: - Window Sill Heights (inches)

    /// Typical window sill height from floor (above countertop level)
    static let typicalWindowSillHeight: Float = 36.0

    /// Minimum sill height for kitchen windows (6" above 36" counter)
    static let kitchenWindowMinSillHeight: Float = 42.0

    // MARK: - Snapping Thresholds

    /// Threshold for HIGH confidence snap (same as cabinets per Architecture 7.3)
    static let snapHighThreshold: Float = 1.5

    /// Threshold for MEDIUM confidence snap
    static let snapMediumThreshold: Float = 3.0

    // MARK: - Dimension Constraints

    /// Minimum window width
    static let minWindowWidth: Float = 24.0

    /// Maximum window width
    static let maxWindowWidth: Float = 72.0

    /// Minimum window height
    static let minWindowHeight: Float = 24.0

    /// Maximum window height
    static let maxWindowHeight: Float = 48.0

    /// Minimum door width
    static let minDoorWidth: Float = 24.0

    /// Maximum door width
    static let maxDoorWidth: Float = 36.0

    /// Floor proximity threshold for door detection
    static let doorFloorProximity: Float = 2.0

    // MARK: - Filler Threshold

    /// Minimum clearance before filler is required
    static let fillerClearanceThreshold: Float = 3.0

    /// Clearance value indicating no adjacent cabinet exists
    static let noAdjacentCabinetClearance: Float = 999.0

    // MARK: - Snapping Methods

    /// Finds the nearest standard window width.
    ///
    /// - Parameter raw: Raw measured width
    /// - Returns: Tuple of (nearest standard width, difference from raw)
    static func nearestWindowWidth(to raw: Float) -> (standard: Float, difference: Float) {
        let nearest = windowWidths.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
        return (nearest, abs(nearest - raw))
    }

    /// Finds the nearest standard window height.
    ///
    /// - Parameter raw: Raw measured height
    /// - Returns: Tuple of (nearest standard height, difference from raw)
    static func nearestWindowHeight(to raw: Float) -> (standard: Float, difference: Float) {
        let nearest = windowHeights.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
        return (nearest, abs(nearest - raw))
    }

    /// Finds the nearest standard door width.
    ///
    /// - Parameter raw: Raw measured width
    /// - Returns: Tuple of (nearest standard width, difference from raw)
    static func nearestDoorWidth(to raw: Float) -> (standard: Float, difference: Float) {
        let nearest = doorWidths.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? raw
        return (nearest, abs(nearest - raw))
    }

    /// Determines if a raw dimension should snap to standard.
    ///
    /// - Parameters:
    ///   - raw: Raw measured dimension
    ///   - standard: Nearest standard dimension
    /// - Returns: Tuple of (should snap, confidence level)
    static func shouldSnap(raw: Float, standard: Float) -> (shouldSnap: Bool, confidence: AIConfidenceLevel) {
        let diff = abs(raw - standard)
        if diff <= snapHighThreshold {
            return (true, .high)
        } else if diff <= snapMediumThreshold {
            return (false, .medium)
        } else {
            return (false, .low)
        }
    }
}

// MARK: - Opening Detector

/// Detects windows and doors from calibrated 3D point cloud.
///
/// **Algorithm Pipeline (ADR-1: Multi-Signal with Confidence Guards):**
/// 1. Wall Density Check - Calculate point density per wall for confidence capping
/// 2. Window Detection - Find voids above countertop height with frame validation
/// 3. Door Detection - Find voids from floor level with standard height profiles
/// 4. Dimension Extraction - Measure width, height and snap to standards
/// 5. Clearance Calculation - Calculate cabinet clearances for quotes
///
/// **Performance Budget:** <100ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = OpeningDetector()
/// let result = try await detector.detect(
///     roomStructure: room,
///     pointCloud: cloud,
///     cabinets: cabinets
/// )
/// ```
@MainActor
final class OpeningDetector: ObservableObject, OpeningDetectorProtocol {

    // MARK: - Constants

    /// Minimum wall point density for HIGH confidence (points per sq ft)
    private static let highDensityThreshold: Float = 50.0

    /// Minimum wall point density for MEDIUM confidence (points per sq ft)
    private static let lowDensityThreshold: Float = 20.0

    /// Density ratio for detecting voids (opening has <20% of average density)
    private static let voidDensityRatio: Float = 0.20

    /// Frame validation threshold (border density > 150% of void density)
    private static let frameDensityRatio: Float = 1.5

    /// Grid cell size for density analysis (inches)
    private static let densityGridCellSize: Float = 3.0

    /// Minimum points required for wall analysis
    private static let minWallPoints: Int = 20

    /// Distance from wall to consider as "on wall" (inches)
    private static let wallProximityThreshold: Float = 6.0

    /// Upper cabinet clearance from window (inches)
    private static let upperCabinetMinClearance: Float = 18.0

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: OpeningDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "OpeningDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("OpeningDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all windows and doors from room structure and point cloud.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and floor plane
    ///   - pointCloud: Calibrated point cloud in inches
    ///   - cabinets: Detected cabinets for clearance calculation
    /// - Returns: Opening detection result with all detected windows and doors
    /// - Throws: `OpeningDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud,
        cabinets: [AIDetectedCabinet]
    ) async throws -> OpeningDetectionResult {
        logger.info("Starting opening detection with \(pointCloud.count) points, \(roomStructure.walls.count) walls")

        guard !pointCloud.isEmpty else {
            throw OpeningDetectionError.noPointCloud
        }

        guard !roomStructure.walls.isEmpty else {
            throw OpeningDetectionError.noWallsDetected
        }

        isProcessing = true
        progress = 0.0
        currentPhase = .windowDetection

        let startTime = CFAbsoluteTimeGetCurrent()
        var warnings: [String] = []

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Get points from point cloud
        var mutablePointCloud = pointCloud
        let points = mutablePointCloud.getPoints()
        let floorY: Float = -roomStructure.floorPlane.distance
        let ceilingHeight = Float(roomStructure.ceilingHeightInches)

        // Calculate wall densities for confidence capping (ADR-1)
        var wallDensities: [UUID: Float] = [:]
        for (wallIndex, wall) in roomStructure.walls.enumerated() {
            let density = calculateWallDensity(points: points, wall: wall, floorY: floorY, ceilingHeight: ceilingHeight)
            wallDensities[wall.id] = density

            if density < Self.lowDensityThreshold {
                warnings.append("Wall \(wallIndex + 1): very sparse data (\(Int(density)) pts/sqft) - opening detection may be unreliable")
            } else if density < Self.highDensityThreshold {
                warnings.append("Wall \(wallIndex + 1): sparse data (\(Int(density)) pts/sqft) - verify openings manually")
            }
        }
        progress = 0.10

        // Detect windows
        try Task.checkCancellation()
        currentPhase = .windowDetection
        let windows = detectWindows(
            points: points,
            walls: roomStructure.walls,
            floorY: floorY,
            ceilingHeight: ceilingHeight,
            wallDensities: wallDensities
        )
        progress = 0.40
        logger.info("Detected \(windows.count) windows")

        // Detect doors
        try Task.checkCancellation()
        currentPhase = .doorDetection
        let doors = detectDoors(
            points: points,
            walls: roomStructure.walls,
            floorY: floorY,
            ceilingHeight: ceilingHeight,
            wallDensities: wallDensities
        )
        progress = 0.70
        logger.info("Detected \(doors.count) doors")

        // Calculate cabinet clearances
        try Task.checkCancellation()
        currentPhase = .clearanceCalculation
        var allOpenings: [(id: UUID, wallId: UUID, positionOnWall: Float, width: Float)] = []

        for window in windows {
            allOpenings.append((window.id, window.wallId, window.positionOnWallInches, window.widthInches))
        }
        for door in doors {
            allOpenings.append((door.id, door.wallId, door.positionOnWallInches, door.widthInches))
        }

        let clearances = calculateCabinetClearances(
            openings: allOpenings,
            cabinets: cabinets,
            walls: roomStructure.walls
        )
        progress = 0.90

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        logger.info("Opening detection complete in \(processingTimeMs)ms: \(windows.count) windows, \(doors.count) doors")

        return OpeningDetectionResult(
            windows: windows,
            doors: doors,
            clearances: clearances,
            processingTimeMs: processingTimeMs,
            warnings: warnings
        )
    }

    // MARK: - Wall Density Calculation (ADR-1)

    /// Calculates point density for a wall (points per square foot).
    ///
    /// - Parameters:
    ///   - points: All points in the point cloud
    ///   - wall: The wall to calculate density for
    ///   - floorY: Y coordinate of the floor
    ///   - ceilingHeight: Ceiling height in inches
    /// - Returns: Point density in points per square foot
    private func calculateWallDensity(
        points: [SIMD3<Float>],
        wall: AIWall,
        floorY: Float,
        ceilingHeight: Float
    ) -> Float {
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)
        let wallLength = Float(wall.lengthInches)

        var wallPointCount = 0

        for point in points {
            let heightAboveFloor = point.y - floorY
            guard heightAboveFloor >= 0 && heightAboveFloor <= ceilingHeight else { continue }

            let point2D = SIMD2<Float>(point.x, point.z)
            let toPoint = point2D - wall.startPoint

            let alongWall = simd_dot(toPoint, wallDir)
            let fromWall = abs(simd_dot(toPoint, wallNormal))

            guard alongWall >= 0 && alongWall <= wallLength &&
                  fromWall <= Self.wallProximityThreshold else { continue }

            wallPointCount += 1
        }

        // Calculate area in square feet (wall length x ceiling height / 144)
        let wallAreaSqFt = (wallLength * ceilingHeight) / 144.0
        return wallAreaSqFt > 0 ? Float(wallPointCount) / wallAreaSqFt : 0
    }

    // MARK: - Window Detection (Task 4)

    /// Detects windows using multi-signal detection (ADR-1).
    ///
    /// **Signals:**
    /// 1. Density void - rectangular low-density region
    /// 2. Height constraint - void bottom >36" from floor
    /// 3. Frame validation - higher density border around void
    ///
    /// - Parameters:
    ///   - points: All points in the point cloud
    ///   - walls: Detected walls
    ///   - floorY: Y coordinate of the floor
    ///   - ceilingHeight: Ceiling height in inches
    ///   - wallDensities: Pre-calculated wall densities for confidence capping
    /// - Returns: Array of detected windows
    private func detectWindows(
        points: [SIMD3<Float>],
        walls: [AIWall],
        floorY: Float,
        ceilingHeight: Float,
        wallDensities: [UUID: Float]
    ) -> [AIDetectedWindow] {
        var windows: [AIDetectedWindow] = []

        for wall in walls {
            let wallWindows = detectWindowsOnWall(
                points: points,
                wall: wall,
                floorY: floorY,
                ceilingHeight: ceilingHeight,
                wallDensity: wallDensities[wall.id] ?? 0
            )
            windows.append(contentsOf: wallWindows)
        }

        return windows
    }

    /// Detects windows on a single wall.
    private func detectWindowsOnWall(
        points: [SIMD3<Float>],
        wall: AIWall,
        floorY: Float,
        ceilingHeight: Float,
        wallDensity: Float
    ) -> [AIDetectedWindow] {
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)
        let wallLength = Float(wall.lengthInches)

        // Project points to wall coordinates
        var wallPoints: [(alongWall: Float, height: Float)] = []

        for point in points {
            let heightAboveFloor = point.y - floorY
            guard heightAboveFloor >= StandardOpeningSizes.typicalWindowSillHeight &&
                  heightAboveFloor <= ceilingHeight - 6 else { continue }

            let point2D = SIMD2<Float>(point.x, point.z)
            let toPoint = point2D - wall.startPoint

            let alongWall = simd_dot(toPoint, wallDir)
            let fromWall = abs(simd_dot(toPoint, wallNormal))

            guard alongWall >= 0 && alongWall <= wallLength &&
                  fromWall <= Self.wallProximityThreshold else { continue }

            wallPoints.append((alongWall, heightAboveFloor))
        }

        guard wallPoints.count >= Self.minWallPoints else { return [] }

        // Create density grid
        let gridWidth = Int(wallLength / Self.densityGridCellSize) + 1
        let gridHeight = Int((ceilingHeight - StandardOpeningSizes.typicalWindowSillHeight) / Self.densityGridCellSize) + 1

        var densityGrid = Array(repeating: Array(repeating: 0, count: gridHeight), count: gridWidth)

        for wp in wallPoints {
            let gridX = min(Int(wp.alongWall / Self.densityGridCellSize), gridWidth - 1)
            let gridY = min(Int((wp.height - StandardOpeningSizes.typicalWindowSillHeight) / Self.densityGridCellSize), gridHeight - 1)
            if gridX >= 0 && gridY >= 0 {
                densityGrid[gridX][gridY] += 1
            }
        }

        // Find voids (low density rectangles)
        let voids = findVoidsInGrid(
            densityGrid: densityGrid,
            cellSize: Self.densityGridCellSize,
            minWidth: StandardOpeningSizes.minWindowWidth,
            maxWidth: StandardOpeningSizes.maxWindowWidth,
            minHeight: StandardOpeningSizes.minWindowHeight,
            maxHeight: StandardOpeningSizes.maxWindowHeight
        )

        // Determine max confidence based on wall density (ADR-1)
        let maxConfidence: AIConfidenceLevel
        if wallDensity >= Self.highDensityThreshold {
            maxConfidence = .high
        } else if wallDensity >= Self.lowDensityThreshold {
            maxConfidence = .medium
        } else {
            maxConfidence = .low
        }

        // Create windows from voids
        var windows: [AIDetectedWindow] = []

        for void in voids {
            // Adjust position back to wall coordinates
            let positionOnWall = void.startX
            let sillHeight = void.startY + StandardOpeningSizes.typicalWindowSillHeight
            let rawWidth = void.width
            let rawHeight = void.height

            // Validate signals (ADR-1)
            var signalCount = 0

            // Signal 1: Density void
            signalCount += 1

            // Signal 2: Height constraint (sill above countertop)
            if sillHeight >= StandardOpeningSizes.typicalWindowSillHeight {
                signalCount += 1
            }

            // Signal 3: Frame validation (check border density)
            if void.hasBorderDensity {
                signalCount += 1
            }

            // Determine confidence from signals
            var confidence: AIConfidenceLevel
            if signalCount >= 3 {
                confidence = .high
            } else if signalCount >= 2 {
                confidence = .medium
            } else {
                confidence = .low
            }

            // Cap confidence based on wall density
            if confidence > maxConfidence {
                confidence = maxConfidence
            }

            // Apply dimension snapping
            let (nearestWidth, widthDiff) = StandardOpeningSizes.nearestWindowWidth(to: rawWidth)
            let (nearestHeight, heightDiff) = StandardOpeningSizes.nearestWindowHeight(to: rawHeight)

            let snappedWidth = widthDiff <= StandardOpeningSizes.snapHighThreshold ? nearestWidth : rawWidth
            let snappedHeight = heightDiff <= StandardOpeningSizes.snapHighThreshold ? nearestHeight : rawHeight

            let isStandardSize = widthDiff <= StandardOpeningSizes.snapHighThreshold &&
                                 heightDiff <= StandardOpeningSizes.snapHighThreshold

            // Calculate upper cabinet placement (ADR-4)
            let windowTop = sillHeight + rawHeight
            let availableUpperCabinetHeight = ceilingHeight - windowTop - Self.upperCabinetMinClearance

            let upperCabinetRecommendation: String?
            if availableUpperCabinetHeight >= 30 {
                upperCabinetRecommendation = "Standard 30\" upper cabinets possible"
            } else if availableUpperCabinetHeight >= 18 {
                upperCabinetRecommendation = "18\" upper cabinets possible"
            } else {
                upperCabinetRecommendation = "No upper cabinets above window"
            }

            // Calculate distance from countertop
            let distanceFromCountertop: Float?
            if sillHeight >= StandardOpeningSizes.typicalWindowSillHeight &&
               sillHeight <= 54 {
                distanceFromCountertop = sillHeight - StandardOpeningSizes.typicalWindowSillHeight
            } else {
                distanceFromCountertop = nil
            }

            // Build notes
            var notes: [String] = []
            if !isStandardSize {
                notes.append("Non-standard size")
            }
            if confidence == .low {
                notes.append("Verify window dimensions")
            }
            if signalCount < 3 {
                notes.append("Detection based on \(signalCount) signal(s)")
            }

            // Create bounding box
            let wallDir2D = simd_normalize(wall.endPoint - wall.startPoint)
            let wallNormal2D = SIMD2<Float>(-wallDir2D.y, wallDir2D.x)
            let centerAlongWall = positionOnWall + rawWidth / 2
            let center2D = wall.startPoint + wallDir2D * centerAlongWall + wallNormal2D * 3 // 3" depth for window frame
            let centerY = sillHeight + rawHeight / 2

            let boundingBox = AIBoundingBox3D(
                center: SIMD3<Float>(center2D.x, centerY, center2D.y),
                size: SIMD3<Float>(snappedWidth, snappedHeight, 6.0)  // 6" depth for frame
            )

            let window = AIDetectedWindow(
                id: UUID(),
                wallId: wall.id,
                positionOnWallInches: positionOnWall,
                heightFromFloorInches: sillHeight,
                boundingBox: boundingBox,
                rawDimensions: SIMD3<Float>(rawWidth, rawHeight, 6.0),
                snappedDimensions: SIMD3<Float>(snappedWidth, snappedHeight, 6.0),
                confidence: confidence,
                isStandardSize: isStandardSize,
                notes: notes,
                sillHeightInches: sillHeight,
                distanceFromCountertopInches: distanceFromCountertop,
                hasFrame: void.hasBorderDensity,
                availableUpperCabinetHeight: availableUpperCabinetHeight > 0 ? availableUpperCabinetHeight : nil,
                upperCabinetRecommendation: upperCabinetRecommendation
            )

            windows.append(window)
        }

        return windows
    }

    // MARK: - Door Detection (Task 5)

    /// Detects doors using multi-signal detection (ADR-1).
    ///
    /// **Signals:**
    /// 1. Density void - rectangular low-density region
    /// 2. Floor contact - bottom edge within 2" of floor
    /// 3. Height profile - ~80" (standard) or >84" (full height)
    ///
    /// - Parameters:
    ///   - points: All points in the point cloud
    ///   - walls: Detected walls
    ///   - floorY: Y coordinate of the floor
    ///   - ceilingHeight: Ceiling height in inches
    ///   - wallDensities: Pre-calculated wall densities for confidence capping
    /// - Returns: Array of detected doors
    private func detectDoors(
        points: [SIMD3<Float>],
        walls: [AIWall],
        floorY: Float,
        ceilingHeight: Float,
        wallDensities: [UUID: Float]
    ) -> [AIDetectedDoor] {
        var doors: [AIDetectedDoor] = []

        for wall in walls {
            let wallDoors = detectDoorsOnWall(
                points: points,
                wall: wall,
                floorY: floorY,
                ceilingHeight: ceilingHeight,
                wallDensity: wallDensities[wall.id] ?? 0
            )
            doors.append(contentsOf: wallDoors)
        }

        return doors
    }

    /// Detects doors on a single wall.
    private func detectDoorsOnWall(
        points: [SIMD3<Float>],
        wall: AIWall,
        floorY: Float,
        ceilingHeight: Float,
        wallDensity: Float
    ) -> [AIDetectedDoor] {
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)
        let wallLength = Float(wall.lengthInches)

        // Project points to wall coordinates (full height for doors)
        var wallPoints: [(alongWall: Float, height: Float)] = []

        for point in points {
            let heightAboveFloor = point.y - floorY
            guard heightAboveFloor >= 0 && heightAboveFloor <= ceilingHeight else { continue }

            let point2D = SIMD2<Float>(point.x, point.z)
            let toPoint = point2D - wall.startPoint

            let alongWall = simd_dot(toPoint, wallDir)
            let fromWall = abs(simd_dot(toPoint, wallNormal))

            guard alongWall >= 0 && alongWall <= wallLength &&
                  fromWall <= Self.wallProximityThreshold else { continue }

            wallPoints.append((alongWall, heightAboveFloor))
        }

        guard wallPoints.count >= Self.minWallPoints else { return [] }

        // Create density grid (from floor to ceiling)
        let gridWidth = Int(wallLength / Self.densityGridCellSize) + 1
        let gridHeight = Int(ceilingHeight / Self.densityGridCellSize) + 1

        var densityGrid = Array(repeating: Array(repeating: 0, count: gridHeight), count: gridWidth)

        for wp in wallPoints {
            let gridX = min(Int(wp.alongWall / Self.densityGridCellSize), gridWidth - 1)
            let gridY = min(Int(wp.height / Self.densityGridCellSize), gridHeight - 1)
            if gridX >= 0 && gridY >= 0 {
                densityGrid[gridX][gridY] += 1
            }
        }

        // Find door-shaped voids (starting near floor)
        let voids = findDoorVoidsInGrid(
            densityGrid: densityGrid,
            cellSize: Self.densityGridCellSize,
            minWidth: StandardOpeningSizes.minDoorWidth,
            maxWidth: StandardOpeningSizes.maxDoorWidth
        )

        // Determine max confidence based on wall density (ADR-1)
        let maxConfidence: AIConfidenceLevel
        if wallDensity >= Self.highDensityThreshold {
            maxConfidence = .high
        } else if wallDensity >= Self.lowDensityThreshold {
            maxConfidence = .medium
        } else {
            maxConfidence = .low
        }

        // Create doors from voids
        var doors: [AIDetectedDoor] = []

        for void in voids {
            let positionOnWall = void.startX
            let bottomHeight = void.startY
            let rawWidth = void.width
            let rawHeight = void.height

            // Validate signals (ADR-1)
            var signalCount = 0

            // Signal 1: Density void
            signalCount += 1

            // Signal 2: Floor contact (bottom within 2" of floor)
            if bottomHeight <= StandardOpeningSizes.doorFloorProximity {
                signalCount += 1
            }

            // Signal 3: Height profile (~80" standard or >84" full height)
            let isStandardHeight = abs(rawHeight - StandardOpeningSizes.standardDoorHeight) <= 4
            let isFullHeight = rawHeight >= StandardOpeningSizes.fullHeightDoorMin
            if isStandardHeight || isFullHeight {
                signalCount += 1
            }

            // Determine confidence from signals
            var confidence: AIConfidenceLevel
            if signalCount >= 3 {
                confidence = .high
            } else if signalCount >= 2 {
                confidence = .medium
            } else {
                confidence = .low
            }

            // Cap confidence based on wall density
            if confidence > maxConfidence {
                confidence = maxConfidence
            }

            // Determine door type
            let doorType: AIOpeningType
            if isFullHeight {
                // Could be sliding or french if wide enough
                if rawWidth >= 60 {
                    doorType = .frenchDoor
                } else if rawWidth >= 48 {
                    doorType = .slidingDoor
                } else {
                    doorType = .door
                }
            } else {
                doorType = .door
            }

            // Apply dimension snapping
            let (nearestWidth, widthDiff) = StandardOpeningSizes.nearestDoorWidth(to: rawWidth)
            let snappedWidth = widthDiff <= StandardOpeningSizes.snapHighThreshold ? nearestWidth : rawWidth

            let snappedHeight: Float
            if isStandardHeight {
                snappedHeight = StandardOpeningSizes.standardDoorHeight
            } else {
                snappedHeight = rawHeight
            }

            let isStandardSize = widthDiff <= StandardOpeningSizes.snapHighThreshold && isStandardHeight

            // Build notes
            var notes: [String] = []
            if !isStandardSize {
                notes.append("Non-standard size")
            }
            if confidence == .low {
                notes.append("Verify door dimensions")
            }
            if isFullHeight {
                notes.append("Full height door")
            }
            if signalCount < 3 {
                notes.append("Detection based on \(signalCount) signal(s)")
            }

            // Create bounding box
            let wallDir2D = simd_normalize(wall.endPoint - wall.startPoint)
            let wallNormal2D = SIMD2<Float>(-wallDir2D.y, wallDir2D.x)
            let centerAlongWall = positionOnWall + rawWidth / 2
            let center2D = wall.startPoint + wallDir2D * centerAlongWall + wallNormal2D * 3
            let centerY = bottomHeight + rawHeight / 2

            let boundingBox = AIBoundingBox3D(
                center: SIMD3<Float>(center2D.x, centerY, center2D.y),
                size: SIMD3<Float>(snappedWidth, snappedHeight, 6.0)
            )

            let door = AIDetectedDoor(
                id: UUID(),
                type: doorType,
                wallId: wall.id,
                positionOnWallInches: positionOnWall,
                heightFromFloorInches: bottomHeight,
                boundingBox: boundingBox,
                rawDimensions: SIMD3<Float>(rawWidth, rawHeight, 6.0),
                snappedDimensions: SIMD3<Float>(snappedWidth, snappedHeight, 6.0),
                confidence: confidence,
                isStandardSize: isStandardSize,
                notes: notes,
                swingDirection: .unknown,  // Best-effort, default to unknown
                isFullHeight: isFullHeight,
                clearanceToAdjacentCabinet: nil  // Calculated later
            )

            doors.append(door)
        }

        return doors
    }

    // MARK: - Void Detection Helpers

    /// Result of void detection in density grid.
    private struct DetectedVoid {
        let startX: Float
        let startY: Float
        let width: Float
        let height: Float
        let hasBorderDensity: Bool
    }

    /// Finds rectangular voids (low density regions) in density grid.
    private func findVoidsInGrid(
        densityGrid: [[Int]],
        cellSize: Float,
        minWidth: Float,
        maxWidth: Float,
        minHeight: Float,
        maxHeight: Float
    ) -> [DetectedVoid] {
        let gridWidth = densityGrid.count
        guard gridWidth > 0 else { return [] }
        let gridHeight = densityGrid[0].count

        // Calculate average density
        var totalPoints = 0
        var cellCount = 0
        for col in densityGrid {
            for cell in col {
                totalPoints += cell
                cellCount += 1
            }
        }
        let avgDensity = cellCount > 0 ? Float(totalPoints) / Float(cellCount) : 0
        let voidThreshold = Int(avgDensity * Self.voidDensityRatio)

        var voids: [DetectedVoid] = []

        // Simple sweep to find contiguous low-density regions
        let minGridWidth = Int(minWidth / cellSize)
        let maxGridWidth = Int(maxWidth / cellSize)
        let minGridHeight = Int(minHeight / cellSize)
        let maxGridHeight = Int(maxHeight / cellSize)

        // Check each potential starting position
        for startX in 0..<(gridWidth - minGridWidth) {
            for startY in 0..<(gridHeight - minGridHeight) {
                // Check if this is a void starting point
                guard densityGrid[startX][startY] <= voidThreshold else { continue }

                // Try to extend the void
                var voidWidth = 1
                var voidHeight = 1

                // Extend width
                while startX + voidWidth < gridWidth && voidWidth < maxGridWidth {
                    var allLow = true
                    for y in startY..<min(startY + minGridHeight, gridHeight) {
                        if densityGrid[startX + voidWidth][y] > voidThreshold {
                            allLow = false
                            break
                        }
                    }
                    if allLow {
                        voidWidth += 1
                    } else {
                        break
                    }
                }

                // Extend height
                while startY + voidHeight < gridHeight && voidHeight < maxGridHeight {
                    var allLow = true
                    for x in startX..<min(startX + voidWidth, gridWidth) {
                        if densityGrid[x][startY + voidHeight] > voidThreshold {
                            allLow = false
                            break
                        }
                    }
                    if allLow {
                        voidHeight += 1
                    } else {
                        break
                    }
                }

                // Check if meets minimum size
                guard voidWidth >= minGridWidth && voidHeight >= minGridHeight else { continue }

                // Check for border density (frame validation)
                let hasBorder = checkBorderDensity(
                    grid: densityGrid,
                    startX: startX,
                    startY: startY,
                    width: voidWidth,
                    height: voidHeight,
                    avgDensity: avgDensity
                )

                let void = DetectedVoid(
                    startX: Float(startX) * cellSize,
                    startY: Float(startY) * cellSize,
                    width: Float(voidWidth) * cellSize,
                    height: Float(voidHeight) * cellSize,
                    hasBorderDensity: hasBorder
                )
                voids.append(void)
            }
        }

        // Remove overlapping voids, keeping larger ones
        return removeOverlappingVoids(voids)
    }

    /// Finds door-shaped voids starting from floor level.
    private func findDoorVoidsInGrid(
        densityGrid: [[Int]],
        cellSize: Float,
        minWidth: Float,
        maxWidth: Float
    ) -> [DetectedVoid] {
        let gridWidth = densityGrid.count
        guard gridWidth > 0 else { return [] }
        let gridHeight = densityGrid[0].count

        // Calculate average density
        var totalPoints = 0
        var cellCount = 0
        for col in densityGrid {
            for cell in col {
                totalPoints += cell
                cellCount += 1
            }
        }
        let avgDensity = cellCount > 0 ? Float(totalPoints) / Float(cellCount) : 0
        let voidThreshold = Int(avgDensity * Self.voidDensityRatio)

        var voids: [DetectedVoid] = []

        let minGridWidth = Int(minWidth / cellSize)
        let maxGridWidth = Int(maxWidth / cellSize)
        let minDoorHeight = Int(StandardOpeningSizes.standardDoorHeight * 0.9 / cellSize) // 90% of standard
        let floorProximityGrid = Int(StandardOpeningSizes.doorFloorProximity / cellSize) + 1

        // Only check starting positions near floor
        for startX in 0..<(gridWidth - minGridWidth) {
            for startY in 0..<floorProximityGrid {
                guard densityGrid[startX][startY] <= voidThreshold else { continue }

                // Extend width
                var voidWidth = 1
                while startX + voidWidth < gridWidth && voidWidth < maxGridWidth {
                    var allLow = true
                    for y in startY..<min(startY + minDoorHeight, gridHeight) {
                        if densityGrid[startX + voidWidth][y] > voidThreshold {
                            allLow = false
                            break
                        }
                    }
                    if allLow {
                        voidWidth += 1
                    } else {
                        break
                    }
                }

                guard voidWidth >= minGridWidth else { continue }

                // Extend height from floor
                var voidHeight = 1
                while startY + voidHeight < gridHeight {
                    var allLow = true
                    for x in startX..<min(startX + voidWidth, gridWidth) {
                        if densityGrid[x][startY + voidHeight] > voidThreshold {
                            allLow = false
                            break
                        }
                    }
                    if allLow {
                        voidHeight += 1
                    } else {
                        break
                    }
                }

                guard voidHeight >= minDoorHeight else { continue }

                let hasBorder = checkBorderDensity(
                    grid: densityGrid,
                    startX: startX,
                    startY: startY,
                    width: voidWidth,
                    height: voidHeight,
                    avgDensity: avgDensity
                )

                let void = DetectedVoid(
                    startX: Float(startX) * cellSize,
                    startY: Float(startY) * cellSize,
                    width: Float(voidWidth) * cellSize,
                    height: Float(voidHeight) * cellSize,
                    hasBorderDensity: hasBorder
                )
                voids.append(void)
            }
        }

        return removeOverlappingVoids(voids)
    }

    /// Checks if void has higher density border (frame validation).
    private func checkBorderDensity(
        grid: [[Int]],
        startX: Int,
        startY: Int,
        width: Int,
        height: Int,
        avgDensity: Float
    ) -> Bool {
        let gridWidth = grid.count
        let gridHeight = grid[0].count
        let frameThreshold = Int(avgDensity * Self.frameDensityRatio)

        var borderPoints = 0
        var borderCells = 0

        // Check left border
        if startX > 0 {
            for y in startY..<min(startY + height, gridHeight) {
                borderPoints += grid[startX - 1][y]
                borderCells += 1
            }
        }

        // Check right border
        if startX + width < gridWidth {
            for y in startY..<min(startY + height, gridHeight) {
                borderPoints += grid[startX + width][y]
                borderCells += 1
            }
        }

        // Check top border
        if startY + height < gridHeight {
            for x in startX..<min(startX + width, gridWidth) {
                borderPoints += grid[x][startY + height]
                borderCells += 1
            }
        }

        // Check bottom border (for windows)
        if startY > 0 {
            for x in startX..<min(startX + width, gridWidth) {
                borderPoints += grid[x][startY - 1]
                borderCells += 1
            }
        }

        let avgBorderDensity = borderCells > 0 ? borderPoints / borderCells : 0
        return avgBorderDensity >= frameThreshold
    }

    /// Removes overlapping voids, keeping larger ones.
    private func removeOverlappingVoids(_ voids: [DetectedVoid]) -> [DetectedVoid] {
        var result: [DetectedVoid] = []

        let sortedVoids = voids.sorted { ($0.width * $0.height) > ($1.width * $1.height) }

        for void in sortedVoids {
            var overlaps = false
            for existing in result {
                let overlapX = void.startX < existing.startX + existing.width &&
                              void.startX + void.width > existing.startX
                let overlapY = void.startY < existing.startY + existing.height &&
                              void.startY + void.height > existing.startY
                if overlapX && overlapY {
                    overlaps = true
                    break
                }
            }
            if !overlaps {
                result.append(void)
            }
        }

        return result
    }

    // MARK: - Cabinet Clearance Calculation (Task 7)

    /// Calculates clearance between openings and adjacent cabinets.
    ///
    /// - Parameters:
    ///   - openings: All detected openings (id, wallId, position, width)
    ///   - cabinets: All detected cabinets
    ///   - walls: All walls
    /// - Returns: Array of opening clearances
    private func calculateCabinetClearances(
        openings: [(id: UUID, wallId: UUID, positionOnWall: Float, width: Float)],
        cabinets: [AIDetectedCabinet],
        walls: [AIWall]
    ) -> [OpeningClearance] {
        var clearances: [OpeningClearance] = []

        for opening in openings {
            // Find cabinets on the same wall
            let samewallCabinets = cabinets.filter { $0.wallId == opening.wallId }

            guard !samewallCabinets.isEmpty else {
                // No cabinets on this wall
                clearances.append(OpeningClearance(
                    openingId: opening.id,
                    nearestCabinetId: nil,
                    clearanceInches: .infinity,
                    side: .both,
                    requiresFiller: false
                ))
                continue
            }

            let openingStart = opening.positionOnWall
            let openingEnd = opening.positionOnWall + opening.width

            var minClearanceLeft: Float = .infinity
            var minClearanceRight: Float = .infinity
            var nearestCabinetId: UUID?

            for cabinet in samewallCabinets {
                let cabinetStart = cabinet.positionOnWallInches
                let cabinetEnd = cabinet.positionOnWallInches + cabinet.widthInches

                // Clearance on left side of opening
                if cabinetEnd <= openingStart {
                    let clearance = openingStart - cabinetEnd
                    if clearance < minClearanceLeft {
                        minClearanceLeft = clearance
                        nearestCabinetId = cabinet.id
                    }
                }

                // Clearance on right side of opening
                if cabinetStart >= openingEnd {
                    let clearance = cabinetStart - openingEnd
                    if clearance < minClearanceRight {
                        minClearanceRight = clearance
                        nearestCabinetId = cabinet.id
                    }
                }
            }

            // Determine which side and if filler is needed
            let minClearance = min(minClearanceLeft, minClearanceRight)
            let side: ClearanceSide
            if minClearanceLeft == minClearanceRight {
                side = .both
            } else if minClearanceLeft < minClearanceRight {
                side = .left
            } else {
                side = .right
            }

            let requiresFiller = minClearance < StandardOpeningSizes.fillerClearanceThreshold

            clearances.append(OpeningClearance(
                openingId: opening.id,
                nearestCabinetId: nearestCabinetId,
                clearanceInches: minClearance.isInfinite ? StandardOpeningSizes.noAdjacentCabinetClearance : minClearance,
                side: side,
                requiresFiller: requiresFiller
            ))
        }

        return clearances
    }
}
