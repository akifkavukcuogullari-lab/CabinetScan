//
//  AIVideoCapture.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//  Rewritten to use AVAssetWriter with ARFrame pixel buffers.
//

import Foundation
import AVFoundation
import ARKit
import CoreImage
import Metal
import UIKit

// MARK: - AI Video Capture Errors

/// Errors that can occur during video capture
enum AIVideoCaptureError: LocalizedError {
    case cameraNotAvailable
    case sessionConfigurationFailed
    case recordingNotPrepared
    case recordingFailed(String)
    case recordingAlreadyInProgress
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available"
        case .sessionConfigurationFailed:
            return "Failed to configure camera session"
        case .recordingNotPrepared:
            return "Recording has not been prepared"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .recordingAlreadyInProgress:
            return "Recording is already in progress"
        case .noActiveRecording:
            return "No active recording to stop"
        }
    }
}

// MARK: - AI Video Capture Frame Delegate

/// Protocol for receiving video frame pixel buffers for quality analysis
protocol AIVideoCaptureFrameDelegate: AnyObject {
    func videoCapture(_ capture: AIVideoCapture, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval)
}

// MARK: - AI Video Capture

/// Service for capturing video during AI flow using AVAssetWriter.
/// Receives ARFrame pixel buffers via AIARFrameDelegate, encodes to H.264 1080p.
/// Based on VideoRecorder.swift patterns from the LiDAR flow.
///
/// **Usage:**
/// 1. Call `prepare()` to set up AVAssetWriter pipeline
/// 2. Set as sessionManager.frameDelegate to start receiving frames
/// 3. Call `startRecording()` to begin encoding
/// 4. Use `setZoom(_:)` to change digital zoom level during recording
/// 5. Call `stopRecording()` to finalize and get video URL
/// 6. Call `cancelRecording()` to discard without saving
///
/// **Threading:**
/// - Frame delivery on ARKit delegate queue (serial)
/// - Pixel buffer copy synchronous on delivery thread
/// - Encoding async on dedicated processingQueue
/// - All public methods safe to call from main thread
class AIVideoCapture: NSObject, AIARFrameDelegate {

    // MARK: - AVAssetWriter Pipeline

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// Dedicated queue for async frame encoding
    private let processingQueue = DispatchQueue(label: "com.cabinetscan.aiflow.videowriter", qos: .userInitiated)

    // MARK: - Recording State

    /// Whether the writer is prepared
    private var isPrepared = false

    /// Whether currently recording
    private var isRecording = false

    /// Output URL for current recording
    private var outputURL: URL?

    /// Frame counter for logging
    private var nextFrameNumber: Int64 = 0

    /// ARKit timestamp of the first recorded frame (used as time-zero for presentation times)
    private var firstFrameTimestamp: TimeInterval = 0

    /// Last recorded frame time for rate limiting
    private var lastRecordedFrameTime: TimeInterval = 0

    /// Whether startSession has been called on the asset writer
    private var sessionStarted = false

    // MARK: - Frame Delegate

    /// Delegate for receiving pixel buffers for quality analysis
    weak var frameDelegate: AIVideoCaptureFrameDelegate?

    // MARK: - Video Settings

    /// Target video resolution (1080p portrait)
    private let targetWidth = 1080
    private let targetHeight = 1920

    /// Target frame rate
    private let targetFrameRate: Double = 30.0

    /// Minimum frame interval for rate limiting
    private var minFrameInterval: TimeInterval { 1.0 / targetFrameRate }

    // MARK: - Zoom

    /// Current digital zoom factor (applied during resizePixelBuffer)
    private var currentZoomFactor: CGFloat = 1.0

    /// Minimum zoom
    var minZoomFactor: CGFloat { 1.0 }

    /// Maximum zoom (2x digital)
    var maxZoomFactor: CGFloat { 2.0 }

    // MARK: - CIContext (reusable, Metal-backed)

    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    // MARK: - Initialization

    override init() {
        super.init()
    }

    deinit {
        assetWriter?.cancelWriting()
    }

    // MARK: - Public Methods

    /// Prepare the AVAssetWriter pipeline for recording
    func prepare() throws {
        guard !isPrepared else {
            print("[AIVideoCapture] Already prepared")
            return
        }

        // Create output URL
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let url = tempDir.appendingPathComponent("ai_capture_\(timestamp)_\(randomId).mp4")

        // Remove any existing file
        try? FileManager.default.removeItem(at: url)

        outputURL = url

        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // Video settings: H.264, 1080p portrait, 8Mbps (same as VideoRecorder)
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Pixel buffer adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if assetWriter!.canAdd(videoInput!) {
            assetWriter!.add(videoInput!)
        } else {
            throw AIVideoCaptureError.sessionConfigurationFailed
        }

        isPrepared = true
        print("[AIVideoCapture] Prepared AVAssetWriter at \(targetWidth)x\(targetHeight) @ \(Int(targetFrameRate))fps")
    }

    /// Start recording — begins accepting frames for encoding
    func startRecording() async throws {
        guard isPrepared else {
            throw AIVideoCaptureError.recordingNotPrepared
        }

        guard !isRecording else {
            throw AIVideoCaptureError.recordingAlreadyInProgress
        }

        guard let writer = assetWriter, writer.status == .unknown else {
            throw AIVideoCaptureError.sessionConfigurationFailed
        }

        writer.startWriting()
        isRecording = true
        nextFrameNumber = 0
        firstFrameTimestamp = 0
        lastRecordedFrameTime = 0
        sessionStarted = false

        print("[AIVideoCapture] Recording started")
    }

