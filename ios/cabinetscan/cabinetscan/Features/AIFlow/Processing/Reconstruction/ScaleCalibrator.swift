//
//  ScaleCalibrator.swift
//  cabinetscan
//
//  Created for Story 3.5: Automatic Scale Calibration
//

import Foundation
import Combine
import simd
import os.log

// MARK: - Scale Calibration Errors

enum ScaleCalibrationError: LocalizedError, Equatable {
    case emptyMesh
    case floorDetectionFailed
    case countertopDetectionFailed
    case ceilingDetectionFailed
    case invalidScaleFactor
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptyMesh:
            return "Mesh is empty - cannot calibrate"
        case .floorDetectionFailed:
            return "Failed to detect floor plane"
        case .countertopDetectionFailed:
            return "Failed to detect countertop surface"
        case .ceilingDetectionFailed:
            return "Failed to detect ceiling plane"
        case .invalidScaleFactor:
            return "Calculated scale factor is out of valid range"
        case .cancelled:
            return "Scale calibration was cancelled"
        }
    }
}

// MARK: - Calibration Phase

enum CalibrationPhase: String {
    case idle = "Idle"
    case detectingFloor = "Detecting Floor"
    case detectingCountertop = "Detecting Countertop"
    case calculatingScale = "Calculating Scale"
    case validating = "Validating"
    case detectingCeiling = "Detecting Ceiling (Fallback)"
    case complete = "Complete"
}

// MARK: - Countertop Detection Result

/// Internal result from countertop detection.
struct CountertopDetectionResult {
    /// Height from floor plane in mesh units
    let heightFromFloor: Float

    /// Total surface area of the detected countertop
    let area: Float

    /// Indices of triangles that form this surface
    let triangleIndices: [Int]
}

// MARK: - Horizontal Surface

/// A detected horizontal surface in the mesh.
struct HorizontalSurface {
    /// Height from floor plane in mesh units
    let heightFromFloor: Float

    /// Total surface area
    let area: Float

    /// Triangle indices forming this surface
    let triangleIndices: [Int]
}

// MARK: - Scale Calibrator

/// Calibrates mesh scale using standard US cabinet heights.
///
/// **Algorithm Overview:**
/// 1. Detect floor plane using RANSAC on lowest mesh vertices
/// 2. Detect countertop as the most prominent horizontal surface at ~36" height
/// 3. Calculate scale factor: `36.0 / countertopHeightInMeshUnits`
/// 4. Validate using upper cabinet (~54") and ceiling (96"-108") heights
///
/// **Confidence Levels:**
/// - HIGH: Both upper cabinet and ceiling validation pass
/// - MEDIUM: One validation passes
/// - LOW: No validation passes (may need manual calibration)
///
/// **Usage:**
/// ```swift
/// let calibrator = ScaleCalibrator()
/// let result = try await calibrator.calibrate(fusionResult: fusionResult)
/// let scaledHeight = meshHeight * result.scaleFactor  // Now in inches
/// ```
@MainActor
final class ScaleCalibrator: ObservableObject {

    // MARK: - Constants

    /// Standard US countertop height in inches
    private static let standardCountertopHeight: Float = 36.0

    /// Standard US ceiling height in inches (default assumption for fallback)
    private static let standardCeilingHeight: Float = 96.0

    /// Standard US interior door height in inches (6'8")
    private static let standardDoorHeight: Float = 80.0

    /// Upper cabinet bottom height in inches (18" above counter)
    private static let standardUpperCabinetHeight: Float = 54.0

    /// Minimum ceiling height in inches
    private static let minCeilingHeight: Float = 96.0

    /// Maximum ceiling height in inches
    private static let maxCeilingHeight: Float = 108.0

    /// Tolerance for upper cabinet height validation (inches)
    private static let upperCabinetTolerance: Float = 6.0

    /// Minimum valid scale factor (sanity check)
    private static let minScaleFactor: Float = 0.1

    /// Maximum valid scale factor (sanity check)
    private static let maxScaleFactor: Float = 10.0

