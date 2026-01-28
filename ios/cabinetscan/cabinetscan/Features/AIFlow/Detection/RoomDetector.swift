//
//  RoomDetector.swift
//  cabinetscan
//
//  Created for Story 4.1: Room Structure Detection
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Room Detector Protocol

/// Protocol for room detection implementations.
/// Enables testing with mock detectors.
protocol RoomDetectorProtocol {
    /// Detects room structure from a calibrated point cloud.
    ///
    /// - Parameter pointCloud: Calibrated point cloud in inches (from Epic 3)
    /// - Returns: Detected room structure with walls, boundaries, and dimensions
    /// - Throws: `RoomDetectionError` if detection fails
    func detect(from pointCloud: AIPointCloud) async throws -> AIRoomStructure
}

// MARK: - Room Detection Phase

/// Phases of room detection for progress tracking.
enum RoomDetectionPhase: String {
    case idle = "Idle"
    case floorDetection = "Detecting Floor"
    case wallDetection = "Detecting Walls"
    case boundaryExtraction = "Extracting Boundary"
    case openBoundaryDetection = "Detecting Open Boundaries"
    case dimensionCalculation = "Calculating Dimensions"
    case shapeClassification = "Classifying Shape"
    case complete = "Complete"

    var displayText: String {
        rawValue
    }
}

// MARK: - Room Detector

/// Detects room structure (walls, floor, boundaries) from calibrated 3D point cloud.
///
/// **Algorithm Pipeline:**
/// 1. Floor Detection - RANSAC on lowest points cluster
/// 2. Wall Detection - Vertical planes via iterative RANSAC
/// 3. Boundary Extraction - Project walls to 2D, connect into polygon
/// 4. Open Boundary Detection - Gaps in wall continuity
/// 5. Dimension Calculation - Width, length, area, perimeter
/// 6. Shape Classification - Rectangle, L-shape, U-shape, etc.
///
/// **Performance Budget:** <500ms (Architecture 9.3)
///
/// **Usage:**
/// ```swift
/// let detector = RoomDetector()
/// let roomStructure = try await detector.detect(from: calibratedPointCloud)
/// ```
@MainActor
final class RoomDetector: ObservableObject, RoomDetectorProtocol {

    // MARK: - Constants

    /// RANSAC iterations for plane fitting
    private static let ransacIterations: Int = 100

    /// RANSAC inlier threshold in inches
    private static let ransacThreshold: Float = 0.5

    /// Floor plane detection: use bottom percentage of points
    private static let floorPointPercentile: Float = 0.15

    /// Minimum points required for floor detection
    private static let minFloorPoints: Int = 50

    /// Minimum points required for a wall plane
    private static let minWallPoints: Int = 20

    /// Normal.y threshold for vertical plane detection
    /// A wall's normal should be horizontal (normal.y ≈ 0)
    private static let verticalPlaneThreshold: Float = 0.15

    /// Minimum wall length in inches to be considered valid
    private static let minWallLengthInches: Float = 12.0

    /// Maximum gap in wall continuity to consider as same boundary (inches)
    private static let wallGapThreshold: Float = 6.0

    /// Depth threshold for open boundary detection (inches)
    /// Points beyond this depth indicate open to adjacent room
    private static let openBoundaryDepthThreshold: Float = 120.0

    /// Point density threshold for open boundary detection (points per square inch)
    /// Below this density, a gap is considered an open boundary to adjacent room.
    /// Derived empirically: typical wall has ~1-5 points/sq.in, open space has <0.1
    private static let openBoundaryDensityThreshold: Float = 0.1

    /// Minimum room dimension in inches (4 feet)
    private static let minRoomDimensionInches: Float = 48.0

    /// Maximum room dimension in inches (30 feet)
    private static let maxRoomDimensionInches: Float = 360.0

    /// Corner proximity threshold in inches (for connecting walls)
    private static let cornerProximityThreshold: Float = 6.0

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current detection phase
    @Published private(set) var currentPhase: RoomDetectionPhase = .idle

    /// Whether detection is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "RoomDetector")

    /// Random number generator for RANSAC (injectable for deterministic testing)
    private var randomGenerator: RandomNumberGenerator

    // MARK: - Initialization

    /// Creates a RoomDetector with system random number generator.
    init() {
        self.randomGenerator = SystemRandomNumberGenerator()
        #if DEBUG
        logger.info("RoomDetector initialized")
        #endif
    }

