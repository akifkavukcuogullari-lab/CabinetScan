//
//  ResultsTransitionTests.swift
//  cabinetscanTests
//
//  Created for Story 5.8: Results Transition to Selection
//

import XCTest
@testable import cabinetscan

/// Tests for Story 5.8: Results Transition to Selection
///
/// Verifies that AI flow results correctly transition to Selection screen
/// and that AI metadata is preserved through the submission pipeline.
@MainActor
final class ResultsTransitionTests: XCTestCase {

    // MARK: - AC1: MeasurementData Storage Tests

    /// Test that setMeasurementData routes to selection when categories exist.
    /// AC1: Navigation transitions to Selection screen automatically.
    func testSetMeasurementData_RoutesToSelection_WhenCategoriesExist() async throws {
        // Given: AppState with showroom config that has categories
        let appState = AppState()
        appState.showroomConfig = try createShowroomConfig(withCategories: true)

        // When: Setting measurement data
        let measurementData = createTestMeasurementData()
        appState.setMeasurementData(measurementData)

        // Then: Should route to selection
        XCTAssertEqual(appState.currentScreen, .selection, "Should route to selection when categories exist")
        XCTAssertNotNil(appState.measurementData, "MeasurementData should be stored")
    }

    /// Test that setMeasurementData routes to review when no categories.
    /// AC1: Data is stored in AppState via setMeasurementData().
    func testSetMeasurementData_RoutesToReview_WhenNoCategories() async throws {
        // Given: AppState with showroom config that has no categories
        let appState = AppState()
        appState.showroomConfig = try createShowroomConfig(withCategories: false)

        // When: Setting measurement data
        let measurementData = createTestMeasurementData()
        appState.setMeasurementData(measurementData)

        // Then: Should route to review
        XCTAssertEqual(appState.currentScreen, .review, "Should route to review when no categories")
        XCTAssertNotNil(appState.measurementData, "MeasurementData should be stored")
    }

    /// Test that setMeasurementData routes to review when showroomConfig is nil.
    func testSetMeasurementData_RoutesToReview_WhenShowroomConfigNil() async {
        // Given: AppState with no showroom config
        let appState = AppState()
        appState.showroomConfig = nil

        // When: Setting measurement data
        let measurementData = createTestMeasurementData()
        appState.setMeasurementData(measurementData)

        // Then: Should route to review (empty categories)
        XCTAssertEqual(appState.currentScreen, .review, "Should route to review when showroomConfig is nil")
    }

    // MARK: - AC3: AI Metadata Serialization Tests

    /// Test that AI metadata is correctly set in MeasurementData.
    /// AC3: Submission includes scanMethod: aiFlow.
    func testMeasurementData_HasScanMethodAIFlow() {
        // Given: MeasurementData from AI flow
        let measurementData = createTestMeasurementData()

        // Then: Should have scanMethod set to aiFlow
        XCTAssertEqual(measurementData.scanMethod, .aiFlow, "scanMethod should be .aiFlow")
    }

    /// Test that AI metadata struct is populated.
    /// AC3: Submission includes aiMetadata struct with all fields.
    func testMeasurementData_HasAIMetadata() {
        // Given: MeasurementData from AI flow
        let measurementData = createTestMeasurementData()

        // Then: Should have aiMetadata populated
        XCTAssertNotNil(measurementData.aiMetadata, "aiMetadata should not be nil")

        let metadata = measurementData.aiMetadata!
        XCTAssertFalse(metadata.calibrationMethod.isEmpty, "calibrationMethod should not be empty")
        XCTAssertGreaterThan(metadata.calibrationConfidence, 0, "calibrationConfidence should be > 0")
        XCTAssertGreaterThan(metadata.overallConfidence, 0, "overallConfidence should be > 0")
        XCTAssertGreaterThanOrEqual(metadata.frameCount, 0, "frameCount should be >= 0")
        XCTAssertGreaterThanOrEqual(metadata.photoCount, 0, "photoCount should be >= 0")
    }