    /// RANSAC iterations for plane fitting
    private static let ransacIterations: Int = 100

    /// RANSAC inlier threshold (mesh units)
    private static let ransacThreshold: Float = 0.02

    /// Minimum normal.y for horizontal plane detection
    private static let horizontalThreshold: Float = 0.9

    /// Strict horizontal threshold for countertop detection
    private static let strictHorizontalThreshold: Float = 0.95

    /// Height clustering tolerance (mesh units)
    private static let heightClusterTolerance: Float = 0.02

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current processing phase
    @Published private(set) var currentPhase: CalibrationPhase = .idle

    /// Whether calibration is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "ScaleCalibrator")

    // MARK: - Initialization

    init() {
        logger.info("ScaleCalibrator initialized")
    }

    // MARK: - Main Calibration Entry Point

    /// Calibrates the mesh to real-world scale using standard cabinet heights.
    ///
    /// - Parameter fusionResult: The TSDF fusion result containing the mesh to calibrate
    /// - Returns: Calibration result with scale factor and confidence
    /// - Throws: `ScaleCalibrationError` if calibration fails completely
    func calibrate(fusionResult: TSDFFusionResult) async throws -> ScaleCalibrationResult {
        guard !fusionResult.mesh.isEmpty else {
            throw ScaleCalibrationError.emptyMesh
        }

        logger.info("Starting scale calibration for mesh with \(fusionResult.mesh.vertexCount) vertices, \(fusionResult.mesh.triangleCount) triangles")

        isProcessing = true
        progress = 0.0
        currentPhase = .detectingFloor

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Step 1: Detect floor plane
        try Task.checkCancellation()
        guard let floorPlane = detectFloorPlane(from: fusionResult.mesh) else {
            logger.error("Floor plane detection failed")
            throw ScaleCalibrationError.floorDetectionFailed
        }
        logger.info("Floor plane detected: normal=(\(floorPlane.normal.x), \(floorPlane.normal.y), \(floorPlane.normal.z)), distance=\(floorPlane.distance)")
        progress = 0.2

        // Step 2: Try countertop detection
        currentPhase = .detectingCountertop
        try Task.checkCancellation()
        let countertopResult = detectCountertop(from: fusionResult.mesh, floorPlane: floorPlane)
        progress = 0.5

        if let countertop = countertopResult {
            // Step 3: Calculate scale from countertop
            currentPhase = .calculatingScale
            let scaleFactor = calculateScale(countertopHeight: countertop.heightFromFloor)
            logger.info("Scale factor calculated: \(scaleFactor) (countertop at \(countertop.heightFromFloor) mesh units)")
            progress = 0.7

            // Validate scale factor is reasonable
            guard scaleFactor >= Self.minScaleFactor && scaleFactor <= Self.maxScaleFactor else {
                logger.warning("Scale factor \(scaleFactor) outside valid range [\(Self.minScaleFactor), \(Self.maxScaleFactor)]")
                // Fall through to ceiling fallback
                return try await calibrateWithCeilingFallback(
                    mesh: fusionResult.mesh,
                    floorPlane: floorPlane,
                    startTime: startTime
                )
            }

            // Step 4: Validate calibration
            currentPhase = .validating
            try Task.checkCancellation()
            let validation = validateCalibration(
                mesh: fusionResult.mesh,
                floorPlane: floorPlane,
                scaleFactor: scaleFactor
            )
            progress = 0.9

            let confidenceLevel = determineConfidence(from: validation)
            let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            logger.info("Calibration complete: scaleFactor=\(scaleFactor), confidence=\(String(describing: confidenceLevel)), time=\(processingTimeMs)ms")

            progress = 1.0

            return ScaleCalibrationResult(
                scaleFactor: scaleFactor,
                calibrationMethod: .autoCountertop,
                confidenceLevel: confidenceLevel,
                countertopHeightInches: Self.standardCountertopHeight,
                ceilingHeightInches: validation.ceilingHeightInches,
                floorPlane: floorPlane,
                validationResults: validation,
                processingTimeMs: processingTimeMs
            )
        } else {
            // Fallback: try ceiling detection
            logger.warning("Countertop detection failed, attempting ceiling fallback")
            return try await calibrateWithCeilingFallback(
                mesh: fusionResult.mesh,
                floorPlane: floorPlane,
                startTime: startTime
            )
        }
    }