    /// Creates a RoomDetector with a custom random number generator.
    /// Use this initializer for deterministic testing with a seeded generator.
    ///
    /// - Parameter randomGenerator: Custom RNG (e.g., SeededRandomNumberGenerator)
    init(randomGenerator: RandomNumberGenerator) {
        self.randomGenerator = randomGenerator
        #if DEBUG
        logger.info("RoomDetector initialized with custom RNG")
        #endif
    }

    // MARK: - Main Detection Entry Point

    /// Detects room structure from a calibrated point cloud.
    ///
    /// - Parameter pointCloud: Calibrated point cloud in inches
    /// - Returns: Complete room structure with walls, boundaries, dimensions
    /// - Throws: `RoomDetectionError` if detection fails
    func detect(from pointCloud: AIPointCloud) async throws -> AIRoomStructure {
        logger.info("Starting room detection with \(pointCloud.count) points")

        guard !pointCloud.isEmpty else {
            throw RoomDetectionError.emptyPointCloud
        }

        isProcessing = true
        progress = 0.0
        currentPhase = .floorDetection

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Get points from point cloud
        var mutablePointCloud = pointCloud
        let points = mutablePointCloud.getPoints()

        // Task 2: Floor Plane Detection (AC2)
        try Task.checkCancellation()
        let floorPlane = try detectFloorPlane(from: points)
        progress = 0.20
        logger.info("Floor plane detected at y=\(-floorPlane.distance)")

        // Task 3: Wall Detection (AC1, AC4)
        currentPhase = .wallDetection
        try Task.checkCancellation()
        let walls = detectWalls(from: points, floorPlane: floorPlane)
        progress = 0.50
        logger.info("Detected \(walls.count) walls")

        guard walls.count >= 3 else {
            throw RoomDetectionError.insufficientWalls
        }

        // Task 4: Boundary Extraction (AC3, AC4)
        currentPhase = .boundaryExtraction
        try Task.checkCancellation()
        let boundaryPolygon = try extractBoundaryPolygon(from: walls)
        progress = 0.65
        logger.info("Boundary polygon has \(boundaryPolygon.count) vertices")

        // Task 5: Open Boundary Detection (AC5)
        currentPhase = .openBoundaryDetection
        try Task.checkCancellation()
        let openBoundaries = detectOpenBoundaries(walls: walls, points: points)
        progress = 0.75

        // Task 6: Dimension Calculation (AC6)
        currentPhase = .dimensionCalculation
        try Task.checkCancellation()
        let (ceilingHeight, ceilingWasClipped) = detectCeilingHeight(from: points, floorPlane: floorPlane)
        let dimensions = try calculateDimensions(
            from: boundaryPolygon,
            walls: walls,
            ceilingHeight: ceilingHeight,
            originalPoints: points  // Pass original points for accurate bounds (NFR6)
        )
        progress = 0.85

        // Track warnings for result
        var detectionWarnings: [String] = []
        if ceilingWasClipped {
            detectionWarnings.append("Ceiling height was outside normal range (8'-12') and was adjusted")
        }

        // Shape Classification
        currentPhase = .shapeClassification
        try Task.checkCancellation()
        let roomShape = classifyRoomShape(
            walls: walls,
            boundaryPolygon: boundaryPolygon,
            openBoundaries: openBoundaries
        )
        progress = 0.95

        // Calculate confidence
        let confidence = calculateConfidence(
            floorPoints: points.filter { floorPlane.absoluteDistance(to: $0) < Self.ransacThreshold }.count,
            totalPoints: points.count,
            wallCount: walls.count,
            boundaryVertices: boundaryPolygon.count
        )

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        logger.info("Room detection complete in \(processingTimeMs)ms: \(roomShape.rawValue) room, \(walls.count) walls")

        return AIRoomStructure(
            floorPlane: floorPlane,
            ceilingHeightInches: ceilingHeight,
            walls: walls,
            boundaryPolygon: boundaryPolygon,
            roomShape: roomShape,
            dimensions: dimensions,
            openBoundaries: openBoundaries,
            confidence: confidence,
            processingTimeMs: processingTimeMs,
            warnings: detectionWarnings
        )
    }

    // MARK: - Task 2: Floor Plane Detection (AC2)

