//
//  AIFlowIntegrationTests.swift
//  cabinetscanTests
//
//  Phase 5.1: AI Flow Integration Tests — Server Pipeline V2
//
//  Verifies the complete flow from server result → ServerResultAdapter → MeasurementData
//  → AppState.setMeasurementData → screen transition, using mock server responses.
//

import XCTest
@testable import cabinetscan

@MainActor
final class AIFlowIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a mock ServerPipelineResult simulating a successful server response.
    private func makeServerResult(
        roomName: String = "Kitchen",
        totalLinearFt: Double = 18.5,
        wallCount: Int = 3,
        windowCount: Int = 1,
        doorCount: Int = 1,
        totalSqFt: Double = 120.0,
        floorPlanURL: String? = "https://storage.example.com/floor_plan.png",
        validationPassed: Bool = true,
        validationIssues: [String] = [],
        processingTimeMs: Int = 45000,
        scaleConfidence: String = "high",
        pipelineVersion: String = "v2"
    ) -> ServerPipelineResult {
        let measurementsData: [String: Any] = [
            "room_name": roomName,
            "room_type": "kitchen",
            "total_linear_ft": totalLinearFt,
            "total_sq_ft": totalSqFt,
            "wall_count": wallCount,
            "window_count": windowCount,
            "door_count": doorCount,
            "calibration_method": "multi_reference",
            "overall_confidence": 0.85,
            "frame_count": 90,
            "photo_count": 5,
            "scale_factor": 1.02,
            "coverage_percentage": 92.0,
            "model_versions": [
                "depth": "video_depth_anything_v2",
                "segmentation": "sam3",
                "pipeline": pipelineVersion
            ],
            "measurements": [
                "walls": [
                    ["id": "wall_1", "length_ft": 8.0],
                    ["id": "wall_2", "length_ft": 6.5],
                    ["id": "wall_3", "length_ft": 4.0],
                ] as [[String: Any]],
                "base_cabinet_count": 5,
                "upper_cabinet_count": 4,
            ] as [String: Any],
        ]

        return ServerPipelineResult(
            measurementsData: measurementsData,
            floorPlanURL: floorPlanURL,
            validationPassed: validationPassed,
            validationIssues: validationIssues,
            processingTimeMs: processingTimeMs,
            scaleConfidence: scaleConfidence,
            pipelineVersion: pipelineVersion
        )
    }

    /// Creates a mock UploadContext simulating data from the upload phase.
    private func makeUploadContext() -> UploadContext {
        return UploadContext(
            videoUrl: "https://storage.example.com/demo/ai_video_123.mp4",
            videoThumbnailUrl: "https://storage.example.com/demo/ai_video_thumb_123.jpg",
            videoDurationSeconds: 45,
            videoSizeBytes: 12_000_000,
            videoResolution: "1920x1080",
            photoUrls: [
                "https://storage.example.com/demo/ai_photo_1.jpg",
                "https://storage.example.com/demo/ai_photo_2.jpg",
                "https://storage.example.com/demo/ai_photo_3.jpg",
            ]
        )
    }

    /// Creates a ShowroomConfig for testing.
    private func createShowroomConfig(withCategories: Bool) throws -> ShowroomConfig {
        let categoriesJSON: String
        if withCategories {
            categoriesJSON = """
            [{
                "id": "cat-1",
                "category_id": "cat-1",
                "name": "Cabinets",
                "slug": "cabinets",
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

    // MARK: - Full Flow Tests

    /// Test complete flow: server result → adapter → MeasurementData → AppState → selection screen.
    func testFullFlow_ServerResultToSelectionScreen() throws {
        let result = makeServerResult()
        let context = makeUploadContext()

        // 1. Convert server result to MeasurementData
        let adapter = ServerResultAdapter()
        let measurementData = adapter.convert(result: result, uploadContext: context)

        // 2. Set on AppState
        let appState = AppState()
        appState.showroomConfig = try createShowroomConfig(withCategories: true)
        appState.setMeasurementData(measurementData)

        // 3. Verify state transition
        XCTAssertEqual(appState.currentScreen, .selection,
            "Should navigate to selection screen when categories exist")
        XCTAssertNotNil(appState.measurementData,
            "MeasurementData should be stored in AppState")
    }

    /// Test flow routes to review when no categories.
    func testFullFlow_ServerResultToReviewScreen_WhenNoCategories() throws {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let measurementData = adapter.convert(result: result, uploadContext: context)

        let appState = AppState()
        appState.showroomConfig = try createShowroomConfig(withCategories: false)
        appState.setMeasurementData(measurementData)

        XCTAssertEqual(appState.currentScreen, .review,
            "Should navigate to review screen when no categories")
    }

    // MARK: - MeasurementData Field Verification

    /// Verify all measurement fields are correctly populated from server result.
    func testConvertedData_HasAllMeasurementFields() {
        let result = makeServerResult(
            roomName: "Kitchen",
            totalLinearFt: 18.5,
            wallCount: 3,
            windowCount: 1,
            doorCount: 1,
            totalSqFt: 120.0
        )
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.roomName, "Kitchen")
        XCTAssertEqual(data.roomType, "kitchen")
        XCTAssertEqual(data.totalLinearFt, 18.5)
        XCTAssertEqual(data.totalSqFt, 120.0)
        XCTAssertEqual(data.wallCount, 3)
        XCTAssertEqual(data.windowCount, 1)
        XCTAssertEqual(data.doorCount, 1)
    }

    /// Verify AI-specific fields are set correctly.
    func testConvertedData_HasAIFlowFields() {
        let result = makeServerResult(scaleConfidence: "high", pipelineVersion: "v2")
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.scanMethod, .aiFlow)
        XCTAssertNotNil(data.aiMetadata)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.9)
        XCTAssertEqual(data.aiMetadata?.calibrationMethod, "multi_reference")
        XCTAssertFalse(data.aiMetadata?.needsVerification ?? true)
        XCTAssertEqual(data.aiMetadata?.processingTimeMs, 45000)
    }

    /// Verify video/media fields come from upload context, not server result.
    func testConvertedData_MediaFieldsFromUploadContext() {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.videoUrl, "https://storage.example.com/demo/ai_video_123.mp4")
        XCTAssertEqual(data.videoThumbnailUrl, "https://storage.example.com/demo/ai_video_thumb_123.jpg")
        XCTAssertEqual(data.videoDurationSeconds, 45)
        XCTAssertEqual(data.videoSizeBytes, 12_000_000)
        XCTAssertEqual(data.videoResolution, "1920x1080")
        XCTAssertEqual(data.videoFormat, "mp4")
        XCTAssertEqual(data.visualizationPhotoUrls?.count, 3)
    }

    /// Verify floor plan URL maps to previewImageUrl.
    func testConvertedData_FloorPlanMapsToPreviewImage() {
        let result = makeServerResult(floorPlanURL: "https://storage.example.com/floor_plan.png")
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.previewImageUrl, "https://storage.example.com/floor_plan.png")
    }

    /// Verify AI flow produces no RoomPlan-specific data.
    func testConvertedData_NoRoomPlanData() {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertTrue(data.roomplanData.isEmpty, "AI flow should have empty roomplanData")
        XCTAssertNil(data.usdzFileUrl, "AI flow should not have USDZ file")
        XCTAssertNil(data.glbFileUrl, "AI flow should not have GLB file")
    }

    // MARK: - Validation Warning Flow

    /// Test that validation issues flow through to MeasurementData warnings.
    func testValidationIssues_FlowToWarnings() {
        let issues = ["Wall count mismatch", "Missing refrigerator"]
        let result = makeServerResult(validationPassed: false, validationIssues: issues)
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertTrue(data.aiMetadata?.needsVerification ?? false,
            "Failed validation should set needsVerification")
        XCTAssertEqual(data.aiMetadata?.warnings, issues)
    }

    /// Test that passing validation means no verification needed.
    func testValidationPassed_NoVerificationNeeded() {
        let result = makeServerResult(validationPassed: true, validationIssues: [])
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertFalse(data.aiMetadata?.needsVerification ?? true)
        XCTAssertNil(data.aiMetadata?.warnings)
    }

    // MARK: - Serialization Tests

    /// Verify the converted MeasurementData serializes to valid JSON for submit-project.
    func testConvertedData_SerializesToValidJSON() throws {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        XCTAssertNotNil(json, "Should produce valid JSON")
        XCTAssertEqual(json?["scan_method"] as? String, "ai_flow")
        XCTAssertNotNil(json?["ai_metadata"])
        XCTAssertEqual(json?["room_name"] as? String, "Kitchen")
        XCTAssertEqual(json?["video_format"] as? String, "mp4")
    }

    /// Verify AI flow MeasurementData can be used in ProjectSubmission.
    func testConvertedData_WorksInProjectSubmission() throws {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let measurementData = adapter.convert(result: result, uploadContext: context)

        let customerJSON = """
        {
            "first_name": "Test",
            "last_name": "User",
            "email": "test@example.com",
            "phone": "555-1234",
            "customer_type": "homeowner"
        }
        """
        let customer = try JSONDecoder().decode(
            CustomerInfo.self,
            from: customerJSON.data(using: .utf8)!
        )

        let submission = ProjectSubmission(
            showroomId: "test-showroom",
            customer: customer,
            endClient: nil,
            project: ProjectInfo(name: "Test Kitchen", notes: nil),
            measurements: measurementData,
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )

        // Should encode without error
        let encoder = JSONEncoder()
        let submissionData = try encoder.encode(submission)
        let submissionJSON = try JSONSerialization.jsonObject(with: submissionData) as? [String: Any]

        XCTAssertNotNil(submissionJSON)
        let measurements = submissionJSON?["measurements"] as? [String: Any]
        XCTAssertEqual(measurements?["scan_method"] as? String, "ai_flow")
    }

    // MARK: - Coordinator Error Flow Tests

    /// Test coordinator error sets error state.
    func testCoordinator_ErrorState_SetsCorrectly() {
        let coordinator = AIFlowCoordinator()

        let error = AIFlowError.processingFailed("Server timeout")
        coordinator.setError(error)

        if case .error(let capturedError) = coordinator.captureState {
            XCTAssertTrue(capturedError.localizedDescription.contains("Server timeout"))
        } else {
            XCTFail("Coordinator should be in error state")
        }
    }

    /// Test coordinator reset from error state.
    func testCoordinator_ResetFromError_ClearsAllState() {
        let coordinator = AIFlowCoordinator()

        coordinator.setError(AIFlowError.processingFailed("fail"))
        coordinator.reset()

        XCTAssertEqual(coordinator.captureState, .idle)
        XCTAssertEqual(coordinator.processingProgress, 0.0)
        XCTAssertNil(coordinator.captureSessionData)
        XCTAssertNil(coordinator.uploadStatus)
        XCTAssertTrue(coordinator.outputWarnings.isEmpty)
    }

    /// Test coordinator cancel clears state.
    func testCoordinator_Cancel_ClearsState() {
        let coordinator = AIFlowCoordinator()

        coordinator.cancelCapture()

        XCTAssertEqual(coordinator.captureState, .idle)
        XCTAssertEqual(coordinator.processingProgress, 0.0)
        XCTAssertNil(coordinator.uploadStatus)
    }

    // MARK: - Confidence Mapping Integration

    /// Test high confidence server result produces correct metadata.
    func testHighConfidence_ProducesExpectedMetadata() {
        let result = makeServerResult(scaleConfidence: "high")
        let context = makeUploadContext()
        let data = ServerResultAdapter().convert(result: result, uploadContext: context)

        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.9)
    }

    /// Test medium confidence.
    func testMediumConfidence_ProducesExpectedMetadata() {
        let result = makeServerResult(scaleConfidence: "medium")
        let context = makeUploadContext()
        let data = ServerResultAdapter().convert(result: result, uploadContext: context)

        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.7)
    }

    /// Test low confidence.
    func testLowConfidence_ProducesExpectedMetadata() {
        let result = makeServerResult(scaleConfidence: "low")
        let context = makeUploadContext()
        let data = ServerResultAdapter().convert(result: result, uploadContext: context)

        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.5)
    }

    // MARK: - Edge Cases

    /// Test server result with minimal data still produces valid MeasurementData.
    func testMinimalServerResult_ProducesValidData() throws {
        let result = ServerPipelineResult(
            measurementsData: [:],
            floorPlanURL: nil,
            validationPassed: true,
            validationIssues: [],
            processingTimeMs: 0,
            scaleConfidence: nil,
            pipelineVersion: nil
        )
        let context = UploadContext(
            videoUrl: "",
            videoThumbnailUrl: nil,
            videoDurationSeconds: 0,
            videoSizeBytes: 0,
            videoResolution: "unknown",
            photoUrls: []
        )

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        // Should still be valid MeasurementData
        XCTAssertEqual(data.scanMethod, .aiFlow)
        XCTAssertEqual(data.roomName, "Kitchen") // default
        XCTAssertTrue(data.roomplanData.isEmpty)

        // Should serialize without error
        let jsonData = try JSONEncoder().encode(data)
        XCTAssertGreaterThan(jsonData.count, 0)
    }

    /// Test server result with detailed measurements dictionary.
    func testDetailedMeasurements_MappedCorrectly() {
        let result = makeServerResult()
        let context = makeUploadContext()

        let adapter = ServerResultAdapter()
        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertNotNil(data.measurements, "Detailed measurements should be mapped")
    }
}