    /// Test that MeasurementData serializes correctly to JSON.
    /// AC3: Verify aiMetadata is serialized correctly in payload.
    func testMeasurementData_SerializesToJSON() throws {
        // Given: MeasurementData from AI flow
        let measurementData = createTestMeasurementData()

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(measurementData)

        // Then: Should produce valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Should produce valid JSON dictionary")

        // Verify scan_method is present
        XCTAssertEqual(json?["scan_method"] as? String, "ai_flow", "scan_method should be 'ai_flow'")

        // Verify ai_metadata is present and has expected structure
        let aiMetadata = json?["ai_metadata"] as? [String: Any]
        XCTAssertNotNil(aiMetadata, "ai_metadata should be present in JSON")
        XCTAssertNotNil(aiMetadata?["calibration_method"], "calibration_method should be in ai_metadata")
        XCTAssertNotNil(aiMetadata?["overall_confidence"], "overall_confidence should be in ai_metadata")
        XCTAssertNotNil(aiMetadata?["processing_time_ms"], "processing_time_ms should be in ai_metadata")
    }

    /// Test that ProjectSubmission with AI flow data serializes correctly.
    func testProjectSubmission_WithAIFlowData_SerializesToJSON() throws {
        // Given: ProjectSubmission with AI flow measurement data
        let submission = try createTestProjectSubmission()

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(submission)

        // Then: Should produce valid JSON with AI metadata
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Should produce valid JSON")

        let measurements = json?["measurements"] as? [String: Any]
        XCTAssertNotNil(measurements, "measurements should be present")
        XCTAssertEqual(measurements?["scan_method"] as? String, "ai_flow", "scan_method should be 'ai_flow'")
    }

    // MARK: - AC5: Error Recovery Tests

    /// Test that nil measurementData doesn't crash AppState.
    /// AC5: App does not crash or hang.
    func testAppState_HandlesNilMeasurementData_Gracefully() async {
        // Given: AppState with nil measurementData
        let appState = AppState()
        appState.measurementData = nil

        // Then: Should not crash when accessing measurementData
        XCTAssertNil(appState.measurementData, "measurementData should be nil")

        // Verify currentScreen can be read without crash
        let _ = appState.currentScreen
    }

    /// Test that AIFlowCoordinator error state is properly set.
    /// AC5: User sees appropriate error message.
    func testAIFlowCoordinator_SetsErrorState_OnFailure() async {
        // Given: AIFlowCoordinator
        let coordinator = AIFlowCoordinator()

        // When: Setting an error
        let testError = AIFlowError.processingFailed("Test failure")
        coordinator.setError(testError)

        // Then: Should be in error state
        if case .error(let error) = coordinator.captureState {
            XCTAssertEqual(error.localizedDescription, testError.localizedDescription,
                          "Error should match the set error")
        } else {
            XCTFail("Coordinator should be in error state")
        }
    }

    /// Test that AIFlowCoordinator reset clears state properly.
    /// AC5: Option to retry or start over is provided.
    func testAIFlowCoordinator_Reset_ClearsState() async {
        // Given: AIFlowCoordinator in error state
        let coordinator = AIFlowCoordinator()
        coordinator.setError(AIFlowError.processingFailed("Test"))

        // When: Resetting
        coordinator.reset()

        // Then: Should be back to idle state
        XCTAssertEqual(coordinator.captureState, .idle, "Should reset to idle state")
        XCTAssertEqual(coordinator.processingProgress, 0.0, "Progress should be reset")
        XCTAssertNil(coordinator.captureSessionData, "Session data should be nil")
    }

    /// Test that AIFlowCoordinator output warnings can be cleared.
    /// AC5: Supports "Continue Anyway" flow from warning sheet.
    func testAIFlowCoordinator_ClearOutputWarnings() async {
        // Given: AIFlowCoordinator (warnings would be set by adaptAndStoreOutput)
        let coordinator = AIFlowCoordinator()

        // When: Clearing warnings
        coordinator.clearOutputWarnings()

        // Then: Warnings should be empty
        XCTAssertTrue(coordinator.outputWarnings.isEmpty, "Output warnings should be cleared")
    }

