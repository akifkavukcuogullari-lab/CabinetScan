//
//  ManualCalibrationTests.swift
//  cabinetscanTests
//
//  Created for Story 3.6: Manual Calibration Fallback
//

import XCTest
import simd
@testable import cabinetscan

/// Tests for manual calibration functionality (Story 3.6)
final class ManualCalibrationTests: XCTestCase {

    var calibrator: ScaleCalibrator!

    override func setUp() async throws {
        await MainActor.run {
            calibrator = ScaleCalibrator()
        }
    }

    override func tearDown() async throws {
        calibrator = nil
    }

    // MARK: - Task 6.2: Door-Based Scale Calculation Tests

    @MainActor
    func testManualDoorCalibration_CalculatesCorrectScale() async throws {
        // Given: A mesh with known floor-to-ceiling distance
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual door calibration with 32" door
        let result = try await calibrator.calibrateManualDoor(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedWidthInches: 32,
            failureReason: "Test failure"
        )

        // Then: Scale factor uses standard door height (80") as reference
        // Door calibration assumes door is 80/96 of ceiling height
        // estimatedDoorHeight = 2.0 * (80/96) = 1.667 mesh units
        // scaleFactor = 80" / 1.667 = 48.0
        XCTAssertEqual(result.scaleFactor, 48.0, accuracy: 0.1)
        XCTAssertEqual(result.calibrationMethod, .manualDoor)
    }

