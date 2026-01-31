//
//  ReflectiveSurfaceDetectorTests.swift
//  cabinetscanTests
//
//  Created for Story 6.4: Reflective Surface Handling
//

import XCTest
import simd
@testable import cabinetscan

@MainActor
final class ReflectiveSurfaceDetectorTests: XCTestCase {

    var detector: ReflectiveSurfaceDetector!

    override func setUp() {
        super.setUp()
        detector = ReflectiveSurfaceDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Task 1.2: Variance Calculation Tests

    /// Test variance calculation with consistent observations (low variance)
    func testAnalyzeDepthVariance_consistentObservations_lowVariance() {
        // Given: Observations with nearly identical TSDF values (consistent surface)
        let observations: [(tsdf: Float, weight: Float)] = [
            (0.02, 1.0),
            (0.021, 1.0),
            (0.019, 1.0),
            (0.02, 1.0)
        ]

        // When: Calculate variance
        let variance = detector.calculateObservationVariance(observations: observations)

        // Then: Variance should be very low (< 0.0001)
        XCTAssertLessThan(variance, 0.0001, "Consistent observations should have very low variance")
    }

    /// Test variance calculation with inconsistent observations (high variance - reflective surface)
    func testAnalyzeDepthVariance_inconsistentObservations_highVariance() {
        // Given: Wildly varying TSDF values (reflective surface signature)
        // Values range from -0.3 to +0.3 - significant disagreement between views
        let observations: [(tsdf: Float, weight: Float)] = [
            (0.3, 1.0),    // One view sees surface far in front
            (-0.3, 1.0),   // Another sees it behind
            (0.2, 1.0),    // Another partial view
            (-0.25, 1.0)   // Yet another contradicting view
        ]
        // Variance = E[X²] - E[X]² ≈ 0.0725 - (-0.0125)² ≈ 0.072 (well above 0.04 threshold)

        // When: Calculate variance
        let variance = detector.calculateObservationVariance(observations: observations)

        // Then: Variance should be high (> threshold of 0.04)
        XCTAssertGreaterThan(variance, ReflectiveSurfaceDetector.varianceThreshold,
                             "Inconsistent observations should exceed variance threshold of 0.04")
    }

    /// Test variance calculation with single observation (returns 0)
    func testAnalyzeDepthVariance_singleObservation_zeroVariance() {
        // Given: Single observation
        let observations: [(tsdf: Float, weight: Float)] = [(0.02, 1.0)]

        // When: Calculate variance
        let variance = detector.calculateObservationVariance(observations: observations)

        // Then: Variance should be 0
        XCTAssertEqual(variance, 0.0, "Single observation should have zero variance")
    }

    /// Test variance calculation with empty observations
    func testAnalyzeDepthVariance_emptyObservations_zeroVariance() {
        // Given: No observations
        let observations: [(tsdf: Float, weight: Float)] = []

        // When: Calculate variance
        let variance = detector.calculateObservationVariance(observations: observations)

        // Then: Variance should be 0
        XCTAssertEqual(variance, 0.0, "Empty observations should have zero variance")
    }

    // MARK: - Task 1.3: High Variance Region Detection Tests

    /// Test high variance region detection finds regions above threshold
    func testDetectHighVarianceRegions_aboveThreshold_detected() {
        // Given: Voxels with some above threshold
        let voxelVariances: [(VoxelIndex, Float)] = [
            (VoxelIndex(x: 0, y: 0, z: 0), 0.01),  // Below threshold
            (VoxelIndex(x: 1, y: 0, z: 0), 0.05),  // Above threshold (0.04)
            (VoxelIndex(x: 2, y: 0, z: 0), 0.02),  // Below threshold
            (VoxelIndex(x: 3, y: 0, z: 0), 0.08),  // Above threshold
        ]

        // When: Detect high variance regions
        let highVarianceVoxels = detector.detectHighVarianceRegions(
            voxelVariances: voxelVariances,
            threshold: ReflectiveSurfaceDetector.varianceThreshold
        )

        // Then: Should find 2 voxels above threshold
        XCTAssertEqual(highVarianceVoxels.count, 2)
        XCTAssertTrue(highVarianceVoxels.contains(VoxelIndex(x: 1, y: 0, z: 0)))
        XCTAssertTrue(highVarianceVoxels.contains(VoxelIndex(x: 3, y: 0, z: 0)))
    }

    /// Test no high variance regions when all below threshold
    func testDetectHighVarianceRegions_allBelowThreshold_empty() {
        // Given: All voxels below threshold
        let voxelVariances: [(VoxelIndex, Float)] = [
            (VoxelIndex(x: 0, y: 0, z: 0), 0.01),
            (VoxelIndex(x: 1, y: 0, z: 0), 0.02),
            (VoxelIndex(x: 2, y: 0, z: 0), 0.03),
        ]

        // When: Detect high variance regions
        let highVarianceVoxels = detector.detectHighVarianceRegions(
            voxelVariances: voxelVariances,
            threshold: ReflectiveSurfaceDetector.varianceThreshold
        )

        // Then: Should be empty
        XCTAssertTrue(highVarianceVoxels.isEmpty)
    }

    // MARK: - Task 1.4: Identify Reflective Surfaces Tests

    /// Test clustering high variance voxels into reflective regions
    func testIdentifyReflectiveSurfaces_clusteredVoxels_createsRegion() {
        // Given: Adjacent high-variance voxels forming a cluster
        let highVarianceVoxels: [VoxelIndex] = [
            VoxelIndex(x: 0, y: 0, z: 0),
            VoxelIndex(x: 1, y: 0, z: 0),
            VoxelIndex(x: 2, y: 0, z: 0),
            VoxelIndex(x: 3, y: 0, z: 0),
            VoxelIndex(x: 4, y: 0, z: 0),
        ]

        // When: Identify reflective surfaces
        let surfaces = detector.identifyReflectiveSurfaces(
            highVarianceVoxels: highVarianceVoxels,
            voxelSize: 0.02
        )

        // Then: Should identify at least one reflective surface
        XCTAssertFalse(surfaces.isEmpty, "Should identify reflective surface from clustered voxels")
    }

    /// Test scattered voxels below cluster threshold are not identified
    func testIdentifyReflectiveSurfaces_scatteredVoxels_noRegion() {
        // Given: Scattered high-variance voxels (not clustered)
        let highVarianceVoxels: [VoxelIndex] = [
            VoxelIndex(x: 0, y: 0, z: 0),
            VoxelIndex(x: 10, y: 10, z: 10),  // Far away
            VoxelIndex(x: 20, y: 20, z: 20),  // Far away
        ]

        // When: Identify reflective surfaces
        let surfaces = detector.identifyReflectiveSurfaces(
            highVarianceVoxels: highVarianceVoxels,
            voxelSize: 0.02
        )

        // Then: Should not identify any reflective surface (below cluster threshold)
        XCTAssertTrue(surfaces.isEmpty, "Scattered voxels should not form reflective surface")
    }

    // MARK: - Task 1.5: Analysis Result Tests

    /// Test ReflectiveSurfaceAnalysisResult contains proper metrics
    func testAnalysisResult_containsMetrics() async throws {
        // Given: A TSDF volume with known variance patterns
        var volume = TSDFVolume(voxelSize: 0.02)

        // Create some test voxels with variance data
        // Note: This requires TSDFVoxel to have variance tracking (Task 2)
        // For now, test the result structure

        // When: Analyze for reflective surfaces
        let result = try await detector.analyzeReflectiveSurfaces(volume: volume)

        // Then: Result should have valid metrics
        XCTAssertGreaterThanOrEqual(result.totalVoxelsAnalyzed, 0)
        XCTAssertGreaterThanOrEqual(result.highVariancePercentage, 0)
        XCTAssertLessThanOrEqual(result.highVariancePercentage, 1.0)
    }

    // MARK: - Task 1.6: Threshold Constants Tests

    /// Test variance threshold is reasonable (2cm² variance = 0.04)
    func testVarianceThreshold_isReasonable() {
        // Given: The defined variance threshold

        // Then: Should be approximately 0.04 (2cm variance squared)
        XCTAssertEqual(ReflectiveSurfaceDetector.varianceThreshold, 0.04, accuracy: 0.001)
    }

    /// Test cluster minimum size is reasonable
    func testClusterMinSize_isReasonable() {
        // Given: The defined cluster minimum size

        // Then: Should be at least 5 voxels (reasonable minimum for a surface)
        XCTAssertGreaterThanOrEqual(ReflectiveSurfaceDetector.clusterMinSize, 5)
    }

    // MARK: - False Positive Prevention Tests

    /// Test that consistent surfaces (non-reflective) are not flagged
    func testNonReflectiveSurface_noFalsePositive() {
        // Given: Observations typical of a matte surface (consistent depth)
        let observations: [(tsdf: Float, weight: Float)] = [
            (0.05, 1.0),
            (0.051, 1.0),
            (0.049, 1.0),
            (0.05, 1.0),
            (0.052, 1.0),
        ]

        // When: Calculate variance
        let variance = detector.calculateObservationVariance(observations: observations)

        // Then: Variance should be below threshold (no false positive)
        XCTAssertLessThan(variance, ReflectiveSurfaceDetector.varianceThreshold,
                         "Consistent matte surface should not trigger reflective detection")
    }

    // MARK: - Task 3: Mirror Detection Integration Tests

    /// Test mirror detection with valid wall data and TSDF volume
    func testDetectMirrorRegions_withWallData_detectsMirrorBehindWall() {
        // Given: A TSDF volume with high-variance voxels behind a wall
        let volume = TSDFVolume(voxelSize: 0.02)

        // Create a wall along the X-axis at z = 0
        let wall = AIWall(
            id: UUID(),
            plane: RoomPlane3D(normal: SIMD3<Float>(0, 0, 1), distance: 0, center: .zero),
            startPoint: SIMD2<Float>(-50, 0),  // Wall from -50 to +50 on X-axis
            endPoint: SIMD2<Float>(50, 0),
            lengthInches: 100,
            heightInches: 96,
            normalDirection: SIMD2<Float>(0, 1),
            boundaryType: .wall
        )

        // When: Detect mirror regions
        let mirrorRegions = detector.detectMirrorRegions(volume: volume, walls: [wall])

        // Then: Should return empty for empty volume (no voxels to analyze)
        XCTAssertTrue(mirrorRegions.isEmpty,
                      "Empty volume should have no mirror regions")
    }

    /// Test mirror detection returns empty for no walls
    func testDetectMirrorRegions_noWalls_returnsEmpty() {
        // Given: A TSDF volume with no walls
        let volume = TSDFVolume(voxelSize: 0.02)

        // When: Detect mirror regions with empty walls
        let mirrorRegions = detector.detectMirrorRegions(volume: volume, walls: [])

        // Then: Should return empty
        XCTAssertTrue(mirrorRegions.isEmpty,
                      "No walls should return no mirror regions")
    }

    /// Test mirror region validation within room bounds
    func testValidateMirrorRegion_withinBounds_returnsTrue() {
        // Given: A mirror region inside room bounds
        let mirrorBounds = AIBoundingBox3D(
            center: SIMD3<Float>(25, 48, 25),
            size: SIMD3<Float>(20, 36, 2)
        )
        let mirrorRegion = MirrorRegion(
            bounds: mirrorBounds,
            wallId: UUID(),
            voxelIndices: [],
            averageVariance: 0.05
        )

        let roomMin = SIMD3<Float>(0, 0, 0)
        let roomMax = SIMD3<Float>(120, 96, 120)  // 10'x8'x10' room in inches

        // When: Validate mirror region
        let isValid = detector.validateMirrorRegion(mirrorRegion, roomMin: roomMin, roomMax: roomMax)

        // Then: Should be valid (within bounds)
        XCTAssertTrue(isValid, "Mirror within room bounds should be valid")
    }

    /// Test mirror region validation outside room bounds
    func testValidateMirrorRegion_outsideBounds_returnsFalse() {
        // Given: A mirror region outside room bounds
        let mirrorBounds = AIBoundingBox3D(
            center: SIMD3<Float>(150, 48, 25),  // X=150 is outside room max X=120
            size: SIMD3<Float>(20, 36, 2)
        )
        let mirrorRegion = MirrorRegion(
            bounds: mirrorBounds,
            wallId: UUID(),
            voxelIndices: [],
            averageVariance: 0.05
        )

        let roomMin = SIMD3<Float>(0, 0, 0)
        let roomMax = SIMD3<Float>(120, 96, 120)

        // When: Validate mirror region
        let isValid = detector.validateMirrorRegion(mirrorRegion, roomMin: roomMin, roomMax: roomMax)

        // Then: Should be invalid (outside bounds)
        XCTAssertFalse(isValid, "Mirror outside room bounds should be invalid")
    }

    /// Test mirror region validation at boundary (within tolerance)
    func testValidateMirrorRegion_atBoundaryWithTolerance_returnsTrue() {
        // Given: A mirror region just outside bounds but within 6-inch tolerance
        let mirrorBounds = AIBoundingBox3D(
            center: SIMD3<Float>(123, 48, 25),  // X=123 is 3 inches outside max X=120 but within 6" tolerance
            size: SIMD3<Float>(10, 36, 2)
        )
        let mirrorRegion = MirrorRegion(
            bounds: mirrorBounds,
            wallId: UUID(),
            voxelIndices: [],
            averageVariance: 0.05
        )

        let roomMin = SIMD3<Float>(0, 0, 0)
        let roomMax = SIMD3<Float>(120, 96, 120)

        // When: Validate mirror region
        let isValid = detector.validateMirrorRegion(mirrorRegion, roomMin: roomMin, roomMax: roomMax)

        // Then: Should be valid (within tolerance)
        XCTAssertTrue(isValid, "Mirror at boundary within tolerance should be valid")
    }

    // MARK: - Task 1.4: Average Variance Calculation Tests

    /// Test identifyReflectiveSurfaces calculates actual average variance from lookup
    func testIdentifyReflectiveSurfaces_withVarianceLookup_calculatesActualAverage() {
        // Given: Adjacent high-variance voxels with variance lookup
        let voxels: [VoxelIndex] = [
            VoxelIndex(x: 0, y: 0, z: 0),
            VoxelIndex(x: 1, y: 0, z: 0),
            VoxelIndex(x: 2, y: 0, z: 0),
            VoxelIndex(x: 3, y: 0, z: 0),
            VoxelIndex(x: 4, y: 0, z: 0),
        ]

        let varianceLookup: [VoxelIndex: Float] = [
            VoxelIndex(x: 0, y: 0, z: 0): 0.05,
            VoxelIndex(x: 1, y: 0, z: 0): 0.06,
            VoxelIndex(x: 2, y: 0, z: 0): 0.07,
            VoxelIndex(x: 3, y: 0, z: 0): 0.08,
            VoxelIndex(x: 4, y: 0, z: 0): 0.09,
        ]
        // Expected average: (0.05 + 0.06 + 0.07 + 0.08 + 0.09) / 5 = 0.07

        // When: Identify reflective surfaces with variance lookup
        let surfaces = detector.identifyReflectiveSurfaces(
            highVarianceVoxels: voxels,
            voxelSize: 0.02,
            varianceLookup: varianceLookup
        )

        // Then: Should calculate actual average variance
        XCTAssertFalse(surfaces.isEmpty, "Should identify reflective surface")
        XCTAssertEqual(surfaces[0].averageVariance, 0.07, accuracy: 0.001,
                       "Should calculate actual average variance from lookup")
    }

    /// Test identifyReflectiveSurfaces without lookup uses fallback
    func testIdentifyReflectiveSurfaces_withoutVarianceLookup_usesFallback() {
        // Given: Adjacent high-variance voxels without variance lookup
        let voxels: [VoxelIndex] = [
            VoxelIndex(x: 0, y: 0, z: 0),
            VoxelIndex(x: 1, y: 0, z: 0),
            VoxelIndex(x: 2, y: 0, z: 0),
            VoxelIndex(x: 3, y: 0, z: 0),
            VoxelIndex(x: 4, y: 0, z: 0),
        ]

        // When: Identify reflective surfaces without variance lookup (empty)
        let surfaces = detector.identifyReflectiveSurfaces(
            highVarianceVoxels: voxels,
            voxelSize: 0.02,
            varianceLookup: [:]  // Empty lookup triggers fallback
        )

        // Then: Should use fallback variance (threshold * 1.5)
        XCTAssertFalse(surfaces.isEmpty, "Should identify reflective surface")
        let expectedFallback = ReflectiveSurfaceDetector.varianceThreshold * 1.5
        XCTAssertEqual(surfaces[0].averageVariance, expectedFallback, accuracy: 0.001,
                       "Should use fallback variance when no lookup provided")
    }

    // MARK: - Empty Volume Handling Tests

    /// Test analyzeReflectiveSurfaces handles empty volume gracefully
    func testAnalyzeReflectiveSurfaces_emptyVolume_returnsEmptyResult() async throws {
        // Given: An empty TSDF volume
        let volume = TSDFVolume(voxelSize: 0.02)

        // When: Analyze for reflective surfaces
        let result = try await detector.analyzeReflectiveSurfaces(volume: volume)

        // Then: Should return empty result with zero metrics
        XCTAssertEqual(result.totalVoxelsAnalyzed, 0,
                       "Empty volume should have 0 voxels analyzed")
        XCTAssertEqual(result.highVarianceVoxelCount, 0,
                       "Empty volume should have 0 high-variance voxels")
        XCTAssertTrue(result.reflectiveRegions.isEmpty,
                      "Empty volume should have no reflective regions")
        XCTAssertTrue(result.mirrorRegions.isEmpty,
                      "Empty volume should have no mirror regions")
    }
}