    // MARK: - Floor Plane Detection (AC2)

    /// Detects the floor plane from the mesh using RANSAC.
    ///
    /// - Parameter mesh: The mesh to analyze
    /// - Returns: The detected floor plane, or nil if detection fails
    func detectFloorPlane(from mesh: AIMesh) -> AIPlane? {
        guard !mesh.vertices.isEmpty else { return nil }

        // Get the lowest 10% of vertices by Y coordinate
        let sortedVertices = mesh.vertices.sorted { $0.y < $1.y }
        let lowestCount = max(3, sortedVertices.count / 10)
        let lowestVertices = Array(sortedVertices.prefix(lowestCount))

        guard lowestVertices.count >= 3 else { return nil }

        // Use RANSAC to fit a plane to the lowest points
        guard let plane = ransacFitPlane(
            points: lowestVertices,
            iterations: Self.ransacIterations,
            threshold: Self.ransacThreshold
        ) else {
            return nil
        }

        // Validate plane is approximately horizontal (normal.y should be close to 1 or -1)
        let absNormalY = abs(plane.normal.y)
        guard absNormalY > Self.horizontalThreshold else {
            logger.warning("Detected floor plane is not horizontal enough: normal.y = \(plane.normal.y)")
            return nil
        }

        // Ensure normal points up (positive Y)
        var floorPlane = plane
        if floorPlane.normal.y < 0 {
            floorPlane.normal = -floorPlane.normal
            floorPlane.distance = -floorPlane.distance
        }

        return floorPlane
    }

    // MARK: - Countertop Detection (AC1)

    /// Detects the countertop surface as the most prominent horizontal surface at counter height.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to analyze
    ///   - floorPlane: The detected floor plane
    /// - Returns: Countertop detection result, or nil if no suitable surface found
    func detectCountertop(from mesh: AIMesh, floorPlane: AIPlane) -> CountertopDetectionResult? {
        // Find all horizontal surfaces
        let surfaces = findHorizontalSurfaces(mesh: mesh, floorPlane: floorPlane)

        guard !surfaces.isEmpty else {
            logger.warning("No horizontal surfaces found in mesh")
            return nil
        }

        // Filter to surfaces in expected countertop height range
        // We don't know the scale yet, so we use relative filtering:
        // - Countertop should be the most prominent horizontal surface
        // - It should NOT be the floor (too low) or ceiling (too high)

        // Find the height range of all surfaces
        let heights = surfaces.map { $0.heightFromFloor }
        guard let minHeight = heights.min(), let maxHeight = heights.max() else {
            return nil
        }

        let heightRange = maxHeight - minHeight
        guard heightRange > 0 else {
            // All surfaces at same height - likely just floor
            return nil
        }

        // Expected countertop ratio: ~36" / 96" ceiling = ~0.375 of total height
        // Allow range of 0.25 to 0.5 of total height
        let minCounterRatio: Float = 0.25
        let maxCounterRatio: Float = 0.5

        // Filter surfaces in the counter height range
        let counterCandidates = surfaces.filter { surface in
            let ratio = (surface.heightFromFloor - minHeight) / heightRange
            return ratio >= minCounterRatio && ratio <= maxCounterRatio
        }

        guard !counterCandidates.isEmpty else {
            logger.warning("No surfaces found in countertop height range")
            return nil
        }

        // Select the largest surface by area as the countertop
        guard let countertop = counterCandidates.max(by: { $0.area < $1.area }) else {
            return nil
        }

        logger.info("Countertop detected: height=\(countertop.heightFromFloor), area=\(countertop.area)")

        return CountertopDetectionResult(
            heightFromFloor: countertop.heightFromFloor,
            area: countertop.area,
            triangleIndices: countertop.triangleIndices
        )
    }

