//
//  AIPhotoCapture.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//  Rewritten to capture photos from ARFrame.capturedImage.
//

import ARKit
import UIKit

// MARK: - Photo Capture Errors

/// Errors that can occur during photo capture
enum PhotoCaptureError: LocalizedError {
    case sessionNotRunning
    case noPoseAvailable
    case captureInProgress
    case compressionFailed
    case saveFailed(Error)
    case noImageData
    case captureTimedOut

    var errorDescription: String? {
        switch self {
        case .sessionNotRunning:
            return "Camera session is not running"
        case .noPoseAvailable:
            return "Could not get camera pose"
        case .captureInProgress:
            return "A capture is already in progress"
        case .compressionFailed:
            return "Failed to compress image"
        case .saveFailed(let error):
            return "Failed to save photo: \(error.localizedDescription)"
        case .noImageData:
            return "No image data captured"
        case .captureTimedOut:
            return "Photo capture timed out"
        }
    }
}

// MARK: - Photo Capture Result

/// Result of a photo capture including both URL and in-memory image
struct PhotoCaptureResult {
    /// URL where the photo was saved
    let url: URL

    /// In-memory UIImage for immediate display
    let image: UIImage

    /// Thumbnail for strip display (200x200)
    let thumbnail: UIImage

    /// Camera pose at capture time (may be nil if tracking was lost)
    let pose: AIPose?

    /// Timestamp of capture
    let timestamp: TimeInterval
}

// MARK: - AI Photo Capture Service

/// Service for capturing high-resolution photos from ARFrame pixel buffers.
/// Replaces the AVCapturePhotoOutput-based capture with synchronous ARFrame snapshots.
///
/// **Usage:**
/// 1. Create with AIARSessionManager
/// 2. Call `capturePhoto()` to grab current ARFrame and convert to image
/// 3. Photo is automatically saved to disk and returned with pose
class AIPhotoCapture: NSObject {

    // MARK: - Properties

    /// AR session manager for session and pose data
    private weak var sessionManager: AIARSessionManager?

    /// Whether a capture is in progress
    private var captureInProgress = false

    // MARK: - Initialization

    /// Initialize with AR session manager
    /// - Parameter sessionManager: The AR session manager for frame and pose data
    init(sessionManager: AIARSessionManager) {
        self.sessionManager = sessionManager
        super.init()
        print("[AIPhotoCapture] Initialized with AR session manager")
    }

    // MARK: - Public Methods

    /// Capture a high-resolution photo from the current ARFrame
    /// - Returns: PhotoCaptureResult with URL, image, thumbnail, and pose
    /// - Throws: PhotoCaptureError if capture fails
    func capturePhoto() async throws -> PhotoCaptureResult {
        guard let manager = sessionManager else {
            throw PhotoCaptureError.sessionNotRunning
        }

        guard !captureInProgress else {
            throw PhotoCaptureError.captureInProgress
        }

        captureInProgress = true
        defer { captureInProgress = false }

        // Get current frame from AR session
        guard let frame = manager.arSession.currentFrame else {
            throw PhotoCaptureError.noImageData
        }

        // Get pose at capture time
        let pose = manager.getCurrentPose()
        let captureTimestamp = Date().timeIntervalSince1970

        // Convert CVPixelBuffer → UIImage
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw PhotoCaptureError.noImageData
        }

        // Apply .right orientation for portrait (ARKit frames are landscape)
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Save to disk
        let url = try savePhotoToDisk(image)

        // Generate thumbnail
        let thumbnail = generateThumbnail(from: image, size: CGSize(width: 200, height: 200))

        print("[AIPhotoCapture] Photo captured - URL: \(url.lastPathComponent), pose available: \(pose != nil)")

        return PhotoCaptureResult(
            url: url,
            image: image,
            thumbnail: thumbnail,
            pose: pose,
            timestamp: captureTimestamp
        )
    }

    // MARK: - Disk Operations

    /// Save photo to temporary directory
    /// - Parameter image: The image to save
    /// - Returns: URL of saved file
    private func savePhotoToDisk(_ image: UIImage) throws -> URL {
        // Use app's temporary directory for photos
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai_photos", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Generate unique filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid = UUID().uuidString.prefix(8)
        let filename = "ai_photo_\(timestamp)_\(uuid).jpg"
        let url = tempDir.appendingPathComponent(filename)

        // Compress to JPEG (0.9 quality balances size vs quality)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw PhotoCaptureError.compressionFailed
        }

        // Write to disk
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PhotoCaptureError.saveFailed(error)
        }

        print("[AIPhotoCapture] Photo saved to disk: \(url.lastPathComponent) (\(data.count / 1024)KB)")
        return url
    }

    /// Generate thumbnail from image with aspect-fill cropping
    /// Maintains aspect ratio by cropping to center square first
    private func generateThumbnail(from image: UIImage, size: CGSize) -> UIImage {
        // Calculate the square crop rect from center of original image
        let originalSize = image.size
        let minDimension = min(originalSize.width, originalSize.height)
        let cropRect = CGRect(
            x: (originalSize.width - minDimension) / 2,
            y: (originalSize.height - minDimension) / 2,
            width: minDimension,
            height: minDimension
        )

        // Crop to center square
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            // Fallback: just scale without preserving aspect
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

        // Scale to target size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Cleanup

    /// No-op — no AVCaptureSession resources to clean up
    func cleanup() {
        print("[AIPhotoCapture] Cleanup (no-op)")
    }
}
