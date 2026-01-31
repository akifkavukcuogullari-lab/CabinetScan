//
//  PointCloudGenerator.swift
//  cabinetscan
//
//  Created for Story 3.3: Point Cloud Generation
//

import Foundation
import Combine
import Metal
import simd
import os.log

// MARK: - Point Cloud Generation Errors

enum PointCloudGenerationError: LocalizedError {
    case noDepthFrames
    case metalDeviceUnavailable
    case pipelineCreationFailed(String)
    case bufferAllocationFailed
    case cancelled
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDepthFrames:
            return "No depth frames provided for point cloud generation"
        case .metalDeviceUnavailable:
            return "Metal device is not available"
        case .pipelineCreationFailed(let reason):
            return "Failed to create Metal pipeline: \(reason)"
        case .bufferAllocationFailed:
            return "Failed to allocate Metal buffer"
        case .cancelled:
            return "Point cloud generation was cancelled"
        case .processingFailed(let reason):
            return "Point cloud processing failed: \(reason)"
        }
    }
}

// MARK: - Point Cloud Generation Result

/// Result of point cloud generation containing metadata
struct PointCloudGenerationResult {
    /// Generated point clouds (one per depth frame)
    let pointClouds: [AIPointCloud]

    /// Number of video frame point clouds
    let videoPointCloudCount: Int

    /// Number of photo point clouds
    let photoPointCloudCount: Int

    /// Total processing time in milliseconds
    let processingTimeMs: Int

    // MARK: - Story 6.4: Reflective Filtering Metrics (Task 4.4)

    /// Number of points filtered due to reflective artifact detection.
    ///
    /// **Design Note:** Per ADR-6.4.2, reflective surface detection is performed
    /// post-TSDF fusion via variance analysis, not during point cloud generation.
    /// This field tracks any pre-filtering done during generation (currently 0).
    /// The actual reflective impact is calculated by `ReflectiveSurfaceDetector`
    /// after fusion completes.
    let reflectiveFilteredCount: Int

    /// Percentage of points filtered for reflective artifacts (0.0-1.0)
    var reflectiveFilteredPercentage: Float {
        let total = totalPointCount + reflectiveFilteredCount
        guard total > 0 else { return 0 }
        return Float(reflectiveFilteredCount) / Float(total)
    }

    /// Total number of points across all clouds
    var totalPointCount: Int {
        pointClouds.reduce(0) { $0 + $1.count }
    }

    /// Average points per frame
    var averagePointsPerFrame: Int {
        guard !pointClouds.isEmpty else { return 0 }
        return totalPointCount / pointClouds.count
    }

    /// Creates a result with default reflective filtering (for backwards compatibility)
    init(
        pointClouds: [AIPointCloud],
        videoPointCloudCount: Int,
        photoPointCloudCount: Int,
        processingTimeMs: Int,
        reflectiveFilteredCount: Int = 0
    ) {
        self.pointClouds = pointClouds
        self.videoPointCloudCount = videoPointCloudCount
        self.photoPointCloudCount = photoPointCloudCount
        self.processingTimeMs = processingTimeMs
        self.reflectiveFilteredCount = reflectiveFilteredCount
    }
}

// MARK: - Point Cloud Generator

/// Converts depth maps into 3D point clouds using camera intrinsics and ARKit poses.
///
/// **Architecture Decision Records:**
/// - **ADR-001:** Metal is REQUIRED for production; CPU fallback for tests/simulator only
/// - **ADR-002:** Keep point data in MTLBuffer for zero-copy GPU handoff
/// - **ADR-003:** Mandatory downsampling for video frames (factor 2, or 3 if >60 frames)
/// - **ADR-004:** Filter depths outside 0.001-0.999 range
/// - **ADR-005:** Do NOT adjust intrinsics for zoom - ARKit already handles it
///
/// **Usage:**
/// ```swift
/// let generator = PointCloudGenerator()
/// let result = try await generator.generatePointClouds(from: depthFrames, isVideoFrame: frameTypes)
/// ```
@MainActor
final class PointCloudGenerator: ObservableObject {

    // MARK: - Constants

    /// Batch size for autoreleasepool processing (from Story 3.2 learnings)
    private static let batchSize = 10

    /// Default downsampling factor for video frames (ADR-003)
    private static let defaultVideoDownsampleFactor = 2

    /// Downsampling factor for large captures (>60 video frames) (ADR-003)
    private static let largeCaptureDownsampleFactor = 3

    /// Threshold for large capture detection
    private static let largeCaptureThreshold = 60

    /// Depth filtering thresholds (ADR-004)
    private static let minValidDepth: Float = 0.001
    private static let maxValidDepth: Float = 0.999

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current frame index being processed
    @Published private(set) var currentFrameIndex: Int = 0

    /// Total number of frames to process
    @Published private(set) var totalFrameCount: Int = 0

    /// Whether generation is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let metalPipeline: PointCloudMetalPipeline?
    private let logger = Logger(subsystem: "com.cabinetscan", category: "PointCloudGenerator")

