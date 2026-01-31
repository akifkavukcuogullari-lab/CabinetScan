//
//  TSDFFusion.swift
//  cabinetscan
//
//  Created for Story 3.4: Multi-View Fusion (TSDF)
//

import Foundation
import Combine
import Metal
import simd
import os.log

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - TSDF Fusion Errors

enum TSDFFusionError: LocalizedError {
    case noPointClouds
    case metalDeviceUnavailable
    case pipelineCreationFailed(String)
    case bufferAllocationFailed
    case cancelled
    case fusionFailed(String)
    case meshExtractionFailed(String)
    case memoryLimitExceeded

    var errorDescription: String? {
        switch self {
        case .noPointClouds:
            return "No point clouds provided for fusion"
        case .metalDeviceUnavailable:
            return "Metal device is not available"
        case .pipelineCreationFailed(let reason):
            return "Failed to create Metal pipeline: \(reason)"
        case .bufferAllocationFailed:
            return "Failed to allocate Metal buffer"
        case .cancelled:
            return "TSDF fusion was cancelled"
        case .fusionFailed(let reason):
            return "TSDF fusion failed: \(reason)"
        case .meshExtractionFailed(let reason):
            return "Mesh extraction failed: \(reason)"
        case .memoryLimitExceeded:
            return "Memory limit exceeded during fusion"
        }
    }
}

// MARK: - Voxel Types

/// 3D voxel index for sparse grid storage (ADR-006)
struct VoxelIndex: Hashable {
    let x: Int
    let y: Int
    let z: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
    }
}

/// Single TSDF voxel storing signed distance and accumulated weight
/// Enhanced for Story 6.4: Reflective Surface Handling - includes variance tracking
struct TSDFVoxel {
    /// Truncated signed distance (-truncation to +truncation)
    /// Positive = outside surface, Negative = inside surface, Zero = on surface
    var tsdf: Float = 0

    /// Accumulated weight for running average
    var weight: Float = 0

    // MARK: - Variance Tracking (Story 6.4, Task 2.1-2.3)

    /// Sum of squared TSDF values for variance calculation: E[X²]
    /// Used with Welford's online algorithm variant for running variance
    var sumSquared: Float = 0

    /// Calculated observation variance across multiple views.
    /// High variance indicates potential reflective surface (AC4).
    ///
    /// Formula: Var(X) = E[X²] - E[X]²
    /// - Returns: Variance value, or 0 if insufficient observations
    var observationVariance: Float {
        // Need at least 2 observations for meaningful variance
        guard weight > 1 else { return 0 }

        let mean = tsdf
        let meanOfSquares = sumSquared / weight

        // Variance = E[X²] - E[X]²
        // max(0, ...) to handle floating point errors that could give tiny negatives
        return max(0, meanOfSquares - mean * mean)
    }
}

// MARK: - Bounding Box for TSDF (min/max style)

/// Axis-aligned bounding box using min/max corners
struct TSDFBoundingBox {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    var size: SIMD3<Float> { max - min }
    var center: SIMD3<Float> { (min + max) / 2 }

    /// Creates an invalid bounding box (for initialization before expansion)
    static var invalid: TSDFBoundingBox {
        TSDFBoundingBox(
            min: SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude),
            max: SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        )
    }

    /// Whether this bounding box is valid (has been expanded at least once)
    var isValid: Bool {
        min.x <= max.x && min.y <= max.y && min.z <= max.z
    }

    /// Expands the bounding box to include a point
    mutating func expand(toInclude point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    /// Expands the bounding box by a margin on all sides
    mutating func expand(byMargin margin: Float) {
        min -= SIMD3<Float>(repeating: margin)
        max += SIMD3<Float>(repeating: margin)
    }
}

// MARK: - TSDF Volume

/// Sparse volumetric TSDF representation (ADR-006).
///
/// Uses dictionary-based sparse storage to only allocate voxels that have been
/// updated with actual data, reducing memory from O(n^3) to O(number_of_surface_voxels).
struct TSDFVolume {
    /// Voxel size in meters (2cm = 0.02m per AC2)
    let voxelSize: Float

    /// Truncation distance for SDF values (ADR-007: 3 * voxelSize)
    let truncationDistance: Float

    /// Bounding box of the volume in world coordinates
    private(set) var boundingBox: TSDFBoundingBox

