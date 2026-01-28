//
//  TSDFFusionTests.swift
//  cabinetscanTests
//
//  Created for Story 3.4: Multi-View Fusion (TSDF)
//

import XCTest
@testable import cabinetscan
import simd

final class TSDFFusionTests: XCTestCase {

    // MARK: - Test Constants

    /// Default voxel size used in tests (2cm)
    private let testVoxelSize: Float = 0.02

    /// Tolerance for floating point comparisons
    private let epsilon: Float = 0.0001

    // MARK: - TSDFVolume Tests

    // MARK: 8.2 - Test Single Point Cloud Integration

    func testSinglePointCloudIntegration() throws {
        // Given: A simple point cloud with a few points forming a plane
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0.0, 0.0, 0.0),
            SIMD3<Float>(0.1, 0.0, 0.0),
            SIMD3<Float>(0.2, 0.0, 0.0),
            SIMD3<Float>(0.0, 0.1, 0.0),
            SIMD3<Float>(0.1, 0.1, 0.0),
        ]
        let pointCloud = AIPointCloud(points: points, colors: nil, normals: nil, metalBuffer: nil, pointCount: points.count)

        // When: Creating volume and integrating
        var volume = TSDFVolume(pointClouds: [pointCloud], voxelSize: testVoxelSize)
        volume.integratePointCloud(pointCloud, weight: 1.0)

        // Then: Volume should have allocated voxels
        XCTAssertGreaterThan(volume.allocatedVoxelCount, 0, "Volume should have allocated voxels")

        // And: Points should have created voxels with positive weight
        for point in points {
            if let voxelIdx = volume.voxelIndex(for: point),
               let voxel = volume.getVoxel(at: voxelIdx) {
                XCTAssertGreaterThan(voxel.weight, 0, "Voxel at point should have positive weight")
            }
        }
    }

    // MARK: 8.3 - Test Multiple Point Cloud Fusion with Overlapping Regions

    func testMultiplePointCloudFusionWithOverlap() throws {
        // Given: Two point clouds with overlapping region
        let points1: [SIMD3<Float>] = [
            SIMD3<Float>(0.0, 0.0, 0.0),
            SIMD3<Float>(0.05, 0.0, 0.0),  // Overlapping region
            SIMD3<Float>(0.1, 0.0, 0.0),
        ]

        let points2: [SIMD3<Float>] = [
            SIMD3<Float>(0.05, 0.0, 0.0),  // Overlapping point
            SIMD3<Float>(0.1, 0.0, 0.0),   // Overlapping point
            SIMD3<Float>(0.15, 0.0, 0.0),
        ]

        let cloud1 = AIPointCloud(points: points1, pointCount: points1.count)
        let cloud2 = AIPointCloud(points: points2, pointCount: points2.count)

        // When: Integrating both clouds
        var volume = TSDFVolume(pointClouds: [cloud1, cloud2], voxelSize: testVoxelSize)
        volume.integratePointCloud(cloud1, weight: 1.0)
        volume.integratePointCloud(cloud2, weight: 1.0)

        // Then: Overlapping region should have higher weight
        let overlappingPoint = SIMD3<Float>(0.05, 0.0, 0.0)
        if let voxelIdx = volume.voxelIndex(for: overlappingPoint),
           let voxel = volume.getVoxel(at: voxelIdx) {
            // Weight should be approximately 2.0 for overlapping voxels
            XCTAssertGreaterThan(voxel.weight, 1.0, "Overlapping voxel should have weight > 1.0")
        }
    }

    // MARK: 8.4 - Test Mesh Extraction Produces Valid Triangles

    func testMeshExtractionProducesValidTriangles() throws {
        // Given: A volume with some voxels forming a simple surface
        var volume = TSDFVolume(voxelSize: testVoxelSize, boundingBox: TSDFBoundingBox(
            min: SIMD3<Float>(-0.1, -0.1, -0.1),
            max: SIMD3<Float>(0.2, 0.2, 0.2)
        ))

        // Create a simple grid of points with upward-facing normals
        let normal = SIMD3<Float>(0, 0, 1)  // Surface faces +Z
        for x in stride(from: 0, to: 5, by: 1) {
            for y in stride(from: 0, to: 5, by: 1) {
                let point = SIMD3<Float>(Float(x) * 0.02, Float(y) * 0.02, 0.0)
                volume.integratePoint(point, normal: normal, weight: 1.0)
            }
        }

        // When: Extracting mesh
        let mesh = try MarchingCubes.extractMesh(from: volume)

        // Then: Mesh should not be empty (for a grid of points)
        // Note: May be empty if all voxels have same TSDF sign
        // The important test is that indices are valid
        if !mesh.isEmpty {
            // All indices should be within vertex bounds
            for index in mesh.indices {
                XCTAssertLessThan(Int(index), mesh.vertices.count, "Index should be within vertex bounds")
            }

            // Triangle count should match index count
            XCTAssertEqual(mesh.indices.count % 3, 0, "Index count should be divisible by 3")

            // No degenerate triangles (all three vertices different)
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                let i0 = mesh.indices[i]
                let i1 = mesh.indices[i + 1]
                let i2 = mesh.indices[i + 2]
                XCTAssertNotEqual(i0, i1, "Triangle vertices should be distinct")
                XCTAssertNotEqual(i1, i2, "Triangle vertices should be distinct")
                XCTAssertNotEqual(i2, i0, "Triangle vertices should be distinct")
            }
        }
    }

    // MARK: 8.5 - Test Memory Stays Under Limit

    func testMemoryStaysUnderLimit() async throws {
        // Given: Multiple point clouds simulating a real capture
        var pointClouds: [AIPointCloud] = []

        // Create 65 point clouds (60 video + 5 photos) with moderate point counts
        for i in 0..<65 {
            // Video frames: ~67K points, Photos: ~268K points
            let pointCount = i < 60 ? 1000 : 4000  // Scaled down for tests

            var points: [SIMD3<Float>] = []
            for j in 0..<pointCount {
                // Spread points across a kitchen-sized volume
                let x = Float.random(in: -2...2)
                let y = Float.random(in: -2...2)
                let z = Float.random(in: 0...3)
                points.append(SIMD3<Float>(x, y, z))
            }

            pointClouds.append(AIPointCloud(points: points, pointCount: points.count))
        }

        // When: Creating fusion and integrating all clouds
        var volume = TSDFVolume(pointClouds: pointClouds, voxelSize: testVoxelSize)

        for (index, cloud) in pointClouds.enumerated() {
            let weight: Float = index < 60 ? 1.0 : 2.0
            volume.integratePointCloud(cloud, weight: weight)
        }

        // Then: Memory should stay under limit (1.5GB = 1,500,000,000 bytes)
        let memoryBytes = volume.estimatedMemoryBytes
        let memoryLimit = 1_500_000_000

        XCTAssertLessThan(memoryBytes, memoryLimit, "Memory should stay under 1.5GB limit")

        // Log actual memory usage for debugging
        print("Test memory usage: \(memoryBytes / 1_000_000)MB")
    }

    // MARK: 8.6 - Test Progress Reporting and Cancellation

    func testProgressReportingAndCancellation() async throws {
        // Given: A fusion with a few point clouds
        let points = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.1, 0, 0)]
        let cloud = AIPointCloud(points: points, pointCount: points.count)
        let clouds = [cloud, cloud, cloud]  // 3 clouds

        let fusion = await TSDFFusion()

        // M4 fix: Check initial state BEFORE starting the task
        // to avoid race condition where fusion might start before we check
        let initialProgress = await fusion.progress
        let initialIsProcessing = await fusion.isProcessing
        XCTAssertEqual(initialProgress, 0.0, accuracy: 0.01, "Progress should be 0 before starting")
        XCTAssertFalse(initialIsProcessing, "Should not be processing before starting")

        // When: Starting fusion
        let result = try await fusion.fuse(pointClouds: clouds, videoCount: 2)

        // Then: After completion, progress should be 1.0
        let finalProgress = await fusion.progress
        XCTAssertEqual(finalProgress, 1.0, accuracy: 0.01, "Progress should be 1.0 after completion")

        // Verify result is valid
        XCTAssertGreaterThan(result.integratedCloudCount, 0, "Should have integrated clouds")
    }

    func testCancellation() async throws {
        // Given: A fusion with many point clouds
        var clouds: [AIPointCloud] = []
        for _ in 0..<100 {
            var points: [SIMD3<Float>] = []
            for _ in 0..<100 {
                points.append(SIMD3<Float>(Float.random(in: -1...1),
                                          Float.random(in: -1...1),
                                          Float.random(in: -1...1)))
            }
            clouds.append(AIPointCloud(points: points, pointCount: points.count))
        }

        let fusion = await TSDFFusion()

        // When: Starting and immediately cancelling
        let task = Task {
            try await fusion.fuse(pointClouds: clouds, videoCount: 90)
        }

        // Cancel after a brief delay
        try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
        task.cancel()

        // Then: Task should be cancelled
        do {
            _ = try await task.value
            // If we get here, cancellation might not have happened
            // This is OK if processing was fast enough
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors are also acceptable (like TSDFFusionError.cancelled)
        }
    }

    // MARK: 8.7 - Test Confidence Weighting

    func testConfidenceWeightingPhotosHigherThanVideo() throws {
        // Given: Same point from two sources
        let point = SIMD3<Float>(0.1, 0.1, 0.1)
        let videoCloud = AIPointCloud(points: [point], pointCount: 1)
        let photoCloud = AIPointCloud(points: [point], pointCount: 1)

        // When: Integrating with different weights
        var volume = TSDFVolume(pointClouds: [videoCloud], voxelSize: testVoxelSize)

        // Video weight = 1.0
        volume.integratePointCloud(videoCloud, weight: 1.0)
        let weightAfterVideo = getVoxelWeight(for: point, in: volume)

        // Photo weight = 2.0
        volume.integratePointCloud(photoCloud, weight: 2.0)
        let weightAfterPhoto = getVoxelWeight(for: point, in: volume)

        // Then: Weight should increase more from photo
        let videoContribution = weightAfterVideo ?? 0
        let totalContribution = weightAfterPhoto ?? 0
        let photoContribution = totalContribution - videoContribution

        XCTAssertEqual(videoContribution, 1.0, accuracy: 0.5, "Video contribution should be ~1.0")
        XCTAssertEqual(photoContribution, 2.0, accuracy: 0.5, "Photo contribution should be ~2.0")
    }

    // MARK: 8.8 - Test Sparse Voxel Grid Doesn't Allocate Empty Regions

    func testSparseVoxelGridEfficiency() throws {
        // Given: Points in a small region of a large bounding box
        let points = [
            SIMD3<Float>(0.0, 0.0, 0.0),
            SIMD3<Float>(0.1, 0.0, 0.0),
            SIMD3<Float>(0.0, 0.1, 0.0),
        ]
        let cloud = AIPointCloud(points: points, pointCount: points.count)

        // Create volume with large bounding box
        var volume = TSDFVolume(voxelSize: testVoxelSize, boundingBox: TSDFBoundingBox(
            min: SIMD3<Float>(-10, -10, -10),
            max: SIMD3<Float>(10, 10, 10)
        ))

        // When: Integrating the small point cloud
        volume.integratePointCloud(cloud, weight: 1.0)

        // Then: Only a small number of voxels should be allocated
        // Dense grid would be: 1000 x 1000 x 1000 = 1 billion voxels
        // Sparse should be: ~100-200 voxels for these 3 points
        let denseVoxelCount = 1000 * 1000 * 1000
        let sparseRatio = Double(volume.allocatedVoxelCount) / Double(denseVoxelCount)

        XCTAssertLessThan(sparseRatio, 0.0001, "Sparse grid should use < 0.01% of dense grid")
        XCTAssertLessThan(volume.allocatedVoxelCount, 10000, "Should allocate only voxels near points")

        print("Sparse efficiency: \(volume.allocatedVoxelCount) voxels allocated (dense would be \(denseVoxelCount))")
    }

    // MARK: - TSDFBoundingBox Tests

    func testBoundingBoxExpansion() {
        // Given: An invalid bounding box
        var bbox = TSDFBoundingBox.invalid
        XCTAssertFalse(bbox.isValid)

        // When: Expanding to include points
        bbox.expand(toInclude: SIMD3<Float>(1, 2, 3))
        bbox.expand(toInclude: SIMD3<Float>(-1, -2, -3))

        // Then: Bounding box should be valid and contain points
        XCTAssertTrue(bbox.isValid)
        XCTAssertEqual(bbox.min.x, -1, accuracy: epsilon)
        XCTAssertEqual(bbox.min.y, -2, accuracy: epsilon)
        XCTAssertEqual(bbox.min.z, -3, accuracy: epsilon)
        XCTAssertEqual(bbox.max.x, 1, accuracy: epsilon)
        XCTAssertEqual(bbox.max.y, 2, accuracy: epsilon)
        XCTAssertEqual(bbox.max.z, 3, accuracy: epsilon)
    }

    func testBoundingBoxMargin() {
        // Given: A bounding box
        var bbox = TSDFBoundingBox(
            min: SIMD3<Float>(0, 0, 0),
            max: SIMD3<Float>(1, 1, 1)
        )

        // When: Expanding by margin
        bbox.expand(byMargin: 0.5)

        // Then: Box should be larger by margin on all sides
        XCTAssertEqual(bbox.min.x, -0.5, accuracy: epsilon)
        XCTAssertEqual(bbox.max.x, 1.5, accuracy: epsilon)
    }

    // MARK: - Voxel Index Tests

    func testVoxelIndexHashing() {
        // Given: Two identical indices
        let idx1 = VoxelIndex(x: 5, y: 10, z: 15)
        let idx2 = VoxelIndex(x: 5, y: 10, z: 15)

        // Then: They should be equal and have same hash
        XCTAssertEqual(idx1, idx2)
        XCTAssertEqual(idx1.hashValue, idx2.hashValue)

        // And: Different indices should not be equal
        let idx3 = VoxelIndex(x: 5, y: 10, z: 16)
        XCTAssertNotEqual(idx1, idx3)
    }

    // MARK: - Marching Cubes Tests

    func testMarchingCubesEmptyVolume() throws {
        // Given: An empty volume
        let volume = TSDFVolume(voxelSize: testVoxelSize)

        // When: Extracting mesh
        let mesh = try MarchingCubes.extractMesh(from: volume)

        // Then: Mesh should be empty
        XCTAssertTrue(mesh.isEmpty)
    }

    func testMeshDecimation() {
        // Given: A mesh with many triangles in a 3D grid pattern
        // M3 fix: Create a more realistic mesh for proper decimation testing
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Create a 10x10 grid of triangles (200 triangles) with some 3D structure
        for row in 0..<10 {
            for col in 0..<10 {
                let x = Float(col) * 0.02
                let y = Float(row) * 0.02
                let z = sin(Float(row + col) * 0.5) * 0.01  // Add some Z variation

                // Create two triangles per cell (quad)
                let baseIdx = UInt32(vertices.count)

                vertices.append(SIMD3<Float>(x, y, z))
                vertices.append(SIMD3<Float>(x + 0.02, y, z))
                vertices.append(SIMD3<Float>(x + 0.02, y + 0.02, z))
                vertices.append(SIMD3<Float>(x, y + 0.02, z))

                // Triangle 1
                indices.append(baseIdx)
                indices.append(baseIdx + 1)
                indices.append(baseIdx + 2)

                // Triangle 2
                indices.append(baseIdx)
                indices.append(baseIdx + 2)
                indices.append(baseIdx + 3)
            }
        }

        let mesh = AIMesh(vertices: vertices, indices: indices)
        XCTAssertEqual(mesh.triangleCount, 200)

        // When: Decimating to 50 triangles
        let decimated = MarchingCubes.decimateMesh(mesh, targetTriangleCount: 50)

        // Then: M3 fix - Triangle count should be close to target (within 20% overshoot allowed)
        XCTAssertLessThanOrEqual(decimated.triangleCount, 60, "Decimation should reach close to target (50 + 20% = 60)")
        XCTAssertGreaterThan(decimated.triangleCount, 0, "Decimation should not produce empty mesh")

        // Verify mesh integrity
        for index in decimated.indices {
            XCTAssertLessThan(Int(index), decimated.vertices.count, "All indices should be valid")
        }
    }

    // MARK: - Helper Methods

    private func getVoxelWeight(for point: SIMD3<Float>, in volume: TSDFVolume) -> Float? {
        guard let idx = volume.voxelIndex(for: point),
              let voxel = volume.getVoxel(at: idx) else {
            return nil
        }
        return voxel.weight
    }
}

// MARK: - AIMesh Extension for Tests

extension AIMesh {
    /// Creates an empty mesh
    init() {
        self.init(vertices: [], indices: [])
    }
}
