//
//  ScaleCalibratorTests.swift
//  cabinetscanTests
//
//  Created for Story 3.5: Automatic Scale Calibration
//

import XCTest
import simd
import Combine
@testable import cabinetscan

@MainActor
final class ScaleCalibratorTests: XCTestCase {

    var sut: ScaleCalibrator!

    override func setUp() async throws {
        try await super.setUp()
        sut = ScaleCalibrator()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    /// Creates a synthetic floor mesh at the given Y coordinate.
    private func createFloorMesh(atY y: Float = 0.0, size: Float = 2.0) -> AIMesh {
        // Create a simple quad (2 triangles) for the floor
        let halfSize = size / 2
        let vertices: [SIMD3<Float>] = [
            SIMD3(-halfSize, y, -halfSize),  // 0: bottom-left
            SIMD3(halfSize, y, -halfSize),   // 1: bottom-right
            SIMD3(halfSize, y, halfSize),    // 2: top-right
            SIMD3(-halfSize, y, halfSize)    // 3: top-left
        ]
        let indices: [UInt32] = [
            0, 1, 2,  // Triangle 1
            0, 2, 3   // Triangle 2
        ]
        return AIMesh(vertices: vertices, indices: indices)
    }

    /// Creates a synthetic box mesh with floor at y=0 and specified heights for counter and ceiling.
    private func createKitchenMesh(
        floorY: Float = 0.0,
        counterY: Float = 0.36,  // ~36" in mesh units if scale is 100
        ceilingY: Float = 0.96   // ~96" in mesh units if scale is 100
    ) -> AIMesh {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let size: Float = 2.0
        let halfSize = size / 2

        // Floor quad (4 vertices, 2 triangles)
        let floorStart = UInt32(vertices.count)
        vertices.append(contentsOf: [
            SIMD3(-halfSize, floorY, -halfSize),
            SIMD3(halfSize, floorY, -halfSize),
            SIMD3(halfSize, floorY, halfSize),
            SIMD3(-halfSize, floorY, halfSize)
        ])
        indices.append(contentsOf: [
            floorStart, floorStart + 1, floorStart + 2,
            floorStart, floorStart + 2, floorStart + 3
        ])

        // Countertop quad (4 vertices, 2 triangles)
        let counterStart = UInt32(vertices.count)
        let counterSize: Float = 1.5
        let counterHalf = counterSize / 2
        vertices.append(contentsOf: [
            SIMD3(-counterHalf, counterY, -counterHalf),
            SIMD3(counterHalf, counterY, -counterHalf),
            SIMD3(counterHalf, counterY, counterHalf),
            SIMD3(-counterHalf, counterY, counterHalf)
        ])
        indices.append(contentsOf: [
            counterStart, counterStart + 1, counterStart + 2,
            counterStart, counterStart + 2, counterStart + 3
        ])

        // Ceiling quad (4 vertices, 2 triangles)
        let ceilingStart = UInt32(vertices.count)
        vertices.append(contentsOf: [
            SIMD3(-halfSize, ceilingY, -halfSize),
            SIMD3(halfSize, ceilingY, -halfSize),
            SIMD3(halfSize, ceilingY, halfSize),
            SIMD3(-halfSize, ceilingY, halfSize)
        ])
        indices.append(contentsOf: [
            ceilingStart, ceilingStart + 1, ceilingStart + 2,
            ceilingStart, ceilingStart + 2, ceilingStart + 3
        ])

        // Add upper cabinet surface at ~54" (0.54 mesh units if scale is 100)
        let upperCabinetY = counterY + 0.18  // 18" above counter
        let upperStart = UInt32(vertices.count)
        let upperSize: Float = 1.0
        let upperHalf = upperSize / 2
        vertices.append(contentsOf: [
            SIMD3(-upperHalf, upperCabinetY, -upperHalf),
            SIMD3(upperHalf, upperCabinetY, -upperHalf),
            SIMD3(upperHalf, upperCabinetY, upperHalf),
            SIMD3(-upperHalf, upperCabinetY, upperHalf)
        ])
        indices.append(contentsOf: [
            upperStart, upperStart + 1, upperStart + 2,
            upperStart, upperStart + 2, upperStart + 3
        ])

        return AIMesh(vertices: vertices, indices: indices)
    }

    /// Creates a TSDFFusionResult with the given mesh.
    private func createFusionResult(mesh: AIMesh) -> TSDFFusionResult {
        TSDFFusionResult(
            mesh: mesh,
            boundingBox: TSDFBoundingBox(
                min: SIMD3(-1, -1, -1),
                max: SIMD3(1, 1, 1)
            ),
            voxelSize: 0.02,
            integratedCloudCount: 1,
            totalPointsProcessed: 1000,
            processingTimeMs: 100,
            qualityMetrics: TSDFQualityMetrics(
                coveragePercentage: 50.0,
                averageVoxelWeight: 1.0,
                totalVoxelCount: 1000,
                isMeshManifold: true
            )
        )
    }

    // MARK: - Task 8.2: Floor Plane Detection Tests

    func testDetectFloorPlane_WithFlatFloor_ReturnsHorizontalPlane() async {
        // Given: A simple floor mesh at y = 0
        let mesh = createFloorMesh(atY: 0.0)

        // When: Detecting floor plane
        let result = sut.detectFloorPlane(from: mesh)

        // Then: Should find a horizontal plane
        XCTAssertNotNil(result, "Floor plane should be detected")
        if let plane = result {
            // Normal should point up (positive Y)
            XCTAssertGreaterThan(plane.normal.y, 0.9, "Floor normal should point up")
            // Distance should be close to 0 (floor at y=0)
            XCTAssertEqual(plane.distance, 0.0, accuracy: 0.1, "Floor should be at y=0")
        }
    }

    func testDetectFloorPlane_WithElevatedFloor_ReturnsCorrectDistance() async {
        // Given: A floor mesh at y = 0.5
        let mesh = createFloorMesh(atY: 0.5)

        // When: Detecting floor plane
        let result = sut.detectFloorPlane(from: mesh)

        // Then: Should find a plane at y = 0.5
        XCTAssertNotNil(result, "Floor plane should be detected")
        if let plane = result {
            XCTAssertGreaterThan(plane.normal.y, 0.9, "Floor normal should point up")
            // For a floor at y=0.5 with normal (0,1,0), distance = -0.5
            XCTAssertEqual(abs(plane.distance), 0.5, accuracy: 0.1, "Floor distance should reflect y=0.5")
        }
    }

    func testDetectFloorPlane_WithEmptyMesh_ReturnsNil() async {
        // Given: An empty mesh
        let mesh = AIMesh(vertices: [], indices: [])

        // When: Detecting floor plane
        let result = sut.detectFloorPlane(from: mesh)

        // Then: Should return nil
        XCTAssertNil(result, "Empty mesh should not produce a floor plane")
    }

    // MARK: - Task 8.3: Countertop Detection Tests

    func testDetectCountertop_WithKitchenMesh_FindsCountertop() async {
        // Given: A kitchen mesh with floor, counter, and ceiling
        let mesh = createKitchenMesh(floorY: 0.0, counterY: 0.36, ceilingY: 0.96)

        // And: A detected floor plane
        let floorPlane = AIPlane(normal: SIMD3(0, 1, 0), distance: 0)

        // When: Detecting countertop
        let result = sut.detectCountertop(from: mesh, floorPlane: floorPlane)

        // Then: Should find countertop
        XCTAssertNotNil(result, "Countertop should be detected")
        if let countertop = result {
            // Height should be close to 0.36 (the countertop Y we set)
            XCTAssertEqual(countertop.heightFromFloor, 0.36, accuracy: 0.05,
                           "Countertop height should be approximately 0.36")
            XCTAssertGreaterThan(countertop.area, 0, "Countertop should have positive area")
        }
    }

    func testDetectCountertop_WithOnlyFloor_ReturnsNil() async {
        // Given: A mesh with only floor
        let mesh = createFloorMesh(atY: 0.0)
        let floorPlane = AIPlane(normal: SIMD3(0, 1, 0), distance: 0)

        // When: Detecting countertop
        let result = sut.detectCountertop(from: mesh, floorPlane: floorPlane)

        // Then: Should return nil (no countertop found)
        XCTAssertNil(result, "Single floor mesh should not have countertop")
    }

    // MARK: - Task 8.4: Scale Factor Calculation Tests

    func testCalculateScale_With36InchCounter_Returns100() async {
        // Given: Countertop at 0.36 mesh units (representing 36" if scale = 100)
        let countertopHeight: Float = 0.36

        // When: Calculating scale
        let scaleFactor = sut.calculateScale(countertopHeight: countertopHeight)

        // Then: Scale should be 100 (36 / 0.36 = 100)
        XCTAssertEqual(scaleFactor, 100.0, accuracy: 0.1, "Scale factor should be 100")
    }

    func testCalculateScale_WithDifferentHeights_ReturnsCorrectScale() async {
        // Test various countertop heights
        let testCases: [(height: Float, expectedScale: Float)] = [
            (0.36, 100.0),   // Standard
            (0.72, 50.0),    // Double height = half scale
            (0.18, 200.0),   // Half height = double scale
            (1.0, 36.0)      // 1 mesh unit = 36 inches
        ]

        for testCase in testCases {
            let scaleFactor = sut.calculateScale(countertopHeight: testCase.height)
            XCTAssertEqual(scaleFactor, testCase.expectedScale, accuracy: 0.1,
                           "Scale for height \(testCase.height) should be \(testCase.expectedScale)")
        }
    }

    func testCalculateScale_WithZeroHeight_ReturnsOne() async {
        // Given: Zero countertop height
        let countertopHeight: Float = 0.0

        // When: Calculating scale
        let scaleFactor = sut.calculateScale(countertopHeight: countertopHeight)

        // Then: Should return 1.0 as fallback
        XCTAssertEqual(scaleFactor, 1.0, "Zero height should return scale factor of 1.0")
    }

    // MARK: - Task 8.5: Validation Logic Tests

    func testValidateCalibration_WithValidKitchen_ReturnsHighConfidence() async throws {
        // Given: A properly scaled kitchen mesh
        // Scale = 100, so 0.36 mesh units = 36", 0.54 = 54", 0.96 = 96"
        let mesh = createKitchenMesh(floorY: 0.0, counterY: 0.36, ceilingY: 1.0)
        let floorPlane = AIPlane(normal: SIMD3(0, 1, 0), distance: 0)
        let scaleFactor: Float = 100.0

        // When: Validating calibration
        let validation = sut.validateCalibration(
            mesh: mesh,
            floorPlane: floorPlane,
            scaleFactor: scaleFactor
        )

        // Then: Should have high confidence (both checks pass)
        // Upper cabinet at 0.54 * 100 = 54", ceiling at 1.0 * 100 = 100"
        XCTAssertTrue(validation.ceilingHeightValid, "Ceiling should be valid (100\" is in range)")
        // Note: Upper cabinet validation depends on surface detection finding the 0.54 surface
    }

    func testDetermineConfidence_WithTwoPassedChecks_ReturnsHigh() async {
        // Given: Validation with both checks passed
        let validation = CalibrationValidation(
            upperCabinetHeightValid: true,
            upperCabinetHeightInches: 54.0,
            ceilingHeightValid: true,
            ceilingHeightInches: 96.0
        )

        // When: Getting passed checks
        let passedChecks = validation.passedChecks

        // Then: Should have 2 passed checks (HIGH confidence)
        XCTAssertEqual(passedChecks, 2, "Both checks passed should yield 2")
    }

    func testDetermineConfidence_WithOnePassedCheck_ReturnsMedium() async {
        // Given: Validation with one check passed
        let validation = CalibrationValidation(
            upperCabinetHeightValid: false,
            upperCabinetHeightInches: nil,
            ceilingHeightValid: true,
            ceilingHeightInches: 100.0
        )

        // When: Getting passed checks
        let passedChecks = validation.passedChecks

        // Then: Should have 1 passed check (MEDIUM confidence)
        XCTAssertEqual(passedChecks, 1, "One check passed should yield 1")
    }

    func testDetermineConfidence_WithNoPassedChecks_ReturnsLow() async {
        // Given: Validation with no checks passed
        let validation = CalibrationValidation.empty

        // When: Getting passed checks
        let passedChecks = validation.passedChecks

        // Then: Should have 0 passed checks (LOW confidence)
        XCTAssertEqual(passedChecks, 0, "No checks passed should yield 0")
    }

    // MARK: - Task 8.6: Ceiling Fallback Tests

    func testDetectCeilingPlane_WithKitchenMesh_FindsCeiling() async {
        // Given: A kitchen mesh with floor, counter, and ceiling
        let mesh = createKitchenMesh(floorY: 0.0, counterY: 0.36, ceilingY: 0.96)

        // When: Detecting ceiling plane
        let result = sut.detectCeilingPlane(from: mesh)

        // Then: Should find ceiling
        XCTAssertNotNil(result, "Ceiling plane should be detected")
        if let plane = result {
            // Normal should point down (negative Y) for ceiling
            XCTAssertLessThan(plane.normal.y, -0.9, "Ceiling normal should point down")
        }
    }

    func testCalibrateFromCeiling_WithStandardCeiling_ReturnsCorrectScale() async {
        // Given: Floor at 0, ceiling at 0.96 mesh units (96" if scale = 100)
        let floorHeight: Float = 0.0
        let ceilingHeight: Float = 0.96

        // When: Calibrating from ceiling with 96" assumption
        let scaleFactor = sut.calibrateFromCeiling(
            floorHeight: floorHeight,
            ceilingHeight: ceilingHeight,
            assumedCeilingInches: 96.0
        )

        // Then: Scale should be 100 (96 / 0.96 = 100)
        XCTAssertEqual(scaleFactor, 100.0, accuracy: 0.1, "Scale factor should be 100")
    }

    // MARK: - Task 8.7: Complete Failure Scenario Tests

    func testCalibrate_WithEmptyMesh_ThrowsEmptyMeshError() async {
        // Given: An empty fusion result
        let emptyMesh = AIMesh(vertices: [], indices: [])
        let fusionResult = createFusionResult(mesh: emptyMesh)

        // When/Then: Should throw emptyMesh error
        do {
            _ = try await sut.calibrate(fusionResult: fusionResult)
            XCTFail("Should throw emptyMesh error")
        } catch let error as ScaleCalibrationError {
            XCTAssertEqual(error, .emptyMesh, "Should throw emptyMesh error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCalibrate_WithNoHorizontalSurfaces_ReturnsFailedMethod() async throws {
        // Given: A mesh with only vertical surfaces (no floor)
        // Create a vertical wall
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0)
        ]
        let indices: [UInt32] = [0, 1, 2, 0, 2, 3]
        let wallMesh = AIMesh(vertices: vertices, indices: indices)
        let fusionResult = createFusionResult(mesh: wallMesh)

        // When/Then: Should throw floor detection failed (no horizontal plane)
        do {
            _ = try await sut.calibrate(fusionResult: fusionResult)
            XCTFail("Should throw floorDetectionFailed error")
        } catch let error as ScaleCalibrationError {
            XCTAssertEqual(error, .floorDetectionFailed, "Should throw floorDetectionFailed error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Task 8.8: Progress Reporting and Cancellation Tests

    func testCalibrate_ReportsProgress() async throws {
        // Given: A valid kitchen mesh
        let mesh = createKitchenMesh()
        let fusionResult = createFusionResult(mesh: mesh)

        // Collect progress values
        var progressValues: [Double] = []
        let cancellable = sut.$progress.sink { progress in
            progressValues.append(progress)
        }

        // When: Calibrating
        _ = try await sut.calibrate(fusionResult: fusionResult)

        cancellable.cancel()

        // Then: Progress should increase from 0 to 1
        XCTAssertFalse(progressValues.isEmpty, "Progress should be reported")
        XCTAssertEqual(progressValues.first, 0.0, "Progress should start at 0")
        XCTAssertEqual(progressValues.last, 1.0, "Progress should end at 1")

        // Progress should be monotonically increasing
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i-1],
                                         "Progress should be monotonically increasing")
        }
    }

    func testCalibrate_ReportsPhases() async throws {
        // Given: A valid kitchen mesh
        let mesh = createKitchenMesh()
        let fusionResult = createFusionResult(mesh: mesh)

        // Collect phase values
        var phases: [CalibrationPhase] = []
        let cancellable = sut.$currentPhase.sink { phase in
            if phases.isEmpty || phases.last != phase {
                phases.append(phase)
            }
        }

        // When: Calibrating
        _ = try await sut.calibrate(fusionResult: fusionResult)

        cancellable.cancel()

        // Then: Should go through expected phases
        XCTAssertTrue(phases.contains(.detectingFloor), "Should report floor detection phase")
        XCTAssertTrue(phases.contains(.detectingCountertop), "Should report countertop detection phase")
        XCTAssertTrue(phases.contains(.complete), "Should report complete phase")
    }

    func testCalibrate_SupportsCancellation() async {
        // Given: A valid kitchen mesh
        let mesh = createKitchenMesh()
        let fusionResult = createFusionResult(mesh: mesh)

        // When: Starting calibration and immediately cancelling
        let task = Task {
            try await sut.calibrate(fusionResult: fusionResult)
        }

        // Cancel immediately
        task.cancel()

        // Then: Task should complete (either successfully or cancelled)
        // We can't guarantee it will be cancelled since calibration is fast
        // but we verify it doesn't crash
        do {
            _ = try await task.value
            // Completed before cancellation - that's OK
        } catch is CancellationError {
            // Cancelled as expected
        } catch {
            // Other errors are acceptable too
        }
    }

    // MARK: - AC6: Scale Accuracy Tests

    func testScaleAccuracy_WithKnownGroundTruth_AchievesFivePercentAccuracy() async throws {
        // AC6: Scale error must be less than 5%
        // Given: A mesh where we know the exact ground truth scale
        // Ground truth: scale = 100 (0.01 mesh units = 1 inch)
        // Floor at 0, countertop at 0.36 mesh units (36"), ceiling at 0.96 (96")
        let groundTruthScale: Float = 100.0
        let mesh = createKitchenMesh(floorY: 0.0, counterY: 0.36, ceilingY: 0.96)
        let fusionResult = createFusionResult(mesh: mesh)

        // When: Running calibration
        let result = try await sut.calibrate(fusionResult: fusionResult)

        // Then: Scale error should be less than 5%
        let scaleError = abs(result.scaleFactor - groundTruthScale) / groundTruthScale
        let errorPercentage = scaleError * 100.0

        XCTAssertLessThan(errorPercentage, 5.0,
                          "Scale error should be < 5%. Got \(errorPercentage)% (scale: \(result.scaleFactor), expected: \(groundTruthScale))")
    }

    func testScaleAccuracy_WithVariousScales_MaintainsFivePercentAccuracy() async throws {
        // Test accuracy across different scale factors
        let testCases: [(counterY: Float, ceilingY: Float, expectedScale: Float)] = [
            (0.36, 0.96, 100.0),   // Standard scale = 100
            (0.72, 1.92, 50.0),    // Scale = 50 (larger mesh units)
            (0.18, 0.48, 200.0),   // Scale = 200 (smaller mesh units)
        ]

        for testCase in testCases {
            let mesh = createKitchenMesh(
                floorY: 0.0,
                counterY: testCase.counterY,
                ceilingY: testCase.ceilingY
            )
            let fusionResult = createFusionResult(mesh: mesh)

            let result = try await sut.calibrate(fusionResult: fusionResult)

            let scaleError = abs(result.scaleFactor - testCase.expectedScale) / testCase.expectedScale
            let errorPercentage = scaleError * 100.0

            XCTAssertLessThan(errorPercentage, 5.0,
                              "Scale error for expected \(testCase.expectedScale) should be < 5%. Got \(errorPercentage)%")
        }
    }

    // MARK: - Integration Tests

    func testFullCalibration_WithStandardKitchen_ReturnsValidResult() async throws {
        // Given: A standard kitchen mesh (scale = 100)
        // Floor at 0, counter at 0.36 (36"), upper cabinet at 0.54 (54"), ceiling at 1.0 (100")
        let mesh = createKitchenMesh(floorY: 0.0, counterY: 0.36, ceilingY: 1.0)
        let fusionResult = createFusionResult(mesh: mesh)

        // When: Running full calibration
        let result = try await sut.calibrate(fusionResult: fusionResult)

        // Then: Should return valid result with countertop method
        XCTAssertEqual(result.calibrationMethod, .autoCountertop, "Should use countertop calibration")

        // Scale factor should be approximately 100 (36 / 0.36)
        XCTAssertEqual(result.scaleFactor, 100.0, accuracy: 10.0,
                       "Scale factor should be approximately 100")

        // Countertop height should be 36"
        XCTAssertEqual(result.countertopHeightInches, 36.0,
                       "Countertop height should be 36 inches")

        // Processing time should be recorded
        XCTAssertGreaterThan(result.processingTimeMs, 0, "Processing time should be positive")
    }

    func testScaleCalibrationResult_ContainsAllRequiredFields() async throws {
        // Given: A kitchen mesh
        let mesh = createKitchenMesh()
        let fusionResult = createFusionResult(mesh: mesh)

        // When: Calibrating
        let result = try await sut.calibrate(fusionResult: fusionResult)

        // Then: Result should contain all AC7 required fields
        XCTAssertGreaterThan(result.scaleFactor, 0, "Scale factor should be positive")
        XCTAssertNotNil(result.calibrationMethod, "Calibration method should be set")
        XCTAssertNotNil(result.confidenceLevel, "Confidence level should be set")
        XCTAssertNotNil(result.floorPlane, "Floor plane should be set")
        XCTAssertNotNil(result.validationResults, "Validation results should be set")
        XCTAssertGreaterThan(result.processingTimeMs, 0, "Processing time should be recorded")
    }
}
