//
//  DepthEstimator.swift
//  cabinetscan
//
//  Created for Story 3.2: Frame Extraction and Depth Estimation
//

import Foundation
import Combine
import CoreVideo
import CoreGraphics
import ImageIO
import simd
import os.log

// MARK: - Depth Estimation Errors

enum DepthEstimationError: LocalizedError {
    case noVideoFile
    case modelNotLoaded
    case cancelled
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoFile:
            return "No video file in capture session data"
        case .modelNotLoaded:
            return "Depth model is not loaded"
        case .cancelled:
            return "Depth estimation was cancelled"
        case .processingFailed(let reason):
            return "Depth processing failed: \(reason)"
        }
    }
}

// MARK: - Timestamped Pose

/// Pose data with timestamp for synchronization
struct TimestampedPose {
    let timestamp: TimeInterval
    let pose: AIPose
}

// MARK: - Depth Estimation Result

/// Result of depth estimation containing all depth frames
struct DepthEstimationResult {
    /// Depth frames from video
    let videoDepthFrames: [AIDepthFrame]

    /// Depth frames from photos (higher confidence)
    let photoDepthFrames: [AIDepthFrame]

    /// All depth frames combined (video + photo)
    var allDepthFrames: [AIDepthFrame] {
        videoDepthFrames + photoDepthFrames
    }

    /// Total number of frames processed
    var totalFrameCount: Int {
        videoDepthFrames.count + photoDepthFrames.count
    }
}

// MARK: - Depth Estimator

/// Orchestrates depth estimation on video frames and photos.
/// Coordinates frame extraction, preprocessing, model inference, and pose synchronization.
///
/// **Critical Architecture Notes (Story 3.1 ADR):**
/// - Processes frames SEQUENTIALLY (not in parallel) to avoid Neural Engine contention
/// - Uses autoreleasepool for batch processing to prevent memory growth
/// - Supports cancellation with partial results
///
/// **Usage:**
/// ```swift
/// let estimator = DepthEstimator(modelManager: DepthModelManager.shared)
/// let result = try await estimator.estimateDepth(from: sessionData, poses: poses)
/// ```
@MainActor
final class DepthEstimator: ObservableObject {

    // MARK: - Constants

    /// Batch size for autoreleasepool processing
    private static let batchSize = 10

    /// Memory warning threshold (1.2 GB)
    private static let memoryWarningThreshold: UInt64 = 1_200_000_000

    /// Maximum resolution for photo depth estimation
    private static let maxPhotoResolution = 1024

    // MARK: - Published Properties

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current frame index being processed
    @Published private(set) var currentFrameIndex: Int = 0

    /// Total number of frames to process
    @Published private(set) var totalFrameCount: Int = 0

    /// Whether estimation is currently running
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Properties

    private let modelManager: DepthModelManager
    private let frameExtractor: FrameExtractor
    private let preprocessor: FramePreprocessor
    private let logger = Logger(subsystem: "com.cabinetscan", category: "DepthEstimator")

    // MARK: - Initialization

    /// Creates a depth estimator with the specified model manager.
    ///
    /// - Parameter modelManager: The model manager for depth inference
    init(modelManager: DepthModelManager = .shared) {
        self.modelManager = modelManager
        self.frameExtractor = FrameExtractor()
        self.preprocessor = FramePreprocessor()
    }

    // MARK: - Main Estimation Entry Point

    /// Estimates depth for all frames in a capture session.
    ///
    /// - Parameters:
    ///   - sessionData: The capture session data containing video and photos
    ///   - poses: Array of timestamped poses for synchronization
    /// - Returns: Depth estimation result with all depth frames
    /// - Throws: DepthEstimationError if estimation fails
    func estimateDepth(
        from sessionData: AICaptureSessionData,
        poses: [TimestampedPose]
    ) async throws -> DepthEstimationResult {
        guard let videoURL = sessionData.videoURL else {
            throw DepthEstimationError.noVideoFile
        }

        logger.info("Starting depth estimation for session")
        isProcessing = true
        progress = 0.0

        defer {
            isProcessing = false
        }

        // Ensure models are loaded
        if await !modelManager.isLoaded {
            logger.info("Loading depth models...")
            try await modelManager.loadModelsWithRetry()
        }

        // Extract frames from video
        logger.info("Extracting frames from video...")
        let extractedFrames = try await frameExtractor.extractFrames(from: videoURL)
        logger.info("Extracted \(extractedFrames.count) frames")

        // Calculate total frame count (video + photos)
        totalFrameCount = extractedFrames.count + sessionData.photos.count

        // Process video frames
        let videoDepthFrames = try await processVideoFrames(extractedFrames, poses: poses)

        // Process photos at higher resolution
        let photoDepthFrames = try await processPhotos(sessionData.photos)

        // Schedule model unload after delay
        await modelManager.scheduleUnload()

        let result = DepthEstimationResult(
            videoDepthFrames: videoDepthFrames,
            photoDepthFrames: photoDepthFrames
        )

        logger.info("Depth estimation complete: \(result.totalFrameCount) frames processed")
        progress = 1.0

        return result
    }