    /// Stop recording and return the video URL
    func stopRecording() async throws -> URL {
        guard isRecording else {
            throw AIVideoCaptureError.noActiveRecording
        }

        guard let writer = assetWriter, let url = outputURL else {
            throw AIVideoCaptureError.recordingFailed("No asset writer available")
        }

        isRecording = false

        // Finalize on processing queue
        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async {
                self.videoInput?.markAsFinished()

                writer.finishWriting {
                    if writer.status == .completed {
                        print("[AIVideoCapture] Recording finalized: \(self.nextFrameNumber) frames written")
                        continuation.resume(returning: url)
                    } else {
                        let error = writer.error ?? AIVideoCaptureError.recordingFailed("Unknown write error")
                        print("[AIVideoCapture] Recording failed: \(error.localizedDescription)")
                        continuation.resume(throwing: AIVideoCaptureError.recordingFailed(error.localizedDescription))
                    }
                }
            }
        }
    }

    /// Cancel recording without saving
    func cancelRecording() {
        isRecording = false
        assetWriter?.cancelWriting()

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
            outputURL = nil
        }

        print("[AIVideoCapture] Recording cancelled")
    }

    /// Set digital zoom level
    func setZoom(_ zoomFactor: CGFloat) {
        let clamped = min(max(zoomFactor, minZoomFactor), maxZoomFactor)
        currentZoomFactor = clamped
        print("[AIVideoCapture] Zoom set to: \(clamped)")
    }

    // MARK: - AIARFrameDelegate

    func arSessionManager(_ manager: AIARSessionManager, didUpdateFrame frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp

        // Always forward to frame delegate for quality analysis (even when not recording)
        frameDelegate?.videoCapture(self, didOutputPixelBuffer: pixelBuffer, timestamp: timestamp)

        // Only encode frames when recording
        guard isRecording,
              let videoInput = videoInput,
              let adaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }

        // Rate-limit to target frame rate
        if timestamp - lastRecordedFrameTime < minFrameInterval {
            return
        }
        lastRecordedFrameTime = timestamp

        // CRITICAL: Copy/resize pixel buffer synchronously while ARKit buffer is valid
        guard let copiedBuffer = resizePixelBuffer(pixelBuffer) else {
            return
        }

        // Capture raw timestamp — presentation time computed on processing queue
        let capturedTimestamp = timestamp

        // Append asynchronously on processing queue
        processingQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }

            // Start session on first frame — all timing logic on same queue
            // to avoid race where multiple frames compute presentationTime = 0
            if !self.sessionStarted {
                self.firstFrameTimestamp = capturedTimestamp
                self.assetWriter?.startSession(atSourceTime: .zero)
                self.sessionStarted = true
            }

            let presentationTime = CMTime(seconds: capturedTimestamp - self.firstFrameTimestamp, preferredTimescale: 600)

            self.nextFrameNumber += 1

            if !adaptor.append(copiedBuffer, withPresentationTime: presentationTime) {
                if let writer = self.assetWriter {
                    print("[AIVideoCapture] Append failed - status: \(writer.status.rawValue), error: \(String(describing: writer.error))")
                }
            }
        }
    }

    // MARK: - Pixel Buffer Processing

    /// Resize, rotate, and copy pixel buffer (GPU-accelerated via CIContext + Metal).
    /// Creates a NEW buffer that we own — the original ARKit buffer can be safely recycled.
    /// Rotates 90° clockwise for portrait orientation and applies digital zoom crop.
    private func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Create output pixel buffer
        var newPixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = newPixelBuffer else {
            print("[AIVideoCapture] Failed to create pixel buffer: \(status)")
            return nil
        }

        // Create CIImage from source
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply digital zoom crop (before rotation) if zoom > 1.0
        if currentZoomFactor > 1.0 {
            let cropWidth = CGFloat(sourceWidth) / currentZoomFactor
            let cropHeight = CGFloat(sourceHeight) / currentZoomFactor
            let cropX = (CGFloat(sourceWidth) - cropWidth) / 2
            let cropY = (CGFloat(sourceHeight) - cropHeight) / 2
            ciImage = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
            // Reset origin after crop
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
        }

        let effectiveWidth = currentZoomFactor > 1.0 ? CGFloat(sourceWidth) / currentZoomFactor : CGFloat(sourceWidth)
        let effectiveHeight = currentZoomFactor > 1.0 ? CGFloat(sourceHeight) / currentZoomFactor : CGFloat(sourceHeight)

        // Rotate 90° clockwise for portrait (ARKit frames are landscape)
        ciImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: 0, y: effectiveWidth))

        // After rotation: dimensions are swapped
        let rotatedWidth = effectiveHeight
        let rotatedHeight = effectiveWidth

        // Scale to fit target dimensions
        let scaleX = CGFloat(targetWidth) / rotatedWidth
        let scaleY = CGFloat(targetHeight) / rotatedHeight
        let scale = min(scaleX, scaleY)

        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center in target buffer
        let scaledWidth = rotatedWidth * scale
        let scaledHeight = rotatedHeight * scale
        let offsetX = (CGFloat(targetWidth) - scaledWidth) / 2
        let offsetY = (CGFloat(targetHeight) - scaledHeight) / 2
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Render to output buffer
        ciContext.render(
            ciImage,
            to: outputBuffer,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return outputBuffer
    }
}