    // MARK: - Scale Factor Calculation (AC3)

    /// Calculates the scale factor from detected countertop height.
    ///
    /// - Parameter countertopHeight: Height of countertop in mesh units
    /// - Returns: Scale factor to convert mesh units to inches
    func calculateScale(countertopHeight: Float) -> Float {
        guard countertopHeight > 0 else { return 1.0 }
        return Self.standardCountertopHeight / countertopHeight
    }

    // MARK: - Validation System (AC4)

    /// Validates the calibration by checking additional reference heights.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to validate against
    ///   - floorPlane: The detected floor plane
    ///   - scaleFactor: The calculated scale factor
    /// - Returns: Validation results with detailed pass/fail for each check
    func validateCalibration(
        mesh: AIMesh,
        floorPlane: AIPlane,
        scaleFactor: Float
    ) -> CalibrationValidation {
        // Find all horizontal surfaces for validation
        let surfaces = findHorizontalSurfaces(mesh: mesh, floorPlane: floorPlane)

        // Check for upper cabinet height (~54")
        let upperCabinetResult = validateUpperCabinetHeight(
            surfaces: surfaces,
            scaleFactor: scaleFactor
        )

        // Check for ceiling height (96"-108")
        let ceilingResult = validateCeilingHeight(
            mesh: mesh,
            floorPlane: floorPlane,
            scaleFactor: scaleFactor
        )

        return CalibrationValidation(
            upperCabinetHeightValid: upperCabinetResult.valid,
            upperCabinetHeightInches: upperCabinetResult.heightInches,
            ceilingHeightValid: ceilingResult.valid,
            ceilingHeightInches: ceilingResult.heightInches
        )
    }

    // MARK: - Ceiling Height Fallback (AC5)

    /// Detects the ceiling plane from the mesh.
    ///
    /// - Parameter mesh: The mesh to analyze
    /// - Returns: The detected ceiling plane, or nil if detection fails
    func detectCeilingPlane(from mesh: AIMesh) -> AIPlane? {
        guard !mesh.vertices.isEmpty else { return nil }

        // Get the highest 10% of vertices by Y coordinate
        let sortedVertices = mesh.vertices.sorted { $0.y > $1.y }
        let highestCount = max(3, sortedVertices.count / 10)
        let highestVertices = Array(sortedVertices.prefix(highestCount))

        guard highestVertices.count >= 3 else { return nil }

        // Use RANSAC to fit a plane to the highest points
        guard let plane = ransacFitPlane(
            points: highestVertices,
            iterations: Self.ransacIterations,
            threshold: Self.ransacThreshold
        ) else {
            return nil
        }

        // Validate plane is approximately horizontal
        let absNormalY = abs(plane.normal.y)
        guard absNormalY > Self.horizontalThreshold else {
            logger.warning("Detected ceiling plane is not horizontal enough: normal.y = \(plane.normal.y)")
            return nil
        }

        // Ensure normal points down (negative Y) for ceiling
        var ceilingPlane = plane
        if ceilingPlane.normal.y > 0 {
            ceilingPlane.normal = -ceilingPlane.normal
            ceilingPlane.distance = -ceilingPlane.distance
        }

        return ceilingPlane
    }

    /// Calibrates using floor-to-ceiling height as fallback.
    ///
    /// - Parameters:
    ///   - floorHeight: Floor plane distance
    ///   - ceilingHeight: Ceiling plane distance
    ///   - assumedCeilingInches: Assumed ceiling height in inches (default 96")
    /// - Returns: Scale factor
    func calibrateFromCeiling(
        floorHeight: Float,
        ceilingHeight: Float,
        assumedCeilingInches: Float = 96.0
    ) -> Float {
        let heightInMeshUnits = abs(ceilingHeight - floorHeight)
        guard heightInMeshUnits > 0 else { return 1.0 }
        return assumedCeilingInches / heightInMeshUnits
    }

    // MARK: - Private Helper Methods

