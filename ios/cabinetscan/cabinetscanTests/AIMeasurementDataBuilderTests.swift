//
//  AIMeasurementDataBuilderTests.swift
//  cabinetscanTests
//
//  Created for Story 5.3: MeasurementData Builder
//  Updated for Story 5.4: MeasurementData Model Extension
//

import XCTest
import simd
@testable import cabinetscan

final class AIMeasurementDataBuilderTests: XCTestCase {

    // MARK: - Properties

    var builder: AIMeasurementDataBuilder!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        builder = AIMeasurementDataBuilder()
    }

    override func tearDown() {
        builder = nil
        super.tearDown()
    }

    // MARK: - Test Task 1.2: Build Method Signature

    func testBuildReturnsValidMeasurementData() {
        // Given: A pipeline result with minimal valid data
        let pipelineResult = createMockPipelineResult()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: MeasurementData is valid and populated
        XCTAssertNotNil(measurementData)
        XCTAssertEqual(measurementData.roomName, "Kitchen")
        XCTAssertEqual(measurementData.roomType, "kitchen")
    }

    // MARK: - Test Task 1.3: Full Signature with Optional Parameters

    func testBuildWithAllOptionalParameters() {
        // Given: Pipeline result with all optional parameters
        let pipelineResult = createMockPipelineResult()
        let captureSession = createMockCaptureSessionData()
        let floorPlanImageURL = URL(string: "file:///tmp/floor_plan.png")
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building with all parameters
        let measurementData = builder.build(
            from: pipelineResult,
            captureSession: captureSession,
            floorPlanImageURL: floorPlanImageURL,
            floorPlanJSON: floorPlanJSON
        )

        // Then: All data is integrated
        XCTAssertNotNil(measurementData)
        XCTAssertEqual(measurementData.previewImageUrl, "file:///tmp/floor_plan.png")
    }

    // MARK: - Test Task 1.4: Handle Optional Inputs Gracefully

    func testBuildWithNilRoomStructure() {
        // Given: Pipeline result with nil room structure
        let pipelineResult = createMockPipelineResultWithoutRoom()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Partial MeasurementData is returned without crashing
        XCTAssertNotNil(measurementData)
        XCTAssertEqual(measurementData.roomName, "Kitchen")
        XCTAssertEqual(measurementData.totalSqFt ?? 0, 0)
    }

    func testBuildWithNilCabinetDetectionResult() {
        // Given: Pipeline result with nil cabinet detection
        let pipelineResult = createMockPipelineResultWithoutCabinets()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Linear feet is 0
        XCTAssertNotNil(measurementData)
        XCTAssertEqual(measurementData.totalLinearFt ?? 0, 0)
    }

    // MARK: - Test Task 2: Room Data Conversion

    func testCalculateTotalLinearFeet() {
        // Given: Pipeline result with cabinet detection
        let pipelineResult = createMockPipelineResultWithCabinets(
            baseCabinets: [36, 24, 18], // 78" total base = 6.5 linear feet
            upperCabinets: [30, 30]     // 60" total upper = 5 linear feet
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Total linear feet = base + upper = 6.5 + 5 = 11.5
        XCTAssertEqual(measurementData.totalLinearFt ?? 0, 11.5, accuracy: 0.01)
    }

    func testCalculateTotalSquareFeet() {
        // Given: Pipeline result with room of 14400 sq inches (100 sq ft)
        let pipelineResult = createMockPipelineResultWithRoomArea(areaSquareInches: 14400)

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Total sq ft = 14400 / 144 = 100
        XCTAssertEqual(measurementData.totalSqFt ?? 0, 100, accuracy: 0.01)
    }

    func testExtractWallWindowDoorCounts() {
        // Given: Pipeline result with openings
        let pipelineResult = createMockPipelineResultWithOpenings(wallCount: 4, windowCount: 2, doorCount: 1)

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Counts are correctly extracted
        XCTAssertEqual(measurementData.wallCount, 4)
        XCTAssertEqual(measurementData.windowCount, 2)
        XCTAssertEqual(measurementData.doorCount, 1)
    }

    // MARK: - Test Task 3: roomplanData Dictionary

    func testBuildRoomplanData() {
        // Given: Pipeline result with detection data
        let pipelineResult = createMockPipelineResultWithOpenings(wallCount: 4, windowCount: 2, doorCount: 1)

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: roomplanData dictionary is populated
        XCTAssertNotNil(measurementData.roomplanData)
        XCTAssertNotNil(measurementData.roomplanData["walls"])
        XCTAssertNotNil(measurementData.roomplanData["doors"])
        XCTAssertNotNil(measurementData.roomplanData["windows"])
        XCTAssertNotNil(measurementData.roomplanData["floors"])
    }

    // MARK: - Test Task 4: measurements Dictionary

    func testBuildMeasurementsWithFloorPlanJSON() {
        // Given: Pipeline result with FloorPlanJSON
        let pipelineResult = createMockPipelineResult()
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // Then: measurements dictionary is populated
        XCTAssertNotNil(measurementData.measurements)
    }

    func testBuildMeasurementsIncludesAIMetadata() {
        // Given: Pipeline result
        let pipelineResult = createMockPipelineResult()
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // Then: AI metadata is included in measurements
        XCTAssertNotNil(measurementData.measurements)
        // The measurements dict should have ai_metadata key
        if let measurements = measurementData.measurements {
            XCTAssertNotNil(measurements["scan_method"] ?? measurements["scanMethod"])
        }
    }

    // MARK: - Test Task 5: File URL Integration

    func testFileURLIntegration() {
        // Given: Pipeline result with capture session and floor plan URL
        let pipelineResult = createMockPipelineResult()
        let captureSession = createMockCaptureSessionData()
        let floorPlanImageURL = URL(string: "file:///tmp/floor_plan.png")

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            captureSession: captureSession,
            floorPlanImageURL: floorPlanImageURL
        )

        // Then: File URLs are properly set
        XCTAssertEqual(measurementData.previewImageUrl, "file:///tmp/floor_plan.png")
        XCTAssertNotNil(measurementData.videoUrl)
        XCTAssertNil(measurementData.usdzFileUrl) // AI flow doesn't generate USDZ
        XCTAssertNil(measurementData.glbFileUrl)  // AI flow doesn't generate GLB
    }

    func testVisualizationPhotoUrls() {
        // Given: Capture session with photos
        let pipelineResult = createMockPipelineResult()
        let captureSession = createMockCaptureSessionDataWithPhotos(count: 3)

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            captureSession: captureSession
        )

        // Then: Photo URLs are populated
        XCTAssertNotNil(measurementData.visualizationPhotoUrls)
        XCTAssertEqual(measurementData.visualizationPhotoUrls?.count, 3)
    }

    // MARK: - Test Task 6: AI Metadata Integration

    func testNeedsVerificationFlagForLowConfidence() {
        // Given: Pipeline result with low overall confidence (<60%)
        let pipelineResult = createMockPipelineResultWithConfidence(overall: 0.5)
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // Then: AI metadata should include needsVerification flag
        XCTAssertNotNil(measurementData.measurements)
        if let measurements = measurementData.measurements,
           let aiMetadata = measurements["ai_metadata"] ?? measurements["aiMetadata"] {
            // The needsVerification should be true for low confidence
            if let metadata = aiMetadata.value as? [String: Any] {
                XCTAssertNotNil(metadata["needs_verification"] ?? metadata["needsVerification"])
            }
        }
    }

    // MARK: - Test Task 7: Cabinet Summary Calculations

    func testCabinetLinearFeetCalculations() {
        // Given: Pipeline result with specific cabinet widths
        let pipelineResult = createMockPipelineResultWithCabinets(
            baseCabinets: [36, 24],  // 60" = 5 linear feet
            upperCabinets: [36],     // 36" = 3 linear feet
            tallCabinets: [24]       // 24" = 2 linear feet
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: Linear feet totals are calculated
        // Note: totalLinearFt is base + upper only per existing formula
        XCTAssertEqual(measurementData.totalLinearFt ?? 0, 8.0, accuracy: 0.01)
    }

    // MARK: - Test: MeasurementData Encodes to JSON

    func testMeasurementDataEncodesToJSON() {
        // Given: A complete MeasurementData
        let pipelineResult = createMockPipelineResult()
        let measurementData = builder.build(from: pipelineResult)

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        // Then: Encoding succeeds without errors
        XCTAssertNoThrow(try encoder.encode(measurementData))
    }

    // MARK: - Story 5.4: ScanMethod Enum Tests

    func testScanMethodEnumEncodesToSnakeCase() throws {
        // Given: ScanMethod values
        let lidar = ScanMethod.lidar
        let aiFlow = ScanMethod.aiFlow

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        let lidarData = try encoder.encode(lidar)
        let aiFlowData = try encoder.encode(aiFlow)

        // Then: Values are snake_case
        let lidarString = String(data: lidarData, encoding: .utf8)
        let aiFlowString = String(data: aiFlowData, encoding: .utf8)

        XCTAssertEqual(lidarString, "\"lidar\"")
        XCTAssertEqual(aiFlowString, "\"ai_flow\"")
    }

    func testScanMethodEnumDecodesFromSnakeCase() throws {
        // Given: JSON with snake_case values
        let lidarJSON = "\"lidar\"".data(using: .utf8)!
        let aiFlowJSON = "\"ai_flow\"".data(using: .utf8)!

        // When: Decoding
        let decoder = JSONDecoder()
        let lidar = try decoder.decode(ScanMethod.self, from: lidarJSON)
        let aiFlow = try decoder.decode(ScanMethod.self, from: aiFlowJSON)

        // Then: Correct enum cases
        XCTAssertEqual(lidar, .lidar)
        XCTAssertEqual(aiFlow, .aiFlow)
    }

    func testScanMethodEnumIsCaseIterable() {
        // Then: All cases are iterable
        let allCases = ScanMethod.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.lidar))
        XCTAssertTrue(allCases.contains(.aiFlow))
    }

    // MARK: - Story 5.4: AIMetadata Struct Tests

    func testAIMetadataEncodesToJSON() throws {
        // Given: AIMetadata with all fields
        let metadata = AIMetadata(
            calibrationMethod: "autoCountertop",
            calibrationConfidence: 0.95,
            overallConfidence: 0.85,
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 300,
            photoCount: 5,
            scaleFactor: 1.0,
            coveragePercentage: 85.0,
            warnings: nil
        )

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys  // AIMetadata has explicit CodingKeys

        // Then: Encoding succeeds
        let data = try encoder.encode(metadata)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["calibration_method"] as? String, "autoCountertop")
        XCTAssertEqual(json?["calibration_confidence"] as? Double, 0.95)
        XCTAssertEqual(json?["overall_confidence"] as? Double, 0.85)
        XCTAssertEqual(json?["processing_time_ms"] as? Int, 5000)
        XCTAssertEqual(json?["needs_verification"] as? Bool, false)
        XCTAssertEqual(json?["frame_count"] as? Int, 300)
        XCTAssertEqual(json?["photo_count"] as? Int, 5)
        XCTAssertEqual(json?["scale_factor"] as? Double, 1.0)
        XCTAssertEqual(json?["coverage_percentage"] as? Double, 85.0)
    }

    func testAIMetadataDecodesFromJSON() throws {
        // Given: JSON with all AIMetadata fields
        let json: [String: Any] = [
            "calibration_method": "manualDoor",
            "calibration_confidence": 0.75,
            "overall_confidence": 0.65,
            "processing_time_ms": 8000,
            "model_versions": ["depth_anything": "v2_small"],
            "needs_verification": true,
            "frame_count": 200,
            "photo_count": 5,
            "scale_factor": 1.05,
            "coverage_percentage": 70.0,
            "warnings": ["Low lighting detected"]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // When: Decoding
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(AIMetadata.self, from: data)

        // Then: All fields decoded correctly
        XCTAssertEqual(metadata.calibrationMethod, "manualDoor")
        XCTAssertEqual(metadata.calibrationConfidence, 0.75)
        XCTAssertEqual(metadata.overallConfidence, 0.65)
        XCTAssertEqual(metadata.processingTimeMs, 8000)
        XCTAssertEqual(metadata.modelVersions["depth_anything"], "v2_small")
        XCTAssertTrue(metadata.needsVerification)
        XCTAssertEqual(metadata.frameCount, 200)
        XCTAssertEqual(metadata.photoCount, 5)
        XCTAssertEqual(metadata.scaleFactor, 1.05)
        XCTAssertEqual(metadata.coveragePercentage, 70.0)
        XCTAssertEqual(metadata.warnings?.count, 1)
        XCTAssertEqual(metadata.warnings?.first, "Low lighting detected")
    }

    func testAIMetadataWithNilWarnings() throws {
        // Given: JSON without warnings field
        let json: [String: Any] = [
            "calibration_method": "autoCountertop",
            "calibration_confidence": 0.9,
            "overall_confidence": 0.85,
            "processing_time_ms": 5000,
            "model_versions": [:],
            "needs_verification": false,
            "frame_count": 300,
            "photo_count": 5,
            "scale_factor": 1.0,
            "coverage_percentage": 85.0
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        // When: Decoding
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(AIMetadata.self, from: data)

        // Then: warnings is nil
        XCTAssertNil(metadata.warnings)
    }

    // MARK: - Story 5.4: MeasurementData Extension Tests

    func testMeasurementDataWithNilAIFieldsEncodesCorrectly() throws {
        // Given: MeasurementData created by LiDAR flow (nil AI fields)
        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: ["walls": AnyCodable(4)],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 2,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: "file:///test.usdz",
            glbFileUrl: nil,
            previewImageUrl: nil,
            videoUrl: nil,
            videoThumbnailUrl: nil,
            videoDurationSeconds: nil,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: nil,
            visualizationPhotoUrls: nil,
            scanMethod: nil,  // LiDAR flow: nil
            aiMetadata: nil   // LiDAR flow: nil
        )

        // When: Encoding to JSON
        // Note: MeasurementData has explicit CodingKeys, so no auto strategy needed
        let encoder = JSONEncoder()

        // Then: Encoding succeeds
        let data = try encoder.encode(measurementData)
        XCTAssertNotNil(data)

        // And: Can decode back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MeasurementData.self, from: data)
        XCTAssertEqual(decoded.roomName, "Kitchen")
        XCTAssertNil(decoded.scanMethod)
        XCTAssertNil(decoded.aiMetadata)
    }

    func testMeasurementDataWithAIFieldsEncodesCorrectly() throws {
        // Given: MeasurementData created by AI flow (with AI fields)
        let aiMetadata = AIMetadata(
            calibrationMethod: "autoCountertop",
            calibrationConfidence: 0.95,
            overallConfidence: 0.85,
            processingTimeMs: 5000,
            modelVersions: ["depth_anything": "v2_small"],
            needsVerification: false,
            frameCount: 300,
            photoCount: 5,
            scaleFactor: 1.0,
            coveragePercentage: 85.0,
            warnings: nil
        )

        let measurementData = MeasurementData(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: ["walls": AnyCodable(4)],
            totalLinearFt: 10.0,
            totalSqFt: 100.0,
            wallCount: 4,
            windowCount: 2,
            doorCount: 1,
            measurements: nil,
            usdzFileUrl: nil,
            glbFileUrl: nil,
            previewImageUrl: "file:///floor_plan.png",
            videoUrl: "file:///video.mp4",
            videoThumbnailUrl: nil,
            videoDurationSeconds: 60,
            videoSizeBytes: nil,
            videoResolution: nil,
            videoFormat: "mp4",
            visualizationPhotoUrls: ["file:///photo1.jpg"],
            scanMethod: .aiFlow,  // AI flow
            aiMetadata: aiMetadata
        )

        // When: Encoding to JSON
        let encoder = JSONEncoder()

        // Then: Encoding succeeds
        let data = try encoder.encode(measurementData)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["scan_method"] as? String, "ai_flow")
        XCTAssertNotNil(json?["ai_metadata"])
    }

    // MARK: - Story 5.4: AIMeasurementDataBuilder Integration Tests

    func testBuilderSetsScanMethodToAIFlow() {
        // Given: Pipeline result
        let pipelineResult = createMockPipelineResult()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: scanMethod is set to .aiFlow
        XCTAssertEqual(measurementData.scanMethod, .aiFlow)
    }

    func testBuilderPopulatesAIMetadata() {
        // Given: Pipeline result
        let pipelineResult = createMockPipelineResult()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: aiMetadata is populated with correct values
        XCTAssertNotNil(measurementData.aiMetadata)
        XCTAssertEqual(measurementData.aiMetadata?.calibrationMethod, "autoCountertop")
        XCTAssertEqual(measurementData.aiMetadata?.processingTimeMs, 5000)
        XCTAssertEqual(measurementData.aiMetadata?.frameCount, 300)
        XCTAssertEqual(measurementData.aiMetadata?.photoCount, 5)
        XCTAssertFalse(measurementData.aiMetadata?.needsVerification ?? true)
    }

    func testBuilderSetsNeedsVerificationForLowConfidenceInAIMetadata() {
        // Given: Pipeline result with low confidence
        let pipelineResult = createMockPipelineResultWithConfidence(overall: 0.5)

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: needsVerification is true in aiMetadata
        XCTAssertNotNil(measurementData.aiMetadata)
        XCTAssertTrue(measurementData.aiMetadata?.needsVerification ?? false)
    }

    func testBuilderKeepsAIMetadataInMeasurementsDictionary() {
        // Given: Pipeline result
        let pipelineResult = createMockPipelineResult()
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building MeasurementData
        let measurementData = builder.build(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // Then: Both top-level aiMetadata AND measurements["ai_metadata"] are present
        XCTAssertNotNil(measurementData.aiMetadata)  // Story 5.4 field
        XCTAssertNotNil(measurementData.measurements)
        // The measurements dict still has ai_metadata for webhook compatibility
        if let measurements = measurementData.measurements {
            XCTAssertNotNil(measurements["ai_metadata"])
        }
    }

    func testBuilderPopulatesAllAIMetadataFields() {
        // Given: Pipeline result with all data
        let pipelineResult = createMockPipelineResult()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: All AIMetadata fields are populated
        let metadata = measurementData.aiMetadata
        XCTAssertNotNil(metadata)
        XCTAssertNotNil(metadata?.calibrationMethod)
        XCTAssertNotNil(metadata?.calibrationConfidence)
        XCTAssertNotNil(metadata?.overallConfidence)
        XCTAssertNotNil(metadata?.processingTimeMs)
        XCTAssertNotNil(metadata?.modelVersions)
        XCTAssertEqual(metadata?.modelVersions["depth_anything"], "v2_small")
        XCTAssertNotNil(metadata?.frameCount)
        XCTAssertNotNil(metadata?.photoCount)
        XCTAssertNotNil(metadata?.scaleFactor)
        XCTAssertNotNil(metadata?.coveragePercentage)
        // needsVerification is a Bool, always present
    }

    func testBuilderPopulatesWarningsInAIMetadata() {
        // Given: Pipeline result with warnings
        let warningResult = createMockPipelineResultWithWarnings()

        // When: Building MeasurementData
        let measurementData = builder.build(from: warningResult)

        // Then: warnings are included in aiMetadata
        XCTAssertNotNil(measurementData.aiMetadata?.warnings)
        XCTAssertEqual(measurementData.aiMetadata?.warnings?.count, 1)
    }

    // MARK: - Story 5.4: LiDAR Backward Compatibility Test (Task 5.7)

    func testLiDARFlowMeasurementDataRoundTrip() throws {
        // Given: MeasurementData created exactly as LiDAR flow does (with nil AI fields)
        // This mirrors the initialization in ScanningView.swift for LiDAR flow
        let lidarMeasurementData = MeasurementData(
            roomName: "Main Room",
            roomType: "kitchen",
            roomplanData: ["walls": AnyCodable(4), "doors": AnyCodable(1), "windows": AnyCodable(2)],
            totalLinearFt: 15.5,
            totalSqFt: 120.0,
            wallCount: 4,
            windowCount: 2,
            doorCount: 1,
            measurements: ["test": AnyCodable("value")],
            usdzFileUrl: "file:///test.usdz",
            glbFileUrl: "file:///test.glb",
            previewImageUrl: "file:///preview.png",
            videoUrl: "file:///video.mp4",
            videoThumbnailUrl: "file:///thumb.jpg",
            videoDurationSeconds: 30,
            videoSizeBytes: 1024000,
            videoResolution: "1920x1080",
            videoFormat: "mp4",
            visualizationPhotoUrls: nil,
            scanMethod: nil,  // LiDAR flow: nil
            aiMetadata: nil   // LiDAR flow: nil
        )

        // When: Encoding and decoding (round-trip)
        let encoder = JSONEncoder()
        let data = try encoder.encode(lidarMeasurementData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MeasurementData.self, from: data)

        // Then: All LiDAR-specific fields preserved, AI fields remain nil
        XCTAssertEqual(decoded.roomName, "Main Room")
        XCTAssertEqual(decoded.roomType, "kitchen")
        XCTAssertEqual(decoded.totalLinearFt, 15.5)
        XCTAssertEqual(decoded.totalSqFt, 120.0)
        XCTAssertEqual(decoded.wallCount, 4)
        XCTAssertEqual(decoded.windowCount, 2)
        XCTAssertEqual(decoded.doorCount, 1)
        XCTAssertEqual(decoded.usdzFileUrl, "file:///test.usdz")
        XCTAssertEqual(decoded.glbFileUrl, "file:///test.glb")
        XCTAssertEqual(decoded.videoUrl, "file:///video.mp4")
        XCTAssertEqual(decoded.videoDurationSeconds, 30)
        XCTAssertNil(decoded.scanMethod)  // Remains nil for LiDAR
        XCTAssertNil(decoded.aiMetadata)  // Remains nil for LiDAR
    }

    func testScanMethodDecodeInvalidValueThrows() {
        // Given: JSON with an invalid scan_method value
        let invalidJSON = """
        "invalid_method"
        """.data(using: .utf8)!

        // When: Attempting to decode
        let decoder = JSONDecoder()

        // Then: Decoding throws an error
        XCTAssertThrowsError(try decoder.decode(ScanMethod.self, from: invalidJSON)) { error in
            // Verify it's a decoding error
            XCTAssertTrue(error is DecodingError)
        }
    }

    // MARK: - Helper for Warnings Test

    private func createMockPipelineResultWithWarnings() -> AIPipelineResult {
        let warning = PipelineWarning(
            stage: .depthEstimation,
            message: "Low lighting detected",
            severity: .caution
        )

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [warning],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    // MARK: - Mock Factory Methods

    private func createMockPipelineResult() -> AIPipelineResult {
        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithoutRoom() -> AIPipelineResult {
        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: nil,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithoutCabinets() -> AIPipelineResult {
        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithCabinets(
        baseCabinets: [Float],
        upperCabinets: [Float],
        tallCabinets: [Float] = []
    ) -> AIPipelineResult {
        var cabinets: [AIDetectedCabinet] = []
        let wallId = UUID()

        // Base cabinets
        for (index, width) in baseCabinets.enumerated() {
            cabinets.append(createMockCabinet(type: .base, widthInches: width, wallId: wallId, index: index))
        }

        // Upper cabinets
        for (index, width) in upperCabinets.enumerated() {
            cabinets.append(createMockCabinet(type: .upper, widthInches: width, wallId: wallId, index: index))
        }

        // Tall cabinets
        for (index, width) in tallCabinets.enumerated() {
            cabinets.append(createMockCabinet(type: .tall, widthInches: width, wallId: wallId, index: index))
        }

        let cabinetResult = CabinetDetectionResult(
            cabinets: cabinets,
            wallCoverageValidation: [],
            processingTimeMs: 1000,
            warnings: []
        )

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: cabinetResult,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithRoomArea(areaSquareInches: Double) -> AIPipelineResult {
        let roomStructure = createMockRoomStructure(areaSquareInches: areaSquareInches)

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithOpenings(wallCount: Int, windowCount: Int, doorCount: Int) -> AIPipelineResult {
        let walls = (0..<wallCount).map { _ in createMockWall() }

        let windows = (0..<windowCount).map { createMockWindow(index: $0) }
        let doors = (0..<doorCount).map { createMockDoor(index: $0) }

        let openingResult = OpeningDetectionResult(
            windows: windows,
            doors: doors,
            clearances: [],
            processingTimeMs: 100,
            warnings: []
        )

        let roomStructure = createMockRoomStructure(walls: walls)

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: roomStructure,
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: openingResult,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithConfidence(overall: Float) -> AIPipelineResult {
        let confidenceLevel: AIConfidenceLevel = overall >= 0.8 ? .high : (overall >= 0.6 ? .medium : .low)

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(confidenceLevel: confidenceLevel),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: nil,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    // MARK: - Helper Mock Creators

    private func createMockMesh() -> AIMesh {
        return AIMesh(vertices: [], indices: [])
    }

    private func createMockCalibration() -> ScaleCalibrationResult {
        return ScaleCalibrationResult(
            scaleFactor: 1.0,
            calibrationMethod: .autoCountertop,
            confidenceLevel: .high,
            countertopHeightInches: 36.0,
            ceilingHeightInches: 96.0,
            floorPlane: AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0),
            validationResults: CalibrationValidation(
                upperCabinetHeightValid: true,
                upperCabinetHeightInches: 54.0,
                ceilingHeightValid: true,
                ceilingHeightInches: 96.0
            ),
            processingTimeMs: 100
        )
    }

    private func createMockRoomStructure(
        areaSquareInches: Double = 14400,
        walls: [AIWall]? = nil,
        confidenceLevel: AIConfidenceLevel = .high
    ) -> AIRoomStructure {
        let defaultWalls = walls ?? [createMockWall()]

        let floorPlane = RoomPlane3D(
            normal: SIMD3<Float>(0, 1, 0),
            distance: 0,
            center: SIMD3<Float>(60, 0, 60)
        )

        let dimensions = RoomDimensions(
            widthInches: 120,
            lengthInches: 120,
            ceilingHeightInches: 96,
            areaSquareInches: areaSquareInches,
            perimeterInches: 480
        )

        let confidence = DetectionConfidence(
            floorConfidence: confidenceLevel == .high ? 0.95 : 0.6,
            wallConfidence: confidenceLevel == .high ? 0.9 : 0.6,
            boundaryConfidence: confidenceLevel == .high ? 0.85 : 0.5
        )

        return AIRoomStructure(
            floorPlane: floorPlane,
            ceilingHeightInches: 96,
            walls: defaultWalls,
            boundaryPolygon: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(120, 0),
                SIMD2<Float>(120, 120),
                SIMD2<Float>(0, 120)
            ],
            roomShape: .rectangle,
            dimensions: dimensions,
            openBoundaries: [],
            confidence: confidence,
            processingTimeMs: 100,
            warnings: []
        )
    }

    private func createMockWall() -> AIWall {
        let plane = RoomPlane3D(
            normal: SIMD3<Float>(0, 0, 1),
            distance: 0,
            center: SIMD3<Float>(60, 48, 0)
        )

        return AIWall(
            id: UUID(),
            plane: plane,
            startPoint: SIMD2<Float>(0, 0),
            endPoint: SIMD2<Float>(120, 0),
            lengthInches: 120,
            heightInches: 96,
            normalDirection: SIMD2<Float>(0, 1),
            boundaryType: .wall
        )
    }

    private func createMockCabinet(type: AICabinetType, widthInches: Float, wallId: UUID, index: Int) -> AIDetectedCabinet {
        let height: Float = type == .base ? 34.5 : (type == .upper ? 30.0 : 84.0)
        let depth: Float = type == .upper ? 12.0 : 24.0

        return AIDetectedCabinet(
            id: UUID(),
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(Float(index) * widthInches + widthInches / 2, height / 2, depth / 2),
                size: SIMD3<Float>(widthInches, height, depth)
            ),
            type: type,
            wallId: wallId,
            positionOnWallInches: Float(index) * widthInches,
            rawDimensions: SIMD3<Float>(widthInches, height, depth),
            snappedDimensions: SIMD3<Float>(widthInches, height, depth),
            confidence: .high,
            isStandardSize: true,
            cornerType: nil,
            cornerDetails: nil,
            isStacked: false,
            specialType: nil,
            stackedWithCabinetId: nil,
            hostingApplianceId: nil,
            notes: []
        )
    }

    private func createMockWindow(index: Int) -> AIDetectedWindow {
        let wallId = UUID()
        return AIDetectedWindow(
            id: UUID(),
            wallId: wallId,
            positionOnWallInches: Float(index) * 40,
            heightFromFloorInches: 42,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(Float(index) * 40 + 18, 54, 0),
                size: SIMD3<Float>(36, 48, 4)
            ),
            rawDimensions: SIMD3<Float>(36, 48, 4),
            snappedDimensions: SIMD3<Float>(36, 48, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            sillHeightInches: 42,
            distanceFromCountertopInches: 6,
            hasFrame: true,
            availableUpperCabinetHeight: 24,
            upperCabinetRecommendation: "24\" upper cabinets possible"
        )
    }

    private func createMockDoor(index: Int) -> AIDetectedDoor {
        let wallId = UUID()
        return AIDetectedDoor(
            id: UUID(),
            type: .door,
            wallId: wallId,
            positionOnWallInches: Float(index) * 40,
            heightFromFloorInches: 0,
            boundingBox: AIBoundingBox3D(
                center: SIMD3<Float>(Float(index) * 40 + 16, 40, 0),
                size: SIMD3<Float>(32, 80, 4)
            ),
            rawDimensions: SIMD3<Float>(32, 80, 4),
            snappedDimensions: SIMD3<Float>(32, 80, 4),
            confidence: .high,
            isStandardSize: true,
            notes: [],
            swingDirection: .right,
            isFullHeight: true,
            clearanceToAdjacentCabinet: nil
        )
    }

    private func createMockFusionQuality() -> TSDFQualityMetrics {
        return TSDFQualityMetrics(
            coveragePercentage: 85.0,
            averageVoxelWeight: 5.0,
            totalVoxelCount: 850000,
            isMeshManifold: true
        )
    }

    private func createMockConstraintValidation() -> ConstraintValidation {
        return ConstraintValidation(
            perimeterConsistent: true,
            areaConsistent: true,
            maxWallChangeInches: 0.5,
            wallsExceedingThreshold: []
        )
    }

    private func createMockCaptureSessionData() -> AICaptureSessionData {
        return AICaptureSessionData(
            videoURL: URL(string: "file:///tmp/video.mp4"),
            photos: [],
            metadata: AICaptureMetadata(
                deviceModel: "iPhone 14 Pro",
                osVersion: "17.0",
                captureDate: Date(),
                videoDuration: 60,
                photoCount: 5,
                averageLighting: 0.7
            ),
            qualityMetrics: nil
        )
    }

    private func createMockCaptureSessionDataWithPhotos(count: Int) -> AICaptureSessionData {
        let photos = (0..<count).map { index in
            AICapturedPhoto(
                url: URL(string: "file:///tmp/photo_\(index).jpg")!,
                pose: AIPose(
                    transform: matrix_identity_float4x4,
                    intrinsics: AICameraIntrinsics(fx: 1000, fy: 1000, cx: 540, cy: 960),
                    trackingState: .normal,
                    zoomFactor: 1.0
                ),
                timestamp: TimeInterval(index)
            )
        }

        return AICaptureSessionData(
            videoURL: URL(string: "file:///tmp/video.mp4"),
            photos: photos,
            metadata: AICaptureMetadata(
                deviceModel: "iPhone 14 Pro",
                osVersion: "17.0",
                captureDate: Date(),
                videoDuration: 60,
                photoCount: count,
                averageLighting: 0.7
            ),
            qualityMetrics: nil
        )
    }

    // MARK: - Story 5.5: Countertop Totals Calculation Tests

    // MARK: - Task 4.2: Test Wall Countertop Linear Feet Calculation (AC1)

    func testCountertopTotalsWallLinearFeet() {
        // Given: Pipeline result with countertop detection
        // Wall countertops: 60" + 48" = 108" = 9.0 linear feet
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [60.0, 48.0],
            wallNetAreaSquareInches: 3060.0,  // 60*25.5 + 48*25.5
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 108.0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: wall_linear_ft = 108 / 12 = 9.0
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let wallLinearFt = countertopTotals["wall_linear_ft"] as? Double else {
            XCTFail("countertop_totals.wall_linear_ft not found")
            return
        }

        XCTAssertEqual(wallLinearFt, 9.0, accuracy: 0.01)
    }

    // MARK: - Task 4.3: Test Wall Countertop Square Feet Calculation (AC2)

    func testCountertopTotalsWallSquareFeet() {
        // Given: Pipeline result with wall countertops
        // Net area = 3060 sq in = 21.25 sq ft
        // IMPORTANT: Test mock sets GROSS = NET + 144, so if we accidentally
        // use GROSS instead of NET, this test will fail (would be 22.25 sq ft)
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [60.0, 48.0],
            wallNetAreaSquareInches: 3060.0,
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 108.0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: wall_sq_ft = 3060 / 144 = 21.25 (NOT 22.25 which would be GROSS)
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let wallSqFt = countertopTotals["wall_sq_ft"] as? Double else {
            XCTFail("countertop_totals.wall_sq_ft not found")
            return
        }

        // This verifies NET area (21.25) is used, not GROSS (22.25)
        XCTAssertEqual(wallSqFt, 21.25, accuracy: 0.01)
        XCTAssertNotEqual(wallSqFt, 22.25, accuracy: 0.01, "Should use NET area, not GROSS area")
    }

    // MARK: - Task 4.4: Test Island Countertop Square Feet Calculation (AC3)

    func testCountertopTotalsIslandSquareFeet() {
        // Given: Pipeline result with island
        // Island area = 4320 sq in = 30.0 sq ft (72" x 60" island)
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [],
            wallNetAreaSquareInches: 0,
            islandAreaSquareInches: 4320.0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: island_sq_ft = 4320 / 144 = 30.0
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let islandSqFt = countertopTotals["island_sq_ft"] as? Double else {
            XCTFail("countertop_totals.island_sq_ft not found")
            return
        }

        XCTAssertEqual(islandSqFt, 30.0, accuracy: 0.01)
    }

    // MARK: - Task 4.5: Test Peninsula Countertop Square Feet Calculation (AC4)

    func testCountertopTotalsPeninsulaSquareFeet() {
        // Given: Pipeline result with peninsula
        // Peninsula area = 2160 sq in = 15.0 sq ft (60" x 36" peninsula)
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [],
            wallNetAreaSquareInches: 0,
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 2160.0,
            backsplashLinearInches: 0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: peninsula_sq_ft = 2160 / 144 = 15.0
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let peninsulaSqFt = countertopTotals["peninsula_sq_ft"] as? Double else {
            XCTFail("countertop_totals.peninsula_sq_ft not found")
            return
        }

        XCTAssertEqual(peninsulaSqFt, 15.0, accuracy: 0.01)
    }

    // MARK: - Task 4.6: Test Backsplash Linear Feet Calculation (AC5)

    func testCountertopTotalsBacksplashLinearFeet() {
        // Given: Pipeline result with backsplash
        // Backsplash = 96" = 8.0 linear feet (windows excluded)
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [108.0],  // 108" wall countertop
            wallNetAreaSquareInches: 2754.0,  // 108 * 25.5
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 96.0  // 96" after excluding 12" window
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: backsplash_linear_ft = 96 / 12 = 8.0
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let backsplashLinearFt = countertopTotals["backsplash_linear_ft"] as? Double else {
            XCTFail("countertop_totals.backsplash_linear_ft not found")
            return
        }

        XCTAssertEqual(backsplashLinearFt, 8.0, accuracy: 0.01)
    }

    // MARK: - Task 4.7: Test Total Countertop Square Feet Aggregation (AC6)

    func testCountertopTotalsTotalSquareFeet() {
        // Given: Pipeline result with all countertop types
        // Wall = 21.25 sq ft, Island = 30.0 sq ft, Peninsula = 15.0 sq ft
        // Total = 66.25 sq ft
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [108.0],
            wallNetAreaSquareInches: 3060.0,  // 21.25 sq ft
            islandAreaSquareInches: 4320.0,    // 30.0 sq ft
            peninsulaAreaSquareInches: 2160.0, // 15.0 sq ft
            backsplashLinearInches: 108.0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: total_sq_ft = 21.25 + 30.0 + 15.0 = 66.25
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any],
              let totalSqFt = countertopTotals["total_sq_ft"] as? Double else {
            XCTFail("countertop_totals.total_sq_ft not found")
            return
        }

        XCTAssertEqual(totalSqFt, 66.25, accuracy: 0.01)
    }

    // MARK: - Task 4.8: Test Integration with Measurements Dictionary (AC7)

    func testCountertopTotalsIntegrationWithMeasurements() {
        // Given: Pipeline result with countertops
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [60.0],
            wallNetAreaSquareInches: 1530.0,
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 60.0
        )

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: countertop_totals key exists and all required fields present
        guard let measurements = measurementData.measurements else {
            XCTFail("measurements is nil")
            return
        }

        XCTAssertNotNil(measurements["countertop_totals"])

        guard let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any] else {
            XCTFail("countertop_totals is not a dictionary")
            return
        }

        // All required keys present
        XCTAssertNotNil(countertopTotals["wall_linear_ft"])
        XCTAssertNotNil(countertopTotals["wall_sq_ft"])
        XCTAssertNotNil(countertopTotals["island_sq_ft"])
        XCTAssertNotNil(countertopTotals["peninsula_sq_ft"])
        XCTAssertNotNil(countertopTotals["backsplash_linear_ft"])
        XCTAssertNotNil(countertopTotals["total_sq_ft"])

        // Values are Doubles (feet units)
        XCTAssertTrue(countertopTotals["wall_linear_ft"] is Double)
        XCTAssertTrue(countertopTotals["wall_sq_ft"] is Double)
        XCTAssertTrue(countertopTotals["island_sq_ft"] is Double)
        XCTAssertTrue(countertopTotals["peninsula_sq_ft"] is Double)
        XCTAssertTrue(countertopTotals["backsplash_linear_ft"] is Double)
        XCTAssertTrue(countertopTotals["total_sq_ft"] is Double)
    }

    // MARK: - Task 4.9: Test Nil/Empty Countertop Handling (AC8)

    func testCountertopTotalsWithNilCountertopResult() {
        // Given: Pipeline result with nil countertop detection
        let pipelineResult = createMockPipelineResult()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: countertop_totals exists with all zeros
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any] else {
            XCTFail("countertop_totals not found")
            return
        }

        XCTAssertEqual(countertopTotals["wall_linear_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["wall_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["island_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["peninsula_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["backsplash_linear_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["total_sq_ft"] as? Double, 0.0)
    }

    func testCountertopTotalsWithEmptyCountertopArrays() {
        // Given: Pipeline result with empty countertop arrays (no detections)
        let pipelineResult = createMockPipelineResultWithEmptyCountertops()

        // When: Building MeasurementData
        let measurementData = builder.build(from: pipelineResult)

        // Then: countertop_totals exists with all zeros
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any] else {
            XCTFail("countertop_totals not found")
            return
        }

        XCTAssertEqual(countertopTotals["wall_linear_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["wall_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["island_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["peninsula_sq_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["backsplash_linear_ft"] as? Double, 0.0)
        XCTAssertEqual(countertopTotals["total_sq_ft"] as? Double, 0.0)
    }

    // MARK: - Task 4.10: Test Countertop Totals with FloorPlanJSON Path (AC7)

    func testCountertopTotalsWithFloorPlanJSONPath() {
        // Given: Pipeline result with countertops AND FloorPlanJSON
        // This tests the convertFloorPlanJSONToMeasurements path, not buildMinimalMeasurements
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [60.0],
            wallNetAreaSquareInches: 1530.0,
            islandAreaSquareInches: 0,
            peninsulaAreaSquareInches: 0,
            backsplashLinearInches: 60.0
        )
        let floorPlanJSON = createMockFloorPlanJSON()

        // When: Building MeasurementData with FloorPlanJSON
        let measurementData = builder.build(
            from: pipelineResult,
            floorPlanJSON: floorPlanJSON
        )

        // Then: countertop_totals should still be present (added after both paths)
        guard let measurements = measurementData.measurements,
              let countertopTotals = measurements["countertop_totals"]?.value as? [String: Any] else {
            XCTFail("countertop_totals not found when using FloorPlanJSON path")
            return
        }

        // Verify all required keys are present
        XCTAssertNotNil(countertopTotals["wall_linear_ft"])
        XCTAssertNotNil(countertopTotals["wall_sq_ft"])
        XCTAssertNotNil(countertopTotals["island_sq_ft"])
        XCTAssertNotNil(countertopTotals["peninsula_sq_ft"])
        XCTAssertNotNil(countertopTotals["backsplash_linear_ft"])
        XCTAssertNotNil(countertopTotals["total_sq_ft"])

        // Verify values are correct
        if let wallLinearFt = countertopTotals["wall_linear_ft"] as? Double {
            XCTAssertEqual(wallLinearFt, 5.0, accuracy: 0.01)
        } else {
            XCTFail("wall_linear_ft is not a Double")
        }
        if let backsplashLinearFt = countertopTotals["backsplash_linear_ft"] as? Double {
            XCTAssertEqual(backsplashLinearFt, 5.0, accuracy: 0.01)
        } else {
            XCTFail("backsplash_linear_ft is not a Double")
        }
    }

    // MARK: - Task 4.11: Test MeasurementData JSON Encoding with Countertop Totals

    func testCountertopTotalsJSONEncoding() throws {
        // Given: Pipeline result with countertops
        let pipelineResult = createMockPipelineResultWithCountertops(
            wallCountertopLengths: [60.0, 48.0],
            wallNetAreaSquareInches: 3060.0,
            islandAreaSquareInches: 4320.0,
            peninsulaAreaSquareInches: 2160.0,
            backsplashLinearInches: 96.0
        )
        let measurementData = builder.build(from: pipelineResult)

        // When: Encoding to JSON
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        // Then: Encoding succeeds without errors
        let data = try encoder.encode(measurementData)
        XCTAssertNotNil(data)

        // Verify the JSON contains countertop_totals key
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)

        // Check measurements contains countertop_totals
        if let measurements = json?["measurements"] as? [String: Any] {
            XCTAssertNotNil(measurements["countertop_totals"], "countertop_totals should be present in measurements")

            // Verify the structure of countertop_totals
            if let countertopTotals = measurements["countertop_totals"] as? [String: Any] {
                XCTAssertNotNil(countertopTotals["wall_linear_ft"])
                XCTAssertNotNil(countertopTotals["wall_sq_ft"])
                XCTAssertNotNil(countertopTotals["island_sq_ft"])
                XCTAssertNotNil(countertopTotals["peninsula_sq_ft"])
                XCTAssertNotNil(countertopTotals["backsplash_linear_ft"])
                XCTAssertNotNil(countertopTotals["total_sq_ft"])
            }
        }
    }

    // MARK: - Test Helpers for Countertop Totals

    private func createMockPipelineResultWithCountertops(
        wallCountertopLengths: [Float],
        wallNetAreaSquareInches: Float,
        islandAreaSquareInches: Float,
        peninsulaAreaSquareInches: Float,
        backsplashLinearInches: Float
    ) -> AIPipelineResult {
        // Calculate wall totals
        let wallTotalLinearInches = wallCountertopLengths.reduce(0, +)

        // Create mock wall countertops to ensure hasDetections returns true
        let wallId = UUID()
        var wallCountertops: [AIWallCountertop] = []
        var position: Float = 0
        for length in wallCountertopLengths {
            let countertop = AIWallCountertop(
                wallId: wallId,
                lengthInches: length,
                depthInches: 25.5,
                startPositionInches: position,
                endPositionInches: position + length
            )
            wallCountertops.append(countertop)
            position += length
        }

        // Create mock island countertops if island area is provided
        var islandCountertops: [AIIslandCountertop] = []
        if islandAreaSquareInches > 0 {
            // Assuming 72x60 island (4320 sq in) for typical test
            let length: Float = 72.0
            let width = islandAreaSquareInches / length
            islandCountertops.append(AIIslandCountertop(
                islandId: UUID(),
                lengthInches: length,
                widthInches: width,
                heightFromFloorInches: 36.0,
                overhangInches: nil,
                cutouts: [],
                confidence: .high
            ))
        }

        // Create mock peninsula countertops if peninsula area is provided
        var peninsulaCountertops: [AIPeninsulaCountertop] = []
        if peninsulaAreaSquareInches > 0 {
            // Assuming 60x36 peninsula (2160 sq in) for typical test
            let length: Float = 60.0
            let width = peninsulaAreaSquareInches / length
            peninsulaCountertops.append(AIPeninsulaCountertop(
                peninsulaId: UUID(),
                lengthInches: length,
                widthInches: width,
                heightFromFloorInches: 36.0,
                overhangInches: nil,
                cutouts: [],
                confidence: .high
            ))
        }

        // Create countertop summary
        // GROSS area is higher than NET area (NET = GROSS - cutouts)
        // Using GROSS = NET + 144 sq in (1 sq ft of cutouts) to verify we use NET, not GROSS
        let wallGrossArea = wallNetAreaSquareInches + 144.0  // Add 1 sq ft for theoretical cutouts
        let countertopSummary = AICountertopSummary(
            wallCountertops: wallCountertops,
            islandCountertops: islandCountertops,
            peninsulaCountertops: peninsulaCountertops,
            wallTotalLinearInches: wallTotalLinearInches,
            wallGrossAreaSquareInches: wallGrossArea,  // Higher than NET to verify correct field is used
            wallNetAreaSquareInches: wallNetAreaSquareInches,
            islandTotalSquareInches: islandAreaSquareInches,
            peninsulaTotalSquareInches: peninsulaAreaSquareInches,
            backsplashLinearInches: backsplashLinearInches,
            backsplashHeightInches: 18.0,
            exposedEdgeTotalInches: 0,
            cutoutCount: 0,
            allCutouts: []
        )

        let backsplashSummary = AIBacksplashSummary(
            linearInches: backsplashLinearInches,
            heightInches: 18.0,
            excludedSections: []
        )

        let countertopResult = CountertopDetectorResult(
            wallCountertops: wallCountertops,
            countertopSummary: countertopSummary,
            backsplashSummary: backsplashSummary,
            edgeTreatmentSummary: AIEdgeTreatmentSummary.empty,
            processingTimeMs: 100,
            warnings: [],
            overallConfidence: .high
        )

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: countertopResult,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockPipelineResultWithEmptyCountertops() -> AIPipelineResult {
        // Create empty countertop result (hasDetections = false)
        let countertopResult = CountertopDetectorResult.empty

        return AIPipelineResult(
            constrainedMesh: createMockMesh(),
            walls: [],
            corners: [],
            calibration: createMockCalibration(),
            roomStructure: createMockRoomStructure(),
            detectedCabinets: nil,
            detectedAppliances: nil,
            detectedIslandsPeninsulas: nil,
            detectedCountertops: countertopResult,
            detectedOpenings: nil,
            extractedMeasurements: nil,
            confidenceScores: nil,
            processingTimeMs: 5000,
            frameCount: 300,
            photoCount: 5,
            fusionQuality: createMockFusionQuality(),
            constraintValidation: createMockConstraintValidation(),
            coverageQuality: .good,
            warnings: [],
            coveragePercentage: nil,
            uncapturedZones: nil,
            originalMesh: nil
        )
    }

    private func createMockFloorPlanJSON() -> FloorPlanJSON {
        return FloorPlanJSON(
            roomName: "Kitchen",
            roomType: "kitchen",
            roomplanData: RoomplanDataJSON(walls: 4, doors: 1, windows: 2, floors: 1, openings: 0),
            totalLinearFt: 11.5,
            totalSqFt: 100,
            wallCount: 4,
            windowCount: 2,
            doorCount: 1,
            measurements: MeasurementsJSON(
                room: RoomJSON(minX: 0, maxX: 10, minZ: 0, maxZ: 10, ceilingHeightFt: 8, shape: "rectangular", confidence: "high"),
                walls: [],
                doors: [],
                windows: [],
                cabinets: CabinetsJSON(upper: [], lower: [], tall: nil),
                appliances: [],
                islands: [],
                peninsulas: [],
                countertops: nil,
                scanMethod: "aiFlow",
                aiMetadata: AIMetadataJSON(
                    schemaVersion: "1.0",
                    overallConfidence: "high",
                    confidenceScore: 0.85,
                    roomConfidenceScore: 0.9,
                    cabinetConfidenceScore: 0.8,
                    applianceConfidenceScore: 0.85,
                    calibrationMethod: "autoCountertop",
                    processingTimeMs: 5000
                ),
                aiSummary: AISummaryJSON(
                    cabinetCounts: CabinetCountsJSON(upper: 4, lower: 6, tall: 1, corner: 1),
                    linearFeet: LinearFeetJSON(upper: 5.0, lower: 6.5, tall: 2.0)
                )
            )
        )
    }
}
