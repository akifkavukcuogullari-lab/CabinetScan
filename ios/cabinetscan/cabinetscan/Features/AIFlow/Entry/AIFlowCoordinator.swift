//
//  AIFlowCoordinator.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import Combine
import UIKit

// MARK: - Coordinator Protocol

/// Protocol defining AI Flow coordination capabilities.
/// Per Architecture Section 6.2 Key Interfaces.
///
/// Note: This protocol references `MeasurementData` from `Models/ProjectSubmission.swift`.
/// This is an intentional dependency as AI Flow must produce output compatible with the
/// existing LiDAR flow's data model. Per ARCH-3, MeasurementData will be extended
/// (additive only) in Story 5.4 to include AI-specific metadata.
protocol AIFlowCoordinatorProtocol {
    /// Start the capture process (video + photos)
    func startCapture() async

    /// Cancel ongoing capture and return to initial state
    func cancelCapture()

    /// Process captured data and return measurement results
    func processCapture(showroomId: String, showroomCode: String) async throws -> MeasurementData

    /// Current state of the capture flow
    var captureState: AICaptureState { get }

    /// Processing progress (0.0 to 1.0)
    var processingProgress: Double { get }
}

// MARK: - Capture State

/// State machine for AI capture flow.
/// Tracks the current phase of capture and processing.
/// Per Architecture Section 6.2 Key Interfaces.
enum AICaptureState: Equatable {
    case idle
    case calibrating
    case recordingVideo
    case capturingPhotos
    case processing
    case complete
    case error(Error)

    static func == (lhs: AICaptureState, rhs: AICaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.calibrating, .calibrating),
             (.recordingVideo, .recordingVideo),
             (.capturingPhotos, .capturingPhotos),
             (.processing, .processing),
             (.complete, .complete):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            // Compare by localized description since Error doesn't conform to Equatable
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - AI Flow Error

/// Errors that can occur during AI flow capture and processing
enum AIFlowError: LocalizedError {
    case captureNotReady
    case processingFailed(String)
    case calibrationFailed
    case insufficientData
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .captureNotReady:
            return "Capture session is not ready"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .calibrationFailed:
            return "Could not calibrate measurements"
        case .insufficientData:
            return "Not enough data captured for accurate measurements"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
}

// MARK: - Coordinator Implementation

/// Coordinates navigation and state within the AI Flow.
/// Manages the lifecycle of capture sessions and processing pipeline.
/// Per Story 2.2 - Tasks 8 & 9
@MainActor
class AIFlowCoordinator: ObservableObject, AIFlowCoordinatorProtocol {
    @Published private(set) var captureState: AICaptureState = .idle
    @Published private(set) var processingProgress: Double = 0.0

    // MARK: - AR Session Manager

    /// Shared AR session manager for pose tracking (Story 2.1)
    /// Created lazily and shared across video and photo capture
    lazy var arSessionManager: AIARSessionManager = {
        let manager = AIARSessionManager()
        return manager
    }()

    // MARK: - Video Capture (for photo capture session sharing)

    /// Video capture instance - stored to share capture session with photo capture
    private(set) var videoCapture: AIVideoCapture?

    /// Set video capture instance (called from VideoCaptureView)
    func setVideoCapture(_ capture: AIVideoCapture) {
        self.videoCapture = capture
    }

    // MARK: - Capture Data Manager (Story 2.6)

    /// Shared capture data manager for session persistence
    lazy var captureDataManager: AICaptureDataManager = {
        let manager = AICaptureDataManager()
        manager.onRecoverableSessionFound = { [weak self] sessionId, state in
            self?.handleRecoverableSessionFound(sessionId: sessionId, state: state)
        }
        return manager
    }()

    /// Whether a recovery prompt should be shown
    @Published private(set) var showRecoveryPrompt: Bool = false

    /// Session ID for recovery prompt
    private(set) var recoverableSessionId: String?

    /// State of recoverable session
    private(set) var recoverableSessionState: AISessionPersistenceState?

    /// Handle finding a recoverable session
    private func handleRecoverableSessionFound(sessionId: String, state: AISessionPersistenceState) {
        recoverableSessionId = sessionId
        recoverableSessionState = state
        showRecoveryPrompt = true
        print("[AIFlowCoordinator] Showing recovery prompt for session: \(sessionId)")
    }