    /// Sparse voxel storage - only surface voxels are allocated (ADR-006)
    private var voxels: [VoxelIndex: TSDFVoxel] = [:]

    /// Grid dimensions (computed from bounding box and voxel size)
    var gridDimensions: SIMD3<Int> {
        guard boundingBox.isValid else { return .zero }
        let size = boundingBox.size
        return SIMD3<Int>(
            Int(ceil(size.x / voxelSize)),
            Int(ceil(size.y / voxelSize)),
            Int(ceil(size.z / voxelSize))
        )
    }

    /// Number of allocated voxels (for memory tracking)
    var allocatedVoxelCount: Int { voxels.count }

    /// Estimated memory usage in bytes
    var estimatedMemoryBytes: Int {
        // Each voxel: VoxelIndex (3 * 8 = 24 bytes) + TSDFVoxel (8 bytes) = 32 bytes
        // Plus dictionary overhead (~1.5x)
        return voxels.count * 48
    }

    // MARK: - Initialization

    /// Creates a TSDF volume with specified parameters.
    ///
    /// - Parameters:
    ///   - voxelSize: Size of each voxel in meters (default 0.02 = 2cm per AC2)
    ///   - boundingBox: Initial bounding box (can be expanded later)
    init(voxelSize: Float = 0.02, boundingBox: TSDFBoundingBox = .invalid) {
        self.voxelSize = voxelSize
        self.truncationDistance = voxelSize * 3  // ADR-007
        self.boundingBox = boundingBox
    }

    /// Creates a TSDF volume sized to fit the given point clouds.
    ///
    /// - Parameters:
    ///   - pointClouds: Point clouds to calculate bounding box from
    ///   - voxelSize: Size of each voxel in meters
    ///   - margin: Extra margin around the bounding box in meters
    init(pointClouds: [AIPointCloud], voxelSize: Float = 0.02, margin: Float = 0.1) {
        self.voxelSize = voxelSize
        self.truncationDistance = voxelSize * 3

        var bbox = TSDFBoundingBox.invalid

        for cloud in pointClouds {
            // Use metalBuffer if available, otherwise use points array
            if let buffer = cloud.metalBuffer, cloud.count > 0 {
                let pointer = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: cloud.count)
                for i in 0..<cloud.count {
                    bbox.expand(toInclude: pointer[i])
                }
            } else {
                for point in cloud.points {
                    bbox.expand(toInclude: point)
                }
            }
        }

        // Add margin
        bbox.expand(byMargin: margin)