    /// Test that AICaptureState error equality works correctly.
    /// AC5: Error states can be compared for UI logic.
    func testAICaptureState_ErrorEquality() {
        // Given: Two error states with same message
        let error1 = AIFlowError.processingFailed("Same message")
        let error2 = AIFlowError.processingFailed("Same message")
        let state1: AICaptureState = .error(error1)
        let state2: AICaptureState = .error(error2)

        // Then: Should be equal (by localized description)
        XCTAssertEqual(state1, state2, "Error states with same message should be equal")

        // Given: Two error states with different messages
        let error3 = AIFlowError.processingFailed("Different message")
        let state3: AICaptureState = .error(error3)

        // Then: Should not be equal
        XCTAssertNotEqual(state1, state3, "Error states with different messages should not be equal")
    }

    /// Test that AIFlowError provides meaningful error descriptions.
    /// AC5: User sees appropriate error message.
    func testAIFlowError_HasMeaningfulDescriptions() {
        // Test each error type has a non-empty description
        let errors: [AIFlowError] = [
            .captureNotReady,
            .processingFailed("test reason"),
            .calibrationFailed,
            .insufficientData,
            .notImplemented
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have error description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }

        // Verify processing failed includes the reason
        let processingError = AIFlowError.processingFailed("custom reason")
        XCTAssertTrue(processingError.errorDescription!.contains("custom reason"),
                     "Processing error should include the failure reason")
    }

    // MARK: - Screen Equatable Tests

    /// Test that AppState.Screen enum is properly equatable.
    func testScreenEquatable_Selection() {
        // Given: Two selection screens
        let screen1: AppState.Screen = .selection
        let screen2: AppState.Screen = .selection

        // Then: Should be equal
        XCTAssertEqual(screen1, screen2, "Selection screens should be equal")
    }

    /// Test that AppState.Screen enum differentiates screens.
    func testScreenEquatable_DifferentScreens() {
        // Given: Different screens
        let selection: AppState.Screen = .selection
        let review: AppState.Screen = .review

        // Then: Should not be equal
        XCTAssertNotEqual(selection, review, "Different screens should not be equal")
    }

    // MARK: - Helper Methods

    /// Creates test MeasurementData with AI flow fields populated.
    private func createTestMeasurementData() -> MeasurementData {
        return MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 25.0,
            totalSqFt: 150.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "https://example.com/floorplan.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: AIMetadata(
                calibrationMethod: "autoCountertop",
                calibrationConfidence: 0.85,
                overallConfidence: 0.75,
                processingTimeMs: 5000,
                modelVersions: ["depth_anything": "v2_small"],
                needsVerification: false,
                frameCount: 100,
                photoCount: 3,
                scaleFactor: 1.0,
                coveragePercentage: 85.0,
                warnings: nil
            )
        )
    }

    /// Creates a ShowroomConfig for testing via JSON decoding.
    private func createShowroomConfig(withCategories: Bool) throws -> ShowroomConfig {
        let categoriesJSON: String
        if withCategories {
            categoriesJSON = """
            [{
                "id": "cat-1",
                "category_id": "cat-1",
                "name": "Test Category",
                "slug": "test-category",
                "pricing_unit": "per_linear_ft",
                "display_order": 0,
                "is_required": false,
                "show_price_to_customer": true,
                "products": []
            }]
            """
        } else {
            categoriesJSON = "[]"
        }

        let json = """
        {
            "id": "test-showroom",
            "showroom_code": "TEST",
            "name": "Test Showroom",
            "branding": {
                "logo_url": null,
                "logo_dark_url": null
            },
            "categories": \(categoriesJSON),
            "addons": []
        }
        """

        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(ShowroomConfig.self, from: data)
    }

    /// Creates a test CustomerInfo via JSON decoding.
    private func createTestCustomerInfo() throws -> CustomerInfo {
        let json = """
        {
            "first_name": "Test",
            "last_name": "User",
            "email": "test@example.com",
            "phone": "555-1234",
            "customer_type": "homeowner"
        }
        """
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(CustomerInfo.self, from: data)
    }

    /// Creates a test ProjectSubmission for testing.
    private func createTestProjectSubmission() throws -> ProjectSubmission {
        return ProjectSubmission(
            showroomId: "test-showroom-id",
            customer: try createTestCustomerInfo(),
            endClient: nil,
            project: ProjectInfo(name: "Test Room", notes: nil),
            measurements: createTestMeasurementData(),
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )
    }
}