    @MainActor
    func testManualDoorCalibration_DifferentDoorWidths_ProduceSameScale() async throws {
        // Given: A mesh with known dimensions
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.5)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Test all door width options
        // Note: Door width is stored for metadata but doesn't affect scale calculation
        // because we can't detect actual door width in the mesh (MVP limitation)
        for doorWidth in DoorWidth.allCases {
            let result = try await calibrator.calibrateManualDoor(
                mesh: mesh,
                floorPlane: floorPlane,
                selectedWidthInches: doorWidth.rawValue,
                failureReason: "Test"
            )

            // Then: Scale factor is consistent (based on standard door height ratio)
            // scaleFactor = 80 / (2.5 * 80/96) = 38.4
            XCTAssertEqual(result.scaleFactor, 38.4, accuracy: 0.1, "Door width \(doorWidth.rawValue) should produce consistent scale (MVP: width is metadata only)")
        }
    }

    @MainActor
    func testManualDoorCalibration_DiffersFromCeilingCalibration() async throws {
        // Given: A mesh with known dimensions
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Calibrate with door (assumes 96" ceiling)
        let doorResult = try await calibrator.calibrateManualDoor(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedWidthInches: 32,
            failureReason: "Test"
        )

        // And: Calibrate with ceiling at 9' (108")
        let ceilingResult = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: CeilingHeight.nine.rawValue,  // 108"
            failureReason: "Test"
        )

        // Then: Results should differ because ceiling uses user-selected height
        // Door: 80 / (2.0 * 80/96) = 48.0
        // Ceiling 9': 108 / 2.0 = 54.0
        XCTAssertNotEqual(doorResult.scaleFactor, ceilingResult.scaleFactor, accuracy: 0.1)
        XCTAssertEqual(doorResult.scaleFactor, 48.0, accuracy: 0.1)
        XCTAssertEqual(ceilingResult.scaleFactor, 54.0, accuracy: 0.1)
    }

    // MARK: - Task 6.3: Ceiling-Based Scale Calculation Tests

    @MainActor
    func testManualCeilingCalibration_8FeetCeiling() async throws {
        // Given: A mesh with known floor-to-ceiling distance
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual ceiling calibration with 8' (96") ceiling
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: CeilingHeight.eight.rawValue,
            failureReason: "Test failure"
        )

        // Then: Scale factor should convert 2.0 mesh units to 96"
        // scaleFactor = 96" / 2.0 = 48.0
        XCTAssertEqual(result.scaleFactor, 48.0, accuracy: 0.1)
        XCTAssertEqual(result.calibrationMethod, .manualCeiling)
        XCTAssertEqual(result.ceilingHeightInches, 96.0)
    }

    @MainActor
    func testManualCeilingCalibration_9FeetCeiling() async throws {
        // Given: A mesh with known floor-to-ceiling distance
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual ceiling calibration with 9' (108") ceiling
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: CeilingHeight.nine.rawValue,
            failureReason: "Test failure"
        )

        // Then: Scale factor should convert 2.0 mesh units to 108"
        // scaleFactor = 108" / 2.0 = 54.0
        XCTAssertEqual(result.scaleFactor, 54.0, accuracy: 0.1)
        XCTAssertEqual(result.ceilingHeightInches, 108.0)
    }

    @MainActor
    func testManualCeilingCalibration_10FeetCeiling() async throws {
        // Given: A mesh with known floor-to-ceiling distance
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual ceiling calibration with 10' (120") ceiling
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: CeilingHeight.ten.rawValue,
            failureReason: "Test failure"
        )

        // Then: Scale factor should convert 2.0 mesh units to 120"
        // scaleFactor = 120" / 2.0 = 60.0
        XCTAssertEqual(result.scaleFactor, 60.0, accuracy: 0.1)
        XCTAssertEqual(result.ceilingHeightInches, 120.0)
    }

    // MARK: - Task 6.4: Confidence Level Tests

    @MainActor
    func testManualDoorCalibration_AlwaysMediumConfidence() async throws {
        // Given: A valid mesh
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual door calibration
        let result = try await calibrator.calibrateManualDoor(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedWidthInches: 32,
            failureReason: "Test"
        )

        // Then: Confidence should always be MEDIUM for manual calibration
        XCTAssertEqual(result.confidenceLevel, .medium)
    }

    @MainActor
    func testManualCeilingCalibration_AlwaysMediumConfidence() async throws {
        // Given: A valid mesh
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual ceiling calibration
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: 96,
            failureReason: "Test"
        )

        // Then: Confidence should always be MEDIUM for manual calibration
        XCTAssertEqual(result.confidenceLevel, .medium)
    }

    // MARK: - Task 6.5: Calibration Method Enum Tests

    @MainActor
    func testManualDoorCalibration_SetsCorrectMethod() async throws {
        // Given: A valid mesh
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual door calibration
        let result = try await calibrator.calibrateManualDoor(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedWidthInches: 32,
            failureReason: "Test"
        )

        // Then: Method should be .manualDoor
        XCTAssertEqual(result.calibrationMethod, .manualDoor)
    }

    @MainActor
    func testManualCeilingCalibration_SetsCorrectMethod() async throws {
        // Given: A valid mesh
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When: Manual ceiling calibration
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: 96,
            failureReason: "Test"
        )

        // Then: Method should be .manualCeiling
        XCTAssertEqual(result.calibrationMethod, .manualCeiling)
    }

    @MainActor
    func testManualCalibration_PreservesFailureReason() async throws {
        // Given: A valid mesh and a specific failure reason
        let mesh = createMeshWithKnownCeilingHeight(heightInMeshUnits: 2.0)
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)
        let failureReason = "Countertop not detected in scan"

        // When: Manual calibration
        let result = try await calibrator.calibrateManualCeiling(
            mesh: mesh,
            floorPlane: floorPlane,
            selectedHeightInches: 96,
            failureReason: failureReason
        )

        // Then: Failure reason should be preserved
        XCTAssertEqual(result.autoCalibrationFailureReason, failureReason)
    }

    // MARK: - Task 6.6: Error Handling Tests

    @MainActor
    func testManualCalibration_EmptyMesh_ThrowsError() async throws {
        // Given: An empty mesh
        let mesh = AIMesh.empty
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When/Then: Calibration should throw emptyMesh error
        do {
            _ = try await calibrator.calibrateManualCeiling(
                mesh: mesh,
                floorPlane: floorPlane,
                selectedHeightInches: 96,
                failureReason: "Test"
            )
            XCTFail("Expected emptyMesh error")
        } catch let error as ScaleCalibrationError {
            XCTAssertEqual(error, .emptyMesh)
        }
    }

    @MainActor
    func testManualCalibration_NoCeiling_ThrowsError() async throws {
        // Given: A mesh with no clear ceiling (flat floor only)
        let mesh = createFlatFloorMesh()
        let floorPlane = AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)

        // When/Then: Calibration should throw ceiling detection error
        do {
            _ = try await calibrator.calibrateManualCeiling(
                mesh: mesh,
                floorPlane: floorPlane,
                selectedHeightInches: 96,
                failureReason: "Test"
            )
            XCTFail("Expected ceilingDetectionFailed error")
        } catch let error as ScaleCalibrationError {
            XCTAssertEqual(error, .ceilingDetectionFailed)
        }
    }

    // MARK: - Data Model Tests

    func testDoorWidthEnum_HasCorrectRawValues() {
        XCTAssertEqual(DoorWidth.thirty.rawValue, 30)
        XCTAssertEqual(DoorWidth.thirtyTwo.rawValue, 32)
        XCTAssertEqual(DoorWidth.thirtySix.rawValue, 36)
    }

    func testCeilingHeightEnum_HasCorrectRawValues() {
        XCTAssertEqual(CeilingHeight.eight.rawValue, 96)
        XCTAssertEqual(CeilingHeight.nine.rawValue, 108)
        XCTAssertEqual(CeilingHeight.ten.rawValue, 120)
    }

    func testManualCalibrationOption_HasCorrectTitles() {
        XCTAssertEqual(ManualCalibrationOption.door.title, "I have a door in the scan")
        XCTAssertEqual(ManualCalibrationOption.ceiling.title, "Use ceiling height")
    }

    func testManualCalibrationOption_DoorHasRecommendedSubtitle() {
        XCTAssertEqual(ManualCalibrationOption.door.subtitle, "Recommended")
        XCTAssertNil(ManualCalibrationOption.ceiling.subtitle)
    }

    // MARK: - Helper Methods

    /// Creates a mesh with a known floor-to-ceiling height for testing
    private func createMeshWithKnownCeilingHeight(heightInMeshUnits: Float) -> AIMesh {
        // Create a simple box mesh with floor at y=0 and ceiling at y=heightInMeshUnits
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Floor vertices (y = 0)
        vertices.append(SIMD3<Float>(-1, 0, -1))
        vertices.append(SIMD3<Float>(1, 0, -1))
        vertices.append(SIMD3<Float>(1, 0, 1))
        vertices.append(SIMD3<Float>(-1, 0, 1))

        // Ceiling vertices (y = heightInMeshUnits)
        vertices.append(SIMD3<Float>(-1, heightInMeshUnits, -1))
        vertices.append(SIMD3<Float>(1, heightInMeshUnits, -1))
        vertices.append(SIMD3<Float>(1, heightInMeshUnits, 1))
        vertices.append(SIMD3<Float>(-1, heightInMeshUnits, 1))

        // Add some intermediate vertices to help RANSAC
        for i in 0..<20 {
            // Floor points
            let x = Float.random(in: -0.9...0.9)
            let z = Float.random(in: -0.9...0.9)
            vertices.append(SIMD3<Float>(x, 0, z))

            // Ceiling points
            vertices.append(SIMD3<Float>(x, heightInMeshUnits, z))
        }

        // Floor triangles
        indices.append(contentsOf: [0, 1, 2])
        indices.append(contentsOf: [0, 2, 3])

        // Ceiling triangles
        indices.append(contentsOf: [4, 6, 5])
        indices.append(contentsOf: [4, 7, 6])

        return AIMesh(vertices: vertices, indices: indices)
    }

    /// Creates a flat floor mesh with no ceiling for testing error cases
    private func createFlatFloorMesh() -> AIMesh {
        var vertices: [SIMD3<Float>] = []

        // Only floor vertices at y = 0
        for _ in 0..<30 {
            let x = Float.random(in: -1...1)
            let z = Float.random(in: -1...1)
            vertices.append(SIMD3<Float>(x, 0, z))
        }

        let indices: [UInt32] = [0, 1, 2]

        return AIMesh(vertices: vertices, indices: indices)
    }
}

