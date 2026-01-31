//
//  AIVideoCapture.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import AVFoundation
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

// MARK: - AI Video Capture

/// Protocol for receiving video frame samples for quality analysis
/// Per Story 2.3 - Integration with quality analyzer
protocol AIVideoCaptureFrameDelegate: AnyObject {
    func videoCapture(_ capture: AIVideoCapture, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
}

/// Service for capturing video during AI flow.
/// Uses AVCaptureSession for direct camera capture at 1080p 30fps.
/// Per Story 2.2 - Task 2, Story 2.3 (frame delegate for quality analysis)
///
/// **Usage:**
/// 1. Call `prepare()` to set up capture session
/// 2. Optionally set `frameDelegate` to receive sample buffers for quality analysis
/// 3. Call `startRecording()` to begin recording
/// 4. Use `setZoom(_:)` to change zoom level during recording
/// 5. Call `stopRecording()` to finish and get video URL
/// 6. Call `cancelRecording()` to discard without saving
///
/// **Threading:**
/// - Session operations run on dedicated session queue
/// - Recording delegate callbacks handled appropriately
/// - Frame delegate callbacks on video data output queue
/// - All public methods safe to call from main thread
class AIVideoCapture: NSObject {

    // MARK: - Properties

    /// AVCapture session for camera access
    /// Made internal to allow sharing with photo capture (Story 2.5)
    let captureSession = AVCaptureSession()

    /// Video input from camera
    private var videoInput: AVCaptureDeviceInput?

    /// Movie file output for recording
    private let movieOutput = AVCaptureMovieFileOutput()

    /// Video data output for frame analysis (Story 2.3)
    private let videoDataOutput = AVCaptureVideoDataOutput()

    /// Serial queue for session operations
    private let sessionQueue = DispatchQueue(label: "com.cabinetscan.aiflow.videocapture", qos: .userInitiated)

    /// Serial queue for video data output (Story 2.3)
    private let videoDataQueue = DispatchQueue(label: "com.cabinetscan.aiflow.videodata", qos: .userInitiated)

    /// Delegate for receiving video frames for quality analysis (Story 2.3)
    weak var frameDelegate: AIVideoCaptureFrameDelegate?

    /// Current capture device (back camera)
    private var captureDevice: AVCaptureDevice?

    /// Whether the session is prepared and ready
    private var isPrepared = false

    /// Whether currently recording
    private var isRecording = false

    /// Output URL for current recording
    private var outputURL: URL?

    /// Continuation for async stopRecording
    private var stopContinuation: CheckedContinuation<URL, Error>?

    // MARK: - Video Settings

    /// Target video resolution (1080p per story spec)
    private let targetWidth = 1920
    private let targetHeight = 1080

    /// Target frame rate
    private let targetFrameRate: Float64 = 30.0

    // MARK: - Public Properties

    /// Cached preview layer - created once and reused
    private lazy var _previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    /// The preview layer for SwiftUI integration
    var previewLayer: AVCaptureVideoPreviewLayer {
        return _previewLayer
    }

    /// Whether the capture session is running
    var isSessionRunning: Bool {
        captureSession.isRunning
    }

    /// Minimum available zoom factor
    var minZoomFactor: CGFloat {
        captureDevice?.minAvailableVideoZoomFactor ?? 1.0
    }

    /// Maximum available zoom factor (capped at 2.0 per FR11)
    var maxZoomFactor: CGFloat {
        min(captureDevice?.maxAvailableVideoZoomFactor ?? 2.0, 2.0)
    }

    // MARK: - Initialization

    override init() {
        super.init()
    }

    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    // MARK: - Public Methods

    /// Prepare the capture session for recording (Task 2.2, 2.3)
    func prepare() throws {
        guard !isPrepared else {
            print("[AIVideoCapture] Already prepared")
            return
        }

        // Configure session preset for 1080p (Task 2.3)
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        // Setup video input (back camera)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            captureSession.commitConfiguration()
            throw AIVideoCaptureError.cameraNotAvailable
        }
        captureDevice = camera