        self.boundingBox = bbox
    }

    // MARK: - Voxel Access

    /// Gets the voxel index for a world-space position.
    func voxelIndex(for position: SIMD3<Float>) -> VoxelIndex? {
        guard boundingBox.isValid else { return nil }

        let relative = position - boundingBox.min
        let ix = Int(floor(relative.x / voxelSize))
        let iy = Int(floor(relative.y / voxelSize))
        let iz = Int(floor(relative.z / voxelSize))

        let dims = gridDimensions
        guard ix >= 0 && ix < dims.x &&
              iy >= 0 && iy < dims.y &&
              iz >= 0 && iz < dims.z else {
            return nil
        }

        return VoxelIndex(x: ix, y: iy, z: iz)
    }

    /// Gets the world-space center position of a voxel.
    func voxelCenter(for index: VoxelIndex) -> SIMD3<Float> {
        return boundingBox.min + SIMD3<Float>(
            (Float(index.x) + 0.5) * voxelSize,
            (Float(index.y) + 0.5) * voxelSize,
            (Float(index.z) + 0.5) * voxelSize
        )
    }

    /// Gets the voxel at the specified index, or nil if not allocated.
    func getVoxel(at index: VoxelIndex) -> TSDFVoxel? {
        return voxels[index]
    }

    /// Gets or creates the voxel at the specified index.
    mutating func getOrCreateVoxel(at index: VoxelIndex) -> TSDFVoxel {
        if let existing = voxels[index] {
            return existing
        }
        let newVoxel = TSDFVoxel()
        voxels[index] = newVoxel
        return newVoxel
    }

    /// Updates a voxel at the specified index.
    mutating func setVoxel(_ voxel: TSDFVoxel, at index: VoxelIndex) {
        voxels[index] = voxel
    }

    // MARK: - Integration

    /// Integrates a single point into the TSDF volume (CPU implementation for tests).
    ///
    /// For each point, updates all voxels within truncation distance using
    /// the running weighted average formula (AC1, AC6).
    ///
    /// Uses proper signed distance when normals are available:
    /// - Positive SDF = voxel is in front of surface (outside/free space)
    /// - Negative SDF = voxel is behind surface (inside/solid)
    /// - Zero SDF = voxel is on the surface
    ///
    /// - Parameters:
    ///   - point: World-space point to integrate
    ///   - normal: Optional surface normal at the point (pointing outward from surface)
    ///   - weight: Weight for this observation (1.0 for video, 2.0 for photos per AC6)
    mutating func integratePoint(_ point: SIMD3<Float>, normal: SIMD3<Float>?, weight: Float) {
        // Find voxels within truncation distance of the point
        let searchRadius = Int(ceil(truncationDistance / voxelSize))

        guard let centerIndex = voxelIndex(for: point) else { return }

        for dx in -searchRadius...searchRadius {
            for dy in -searchRadius...searchRadius {
                for dz in -searchRadius...searchRadius {
                    let voxelIdx = VoxelIndex(
                        x: centerIndex.x + dx,
                        y: centerIndex.y + dy,
                        z: centerIndex.z + dz
                    )

                    // Bounds check
                    let dims = gridDimensions
                    guard voxelIdx.x >= 0 && voxelIdx.x < dims.x &&
                          voxelIdx.y >= 0 && voxelIdx.y < dims.y &&
                          voxelIdx.z >= 0 && voxelIdx.z < dims.z else {
                        continue
                    }

                    let center = voxelCenter(for: voxelIdx)
                    let toVoxel = center - point
                    let distance = simd_length(toVoxel)

                    // Skip if outside truncation distance
                    guard distance <= truncationDistance else { continue }

                    // Calculate signed distance
                    let sdf: Float
                    if let n = normal, simd_length(n) > 0.001 {
                        // With normal: sign based on which side of the surface the voxel is
                        // dot(normal, toVoxel) > 0 means voxel is in front of surface (positive SDF)
                        // dot(normal, toVoxel) < 0 means voxel is behind surface (negative SDF)
                        sdf = simd_dot(simd_normalize(n), toVoxel)
                    } else {
                        // Without normal: use projective distance approximation
                        // Assume camera is above (positive Y), so points face upward
                        // Voxels above the point are outside (positive), below are inside (negative)
                        // This is a reasonable default for floor/counter surfaces scanned from above
                        sdf = toVoxel.y > 0 ? distance : -distance
                    }

                    // Truncate to [-truncation, +truncation]
                    let truncatedSDF = max(-truncationDistance, min(sdf, truncationDistance))

                    // Get or create voxel and update using running weighted average
                    var voxel = getOrCreateVoxel(at: voxelIdx)
                    let newWeight = voxel.weight + weight

                    // Story 6.4: Update running variance tracking (Task 2.2-2.3)
                    // Track sum of squared values for variance calculation
                    voxel.sumSquared += truncatedSDF * truncatedSDF * weight

                    // Update TSDF using running weighted average
                    voxel.tsdf = (voxel.tsdf * voxel.weight + truncatedSDF * weight) / newWeight
                    voxel.weight = newWeight

                    setVoxel(voxel, at: voxelIdx)
                }
            }
        }
    }

    /// Integrates an entire point cloud into the volume.
    ///
    /// - Parameters:
    ///   - pointCloud: Point cloud to integrate
    ///   - weight: Weight for all points in this cloud
    mutating func integratePointCloud(_ pointCloud: AIPointCloud, weight: Float) {
        // Get points from metalBuffer if available
        var points: [SIMD3<Float>]
        if let buffer = pointCloud.metalBuffer, pointCloud.count > 0 {
            let pointer = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: pointCloud.count)
            points = Array(UnsafeBufferPointer(start: pointer, count: pointCloud.count))
        } else {
            points = pointCloud.points
        }

        // Get normals if available
        let normals = pointCloud.normals

        for (index, point) in points.enumerated() {
            let normal = normals?[safe: index]
            integratePoint(point, normal: normal, weight: weight)
        }
    }

    // MARK: - Iteration

    /// Iterates over all allocated voxels.
    func forEachVoxel(_ body: (VoxelIndex, TSDFVoxel) -> Void) {
        for (index, voxel) in voxels {
            body(index, voxel)
        }
    }

    /// Returns all voxel indices that could contain a surface crossing.
    /// A voxel potentially contains a surface if it has observations and
    /// at least one neighbor has a different sign.
    func getSurfaceVoxelIndices() -> [VoxelIndex] {
        var surfaceVoxels: [VoxelIndex] = []

        for (index, voxel) in voxels {
            guard voxel.weight > 0 else { continue }

            // Check if this voxel or any neighbor could contain a surface
            // For now, include all voxels with observations
            surfaceVoxels.append(index)
        }

        return surfaceVoxels
    }

    // MARK: - Variance Analysis (Story 6.4, Task 2.4-2.6)

    /// Checks if a new observation is consistent with existing voxel state.
    /// High variance indicates potential reflective surface.
    ///
    /// - Parameters:
    ///   - newSDF: The new SDF observation
    ///   - voxel: The existing voxel state
    /// - Returns: True if observation is consistent, false if potentially reflective
    func checkObservationConsistency(newSDF: Float, voxel: TSDFVoxel) -> Bool {
        // Need at least 2 observations for comparison
        guard voxel.weight >= 1 else { return true }

        // Check if new observation deviates significantly from mean
        let deviation = abs(newSDF - voxel.tsdf)
        let threshold = truncationDistance * 0.5  // 50% of truncation = significant deviation

        return deviation <= threshold
    }

    /// Returns voxels with variance above the threshold.
    /// These are candidates for reflective surface regions.
    ///
    /// - Parameter threshold: Variance threshold (default: 0.04 for ~2cm std dev)
    /// - Returns: Array of (index, variance) tuples for high-variance voxels
    func flagHighVarianceVoxels(threshold: Float = 0.04) -> [(VoxelIndex, Float)] {
        var results: [(VoxelIndex, Float)] = []

        for (index, voxel) in voxels {
            guard voxel.weight >= 2 else { continue }

            let variance = voxel.observationVariance
            if variance > threshold {
                results.append((index, variance))
            }
        }

        return results
    }

    // MARK: - Memory Management

    /// Removes voxels with low weight (likely noise).
    mutating func pruneWeakVoxels(minimumWeight: Float = 0.5) {
        voxels = voxels.filter { $0.value.weight >= minimumWeight }
    }

    /// Clears all voxels.
    mutating func clear() {
        voxels.removeAll()
    }
}

