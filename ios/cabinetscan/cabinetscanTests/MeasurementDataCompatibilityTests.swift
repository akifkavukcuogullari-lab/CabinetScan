//
//  MeasurementDataCompatibilityTests.swift
//  cabinetscanTests
//
//  Phase 5.4: Verify LiDAR and AI flow produce compatible MeasurementData.
//  Server Pipeline V2
//
//  Both scan methods must serialize identically for submit-project and dashboard.
//

import XCTest
@testable import cabinetscan

@MainActor
final class MeasurementDataCompatibilityTests: XCTestCase {

    // MARK: - Helpers

    private func createLiDARMeasurementData() -> MeasurementData {
        return MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: ["key": AnyCodable("value")],
            totalLinearFt: 20.0,
            totalSqFt: 150.0,
            wallCount: 4,
            windowCount: 1,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: "https://storage.example.com/room.usdz",
            glbFileUrl: nil,
            previewImageUrl: "https://storage.example.com/preview.jpg",
            videoUrl: "https://storage.example.com/video.mp4",
            videoThumbnailUrl: "https://storage.example.com/thumb.jpg",
            videoDurationSeconds: 60,
            videoSizeBytes: 15_000_000,
            videoResolution: "1920x1080",
            videoFormat: "mp4",
            visualizationPhotoUrls: ["photo1.jpg", "photo2.jpg"],
            scanMethod: .lidar,
            aiMetadata: nil,
            posesUrl: nil,
            planesUrl: nil,
            processingJobId: nil
        )
    }

    private func createAIFlowMeasurementData() -> MeasurementData {
        let adapter = ServerResultAdapter()
        let result = ServerPipelineResult(
            measurementsData: [
                "room_name": "Kitchen",
                "room_type": "kitchen",
                "total_linear_ft": 20.0,
                "total_sq_ft": 150.0,
                "wall_count": 4,
                "window_count": 1,
                "door_count": 1,
            ],
            floorPlanURL: "https://storage.example.com/floor_plan.png",
            validationPassed: true,
            validationIssues: [],
            processingTimeMs: 45000,
            scaleConfidence: "high",
            pipelineVersion: "v2"
        )
        let context = UploadContext(
            videoUrl: "https://storage.example.com/video.mp4",
            videoThumbnailUrl: "https://storage.example.com/thumb.jpg",
            videoDurationSeconds: 60,
            videoSizeBytes: 15_000_000,
            videoResolution: "1920x1080",
            photoUrls: ["photo1.jpg", "photo2.jpg"],
            posesUrl: nil,
            planesUrl: nil,
            processingJobId: nil
        )
        return adapter.convert(result: result, uploadContext: context)
    }

    // MARK: - ScanMethod Enum Tests

    func testScanMethodHasBothCases() {
        let allCases = ScanMethod.allCases
        XCTAssertTrue(allCases.contains(.lidar))
        XCTAssertTrue(allCases.contains(.aiFlow))
        XCTAssertEqual(allCases.count, 2)
    }

    func testScanMethodRawValues() {
        XCTAssertEqual(ScanMethod.lidar.rawValue, "lidar")
        XCTAssertEqual(ScanMethod.aiFlow.rawValue, "ai_flow")
    }

    // MARK: - Both Flows Produce Valid JSON

    func testLiDARData_SerializesToJSON() throws {
        let data = createLiDARMeasurementData()
        let jsonData = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["scan_method"] as? String, "lidar")
        XCTAssertEqual(json?["room_name"] as? String, "Kitchen")
    }

    func testAIFlowData_SerializesToJSON() throws {
        let data = createAIFlowMeasurementData()
        let jsonData = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["scan_method"] as? String, "ai_flow")
        XCTAssertEqual(json?["room_name"] as? String, "Kitchen")
    }

    // MARK: - Shared Fields Match

    func testBothFlows_ShareCommonMeasurementFields() {
        let lidar = createLiDARMeasurementData()
        let ai = createAIFlowMeasurementData()

        // Room-level fields should match when given same input
        XCTAssertEqual(lidar.roomName, ai.roomName)
        XCTAssertEqual(lidar.roomType, ai.roomType)
        XCTAssertEqual(lidar.totalLinearFt, ai.totalLinearFt)
        XCTAssertEqual(lidar.totalSqFt, ai.totalSqFt)
        XCTAssertEqual(lidar.wallCount, ai.wallCount)
        XCTAssertEqual(lidar.windowCount, ai.windowCount)
        XCTAssertEqual(lidar.doorCount, ai.doorCount)
    }

    func testBothFlows_ShareVideoFields() {
        let lidar = createLiDARMeasurementData()
        let ai = createAIFlowMeasurementData()

        XCTAssertEqual(lidar.videoUrl, ai.videoUrl)
        XCTAssertEqual(lidar.videoThumbnailUrl, ai.videoThumbnailUrl)
        XCTAssertEqual(lidar.videoDurationSeconds, ai.videoDurationSeconds)
        XCTAssertEqual(lidar.videoSizeBytes, ai.videoSizeBytes)
        XCTAssertEqual(lidar.videoResolution, ai.videoResolution)
        XCTAssertEqual(lidar.videoFormat, ai.videoFormat)
    }

    func testBothFlows_SharePhotoUrls() {
        let lidar = createLiDARMeasurementData()
        let ai = createAIFlowMeasurementData()

        XCTAssertEqual(lidar.visualizationPhotoUrls?.count, ai.visualizationPhotoUrls?.count)
    }

    // MARK: - Flow-Specific Fields

    func testLiDARFlow_HasUsdzFile() {
        let lidar = createLiDARMeasurementData()
        XCTAssertNotNil(lidar.usdzFileUrl, "LiDAR flow should have USDZ file")
    }

    func testAIFlow_HasNoUsdzFile() {
        let ai = createAIFlowMeasurementData()
        XCTAssertNil(ai.usdzFileUrl, "AI flow should not have USDZ file")
    }

    func testLiDARFlow_HasNoAIMetadata() {
        let lidar = createLiDARMeasurementData()
        XCTAssertNil(lidar.aiMetadata, "LiDAR flow should have nil aiMetadata")
    }

    func testAIFlow_HasAIMetadata() {
        let ai = createAIFlowMeasurementData()
        XCTAssertNotNil(ai.aiMetadata, "AI flow should have aiMetadata")
        XCTAssertEqual(ai.aiMetadata?.calibrationMethod, "multi_reference")
    }

    func testLiDARFlow_HasRoomplanData() {
        let lidar = createLiDARMeasurementData()
        XCTAssertFalse(lidar.roomplanData.isEmpty, "LiDAR flow should have roomplanData")
    }

    func testAIFlow_HasEmptyRoomplanData() {
        let ai = createAIFlowMeasurementData()
        XCTAssertTrue(ai.roomplanData.isEmpty, "AI flow should have empty roomplanData")
    }

    // MARK: - JSON Key Compatibility

    /// Verify both flows produce the same JSON keys for shared fields.
    func testBothFlows_ProduceSameJSONKeys() throws {
        let lidarJSON = try encodeToDict(createLiDARMeasurementData())
        let aiJSON = try encodeToDict(createAIFlowMeasurementData())

        // Keys that must be present in BOTH flows
        let requiredSharedKeys = [
            "room_name", "room_type", "roomplan_data",
            "total_linear_ft", "total_sq_ft",
            "wall_count", "window_count", "door_count",
            "video_url", "video_thumbnail_url",
            "video_duration_seconds", "video_size_bytes",
            "video_resolution", "video_format",
            "scan_method",
        ]

        for key in requiredSharedKeys {
            XCTAssertTrue(lidarJSON.keys.contains(key), "LiDAR JSON missing key: \(key)")
            XCTAssertTrue(aiJSON.keys.contains(key), "AI Flow JSON missing key: \(key)")
        }
    }

    /// Verify AI flow includes ai_metadata key in JSON.
    func testAIFlow_JSONHasAIMetadataKey() throws {
        let aiJSON = try encodeToDict(createAIFlowMeasurementData())
        XCTAssertNotNil(aiJSON["ai_metadata"], "AI flow JSON should have ai_metadata key")

        let aiMeta = aiJSON["ai_metadata"] as? [String: Any]
        XCTAssertNotNil(aiMeta?["calibration_method"])
        XCTAssertNotNil(aiMeta?["calibration_confidence"])
        XCTAssertNotNil(aiMeta?["processing_time_ms"])
        XCTAssertNotNil(aiMeta?["model_versions"])
        XCTAssertNotNil(aiMeta?["needs_verification"])
    }

    // MARK: - AppState Compatibility

    /// Both flows should route through AppState.setMeasurementData identically.
    func testBothFlows_RouteToSelectionWithCategories() throws {
        let lidar = createLiDARMeasurementData()
        let ai = createAIFlowMeasurementData()
        let config = try createShowroomConfig(withCategories: true)

        let appStateLiDAR = AppState()
        appStateLiDAR.showroomConfig = config
        appStateLiDAR.setMeasurementData(lidar)

        let appStateAI = AppState()
        appStateAI.showroomConfig = config
        appStateAI.setMeasurementData(ai)

        XCTAssertEqual(appStateLiDAR.currentScreen, appStateAI.currentScreen,
            "Both flows should route to the same screen")
        XCTAssertEqual(appStateLiDAR.currentScreen, .selection)
    }

    /// Both flows should route to review when no categories.
    func testBothFlows_RouteToReviewWithoutCategories() throws {
        let lidar = createLiDARMeasurementData()
        let ai = createAIFlowMeasurementData()
        let config = try createShowroomConfig(withCategories: false)

        let appStateLiDAR = AppState()
        appStateLiDAR.showroomConfig = config
        appStateLiDAR.setMeasurementData(lidar)

        let appStateAI = AppState()
        appStateAI.showroomConfig = config
        appStateAI.setMeasurementData(ai)

        XCTAssertEqual(appStateLiDAR.currentScreen, appStateAI.currentScreen)
        XCTAssertEqual(appStateLiDAR.currentScreen, .review)
    }

    // MARK: - ProjectSubmission Compatibility

    /// Both flows should produce a valid ProjectSubmission.
    func testBothFlows_ProduceValidProjectSubmission() throws {
        let customer = try JSONDecoder().decode(
            CustomerInfo.self,
            from: """
            {
                "first_name": "Test",
                "last_name": "User",
                "email": "test@example.com",
                "phone": "555-1234",
                "customer_type": "homeowner"
            }
            """.data(using: .utf8)!
        )

        let lidarSubmission = ProjectSubmission(
            showroomId: "test",
            customer: customer,
            endClient: nil,
            project: ProjectInfo(name: "Test", notes: nil),
            measurements: createLiDARMeasurementData(),
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )

        let aiSubmission = ProjectSubmission(
            showroomId: "test",
            customer: customer,
            endClient: nil,
            project: ProjectInfo(name: "Test", notes: nil),
            measurements: createAIFlowMeasurementData(),
            selections: [],
            addonSelections: [],
            deviceInfo: nil,
            consent: nil
        )

        // Both should encode without error
        let encoder = JSONEncoder()
        let lidarData = try encoder.encode(lidarSubmission)
        let aiData = try encoder.encode(aiSubmission)

        XCTAssertGreaterThan(lidarData.count, 0)
        XCTAssertGreaterThan(aiData.count, 0)

        // Both should produce valid JSON
        let lidarJSON = try JSONSerialization.jsonObject(with: lidarData) as? [String: Any]
        let aiJSON = try JSONSerialization.jsonObject(with: aiData) as? [String: Any]

        XCTAssertNotNil(lidarJSON?["measurements"])
        XCTAssertNotNil(aiJSON?["measurements"])
    }

    // MARK: - Helpers

    private func encodeToDict(_ data: MeasurementData) throws -> [String: Any] {
        let jsonData = try JSONEncoder().encode(data)
        return try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
    }

    private func createShowroomConfig(withCategories: Bool) throws -> ShowroomConfig {
        let categoriesJSON = withCategories ? """
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
        """ : "[]"

        let json = """
        {
            "id": "test-showroom",
            "showroom_code": "TEST",
            "name": "Test Showroom",
            "branding": { "logo_url": null, "logo_dark_url": null },
            "categories": \(categoriesJSON),
            "addons": []
        }
        """
        return try JSONDecoder().decode(ShowroomConfig.self, from: json.data(using: .utf8)!)
    }
}