    /// Fits a plane to points using RANSAC algorithm.
    private func ransacFitPlane(
        points: [SIMD3<Float>],
        iterations: Int,
        threshold: Float
    ) -> AIPlane? {
        guard points.count >= 3 else { return nil }

        var bestPlane: AIPlane?
        var bestInlierCount = 0

        for _ in 0..<iterations {
            // Randomly select 3 distinct points
            let indices = randomIndices(count: 3, max: points.count)
            let p1 = points[indices[0]]
            let p2 = points[indices[1]]
            let p3 = points[indices[2]]

            // Compute plane from 3 points
            let v1 = p2 - p1
            let v2 = p3 - p1

            // Skip if points are too close (nearly coincident)
            let v1Length = simd_length(v1)
            let v2Length = simd_length(v2)
            guard v1Length > 0.0001 && v2Length > 0.0001 else { continue }

            // Check for collinearity: cross product magnitude should be significant
            // relative to the edge lengths (area of parallelogram > epsilon)
            let cross = simd_cross(v1, v2)
            let crossLength = simd_length(cross)

            // Skip degenerate/collinear triangles (cross product too small relative to edges)
            let minEdgeProduct = v1Length * v2Length * 0.01  // 1% threshold for near-collinearity
            guard crossLength > max(0.0001, minEdgeProduct) else { continue }

            let normal = cross / crossLength
            let d = -simd_dot(normal, p1)

            // Count inliers
            var inlierCount = 0
            for point in points {
                let dist = abs(simd_dot(normal, point) + d)
                if dist < threshold {
                    inlierCount += 1
                }
            }

            // Keep best plane
            if inlierCount > bestInlierCount {
                bestInlierCount = inlierCount
                bestPlane = AIPlane(normal: normal, distance: d)
            }
        }

        // Require at least 50% inliers for a valid plane
        guard bestInlierCount >= points.count / 2 else {
            return nil
        }

        return bestPlane
    }

    /// Generates random distinct indices.
    private func randomIndices(count: Int, max: Int) -> [Int] {
        var indices = Set<Int>()
        while indices.count < count {
            indices.insert(Int.random(in: 0..<max))
        }
        return Array(indices)
    }

    /// Finds all horizontal surfaces in the mesh.
    private func findHorizontalSurfaces(
        mesh: AIMesh,
        floorPlane: AIPlane
    ) -> [HorizontalSurface] {
        guard mesh.triangleCount > 0 else { return [] }

        // Group triangles by approximate height and horizontal orientation
        var heightGroups: [Int: (area: Float, triangles: [Int])] = [:]

        for i in 0..<mesh.triangleCount {
            let idx = i * 3
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
            let crossLength = simd_length(cross)

            guard crossLength > 0.0001 else { continue }

            let normal = cross / crossLength

            // Check if triangle is horizontal (normal points up)
            guard abs(normal.y) > Self.strictHorizontalThreshold else { continue }

            // Calculate triangle center height relative to floor
            let centerY = (v0.y + v1.y + v2.y) / 3.0
            let heightFromFloor = distanceFromPlane(point: SIMD3<Float>(0, centerY, 0), plane: floorPlane)

            // Skip surfaces below floor (negative height)
            guard heightFromFloor > 0 else { continue }

            // Calculate triangle area
            let area = crossLength / 2.0

            // Group by height bucket
            let heightBucket = Int(heightFromFloor / Self.heightClusterTolerance)

            if var group = heightGroups[heightBucket] {
                group.area += area
                group.triangles.append(i)
                heightGroups[heightBucket] = group
            } else {
                heightGroups[heightBucket] = (area: area, triangles: [i])
            }
        }

        // Convert to HorizontalSurface array
        return heightGroups.map { bucket, data in
            HorizontalSurface(
                heightFromFloor: Float(bucket) * Self.heightClusterTolerance,
                area: data.area,
                triangleIndices: data.triangles
            )
        }.sorted { $0.area > $1.area }  // Sort by area (largest first)
    }

    /// Calculates distance from a point to a plane.
    private func distanceFromPlane(point: SIMD3<Float>, plane: AIPlane) -> Float {
        return simd_dot(plane.normal, point) + plane.distance
    }

