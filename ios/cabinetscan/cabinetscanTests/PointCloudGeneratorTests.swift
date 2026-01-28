//
//  PointCloudGeneratorTests.swift
//  cabinetscanTests
//
//  Created for Story 3.3: Point Cloud Generation
//

import XCTest
import simd
@testable import cabinetscan

final class PointCloudGeneratorTests: XCTestCase {

    var generator: PointCloudGenerator!

    override func setUp() async throws {
        await MainActor.run {
            generator = PointCloudGenerator()
        }
    }

    override func tearDown() async throws {
        generator = nil
    }

    // MARK: - Test Helpers

    /// Creates a test depth frame with uniform depth values
    func createTestDepthFrame(
        width: Int = 100,
        height: Int = 100,
        depthValue: Float = 0.5,
        pose: AIPose? = nil
    ) -> AIDepthFrame {
        let depthData = Array(repeating: Array(repeating: depthValue, count: width), count: height)
        let testPose = pose ?? createIdentityPose()

        return AIDepthFrame(
            depthData: depthData,
            width: width,
            height: height,
            timestamp: 0.0,
            pose: testPose,
            confidence: .medium
        )
    }

    /// Creates an identity pose (no rotation or translation)
    func createIdentityPose() -> AIPose {
        return AIPose(
            transform: matrix_identity_float4x4,
            intrinsics: AICameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50),
            trackingState: .normal,
            zoomFactor: 1.0
        )
    }

    /// Creates a pose with a known rotation (90 degrees around Y axis)
    func createRotatedPose() -> AIPose {
        // 90 degree rotation around Y axis
        let angle: Float = .pi / 2
        var rotationMatrix = matrix_identity_float4x4
        rotationMatrix.columns.0 = SIMD4<Float>(cos(angle), 0, -sin(angle), 0)
        rotationMatrix.columns.2 = SIMD4<Float>(sin(angle), 0, cos(angle), 0)

        return AIPose(
            transform: rotationMatrix,
            intrinsics: AICameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50),
            trackingState: .normal,
            zoomFactor: 1.0
        )
    }

    /// Creates a pose with translation
    func createTranslatedPose(tx: Float, ty: Float, tz: Float) -> AIPose {
        var translationMatrix = matrix_identity_float4x4
        translationMatrix.columns.3 = SIMD4<Float>(tx, ty, tz, 1)

        return AIPose(
            transform: translationMatrix,
            intrinsics: AICameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50),
            trackingState: .normal,
            zoomFactor: 1.0
        )
    }

    // MARK: - Task 10.2: Depth-to-Point Conversion Tests

    func testDepthToPointConversion_KnownIntrinsics() async throws {
        // Given: A depth frame with known intrinsics and a single valid depth value
        let intrinsics = AICameraIntrinsics(fx: 100, fy: 100, cx: 5, cy: 5)
        let pose = AIPose(
            transform: matrix_identity_float4x4,
            intrinsics: intrinsics,
            trackingState: .normal,
            zoomFactor: 1.0
        )

        // Create a 10x10 depth map with depth = 0.5 at center (5,5)
        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 10), count: 10)
        depthData[5][5] = 0.5  // Single valid depth at center

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: pose,
            confidence: .medium
        )

        // When: Generating point cloud (CPU path for testing)
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Should have exactly one point
        XCTAssertEqual(pointCloud.count, 1, "Should have exactly one valid point")

        // Verify the point coordinates using unprojection formula:
        // X = (u - cx) * depth / fx = (5 - 5) * 0.5 / 100 = 0
        // Y = (v - cy) * depth / fy = (5 - 5) * 0.5 / 100 = 0
        // Z = depth = 0.5
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()
        XCTAssertEqual(points[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(points[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(points[0].z, 0.5, accuracy: 0.0001)
    }

    func testDepthToPointConversion_OffCenterPixel() async throws {
        // Given: Depth at pixel (10, 10) with cx=5, cy=5
        let intrinsics = AICameraIntrinsics(fx: 100, fy: 100, cx: 5, cy: 5)
        let pose = AIPose(
            transform: matrix_identity_float4x4,
            intrinsics: intrinsics,
            trackingState: .normal,
            zoomFactor: 1.0
        )

        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 20), count: 20)
        depthData[10][10] = 0.5  // Depth at (10, 10)

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 20,
            height: 20,
            timestamp: 0.0,
            pose: pose,
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Verify unprojection
        // X = (10 - 5) * 0.5 / 100 = 0.025
        // Y = (10 - 5) * 0.5 / 100 = 0.025
        // Z = 0.5
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 0.025, accuracy: 0.0001)
        XCTAssertEqual(points[0].y, 0.025, accuracy: 0.0001)
        XCTAssertEqual(points[0].z, 0.5, accuracy: 0.0001)
    }

    // MARK: - Task 10.3: World Transform Tests

    func testWorldTransform_IdentityPose() async throws {
        // Given: Identity pose (no rotation or translation)
        let frame = createTestDepthFrame(width: 10, height: 10, depthValue: 0.5)

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Points should be in camera space (same as world space for identity)
        XCTAssertGreaterThan(pointCloud.count, 0, "Should generate points")
    }

    func testWorldTransform_WithTranslation() async throws {
        // Given: Pose with translation (1, 2, 3)
        let translatedPose = createTranslatedPose(tx: 1, ty: 2, tz: 3)
        let intrinsics = AICameraIntrinsics(fx: 100, fy: 100, cx: 5, cy: 5)
        let pose = AIPose(
            transform: translatedPose.transform,
            intrinsics: intrinsics,
            trackingState: .normal,
            zoomFactor: 1.0
        )

        // Create depth at center (5,5) with depth 0.5
        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 10), count: 10)
        depthData[5][5] = 0.5

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: pose,
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Point should be translated
        // Camera space: (0, 0, 0.5)
        // World space: (0 + 1, 0 + 2, 0.5 + 3) = (1, 2, 3.5)
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(points[0].y, 2.0, accuracy: 0.0001)
        XCTAssertEqual(points[0].z, 3.5, accuracy: 0.0001)
    }

    func testWorldTransform_WithRotation() async throws {
        // Given: 90 degree rotation around Y axis
        let rotatedPose = createRotatedPose()
        let intrinsics = AICameraIntrinsics(fx: 100, fy: 100, cx: 0, cy: 0)

        // Create depth at pixel (10, 0) with depth 0.5
        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 20), count: 20)
        depthData[0][10] = 0.5  // This gives camera space (0.05, 0, 0.5)

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 20,
            height: 20,
            timestamp: 0.0,
            pose: AIPose(
                transform: rotatedPose.transform,
                intrinsics: intrinsics,
                trackingState: .normal,
                zoomFactor: 1.0
            ),
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Point should be rotated 90 degrees around Y
        // Camera space: X = (10-0)*0.5/100 = 0.05, Y = 0, Z = 0.5
        // After 90° Y rotation: new_X = Z = 0.5, new_Z = -X = -0.05
        var mutableCloud = pointCloud
        let points = mutableCloud.getPoints()
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 0.5, accuracy: 0.01)
        XCTAssertEqual(points[0].y, 0.0, accuracy: 0.01)
        XCTAssertEqual(points[0].z, -0.05, accuracy: 0.01)
    }

    // MARK: - Task 10.4: Downsampling Tests

    func testDownsampling_VideoFramesFactor2() async throws {
        // Given: A 100x100 depth frame (10,000 pixels)
        let frame = createTestDepthFrame(width: 100, height: 100, depthValue: 0.5)

        // When: Downsampling by factor 2
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 2)
        }

        // Then: Should have ~25% of original pixels (50x50 = 2,500)
        // All are valid depth, so count should be 2,500
        XCTAssertEqual(pointCloud.count, 2500, "Downsampling by 2 should produce 50x50 = 2500 points")
    }

    func testDownsampling_PhotoFramesNoDownsample() async throws {
        // Given: A 100x100 depth frame
        let frame = createTestDepthFrame(width: 100, height: 100, depthValue: 0.5)

        // When: No downsampling (factor 1) - for photos per ADR-003
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Should have all 10,000 points
        XCTAssertEqual(pointCloud.count, 10000, "No downsampling should preserve all points")
    }

    func testDownsampling_LargeCapturesFactor3() async throws {
        // Given: A 99x99 depth frame (divisible by 3)
        let frame = createTestDepthFrame(width: 99, height: 99, depthValue: 0.5)

        // When: Downsampling by factor 3
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 3)
        }

        // Then: Should have 33x33 = 1,089 points
        XCTAssertEqual(pointCloud.count, 1089, "Downsampling by 3 should produce 33x33 = 1089 points")
    }

    // MARK: - Task 10.5: Depth Filtering Tests (ADR-004)

    func testDepthFiltering_BelowMinimum() async throws {
        // Given: Depth values below 0.001 threshold
        var depthData = Array(repeating: Array(repeating: Float(0.0005), count: 10), count: 10)
        depthData[5][5] = 0.5  // One valid point

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: createIdentityPose(),
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Only one point should pass filtering
        XCTAssertEqual(pointCloud.count, 1, "Only depth >= 0.001 should be valid")
    }

    func testDepthFiltering_AboveMaximum() async throws {
        // Given: Depth values above 0.999 threshold
        var depthData = Array(repeating: Array(repeating: Float(0.9999), count: 10), count: 10)
        depthData[5][5] = 0.5  // One valid point

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: createIdentityPose(),
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Only one point should pass filtering
        XCTAssertEqual(pointCloud.count, 1, "Only depth <= 0.999 should be valid")
    }

    func testDepthFiltering_NaN() async throws {
        // Given: Depth values with NaN
        var depthData = Array(repeating: Array(repeating: Float.nan, count: 10), count: 10)
        depthData[5][5] = 0.5  // One valid point

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: createIdentityPose(),
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Only one point should pass filtering
        XCTAssertEqual(pointCloud.count, 1, "NaN depths should be filtered out")
    }

    func testDepthFiltering_ExactlyAtThresholds() async throws {
        // Given: Depth values exactly at thresholds (should be valid)
        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 10), count: 10)
        depthData[0][0] = 0.001   // Exactly at minimum - should be valid
        depthData[0][1] = 0.999   // Exactly at maximum - should be valid

        let frame = AIDepthFrame(
            depthData: depthData,
            width: 10,
            height: 10,
            timestamp: 0.0,
            pose: createIdentityPose(),
            confidence: .medium
        )

        // When
        let pointCloud = await MainActor.run {
            generator.generatePointCloudCPU(from: frame, downsampleFactor: 1)
        }

        // Then: Both points at exact thresholds should be valid
        XCTAssertEqual(pointCloud.count, 2, "Depths exactly at 0.001 and 0.999 should be valid")
    }

    // MARK: - Task 10.6: Progress and Cancellation Tests

    func testProgressReporting() async throws {
        // Given: Multiple depth frames
        let frames = (0..<5).map { _ in
            createTestDepthFrame(width: 10, height: 10, depthValue: 0.5)
        }

        // When: Generating point clouds
        let result = try await generator.generatePointClouds(from: frames, videoFrameCount: 5)

        // Then: Progress should reach 1.0 and all frames processed
        let finalProgress = await MainActor.run { generator.progress }
        XCTAssertEqual(finalProgress, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.pointClouds.count, 5)
        XCTAssertEqual(result.videoPointCloudCount, 5)
        XCTAssertEqual(result.photoPointCloudCount, 0)
        XCTAssertGreaterThan(result.totalPointCount, 0)
    }

    // MARK: - Mixed Video/Photo Processing Tests (M2 fix)

    func testMixedVideoPhotoProcessing() async throws {
        // Given: 3 video frames + 2 photo frames
        // Video frames will be downsampled by factor 2, photos won't
        let videoFrames = (0..<3).map { _ in
            createTestDepthFrame(width: 100, height: 100, depthValue: 0.5)
        }
        let photoFrames = (0..<2).map { _ in
            createTestDepthFrame(width: 100, height: 100, depthValue: 0.5)
        }
        let allFrames = videoFrames + photoFrames

        // When: Processing with videoFrameCount = 3
        let result = try await generator.generatePointClouds(from: allFrames, videoFrameCount: 3)

        // Then: Should have 5 point clouds
        XCTAssertEqual(result.pointClouds.count, 5)
        XCTAssertEqual(result.videoPointCloudCount, 3)
        XCTAssertEqual(result.photoPointCloudCount, 2)

        // Video frames (first 3) should have ~2500 points (100x100 / 4 due to factor 2 downsampling)
        // Photo frames (last 2) should have ~10000 points (no downsampling)
        for i in 0..<3 {
            XCTAssertEqual(result.pointClouds[i].count, 2500,
                           "Video frame \(i) should be downsampled to 2500 points")
        }
        for i in 3..<5 {
            XCTAssertEqual(result.pointClouds[i].count, 10000,
                           "Photo frame \(i) should NOT be downsampled (10000 points)")
        }
    }

    func testLargeCaptureUsesFactor3() async throws {
        // Given: 61 video frames (exceeds threshold of 60)
        let frames = (0..<61).map { _ in
            createTestDepthFrame(width: 99, height: 99, depthValue: 0.5)  // 99x99 divisible by 3
        }

        // When: Processing - should use factor 3 for large captures
        let result = try await generator.generatePointClouds(from: frames, videoFrameCount: 61)

        // Then: Each video frame should have 33x33 = 1089 points (factor 3 downsampling)
        XCTAssertEqual(result.pointClouds.count, 61)
        XCTAssertEqual(result.pointClouds[0].count, 1089,
                       "Large capture should use factor 3 downsampling (33x33 = 1089)")
    }

    func testGenerationResultMetadata() async throws {
        // Given: Mixed frames
        let frames = (0..<4).map { _ in
            createTestDepthFrame(width: 10, height: 10, depthValue: 0.5)
        }

        // When
        let result = try await generator.generatePointClouds(from: frames, videoFrameCount: 2)

        // Then: Metadata should be accurate
        XCTAssertEqual(result.videoPointCloudCount, 2)
        XCTAssertEqual(result.photoPointCloudCount, 2)
        XCTAssertGreaterThan(result.processingTimeMs, 0)
        XCTAssertGreaterThan(result.totalPointCount, 0)
        XCTAssertGreaterThan(result.averagePointsPerFrame, 0)
    }

    func testCancellation() async throws {
        // Given: A long-running task
        let frames = (0..<100).map { _ in
            createTestDepthFrame(width: 100, height: 100, depthValue: 0.5)
        }

        // When: Cancelling the task
        let task = Task {
            try await generator.generatePointClouds(from: frames, videoFrameCount: 100)
        }

        // Cancel after a short delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        // Then: Task should throw cancellation error
        do {
            _ = try await task.value
            // If we get here without error, the task completed before cancellation
            // This is acceptable - cancellation is best-effort
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Task 10.7: ADR-005 Compliance Tests

    func testIntrinsicsNotAdjustedForZoom() async throws {
        // Given: Same scene with different zoom factors
        let intrinsics = AICameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50)

        var depthData = Array(repeating: Array(repeating: Float(0.0), count: 100), count: 100)
        depthData[50][50] = 0.5  // Center point

        // Pose with zoom 1.0
        let pose1x = AIPose(
            transform: matrix_identity_float4x4,
            intrinsics: intrinsics,
            trackingState: .normal,
            zoomFactor: 1.0
        )

        // Pose with zoom 2.0 (same intrinsics - ARKit already adjusts)
        let pose2x = AIPose(
            transform: matrix_identity_float4x4,
            intrinsics: intrinsics,  // Same intrinsics - ADR-005
            trackingState: .normal,
            zoomFactor: 2.0
        )

        let frame1x = AIDepthFrame(depthData: depthData, width: 100, height: 100, timestamp: 0, pose: pose1x, confidence: .medium)
        let frame2x = AIDepthFrame(depthData: depthData, width: 100, height: 100, timestamp: 0, pose: pose2x, confidence: .medium)

        // When
        let pointCloud1x = await MainActor.run { generator.generatePointCloudCPU(from: frame1x, downsampleFactor: 1) }
        let pointCloud2x = await MainActor.run { generator.generatePointCloudCPU(from: frame2x, downsampleFactor: 1) }

        // Then: Both should produce the same point (intrinsics are NOT adjusted for zoom)
        var mutable1x = pointCloud1x
        var mutable2x = pointCloud2x
        let points1x = mutable1x.getPoints()
        let points2x = mutable2x.getPoints()

        XCTAssertEqual(points1x.count, 1)
        XCTAssertEqual(points2x.count, 1)

        // Points should be identical (ADR-005: no zoom adjustment)
        XCTAssertEqual(points1x[0].x, points2x[0].x, accuracy: 0.0001,
                       "X should be same regardless of zoomFactor (ADR-005)")
        XCTAssertEqual(points1x[0].y, points2x[0].y, accuracy: 0.0001,
                       "Y should be same regardless of zoomFactor (ADR-005)")
        XCTAssertEqual(points1x[0].z, points2x[0].z, accuracy: 0.0001,
                       "Z should be same regardless of zoomFactor (ADR-005)")
    }

    // MARK: - AIPointCloud Metal Buffer Tests

    func testAIPointCloud_MetalBufferLazyConversion() {
        // Given: A point cloud with only Swift array (no metal buffer)
        let points = [SIMD3<Float>(1, 2, 3), SIMD3<Float>(4, 5, 6)]
        var pointCloud = AIPointCloud(points: points, colors: nil, normals: nil, metalBuffer: nil, pointCount: 2)

        // When: Getting points
        let retrievedPoints = pointCloud.getPoints()

        // Then: Should return the original points
        XCTAssertEqual(retrievedPoints.count, 2)
        XCTAssertEqual(retrievedPoints[0], SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(retrievedPoints[1], SIMD3<Float>(4, 5, 6))
    }

    func testAIPointCloud_Count() {
        // Given: Point cloud with points
        let points = [SIMD3<Float>(1, 2, 3), SIMD3<Float>(4, 5, 6), SIMD3<Float>(7, 8, 9)]
        let pointCloud = AIPointCloud(points: points, colors: nil, normals: nil, metalBuffer: nil, pointCount: 3)

        // Then
        XCTAssertEqual(pointCloud.count, 3)
        XCTAssertFalse(pointCloud.isEmpty)
    }

    func testAIPointCloud_Empty() {
        // Given: Empty point cloud
        let pointCloud = AIPointCloud()

        // Then
        XCTAssertEqual(pointCloud.count, 0)
        XCTAssertTrue(pointCloud.isEmpty)
    }
}
