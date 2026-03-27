//
//  ServerResultAdapterTests.swift
//  cabinetscanTests
//
//  Phase 2.2-test: ServerResultAdapter unit tests
//  Server Pipeline V2
//

import XCTest
@testable import cabinetscan

final class ServerResultAdapterTests: XCTestCase {

    private var adapter: ServerResultAdapter!

    override func setUp() {
        super.setUp()
        adapter = ServerResultAdapter()
    }

    override func tearDown() {
        adapter = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeResult(
        measurementsData: [String: Any] = [:],
        floorPlanURL: String? = "https://example.com/floor_plan.png",
        validationPassed: Bool = true,
        validationIssues: [String] = [],
        processingTimeMs: Int = 5000,
        scaleConfidence: String? = "high",
        pipelineVersion: String? = "v2"
    ) -> ServerPipelineResult {
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

    private func makeUploadContext() -> UploadContext {
        return UploadContext(
            videoUrl: "https://example.com/video.mp4",
            videoThumbnailUrl: "https://example.com/thumb.jpg",
            videoDurationSeconds: 60,
            videoSizeBytes: 10_000_000,
            videoResolution: "1920x1080",
            photoUrls: ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
            posesUrl: nil,
            planesUrl: nil,
            processingJobId: nil
        )
    }

    // MARK: - Basic Conversion Tests

    func testConvertProducesMeasurementData() {
        let result = makeResult(measurementsData: [
            "room_name": "Kitchen",
            "total_linear_ft": 18.5,
            "wall_count": 3,
        ])
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.roomName, "Kitchen")
        XCTAssertEqual(data.totalLinearFt, 18.5)
        XCTAssertEqual(data.wallCount, 3)
    }

    func testScanMethodIsAIFlow() {
        let result = makeResult()
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.scanMethod, .aiFlow)
    }

    func testAIMetadataPopulated() {
        let result = makeResult(processingTimeMs: 8000, scaleConfidence: "high")
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertNotNil(data.aiMetadata)
        XCTAssertEqual(data.aiMetadata?.processingTimeMs, 8000)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.9) // "high" maps to 0.9
    }

    func testVideoFieldsFromUploadContext() {
        let result = makeResult()
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.videoUrl, "https://example.com/video.mp4")
        XCTAssertEqual(data.videoThumbnailUrl, "https://example.com/thumb.jpg")
        XCTAssertEqual(data.videoDurationSeconds, 60)
        XCTAssertEqual(data.videoSizeBytes, 10_000_000)
        XCTAssertEqual(data.videoResolution, "1920x1080")
        XCTAssertEqual(data.videoFormat, "mp4")
    }

    func testPhotoURLsFromUploadContext() {
        let result = makeResult()
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.visualizationPhotoUrls?.count, 2)
    }

    func testFloorPlanURLMappedToPreviewImage() {
        let result = makeResult(floorPlanURL: "https://example.com/plan.png")
        let context = makeUploadContext()

        let data = adapter.convert(result: result, uploadContext: context)

        XCTAssertEqual(data.previewImageUrl, "https://example.com/plan.png")
    }

    // MARK: - Confidence Mapping

    func testHighConfidenceMapping() {
        let result = makeResult(scaleConfidence: "high")
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.9)
    }

    func testMediumConfidenceMapping() {
        let result = makeResult(scaleConfidence: "medium")
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.7)
    }

    func testLowConfidenceMapping() {
        let result = makeResult(scaleConfidence: "low")
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.5)
    }

    func testNilConfidenceDefaultsToMedium() {
        let result = makeResult(scaleConfidence: nil)
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.calibrationConfidence, 0.7)
    }

    // MARK: - Validation

    func testValidationPassedSetsNeedsVerificationFalse() {
        let result = makeResult(validationPassed: true)
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.needsVerification, false)
    }

    func testValidationFailedSetsNeedsVerificationTrue() {
        let result = makeResult(validationPassed: false)
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.needsVerification, true)
    }

    func testValidationIssuesInWarnings() {
        let issues = ["Wall count mismatch", "Missing refrigerator"]
        let result = makeResult(validationIssues: issues)
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.aiMetadata?.warnings, issues)
    }

    func testEmptyValidationIssuesNilWarnings() {
        let result = makeResult(validationIssues: [])
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertNil(data.aiMetadata?.warnings)
    }

    // MARK: - Missing Fields

    func testDefaultRoomName() {
        let result = makeResult(measurementsData: [:])
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertEqual(data.roomName, "Kitchen")
    }

    func testMissingOptionalFields() {
        let result = makeResult(measurementsData: [:])
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertNil(data.totalLinearFt)
        XCTAssertNil(data.wallCount)
        XCTAssertNil(data.windowCount)
        XCTAssertNil(data.doorCount)
    }

    func testNoRoomPlanData() {
        let result = makeResult()
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertTrue(data.roomplanData.isEmpty, "AI flow should have empty roomplanData")
    }

    func testNoUSDZFile() {
        let result = makeResult()
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertNil(data.usdzFileUrl, "AI flow should not have USDZ file")
    }

    // MARK: - Measurements Dictionary

    func testMeasurementsDictionaryMapped() {
        let result = makeResult(measurementsData: [
            "measurements": [
                "walls": [["id": "wall_1", "length_ft": 10.0]],
                "base_cabinet_count": 5,
            ] as [String: Any]
        ])
        let context = makeUploadContext()
        let data = adapter.convert(result: result, uploadContext: context)
        XCTAssertNotNil(data.measurements)
    }
}
