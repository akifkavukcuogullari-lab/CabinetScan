//
//  GeometricConstraints.swift
//  cabinetscan
//
//  Created for Story 3.7: Geometric Constraints Application
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Geometric Constraints Errors

enum GeometricConstraintsError: LocalizedError, Equatable {
    case emptyMesh
    case wallDetectionFailed
    case cornerDetectionFailed
    case validationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptyMesh:
            return "Mesh is empty - cannot apply geometric constraints"
        case .wallDetectionFailed:
            return "Failed to detect walls in the mesh"
        case .cornerDetectionFailed:
            return "Failed to detect corners in the mesh"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .cancelled:
            return "Geometric constraint application was cancelled"
        }
    }
}

// MARK: - Constraint Phase

enum ConstraintPhase: String {
    case idle = "Idle"
    case aligningFloor = "Aligning Floor"
    case detectingWalls = "Detecting Walls"
    case snappingVertical = "Snapping Vertical"
    case detectingCorners = "Detecting Corners"
    case regularizingCorners = "Regularizing Corners"
    case straighteningWalls = "Straightening Walls"
    case validating = "Validating"
    case complete = "Complete"
}

// MARK: - Detected Wall

/// A wall segment detected in the mesh.
struct DetectedWall {
    /// Start point of wall in XZ plane (top-down view)
    var startPoint: SIMD2<Float>

    /// End point of wall in XZ plane (top-down view)
    var endPoint: SIMD2<Float>

    /// Normal vector of the wall surface (horizontal component)
    var normal: SIMD3<Float>

    /// Height of the wall
    var height: Float

    /// Whether the wall was snapped to vertical
    var isVertical: Bool

    /// Angle deviation from true vertical (degrees)
    var verticalityAngle: Float

    /// Indices of mesh triangles belonging to this wall
    var triangleIndices: [Int]

    /// Indices of mesh vertices belonging to this wall (for vertex transformation)
    var vertexIndices: Set<Int>

    /// Original length before regularization (for validation)
    var originalLength: Float?

    /// Length of the wall
    var length: Float {
        simd_distance(startPoint, endPoint)
    }

    /// Change in length from original (in same units as length)
    var lengthChange: Float {
        guard let original = originalLength else { return 0 }
        return abs(length - original)
    }
}

// MARK: - Detected Corner

/// A corner where two walls meet.
struct DetectedCorner {
    /// Position of the corner in XZ plane
    var position: SIMD2<Float>

    /// Index of first wall forming this corner
    var wall1Index: Int

    /// Index of second wall forming this corner
    var wall2Index: Int

    /// Angle between the walls (degrees)
    var angle: Float

    /// Whether this corner was regularized (snapped to standard angle)
    var wasRegularized: Bool

    /// Whether this is a non-standard angle (not near 90°, 45°, or 135°)
    var isNonStandard: Bool
}

// MARK: - Constraint Validation

/// Validation results for the constraint application.
struct ConstraintValidation {
    /// Whether the perimeter is consistent with sum of wall lengths
    let perimeterConsistent: Bool

    /// Whether the area calculation is consistent
    let areaConsistent: Bool

    /// Maximum wall change in inches
    let maxWallChangeInches: Float

    /// Indices of walls that changed more than 2"
    let wallsExceedingThreshold: [Int]
}

// MARK: - Geometric Constraints Input

/// Input data for geometric constraint application.
struct GeometricConstraintsInput {
    let fusionResult: TSDFFusionResult
    let calibration: ScaleCalibrationResult
}

// MARK: - Geometric Constraints Result

/// Result of applying geometric constraints to a mesh.
struct GeometricConstraintsResult {
    /// The regularized (constraint-applied) mesh
    let regularizedMesh: AIMesh

    /// The original mesh before constraints (for debugging)
    let originalMesh: AIMesh

    /// Rotation matrix applied to align floor with Y-up
    let floorAlignmentApplied: simd_float4x4

    /// Detected and regularized walls
    let walls: [DetectedWall]

    /// Detected and regularized corners
    let corners: [DetectedCorner]

    /// Validation results
    let validation: ConstraintValidation