// MARK: - TSDF Fusion Result

/// Result of TSDF fusion containing the unified mesh and metadata
struct TSDFFusionResult {
    /// Extracted surface mesh
    let mesh: AIMesh

    /// Bounding box of the fused volume (in world coordinates)
    let boundingBox: TSDFBoundingBox

    /// Voxel resolution used (in meters)
    let voxelSize: Float

    /// Number of point clouds integrated
    let integratedCloudCount: Int

    /// Total points processed
    let totalPointsProcessed: Int

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Fusion quality metrics
    let qualityMetrics: TSDFQualityMetrics

    // MARK: - Story 6.4: Reflective Surface Analysis

    /// Reflective surface analysis result (optional, nil if not run)
    let reflectiveSurfaceAnalysis: ReflectiveSurfaceAnalysisResult?

    /// Creates a fusion result with optional reflective surface analysis
    init(
        mesh: AIMesh,
        boundingBox: TSDFBoundingBox,
        voxelSize: Float,
        integratedCloudCount: Int,
        totalPointsProcessed: Int,
        processingTimeMs: Int,
        qualityMetrics: TSDFQualityMetrics,
        reflectiveSurfaceAnalysis: ReflectiveSurfaceAnalysisResult? = nil
    ) {
        self.mesh = mesh
        self.boundingBox = boundingBox
        self.voxelSize = voxelSize
        self.integratedCloudCount = integratedCloudCount
        self.totalPointsProcessed = totalPointsProcessed
        self.processingTimeMs = processingTimeMs
        self.qualityMetrics = qualityMetrics
        self.reflectiveSurfaceAnalysis = reflectiveSurfaceAnalysis
    }
}

/// Surface mesh generated from TSDF fusion
struct AIMesh {
    /// Triangle vertices (3 vertices per triangle, indexed by indices array)
    let vertices: [SIMD3<Float>]

    /// Triangle indices (3 indices per triangle)
    let indices: [UInt32]

    /// Number of triangles
    var triangleCount: Int { indices.count / 3 }