    /// Validates upper cabinet height.
    private func validateUpperCabinetHeight(
        surfaces: [HorizontalSurface],
        scaleFactor: Float
    ) -> (valid: Bool, heightInches: Float?) {
        // Look for a surface at approximately 54" (upper cabinet bottom)
        for surface in surfaces {
            let heightInches = surface.heightFromFloor * scaleFactor
            let expectedHeight = Self.standardUpperCabinetHeight

            if abs(heightInches - expectedHeight) <= Self.upperCabinetTolerance {
                return (true, heightInches)
            }
        }
        return (false, nil)
    }

    /// Validates ceiling height.
    private func validateCeilingHeight(
        mesh: AIMesh,
        floorPlane: AIPlane,
        scaleFactor: Float
    ) -> (valid: Bool, heightInches: Float?) {
        // Find the highest point in the mesh
        guard let maxY = mesh.vertices.map({ $0.y }).max() else {
            return (false, nil)
        }

        let ceilingHeightMeshUnits = distanceFromPlane(
            point: SIMD3<Float>(0, maxY, 0),
            plane: floorPlane
        )
        let ceilingHeightInches = ceilingHeightMeshUnits * scaleFactor

        let valid = ceilingHeightInches >= Self.minCeilingHeight &&
                    ceilingHeightInches <= Self.maxCeilingHeight

        return (valid, ceilingHeightInches)
    }

    /// Determines confidence level from validation results.
    private func determineConfidence(from validation: CalibrationValidation) -> AIConfidenceLevel {
        switch validation.passedChecks {
        case 2:
            return .high
        case 1:
            return .medium
        default:
            return .low
        }
    }

    // MARK: - Manual Calibration Methods (Story 3.6)