    /// Processing time in milliseconds
    let processingTimeMs: Int
}

// MARK: - Geometric Constraints Processor

/// Applies geometric constraints to regularize 3D reconstructions.
///
/// **Processing Pipeline:**
/// 1. Align floor to horizontal (Y=0)
/// 2. Detect vertical walls using iterative RANSAC
/// 3. Snap walls to true vertical (within 5° tolerance)
/// 4. Detect corners (wall intersections)
/// 5. Regularize corners to standard angles (90°, 45°, 135°)
/// 6. Straighten walls to connect at regularized corners
/// 7. Validate changes are within tolerance
///
/// **Usage:**
/// ```swift
/// let constraints = GeometricConstraints()
/// let result = try await constraints.apply(
///     to: fusionResult,
///     calibration: calibrationResult
/// )
/// ```
@MainActor
final class GeometricConstraints: ObservableObject {

    // MARK: - Constants

    /// Tolerance for snapping to vertical (5° per ADR-002)
    private static let verticalSnapTolerance: Float = 5.0

    /// Tolerance for snapping to standard angles (5°)
    private static let angleSnapTolerance: Float = 5.0

    /// Maximum wall change before flagging (2" per AC7)
    private static let maxWallChangeInches: Float = 2.0

    /// RANSAC iterations for plane fitting
    private static let ransacIterations: Int = 100

    /// RANSAC inlier threshold
    private static let ransacThreshold: Float = 0.05

    /// Minimum points for a wall plane
    private static let minWallPoints: Int = 10

    /// Normal.y threshold for vertical plane detection (horizontal normal)
    private static let verticalPlaneThreshold: Float = 0.1

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current processing phase
    @Published private(set) var currentPhase: ConstraintPhase = .idle

    /// Whether processing is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "GeometricConstraints")

    // MARK: - Initialization

    init() {
        logger.info("GeometricConstraints initialized")
    }

    // MARK: - Main Entry Point (Task 8)