    // MARK: - Video Frame Processing (Task 4)

    /// Processes video frames for depth estimation.
    /// Uses batched processing with memory management between batches.
    ///
    /// **Note:** autoreleasepool is used only around synchronous operations (preprocessing).
    /// Async operations (model inference) cannot be wrapped in autoreleasepool as it
    /// may suspend and resume unpredictably.
    ///
    /// - Parameters:
    ///   - frames: Extracted video frames
    ///   - poses: Timestamped poses for synchronization
    /// - Returns: Array of depth frames
    private func processVideoFrames(
        _ frames: [ExtractedFrame],
        poses: [TimestampedPose]
    ) async throws -> [AIDepthFrame] {
        logger.info("Processing \(frames.count) video frames...")

        var results: [AIDepthFrame] = []
        results.reserveCapacity(frames.count)

        let depthWrapper = try await modelManager.getDepthWrapper()

        // Process in batches
        for batchStart in stride(from: 0, to: frames.count, by: Self.batchSize) {
            // Check cancellation at batch boundary
            try Task.checkCancellation()

            let batchEnd = min(batchStart + Self.batchSize, frames.count)

            for i in batchStart..<batchEnd {
                // Check cancellation between frames
                try Task.checkCancellation()

                let frame = frames[i]

                do {
                    // Preprocess frame synchronously within autoreleasepool
                    let processedBuffer: CVPixelBuffer = try autoreleasepool {
                        try preprocessor.preprocess(frame.pixelBuffer)
                    }

                    // Run depth inference (async - cannot be in autoreleasepool)
                    let depthMap = try await depthWrapper.predict(image: processedBuffer)

                    // Post-process synchronously within autoreleasepool
                    let depthFrame: AIDepthFrame = autoreleasepool {
                        // Normalize depth values
                        let normalizedDepth = depthWrapper.normalizeDepth(depthMap)

                        // Convert to 2D float array
                        let depthData = depthWrapper.depthArrayToFloat2D(normalizedDepth)

                        // Get synchronized pose
                        let pose = getPoseForTimestamp(frame.timestamp, poses: poses)

                        // Create depth frame
                        return AIDepthFrame(
                            depthData: depthData,
                            width: FramePreprocessor.targetWidth,
                            height: FramePreprocessor.targetHeight,
                            timestamp: frame.timestamp,
                            pose: pose,
                            confidence: .medium  // Video frames = medium confidence
                        )
                    }

                    results.append(depthFrame)

                } catch is CancellationError {
                    throw DepthEstimationError.cancelled
                } catch {
                    // Log but continue on individual frame errors
                    logger.warning("Failed to process frame at \(frame.timestamp)s: \(error.localizedDescription)")
                }

                // Update progress
                currentFrameIndex = i + 1
                progress = Double(currentFrameIndex) / Double(totalFrameCount)
            }

            // Check memory usage after each batch
            await checkMemoryUsage()
        }

        return results
    }

    // MARK: - Photo Processing (Task 5)