    /// Detects floor plane using RANSAC on lowest points cluster.
    ///
    /// - Parameter points: All points in the point cloud
    /// - Returns: The detected floor plane
    /// - Throws: `RoomDetectionError.floorDetectionFailed` if no floor found
    private func detectFloorPlane(from points: [SIMD3<Float>]) throws -> RoomPlane3D {
        // Sort points by Y (vertical) coordinate to find lowest cluster
        let sortedByY = points.sorted { $0.y < $1.y }

        // Take bottom percentile of points for floor detection
        let floorPointCount = max(
            Self.minFloorPoints,
            Int(Float(points.count) * Self.floorPointPercentile)
        )
        let floorCandidates = Array(sortedByY.prefix(floorPointCount))

        guard floorCandidates.count >= Self.minFloorPoints else {
            throw RoomDetectionError.floorDetectionFailed
        }

        // Run RANSAC to fit floor plane
        guard let plane = ransacFitPlane(
            points: floorCandidates,
            iterations: Self.ransacIterations,
            threshold: Self.ransacThreshold
        ) else {
            throw RoomDetectionError.floorDetectionFailed
        }

        // Validate floor is approximately horizontal (normal ≈ [0, 1, 0] or [0, -1, 0])
        let normalizedNormal = simd_normalize(plane.normal)
        let verticalComponent = abs(normalizedNormal.y)

        guard verticalComponent > 0.9 else {
            logger.warning("Detected floor plane is not horizontal: normal.y = \(normalizedNormal.y)")
            throw RoomDetectionError.floorDetectionFailed
        }

        // Ensure normal points upward
        var finalNormal = normalizedNormal
        var finalDistance = plane.distance
        if finalNormal.y < 0 {
            finalNormal = -finalNormal
            finalDistance = -finalDistance
        }

        return RoomPlane3D(
            normal: finalNormal,
            distance: finalDistance,
            center: plane.center
        )
    }

    // MARK: - Task 3: Wall Detection (AC1, AC4)

    /// Detects vertical walls using iterative RANSAC.
    ///
    /// - Parameters:
    ///   - points: All points in the point cloud
    ///   - floorPlane: The detected floor plane
    /// - Returns: Array of detected walls
    private func detectWalls(
        from points: [SIMD3<Float>],
        floorPlane: RoomPlane3D
    ) -> [AIWall] {
        // Filter points that are above the floor (wall candidates)
        // Wall points should be at least a few inches above floor
        let minHeightAboveFloor: Float = 6.0
        let maxHeightAboveFloor: Float = 120.0 // 10 feet

        let wallCandidates = points.filter { point in
            let heightAboveFloor = point.y - (-floorPlane.distance)
            return heightAboveFloor >= minHeightAboveFloor && heightAboveFloor <= maxHeightAboveFloor
        }

        var walls: [AIWall] = []
        var remainingPoints = wallCandidates
        var iteration = 0
        let maxIterations = 10

        while remainingPoints.count >= Self.minWallPoints && iteration < maxIterations {
            iteration += 1

            // Find vertical planes (normal is approximately horizontal)
            guard let (plane, inlierIndices) = ransacFitVerticalPlane(
                points: remainingPoints,
                iterations: Self.ransacIterations,
                threshold: Self.ransacThreshold
            ) else {
                break
            }

            let wallPoints = inlierIndices.map { remainingPoints[$0] }

            // Project to 2D (X-Z plane) and fit line segment
            let points2D = wallPoints.map { SIMD2<Float>($0.x, $0.z) }
            let (start2D, end2D) = fitLine2D(points: points2D)

            // Calculate wall length
            let wallLength = simd_distance(start2D, end2D)

            // Skip walls that are too short
            guard wallLength >= Self.minWallLengthInches else {
                // Remove these points and continue
                let inlierSet = Set(inlierIndices)
                remainingPoints = remainingPoints.enumerated()
                    .filter { !inlierSet.contains($0.offset) }
                    .map { $0.element }
                continue
            }

            // Calculate wall height
            let wallHeights = wallPoints.map { $0.y - (-floorPlane.distance) }
            let wallHeight = (wallHeights.max() ?? 0) - (wallHeights.min() ?? 0)

            // Calculate 2D normal (perpendicular to wall direction)
            let wallDir = simd_normalize(end2D - start2D)
            let normal2D = SIMD2<Float>(-wallDir.y, wallDir.x)

            let wall = AIWall(
                id: UUID(),
                plane: plane,
                startPoint: start2D,
                endPoint: end2D,
                lengthInches: Double(wallLength),
                heightInches: Double(wallHeight),
                normalDirection: normal2D,
                boundaryType: .wall
            )
            walls.append(wall)

            // Remove inliers from remaining points
            let inlierSet = Set(inlierIndices)
            remainingPoints = remainingPoints.enumerated()
                .filter { !inlierSet.contains($0.offset) }
                .map { $0.element }

            logger.debug("Wall \(walls.count): length=\(wallLength)in, height=\(wallHeight)in")
        }

        return walls
    }

