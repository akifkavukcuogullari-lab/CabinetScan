//
//  AIPhotoCapture.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import AVFoundation
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

/// Service for capturing high-resolution photos with ARKit pose data.
/// Per Story 2.5 - Task 3
///
/// **Usage:**
/// 1. Create with AVCaptureSession and AIARSessionManager
/// 2. Call `capturePhoto()` to capture a photo
/// 3. Photo is automatically saved to disk and returned with pose
class AIPhotoCapture: NSObject {

    // MARK: - Properties

    /// Photo output for capturing still images
    private let photoOutput = AVCapturePhotoOutput()

    /// AR session manager for pose data
    private weak var sessionManager: AIARSessionManager?

    /// Capture session reference
    private weak var captureSession: AVCaptureSession?

    /// Whether a capture is in progress
    private var captureInProgress = false

    /// Continuation for async capture with timeout protection
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    /// Timeout for photo capture (5 seconds)
    private let captureTimeout: TimeInterval = 5.0

    /// Timer for capture timeout
    private var captureTimeoutTask: Task<Void, Never>?

    /// Photo settings for high-quality capture
    private var photoSettings: AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        // Enable high resolution if available
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }
        return settings
    }

    // MARK: - Initialization

    /// Initialize with capture session and AR session manager
    /// - Parameters:
    ///   - captureSession: The AVCaptureSession to add photo output to
    ///   - sessionManager: The AR session manager for pose data
    init(captureSession: AVCaptureSession, sessionManager: AIARSessionManager) {
        self.captureSession = captureSession
        self.sessionManager = sessionManager
        super.init()

        configurePhotoOutput(session: captureSession)
        print("[AIPhotoCapture] Initialized with session and AR manager")
    }

    // MARK: - Configuration

    /// Configure photo output on the capture session
    private func configurePhotoOutput(session: AVCaptureSession) {
        // Check if we can add the output
        guard session.canAddOutput(photoOutput) else {
            print("[AIPhotoCapture] Cannot add photo output to session")
            return
        }

        session.beginConfiguration()

        // Configure for high quality
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Add output
        session.addOutput(photoOutput)

        session.commitConfiguration()

        print("[AIPhotoCapture] Photo output configured - high resolution enabled")
    }

    // MARK: - Public Methods

    /// Capture a high-resolution photo with current ARKit pose
    /// - Returns: PhotoCaptureResult with URL, image, thumbnail, and pose
    /// - Throws: PhotoCaptureError if capture fails
    func capturePhoto() async throws -> PhotoCaptureResult {
        // Check if capture session is running
        guard let session = captureSession, session.isRunning else {
            throw PhotoCaptureError.sessionNotRunning
        }

        // Check if capture is already in progress
        guard !captureInProgress else {
            throw PhotoCaptureError.captureInProgress
        }

        captureInProgress = true
        defer { captureInProgress = false }

        // Get pose at capture time (before waiting for photo)
        let pose = sessionManager?.getCurrentPose()
        let captureTimestamp = Date().timeIntervalSince1970

        // Capture photo using continuation with timeout protection
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            self.captureContinuation = continuation

            // Set up timeout to prevent orphaned continuations
            self.captureTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.captureTimeout ?? 5.0) * 1_000_000_000))
                await MainActor.run {
                    if let cont = self?.captureContinuation {
                        self?.captureContinuation = nil
                        cont.resume(throwing: PhotoCaptureError.captureTimedOut)
                    }
                }
            }

            // Capture on main thread (AVCapturePhotoOutput requirement)
            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(with: self.photoSettings, delegate: self)
            }
        }

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

    /// Remove photo output from session
    func cleanup() {
        guard let session = captureSession else { return }

        session.beginConfiguration()
        session.removeOutput(photoOutput)
        session.commitConfiguration()

        print("[AIPhotoCapture] Photo output removed from session")
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension AIPhotoCapture: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Cancel timeout task since we received a response
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil

        // Handle error
        if let error = error {
            captureContinuation?.resume(throwing: error)
            captureContinuation = nil
            return
        }

        // Get image data
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            captureContinuation?.resume(throwing: PhotoCaptureError.noImageData)
            captureContinuation = nil
            return
        }

        // Resume with image
        captureContinuation?.resume(returning: image)
        captureContinuation = nil
    }
}
