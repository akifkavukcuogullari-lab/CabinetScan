//
//  PhotoCaptureTests.swift
//  cabinetscanTests
//
//  Created by Dev Agent on 2026-01-26.
//  Story 2.5: Photo Capture Flow - Unit Tests
//

import XCTest
import simd
@testable import cabinetscan

// MARK: - AIAngleTracker Tests

final class AIAngleTrackerTests: XCTestCase {

    var angleTracker: AIAngleTracker!

    override func setUp() {
        super.setUp()
        angleTracker = AIAngleTracker()
    }

    override func tearDown() {
        angleTracker = nil
        super.tearDown()
    }

    // MARK: - Empty State Tests

    func testNoPhotos_NeverSimilar() {
        // Given: No photos captured
        // When: Checking similarity
        let pose = createTestPose(yaw: 0, pitch: 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose)

        // Then: Should not be similar (no comparison)
        XCTAssertFalse(result.isSimilar)
        XCTAssertNil(result.suggestion)
        XCTAssertEqual(result.similarPhotoIndex, -1)
    }

    // MARK: - Similar Angle Tests

    func testSameAngle_IsSimilar() {
        // Given: One photo captured at yaw=0, pitch=0
        let pose1 = createTestPose(yaw: 0, pitch: 0)
        angleTracker.recordCapture(pose: pose1)

        // When: Checking same angle
        let pose2 = createTestPose(yaw: 0, pitch: 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose2)

        // Then: Should be similar
        XCTAssertTrue(result.isSimilar)
        XCTAssertNotNil(result.suggestion)
        XCTAssertEqual(result.similarPhotoIndex, 0)
    }

    func testWithin20Degrees_IsSimilar() {
        // Given: Photo at yaw=0, pitch=0
        let pose1 = createTestPose(yaw: 0, pitch: 0)
        angleTracker.recordCapture(pose: pose1)

        // When: Checking angle within 20 degrees
        let pose2 = createTestPose(yaw: 15, pitch: 15)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose2)