    // MARK: - Task 4: Boundary Extraction (AC3, AC4)

    /// Extracts room boundary polygon from detected walls.
    ///
    /// Projects walls to 2D and connects them into a closed polygon.
    /// Handles interior corners (L-shape, U-shape).
    ///
    /// - Parameter walls: Detected walls
    /// - Returns: Ordered boundary polygon vertices (2D)
    /// - Throws: `RoomDetectionError.boundaryExtractionFailed` if polygon cannot be formed
    private func extractBoundaryPolygon(from walls: [AIWall]) throws -> [SIMD2<Float>] {
        guard walls.count >= 3 else {
            throw RoomDetectionError.boundaryExtractionFailed
        }

        // Collect all wall endpoints
        var endpoints: [(point: SIMD2<Float>, wallIndex: Int, isStart: Bool)] = []
        for (index, wall) in walls.enumerated() {
            endpoints.append((wall.startPoint, index, true))
            endpoints.append((wall.endPoint, index, false))
        }

        // Find corners by clustering nearby endpoints
        var corners: [SIMD2<Float>] = []
        var usedEndpoints = Set<Int>()

        for (i, ep1) in endpoints.enumerated() {
            guard !usedEndpoints.contains(i) else { continue }

            var cluster = [ep1.point]
            usedEndpoints.insert(i)

            // Find all endpoints within proximity threshold
            for (j, ep2) in endpoints.enumerated() {
                guard j > i && !usedEndpoints.contains(j) else { continue }

                let dist = simd_distance(ep1.point, ep2.point)
                if dist < Self.cornerProximityThreshold {
                    cluster.append(ep2.point)
                    usedEndpoints.insert(j)
                }
            }

            // Corner position is centroid of cluster
            let cornerPos = cluster.reduce(SIMD2<Float>.zero, +) / Float(cluster.count)
            corners.append(cornerPos)
        }

        // Sort corners counter-clockwise around centroid
        let centroid = corners.reduce(SIMD2<Float>.zero, +) / Float(corners.count)
        let sortedCorners = corners.sorted { a, b in
            let angleA = atan2(a.y - centroid.y, a.x - centroid.x)
            let angleB = atan2(b.y - centroid.y, b.x - centroid.x)
            return angleA < angleB
        }

        guard sortedCorners.count >= 3 else {
            throw RoomDetectionError.boundaryExtractionFailed
        }

        return sortedCorners
    }

    // MARK: - Task 5: Open Boundary Detection (AC5)

    /// Detects open boundaries where kitchen opens to adjacent room.
    ///
    /// - Parameters:
    ///   - walls: Detected walls
    ///   - points: All points in the point cloud
    /// - Returns: Array of open boundary segments
    private func detectOpenBoundaries(
        walls: [AIWall],
        points: [SIMD3<Float>]
    ) -> [OpenBoundary] {
        var openBoundaries: [OpenBoundary] = []

        // Check for gaps between wall endpoints
        for (i, wall1) in walls.enumerated() {
            for (j, wall2) in walls.enumerated() where j > i {
                // Check if wall endpoints are close but not connected
                let gaps = [
                    (wall1.endPoint, wall2.startPoint),
                    (wall1.endPoint, wall2.endPoint),
                    (wall1.startPoint, wall2.startPoint),
                    (wall1.startPoint, wall2.endPoint)
                ]

                for (p1, p2) in gaps {
                    let gapWidth = simd_distance(p1, p2)

                    // Gap is too large to be a corner but could be an opening
                    if gapWidth > Self.cornerProximityThreshold && gapWidth < Self.openBoundaryDepthThreshold {
                        // Check if there are few points in this gap region (indicating open space)
                        let gapCenter = (p1 + p2) / 2
                        let pointsInGap = points.filter { point in
                            let point2D = SIMD2<Float>(point.x, point.z)
                            let distToGapCenter = simd_distance(point2D, gapCenter)
                            return distToGapCenter < gapWidth / 2
                        }

                        // If few points in gap, it's likely an open boundary
                        let pointDensity = Float(pointsInGap.count) / (gapWidth * gapWidth)
                        if pointDensity < Self.openBoundaryDensityThreshold {
                            openBoundaries.append(OpenBoundary(
                                startPoint: p1,
                                endPoint: p2,
                                widthInches: Double(gapWidth)
                            ))
                        }
                    }
                }
            }
        }

        return openBoundaries
    }