    /// Processes photos for depth estimation at higher resolution.
    /// Photos are processed with high confidence level.
    ///
    /// **Progress tracking note:**
    /// At this point, `currentFrameIndex` equals the number of video frames processed.
    /// We continue incrementing it for photo processing so that progress correctly
    /// reflects (videoFrames + photos) / totalFrameCount.
    ///
    /// - Parameter photos: Array of captured photos
    /// - Returns: Array of depth frames from photos
    private func processPhotos(_ photos: [AICapturedPhoto]) async throws -> [AIDepthFrame] {
        guard !photos.isEmpty else { return [] }

        logger.info("Processing \(photos.count) photos...")

        var results: [AIDepthFrame] = []
        results.reserveCapacity(photos.count)

        let depthWrapper = try await modelManager.getDepthWrapper()

        for photo in photos {
            try Task.checkCancellation()

            do {
                // Load photo as pixel buffer (within autoreleasepool for memory management)
                let pixelBuffer: CVPixelBuffer? = autoreleasepool {
                    loadPhotoAsPixelBuffer(from: photo.url)
                }

                guard let pixelBuffer = pixelBuffer else {
                    logger.warning("Failed to load photo: \(photo.url.lastPathComponent)")
                    continue
                }

                // Determine resolution (use higher res if memory allows)
                let targetSize = await determinePhotoTargetSize()

                // Preprocess photo
                let processedBuffer = try preprocessor.preprocess(pixelBuffer, targetSize: targetSize)

                // Run depth inference
                let depthMap = try await depthWrapper.predict(image: processedBuffer)

                // Post-process within autoreleasepool
                let depthFrame: AIDepthFrame = autoreleasepool {
                    // Normalize depth values
                    let normalizedDepth = depthWrapper.normalizeDepth(depthMap)

                    // Convert to 2D float array
                    let depthData = depthWrapper.depthArrayToFloat2D(normalizedDepth)

                    // Create depth frame with photo pose
                    return AIDepthFrame(
                        depthData: depthData,
                        width: Int(targetSize.width),
                        height: Int(targetSize.height),
                        timestamp: photo.timestamp,
                        pose: photo.pose,
                        confidence: .high  // Photos = high confidence
                    )
                }

                results.append(depthFrame)

                // Update progress: currentFrameIndex continues from video frame count
                currentFrameIndex += 1
                progress = Double(currentFrameIndex) / Double(totalFrameCount)

            } catch {
                logger.warning("Failed to process photo: \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - Pose Synchronization (Task 6)

    /// Gets the pose for a given timestamp using binary search and interpolation.
    ///
    /// - Parameters:
    ///   - timestamp: The target timestamp
    ///   - poses: Array of timestamped poses (must be sorted by timestamp)
    /// - Returns: The interpolated or nearest pose
    func getPoseForTimestamp(_ timestamp: TimeInterval, poses: [TimestampedPose]) -> AIPose {
        guard !poses.isEmpty else {
            // Return identity pose if no poses available
            return AIPose(
                transform: matrix_identity_float4x4,
                intrinsics: AICameraIntrinsics(fx: 1000, fy: 1000, cx: 259, cy: 259),
                trackingState: .notAvailable,
                zoomFactor: 1.0
            )
        }

        // Handle edge cases
        if timestamp <= poses.first!.timestamp {
            return poses.first!.pose
        }
        if timestamp >= poses.last!.timestamp {
            return poses.last!.pose
        }

        // Binary search for surrounding poses
        var low = 0
        var high = poses.count - 1

        while low < high - 1 {
            let mid = (low + high) / 2
            if poses[mid].timestamp <= timestamp {
                low = mid
            } else {
                high = mid
            }
        }

        let before = poses[low]
        let after = poses[high]

        // Check for exact match
        if abs(before.timestamp - timestamp) < 0.001 {
            return before.pose
        }
        if abs(after.timestamp - timestamp) < 0.001 {
            return after.pose
        }

        // Interpolate between poses
        return interpolatePose(
            at: timestamp,
            before: (time: before.timestamp, pose: before.pose),
            after: (time: after.timestamp, pose: after.pose)
        )
    }

    /// Interpolates pose between two known poses.
    ///
    /// - Parameters:
    ///   - timestamp: Target timestamp
    ///   - before: Earlier pose with timestamp
    ///   - after: Later pose with timestamp
    /// - Returns: Interpolated pose
    private func interpolatePose(
        at timestamp: TimeInterval,
        before: (time: TimeInterval, pose: AIPose),
        after: (time: TimeInterval, pose: AIPose)
    ) -> AIPose {
        let t = Float((timestamp - before.time) / (after.time - before.time))

        // Linearly interpolate transform matrices
        let transform = simd_float4x4(
            mix(before.pose.transform.columns.0, after.pose.transform.columns.0, t: t),
            mix(before.pose.transform.columns.1, after.pose.transform.columns.1, t: t),
            mix(before.pose.transform.columns.2, after.pose.transform.columns.2, t: t),
            mix(before.pose.transform.columns.3, after.pose.transform.columns.3, t: t)
        )

        // Use intrinsics from nearest pose (intrinsics typically don't change)
        let intrinsics = t < 0.5 ? before.pose.intrinsics : after.pose.intrinsics
        let trackingState = t < 0.5 ? before.pose.trackingState : after.pose.trackingState
        let zoomFactor = before.pose.zoomFactor + CGFloat(t) * (after.pose.zoomFactor - before.pose.zoomFactor)

        return AIPose(
            transform: transform,
            intrinsics: intrinsics,
            trackingState: trackingState,
            zoomFactor: zoomFactor
        )
    }

    // MARK: - Memory Management (Task 8)

    /// Checks current memory usage and logs warnings if high.
    private func checkMemoryUsage() async {
        let memoryUsage = await modelManager.getMemoryUsage()

        if memoryUsage > Self.memoryWarningThreshold {
            logger.warning("Memory usage high: \(memoryUsage / (1024 * 1024))MB")
        }
    }

    // MARK: - Helper Methods

    /// Loads a photo from URL as CVPixelBuffer.
    ///
    /// - Parameter url: Photo file URL
    /// - Returns: CVPixelBuffer or nil if loading fails
    private func loadPhotoAsPixelBuffer(from url: URL) -> CVPixelBuffer? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    /// Determines target size for photo depth estimation based on available memory.
    /// Uses higher resolution (1024x1024) when sufficient memory is available,
    /// falls back to standard size (518x518) otherwise.
    ///
    /// Per AC4: "photos are processed at higher resolution (up to 1024x1024 if memory allows)"
    ///
    /// - Returns: Target size for photo preprocessing
    private func determinePhotoTargetSize() async -> CGSize {
        let currentMemory = await modelManager.getMemoryUsage()
        let highResThreshold: UInt64 = 1_000_000_000  // 1GB - use high res if under this

        if currentMemory < highResThreshold {
            // Memory is comfortable, use higher resolution for better depth accuracy
            return CGSize(width: Self.maxPhotoResolution, height: Self.maxPhotoResolution)
        } else {
            // Memory is constrained, use standard resolution
            logger.info("Memory usage high (\(currentMemory / (1024 * 1024))MB), using standard photo resolution")
            return CGSize(width: FramePreprocessor.targetWidth, height: FramePreprocessor.targetHeight)
        }
    }
}

// MARK: - SIMD Extensions

/// Linear interpolation for SIMD4<Float>
private func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, t: Float) -> SIMD4<Float> {
    return a + (b - a) * t
}

// MARK: - Depth Inference Benchmarking (Story 3.9 Task 3)

extension DepthEstimator {

    /// Benchmark result for depth inference performance.
    struct BenchmarkResult {
        /// Average inference time in milliseconds
        let averageMs: Double

        /// Cold-start (first inference) time in milliseconds
        let coldStartMs: Double

        /// Warm inference times (subsequent) in milliseconds
        let warmInferenceTimes: [Double]

        /// Minimum inference time
        let minMs: Double

        /// Maximum inference time
        let maxMs: Double

        /// Pass/fail status based on NFR1 (<50ms target)
        let status: PassStatus

        /// Warning message if any
        let warning: String?
    }

    /// Benchmarks depth inference performance.
    ///
    /// Runs 10 inference cycles and measures timing to validate NFR1.
    ///
    /// **NFR1:** Depth inference shall complete in under 50ms per frame on iPhone 12.
    ///
    /// - Parameter testBuffer: A CVPixelBuffer to use for testing
    /// - Returns: BenchmarkResult with timing data
    /// - Throws: DepthEstimationError if models not loaded
    func benchmarkDepthInference(using testBuffer: CVPixelBuffer) async throws -> BenchmarkResult {
        // Ensure models are loaded
        if await !modelManager.isLoaded {
            try await modelManager.loadModelsWithRetry()
        }

        let depthWrapper = try await modelManager.getDepthWrapper()
        let iterations = 10

        var times: [Double] = []
        var coldStartMs: Double = 0

        // Run benchmark iterations
        for i in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            _ = try await depthWrapper.predict(image: testBuffer)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            times.append(elapsed)

            if i == 0 {
                coldStartMs = elapsed
            }

            #if DEBUG
            logger.debug("Inference \(i + 1)/\(iterations): \(String(format: "%.1f", elapsed))ms")
            #endif
        }

        // Calculate statistics
        let warmTimes = Array(times.dropFirst())
        let averageMs = warmTimes.reduce(0, +) / Double(warmTimes.count)
        let minMs = times.min() ?? 0
        let maxMs = times.max() ?? 0

        // Determine status based on NFR1 (50ms target)
        let status: PassStatus
        let warning: String?

        if averageMs < 40 {
            status = .pass
            warning = nil
        } else if averageMs < 50 {
            status = .warn
            warning = "Inference time (\(String(format: "%.1f", averageMs))ms) is close to 50ms limit"
        } else {
            status = .fail
            warning = "Inference time (\(String(format: "%.1f", averageMs))ms) exceeds 50ms limit"
        }

        return BenchmarkResult(
            averageMs: averageMs,
            coldStartMs: coldStartMs,
            warmInferenceTimes: warmTimes,
            minMs: minMs,
            maxMs: maxMs,
            status: status,
            warning: warning
        )
    }
}