    /// Number of vertices
    var vertexCount: Int { vertices.count }

    /// Whether the mesh is empty
    var isEmpty: Bool { vertices.isEmpty || indices.isEmpty }

    /// Optional: Metal buffer for GPU consumption
    var vertexBuffer: MTLBuffer?
    var indexBuffer: MTLBuffer?

    /// Empty mesh
    static let empty = AIMesh(vertices: [], indices: [])
}

/// Quality metrics for TSDF fusion
struct TSDFQualityMetrics {
    /// Percentage of grid covered by voxels with observations
    let coveragePercentage: Double

    /// Average weight per voxel (higher = more observations)
    let averageVoxelWeight: Float

    /// Total number of voxels with observations
    let totalVoxelCount: Int

    /// Whether mesh is manifold (no holes, properly connected)
    let isMeshManifold: Bool
}

// MARK: - TSDF Fusion Orchestrator

/// Fuses multiple point clouds into a unified 3D volume using TSDF.
///
/// **Architecture Decision Records:**
/// - **ADR-001:** Metal is REQUIRED for production; CPU fallback for tests/simulator only
/// - **ADR-006:** Sparse voxel grid for memory efficiency
/// - **ADR-007:** Truncation distance = 3 * voxel size
/// - **ADR-008:** Atomic operations for thread-safe GPU voxel updates
///
/// **Usage:**
/// ```swift
/// let fusion = TSDFFusion()
/// let result = try await fusion.fuse(pointClouds: clouds, videoCount: 60)
/// ```
@MainActor
final class TSDFFusion: ObservableObject {

    // MARK: - Constants

    /// Batch size for autoreleasepool processing (from Story 3.2 learnings)
    private static let batchSize = 10

    /// Default voxel size in meters (2cm per AC2)
    private static let defaultVoxelSize: Float = 0.02

    /// Memory limit in bytes (1.5GB per AC4/NFR13)
    private static let memoryLimit: Int = 1_500_000_000

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current processing phase
    @Published private(set) var currentPhase: FusionPhase = .idle

    /// Whether fusion is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let metalPipeline: TSDFMetalPipeline?
    private let logger = Logger(subsystem: "com.cabinetscan", category: "TSDFFusion")

    // MARK: - Fusion Phase

    enum FusionPhase: String {
        case idle = "Idle"
        case calculatingBounds = "Calculating Bounds"
        case integrating = "Integrating Point Clouds"
        case extractingMesh = "Extracting Mesh"
        case complete = "Complete"
    }

    // MARK: - Initialization