    // MARK: - Task 6: Dimension Calculation (AC6)

    /// Detects ceiling height from point cloud.
    ///
    /// Uses 99th percentile for accuracy (NFR6: ±1") while filtering extreme outliers.
    ///
    /// - Parameters:
    ///   - points: All points in the point cloud
    ///   - floorPlane: The detected floor plane
    /// - Returns: Tuple of (ceiling height in inches, whether value was clamped)
    private func detectCeilingHeight(
        from points: [SIMD3<Float>],
        floorPlane: RoomPlane3D
    ) -> (height: Double, wasClipped: Bool) {
        // Calculate height above floor for each point
        let floorY = -floorPlane.distance
        let heights = points.map { $0.y - floorY }

        // Use 99th percentile as ceiling height for accuracy (NFR6: ±1")
        // 99th percentile ignores extreme outliers while maintaining accuracy
        let sortedHeights = heights.sorted()
        let percentileIndex = Int(Float(sortedHeights.count) * 0.99)
        let rawCeilingHeight = Double(sortedHeights[min(percentileIndex, sortedHeights.count - 1)])

        // Validate against reasonable ceiling heights (96" to 144" = 8' to 12')
        let wasClipped = rawCeilingHeight < 96.0 || rawCeilingHeight > 144.0
        let clampedHeight = max(96.0, min(144.0, rawCeilingHeight))

        if wasClipped {
            logger.warning("Ceiling height \(rawCeilingHeight)\" outside normal range (96\"-144\"), clamped to \(clampedHeight)\"")
        } else {
            logger.debug("Ceiling height: \(rawCeilingHeight)in")
        }

        return (clampedHeight, wasClipped)
    }

    /// Calculates room dimensions from original point cloud for NFR6 accuracy (±1").
    ///
    /// Uses original points for bounding box (most accurate) and boundary polygon for area.
    ///
    /// - Parameters:
    ///   - boundaryPolygon: Room boundary in 2D (used for area calculation)
    ///   - walls: Detected walls (used for perimeter)
    ///   - ceilingHeight: Ceiling height in inches
    ///   - originalPoints: Original point cloud (used for accurate bounding box)
    /// - Returns: Room dimensions
    /// - Throws: `RoomDetectionError.dimensionCalculationFailed` if calculation fails
    private func calculateDimensions(
        from boundaryPolygon: [SIMD2<Float>],
        walls: [AIWall],
        ceilingHeight: Double,
        originalPoints: [SIMD3<Float>]
    ) throws -> RoomDimensions {
        guard !boundaryPolygon.isEmpty else {
            throw RoomDetectionError.dimensionCalculationFailed
        }

        // NFR6: Use original point cloud bounds for accurate width/length (±1")
        // This is more accurate than using derived boundary polygon
        let xCoords = originalPoints.map { $0.x }
        let zCoords = originalPoints.map { $0.z }

        let minX = xCoords.min() ?? 0
        let maxX = xCoords.max() ?? 0
        let minZ = zCoords.min() ?? 0
        let maxZ = zCoords.max() ?? 0

        let width = Double(maxX - minX)
        let length = Double(maxZ - minZ)

        // Calculate area using Shoelace formula
        let area = calculatePolygonArea(vertices: boundaryPolygon)

        // Calculate perimeter as sum of wall lengths
        let perimeter = walls.reduce(0.0) { $0 + $1.lengthInches }

        // Log warning if dimensions are outside reasonable range
        if width < Double(Self.minRoomDimensionInches) ||
           width > Double(Self.maxRoomDimensionInches) ||
           length < Double(Self.minRoomDimensionInches) ||
           length > Double(Self.maxRoomDimensionInches) {
            logger.warning("Room dimensions may be out of typical range: \(width)\" x \(length)\"")
        }

        return RoomDimensions(
            widthInches: width,
            lengthInches: length,
            ceilingHeightInches: ceilingHeight,
            areaSquareInches: area,
            perimeterInches: perimeter
        )
    }