// MARK: - ViewModel Tests

@MainActor
final class ManualCalibrationViewModelTests: XCTestCase {

    func testViewModel_InitialState() {
        // Given: Input and calibrator
        let input = createTestInput()
        let calibrator = ScaleCalibrator()

        // When: Create view model
        let viewModel = ManualCalibrationViewModel(input: input, calibrator: calibrator)

        // Then: Initial state should be correct
        XCTAssertNil(viewModel.selectedOption)
        XCTAssertEqual(viewModel.selectedDoorWidth, .thirtyTwo)  // Default
        XCTAssertEqual(viewModel.selectedCeilingHeight, .eight)  // Default
        XCTAssertEqual(viewModel.calibrationState, .idle)
        XCTAssertFalse(viewModel.isCalibrating)
        XCTAssertFalse(viewModel.canContinue)  // No option selected
    }

    func testViewModel_SelectDoorOption_EnablesContinue() {
        // Given: View model
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())

        // When: Select door option
        viewModel.selectOption(.door)

        // Then: Can continue (has default door width)
        XCTAssertEqual(viewModel.selectedOption, .door)
        XCTAssertTrue(viewModel.canContinue)
    }

    func testViewModel_SelectCeilingOption_EnablesContinue() {
        // Given: View model
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())

        // When: Select ceiling option
        viewModel.selectOption(.ceiling)

        // Then: Can continue (has default ceiling height)
        XCTAssertEqual(viewModel.selectedOption, .ceiling)
        XCTAssertTrue(viewModel.canContinue)
    }

    func testViewModel_SelectDoorWidth() {
        // Given: View model with door option selected
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())
        viewModel.selectOption(.door)

        // When: Select different door widths
        for width in DoorWidth.allCases {
            viewModel.selectDoorWidth(width)
            XCTAssertEqual(viewModel.selectedDoorWidth, width)
        }
    }

    func testViewModel_SelectCeilingHeight() {
        // Given: View model with ceiling option selected
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())
        viewModel.selectOption(.ceiling)

        // When: Select different ceiling heights
        for height in CeilingHeight.allCases {
            viewModel.selectCeilingHeight(height)
            XCTAssertEqual(viewModel.selectedCeilingHeight, height)
        }
    }

    func testViewModel_FailureReason_FromInput() {
        // Given: Input with specific failure reason
        let input = ManualCalibrationInput(
            fusionResult: createTestFusionResult(),
            floorPlane: AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0),
            failureReason: "Test failure reason",
            previewPhotoURL: nil
        )

        // When: Create view model
        let viewModel = ManualCalibrationViewModel(input: input, calibrator: ScaleCalibrator())

        // Then: Failure reason should be accessible
        XCTAssertEqual(viewModel.failureReason, "Test failure reason")
    }

    // MARK: - Pipeline Integration Tests (Task 5)

    func testViewModel_CancelCallsCallback() {
        // Given: View model with cancel callback
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())
        var cancelCalled = false
        viewModel.onCancel = { cancelCalled = true }

        // When: Cancel is called
        viewModel.cancel()

        // Then: Callback should be invoked
        XCTAssertTrue(cancelCalled)
    }

    func testViewModel_ContinueWithEstimate_ProducesLowConfidence() {
        // Given: View model with completion callback
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())
        viewModel.selectOption(.door)

        var receivedResult: ScaleCalibrationResult?
        viewModel.onCalibrationComplete = { result in
            receivedResult = result
        }

        // When: User continues with estimate
        viewModel.continueWithEstimate()

        // Then: Result should have LOW confidence
        XCTAssertNotNil(receivedResult)
        XCTAssertEqual(receivedResult?.confidenceLevel, .low)
    }

    func testViewModel_ContinueWithEstimate_UsesReasonableScale() {
        // Given: View model with known bounding box (height = 1.0 mesh units)
        let input = createTestInput()  // Uses .empty mesh with bounding box 0...1
        let viewModel = ManualCalibrationViewModel(input: input, calibrator: ScaleCalibrator())
        viewModel.selectOption(.ceiling)

        var receivedResult: ScaleCalibrationResult?
        viewModel.onCalibrationComplete = { result in
            receivedResult = result
        }

        // When: User continues with estimate
        viewModel.continueWithEstimate()

        // Then: Scale factor should be reasonable (96" / 1.0 = 96)
        XCTAssertNotNil(receivedResult)
        XCTAssertEqual(receivedResult?.scaleFactor ?? 0, 96.0, accuracy: 1.0)
    }

    func testViewModel_ShowError_SetsToTrue_OnError() async {
        // Given: View model with empty mesh (will cause error)
        let emptyInput = ManualCalibrationInput(
            fusionResult: TSDFFusionResult(
                mesh: .empty,
                boundingBox: TSDFBoundingBox(min: .zero, max: .one),
                voxelSize: 0.02,
                integratedCloudCount: 0,
                totalPointsProcessed: 0,
                processingTimeMs: 0,
                qualityMetrics: TSDFQualityMetrics(
                    coveragePercentage: 0,
                    averageVoxelWeight: 0,
                    totalVoxelCount: 0,
                    isMeshManifold: false
                )
            ),
            floorPlane: AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0),
            failureReason: "Test",
            previewPhotoURL: nil
        )
        let viewModel = ManualCalibrationViewModel(input: emptyInput, calibrator: ScaleCalibrator())
        viewModel.selectOption(.ceiling)
        viewModel.selectCeilingHeight(.eight)

        // When: Calibration is attempted (will fail due to empty mesh)
        await viewModel.performCalibration()

        // Then: showError should be true
        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testViewModel_Retry_ResetsErrorState() async {
        // Given: View model in error state
        let viewModel = ManualCalibrationViewModel(input: createTestInput(), calibrator: ScaleCalibrator())
        viewModel.selectOption(.ceiling)

        // Simulate error state
        await viewModel.performCalibration()  // Will fail with empty mesh

        // When: Retry is called
        viewModel.retry()

        // Then: Error state should be cleared
        XCTAssertFalse(viewModel.showError)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.calibrationState, .idle)
    }

    // MARK: - Helper Methods

    private func createTestInput() -> ManualCalibrationInput {
        return ManualCalibrationInput(
            fusionResult: createTestFusionResult(),
            floorPlane: AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0),
            failureReason: "Auto calibration failed",
            previewPhotoURL: nil
        )
    }

    private func createTestFusionResult() -> TSDFFusionResult {
        return TSDFFusionResult(
            mesh: .empty,
            boundingBox: TSDFBoundingBox(min: .zero, max: .one),
            voxelSize: 0.02,
            integratedCloudCount: 10,
            totalPointsProcessed: 1000,
            processingTimeMs: 500,
            qualityMetrics: TSDFQualityMetrics(
                coveragePercentage: 0.8,
                averageVoxelWeight: 5.0,
                totalVoxelCount: 10000,
                isMeshManifold: true
            )
        )
    }
}
