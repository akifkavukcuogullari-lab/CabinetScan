//
//  CabinetDetector.swift
//  cabinetscan
//
//  Created for Story 4.2: Cabinet Detection (Base, Upper, Tall)
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Cabinet Detector Protocol

/// Protocol for cabinet detection implementations.
/// Enables testing with mock detectors.
protocol CabinetDetectorProtocol {
    /// Detects cabinets from room structure and point cloud.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure from RoomDetector (walls, floor plane)
    ///   - pointCloud: Calibrated point cloud in inches
    /// - Returns: Cabinet detection result with all detected cabinets
    /// - Throws: `CabinetDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) async throws -> CabinetDetectionResult
}

// MARK: - Cabinet Detection Phase

/// Phases of cabinet detection for progress tracking.
enum CabinetDetectionPhase: String {
    case idle = "Idle"
    case baseCabinetDetection = "Detecting Base Cabinets"
    case upperCabinetDetection = "Detecting Upper Cabinets"
    case tallCabinetDetection = "Detecting Tall Cabinets"
    case dimensionExtraction = "Extracting Dimensions"
    case snapping = "Applying Standard Sizes"
    case validation = "Validating Cabinet Runs"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Cabinet Detector

/// Detects kitchen cabinets (base, upper, tall) from calibrated 3D point cloud.
///
/// **Algorithm Pipeline:**
/// 1. Base Cabinet Detection - Find surfaces at countertop height (~36")
/// 2. Upper Cabinet Detection - Find cabinets at 54"-96" height
/// 3. Tall Cabinet Detection - Find floor-to-ceiling cabinets (>72")
/// 4. Dimension Extraction - Measure width, height, depth
/// 5. Standard Size Snapping - Snap to standard sizes with tolerance
/// 6. Cabinet Run Validation - Validate coverage against wall lengths
///
/// **Performance Budget:** <1000ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = CabinetDetector()
/// let result = try await detector.detect(roomStructure: room, pointCloud: cloud)
/// ```
@MainActor
final class CabinetDetector: ObservableObject, CabinetDetectorProtocol {

    // MARK: - Constants

    /// Countertop height range (inches) for base cabinet detection
    private static let countertopHeightMin: Float = 34.0
    private static let countertopHeightMax: Float = 38.0
    private static let countertopHeightNominal: Float = 36.0

    /// Upper cabinet bottom height from floor (inches)
    private static let upperCabinetBottomMin: Float = 52.0
    private static let upperCabinetBottomMax: Float = 56.0
    private static let upperCabinetBottomNominal: Float = 54.0

    /// Upper cabinet top height from floor (inches)
    private static let upperCabinetTopMin: Float = 82.0
    private static let upperCabinetTopMax: Float = 98.0

    /// Tall cabinet minimum height (inches)
    private static let tallCabinetMinHeight: Float = 72.0

    /// Base cabinet standard depth (inches)
    private static let baseCabinetDepth: Float = 24.0
    private static let baseCabinetDepthTolerance: Float = 3.0

    /// Upper cabinet standard depth (inches)
    private static let upperCabinetDepth: Float = 12.0
    private static let upperCabinetDepthTolerance: Float = 3.0

    /// Minimum cabinet width (inches)
    private static let minCabinetWidth: Float = 9.0

    /// Maximum cabinet width (inches)
    private static let maxCabinetWidth: Float = 48.0

    /// Distance from wall to consider as "against wall" (inches)
    private static let wallProximityThreshold: Float = 6.0

    /// Snapping thresholds per Architecture 7.3
    private static let snapHighThreshold: Float = 1.5    // Snap to standard, HIGH confidence
    private static let snapMediumThreshold: Float = 3.0  // Keep raw, MEDIUM confidence

    /// Minimum points required for cabinet detection
    private static let minPointsForCabinet: Int = 50

    /// Vertical slice thickness for horizontal surface detection (inches)
    private static let sliceThickness: Float = 2.0

    /// Gap threshold for detecting cabinet edges (inches)
    /// Gaps larger than this indicate a boundary between cabinets
    private static let edgeGapThreshold: Float = 2.0

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: CabinetDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "CabinetDetector")

    // MARK: - Initialization