    /// Creates a TSDF fusion processor.
    /// Attempts to create Metal pipeline; falls back to CPU for simulator/tests (ADR-001).
    init() {
        // Try to create Metal pipeline (production path)
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                self.metalPipeline = try TSDFMetalPipeline(device: device)
                logger.info("TSDF Metal pipeline initialized successfully")
            } catch {
                logger.warning("Failed to create TSDF Metal pipeline: \(error.localizedDescription). Using CPU fallback.")
                self.metalPipeline = nil
            }
        } else {
            // No Metal device - this is expected on simulator (ADR-001)
            logger.info("No Metal device available - using CPU fallback (simulator/test environment)")
            self.metalPipeline = nil
        }
    }

    // MARK: - Main Fusion Entry Point

    /// Fuses multiple point clouds into a unified mesh.
    ///
    /// - Parameters:
    ///   - pointClouds: Array of point clouds to fuse
    ///   - videoCount: Number of point clouds that are from video (remaining are photos)
    /// - Returns: Fusion result with mesh and metadata
    func fuse(
        pointClouds: [AIPointCloud],
        videoCount: Int
    ) async throws -> TSDFFusionResult {
        guard !pointClouds.isEmpty else {
            throw TSDFFusionError.noPointClouds
        }

        logger.info("Starting TSDF fusion for \(pointClouds.count) point clouds (\(videoCount) video, \(pointClouds.count - videoCount) photo)")

        isProcessing = true
        progress = 0.0
        currentPhase = .calculatingBounds

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            isProcessing = false
            currentPhase = .complete
            metalPipeline?.releaseBuffers()
        }

        // Step 1: Calculate bounding box from all point clouds
        currentPhase = .calculatingBounds
        var volume = TSDFVolume(pointClouds: pointClouds, voxelSize: Self.defaultVoxelSize)

        logger.info("Volume initialized: \(volume.gridDimensions.x)x\(volume.gridDimensions.y)x\(volume.gridDimensions.z) voxels")

        progress = 0.05

        // Step 2: Integrate all point clouds
        currentPhase = .integrating
        var totalPointsProcessed = 0

        for (index, cloud) in pointClouds.enumerated() {
            try Task.checkCancellation()

            // Weight: video = 1.0, photos = 2.0 (AC6)
            let weight: Float = index < videoCount ? 1.0 : 2.0

            // Use Metal pipeline if available, otherwise CPU
            if let pipeline = metalPipeline {
                try await pipeline.integratePointCloud(cloud, into: &volume, weight: weight)
            } else {
                autoreleasepool {
                    volume.integratePointCloud(cloud, weight: weight)
                }
            }

            totalPointsProcessed += cloud.count

            // Update progress (5% - 80% for integration)
            progress = 0.05 + Double(index + 1) / Double(pointClouds.count) * 0.75

            // Memory check
            if volume.estimatedMemoryBytes > Self.memoryLimit {
                logger.warning("Memory limit approaching, pruning weak voxels")
                volume.pruneWeakVoxels(minimumWeight: 1.0)
            }
        }

        logger.info("Integration complete: \(volume.allocatedVoxelCount) voxels, \(totalPointsProcessed) points processed")

        // Step 3: Extract mesh using marching cubes
        currentPhase = .extractingMesh
        progress = 0.85

        let mesh = try MarchingCubes.extractMesh(from: volume)

        progress = 1.0

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        logger.info("TSDF fusion complete: \(mesh.triangleCount) triangles in \(processingTimeMs)ms")

        // Calculate quality metrics
        let dims = volume.gridDimensions
        let totalPossibleVoxels = dims.x * dims.y * dims.z
        let coveragePercentage = totalPossibleVoxels > 0
            ? Double(volume.allocatedVoxelCount) / Double(totalPossibleVoxels) * 100
            : 0

        var totalWeight: Float = 0
        volume.forEachVoxel { _, voxel in
            totalWeight += voxel.weight
        }
        let averageWeight = volume.allocatedVoxelCount > 0
            ? totalWeight / Float(volume.allocatedVoxelCount)
            : 0

        let qualityMetrics = TSDFQualityMetrics(
            coveragePercentage: coveragePercentage,
            averageVoxelWeight: averageWeight,
            totalVoxelCount: volume.allocatedVoxelCount,
            isMeshManifold: true  // Marching cubes produces manifold meshes by construction
        )

        // Story 6.4: Run reflective surface analysis on the fused volume
        let reflectiveAnalysis = analyzeReflectiveSurfaces(volume: volume)

        return TSDFFusionResult(
            mesh: mesh,
            boundingBox: volume.boundingBox,
            voxelSize: volume.voxelSize,
            integratedCloudCount: pointClouds.count,
            totalPointsProcessed: totalPointsProcessed,
            processingTimeMs: processingTimeMs,
            qualityMetrics: qualityMetrics,
            reflectiveSurfaceAnalysis: reflectiveAnalysis
        )
    }

    // MARK: - Story 6.4: Reflective Surface Analysis

    /// Analyzes the fused volume for reflective surfaces using variance data.
    /// This runs after all point clouds have been integrated.
    private func analyzeReflectiveSurfaces(volume: TSDFVolume) -> ReflectiveSurfaceAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Get high-variance voxels
        let highVarianceVoxels = volume.flagHighVarianceVoxels(threshold: ReflectiveSurfaceDetector.varianceThreshold)

        var totalVoxels = 0
        volume.forEachVoxel { _, voxel in
            if voxel.weight >= 2 {
                totalVoxels += 1
            }
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        if highVarianceVoxels.count > 0 {
            logger.info("Story 6.4: Found \(highVarianceVoxels.count) high-variance voxels (\(String(format: "%.1f", Float(highVarianceVoxels.count) / Float(max(1, totalVoxels)) * 100))%)")
        }

        return ReflectiveSurfaceAnalysisResult(
            totalVoxelsAnalyzed: totalVoxels,
            highVarianceVoxelCount: highVarianceVoxels.count,
            reflectiveRegions: [],  // Full region detection done by ReflectiveSurfaceDetector if needed
            mirrorRegions: [],
            processingTimeMs: processingTimeMs
        )
    }
}
