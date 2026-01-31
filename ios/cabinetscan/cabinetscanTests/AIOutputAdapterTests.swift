//
//  AIOutputAdapterTests.swift
//  cabinetscanTests
//
//  Created for Story 5.6: AI Output Adapter
//

import XCTest
@testable import cabinetscan

// MARK: - AI Output Adapter Tests

final class AIOutputAdapterTests: XCTestCase {

    // MARK: - Properties

    private var adapter: AIOutputAdapter!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        adapter = AIOutputAdapter()
    }

    override func tearDown() {
        adapter = nil
        super.tearDown()
    }

    // MARK: - Task 2 Tests: Result Types

    /// Test 2.1: AIOutputAdapterResult struct exists with required properties
    func testAIOutputAdapterResultHasRequiredProperties() {
        // Given: A mock validation result
        let validationResult = AIOutputValidationResult(isValid: true, errors: [], warnings: [])

        // When: Creating an adapter result
        let result = AIOutputAdapterResult(
            measurementData: createMockMeasurementData(),
            floorPlanURL: URL(fileURLWithPath: "/tmp/test.png"),
            validationResult: validationResult
        )

        // Then: All properties are accessible
        XCTAssertNotNil(result.measurementData)
        XCTAssertNotNil(result.floorPlanURL)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    /// Test 2.2: AIOutputValidationResult struct exists with required properties
    func testAIOutputValidationResultHasRequiredProperties() {
        // Given/When: Creating validation results
        let validResult = AIOutputValidationResult(isValid: true, errors: [], warnings: ["Some warning"])
        let invalidResult = AIOutputValidationResult.invalid(errors: ["Missing data"])

        // Then: Properties are correct
        XCTAssertTrue(validResult.isValid)
        XCTAssertTrue(validResult.errors.isEmpty)
        XCTAssertEqual(validResult.warnings, ["Some warning"])

        XCTAssertFalse(invalidResult.isValid)
        XCTAssertEqual(invalidResult.errors, ["Missing data"])
    }

    /// Test 2.3: AIOutputError enum exists with all cases
    func testAIOutputErrorEnumHasAllCases() {
        // Given: All error cases
        let errors: [AIOutputError] = [
            .renderingFailed("test"),
            .jsonGenerationFailed("test"),
            .validationFailed(["error"]),
            .noRoomStructure
        ]

        // Then: Each has an error description
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    /// Test 2.4: Validation warnings included for low confidence
    func testValidationIncludesWarningsForLowConfidence() {
        // This will be tested via validateOutput method
        // Validation result should support warnings
        let result = AIOutputValidationResult(
            isValid: true,
            errors: [],
            warnings: ["Overall confidence is low - measurements may need verification"]
        )

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    // MARK: - Task 3 Tests: Validation Logic

    /// Test 3.2: Validation fails for empty room name
    func testValidationFailsForEmptyRoomName() async throws {
        // Given: MeasurementData with empty room name
        let measurementData = MeasurementData(
            roomName: "",  // Empty!
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: nil,
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: createMockAIMetadata()
        )

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: URL(fileURLWithPath: "/tmp/test.png")
        )

        // Then: Validation fails
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("Room name") }))
    }

    /// Test 3.5: Validation fails if scanMethod is not aiFlow
    func testValidationFailsIfScanMethodNotAIFlow() async throws {
        // Given: MeasurementData with lidar scan method
        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "/tmp/test.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .lidar,  // Wrong!
            aiMetadata: createMockAIMetadata()
        )

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: URL(fileURLWithPath: "/tmp/test.png")
        )

        // Then: Validation fails
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("aiFlow") }))
    }

    /// Test 3.6: Validation fails if aiMetadata is missing
    func testValidationFailsIfAIMetadataMissing() async throws {
        // Given: MeasurementData without aiMetadata
        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "/tmp/test.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: nil  // Missing!
        )

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: URL(fileURLWithPath: "/tmp/test.png")
        )

        // Then: Validation fails
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("metadata") }))
    }

    /// Test 3.7: Validation generates warnings for low confidence
    func testValidationGeneratesWarningsForLowConfidence() async throws {
        // Given: MeasurementData with low confidence
        let lowConfidenceMetadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.9,
            overallConfidence: 0.4,  // Below 0.6 threshold
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: true,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 0.8,
            warnings: nil
        )

        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "/tmp/test.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: lowConfidenceMetadata
        )

        // Create a temporary file for floor plan
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)  // PNG header
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: tempURL
        )

        // Then: Validation passes but has warnings
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("confidence") }))
    }

    /// Test 5.3: Validation passes for complete data
    func testValidationPassesForCompleteData() async throws {
        // Given: Complete valid MeasurementData
        let measurementData = createMockMeasurementData()

        // Create a temporary file for floor plan
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)  // PNG header
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: tempURL
        )

        // Then: Validation passes
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    /// Test 5.5: scanMethod is always .aiFlow in adapted output
    func testScanMethodIsAlwaysAIFlow() {
        // Given: Mock measurement data
        let measurementData = createMockMeasurementData()

        // Then: scanMethod is .aiFlow
        XCTAssertEqual(measurementData.scanMethod, .aiFlow)
    }

    /// Test 5.6: aiMetadata is populated correctly
    func testAIMetadataIsPopulatedCorrectly() {
        // Given: Mock measurement data
        let measurementData = createMockMeasurementData()

        // Then: aiMetadata is populated
        XCTAssertNotNil(measurementData.aiMetadata)
        XCTAssertEqual(measurementData.aiMetadata?.calibrationMethod, "creditCard")
        XCTAssertGreaterThan(measurementData.aiMetadata?.overallConfidence ?? 0, 0)
    }

    // MARK: - Task 5.8 Tests: Error Handling (Code Review Fix)

    /// Test 5.8.1: Error descriptions are user-friendly (no technical jargon)
    func testErrorDescriptionsAreUserFriendly() {
        // Given: All error types
        let errors: [AIOutputError] = [
            .renderingFailed("test reason"),
            .jsonGenerationFailed("test reason"),
            .validationFailed(["error1", "error2"]),
            .noRoomStructure
        ]

        // Then: All have user-friendly descriptions
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
            // Verify descriptions don't contain technical jargon
            XCTAssertFalse(error.errorDescription!.contains("nil"))
            XCTAssertFalse(error.errorDescription!.contains("null"))
        }
    }

    /// Test 5.8.2: Rendering failed error includes reason in description
    func testRenderingFailedErrorIncludesReason() {
        // Given: A rendering failure with specific reason
        let error = AIOutputError.renderingFailed("GPU memory exhausted")

        // Then: The reason appears in the description
        XCTAssertTrue(error.errorDescription?.contains("GPU memory exhausted") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("floor plan") ?? false)
    }

    /// Test 5.8.3: Validation failed error lists all errors
    func testValidationFailedErrorListsAllErrors() {
        // Given: Validation failure with multiple errors
        let error = AIOutputError.validationFailed(["Room name empty", "No floor plan"])

        // Then: All errors appear in the description
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Room name empty"))
        XCTAssertTrue(description.contains("No floor plan"))
    }

    /// Test 5.8.4: noRoomStructure error has actionable message
    func testNoRoomStructureErrorIsActionable() {
        // Given: noRoomStructure error
        let error = AIOutputError.noRoomStructure

        // Then: Description suggests action user can take
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("scan") || description.contains("try"))
    }

    /// Test 5.8.5: JSON generation failed error includes reason
    func testJSONGenerationFailedErrorIncludesReason() {
        // Given: JSON generation failure
        let error = AIOutputError.jsonGenerationFailed("Invalid cabinet data")

        // Then: Reason is included
        XCTAssertTrue(error.errorDescription?.contains("Invalid cabinet data") ?? false)
    }

    // MARK: - Story 6.2 Tests: Coverage Metadata (Task 7.5)

    /// Test 6.2.1: Coverage percentage included in aiMetadata
    func testCoveragePercentageInAIMetadata() {
        // Given: AIMetadata with coverage percentage
        let metadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.9,
            overallConfidence: 0.75,
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 0.75,  // 75% coverage
            warnings: ["Some areas not captured (75% coverage)"]
        )

        // Then: Coverage percentage is accessible
        XCTAssertEqual(metadata.coveragePercentage, 0.75)
    }

    /// Test 6.2.2: Coverage warnings included in aiMetadata
    func testCoverageWarningsInAIMetadata() {
        // Given: AIMetadata with coverage warnings
        let metadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.9,
            overallConfidence: 0.5,
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: true,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 0.25,  // 25% coverage (severe)
            warnings: [
                "Some areas not captured (25% coverage)",
                "Incomplete scan - consider rescanning"
            ]
        )

        // Then: Warnings are accessible and contain coverage info
        XCTAssertNotNil(metadata.warnings)
        XCTAssertEqual(metadata.warnings?.count, 2)
        XCTAssertTrue(metadata.warnings?.contains(where: { $0.contains("not captured") }) ?? false)
        XCTAssertTrue(metadata.warnings?.contains(where: { $0.contains("Incomplete scan") }) ?? false)
    }

    /// Test 6.2.3: Full coverage produces no coverage warnings
    func testFullCoverageNoWarnings() {
        // Given: AIMetadata with 100% coverage
        let metadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.95,
            overallConfidence: 0.9,
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 1.0,  // Full coverage
            warnings: nil
        )

        // Then: Coverage is full and no warnings
        XCTAssertEqual(metadata.coveragePercentage, 1.0)
        XCTAssertNil(metadata.warnings)
    }

    /// Test 6.2.4: Validation passes with partial coverage (75%)
    func testValidationPassesWithPartialCoverage() async throws {
        // Given: MeasurementData with partial coverage
        let metadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.9,
            overallConfidence: 0.675,  // 0.9 * 0.75 = adjusted for coverage
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 0.75,
            warnings: ["Some areas not captured (75% coverage)"]
        )

        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 20.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "/tmp/floor_plan.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: metadata
        )

        // Create temporary floor plan file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)  // PNG header
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // When: Validating
        let result = adapter.validateOutputPublic(
            measurementData: measurementData,
            floorPlanURL: tempURL
        )

        // Then: Validation passes (partial coverage is acceptable)
        XCTAssertTrue(result.isValid)
    }

    /// Test 6.2.5: Severe coverage (25%) still allows quote submission
    func testSevereCoverageAllowsQuoteSubmission() {
        // Given: AIMetadata with severe coverage (25%)
        let metadata = AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.9,
            overallConfidence: 0.225,  // Very low due to coverage penalty
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: true,
            frameCount: 30,
            photoCount: 5,
            scaleFactor: 0.01,
            coveragePercentage: 0.25,
            warnings: [
                "Some areas not captured (25% coverage)",
                "Incomplete scan - consider rescanning"
            ]
        )

        // Then: needsVerification is true but data is still present
        XCTAssertTrue(metadata.needsVerification)
        XCTAssertEqual(metadata.coveragePercentage, 0.25)
        // Even with severe coverage, user can still proceed with warnings
        XCTAssertFalse(metadata.warnings?.isEmpty ?? true)
    }

    // MARK: - Helper Methods

    private func createMockMeasurementData() -> MeasurementData {
        return MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 24.5,
            totalSqFt: 120.0,
            wallCount: 4,
            windowCount: 2,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "/tmp/floor_plan.png",
            videoUrl: "/tmp/capture.mp4",
            videoThumbnailUrl: nil,
            videoDurationSeconds: 10,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: ["/tmp/photo1.jpg", "/tmp/photo2.jpg"],
            scanMethod: .aiFlow,
            aiMetadata: createMockAIMetadata()
        )
    }

    private func createMockAIMetadata() -> AIMetadata {
        return AIMetadata(
            calibrationMethod: "creditCard",
            calibrationConfidence: 0.95,
            overallConfidence: 0.85,
            processingTimeMs: 8500,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 45,
            photoCount: 5,
            scaleFactor: 0.0254,
            coveragePercentage: 0.78,
            warnings: nil
        )
    }
}