    init() {
        #if DEBUG
        logger.info("CabinetDetector initialized")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects all cabinets from room structure and point cloud.
    ///
    /// - Parameters:
    ///   - roomStructure: Room structure containing walls and floor plane
    ///   - pointCloud: Calibrated point cloud in inches
    /// - Returns: Cabinet detection result with all detected cabinets
    /// - Throws: `CabinetDetectionError` if detection fails
    func detect(
        roomStructure: AIRoomStructure,
        pointCloud: AIPointCloud
    ) async throws -> CabinetDetectionResult {
        logger.info("Starting cabinet detection with \(pointCloud.count) points, \(roomStructure.walls.count) walls")

        guard !pointCloud.isEmpty else {
            throw CabinetDetectionError.noPointCloud
        }

        guard !roomStructure.walls.isEmpty else {
            throw CabinetDetectionError.noWallsDetected
        }

        isProcessing = true
        progress = 0.0
        currentPhase = .baseCabinetDetection

        let startTime = CFAbsoluteTimeGetCurrent()
        var warnings: [String] = []
        var allCabinets: [AIDetectedCabinet] = []

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Get points from point cloud
        var mutablePointCloud = pointCloud
        let points = mutablePointCloud.getPoints()
        let floorY: Float = -roomStructure.floorPlane.distance

        // Task 2: Detect base cabinets
        try Task.checkCancellation()
        currentPhase = .baseCabinetDetection
        let baseCabinets = detectBaseCabinets(
            points: points,
            walls: roomStructure.walls,
            floorY: floorY
        )
        allCabinets.append(contentsOf: baseCabinets)
        progress = 0.30
        logger.info("Detected \(baseCabinets.count) base cabinets")

        // Task 3: Detect upper cabinets
        try Task.checkCancellation()
        currentPhase = .upperCabinetDetection
        let upperCabinets = detectUpperCabinets(
            points: points,
            walls: roomStructure.walls,
            floorY: floorY
        )
        allCabinets.append(contentsOf: upperCabinets)
        progress = 0.55
        logger.info("Detected \(upperCabinets.count) upper cabinets")

        // Task 4: Detect tall cabinets
        try Task.checkCancellation()
        currentPhase = .tallCabinetDetection
        let tallCabinets = detectTallCabinets(
            points: points,
            walls: roomStructure.walls,
            floorY: floorY,
            ceilingHeight: Float(roomStructure.ceilingHeightInches)
        )
        allCabinets.append(contentsOf: tallCabinets)
        progress = 0.75
        logger.info("Detected \(tallCabinets.count) tall cabinets")

        // Task 8: Validate cabinet runs
        try Task.checkCancellation()
        currentPhase = .validation
        let wallValidation = validateCabinetRuns(
            cabinets: allCabinets,
            walls: roomStructure.walls
        )
        progress = 0.90

        // Add warnings for validation issues
        for validation in wallValidation {
            if !validation.isValid {
                warnings.append("Wall coverage discrepancy: \(String(format: "%.1f", validation.coverageDiscrepancyInches))\" on wall")
            }
            for gap in validation.baseGaps where gap.widthInches > 6 {
                warnings.append("Gap of \(String(format: "%.1f", gap.widthInches))\" detected between base cabinets")
            }
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        logger.info("Cabinet detection complete in \(processingTimeMs)ms: \(allCabinets.count) cabinets (\(baseCabinets.count) base, \(upperCabinets.count) upper, \(tallCabinets.count) tall)")

        return CabinetDetectionResult(
            cabinets: allCabinets,
            wallCoverageValidation: wallValidation,
            processingTimeMs: processingTimeMs,
            warnings: warnings
        )
    }

    // MARK: - Task 2: Base Cabinet Detection (AC1, AC5, AC6)

    /// Detects base cabinets by finding surfaces at countertop height.
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - walls: Detected walls from room structure
    ///   - floorY: Y coordinate of the floor plane
    /// - Returns: Array of detected base cabinets
    private func detectBaseCabinets(
        points: [SIMD3<Float>],
        walls: [AIWall],
        floorY: Float
    ) -> [AIDetectedCabinet] {
        var cabinets: [AIDetectedCabinet] = []

        for wall in walls {
            // Find points near this wall at countertop height
            let wallCabinets = detectCabinetsAlongWall(
                points: points,
                wall: wall,
                floorY: floorY,
                heightRange: (Self.countertopHeightMin, Self.countertopHeightMax),
                expectedDepth: Self.baseCabinetDepth,
                depthTolerance: Self.baseCabinetDepthTolerance,
                cabinetType: .base
            )
            cabinets.append(contentsOf: wallCabinets)
        }

        return cabinets
    }

    // MARK: - Task 3: Upper Cabinet Detection (AC2, AC5, AC6)

    /// Detects upper cabinets mounted on walls above countertop.
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - walls: Detected walls from room structure
    ///   - floorY: Y coordinate of the floor plane
    /// - Returns: Array of detected upper cabinets
    private func detectUpperCabinets(
        points: [SIMD3<Float>],
        walls: [AIWall],
        floorY: Float
    ) -> [AIDetectedCabinet] {
        var cabinets: [AIDetectedCabinet] = []

        for wall in walls {
            // Find points near this wall at upper cabinet height
            let wallCabinets = detectCabinetsAlongWall(
                points: points,
                wall: wall,
                floorY: floorY,
                heightRange: (Self.upperCabinetBottomMin, Self.upperCabinetTopMax),
                expectedDepth: Self.upperCabinetDepth,
                depthTolerance: Self.upperCabinetDepthTolerance,
                cabinetType: .upper
            )
            cabinets.append(contentsOf: wallCabinets)
        }

        return cabinets
    }

    // MARK: - Task 4: Tall Cabinet Detection (AC3, AC5)

    /// Detects tall/pantry cabinets that span floor to near-ceiling.
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - walls: Detected walls from room structure
    ///   - floorY: Y coordinate of the floor plane
    ///   - ceilingHeight: Ceiling height in inches
    /// - Returns: Array of detected tall cabinets
    private func detectTallCabinets(
        points: [SIMD3<Float>],
        walls: [AIWall],
        floorY: Float,
        ceilingHeight: Float
    ) -> [AIDetectedCabinet] {
        var cabinets: [AIDetectedCabinet] = []

        for wall in walls {
            // Find tall cabinets - span from near floor to >72" height
            let wallCabinets = detectCabinetsAlongWall(
                points: points,
                wall: wall,
                floorY: floorY,
                heightRange: (0, ceilingHeight),
                expectedDepth: Self.baseCabinetDepth,  // Tall cabinets are same depth as base
                depthTolerance: Self.baseCabinetDepthTolerance,
                cabinetType: .tall,
                minHeight: Self.tallCabinetMinHeight
            )
            cabinets.append(contentsOf: wallCabinets)
        }

        return cabinets
    }

    // MARK: - Cabinet Detection Along Wall

    /// Detects cabinets along a specific wall within height and depth constraints.
    ///
    /// - Parameters:
    ///   - points: All points in the calibrated point cloud
    ///   - wall: The wall to detect cabinets along
    ///   - floorY: Y coordinate of the floor plane
    ///   - heightRange: Expected height range (min, max) from floor
    ///   - expectedDepth: Expected cabinet depth
    ///   - depthTolerance: Tolerance for depth matching
    ///   - cabinetType: Type of cabinet being detected
    ///   - minHeight: Minimum cabinet height (for tall cabinets)
    /// - Returns: Array of detected cabinets along this wall
    private func detectCabinetsAlongWall(
        points: [SIMD3<Float>],
        wall: AIWall,
        floorY: Float,
        heightRange: (min: Float, max: Float),
        expectedDepth: Float,
        depthTolerance: Float,
        cabinetType: AICabinetType,
        minHeight: Float? = nil
    ) -> [AIDetectedCabinet] {
        // Wall direction vector (normalized)
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallLength = Float(wall.lengthInches)

        // Wall normal (perpendicular, pointing into room)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

        // Filter points near this wall and within height range
        var wallPoints: [(point: SIMD3<Float>, alongWall: Float, fromWall: Float)] = []

        for point in points {
            let heightAboveFloor = point.y - floorY

            // Check height range
            guard heightAboveFloor >= heightRange.min && heightAboveFloor <= heightRange.max else {
                continue
            }

            // Project point to wall coordinates
            let point2D = SIMD2<Float>(point.x, point.z)
            let toPoint = point2D - wall.startPoint

            // Distance along wall
            let alongWall = simd_dot(toPoint, wallDir)

            // Distance from wall (perpendicular)
            let fromWall = simd_dot(toPoint, wallNormal)

            // Check if point is within expected depth range from wall
            guard fromWall >= 0 && fromWall <= expectedDepth + depthTolerance else {
                continue
            }

            // Check if point is within wall bounds (with small margin)
            guard alongWall >= -Self.wallProximityThreshold &&
                  alongWall <= wallLength + Self.wallProximityThreshold else {
                continue
            }

            wallPoints.append((point, alongWall, fromWall))
        }

        guard wallPoints.count >= Self.minPointsForCabinet else {
            return []
        }

        // Segment points into individual cabinets
        return segmentCabinets(
            wallPoints: wallPoints,
            wall: wall,
            floorY: floorY,
            cabinetType: cabinetType,
            minHeight: minHeight
        )
    }

    // MARK: - Cabinet Segmentation

    /// Segments points along a wall into individual cabinets.
    ///
    /// Uses edge detection to find cabinet boundaries, falls back to
    /// standard width estimation for merged cabinets (AC6).
    ///
    /// - Parameters:
    ///   - wallPoints: Points with their wall-relative positions
    ///   - wall: The wall these cabinets are on
    ///   - floorY: Y coordinate of the floor plane
    ///   - cabinetType: Type of cabinet being detected
    ///   - minHeight: Minimum cabinet height (for tall cabinets)
    /// - Returns: Array of segmented cabinets
    private func segmentCabinets(
        wallPoints: [(point: SIMD3<Float>, alongWall: Float, fromWall: Float)],
        wall: AIWall,
        floorY: Float,
        cabinetType: AICabinetType,
        minHeight: Float?
    ) -> [AIDetectedCabinet] {
        // Sort points by position along wall
        let sortedPoints = wallPoints.sorted { $0.alongWall < $1.alongWall }

        guard let firstPoint = sortedPoints.first,
              let lastPoint = sortedPoints.last else {
            return []
        }

        let totalWidth = lastPoint.alongWall - firstPoint.alongWall

        // Skip if total width is too small
        guard totalWidth >= Self.minCabinetWidth else {
            return []
        }

        // Calculate raw dimensions
        let heights = wallPoints.map { $0.point.y - floorY }
        let depths = wallPoints.map { $0.fromWall }

        let minY = heights.min() ?? 0
        let maxY = heights.max() ?? 0
        let rawHeight = maxY - minY

        // For tall cabinets, verify minimum height
        if let minH = minHeight, rawHeight < minH {
            return []
        }

        // For upper cabinets, use the height range from detected points
        let actualHeight: Float
        if cabinetType == .upper {
            actualHeight = rawHeight
        } else if cabinetType == .tall {
            actualHeight = rawHeight
        } else {
            // Base cabinet - use standard height
            actualHeight = StandardCabinetSizes.baseHeight
        }

        let rawDepth = (depths.max() ?? 0) - (depths.min() ?? 0)
        let avgDepth = depths.reduce(0, +) / Float(depths.count)

        // Try to detect cabinet edges using density gaps
        let edges = detectCabinetEdges(sortedPoints: sortedPoints, totalWidth: totalWidth)

        var cabinets: [AIDetectedCabinet] = []

        if edges.count >= 2 {
            // Found clear edges - create cabinets between edges
            for i in 0..<(edges.count - 1) {
                let startPos = edges[i]
                let endPos = edges[i + 1]
                let width = endPos - startPos

                guard width >= Self.minCabinetWidth && width <= Self.maxCabinetWidth else {
                    continue
                }

                let cabinet = createCabinet(
                    wall: wall,
                    positionOnWall: startPos,
                    rawWidth: width,
                    rawHeight: actualHeight,
                    rawDepth: avgDepth,
                    cabinetType: cabinetType,
                    isMerged: false
                )
                cabinets.append(cabinet)
            }
        } else {
            // No clear edges - estimate using standard widths (AC6)
            let estimatedCabinets = estimateCabinetsFromStandardWidths(
                startPos: firstPoint.alongWall,
                totalWidth: totalWidth,
                wall: wall,
                rawHeight: actualHeight,
                rawDepth: avgDepth,
                cabinetType: cabinetType
            )
            cabinets.append(contentsOf: estimatedCabinets)
        }

        return cabinets
    }

    // MARK: - Edge Detection

    /// Detects cabinet edges by finding gaps in point density.
    ///
    /// - Parameters:
    ///   - sortedPoints: Points sorted by position along wall
    ///   - totalWidth: Total width of cabinet run
    /// - Returns: Array of edge positions along wall
    private func detectCabinetEdges(
        sortedPoints: [(point: SIMD3<Float>, alongWall: Float, fromWall: Float)],
        totalWidth: Float
    ) -> [Float] {
        guard sortedPoints.count >= 2 else { return [] }

        var edges: [Float] = [sortedPoints.first!.alongWall]

        // Look for gaps in point distribution using class constant
        for i in 1..<sortedPoints.count {
            let gap = sortedPoints[i].alongWall - sortedPoints[i - 1].alongWall
            if gap > Self.edgeGapThreshold {
                // Found a gap - this is likely a cabinet edge
                edges.append(sortedPoints[i - 1].alongWall)
                edges.append(sortedPoints[i].alongWall)
            }
        }

        edges.append(sortedPoints.last!.alongWall)

        // Remove duplicates and sort
        let uniqueEdges = Array(Set(edges)).sorted()

        return uniqueEdges
    }

    // MARK: - Standard Width Estimation (AC6)

    /// Estimates cabinet boundaries using standard widths when edges are unclear.
    ///
    /// - Parameters:
    ///   - startPos: Starting position along wall
    ///   - totalWidth: Total width to fill
    ///   - wall: The wall these cabinets are on
    ///   - rawHeight: Raw measured height
    ///   - rawDepth: Raw measured depth
    ///   - cabinetType: Type of cabinet
    /// - Returns: Array of estimated cabinets
    private func estimateCabinetsFromStandardWidths(
        startPos: Float,
        totalWidth: Float,
        wall: AIWall,
        rawHeight: Float,
        rawDepth: Float,
        cabinetType: AICabinetType
    ) -> [AIDetectedCabinet] {
        var cabinets: [AIDetectedCabinet] = []
        var currentPos = startPos
        var remainingWidth = totalWidth

        // Try to fit standard width cabinets
        while remainingWidth >= Self.minCabinetWidth {
            // Find best standard width that fits
            let (standardWidth, _) = StandardCabinetSizes.nearestWidth(to: remainingWidth)

            let cabinetWidth: Float
            if standardWidth <= remainingWidth {
                cabinetWidth = standardWidth
            } else {
                // Use largest standard width that fits
                let fittingWidths = StandardCabinetSizes.widths.filter { $0 <= remainingWidth }
                cabinetWidth = fittingWidths.max() ?? remainingWidth
            }

            let cabinet = createCabinet(
                wall: wall,
                positionOnWall: currentPos,
                rawWidth: cabinetWidth,
                rawHeight: rawHeight,
                rawDepth: rawDepth,
                cabinetType: cabinetType,
                isMerged: true  // Mark as merged/estimated
            )
            cabinets.append(cabinet)

            currentPos += cabinetWidth
            remainingWidth -= cabinetWidth
        }

        return cabinets
    }

    // MARK: - Task 5 & 6: Create Cabinet with Dimension Extraction and Snapping

    /// Creates a detected cabinet with dimension snapping and confidence scoring.
    ///
    /// - Parameters:
    ///   - wall: The wall this cabinet is attached to
    ///   - positionOnWall: Position along wall from start
    ///   - rawWidth: Raw measured width
    ///   - rawHeight: Raw measured height
    ///   - rawDepth: Raw measured depth
    ///   - cabinetType: Type of cabinet
    ///   - isMerged: Whether this cabinet was estimated from merged edges
    /// - Returns: A fully configured AIDetectedCabinet
    private func createCabinet(
        wall: AIWall,
        positionOnWall: Float,
        rawWidth: Float,
        rawHeight: Float,
        rawDepth: Float,
        cabinetType: AICabinetType,
        isMerged: Bool
    ) -> AIDetectedCabinet {
        // Validate dimensions are positive (guard against bad point cloud data)
        let validatedWidth = max(rawWidth, Self.minCabinetWidth)
        let validatedHeight = max(rawHeight, 1.0)  // Minimum 1" height
        let validatedDepth = max(rawDepth, 1.0)    // Minimum 1" depth

        let rawDimensions = SIMD3<Float>(validatedWidth, validatedHeight, validatedDepth)

        // Task 6: Apply standard size snapping
        let snappingResult = applyStandardSizeSnapping(
            rawDimensions: rawDimensions,
            cabinetType: cabinetType
        )

        // Task 7: Calculate confidence
        let confidence = calculateConfidence(
            rawDimensions: rawDimensions,
            snappedDimensions: snappingResult.snapped,
            isStandardSize: snappingResult.isStandard,
            isMerged: isMerged
        )

        // Build notes
        var notes: [String] = []
        if !snappingResult.isStandard {
            notes.append("Non-standard size")
        }
        if isMerged {
            notes.append("Estimated from merged cabinets")
        }
        if confidence == .low {
            notes.append("Verify dimensions")
        }

        // Calculate bounding box center
        let wallDir = simd_normalize(wall.endPoint - wall.startPoint)
        let wallNormal = SIMD2<Float>(-wallDir.y, wallDir.x)

        let centerAlongWall = positionOnWall + rawWidth / 2
        let center2D = wall.startPoint + wallDir * centerAlongWall + wallNormal * (rawDepth / 2)

        let centerY: Float
        switch cabinetType {
        case .base:
            centerY = rawHeight / 2
        case .upper:
            centerY = Self.upperCabinetBottomNominal + rawHeight / 2
        case .tall:
            centerY = rawHeight / 2
        }

        let boundingBox = AIBoundingBox3D(
            center: SIMD3<Float>(center2D.x, centerY, center2D.y),
            size: snappingResult.snapped
        )

        return AIDetectedCabinet(
            boundingBox: boundingBox,
            type: cabinetType,
            wallId: wall.id,
            positionOnWallInches: positionOnWall,
            rawDimensions: rawDimensions,
            snappedDimensions: snappingResult.snapped,
            confidence: confidence,
            isStandardSize: snappingResult.isStandard,
            cornerType: nil,
            notes: notes
        )
    }

    // MARK: - Task 6: Standard Size Snapping (AC5, AC8)

    /// Applies standard size snapping to raw dimensions.
    ///
    /// Per Architecture 7.3:
    /// - < 1.5" difference: snap to standard, HIGH confidence
    /// - < 3" difference: keep raw, MEDIUM confidence
    /// - >= 3" difference: keep raw, LOW confidence
    ///
    /// - Parameters:
    ///   - rawDimensions: Raw measured dimensions (w, h, d)
    ///   - cabinetType: Type of cabinet for appropriate standards
    /// - Returns: Snapped dimensions and whether standard
    private func applyStandardSizeSnapping(
        rawDimensions: SIMD3<Float>,
        cabinetType: AICabinetType
    ) -> (snapped: SIMD3<Float>, isStandard: Bool) {
        let rawWidth = rawDimensions.x
        let rawHeight = rawDimensions.y
        let rawDepth = rawDimensions.z

        // Snap width
        let (nearestWidth, widthDiff) = StandardCabinetSizes.nearestWidth(to: rawWidth)
        let snappedWidth = widthDiff < Self.snapHighThreshold ? nearestWidth : rawWidth

        // Snap height
        let (nearestHeight, heightDiff) = StandardCabinetSizes.nearestHeight(to: rawHeight, type: cabinetType)
        let snappedHeight = heightDiff < Self.snapHighThreshold ? nearestHeight : rawHeight

        // Snap depth
        let (nearestDepth, depthDiff) = StandardCabinetSizes.nearestDepth(to: rawDepth, type: cabinetType)
        let snappedDepth = depthDiff < Self.snapHighThreshold ? nearestDepth : rawDepth

        // Is standard if all dimensions match
        let isStandard = widthDiff < Self.snapHighThreshold &&
                         heightDiff < Self.snapHighThreshold &&
                         depthDiff < Self.snapHighThreshold

        return (
            snapped: SIMD3<Float>(snappedWidth, snappedHeight, snappedDepth),
            isStandard: isStandard
        )
    }

    // MARK: - Task 7: Confidence Scoring (AC4, AC6, AC7, AC8)

    /// Calculates confidence level for a detected cabinet.
    ///
    /// - Parameters:
    ///   - rawDimensions: Raw measured dimensions
    ///   - snappedDimensions: Snapped dimensions
    ///   - isStandardSize: Whether dimensions match standards
    ///   - isMerged: Whether cabinet was estimated from merged edges
    /// - Returns: Confidence level
    private func calculateConfidence(
        rawDimensions: SIMD3<Float>,
        snappedDimensions: SIMD3<Float>,
        isStandardSize: Bool,
        isMerged: Bool
    ) -> AIConfidenceLevel {
        // Calculate dimension differences
        let widthDiff = abs(rawDimensions.x - snappedDimensions.x)
        let heightDiff = abs(rawDimensions.y - snappedDimensions.y)
        let depthDiff = abs(rawDimensions.z - snappedDimensions.z)
        let maxDiff = max(widthDiff, max(heightDiff, depthDiff))

        // High: standard size and clear edges
        if isStandardSize && !isMerged {
            return .high
        }

        // Medium: geometric validated but unclear edges OR slight non-standard
        if maxDiff < Self.snapMediumThreshold || isMerged {
            return .medium
        }

        // Low: non-standard dimensions
        return .low
    }

    // MARK: - Task 8: Cabinet Run Validation (AC9)

    /// Validates cabinet coverage against wall lengths.
    ///
    /// - Parameters:
    ///   - cabinets: All detected cabinets
    ///   - walls: All walls in the room
    /// - Returns: Validation results per wall
    private func validateCabinetRuns(
        cabinets: [AIDetectedCabinet],
        walls: [AIWall]
    ) -> [WallCoverageValidation] {
        var validations: [WallCoverageValidation] = []

        for wall in walls {
            // Get cabinets on this wall
            let wallBaseCabinets = cabinets.filter { $0.wallId == wall.id && $0.type == .base }
            let wallUpperCabinets = cabinets.filter { $0.wallId == wall.id && $0.type == .upper }

            // Calculate totals
            let baseTotalInches = wallBaseCabinets.reduce(0) { $0 + $1.widthInches }
            let upperTotalInches = wallUpperCabinets.reduce(0) { $0 + $1.widthInches }

            // Find gaps between base cabinets
            let sortedBase = wallBaseCabinets.sorted { $0.positionOnWallInches < $1.positionOnWallInches }
            var baseGaps: [CabinetGap] = []

            for i in 1..<sortedBase.count {
                let prevEnd = sortedBase[i - 1].positionOnWallInches + sortedBase[i - 1].widthInches
                let currentStart = sortedBase[i].positionOnWallInches
                if currentStart > prevEnd + 1 {  // Gap > 1"
                    baseGaps.append(CabinetGap(startInches: prevEnd, endInches: currentStart))
                }
            }

            // Find gaps between upper cabinets
            let sortedUpper = wallUpperCabinets.sorted { $0.positionOnWallInches < $1.positionOnWallInches }
            var upperGaps: [CabinetGap] = []

            for i in 1..<sortedUpper.count {
                let prevEnd = sortedUpper[i - 1].positionOnWallInches + sortedUpper[i - 1].widthInches
                let currentStart = sortedUpper[i].positionOnWallInches
                if currentStart > prevEnd + 1 {
                    upperGaps.append(CabinetGap(startInches: prevEnd, endInches: currentStart))
                }
            }

            validations.append(WallCoverageValidation(
                wallId: wall.id,
                wallLengthInches: Float(wall.lengthInches),
                baseCabinetTotalInches: baseTotalInches,
                upperCabinetTotalInches: upperTotalInches,
                baseGaps: baseGaps,
                upperGaps: upperGaps
            ))
        }

        return validations
    }
}