    // MARK: - Shape Classification

    /// Classifies room shape based on geometry.
    ///
    /// - Parameters:
    ///   - walls: Detected walls
    ///   - boundaryPolygon: Room boundary polygon
    ///   - openBoundaries: Open boundary segments
    /// - Returns: Classified room shape
    private func classifyRoomShape(
        walls: [AIWall],
        boundaryPolygon: [SIMD2<Float>],
        openBoundaries: [OpenBoundary]
    ) -> RoomShape {
        // Check for open boundaries first
        if !openBoundaries.isEmpty {
            return .open
        }

        let wallCount = walls.count
        let cornerCount = boundaryPolygon.count

        // Calculate aspect ratio for galley detection
        let xCoords = boundaryPolygon.map { $0.x }
        let zCoords = boundaryPolygon.map { $0.y }
        let width = (xCoords.max() ?? 0) - (xCoords.min() ?? 0)
        let length = (zCoords.max() ?? 0) - (zCoords.min() ?? 0)
        let aspectRatio = max(width, length) / max(min(width, length), 1)

        // Galley: narrow room with high aspect ratio
        if wallCount <= 4 && aspectRatio > 2.5 {
            return .galley
        }

        // Rectangle: 4 walls, 4 corners, roughly equal angles
        if wallCount == 4 && cornerCount == 4 {
            return .rectangle
        }

        // L-shape: 6 walls/corners (2 more than rectangle)
        if (wallCount == 5 || wallCount == 6) && (cornerCount == 5 || cornerCount == 6) {
            return .lShape
        }

        // U-shape: 8 walls/corners
        if wallCount >= 7 && cornerCount >= 7 {
            return .uShape
        }

        return .irregular
    }

    // MARK: - Confidence Calculation

    /// Calculates detection confidence.
    private func calculateConfidence(
        floorPoints: Int,
        totalPoints: Int,
        wallCount: Int,
        boundaryVertices: Int
    ) -> DetectionConfidence {
        // Floor confidence: ratio of points near floor plane
        let floorConfidence = min(1.0, Float(floorPoints) / Float(max(100, totalPoints / 10)))

        // Wall confidence: based on number of walls detected
        let wallConfidence: Float = switch wallCount {
        case 4: 1.0    // Perfect rectangle
        case 5...6: 0.9 // L-shape
        case 7...8: 0.85 // U-shape
        case 3: 0.7     // Minimum walls
        default: 0.6    // Unusual count
        }

        // Boundary confidence: based on polygon quality
        let boundaryConfidence: Float = switch boundaryVertices {
        case 4: 1.0     // Perfect rectangle
        case 5...8: 0.9  // Common shapes
        case 3: 0.7      // Minimum
        default: 0.6     // Irregular
        }

        return DetectionConfidence(
            floorConfidence: floorConfidence,
            wallConfidence: wallConfidence,
            boundaryConfidence: boundaryConfidence
        )
    }

    // MARK: - RANSAC Helpers

    /// RANSAC plane fitting for general 3D planes.
    private func ransacFitPlane(
        points: [SIMD3<Float>],
        iterations: Int,
        threshold: Float
    ) -> RoomPlane3D? {
        guard points.count >= 3 else { return nil }

        var bestPlane: RoomPlane3D?
        var bestInlierCount = 0

        for _ in 0..<iterations {
            // Sample 3 random points
            let indices = randomIndices(count: 3, max: points.count)
            let p1 = points[indices[0]]
            let p2 = points[indices[1]]
            let p3 = points[indices[2]]

            // Fit plane through 3 points
            let v1 = p2 - p1
            let v2 = p3 - p1
            let cross = simd_cross(v1, v2)
            let crossLength = simd_length(cross)
            guard crossLength > 0.0001 else { continue }

            let normal = cross / crossLength
            let distance = -simd_dot(normal, p1)
            let center = (p1 + p2 + p3) / 3

            // Count inliers
            var inlierCount = 0
            for point in points {
                let dist = abs(simd_dot(normal, point) + distance)
                if dist < threshold {
                    inlierCount += 1
                }
            }

            if inlierCount > bestInlierCount {
                bestInlierCount = inlierCount
                bestPlane = RoomPlane3D(normal: normal, distance: distance, center: center)
            }
        }

        return bestPlane
    }

