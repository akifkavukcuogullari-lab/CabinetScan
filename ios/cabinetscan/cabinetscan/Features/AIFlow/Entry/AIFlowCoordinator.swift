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
    func processCapture() async throws -> MeasurementData

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
    case manualCalibration(ManualCalibrationInput)  // Story 3.6: Manual calibration fallback
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
        case (.manualCalibration, .manualCalibration):
            return true  // Don't compare associated values for equality
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
        captureSessionData = nil
        arSessionManager.stopSession()
        print("[AIFlowCoordinator] Capture cancelled, session stopped")
    }

    /// Process captured data into measurements
    func processCapture() async throws -> MeasurementData {
        captureState = .processing
        // Placeholder - will be implemented in Epic 3
        throw AIFlowError.notImplemented
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

    // MARK: - Manual Calibration (Story 3.6)

    /// Scale calibrator for manual calibration
    lazy var scaleCalibrator: ScaleCalibrator = {
        return ScaleCalibrator()
    }()

    /// Current calibration result (after automatic or manual calibration)
    @Published private(set) var calibrationResult: ScaleCalibrationResult?

    /// Triggers manual calibration when automatic calibration fails.
    ///
    /// Called by the processing pipeline when `ScaleCalibrationResult.calibrationMethod == .failed`.
    /// Pauses processing and presents ManualCalibrationView.
    ///
    /// - Parameter input: Data needed for manual calibration including fusion result and failure reason
    func triggerManualCalibration(input: ManualCalibrationInput) {
        captureState = .manualCalibration(input)
        print("[AIFlowCoordinator] Triggered manual calibration - reason: \(input.failureReason)")
    }

    /// Called when manual calibration completes successfully.
    ///
    /// Resumes the processing pipeline with the new scale factor.
    ///
    /// - Parameter result: The calibration result from manual calibration
    func onManualCalibrationComplete(_ result: ScaleCalibrationResult) {
        calibrationResult = result
        captureState = .processing
        print("[AIFlowCoordinator] Manual calibration complete - scaleFactor: \(result.scaleFactor), method: \(result.calibrationMethod)")
    }

    /// Called when user cancels manual calibration.
    ///
    /// Returns to error state since calibration is required.
    func onManualCalibrationCancelled() {
        captureState = .error(AIFlowError.calibrationFailed)
        print("[AIFlowCoordinator] Manual calibration cancelled - setting error state")
    }

    /// Creates a ManualCalibrationViewModel for the current manual calibration input.
    ///
    /// - Returns: ViewModel configured for manual calibration, or nil if not in manual calibration state
    func createManualCalibrationViewModel() -> ManualCalibrationViewModel? {
        guard case .manualCalibration(let input) = captureState else {
            return nil
        }

        let viewModel = ManualCalibrationViewModel(input: input, calibrator: scaleCalibrator)

        // Set up callbacks
        viewModel.onCalibrationComplete = { [weak self] result in
            self?.onManualCalibrationComplete(result)
        }

        viewModel.onCancel = { [weak self] in
            self?.onManualCalibrationCancelled()
        }

        return viewModel
    }

    /// Checks if automatic calibration failed and manual calibration is needed.
    ///
    /// Called by the pipeline after automatic calibration attempt.
    ///
    /// - Parameters:
    ///   - result: The automatic calibration result
    ///   - fusionResult: The TSDF fusion result
    ///   - capturedPhotos: Photos captured during the session
    /// - Returns: True if manual calibration is needed and has been triggered
    func checkCalibrationAndTriggerManualIfNeeded(
        result: ScaleCalibrationResult,
        fusionResult: TSDFFusionResult,
        capturedPhotos: [AICapturedPhoto]
    ) -> Bool {
        // Only trigger manual calibration if automatic failed
        guard result.calibrationMethod == .failed else {
            calibrationResult = result
            return false
        }

        // Get first photo URL for preview
        let previewPhotoURL = capturedPhotos.first?.url

        // Determine failure reason
        let failureReason: String
        if result.validationResults.passedChecks == 0 {
            failureReason = "Could not detect countertop or ceiling for automatic calibration"
        } else {
            failureReason = "Calibration validation failed"
        }

        // Create input and trigger manual calibration
        let input = ManualCalibrationInput(
            fusionResult: fusionResult,
            floorPlane: result.floorPlane,
            failureReason: failureReason,
            previewPhotoURL: previewPhotoURL
        )

        triggerManualCalibration(input: input)
        return true
    }

    // MARK: - Output Adapter (Story 5.6)

    /// Output adapter for converting pipeline results to MeasurementData
    private lazy var outputAdapter = AIOutputAdapter()

    /// Validation warnings from the output adapter
    @Published private(set) var outputWarnings: [String] = []

    /// Adapts pipeline result and stores in AppState.
    ///
    /// Called when processing completes successfully. This method:
    /// 1. Converts pipeline result to MeasurementData via AIOutputAdapter
    /// 2. Stores validation warnings for potential display
    /// 3. Updates AppState with the adapted measurement data
    /// 4. Transitions to complete state
    ///
    /// - Parameters:
    ///   - pipelineResult: Completed pipeline result from Epic 3/4
    ///   - appState: AppState to store measurement data for downstream screens
    /// - Throws: AIOutputError if adaptation fails
    func adaptAndStoreOutput(
        pipelineResult: AIPipelineResult,
        appState: AppState
    ) async throws {
        print("[AIFlowCoordinator] Starting output adaptation")

        do {
            let result = try await outputAdapter.adapt(
                pipelineResult: pipelineResult,
                captureSession: captureSessionData
            )

            // Store warnings for potential display (e.g., low confidence)
            outputWarnings = result.warnings

            if !result.warnings.isEmpty {
                print("[AIFlowCoordinator] Output warnings: \(result.warnings)")
            }

            // Update AppState with adapted measurement data
            appState.setMeasurementData(result.measurementData)

            // Transition to complete state
            captureState = .complete

            print("[AIFlowCoordinator] Output adaptation complete - transitioning to complete state")
        } catch {
            print("[AIFlowCoordinator] Output adaptation failed: \(error.localizedDescription)")
            captureState = .error(error)
            throw error
        }
    }

    /// Called when processing completes successfully.
    ///
    /// Convenience method that wraps adaptAndStoreOutput for simpler callsites.
    ///
    /// - Parameters:
    ///   - pipelineResult: Completed pipeline result
    ///   - appState: AppState for storing measurement data
    func onProcessingComplete(
        pipelineResult: AIPipelineResult,
        appState: AppState
    ) async {
        do {
            try await adaptAndStoreOutput(pipelineResult: pipelineResult, appState: appState)
        } catch {
            // Error state already set in adaptAndStoreOutput
            print("[AIFlowCoordinator] onProcessingComplete failed: \(error.localizedDescription)")
        }
    }

    /// Clears output warnings (e.g., after user acknowledges them)
    func clearOutputWarnings() {
        outputWarnings = []
    }

    // MARK: - Timeout Handling (Story 6.8)

    /// Pipeline orchestrator for timeout retry operations
    private var pipelineOrchestrator: AIPipelineOrchestrator?

    /// Sets the pipeline orchestrator for timeout retry operations.
    ///
    /// Called by ProcessingView or the view that owns the orchestrator.
    ///
    /// - Parameter orchestrator: The pipeline orchestrator instance
    func setPipelineOrchestrator(_ orchestrator: AIPipelineOrchestrator) {
        self.pipelineOrchestrator = orchestrator
    }

    /// Called when user cancels from timeout warning sheet.
    ///
    /// **Per Story 6.8 AC4:**
    /// When user selects "Cancel", captured data is saved for potential later use.
    ///
    /// - Parameter checkpoint: Current pipeline checkpoint (if available)
    func onTimeoutCancel(checkpoint: PipelineCheckpoint?) {
        guard let sessionData = captureSessionData else {
            print("[AIFlowCoordinator] Timeout cancel - no session data to preserve")
            captureState = .idle
            return
        }

        // Save session data for later recovery
        do {
            _ = try captureDataManager.saveSessionForLater(
                videoDuration: sessionData.metadata?.videoDuration ?? 0,
                photoCount: sessionData.photos.count,
                checkpoint: checkpoint,
                qualityMetrics: sessionData.qualityMetrics
            )
            print("[AIFlowCoordinator] Timeout cancel - session saved for later recovery")
        } catch {
            print("[AIFlowCoordinator] Failed to save session for later: \(error)")
        }

        // Return to idle state
        captureState = .idle
        processingProgress = 0.0
    }

    /// Called when user selects retry from timeout warning sheet.
    ///
    /// **Per Story 6.8 AC3:**
    /// Processing restarts from last checkpoint without re-capturing.
    ///
    /// - Returns: Task that performs the retry operation
    @discardableResult
    func onTimeoutRetry() -> Task<AIPipelineResult?, Error>? {
        guard let orchestrator = pipelineOrchestrator,
              let sessionData = captureSessionData else {
            print("[AIFlowCoordinator] Timeout retry - missing orchestrator or session data")
            return nil
        }

        print("[AIFlowCoordinator] Starting timeout retry from checkpoint")

        return Task {
            do {
                let result = try await orchestrator.retry(captureData: sessionData)
                return result
            } catch {
                print("[AIFlowCoordinator] Timeout retry failed: \(error)")
                throw error
            }
        }
    }

    /// Checks for timeout-cancelled sessions that can be resumed.
    ///
    /// **Per Story 6.8 Task 6.5:**
    /// Discovers sessions that were cancelled due to timeout.
    ///
    /// - Returns: Array of session IDs that can be resumed
    func findTimeoutCancelledSessions() -> [String] {
        return captureDataManager.findTimeoutCancelledSessions()
    }

    /// Resumes a timeout-cancelled session from its checkpoint.
    ///
    /// - Parameter sessionId: The session ID to resume
    /// - Returns: True if session was found and can be resumed
    func resumeTimeoutCancelledSession(sessionId: String) -> Bool {
        guard let checkpoint = captureDataManager.getTimeoutCheckpoint(for: sessionId),
              let recoveredData = captureDataManager.recoverSession(sessionId: sessionId) else {
            print("[AIFlowCoordinator] Cannot resume timeout session: \(sessionId)")
            return false
        }

        captureSessionData = recoveredData
        captureState = .processing
        print("[AIFlowCoordinator] Resumed timeout session: \(sessionId) from checkpoint: \(checkpoint.description)")
        return true
    }
}