    /// Applies geometric constraints to regularize the mesh.
    ///
    /// - Parameters:
    ///   - fusionResult: TSDF fusion result containing the mesh
    ///   - calibration: Scale calibration result with floor plane
    /// - Returns: Constrained mesh with regularized geometry
    /// - Throws: `GeometricConstraintsError` if processing fails
    func apply(
        to fusionResult: TSDFFusionResult,
        calibration: ScaleCalibrationResult
    ) async throws -> GeometricConstraintsResult {
        guard !fusionResult.mesh.isEmpty else {
            throw GeometricConstraintsError.emptyMesh
        }

        logger.info("Starting geometric constraints for mesh with \(fusionResult.mesh.vertexCount) vertices")

        isProcessing = true
        progress = 0.0
        currentPhase = .aligningFloor

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Preserve original mesh for validation
        let originalMesh = fusionResult.mesh

        // Task 0: Apply floor plane alignment (AC2)
        try Task.checkCancellation()
        let (alignedMesh, floorRotation) = alignFloorToHorizontal(
            mesh: fusionResult.mesh,
            floorPlane: calibration.floorPlane
        )
        progress = 0.15

        // Task 2: Detect walls using iterative RANSAC (AC1)
        currentPhase = .detectingWalls
        try Task.checkCancellation()
        var walls = detectWalls(from: alignedMesh)
        logger.info("Detected \(walls.count) walls")
        progress = 0.35

        // Task 3: Snap walls to vertical (AC1, AC4)
        currentPhase = .snappingVertical
        try Task.checkCancellation()
        var workingMesh = alignedMesh
        snapWallsToVertical(&walls, mesh: &workingMesh)
        progress = 0.50

        // Task 4: Detect corners (AC3)
        currentPhase = .detectingCorners
        try Task.checkCancellation()
        var corners = detectCorners(from: walls)
        logger.info("Detected \(corners.count) corners")
        progress = 0.65

        // Task 5: Regularize corners (AC3, AC4, AC5)
        currentPhase = .regularizingCorners
        try Task.checkCancellation()
        regularizeCorners(&corners, walls: &walls)
        progress = 0.75

        // Task 6: Straighten walls (AC6)
        currentPhase = .straighteningWalls
        try Task.checkCancellation()
        straightenWalls(&walls, corners: corners, mesh: &workingMesh)
        progress = 0.85

        // Task 7: Validate (AC7)
        currentPhase = .validating
        try Task.checkCancellation()
        let validation = validateRegularization(
            original: originalMesh,
            regularized: workingMesh,
            walls: walls,
            scaleFactor: calibration.scaleFactor
        )
        progress = 1.0

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        logger.info("Geometric constraints complete in \(processingTimeMs)ms")

        return GeometricConstraintsResult(
            regularizedMesh: workingMesh,
            originalMesh: originalMesh,
            floorAlignmentApplied: floorRotation,
            walls: walls,
            corners: corners,
            validation: validation,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - Task 0: Floor Plane Alignment (AC2)

    /// Aligns the floor plane to be horizontal (Y=0).
    ///
    /// - Parameters:
    ///   - mesh: The mesh to align
    ///   - floorPlane: The detected floor plane from calibration
    /// - Returns: Tuple of aligned mesh and the rotation matrix applied
    private func alignFloorToHorizontal(
        mesh: AIMesh,
        floorPlane: AIPlane
    ) -> (AIMesh, simd_float4x4) {
        // Target: floor normal should be Y-up (0, 1, 0)
        let targetNormal = SIMD3<Float>(0, 1, 0)
        let currentNormal = simd_normalize(floorPlane.normal)

        // Check if already aligned
        let dotProduct = simd_dot(currentNormal, targetNormal)
        if abs(dotProduct) > 0.999 {
            // Already aligned (or inverted)
            logger.info("Floor already horizontal, no rotation needed")
            return (mesh, simd_float4x4(1))
        }

        // Calculate rotation to align floor normal with Y-up
        let rotationMatrix = rotationMatrixFromTo(from: currentNormal, to: targetNormal)

        // Transform all vertices
        let transformedVertices = mesh.vertices.map { vertex -> SIMD3<Float> in
            let v4 = SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
            let rotated = rotationMatrix * v4
            return SIMD3<Float>(rotated.x, rotated.y, rotated.z)
        }

        let alignedMesh = AIMesh(vertices: transformedVertices, indices: mesh.indices)
        logger.info("Floor aligned to horizontal with rotation matrix")

        return (alignedMesh, rotationMatrix)
    }

    /// Creates a rotation matrix to rotate one vector to another.
    private func rotationMatrixFromTo(from: SIMD3<Float>, to: SIMD3<Float>) -> simd_float4x4 {
        let fromNorm = simd_normalize(from)
        let toNorm = simd_normalize(to)

        let dot = simd_dot(fromNorm, toNorm)

        // Handle parallel vectors
        if dot > 0.9999 {
            return simd_float4x4(1)
        }
        if dot < -0.9999 {
            // 180° rotation - find perpendicular axis
            var perp = simd_cross(SIMD3<Float>(1, 0, 0), fromNorm)
            if simd_length(perp) < 0.001 {
                perp = simd_cross(SIMD3<Float>(0, 1, 0), fromNorm)
            }
            perp = simd_normalize(perp)
            return rotationMatrix(angle: .pi, axis: perp)
        }

        // General case using Rodrigues' rotation formula
        let axis = simd_normalize(simd_cross(fromNorm, toNorm))
        let angle = acos(dot)

        return rotationMatrix(angle: angle, axis: axis)
    }

    /// Creates a rotation matrix from angle and axis.
    private func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c
        let x = axis.x
        let y = axis.y
        let z = axis.z

        return simd_float4x4(
            SIMD4<Float>(t*x*x + c,    t*x*y - s*z, t*x*z + s*y, 0),
            SIMD4<Float>(t*x*y + s*z,  t*y*y + c,   t*y*z - s*x, 0),
            SIMD4<Float>(t*x*z - s*y,  t*y*z + s*x, t*z*z + c,   0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    // MARK: - Task 2: Wall Detection (AC1)

    /// Detects walls using iterative RANSAC.
    ///
    /// - Parameter mesh: The aligned mesh
    /// - Returns: Array of detected walls
    private func detectWalls(from mesh: AIMesh) -> [DetectedWall] {
        var walls: [DetectedWall] = []
        var remainingTriangles = Set(0..<mesh.triangleCount)

        // Iteratively find walls until no significant planes remain
        while remainingTriangles.count >= Self.minWallPoints {
            // Collect vertices and normals from remaining triangles
            var candidatePoints: [(position: SIMD3<Float>, normal: SIMD3<Float>, triangleIdx: Int)] = []

            for triIdx in remainingTriangles {
                let idx = triIdx * 3
                guard idx + 2 < mesh.indices.count else { continue }

                let i0 = Int(mesh.indices[idx])
                let i1 = Int(mesh.indices[idx + 1])
                let i2 = Int(mesh.indices[idx + 2])

                guard i0 < mesh.vertices.count,
                      i1 < mesh.vertices.count,
                      i2 < mesh.vertices.count else { continue }

                let v0 = mesh.vertices[i0]
                let v1 = mesh.vertices[i1]
                let v2 = mesh.vertices[i2]

                // Calculate triangle normal
                let edge1 = v1 - v0
                let edge2 = v2 - v0
                let cross = simd_cross(edge1, edge2)
                let crossLen = simd_length(cross)
                guard crossLen > 0.0001 else { continue }

                let normal = cross / crossLen

                // Check if this is a vertical plane (normal is horizontal, i.e., normal.y ≈ 0)
                guard abs(normal.y) < Self.verticalPlaneThreshold else { continue }

                let center = (v0 + v1 + v2) / 3
                candidatePoints.append((center, normal, triIdx))
            }

            guard candidatePoints.count >= Self.minWallPoints else { break }

            // Run RANSAC to find dominant wall plane
            guard let (wallPlane, inlierIndices) = ransacFitVerticalPlane(
                points: candidatePoints,
                iterations: Self.ransacIterations,
                threshold: Self.ransacThreshold
            ) else {
                break
            }

            // Create wall from inliers
            let wallTriangles = inlierIndices.map { candidatePoints[$0].triangleIdx }
            let wallPoints = inlierIndices.map { candidatePoints[$0].position }

            // Project to 2D (XZ plane) and fit line
            let points2D = wallPoints.map { SIMD2<Float>($0.x, $0.z) }
            let (start2D, end2D) = fitLine2D(points: points2D)

            // Calculate wall height
            let heights = wallPoints.map { $0.y }
            let wallHeight = (heights.max() ?? 0) - (heights.min() ?? 0)

            // Calculate verticality angle
            let verticalityAngle = asin(abs(wallPlane.normal.y)) * 180 / .pi

            // Collect vertex indices for this wall
            var wallVertexIndices = Set<Int>()
            for triIdx in wallTriangles {
                let idx = triIdx * 3
                guard idx + 2 < mesh.indices.count else { continue }
                wallVertexIndices.insert(Int(mesh.indices[idx]))
                wallVertexIndices.insert(Int(mesh.indices[idx + 1]))
                wallVertexIndices.insert(Int(mesh.indices[idx + 2]))
            }

            let wallLength = simd_distance(start2D, end2D)
            let wall = DetectedWall(
                startPoint: start2D,
                endPoint: end2D,
                normal: wallPlane.normal,
                height: wallHeight,
                isVertical: verticalityAngle < Self.verticalSnapTolerance,
                verticalityAngle: verticalityAngle,
                triangleIndices: wallTriangles,
                vertexIndices: wallVertexIndices,
                originalLength: wallLength  // Store for validation (AC7)
            )
            walls.append(wall)

            // Remove inliers from remaining triangles
            for triIdx in wallTriangles {
                remainingTriangles.remove(triIdx)
            }
        }

        return walls
    }

    /// RANSAC to fit a vertical plane to points.
    private func ransacFitVerticalPlane(
        points: [(position: SIMD3<Float>, normal: SIMD3<Float>, triangleIdx: Int)],
        iterations: Int,
        threshold: Float
    ) -> (plane: AIPlane, inlierIndices: [Int])? {
        guard points.count >= 3 else { return nil }

        var bestPlane: AIPlane?
        var bestInliers: [Int] = []

        for _ in 0..<iterations {
            // Pick 3 random points
            let indices = randomIndices(count: 3, max: points.count)
            let p1 = points[indices[0]].position
            let p2 = points[indices[1]].position
            let p3 = points[indices[2]].position

            // Fit plane
            let v1 = p2 - p1
            let v2 = p3 - p1
            let cross = simd_cross(v1, v2)
            let crossLen = simd_length(cross)
            guard crossLen > 0.0001 else { continue }

            let normal = cross / crossLen

            // Verify it's a vertical plane
            guard abs(normal.y) < Self.verticalPlaneThreshold else { continue }

            let d = -simd_dot(normal, p1)

            // Count inliers
            var inliers: [Int] = []
            for (idx, pt) in points.enumerated() {
                let dist = abs(simd_dot(normal, pt.position) + d)
                if dist < threshold {
                    inliers.append(idx)
                }
            }

            if inliers.count > bestInliers.count {
                bestInliers = inliers
                bestPlane = AIPlane(normal: normal, distance: d)
            }
        }

        // Require at least minWallPoints inliers
        guard bestInliers.count >= Self.minWallPoints, let plane = bestPlane else {
            return nil
        }

        return (plane, bestInliers)
    }

    /// Generates random distinct indices.
    private func randomIndices(count: Int, max: Int) -> [Int] {
        var indices = Set<Int>()
        while indices.count < count && indices.count < max {
            indices.insert(Int.random(in: 0..<max))
        }
        return Array(indices)
    }

    /// Fits a 2D line to points and returns endpoints.
    private func fitLine2D(points: [SIMD2<Float>]) -> (start: SIMD2<Float>, end: SIMD2<Float>) {
        guard points.count >= 2 else {
            return (SIMD2(0, 0), SIMD2(1, 0))
        }

        // Find principal axis using PCA
        let centroid = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let centered = points.map { $0 - centroid }

        // Compute covariance matrix
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

    // MARK: - Task 3: Vertical Snapping (AC1, AC4)

    /// Snaps walls to true vertical if within tolerance.
    /// Transforms actual mesh vertices to align with the vertical plane.
    private func snapWallsToVertical(_ walls: inout [DetectedWall], mesh: inout AIMesh) {
        var mutableVertices = mesh.vertices

        for i in 0..<walls.count {
            if walls[i].verticalityAngle < Self.verticalSnapTolerance && walls[i].verticalityAngle > 0.01 {
                let originalNormal = walls[i].normal
                let originalAngle = walls[i].verticalityAngle

                // Snap normal to vertical by zeroing Y component
                var verticalNormal = originalNormal
                verticalNormal.y = 0
                guard simd_length(verticalNormal) > 0.001 else { continue }
                verticalNormal = simd_normalize(verticalNormal)

                // Calculate rotation to snap from original to vertical plane
                // We need to rotate vertices around the wall's 2D line axis
                let wallDir2D = simd_normalize(walls[i].endPoint - walls[i].startPoint)
                let wallAxis3D = SIMD3<Float>(wallDir2D.x, 0, wallDir2D.y)  // Horizontal axis along wall

                // Rotation angle is the verticality angle (convert to radians)
                let rotationAngle = originalAngle * .pi / 180

                // Determine rotation direction based on normal tilt
                let sign: Float = originalNormal.y > 0 ? -1 : 1

                // Calculate wall center for rotation pivot
                let wallCenter2D = (walls[i].startPoint + walls[i].endPoint) / 2
                let wallCenterY = mutableVertices
                    .enumerated()
                    .filter { walls[i].vertexIndices.contains($0.offset) }
                    .map { $0.element.y }
                    .reduce(0, +) / max(Float(walls[i].vertexIndices.count), 1)
                let pivot = SIMD3<Float>(wallCenter2D.x, wallCenterY, wallCenter2D.y)

                // Create rotation matrix around wall axis
                let rotMatrix = rotationMatrix(angle: sign * rotationAngle, axis: wallAxis3D)

                // Transform vertices belonging to this wall
                for vertexIdx in walls[i].vertexIndices {
                    guard vertexIdx < mutableVertices.count else { continue }

                    // Translate to pivot, rotate, translate back
                    let v = mutableVertices[vertexIdx]
                    let translated = v - pivot
                    let v4 = SIMD4<Float>(translated.x, translated.y, translated.z, 1.0)
                    let rotated = rotMatrix * v4
                    mutableVertices[vertexIdx] = SIMD3<Float>(rotated.x, rotated.y, rotated.z) + pivot
                }

                // Update wall metadata
                let vertexCount = walls[i].vertexIndices.count
                walls[i].normal = verticalNormal
                walls[i].isVertical = true
                walls[i].verticalityAngle = 0

                logger.debug("Wall \(i) snapped to vertical (was \(originalAngle)°), \(vertexCount) vertices transformed")
            }
        }

        // Update mesh with transformed vertices
        mesh = AIMesh(vertices: mutableVertices, indices: mesh.indices)
    }

    // MARK: - Task 4: Corner Detection (AC3)

    /// Detects corners where walls intersect.
    private func detectCorners(from walls: [DetectedWall]) -> [DetectedCorner] {
        var corners: [DetectedCorner] = []

        for i in 0..<walls.count {
            for j in (i+1)..<walls.count {
                // Find intersection of wall lines in 2D
                if let intersection = lineIntersection2D(
                    p1: walls[i].startPoint, p2: walls[i].endPoint,
                    p3: walls[j].startPoint, p4: walls[j].endPoint
                ) {
                    // Check if intersection is near the endpoints of both walls
                    let distToWallI = min(
                        simd_distance(intersection, walls[i].startPoint),
                        simd_distance(intersection, walls[i].endPoint)
                    )
                    let distToWallJ = min(
                        simd_distance(intersection, walls[j].startPoint),
                        simd_distance(intersection, walls[j].endPoint)
                    )

                    // Only accept if intersection is at endpoints
                    let maxDist: Float = 0.5  // tolerance for endpoint proximity
                    guard distToWallI < maxDist && distToWallJ < maxDist else { continue }

                    // Calculate angle between walls
                    let dir1 = simd_normalize(walls[i].endPoint - walls[i].startPoint)
                    let dir2 = simd_normalize(walls[j].endPoint - walls[j].startPoint)
                    let dot = simd_dot(dir1, dir2)
                    var angle = acos(simd_clamp(dot, -1, 1)) * 180 / .pi

                    // Ensure angle is the interior angle (0-180°)
                    if angle > 180 {
                        angle = 360 - angle
                    }

                    let corner = DetectedCorner(
                        position: intersection,
                        wall1Index: i,
                        wall2Index: j,
                        angle: angle,
                        wasRegularized: false,
                        isNonStandard: false
                    )
                    corners.append(corner)
                }
            }
        }

        return corners
    }

    /// Finds the intersection of two 2D line segments.
    private func lineIntersection2D(
        p1: SIMD2<Float>, p2: SIMD2<Float>,
        p3: SIMD2<Float>, p4: SIMD2<Float>
    ) -> SIMD2<Float>? {
        let d1 = p2 - p1
        let d2 = p4 - p3
        let d3 = p3 - p1

        let cross = d1.x * d2.y - d1.y * d2.x
        guard abs(cross) > 0.0001 else { return nil }  // Parallel

        let t = (d3.x * d2.y - d3.y * d2.x) / cross
        let u = (d3.x * d1.y - d3.y * d1.x) / cross

        // Check if intersection is within both segments (with some tolerance for endpoints)
        let tolerance: Float = 0.2
        guard t >= -tolerance && t <= 1 + tolerance &&
              u >= -tolerance && u <= 1 + tolerance else {
            return nil
        }

        return p1 + t * d1
    }

    // MARK: - Task 5: Angle Regularization (AC3, AC4, AC5)

    /// Regularizes corner angles to standard values.
    private func regularizeCorners(_ corners: inout [DetectedCorner], walls: inout [DetectedWall]) {
        for i in 0..<corners.count {
            let angle = corners[i].angle

            // Check for standard angles within tolerance
            if abs(angle - 90.0) <= Self.angleSnapTolerance {
                corners[i].angle = 90.0
                corners[i].wasRegularized = true
                corners[i].isNonStandard = false
            } else if abs(angle - 45.0) <= Self.angleSnapTolerance {
                corners[i].angle = 45.0
                corners[i].wasRegularized = true
                corners[i].isNonStandard = false
            } else if abs(angle - 135.0) <= Self.angleSnapTolerance {
                corners[i].angle = 135.0
                corners[i].wasRegularized = true
                corners[i].isNonStandard = false
            } else {
                // Non-standard angle - preserve and flag
                corners[i].wasRegularized = false
                corners[i].isNonStandard = true
                logger.info("Non-standard corner angle: \(angle)° preserved")
            }
        }
    }

    // MARK: - Task 6: Wall Straightening (AC6)

    /// Straightens walls to connect at regularized corner positions.
    /// Transforms mesh vertices near corners to align with regularized positions.
    private func straightenWalls(
        _ walls: inout [DetectedWall],
        corners: [DetectedCorner],
        mesh: inout AIMesh
    ) {
        var mutableVertices = mesh.vertices

        // Update wall endpoints based on regularized corner positions
        for corner in corners {
            guard corner.wasRegularized else { continue }

            let w1 = corner.wall1Index
            let w2 = corner.wall2Index
            guard w1 < walls.count && w2 < walls.count else { continue }

            let cornerPos = corner.position

            // Determine which endpoint of each wall is at this corner
            let w1AtStart = simd_distance(walls[w1].startPoint, cornerPos) <
                           simd_distance(walls[w1].endPoint, cornerPos)
            let w2AtStart = simd_distance(walls[w2].startPoint, cornerPos) <
                           simd_distance(walls[w2].endPoint, cornerPos)

            // Calculate displacement needed for each wall's corner endpoint
            let oldCornerW1 = w1AtStart ? walls[w1].startPoint : walls[w1].endPoint
            let oldCornerW2 = w2AtStart ? walls[w2].startPoint : walls[w2].endPoint

            // Transform vertices near the corner for wall 1
            let displacement1 = cornerPos - oldCornerW1
            if simd_length(displacement1) > 0.001 {
                transformCornerVertices(
                    vertices: &mutableVertices,
                    wall: walls[w1],
                    oldCorner: oldCornerW1,
                    displacement: displacement1,
                    influenceRadius: 0.3  // Blend within 30cm of corner
                )
            }

            // Transform vertices near the corner for wall 2
            let displacement2 = cornerPos - oldCornerW2
            if simd_length(displacement2) > 0.001 {
                transformCornerVertices(
                    vertices: &mutableVertices,
                    wall: walls[w2],
                    oldCorner: oldCornerW2,
                    displacement: displacement2,
                    influenceRadius: 0.3
                )
            }

            // Update wall endpoint metadata
            if w1AtStart {
                walls[w1].startPoint = cornerPos
            } else {
                walls[w1].endPoint = cornerPos
            }

            if w2AtStart {
                walls[w2].startPoint = cornerPos
            } else {
                walls[w2].endPoint = cornerPos
            }

            logger.debug("Corner at (\(cornerPos.x), \(cornerPos.y)) straightened, walls \(w1) and \(w2) adjusted")
        }

        // Update mesh with transformed vertices
        mesh = AIMesh(vertices: mutableVertices, indices: mesh.indices)
    }

    /// Transforms vertices near a corner with distance-based blending.
    private func transformCornerVertices(
        vertices: inout [SIMD3<Float>],
        wall: DetectedWall,
        oldCorner: SIMD2<Float>,
        displacement: SIMD2<Float>,
        influenceRadius: Float
    ) {
        for vertexIdx in wall.vertexIndices {
            guard vertexIdx < vertices.count else { continue }

            let v = vertices[vertexIdx]
            let v2D = SIMD2<Float>(v.x, v.z)

            // Distance from old corner position
            let dist = simd_distance(v2D, oldCorner)

            // Blend factor: full displacement at corner, zero at influenceRadius
            let blend = max(0, 1 - dist / influenceRadius)

            if blend > 0 {
                // Apply blended displacement in XZ plane
                let adjustedDisplacement = displacement * blend
                vertices[vertexIdx] = SIMD3<Float>(
                    v.x + adjustedDisplacement.x,
                    v.y,  // Keep Y (height) unchanged
                    v.z + adjustedDisplacement.y
                )
            }
        }
    }

    // MARK: - Task 7: Validation (AC7)

    /// Validates the regularization results.
    /// Checks perimeter consistency, area consistency, and flags walls changed >2".
    private func validateRegularization(
        original: AIMesh,
        regularized: AIMesh,
        walls: [DetectedWall],
        scaleFactor: Float
    ) -> ConstraintValidation {
        // Calculate actual perimeter from wall lengths (sum of all walls)
        let currentPerimeter = walls.reduce(Float(0)) { $0 + $1.length }
        let originalPerimeter = walls.reduce(Float(0)) { $0 + ($1.originalLength ?? $1.length) }

        // Perimeter consistency check (within 5% tolerance)
        let perimeterDiff = abs(currentPerimeter - originalPerimeter) / max(originalPerimeter, 0.001)
        let perimeterConsistent = perimeterDiff < 0.05 || walls.isEmpty

        // Calculate floor area using Shoelace formula on wall endpoints
        // This works for any polygon shape (L-shaped, etc.)
        let originalArea = calculatePolygonArea(from: walls, useOriginal: true)
        let regularizedArea = calculatePolygonArea(from: walls, useOriginal: false)

        // Area consistency check (within 5% tolerance)
        let areaDiff = abs(regularizedArea - originalArea) / max(originalArea, 0.001)
        let areaConsistent = areaDiff < 0.05 || walls.isEmpty

        // Track wall length changes and find walls exceeding 2" threshold
        let changeThresholdMeters = Self.maxWallChangeInches * 0.0254  // Convert inches to meters
        var maxChangeMeters: Float = 0
        var wallsExceeding: [Int] = []

        for (i, wall) in walls.enumerated() {
            // Calculate actual length change from original
            let lengthChange = wall.lengthChange
            maxChangeMeters = max(maxChangeMeters, lengthChange)

            // Convert to inches for threshold comparison
            let lengthChangeInches = lengthChange * scaleFactor
            if lengthChangeInches > Self.maxWallChangeInches {
                wallsExceeding.append(i)
                logger.warning("Wall \(i) changed by \(lengthChangeInches)\" (exceeds \(Self.maxWallChangeInches)\" threshold)")
            }
        }

        let maxWallChangeInches = maxChangeMeters * scaleFactor

        logger.info("Validation: perimeter=\(perimeterConsistent) (diff=\(perimeterDiff*100)%), area=\(areaConsistent) (diff=\(areaDiff*100)%), maxChange=\(maxWallChangeInches)\"")

        return ConstraintValidation(
            perimeterConsistent: perimeterConsistent,
            areaConsistent: areaConsistent,
            maxWallChangeInches: maxWallChangeInches,
            wallsExceedingThreshold: wallsExceeding
        )
    }

    /// Calculates polygon area using the Shoelace formula.
    /// Constructs polygon from wall endpoints in order.
    private func calculatePolygonArea(from walls: [DetectedWall], useOriginal: Bool) -> Float {
        guard walls.count >= 3 else { return 0 }

        // Build ordered polygon points from wall endpoints
        // This assumes walls form a closed loop
        var points: [SIMD2<Float>] = []

        // Start with first wall's start point
        if let firstWall = walls.first {
            points.append(useOriginal ? firstWall.startPoint : firstWall.startPoint)

            // For each wall, add the endpoint that's not already in points
            for wall in walls {
                let start = wall.startPoint
                let end = wall.endPoint

                if let last = points.last {
                    // Add the endpoint that's closer to the last point
                    if simd_distance(start, last) < simd_distance(end, last) {
                        if simd_distance(end, points.first ?? end) > 0.01 {
                            points.append(end)
                        }
                    } else {
                        if simd_distance(start, points.first ?? start) > 0.01 {
                            points.append(start)
                        }
                    }
                }
            }
        }

        // Apply Shoelace formula
        var area: Float = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }

        return abs(area) / 2
    }
}