    // MARK: - Initialization

    /// Creates a point cloud generator.
    /// Attempts to create Metal pipeline; falls back to CPU for simulator/tests (ADR-001).
    init() {
        // Try to create Metal pipeline (production path)
        if let device = MTLCreateSystemDefaultDevice() {
            do {
                self.metalPipeline = try PointCloudMetalPipeline(device: device)
                logger.info("Metal pipeline initialized successfully")
            } catch {
                logger.warning("Failed to create Metal pipeline: \(error.localizedDescription). Using CPU fallback.")
                self.metalPipeline = nil
            }
        } else {
            // No Metal device - this is expected on simulator (ADR-001)
            logger.info("No Metal device available - using CPU fallback (simulator/test environment)")
            self.metalPipeline = nil
        }
    }

    // MARK: - Main Generation Entry Points

    /// Generates a point cloud from a single depth frame.
    ///
    /// - Parameters:
    ///   - depthFrame: The depth frame to convert
    ///   - isVideoFrame: Whether this is from video (applies downsampling) or photo (no downsampling)
    ///   - downsampleFactor: Override downsampling factor (default based on ADR-003)
    /// - Returns: Generated point cloud
    func generatePointCloud(
        from depthFrame: AIDepthFrame,
        isVideoFrame: Bool = true,
        downsampleFactor: Int? = nil
    ) async throws -> AIPointCloud {
        let factor = downsampleFactor ?? (isVideoFrame ? Self.defaultVideoDownsampleFactor : 1)

        if let pipeline = metalPipeline {
            return try await pipeline.generatePointCloud(from: depthFrame, downsampleFactor: factor)
        } else {
            return generatePointCloudCPU(from: depthFrame, downsampleFactor: factor)
        }
    }

    /// Generates point clouds from multiple depth frames.
    ///
    /// - Parameters:
    ///   - depthFrames: Array of depth frames to process
    ///   - videoFrameCount: Number of frames that are from video (remaining are photos)
    /// - Returns: Point cloud generation result with all point clouds
    func generatePointClouds(
        from depthFrames: [AIDepthFrame],
        videoFrameCount: Int
    ) async throws -> PointCloudGenerationResult {
        guard !depthFrames.isEmpty else {
            throw PointCloudGenerationError.noDepthFrames
        }

        logger.info("Starting point cloud generation for \(depthFrames.count) frames (\(videoFrameCount) video, \(depthFrames.count - videoFrameCount) photo)")

        isProcessing = true
        progress = 0.0
        currentFrameIndex = 0
        totalFrameCount = depthFrames.count

        let startTime = CFAbsoluteTimeGetCurrent()

        defer {
            isProcessing = false
            // Release Metal buffers after processing completes (M4 fix)
            metalPipeline?.releaseBuffers()
        }

        // Determine downsampling factor (ADR-003)
        let videoDownsampleFactor = videoFrameCount > Self.largeCaptureThreshold
            ? Self.largeCaptureDownsampleFactor
            : Self.defaultVideoDownsampleFactor

        logger.info("Using downsampling factor \(videoDownsampleFactor) for video frames")

        var pointClouds: [AIPointCloud] = []
        pointClouds.reserveCapacity(depthFrames.count)

        // Process in batches with memory management
        for batchStart in stride(from: 0, to: depthFrames.count, by: Self.batchSize) {
            try Task.checkCancellation()

            let batchEnd = min(batchStart + Self.batchSize, depthFrames.count)

            for i in batchStart..<batchEnd {
                try Task.checkCancellation()

                let frame = depthFrames[i]
                let isVideoFrame = i < videoFrameCount
                let factor = isVideoFrame ? videoDownsampleFactor : 1  // No downsampling for photos (ADR-003)

                let pointCloud: AIPointCloud
                if let pipeline = metalPipeline {
                    // Wrap sync operations in autoreleasepool (Story 3.2 pattern)
                    pointCloud = try await autoreleasepool {
                        try pipeline.generatePointCloud(from: frame, downsampleFactor: factor)
                    }
                } else {
                    pointCloud = autoreleasepool {
                        generatePointCloudCPU(from: frame, downsampleFactor: factor)
                    }
                }

                pointClouds.append(pointCloud)

                // Update progress
                currentFrameIndex = i + 1
                progress = Double(currentFrameIndex) / Double(totalFrameCount)
            }
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        logger.info("Point cloud generation complete: \(pointClouds.count) clouds in \(processingTimeMs)ms")

        progress = 1.0

        return PointCloudGenerationResult(
            pointClouds: pointClouds,
            videoPointCloudCount: videoFrameCount,
            photoPointCloudCount: depthFrames.count - videoFrameCount,
            processingTimeMs: processingTimeMs
        )
    }

    // MARK: - CPU Fallback Implementation (ADR-001: For tests/simulator only)

    /// CPU fallback for point cloud generation.
    /// **USE ONLY FOR TESTING** - Production devices always use Metal pipeline.
    ///
    /// - Parameters:
    ///   - depthFrame: Depth frame to convert
    ///   - downsampleFactor: Factor to downsample by (1 = no downsampling)
    /// - Returns: Generated point cloud
    func generatePointCloudCPU(
        from depthFrame: AIDepthFrame,
        downsampleFactor: Int = 1
    ) -> AIPointCloud {
        let depthData = depthFrame.depthData
        let height = depthFrame.height
        let width = depthFrame.width
        let intrinsics = depthFrame.pose.intrinsics
        let transform = depthFrame.pose.transform

        // Bounds validation (M3 fix)
        guard depthData.count >= height else {
            logger.error("Depth data height mismatch: expected \(height), got \(depthData.count)")
            return AIPointCloud(points: [], colors: nil, normals: nil, metalBuffer: nil, pointCount: 0)
        }

        // Use intrinsics directly - ARKit already accounts for zoom (ADR-005)
        let fx = intrinsics.fx
        let fy = intrinsics.fy
        let cx = intrinsics.cx
        let cy = intrinsics.cy

        var points: [SIMD3<Float>] = []
        // Estimate capacity: ~25% valid points after filtering, divided by downsample factor squared
        let estimatedCapacity = (width * height) / (4 * downsampleFactor * downsampleFactor)
        points.reserveCapacity(estimatedCapacity)

        // Track filtered points for quality monitoring (ADR-004)
        var totalPixelsProcessed = 0
        var filteredOutCount = 0

        // Process with downsampling
        let step = max(1, downsampleFactor)
        for v in stride(from: 0, to: height, by: step) {
            // Bounds check for row (M3 fix)
            guard v < depthData.count && depthData[v].count >= width else { continue }

            for u in stride(from: 0, to: width, by: step) {
                // Bounds check for column (M3 fix)
                guard u < depthData[v].count else { continue }

                totalPixelsProcessed += 1
                let depth = depthData[v][u]

                // Filter invalid depths (ADR-004)
                guard depth >= Self.minValidDepth && depth <= Self.maxValidDepth && !depth.isNaN else {
                    filteredOutCount += 1
                    continue
                }

                // Unproject to camera space
                let x = (Float(u) - cx) * depth / fx
                let y = (Float(v) - cy) * depth / fy
                let z = depth

                // Transform to world space
                let cameraPoint = SIMD4<Float>(x, y, z, 1.0)
                let worldPoint = transform * cameraPoint

                points.append(SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z))
            }
        }

        // Log filtered point percentage for quality monitoring (ADR-004)
        if totalPixelsProcessed > 0 {
            let filteredPercentage = Double(filteredOutCount) / Double(totalPixelsProcessed) * 100.0
            logger.debug("CPU point cloud: \(points.count) valid points, \(filteredOutCount)/\(totalPixelsProcessed) filtered (\(String(format: "%.1f", filteredPercentage))%)")
        }

        return AIPointCloud(points: points, colors: nil, normals: nil, metalBuffer: nil, pointCount: points.count)
    }

