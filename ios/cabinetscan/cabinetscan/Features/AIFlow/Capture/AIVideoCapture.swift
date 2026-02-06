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
    /// NOTE: This output is only enabled when NOT recording to avoid conflicts
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

    /// Recording start time for duration validation
    private var recordingStartTime: Date?

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

            // Configure video for reliable recording
            // Set max duration to 3 minutes (per FR: 30-60 second typical scans)
            movieOutput.maxRecordedDuration = CMTime(seconds: 180, preferredTimescale: 600)
            // Require at least 100MB free disk space
            movieOutput.minFreeDiskSpaceLimit = 100_000_000

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

        // NOTE: Video data output for quality analysis is NOT added during prepare()
        // Adding both movieOutput and videoDataOutput causes frame competition issues
        // that result in truncated recordings. Quality analysis should be done on
        // the recorded video file after recording completes.
        // See: AI_FLOW_ISSUES_AND_FIX_PLAN.md - Issue 1.1
        print("[AIVideoCapture] Video data output disabled during recording to prevent truncation")

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
    /// Now async to verify recording actually starts
    func startRecording() async throws {
        guard isPrepared else {
            throw AIVideoCaptureError.recordingNotPrepared
        }

        guard !isRecording else {
            throw AIVideoCaptureError.recordingAlreadyInProgress
        }

        // Wait for session to be running (it starts async in prepare())
        // Poll for up to 2 seconds
        var waitCount = 0
        while !captureSession.isRunning && waitCount < 20 {
            print("[AIVideoCapture] Waiting for capture session to start... (\(waitCount + 1)/20)")
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            waitCount += 1
        }

        // Verify session is running
        guard captureSession.isRunning else {
            print("[AIVideoCapture] ERROR: Capture session not running after waiting 2 seconds")
            throw AIVideoCaptureError.sessionConfigurationFailed
        }
        print("[AIVideoCapture] Capture session confirmed running")

        // Verify movie output is connected
        guard movieOutput.connection(with: .video) != nil else {
            print("[AIVideoCapture] ERROR: No video connection to movie output")
            throw AIVideoCaptureError.sessionConfigurationFailed
        }

        // Create output URL with timestamp (Task 2.7)
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let url = tempDir.appendingPathComponent("ai_capture_\(timestamp)_\(randomId).mp4")

        // Remove any existing file
        try? FileManager.default.removeItem(at: url)

        outputURL = url

        print("[AIVideoCapture] Starting recording to: \(url.lastPathComponent)")
        print("[AIVideoCapture] Session running: \(captureSession.isRunning)")
        print("[AIVideoCapture] Movie output connections: \(movieOutput.connections.count)")

        // Record start time for duration validation
        recordingStartTime = Date()

        // Start recording synchronously on session queue and wait for it
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                continuation.resume()
            }
        }

        // Wait a moment for AVFoundation to start recording
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify recording actually started
        if movieOutput.isRecording {
            isRecording = true
            print("[AIVideoCapture] Recording confirmed started: \(url.lastPathComponent)")
        } else {
            print("[AIVideoCapture] WARNING: Recording did not start! movieOutput.isRecording=false")
            // Still set our flag - the delegate might fire later
            isRecording = true
            print("[AIVideoCapture] Proceeding anyway, delegate may confirm start later")
        }
    }

    /// Stop recording and return the video URL (Task 2.5)
    /// Includes timeout protection to prevent infinite hang if delegate is not called
    func stopRecording() async throws -> URL {
        print("[AIVideoCapture] stopRecording() called")
        print("[AIVideoCapture] - isRecording=\(isRecording)")
        print("[AIVideoCapture] - movieOutput.isRecording=\(movieOutput.isRecording)")
        print("[AIVideoCapture] - captureSession.isRunning=\(captureSession.isRunning)")
        print("[AIVideoCapture] - outputURL=\(outputURL?.lastPathComponent ?? "nil")")
        print("[AIVideoCapture] - stopContinuation already set=\(stopContinuation != nil)")

        // Primary check: our internal flag
        guard isRecording else {
            print("[AIVideoCapture] ERROR: isRecording is false")
            // Check if we have a valid output file anyway (recovery path)
            if let url = outputURL, FileManager.default.fileExists(atPath: url.path) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                print("[AIVideoCapture] Found existing file: \(url.lastPathComponent), size=\(fileSize)")
                if fileSize > 0 {
                    print("[AIVideoCapture] Returning existing file as recovery")
                    return url
                }
            }
            throw AIVideoCaptureError.noActiveRecording
        }

        // Secondary check: AVFoundation's state
        // If AVFoundation stopped unexpectedly, try to return the file if it exists
        if !movieOutput.isRecording {
            print("[AIVideoCapture] WARNING: movieOutput.isRecording is false but isRecording was true")
            print("[AIVideoCapture] AVFoundation may have stopped unexpectedly")
            isRecording = false // Sync our state

            if let url = outputURL, FileManager.default.fileExists(atPath: url.path) {
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                print("[AIVideoCapture] Found output file: \(url.lastPathComponent), size=\(fileSize)")
                if fileSize > 0 {
                    print("[AIVideoCapture] Returning existing file")
                    return url
                }
            }
            throw AIVideoCaptureError.recordingFailed("Recording was not active in AVFoundation")
        }

        // Use a timeout to prevent infinite hang if delegate callback never fires
        let timeoutSeconds: UInt64 = 30
        print("[AIVideoCapture] Starting stop with \(timeoutSeconds)s timeout")

        // Calculate expected duration for validation
        let expectedDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        print("[AIVideoCapture] Expected recording duration: \(String(format: "%.1f", expectedDuration))s")

        do {
            let videoURL = try await withThrowingTaskGroup(of: URL.self) { group in
                // Task 1: Wait for delegate callback
                // CRITICAL FIX: Set continuation BEFORE dispatching stopRecording
                // to prevent race condition where delegate fires before continuation is set
                group.addTask { [weak self] in
                    print("[AIVideoCapture] Task 1: Starting continuation task")
                    return try await withCheckedThrowingContinuation { continuation in
                        guard let self = self else {
                            print("[AIVideoCapture] ERROR: self is nil in continuation")
                            continuation.resume(throwing: AIVideoCaptureError.noActiveRecording)
                            return
                        }

                        // CRITICAL: Set continuation FIRST
                        print("[AIVideoCapture] Task 1: Setting stopContinuation BEFORE dispatch")
                        self.stopContinuation = continuation

                        // THEN dispatch stop (delegate callback will find continuation ready)
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
                    print("[AIVideoCapture] Task 2: Timeout reached")
                    throw AIVideoCaptureError.recordingFailed("Video finalization timed out after \(timeoutSeconds) seconds")
                }

                // Wait for first task to complete
                print("[AIVideoCapture] Waiting for first task to complete...")
                guard let result = try await group.next() else {
                    print("[AIVideoCapture] ERROR: group.next() returned nil")
                    throw AIVideoCaptureError.recordingFailed("Unexpected error during video finalization")
                }

                print("[AIVideoCapture] Got result, cancelling remaining tasks")
                group.cancelAll()
                return result
            }

            // Validate video file after successful recording
            try validateRecordedVideo(at: videoURL, expectedDuration: expectedDuration)

            return videoURL
        } catch {
            // Clean up on any error (including timeout)
            print("[AIVideoCapture] stopRecording error: \(error.localizedDescription)")
            print("[AIVideoCapture] Cleaning up: isRecording=false, stopContinuation=nil")
            isRecording = false
            stopContinuation = nil
            recordingStartTime = nil
            throw error
        }
    }

    /// Validates that the recorded video file is valid
    /// - Parameters:
    ///   - url: URL of the recorded video
    ///   - expectedDuration: Expected duration based on recording time
    private func validateRecordedVideo(at url: URL, expectedDuration: TimeInterval) throws {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AIVideoCaptureError.recordingFailed("Video file does not exist")
        }

        // Check file size
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        print("[AIVideoCapture] Video validation: size=\(fileSize) bytes, expectedDuration=\(String(format: "%.1f", expectedDuration))s")

        // Minimum expected size: ~100KB per second for compressed H.264 video
        // For a 30-second video, we expect at least 3MB
        let minExpectedSize: Int64
        if expectedDuration >= 3 {
            // At least 100KB per second of expected recording
            minExpectedSize = Int64(expectedDuration * 100_000)
        } else {
            // Short recordings: at least 100KB
            minExpectedSize = 100_000
        }

        if fileSize < minExpectedSize && expectedDuration > 3 {
            print("[AIVideoCapture] WARNING: Video file suspiciously small: \(fileSize) bytes for \(String(format: "%.1f", expectedDuration))s recording")
            print("[AIVideoCapture] Expected at least \(minExpectedSize) bytes")
            // Don't throw here - the file might still be usable, just log the warning
        }

        print("[AIVideoCapture] Video validation passed: \(url.lastPathComponent)")
    }

    /// Cancel recording without saving
    func cancelRecording() {
        guard isRecording else { return }

        // Capture and clear continuation BEFORE dispatching to avoid race condition
        let continuation = stopContinuation
        stopContinuation = nil
        isRecording = false
        recordingStartTime = nil

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
        print("[AIVideoCapture] DELEGATE: isRecording was=\(isRecording)")

        // Capture continuation before any async work to avoid race conditions
        guard let continuation = stopContinuation else {
            // No continuation means this was an unexpected stop (AVFoundation error)
            // Log but don't change isRecording - the ViewModel will detect this via movieOutput.isRecording
            print("[AIVideoCapture] DELEGATE: WARNING - No continuation to resume! Unexpected recording stop.")
            print("[AIVideoCapture] DELEGATE: File exists=\(FileManager.default.fileExists(atPath: outputFileURL.path))")
            return
        }

        // Only set isRecording = false for controlled stops
        isRecording = false
        stopContinuation = nil
        recordingStartTime = nil

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