        // Configure camera for optimal frame rate
        do {
            try camera.lockForConfiguration()
            // Set frame rate to 30fps
            if let format = camera.formats.first(where: { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width >= Int32(targetWidth) &&
                       format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= targetFrameRate })
            }) {
                camera.activeFormat = format
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFrameRate))
            }
            camera.unlockForConfiguration()
        } catch {
            print("[AIVideoCapture] Warning: Could not configure frame rate: \(error)")
        }

        // Add video input
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
                captureSession.commitConfiguration()
                throw AIVideoCaptureError.sessionConfigurationFailed
            }
        } catch {
            captureSession.commitConfiguration()
            throw AIVideoCaptureError.sessionConfigurationFailed
        }

        // Add movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)

            // Configure video orientation for portrait (Task 2.6)
            if let connection = movieOutput.connection(with: .video) {
                // Use the new rotation angle API for iOS 17+
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90 // Portrait orientation
                }
                // Enable video stabilization if available
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        } else {
            captureSession.commitConfiguration()
            throw AIVideoCaptureError.sessionConfigurationFailed
        }

        // Add video data output for quality analysis (Story 2.3)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)

            // Configure video orientation for data output
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
            print("[AIVideoCapture] Video data output added for quality analysis")
        } else {
            // Non-fatal: quality analysis just won't work
            print("[AIVideoCapture] Warning: Could not add video data output for quality analysis")
        }

        captureSession.commitConfiguration()

        // Start session on background queue
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
            print("[AIVideoCapture] Capture session started")
        }

        isPrepared = true
        print("[AIVideoCapture] Prepared for recording at \(targetWidth)x\(targetHeight) @ \(Int(targetFrameRate))fps")
    }

    /// Start recording video (Task 2.4)
    func startRecording() throws {
        guard isPrepared else {
            throw AIVideoCaptureError.recordingNotPrepared
        }

        guard !isRecording else {
            throw AIVideoCaptureError.recordingAlreadyInProgress
        }

        // Create output URL with timestamp (Task 2.7)
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let url = tempDir.appendingPathComponent("ai_capture_\(timestamp)_\(randomId).mp4")

        // Remove any existing file
        try? FileManager.default.removeItem(at: url)

        outputURL = url
        isRecording = true

        // Start recording on session queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            print("[AIVideoCapture] Recording started to: \(url.lastPathComponent)")
        }
    }

    /// Stop recording and return the video URL (Task 2.5)
    /// Includes timeout protection to prevent infinite hang if delegate is not called
    func stopRecording() async throws -> URL {
        print("[AIVideoCapture] stopRecording() called, isRecording=\(isRecording)")

        guard isRecording else {
            print("[AIVideoCapture] ERROR: Not recording, throwing noActiveRecording")
            throw AIVideoCaptureError.noActiveRecording
        }

        // Use a timeout to prevent infinite hang if delegate callback never fires
        let timeoutSeconds: UInt64 = 30 // 30 second timeout for video finalization
        print("[AIVideoCapture] Starting stop with \(timeoutSeconds)s timeout")

        return try await withThrowingTaskGroup(of: URL.self) { group in
            // Task 1: Wait for delegate callback
            group.addTask { [weak self] in
                print("[AIVideoCapture] Task 1: Starting continuation task")
                return try await withCheckedThrowingContinuation { continuation in
                    guard let self = self else {
                        print("[AIVideoCapture] ERROR: self is nil in continuation")
                        continuation.resume(throwing: AIVideoCaptureError.noActiveRecording)
                        return
                    }
                    print("[AIVideoCapture] Task 1: Setting stopContinuation")
                    self.stopContinuation = continuation
                    self.sessionQueue.async { [weak self] in
                        print("[AIVideoCapture] Task 1: Calling movieOutput.stopRecording()")
                        self?.movieOutput.stopRecording()
                        print("[AIVideoCapture] Task 1: movieOutput.stopRecording() called, waiting for delegate")
                    }
                }
            }

            // Task 2: Timeout protection
            group.addTask {
                print("[AIVideoCapture] Task 2: Starting timeout task (\(timeoutSeconds)s)")
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                print("[AIVideoCapture] Task 2: Timeout reached, throwing error")
                throw AIVideoCaptureError.recordingFailed("Video finalization timed out after \(timeoutSeconds) seconds")
            }

            // Wait for first task to complete
            print("[AIVideoCapture] Waiting for first task to complete...")
            guard let result = try await group.next() else {
                print("[AIVideoCapture] ERROR: group.next() returned nil")
                throw AIVideoCaptureError.recordingFailed("Unexpected error during video finalization")
            }

            print("[AIVideoCapture] Got result, cancelling remaining tasks")
            // Cancel remaining tasks
            group.cancelAll()
            return result
        }
    }

    /// Cancel recording without saving
    func cancelRecording() {
        guard isRecording else { return }

        // Capture and clear continuation BEFORE dispatching to avoid race condition
        let continuation = stopContinuation
        stopContinuation = nil
        isRecording = false

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieOutput.stopRecording()
            // Delete the file after stopping
            if let url = self.outputURL {
                try? FileManager.default.removeItem(at: url)
                self.outputURL = nil
            }
            print("[AIVideoCapture] Recording cancelled")
        }

        // Resume any waiting continuation with an error so it doesn't hang
        continuation?.resume(throwing: AIVideoCaptureError.recordingFailed("Recording was cancelled"))
    }

    /// Set zoom level (Task 3.3 - called from view model)
    func setZoom(_ zoomFactor: CGFloat) {
        guard let device = captureDevice else { return }

        // Clamp to valid range (0.5x to 2.0x per FR11, but respect device limits)
        let minZoom = max(device.minAvailableVideoZoomFactor, 0.5)
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 2.0)
        let clampedZoom = min(max(zoomFactor, minZoom), maxZoom)

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()
                print("[AIVideoCapture] Zoom set to: \(clampedZoom)")
            } catch {
                print("[AIVideoCapture] Failed to set zoom: \(error)")
            }
        }
    }

    /// Stop the capture session
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            print("[AIVideoCapture] Capture session stopped")
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension AIVideoCapture: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("[AIVideoCapture] Recording started to file: \(fileURL.lastPathComponent)")
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("[AIVideoCapture] DELEGATE: didFinishRecordingTo called")
        print("[AIVideoCapture] DELEGATE: outputFileURL=\(outputFileURL.lastPathComponent)")
        print("[AIVideoCapture] DELEGATE: error=\(error?.localizedDescription ?? "nil")")
        print("[AIVideoCapture] DELEGATE: stopContinuation exists=\(stopContinuation != nil)")

        isRecording = false

        // Capture continuation before any async work to avoid race conditions
        guard let continuation = stopContinuation else {
            print("[AIVideoCapture] DELEGATE: WARNING - No continuation to resume!")
            return
        }
        stopContinuation = nil

        if let error = error {
            // Check if this was a user-initiated stop (not a real error)
            // AVFoundation reports this as an error but the file is valid
            let nsError = error as NSError
            print("[AIVideoCapture] DELEGATE: Error code=\(nsError.code), domain=\(nsError.domain)")

            // Check if the file exists and has valid data
            let fileExists = FileManager.default.fileExists(atPath: outputFileURL.path)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int64) ?? 0
            print("[AIVideoCapture] DELEGATE: fileExists=\(fileExists), fileSize=\(fileSize)")

            if fileExists && fileSize > 0 {
                // File exists and has content - recording was successful
                print("[AIVideoCapture] DELEGATE: Recording finished successfully despite error, resuming with URL")
                continuation.resume(returning: outputFileURL)
            } else {
                print("[AIVideoCapture] DELEGATE: Recording failed, resuming with error")
                continuation.resume(throwing: AIVideoCaptureError.recordingFailed(error.localizedDescription))
                // Clean up failed recording
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        } else {
            print("[AIVideoCapture] DELEGATE: Recording finished successfully, resuming with URL")
            continuation.resume(returning: outputFileURL)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Story 2.3)

extension AIVideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Forward to frame delegate for quality analysis
        frameDelegate?.videoCapture(self, didOutputSampleBuffer: sampleBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Frame was dropped - this is fine for analysis (we sample anyway)
    }
}
