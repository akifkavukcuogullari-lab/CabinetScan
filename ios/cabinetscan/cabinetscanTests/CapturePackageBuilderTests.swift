//
//  CapturePackageBuilderTests.swift
//  cabinetscanTests
//
//  Phase 1.2-test: CapturePackageBuilder unit tests
//  Server Pipeline V2
//

import XCTest
import simd
@testable import cabinetscan

final class CapturePackageBuilderTests: XCTestCase {

    private var sessionManager: AIARSessionManager!
    private var builder: CapturePackageBuilder!

    override func setUp() {
        super.setUp()
        sessionManager = AIARSessionManager()
        builder = CapturePackageBuilder(sessionManager: sessionManager)
    }

    override func tearDown() {
        sessionManager.stopSession()
        builder = nil
        sessionManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTempVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_video_\(UUID().uuidString.prefix(8)).mp4")
        FileManager.default.createFile(atPath: url.path, contents: Data("fake video".utf8))
        return url
    }

    private func makeSessionData(
        videoURL: URL? = nil,
        photoCount: Int = 5,
        duration: TimeInterval = 60
    ) -> AICaptureSessionData {
        let photos = (0..<photoCount).map { i in
            AICapturedPhoto(
                url: FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(i).jpg"),
                pose: AIPose(
                    transform: matrix_identity_float4x4,
                    intrinsics: AICameraIntrinsics(fx: 1000, fy: 1000, cx: 540, cy: 960),
                    trackingState: .normal,
                    zoomFactor: 1.0
                ),
                timestamp: TimeInterval(i)
            )
        }

        var data = AICaptureSessionData()
        data.videoURL = videoURL
        data.photos = photos
        data.metadata = AICaptureMetadata(
            deviceModel: "iPhone 14",
            osVersion: "17.0",
            captureDate: Date(),
            videoDuration: duration,
            photoCount: photoCount,
            averageLighting: 200
        )
        return data
    }

    // MARK: - Build Tests

    func testBuildProducesValidPackage() {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "test-showroom-123"
        )

        XCTAssertEqual(package.videoURL, videoURL)
        XCTAssertFalse(package.posesData.isEmpty, "Poses data should not be empty")
        XCTAssertFalse(package.planesData.isEmpty, "Planes data should not be empty")
        XCTAssertEqual(package.photos.count, 5)

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }

    func testBuildMetadataFieldsPopulated() {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL, photoCount: 7, duration: 90)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "showroom-abc"
        )

        XCTAssertEqual(package.metadata.showroomId, "showroom-abc")
        XCTAssertEqual(package.metadata.photoCount, 7)
        XCTAssertEqual(package.metadata.videoDuration, 90)
        XCTAssertFalse(package.metadata.deviceModel.isEmpty)
        XCTAssertFalse(package.metadata.osVersion.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }

    func testBuildWithZeroPlanesProducesEmptyPlanesArray() throws {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "test"
        )

        // Parse planes data — should be valid empty JSON array
        let planes = try XCTUnwrap(
            JSONSerialization.jsonObject(with: package.planesData) as? [[String: Any]]
        )
        XCTAssertEqual(planes.count, 0)
        XCTAssertEqual(package.metadata.planeCount, 0)

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }

    func testBuildPosesDataIsValidJSON() throws {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "test"
        )

        // Poses data should be valid JSON with poseCount key
        let posesDict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: package.posesData) as? [String: Any]
        )
        XCTAssertNotNil(posesDict["poseCount"], "Should contain poseCount")
        XCTAssertNotNil(posesDict["poses"], "Should contain poses array")

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }

    func testBuildMetadataIsCodable() throws {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "test"
        )

        // Metadata should round-trip through JSON encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(package.metadata)
        XCTAssertFalse(encoded.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CapturePackageMetadata.self, from: encoded)
        XCTAssertEqual(decoded.showroomId, package.metadata.showroomId)
        XCTAssertEqual(decoded.photoCount, package.metadata.photoCount)

        // Verify snake_case keys
        let jsonDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(jsonDict["device_model"], "Should use snake_case key")
        XCTAssertNotNil(jsonDict["showroom_id"], "Should use snake_case key")
        XCTAssertNil(jsonDict["deviceModel"], "Should NOT use camelCase key")

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }

    func testBuildWithZeroPhotos() {
        let videoURL = makeTempVideoURL()
        let sessionData = makeSessionData(videoURL: videoURL, photoCount: 0)

        let package = builder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: "test"
        )

        XCTAssertEqual(package.photos.count, 0)
        XCTAssertEqual(package.metadata.photoCount, 0)

        // Clean up
        try? FileManager.default.removeItem(at: videoURL)
    }
}