    /// User chose to resume the recoverable session
    func resumeRecoverableSession() {
        guard let sessionId = recoverableSessionId else { return }

        if let recoveredData = captureDataManager.recoverSession(sessionId: sessionId) {
            captureSessionData = recoveredData

            // Navigate to appropriate state based on what was recovered
            if recoveredData.videoURL != nil && recoveredData.photos.isEmpty {
                captureState = .capturingPhotos
                print("[AIFlowCoordinator] Resumed session - video recovered, moving to photo capture")
            } else if !recoveredData.photos.isEmpty && recoveredData.photos.count < AICaptureSessionData.minimumPhotoCount {
                captureState = .capturingPhotos
                print("[AIFlowCoordinator] Resumed session - partial photos recovered, continuing photo capture")
            } else if recoveredData.hasMinimumData {
                captureState = .processing
                print("[AIFlowCoordinator] Resumed session - full data recovered, moving to processing")
            }
        }

        showRecoveryPrompt = false
        recoverableSessionId = nil
        recoverableSessionState = nil
    }

    /// User chose to discard the recoverable session
    func discardRecoverableSession() {
        if let sessionId = recoverableSessionId {
            // Clean up the old session
            let sessionDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("AIFlowCaptures")
                .appendingPathComponent(sessionId)
            try? FileManager.default.removeItem(at: sessionDir)
            print("[AIFlowCoordinator] Discarded recoverable session: \(sessionId)")
        }

        showRecoveryPrompt = false
        recoverableSessionId = nil
        recoverableSessionState = nil
    }

    // MARK: - Capture Session Data

    /// Current capture session data (accumulates video + photos)
    @Published private(set) var captureSessionData: AICaptureSessionData?

    // MARK: - Protocol Methods

    /// Start capture sequence
    func startCapture() async {
        captureState = .recordingVideo
        print("[AIFlowCoordinator] Started capture sequence - recording video")
    }

    /// Cancel ongoing capture
    func cancelCapture() {
        captureState = .idle
        processingProgress = 0.0
        uploadStatus = nil
        captureSessionData = nil
        arSessionManager.stopSession()
        Task { await pipelineClient.cancel() }
        print("[AIFlowCoordinator] Capture cancelled, session stopped")
    }

    /// Process captured data by uploading to server pipeline and polling for results.
    ///
    /// Flow: Build package -> Upload files -> Create job -> Poll status -> Convert results
    ///
    /// - Parameters:
    ///   - showroomId: Showroom UUID for job context
    ///   - showroomCode: Showroom code for storage paths
    /// - Returns: MeasurementData ready for AppState.setMeasurementData()
    func processCapture(showroomId: String, showroomCode: String) async throws -> MeasurementData {
        captureState = .processing
        processingProgress = 0.0

        // 1. Build capture package
        uploadStatus = "Preparing capture data..."
        print("[AIFlowCoordinator] Building capture package...")
        let package = try buildCapturePackage(showroomId: showroomId)
        processingProgress = 0.05

        // 2. Upload files and create job
        let jobId = try await pipelineClient.submitJob(
            package: package,
            showroomCode: showroomCode,
            showroomId: showroomId
        ) { [weak self] status in
            self?.uploadStatus = status
        }
        processingProgress = 0.3
        print("[AIFlowCoordinator] Job submitted: \(jobId)")

        // 3. Poll for results
        uploadStatus = "Processing scan on server..."
        let result = try await pipelineClient.pollForResults(jobId: jobId) { [weak self] progress, stage in
            // Map server progress (0-1) to our progress range (0.3-0.9)
            self?.processingProgress = 0.3 + (progress * 0.6)
            self?.uploadStatus = stage
        }
        processingProgress = 0.9
        print("[AIFlowCoordinator] Results received, converting...")

        // 4. Convert to MeasurementData
        uploadStatus = "Finalizing measurements..."
        let uploadContext = UploadContext(
            videoUrl: captureSessionData?.videoURL?.absoluteString ?? "",
            videoThumbnailUrl: nil,
            videoDurationSeconds: Int(captureSessionData?.metadata?.videoDuration ?? 0),
            videoSizeBytes: 0,
            videoResolution: "unknown",
            photoUrls: []
        )

        let adapter = ServerResultAdapter()
        let measurementData = adapter.convert(
            result: result,
            uploadContext: uploadContext
        )

        // Store validation warnings
        if !result.validationIssues.isEmpty {
            outputWarnings = result.validationIssues
        }

        processingProgress = 1.0
        captureState = .complete
        uploadStatus = nil

        print("[AIFlowCoordinator] Processing complete")
        return measurementData
    }

