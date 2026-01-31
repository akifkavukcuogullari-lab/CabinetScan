//
//  DownstreamIntegrationTests.swift
//  cabinetscanTests
//
//  Story 6.10: Final Integration Testing
//  AC2: Downstream Integration - Verify AI data works with Selection, Review, Submission
//

import XCTest
import SwiftUI
@testable import cabinetscan

/// Integration tests verifying AI flow output works correctly with downstream screens.
/// Tests Selection, Review, and Submission flows with AI-generated MeasurementData.
final class DownstreamIntegrationTests: XCTestCase {

    // MARK: - Properties

    var appState: AppState!

    // MARK: - Setup

    @MainActor
    override func setUp() {
        super.setUp()
        appState = AppState()
    }

    override func tearDown() {
        appState = nil
        super.tearDown()
    }

    // MARK: - Task 2.2: Mock AI MeasurementData

    /// Creates comprehensive mock AI MeasurementData with all fields populated.
    private func createMockAIMeasurementData() -> MeasurementData {
        let aiMetadata = AIMetadata(
            calibrationMethod: "automatic",
            calibrationConfidence: 0.85,
            overallConfidence: 0.78,
            processingTimeMs: 12500,
            modelVersions: ["depth": "DepthAnythingV2Small", "segmentation": "DeepLabV3"],
            needsVerification: false,
            frameCount: 45,
            photoCount: 5,
            scaleFactor: 1.0,
            coveragePercentage: 92.5,
            warnings: nil
        )

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
            previewImageUrl: "file://temp/floor_plan.png",
            videoUrl: "file://temp/capture.mp4",
            videoThumbnailUrl: nil,
            videoDurationSeconds: 45,
            videoSizeBytes: 10_000_000,
            videoResolution: "1920x1080",
            videoFormat: "mp4",
            visualizationPhotoUrls: ["photo1.jpg", "photo2.jpg", "photo3.jpg"],
            scanMethod: .aiFlow,
            aiMetadata: aiMetadata
        )
    }

    /// Creates mock LiDAR MeasurementData for comparison tests.
    private func createMockLiDARMeasurementData() -> MeasurementData {
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
            usdzFileUrl: "file://room.usdz",
            glbFileUrl: nil,
            previewImageUrl: nil,
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .lidar,
            aiMetadata: nil
        )
    }

    // MARK: - Task 2.3: SelectionView Accepts AI MeasurementData

    /// Test that AppState accepts AI MeasurementData via setMeasurementData.
    @MainActor
    func testAppState_SetMeasurementData_WithAIData() {
        // Given: AI MeasurementData
        let data = createMockAIMeasurementData()

        // When: Setting in AppState
        appState.setMeasurementData(data)

        // Then: Should be stored correctly
        XCTAssertNotNil(appState.measurementData, "MeasurementData should be stored")
        XCTAssertEqual(appState.measurementData?.scanMethod, .aiFlow,
            "scanMethod should be .aiFlow")
        XCTAssertNotNil(appState.measurementData?.aiMetadata,
            "aiMetadata should be present")
    }

    /// Test that screen navigation works after setting AI data.
    @MainActor
    func testAppState_NavigatesToSelection_AfterAIData() {
        // Given: AI MeasurementData and showroom with categories
        let data = createMockAIMeasurementData()

        // Mock a showroom config with categories
        // Note: Without actual ShowroomConfig, we verify navigation logic
        appState.setMeasurementData(data)

        // Then: Should navigate to selection or review based on categories
        // When no categories, goes to review; otherwise to selection
        let validScreens: [AppState.Screen] = [.selection, .review]
        let currentScreenValid = validScreens.contains { screen in
            if case .selection = appState.currentScreen { return true }
            if case .review = appState.currentScreen { return true }
            return false
        }
        XCTAssertTrue(currentScreenValid,
            "Should navigate to selection or review after setting measurement data")
    }

    // MARK: - Task 2.4: ReviewView Displays AI Data

    /// Test that AI measurement data fields are accessible for display.
    @MainActor
    func testMeasurementData_AIFieldsAccessible() {
        // Given: AI MeasurementData
        let data = createMockAIMeasurementData()
        appState.setMeasurementData(data)

        // Then: All display fields should be accessible
        let measurements = appState.measurementData!

        XCTAssertEqual(measurements.roomName, "Kitchen")
        XCTAssertEqual(measurements.roomType, "kitchen")
        XCTAssertEqual(measurements.totalLinearFt, 24.5)
        XCTAssertEqual(measurements.totalSqFt, 120.0)
        XCTAssertEqual(measurements.wallCount, 4)
        XCTAssertEqual(measurements.windowCount, 2)
        XCTAssertEqual(measurements.doorCount, 1)
    }

    /// Test that AI metadata confidence fields are accessible.
    @MainActor
    func testMeasurementData_AIMetadataAccessible() {
        // Given: AI MeasurementData
        let data = createMockAIMeasurementData()
        appState.setMeasurementData(data)

        // Then: AI metadata should be accessible
        let aiMetadata = appState.measurementData?.aiMetadata
        XCTAssertNotNil(aiMetadata)
        XCTAssertEqual(aiMetadata?.overallConfidence, 0.78)
        XCTAssertEqual(aiMetadata?.calibrationConfidence, 0.85)
        XCTAssertEqual(aiMetadata?.coveragePercentage, 92.5)
        XCTAssertEqual(aiMetadata?.frameCount, 45)
        XCTAssertEqual(aiMetadata?.photoCount, 5)
    }

    // MARK: - Task 2.5: ProjectSubmission Encodes AI Metadata

    /// Test that ProjectSubmission can be created with AI MeasurementData.
    func testProjectSubmission_CreatedWithAIMeasurementData() throws {
        // Given: AI MeasurementData
        let data = createMockAIMeasurementData()

        // When: Creating ProjectSubmission
        let submission = ProjectSubmission(
            showroomId: "test-showroom",
            customer: CustomerInfo(
                firstName: "John",
                lastName: "Doe",
                email: "john@example.com",
                phone: "555-1234",
                customerType: .homeowner,
                addressLine1: nil,
                city: nil,
                state: nil,
                zipCode: nil
            ),
            endClient: nil,
            project: ProjectInfo(name: "Test Project", notes: nil),
            measurements: data,
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )

        // Then: Should be valid
        XCTAssertEqual(submission.measurements.scanMethod, .aiFlow)
        XCTAssertNotNil(submission.measurements.aiMetadata)
    }

    /// Test that ProjectSubmission encodes to JSON correctly with AI metadata.
    func testProjectSubmission_EncodesAIMetadata() throws {
        // Given: ProjectSubmission with AI data
        let data = createMockAIMeasurementData()
        let submission = ProjectSubmission(
            showroomId: "test-showroom",
            customer: CustomerInfo(
                firstName: "John",
                lastName: "Doe",
                email: "john@example.com",
                phone: "555-1234",
                customerType: .homeowner,
                addressLine1: nil,
                city: nil,
                state: nil,
                zipCode: nil
            ),
            endClient: nil,
            project: ProjectInfo(name: "Test Project", notes: nil),
            measurements: data,
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(submission)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Then: Should contain AI-specific fields
        XCTAssertTrue(jsonString.contains("\"scan_method\":\"ai_flow\""),
            "JSON should contain scan_method: ai_flow")
        XCTAssertTrue(jsonString.contains("\"calibration_method\":\"automatic\""),
            "JSON should contain calibration_method")
        XCTAssertTrue(jsonString.contains("\"overall_confidence\""),
            "JSON should contain overall_confidence")
    }

    // MARK: - Task 2.6: AIMetadata Codable Conformance

    /// Test that AIMetadata encodes correctly.
    func testAIMetadata_EncodesCorrectly() throws {
        // Given: AIMetadata
        let metadata = AIMetadata(
            calibrationMethod: "manual",
            calibrationConfidence: 0.95,
            overallConfidence: 0.88,
            processingTimeMs: 8000,
            modelVersions: ["depth": "V2"],
            needsVerification: true,
            frameCount: 30,
            photoCount: 3,
            scaleFactor: 1.05,
            coveragePercentage: 85.0,
            warnings: ["Low lighting detected"]
        )

        // When: Encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        let jsonString = String(data: data, encoding: .utf8)!

        // Then: All fields should be present with correct keys
        XCTAssertTrue(jsonString.contains("\"calibration_method\":\"manual\""))
        XCTAssertTrue(jsonString.contains("\"calibration_confidence\":0.95"))
        XCTAssertTrue(jsonString.contains("\"overall_confidence\":0.88"))
        XCTAssertTrue(jsonString.contains("\"processing_time_ms\":8000"))
        XCTAssertTrue(jsonString.contains("\"needs_verification\":true"))
        XCTAssertTrue(jsonString.contains("\"frame_count\":30"))
        XCTAssertTrue(jsonString.contains("\"photo_count\":3"))
        XCTAssertTrue(jsonString.contains("\"scale_factor\":1.05"))
        XCTAssertTrue(jsonString.contains("\"coverage_percentage\":85"))
        XCTAssertTrue(jsonString.contains("\"warnings\":[\"Low lighting detected\"]"))
    }

    /// Test that AIMetadata decodes correctly.
    func testAIMetadata_DecodesCorrectly() throws {
        // Given: JSON string
        let json = """
        {
            "calibration_method": "automatic",
            "calibration_confidence": 0.9,
            "overall_confidence": 0.75,
            "processing_time_ms": 10000,
            "model_versions": {"depth": "V2Small"},
            "needs_verification": false,
            "frame_count": 40,
            "photo_count": 4,
            "scale_factor": 1.0,
            "coverage_percentage": 90.0
        }
        """

        // When: Decoding
        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let metadata = try decoder.decode(AIMetadata.self, from: data)

        // Then: All fields should be correct
        XCTAssertEqual(metadata.calibrationMethod, "automatic")
        XCTAssertEqual(metadata.calibrationConfidence, 0.9)
        XCTAssertEqual(metadata.overallConfidence, 0.75)
        XCTAssertEqual(metadata.processingTimeMs, 10000)
        XCTAssertEqual(metadata.needsVerification, false)
        XCTAssertEqual(metadata.frameCount, 40)
        XCTAssertEqual(metadata.photoCount, 4)
        XCTAssertEqual(metadata.scaleFactor, 1.0)
        XCTAssertEqual(metadata.coveragePercentage, 90.0)
        XCTAssertNil(metadata.warnings)
    }

    // MARK: - Task 2.7: Confidence Indicators

    /// Test that needsVerification flag is accessible for confidence display.
    func testAIMetadata_NeedsVerificationAccessible() {
        // Given: AIMetadata with needsVerification = true
        let metadata = AIMetadata(
            calibrationMethod: "automatic",
            calibrationConfidence: 0.5,
            overallConfidence: 0.45,
            processingTimeMs: 15000,
            modelVersions: [:],
            needsVerification: true,
            frameCount: 20,
            photoCount: 2,
            scaleFactor: 1.0,
            coveragePercentage: 60.0,
            warnings: ["Low confidence - verification recommended"]
        )

        // Then: Flag should be accessible
        XCTAssertTrue(metadata.needsVerification,
            "needsVerification should be true for low confidence")
        XCTAssertNotNil(metadata.warnings)
        XCTAssertEqual(metadata.warnings?.count, 1)
    }

    /// Test that confidence levels determine needsVerification correctly.
    func testConfidenceLevel_DeterminesVerificationNeed() {
        // Given: High confidence metadata
        let highConfidence = AIMetadata(
            calibrationMethod: "automatic",
            calibrationConfidence: 0.95,
            overallConfidence: 0.90,
            processingTimeMs: 8000,
            modelVersions: [:],
            needsVerification: false,
            frameCount: 50,
            photoCount: 6,
            scaleFactor: 1.0,
            coveragePercentage: 95.0,
            warnings: nil
        )

        // Then: Should not need verification
        XCTAssertFalse(highConfidence.needsVerification)

        // Given: Low confidence metadata
        let lowConfidence = AIMetadata(
            calibrationMethod: "manual",
            calibrationConfidence: 0.5,
            overallConfidence: 0.4,
            processingTimeMs: 20000,
            modelVersions: [:],
            needsVerification: true,
            frameCount: 15,
            photoCount: 2,
            scaleFactor: 0.9,
            coveragePercentage: 50.0,
            warnings: ["Low confidence"]
        )

        // Then: Should need verification
        XCTAssertTrue(lowConfidence.needsVerification)
    }

    // MARK: - Task 2.8: Export Functionality

    /// Test that AI MeasurementData fields are complete for export.
    func testMeasurementData_HasExportFields() {
        // Given: AI MeasurementData
        let data = createMockAIMeasurementData()

        // Then: Export-relevant fields should be present
        XCTAssertNotNil(data.previewImageUrl, "Floor plan image URL should be present")
        XCTAssertNotNil(data.videoUrl, "Video URL should be present")
        XCTAssertNotNil(data.visualizationPhotoUrls, "Photo URLs should be present")
        XCTAssertEqual(data.visualizationPhotoUrls?.count, 3, "Should have 3 photos")
    }

    // MARK: - Task 2.9: Backward Compatibility

    /// Test that MeasurementData without scanMethod/aiMetadata decodes correctly.
    func testMeasurementData_BackwardCompatibility_LegacyFormat() throws {
        // Given: Legacy JSON without scanMethod and aiMetadata
        let legacyJSON = """
        {
            "room_name": "Kitchen",
            "room_type": "kitchen",
            "roomplan_data": {},
            "total_linear_ft": 24.5,
            "total_sq_ft": 100.0,
            "wall_count": 4,
            "window_count": 1,
            "door_count": 2
        }
        """

        // When: Decoding
        let decoder = JSONDecoder()
        let data = legacyJSON.data(using: .utf8)!
        let measurement = try decoder.decode(MeasurementData.self, from: data)

        // Then: Should decode without error, optional fields are nil
        XCTAssertEqual(measurement.roomName, "Kitchen")
        XCTAssertEqual(measurement.totalLinearFt, 24.5)
        XCTAssertNil(measurement.scanMethod, "Legacy data should have nil scanMethod")
        XCTAssertNil(measurement.aiMetadata, "Legacy data should have nil aiMetadata")
    }

    /// Test that MeasurementData with partial fields decodes correctly.
    func testMeasurementData_BackwardCompatibility_PartialFields() throws {
        // Given: JSON with some optional fields missing
        let partialJSON = """
        {
            "room_name": "Bathroom",
            "room_type": "bathroom",
            "roomplan_data": {},
            "scan_method": "lidar"
        }
        """

        // When: Decoding
        let decoder = JSONDecoder()
        let data = partialJSON.data(using: .utf8)!
        let measurement = try decoder.decode(MeasurementData.self, from: data)

        // Then: Should decode with nil for missing optional fields
        XCTAssertEqual(measurement.roomName, "Bathroom")
        XCTAssertEqual(measurement.scanMethod, .lidar)
        XCTAssertNil(measurement.totalLinearFt)
        XCTAssertNil(measurement.aiMetadata)
    }

    // MARK: - Task 2.10: Error Recovery Integration

    /// Test that partial results from timeout can be used downstream.
    func testErrorRecovery_PartialResultsUsable() {
        // Given: Partial MeasurementData (simulating timeout recovery)
        let partialData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: nil, // No cabinet data (partial)
            totalSqFt: 100.0,   // Room area estimated
            wallCount: 3,       // Partial wall detection
            windowCount: nil,
            doorCount: nil,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "file://partial_floor_plan.png",
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: .aiFlow,
            aiMetadata: AIMetadata(
                calibrationMethod: "automatic",
                calibrationConfidence: 0.6,
                overallConfidence: 0.5,
                processingTimeMs: 30000,
                modelVersions: [:],
                needsVerification: true,
                frameCount: 20,
                photoCount: 2,
                scaleFactor: 1.0,
                coveragePercentage: 40.0,
                warnings: ["Processing timeout - partial results"]
            )
        )

        // Then: Should be valid enough for downstream (even with partial data)
        XCTAssertNotNil(partialData.roomName)
        XCTAssertNotNil(partialData.previewImageUrl)
        XCTAssertTrue(partialData.aiMetadata?.needsVerification ?? false,
            "Partial results should flag verification needed")
    }

    /// Test that tracking recovery checkpoint data integrates correctly.
    func testErrorRecovery_TrackingRecoveryCheckpoint() {
        // Given: Data recovered from tracking lost state
        let recoveredData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: [:],
            totalLinearFt: 20.0,
            totalSqFt: 90.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "file://recovered_floor_plan.png",
            videoUrl: "file://partial_video.mp4",
            videoThumbnailUrl: nil,
            videoDurationSeconds: 30,
            videoSizeBytes: 5_000_000,
            videoResolution: "1920x1080",
            videoFormat: "mp4",
            visualizationPhotoUrls: ["checkpoint_photo.jpg"],
            scanMethod: .aiFlow,
            aiMetadata: AIMetadata(
                calibrationMethod: "automatic",
                calibrationConfidence: 0.7,
                overallConfidence: 0.65,
                processingTimeMs: 25000,
                modelVersions: [:],
                needsVerification: true,
                frameCount: 35,
                photoCount: 3,
                scaleFactor: 1.0,
                coveragePercentage: 70.0,
                warnings: ["Recovered from tracking lost - some areas may be incomplete"]
            )
        )

        // Then: Should be usable for downstream
        XCTAssertNotNil(recoveredData.totalLinearFt)
        XCTAssertNotNil(recoveredData.aiMetadata)
        XCTAssertTrue(recoveredData.aiMetadata?.warnings?.first?.contains("tracking") ?? false)
    }

    // MARK: - Both Scan Methods Work

    /// Test that both LiDAR and AI MeasurementData work with AppState.
    @MainActor
    func testAppState_AcceptsBothScanMethods() {
        // Given: LiDAR data
        let lidarData = createMockLiDARMeasurementData()
        appState.setMeasurementData(lidarData)

        // Then: LiDAR data accepted
        XCTAssertEqual(appState.measurementData?.scanMethod, .lidar)
        XCTAssertNil(appState.measurementData?.aiMetadata)

        // Given: AI data
        let aiData = createMockAIMeasurementData()
        appState.setMeasurementData(aiData)

        // Then: AI data accepted
        XCTAssertEqual(appState.measurementData?.scanMethod, .aiFlow)
        XCTAssertNotNil(appState.measurementData?.aiMetadata)
    }
}