    // MARK: - World Transform

    /// Transforms points from camera space to world space using the pose transform.
    ///
    /// - Parameters:
    ///   - points: Array of camera-space points
    ///   - pose: Camera pose with transform matrix
    /// - Returns: Array of world-space points
    func transformToWorldSpace(points: [SIMD3<Float>], pose: AIPose) -> [SIMD3<Float>] {
        let transform = pose.transform

        return points.map { point in
            let cameraPoint = SIMD4<Float>(point.x, point.y, point.z, 1.0)
            let worldPoint = transform * cameraPoint
            return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        }
    }

    // MARK: - Downsampling

    /// Downsamples a point cloud by selecting every nth point.
    ///
    /// - Parameters:
    ///   - cloud: Point cloud to downsample
    ///   - factor: Downsample factor (2 = keep every other point)
    /// - Returns: Downsampled point cloud
    func downsamplePointCloud(_ cloud: AIPointCloud, factor: Int) -> AIPointCloud {
        guard factor > 1 else { return cloud }

        var points = cloud.points
        if points.isEmpty, let buffer = cloud.metalBuffer {
            // Convert from metal buffer if needed
            let count = cloud.count
            let pointer = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: count)
            points = Array(UnsafeBufferPointer(start: pointer, count: count))
        }

        // Simple uniform downsampling
        let downsampledPoints = stride(from: 0, to: points.count, by: factor).map { points[$0] }

        // Downsample colors and normals if present
        let downsampledColors: [SIMD3<Float>]? = cloud.colors.map { colors in
            stride(from: 0, to: colors.count, by: factor).map { colors[$0] }
        }

        let downsampledNormals: [SIMD3<Float>]? = cloud.normals.map { normals in
            stride(from: 0, to: normals.count, by: factor).map { normals[$0] }
        }

        return AIPointCloud(
            points: downsampledPoints,
            colors: downsampledColors,
            normals: downsampledNormals,
            metalBuffer: nil,
            pointCount: downsampledPoints.count
        )
    }
}