    /// Calibrates using manual door width selection.
    ///
    /// When automatic calibration fails, user can select a standard door width
    /// (30", 32", or 36"). Since detecting door width in the mesh is complex,
    /// we use the standard door HEIGHT (80") as the reference dimension.
    ///
    /// The scale is calculated by:
    /// 1. Measuring floor-to-ceiling distance in mesh units
    /// 2. Assuming door occupies ~83% of ceiling height (80"/96" standard)
    /// 3. Applying scale: standardDoorHeight / (meshCeilingHeight * 0.833)
    ///
    /// This produces different results from ceiling calibration, making the
    /// door vs ceiling choice meaningful to users.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to calibrate
    ///   - floorPlane: Already-detected floor plane
    ///   - selectedWidthInches: User-selected door width in inches (for metadata)
    ///   - failureReason: Why auto-calibration failed (for metadata)
    /// - Returns: Calibration result with MEDIUM confidence
    /// - Throws: `ScaleCalibrationError` if calibration fails
    func calibrateManualDoor(
        mesh: AIMesh,
        floorPlane: AIPlane,
        selectedWidthInches: Float,
        failureReason: String
    ) async throws -> ScaleCalibrationResult {
        guard !mesh.isEmpty else {
            throw ScaleCalibrationError.emptyMesh
        }

        logger.info("Starting manual door calibration with width: \(selectedWidthInches)\"")

        let startTime = CFAbsoluteTimeGetCurrent()
        isProcessing = true
        currentPhase = .detectingCeiling
        progress = 0.2

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Detect ceiling to get room height
        guard let ceilingPlane = detectCeilingPlane(from: mesh) else {
            logger.error("Ceiling detection failed during manual door calibration")
            throw ScaleCalibrationError.ceilingDetectionFailed
        }

        progress = 0.5

        // Calculate floor-to-ceiling distance in mesh units
        let floorY = -floorPlane.distance / floorPlane.normal.y
        let ceilingY = -ceilingPlane.distance / ceilingPlane.normal.y
        let roomHeightInMeshUnits = abs(ceilingY - floorY)

        // For door calibration, assume door height is 80" (standard US door)
        // Standard door is ~83.3% of an 8' ceiling (80/96)
        // We estimate door height in mesh units as: roomHeight * (80/96)
        let doorHeightRatio: Float = Self.standardDoorHeight / Self.standardCeilingHeight
        let estimatedDoorHeightInMeshUnits = roomHeightInMeshUnits * doorHeightRatio

        // Scale factor converts mesh units to inches using door height as reference
        let scaleFactor = Self.standardDoorHeight / estimatedDoorHeightInMeshUnits

        logger.info("Manual door calibration: room height=\(roomHeightInMeshUnits) mesh units, door width=\(selectedWidthInches)\", scale=\(scaleFactor)")

        progress = 0.8

        // Validate scale factor is reasonable
        guard scaleFactor >= Self.minScaleFactor && scaleFactor <= Self.maxScaleFactor else {
            logger.error("Manual door scale factor \(scaleFactor) outside valid range")
            throw ScaleCalibrationError.invalidScaleFactor
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        // Calculate implied ceiling height for validation
        let impliedCeilingHeight = roomHeightInMeshUnits * scaleFactor

        // Manual calibration always returns MEDIUM confidence
        var result = ScaleCalibrationResult(
            scaleFactor: scaleFactor,
            calibrationMethod: .manualDoor,
            confidenceLevel: .medium,
            countertopHeightInches: nil,
            ceilingHeightInches: impliedCeilingHeight,
            floorPlane: floorPlane,
            validationResults: CalibrationValidation(
                upperCabinetHeightValid: false,
                upperCabinetHeightInches: nil,
                ceilingHeightValid: impliedCeilingHeight >= Self.minCeilingHeight && impliedCeilingHeight <= Self.maxCeilingHeight,
                ceilingHeightInches: impliedCeilingHeight
            ),
            processingTimeMs: processingTimeMs
        )
        result.autoCalibrationFailureReason = failureReason

        logger.info("Manual door calibration complete: scaleFactor=\(scaleFactor), impliedCeiling=\(impliedCeilingHeight)\", time=\(processingTimeMs)ms")

        return result
    }

    /// Calibrates using manual ceiling height selection.
    ///
    /// User selects their ceiling height (8', 9', or 10'). The scale is
    /// calculated by measuring the floor-to-ceiling distance in mesh units
    /// and dividing by the selected height in inches.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to calibrate
    ///   - floorPlane: Already-detected floor plane
    ///   - selectedHeightInches: User-selected ceiling height in inches
    ///   - failureReason: Why auto-calibration failed (for metadata)
    /// - Returns: Calibration result with MEDIUM confidence
    /// - Throws: `ScaleCalibrationError` if calibration fails
    func calibrateManualCeiling(
        mesh: AIMesh,
        floorPlane: AIPlane,
        selectedHeightInches: Float,
        failureReason: String
    ) async throws -> ScaleCalibrationResult {
        guard !mesh.isEmpty else {
            throw ScaleCalibrationError.emptyMesh
        }

        logger.info("Starting manual ceiling calibration with height: \(selectedHeightInches)\"")

        let startTime = CFAbsoluteTimeGetCurrent()
        isProcessing = true
        currentPhase = .detectingCeiling
        progress = 0.2

        defer {
            isProcessing = false
            currentPhase = .complete
        }

        // Detect ceiling plane
        guard let ceilingPlane = detectCeilingPlane(from: mesh) else {
            logger.error("Ceiling detection failed during manual ceiling calibration")
            throw ScaleCalibrationError.ceilingDetectionFailed
        }

        progress = 0.5

        // Calculate floor-to-ceiling distance in mesh units
        let floorY = -floorPlane.distance / floorPlane.normal.y
        let ceilingY = -ceilingPlane.distance / ceilingPlane.normal.y
        let heightInMeshUnits = abs(ceilingY - floorY)

        // Calculate scale using user-selected ceiling height
        let scaleFactor = selectedHeightInches / heightInMeshUnits

        logger.info("Manual ceiling calibration: distance=\(heightInMeshUnits) mesh units, selected=\(selectedHeightInches)\", scale=\(scaleFactor)")

        progress = 0.8

        // Validate scale factor is reasonable
        guard scaleFactor >= Self.minScaleFactor && scaleFactor <= Self.maxScaleFactor else {
            logger.error("Manual ceiling scale factor \(scaleFactor) outside valid range")
            throw ScaleCalibrationError.invalidScaleFactor
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        // Manual calibration always returns MEDIUM confidence
        var result = ScaleCalibrationResult(
            scaleFactor: scaleFactor,
            calibrationMethod: .manualCeiling,
            confidenceLevel: .medium,
            countertopHeightInches: nil,
            ceilingHeightInches: selectedHeightInches,
            floorPlane: floorPlane,
            validationResults: CalibrationValidation(
                upperCabinetHeightValid: false,
                upperCabinetHeightInches: nil,
                ceilingHeightValid: true,
                ceilingHeightInches: selectedHeightInches
            ),
            processingTimeMs: processingTimeMs
        )
        result.autoCalibrationFailureReason = failureReason

        logger.info("Manual ceiling calibration complete: scaleFactor=\(scaleFactor), time=\(processingTimeMs)ms")

        return result
    }

    // MARK: - Private Helper Methods

    /// Fallback calibration using ceiling height.
    private func calibrateWithCeilingFallback(
        mesh: AIMesh,
        floorPlane: AIPlane,
        startTime: CFAbsoluteTime
    ) async throws -> ScaleCalibrationResult {
        currentPhase = .detectingCeiling
        progress = 0.6

        try Task.checkCancellation()

        // Detect ceiling
        guard let ceilingPlane = detectCeilingPlane(from: mesh) else {
            logger.error("Ceiling detection also failed - calibration cannot proceed")
            let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            // Return failed result
            return ScaleCalibrationResult(
                scaleFactor: 1.0,
                calibrationMethod: .failed,
                confidenceLevel: .low,
                countertopHeightInches: nil,
                ceilingHeightInches: nil,
                floorPlane: floorPlane,
                validationResults: .empty,
                processingTimeMs: processingTimeMs
            )
        }

        // Calculate floor-to-ceiling distance
        let floorY = -floorPlane.distance / floorPlane.normal.y
        let ceilingY = -ceilingPlane.distance / ceilingPlane.normal.y
        let heightInMeshUnits = abs(ceilingY - floorY)

        // Calculate scale using assumed 96" ceiling
        let scaleFactor = calibrateFromCeiling(
            floorHeight: floorY,
            ceilingHeight: ceilingY,
            assumedCeilingInches: Self.standardCeilingHeight
        )

        logger.info("Ceiling fallback: floor-ceiling distance = \(heightInMeshUnits) mesh units, scale = \(scaleFactor)")

        // Validate scale factor
        guard scaleFactor >= Self.minScaleFactor && scaleFactor <= Self.maxScaleFactor else {
            logger.error("Ceiling-based scale factor \(scaleFactor) outside valid range")
            let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            return ScaleCalibrationResult(
                scaleFactor: 1.0,
                calibrationMethod: .failed,
                confidenceLevel: .low,
                countertopHeightInches: nil,
                ceilingHeightInches: nil,
                floorPlane: floorPlane,
                validationResults: .empty,
                processingTimeMs: processingTimeMs
            )
        }

        progress = 0.8

        // Validate (limited validation since we used ceiling for scale)
        currentPhase = .validating
        let validation = CalibrationValidation(
            upperCabinetHeightValid: false,
            upperCabinetHeightInches: nil,
            ceilingHeightValid: true,  // By definition, since we used ceiling
            ceilingHeightInches: Self.standardCeilingHeight
        )

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        // Return with lower confidence (medium at best, since ceiling-based is less reliable)
        return ScaleCalibrationResult(
            scaleFactor: scaleFactor,
            calibrationMethod: .autoCeiling,  // Automatic ceiling-based calibration
            confidenceLevel: .medium,
            countertopHeightInches: nil,
            ceilingHeightInches: Self.standardCeilingHeight,
            floorPlane: floorPlane,
            validationResults: validation,
            processingTimeMs: processingTimeMs
        )
    }
}