        // Then: Should be similar (within threshold)
        XCTAssertTrue(result.isSimilar)
    }

    func testBeyond20Degrees_NotSimilar() {
        // Given: Photo at yaw=0, pitch=0
        let pose1 = createTestPose(yaw: 0, pitch: 0)
        angleTracker.recordCapture(pose: pose1)

        // When: Checking angle beyond 20 degrees on one axis
        let pose2 = createTestPose(yaw: 30, pitch: 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose2)

        // Then: Should not be similar
        XCTAssertFalse(result.isSimilar)
    }

    // MARK: - Suggestion Direction Tests

    func testSuggestion_MovesAwayFromSimilar() {
        // Given: Photo at yaw=0, pitch=0
        let pose1 = createTestPose(yaw: 0, pitch: 0)
        angleTracker.recordCapture(pose: pose1)

        // When: At similar angle (slightly to the left)
        let pose2 = createTestPose(yaw: -5, pitch: 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose2)

        // Then: Should suggest moving right (opposite direction)
        XCTAssertTrue(result.isSimilar)
        XCTAssertTrue(result.suggestion?.contains("right") == true || result.suggestion?.contains("up") == true || result.suggestion?.contains("down") == true)
    }

    // MARK: - Multiple Photos Tests

    func testMultiplePhotos_ChecksAllAngles() {
        // Given: Multiple photos at different angles
        angleTracker.recordCapture(pose: createTestPose(yaw: 0, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 45, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 90, pitch: 0))

        // When: At angle similar to second photo
        let pose = createTestPose(yaw: 45, pitch: 5)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose)

        // Then: Should be similar (to photo at index 1)
        XCTAssertTrue(result.isSimilar)
        XCTAssertEqual(result.similarPhotoIndex, 1)
    }

    func testMultiplePhotos_UniqueAngle_NotSimilar() {
        // Given: Multiple photos at different angles
        angleTracker.recordCapture(pose: createTestPose(yaw: 0, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 60, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 120, pitch: 0))

        // When: At unique angle
        let pose = createTestPose(yaw: 180, pitch: 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: pose)

        // Then: Should not be similar
        XCTAssertFalse(result.isSimilar)
    }

    // MARK: - Remove Capture Tests

    func testRemoveCapture_ReducesCount() {
        // Given: 3 captures
        angleTracker.recordCapture(pose: createTestPose(yaw: 0, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 45, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 90, pitch: 0))
        XCTAssertEqual(angleTracker.captureCount, 3)

        // When: Removing one
        angleTracker.removeLastCapture()

        // Then: Count reduced
        XCTAssertEqual(angleTracker.captureCount, 2)
    }

    func testRemoveCaptureAtIndex_RemovesCorrectOne() {
        // Given: 3 captures at distinct angles
        angleTracker.recordCapture(pose: createTestPose(yaw: 0, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 45, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 90, pitch: 0))

        // When: Removing index 1 (45 degrees)
        angleTracker.removeCapture(at: 1)

        // Then: Checking 45 degrees should now be unique
        let result = angleTracker.isAngleTooSimilar(currentPose: createTestPose(yaw: 45, pitch: 0))
        XCTAssertFalse(result.isSimilar)
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllCaptures() {
        // Given: Multiple captures
        angleTracker.recordCapture(pose: createTestPose(yaw: 0, pitch: 0))
        angleTracker.recordCapture(pose: createTestPose(yaw: 45, pitch: 0))

        // When: Reset
        angleTracker.reset()

        // Then: Count is 0 and no similarity checks
        XCTAssertEqual(angleTracker.captureCount, 0)
        let result = angleTracker.isAngleTooSimilar(currentPose: createTestPose(yaw: 0, pitch: 0))
        XCTAssertFalse(result.isSimilar)
    }

    // MARK: - Helper Methods

    /// Create a test pose with specified yaw and pitch angles (in degrees)
    /// This matches the forward-vector-based extraction in AIAngleTracker:
    /// - yaw: horizontal angle from Z axis (positive = looking right)
    /// - pitch: vertical angle from horizontal (positive = looking up)
    private func createTestPose(yaw: Float, pitch: Float) -> AIPose {
        // Convert degrees to radians
        let yawRad = yaw * Float.pi / 180
        let pitchRad = pitch * Float.pi / 180

        // The AIAngleTracker extracts orientation from the camera's forward direction
        // which is the negated 3rd column of the transform (-Z axis in camera space)
        //
        // Forward vector for given yaw/pitch:
        // forwardX = sin(yaw) * cos(pitch)
        // forwardY = sin(pitch)
        // forwardZ = cos(yaw) * cos(pitch)
        //
        // Since forward = -column2, we need column2 = -forward

        let cosYaw = cos(yawRad)
        let sinYaw = sin(yawRad)
        let cosPitch = cos(pitchRad)
        let sinPitch = sin(pitchRad)

        // Build a proper rotation matrix for a camera looking in the yaw/pitch direction
        // Camera looks down -Z, so we construct the transform accordingly

        // Right vector (X axis) - perpendicular to forward in horizontal plane
        let rightX = cosYaw
        let rightY: Float = 0
        let rightZ = -sinYaw

        // Up vector (Y axis) - perpendicular to both forward and right
        let upX = -sinYaw * sinPitch
        let upY = cosPitch
        let upZ = -cosYaw * sinPitch

        // Forward vector negated (stored in column 2, camera looks down -Z)
        let col2X = -sinYaw * cosPitch
        let col2Y = -sinPitch
        let col2Z = -cosYaw * cosPitch

        let transform = simd_float4x4(
            SIMD4<Float>(rightX, rightY, rightZ, 0),     // Column 0: Right
            SIMD4<Float>(upX, upY, upZ, 0),              // Column 1: Up
            SIMD4<Float>(col2X, col2Y, col2Z, 0),        // Column 2: -Forward
            SIMD4<Float>(0, 0, 0, 1)                     // Column 3: Position
        )

        return AIPose(
            transform: transform,
            intrinsics: AICameraIntrinsics(fx: 1000, fy: 1000, cx: 500, cy: 500),
            trackingState: .normal,
            zoomFactor: 1.0
        )
    }
}

// MARK: - PhotoThumbnailItem Tests

final class PhotoThumbnailItemTests: XCTestCase {

    func testEquatable_SameIdSameBlurry_AreEqual() {
        let id = UUID()
        let item1 = PhotoThumbnailItem(id: id, thumbnail: UIImage(), isBlurry: false)
        let item2 = PhotoThumbnailItem(id: id, thumbnail: UIImage(), isBlurry: false)

        XCTAssertEqual(item1, item2)
    }

    func testEquatable_DifferentId_NotEqual() {
        let item1 = PhotoThumbnailItem(id: UUID(), thumbnail: UIImage(), isBlurry: false)
        let item2 = PhotoThumbnailItem(id: UUID(), thumbnail: UIImage(), isBlurry: false)

        XCTAssertNotEqual(item1, item2)
    }

    func testEquatable_DifferentBlurry_NotEqual() {
        let id = UUID()
        let item1 = PhotoThumbnailItem(id: id, thumbnail: UIImage(), isBlurry: false)
        let item2 = PhotoThumbnailItem(id: id, thumbnail: UIImage(), isBlurry: true)

        XCTAssertNotEqual(item1, item2)
    }
}

// MARK: - PreviewPhoto Tests

final class PreviewPhotoTests: XCTestCase {

    func testIdentifiable_UniqueIds() {
        let photo1 = PreviewPhoto(id: UUID(), index: 0, image: nil, isBlurry: false)
        let photo2 = PreviewPhoto(id: UUID(), index: 1, image: nil, isBlurry: false)

        XCTAssertNotEqual(photo1.id, photo2.id)
    }
}