    /// RANSAC for fitting vertical planes (walls).
    private func ransacFitVerticalPlane(
        points: [SIMD3<Float>],
        iterations: Int,
        threshold: Float
    ) -> (plane: RoomPlane3D, inlierIndices: [Int])? {
        guard points.count >= 3 else { return nil }

        var bestPlane: RoomPlane3D?
        var bestInliers: [Int] = []

        for _ in 0..<iterations {
            // Sample 3 random points
            let indices = randomIndices(count: 3, max: points.count)
            let p1 = points[indices[0]]
            let p2 = points[indices[1]]
            let p3 = points[indices[2]]

            // Fit plane
            let v1 = p2 - p1
            let v2 = p3 - p1
            let cross = simd_cross(v1, v2)
            let crossLength = simd_length(cross)
            guard crossLength > 0.0001 else { continue }

            let normal = cross / crossLength

            // Verify it's a vertical plane (normal is approximately horizontal)
            guard abs(normal.y) < Self.verticalPlaneThreshold else { continue }

            let distance = -simd_dot(normal, p1)
            let center = (p1 + p2 + p3) / 3

            // Count inliers
            var inliers: [Int] = []
            for (idx, point) in points.enumerated() {
                let dist = abs(simd_dot(normal, point) + distance)
                if dist < threshold {
                    inliers.append(idx)
                }
            }

            if inliers.count > bestInliers.count {
                bestInliers = inliers
                bestPlane = RoomPlane3D(normal: normal, distance: distance, center: center)
            }
        }

        guard bestInliers.count >= Self.minWallPoints, let plane = bestPlane else {
            return nil
        }

        return (plane, bestInliers)
    }

    /// Generates random distinct indices using the injected random generator.
    private func randomIndices(count: Int, max: Int) -> [Int] {
        var indices = Set<Int>()
        while indices.count < count && indices.count < max {
            indices.insert(Int.random(in: 0..<max, using: &randomGenerator))
        }
        return Array(indices)
    }

    // MARK: - 2D Geometry Helpers

    /// Fits a 2D line to points and returns endpoints.
    private func fitLine2D(points: [SIMD2<Float>]) -> (start: SIMD2<Float>, end: SIMD2<Float>) {
        guard points.count >= 2 else {
            return (SIMD2(0, 0), SIMD2(1, 0))
        }

        // Find principal axis using PCA
        let centroid = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let centered = points.map { $0 - centroid }

        // Compute covariance matrix elements
        var cxx: Float = 0
        var cxy: Float = 0
        var cyy: Float = 0

        for p in centered {
            cxx += p.x * p.x
            cxy += p.x * p.y
            cyy += p.y * p.y
        }

        // Find eigenvector of larger eigenvalue (principal direction)
        let trace = cxx + cyy
        let det = cxx * cyy - cxy * cxy
        let discriminant = sqrt(max(0, trace * trace / 4 - det))
        let lambda1 = trace / 2 + discriminant

        var direction: SIMD2<Float>
        if abs(cxy) > 0.0001 {
            direction = simd_normalize(SIMD2(lambda1 - cyy, cxy))
        } else if cxx >= cyy {
            direction = SIMD2(1, 0)
        } else {
            direction = SIMD2(0, 1)
        }

        // Project all points onto line and find extents
        let projections = centered.map { simd_dot($0, direction) }
        let minProj = projections.min() ?? 0
        let maxProj = projections.max() ?? 0

        let start = centroid + direction * minProj
        let end = centroid + direction * maxProj

        return (start, end)
    }

    /// Calculates polygon area using the Shoelace formula.
    private func calculatePolygonArea(vertices: [SIMD2<Float>]) -> Double {
        guard vertices.count >= 3 else { return 0 }

        var area: Float = 0
        let n = vertices.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += vertices[i].x * vertices[j].y
            area -= vertices[j].x * vertices[i].y
        }

        return Double(abs(area) / 2)
    }
}