    /// Update processing progress
    func updateProgress(_ progress: Double) {
        processingProgress = min(max(progress, 0.0), 1.0)
    }

    /// Transition to error state
    func setError(_ error: Error) {
        captureState = .error(error)
    }

    /// Reset to initial state
    func reset() {
        captureState = .idle
        processingProgress = 0.0
        captureSessionData = nil
        print("[AIFlowCoordinator] Reset to initial state")
    }

    // MARK: - Video Capture Completion (Story 2.2 - Task 9)

    /// Called when video recording completes
    /// Stores capture data and transitions to photo capture phase
    /// - Parameter data: The capture session data with video URL and poses
    func onVideoCaptureComplete(_ data: AICaptureSessionData) {
        captureSessionData = data
        captureState = .capturingPhotos
        print("[AIFlowCoordinator] Video capture complete - transitioning to photo capture")
        print("[AIFlowCoordinator] Video URL: \(data.videoURL?.lastPathComponent ?? "nil")")
        print("[AIFlowCoordinator] Video duration: \(data.metadata?.videoDuration ?? 0)s")
    }

    /// Called when user cancels from video capture
    /// Returns to idle state and cleans up
    func onVideoCaptureBack() {
        captureState = .idle
        captureSessionData = nil
        arSessionManager.stopSession()
        print("[AIFlowCoordinator] Video capture cancelled - returning to intro")
    }

    // MARK: - Photo Capture (Placeholder for Story 2.5)

    /// Called when photo capture completes
    /// Will be fully implemented in Story 2.5
    func onPhotoCaptureComplete(_ photos: [AICapturedPhoto]) {
        guard var data = captureSessionData else {
            print("[AIFlowCoordinator] Error: No capture session data for photo completion")
            return
        }

        // Add photos to session data
        data.photos = photos

        // Update metadata with photo count
        if let metadata = data.metadata {
            data.metadata = AICaptureMetadata(
                deviceModel: metadata.deviceModel,
                osVersion: metadata.osVersion,
                captureDate: metadata.captureDate,
                videoDuration: metadata.videoDuration,
                photoCount: photos.count,
                averageLighting: metadata.averageLighting
            )
        } else {
            // Create metadata if it doesn't exist
            data.metadata = AICaptureMetadata(
                deviceModel: UIDevice.current.model,
                osVersion: UIDevice.current.systemVersion,
                captureDate: Date(),
                videoDuration: 0,
                photoCount: photos.count,
                averageLighting: nil
            )
        }

        captureSessionData = data
        captureState = .processing

        print("[AIFlowCoordinator] Photo capture complete - \(photos.count) photos captured")
        print("[AIFlowCoordinator] Transitioning to processing phase")
    }

    /// Called when user cancels from photo capture
    /// Returns to video capture state (option to retake video)
    func onPhotoCaptureBack() {
        captureState = .recordingVideo
        // Keep the video data - user might want to retake or continue with fewer photos
        print("[AIFlowCoordinator] Photo capture cancelled - returning to video capture")
    }

    // MARK: - Capture Package Builder (Phase 1.3)

    /// Builds capture packages for server pipeline upload
    private lazy var packageBuilder = CapturePackageBuilder(sessionManager: arSessionManager)

    /// Build a capture package from the current session data.
    /// - Parameter showroomId: The showroom identifier for server context
    /// - Returns: A `CapturePackage` ready for upload
    /// - Throws: `AIFlowError.insufficientData` if video URL or session data is missing
    func buildCapturePackage(showroomId: String) throws -> CapturePackage {
        guard let sessionData = captureSessionData,
              let videoURL = sessionData.videoURL else {
            throw AIFlowError.insufficientData
        }

        return packageBuilder.build(
            videoURL: videoURL,
            sessionData: sessionData,
            showroomId: showroomId
        )
    }

    // MARK: - Server Pipeline Client (Phase 2.1)

    /// Server pipeline client for uploading and polling
    private lazy var pipelineClient = ServerPipelineClient(uploader: uploader)

    // MARK: - Upload

    /// Uploader for video and photos to Supabase storage
    private lazy var uploader = AIFlowUploader()

    /// Upload progress status message
    @Published private(set) var uploadStatus: String?

    /// Validation warnings
    @Published private(set) var outputWarnings: [String] = []

    /// Clears output warnings (e.g., after user acknowledges them)
    func clearOutputWarnings() {
        outputWarnings = []
    }
}
