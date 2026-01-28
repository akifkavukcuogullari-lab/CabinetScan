//
//  FrameExtractor.swift
//  cabinetscan
//
//  Created for Story 3.2: Frame Extraction and Depth Estimation
//

import Foundation
import AVFoundation
import CoreVideo
import CoreImage
import os.log

// MARK: - Extracted Frame Model

/// A frame extracted from video for depth processing.
/// Note: Not Sendable because CVPixelBuffer is not thread-safe.
struct ExtractedFrame {
    /// Pixel buffer containing the frame image
    let pixelBuffer: CVPixelBuffer

    /// Timestamp relative to video start (in seconds)
    let timestamp: TimeInterval

    /// Original frame width before any preprocessing
    let originalWidth: Int

    /// Original frame height before any preprocessing
    let originalHeight: Int
}

// MARK: - Frame Extraction Errors

enum FrameExtractionError: LocalizedError {
    case videoNotFound(URL)
    case pixelBufferCreationFailed
    case frameExtractionFailed(TimeInterval)
    case invalidVideoAsset
    case cancelled

    var errorDescription: String? {
        switch self {
        case .videoNotFound(let url):
            return "Video file not found at \(url.path)"
        case .pixelBufferCreationFailed:
            return "Failed to create pixel buffer for frame"
        case .frameExtractionFailed(let time):
            return "Failed to extract frame at \(time)s"
        case .invalidVideoAsset:
            return "Invalid video asset - could not load duration"
        case .cancelled:
            return "Frame extraction was cancelled"
        }
    }
}

// MARK: - Frame Extractor

/// Extracts frames from video files at configurable frame rates.
/// Optimized for AI processing pipeline with support for cancellation and progress reporting.
///
/// **Usage:**
/// ```swift
/// let extractor = FrameExtractor()
/// let frames = try await extractor.extractFrames(from: videoURL)
/// ```
final class FrameExtractor {

    // MARK: - Constants

    /// Default extraction rate: 2 frames per second (every 0.5 seconds)
    static let defaultFrameRate: Double = 2.0

    /// Timescale for precise timing (600 = common video timescale)
    private static let timescale: CMTimeScale = 600

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.cabinetscan", category: "FrameExtractor")

    /// Current extraction progress (0.0 to 1.0)
    private(set) var progress: Double = 0.0

    /// Current frame index being extracted
    private(set) var currentFrameIndex: Int = 0

    /// Total number of frames to extract
    private(set) var totalFrameCount: Int = 0

    // MARK: - Extraction

    /// Extracts frames from a video file at the specified frame rate.
    ///
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - frameRate: Frames per second to extract (default: 2.0 FPS)
    /// - Returns: Array of extracted frames with metadata
    /// - Throws: FrameExtractionError if extraction fails
    func extractFrames(
        from videoURL: URL,
        frameRate: Double = FrameExtractor.defaultFrameRate
    ) async throws -> [ExtractedFrame] {
        logger.info("Starting frame extraction from: \(videoURL.lastPathComponent)")

        // Verify video file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw FrameExtractionError.videoNotFound(videoURL)
        }

        // Create asset and load duration
        let asset = AVAsset(url: videoURL)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            logger.error("Failed to load video duration: \(error.localizedDescription)")
            throw FrameExtractionError.invalidVideoAsset
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0, durationSeconds.isFinite else {
            throw FrameExtractionError.invalidVideoAsset
        }

        logger.info("Video duration: \(String(format: "%.2f", durationSeconds))s")

        // Configure image generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Calculate frame times at specified frame rate
        let frameInterval = 1.0 / frameRate
        var frameTimes: [CMTime] = []
        var currentTime: Double = 0

        while currentTime < durationSeconds {
            frameTimes.append(CMTime(seconds: currentTime, preferredTimescale: Self.timescale))
            currentTime += frameInterval
        }

        totalFrameCount = frameTimes.count
        currentFrameIndex = 0
        progress = 0.0

        logger.info("Extracting \(self.totalFrameCount) frames at \(frameRate) FPS")

        // Extract frames
        var frames: [ExtractedFrame] = []
        frames.reserveCapacity(totalFrameCount)

        let startTime = Date()

        for (index, requestedTime) in frameTimes.enumerated() {
            // Check for cancellation
            try Task.checkCancellation()

            do {
                let (cgImage, actualTime) = try await generator.image(at: requestedTime)

                // Convert CGImage to CVPixelBuffer
                let pixelBuffer = try convertCGImageToPixelBuffer(cgImage)

                let frame = ExtractedFrame(
                    pixelBuffer: pixelBuffer,
                    timestamp: CMTimeGetSeconds(actualTime),
                    originalWidth: cgImage.width,
                    originalHeight: cgImage.height
                )

                frames.append(frame)

                // Update progress
                currentFrameIndex = index + 1
                progress = Double(currentFrameIndex) / Double(totalFrameCount)

            } catch is CancellationError {
                logger.info("Frame extraction cancelled at frame \(index)")
                throw FrameExtractionError.cancelled
            } catch {
                // Log but don't fail on individual frame errors
                logger.warning("Failed to extract frame at \(CMTimeGetSeconds(requestedTime))s: \(error.localizedDescription)")
                // Continue to next frame
            }
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        logger.info("Extracted \(frames.count) frames in \(String(format: "%.2f", elapsedTime))s")

        return frames
    }

    // MARK: - Pixel Buffer Conversion

    /// Converts a CGImage to CVPixelBuffer for processing.
    ///
    /// - Parameter image: The source CGImage
    /// - Returns: A CVPixelBuffer containing the image data
    /// - Throws: FrameExtractionError.pixelBufferCreationFailed if conversion fails
    private func convertCGImageToPixelBuffer(_ image: CGImage) throws -> CVPixelBuffer {
        let width = image.width
        let height = image.height

        // Create pixel buffer attributes
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw FrameExtractionError.pixelBufferCreationFailed
        }

        // Lock buffer for writing
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        // Create graphics context and draw image
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw FrameExtractionError.pixelBufferCreationFailed
        }

        // Draw image into buffer (flip Y coordinate)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
