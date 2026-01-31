//
//  VideoCaptureViewModel.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import Combine
import AVFoundation

// MARK: - Recording State

/// State machine for video recording
enum RecordingState: Equatable {
    case idle           // Initial state, camera preview visible
    case waitingForAR   // Waiting for AR session to be ready
    case recording      // Actively recording video
    case stopped        // Recording complete, preparing for next step
}

// MARK: - Video Capture ViewModel

/// Manages video capture state and interactions with AR session and video recorder.
/// Per Story 2.2 - Task 1
///
/// **Usage:**
/// 1. Create instance with AIARSessionManager
/// 2. Observe `isARReady` to enable start button
/// 3. Call `startRecording()` when user taps start
/// 4. Call `stopRecording()` when user taps stop (after 10s minimum)
/// 5. Access `captureData` after recording completes
@MainActor
class VideoCaptureViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Current recording state
    @Published private(set) var recordingState: RecordingState = .idle

    /// Elapsed recording time in seconds
    @Published private(set) var elapsedTime: TimeInterval = 0

    /// Current zoom level (1.0 = no zoom)
    @Published var zoomLevel: CGFloat = 1.0

    /// Whether stop button should be enabled (after 10s)
    @Published private(set) var isStopEnabled: Bool = false

    /// Whether to show max duration reached toast
    @Published var showMaxDurationToast: Bool = false

    /// Whether AR session is ready for capture
    @Published private(set) var isARReady: Bool = false

    /// Whether recording has completed and data is ready for navigation
    @Published private(set) var isRecordingFinalized: Bool = false

    /// Error message to display, if any
    @Published var errorMessage: String?

    // MARK: - Tracking Recovery Properties (Story 6.7)

    /// Current tracking recovery state
    @Published private(set) var trackingRecoveryState: TrackingRecoveryState = .normal

    /// Whether to show tracking recovery toast
    @Published var showTrackingRecoveryToast: Bool = false

    /// Whether to show tracking failed sheet
    @Published var showTrackingFailedSheet: Bool = false

    // MARK: - Constants

    /// Minimum recording duration in seconds (AC2)
    static let minimumDuration: TimeInterval = 10

    /// Maximum recording duration in seconds (AC4)
    static let maximumDuration: TimeInterval = 120

    // MARK: - Dependencies

    /// AR session manager for pose tracking (from Story 2.1)
    let sessionManager: AIARSessionManager

    /// Video capture service
    private(set) var videoCapture: AIVideoCapture?

    /// Capture data manager for persistence (Story 2.6)
    private let dataManager: AICaptureDataManager

    // MARK: - Capture Data

    /// Captured session data (video URL + poses)
    private(set) var captureData: AICaptureSessionData?

    /// Exported pose data dictionary
    private(set) var exportedPoseData: [String: Any]?

    // MARK: - Private Properties

    /// Timer subscription for elapsed time updates
    private var timerCancellable: AnyCancellable?

    /// Subscription for AR session ready state
    private var arReadyCancellable: AnyCancellable?

    /// Subscription for tracking recovery state (Story 6.7)
    private var trackingRecoveryCancellable: AnyCancellable?

    /// Haptic feedback generator (prepared in advance per AC5)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Selection haptic for zoom changes
    private let selectionHaptic = UISelectionFeedbackGenerator()

    // MARK: - Initialization

    /// Initialize with AR session manager and data manager dependencies
    /// - Parameters:
    ///   - sessionManager: The AR session manager for pose tracking
    ///   - dataManager: The capture data manager for persistence (Story 2.6)
    /// Note: dataManager is required (no default) to ensure consistent session handling (Issue #7 fix)
    init(sessionManager: AIARSessionManager, dataManager: AICaptureDataManager) {
        self.sessionManager = sessionManager
        self.dataManager = dataManager
        setupARSessionObserver()
        prepareHaptics()
    }

    deinit {
        timerCancellable?.cancel()
        arReadyCancellable?.cancel()
        trackingRecoveryCancellable?.cancel()
    }

    // MARK: - Setup

    /// Observe AR session ready state
    private func setupARSessionObserver() {
        arReadyCancellable = sessionManager.$isReadyForCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                self?.isARReady = isReady
                print("[VideoCaptureViewModel] AR ready state changed: \(isReady)")
            }
    }

    /// Setup tracking recovery observer (Story 6.7)
    private func setupTrackingRecoveryObserver() {
        trackingRecoveryCancellable = sessionManager.trackingRecoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handleTrackingRecoveryStateChange(newState)
            }
    }

    /// Handle tracking recovery state changes (Story 6.7)
    /// M2 fix: Added haptic feedback for tracking state changes
    private func handleTrackingRecoveryStateChange(_ newState: TrackingRecoveryState) {
        let oldState = trackingRecoveryState
        trackingRecoveryState = newState

        // Update toast visibility and provide haptic feedback
        switch newState {
        case .normal:
            // If recovering from non-normal state, show briefly then hide
            if oldState != .normal {
                showTrackingRecoveryToast = true
                // Toast will auto-dismiss via container
                // Light haptic for recovery success
                selectionHaptic.selectionChanged()
            }
        case .limited:
            showTrackingRecoveryToast = true
            // Selection haptic for limited tracking (gentle warning)
            if oldState == .normal {
                selectionHaptic.selectionChanged()
            }
        case .lost:
            showTrackingRecoveryToast = true
            // Medium impact haptic for tracking lost (stronger warning)
            // Only trigger haptic on first transition to lost state
            if case .lost = oldState {
                // Already in lost state, don't repeat haptic
            } else {
                hapticGenerator.impactOccurred()
            }
        case .failed:
            // Show the failed sheet instead of toast
            showTrackingRecoveryToast = false
            showTrackingFailedSheet = true
            // Strong haptic for failure
            let errorHaptic = UINotificationFeedbackGenerator()
            errorHaptic.notificationOccurred(.error)
        }

        print("[VideoCaptureViewModel] Tracking recovery state: \(newState)")
    }

    /// Prepare haptic generators to avoid delay on first use
    private func prepareHaptics() {
        hapticGenerator.prepare()
        selectionHaptic.prepare()
    }

    // MARK: - Public Methods

    /// Start the AR session (call when view appears)
    func onViewAppear() {
        sessionManager.startSession()
        print("[VideoCaptureViewModel] View appeared, starting AR session")
    }

    /// Clean up when view disappears
    func onViewDisappear() {
        if recordingState == .recording {
            // Cancel recording if user leaves during recording
            cancelRecording()
        }
        // Don't stop AR session here - let coordinator manage lifecycle
        print("[VideoCaptureViewModel] View disappeared")
    }

    /// Start video recording (AC1, AC6)
    /// Waits for AR ready state if not already ready
    func startRecording() {
        guard recordingState == .idle else {
            print("[VideoCaptureViewModel] Cannot start - already in state: \(recordingState)")
            return
        }

        if !isARReady {
            // Wait for AR session to be ready
            recordingState = .waitingForAR
            print("[VideoCaptureViewModel] Waiting for AR session to be ready...")

            // Set up one-time observer for AR ready
            arReadyCancellable?.cancel()
            arReadyCancellable = sessionManager.$isReadyForCapture
                .filter { $0 }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.beginRecording()
                }
            return
        }

        beginRecording()
    }

    /// Actually begin recording after AR is ready
    private func beginRecording() {
        // Create video capture service
        videoCapture = AIVideoCapture()

        // Use Task since startRecording is now async
        Task {
            do {
                // Start persistence session (Story 2.6)
                try dataManager.startSession()
                dataManager.cleanupOldSessions(keepLatest: 3)

                try videoCapture?.prepare()
                try await videoCapture?.startRecording()

                // Trigger haptic feedback (AC1)
                hapticGenerator.impactOccurred()

                // Update state
                recordingState = .recording
                elapsedTime = 0
                isStopEnabled = false

                // Start timer for UI updates
                startTimer()

                // Setup tracking recovery observer (Story 6.7)
                setupTrackingRecoveryObserver()

                print("[VideoCaptureViewModel] Recording started with session: \(dataManager.currentSessionId ?? "unknown")")
            } catch {
                // Clean up on error - ensure timer is cancelled
                timerCancellable?.cancel()
                videoCapture = nil
                dataManager.cancelSession()
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                recordingState = .idle
                print("[VideoCaptureViewModel] Failed to start recording: \(error)")
            }
        }
    }

    /// Stop video recording (AC5)
    func stopRecording() {
        guard recordingState == .recording else {
            print("[VideoCaptureViewModel] Cannot stop - not recording")
            return
        }

        guard elapsedTime >= Self.minimumDuration else {
            print("[VideoCaptureViewModel] Cannot stop - minimum duration not reached")
            return
        }

        // Trigger haptic feedback (AC5)
        hapticGenerator.impactOccurred()

        // Stop the timer
        timerCancellable?.cancel()

        // Update state
        recordingState = .stopped
        print("[VideoCaptureViewModel] Recording stopped, starting finalization...")

        // Start watchdog timer - if still in .stopped state after 60s, force error
        startSaveWatchdog()

        // Stop video recording asynchronously
        Task {
            await finalizeRecording()
        }
    }

    /// Watchdog timer to prevent infinite loading - fires after 60 seconds
    private var watchdogTask: Task<Void, Never>?

    private func startSaveWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                // If we're still in .stopped state, something went wrong
                if self.recordingState == .stopped && !self.isRecordingFinalized {
                    print("[VideoCaptureViewModel] WATCHDOG: Save timeout after 60s, forcing error state")
                    self.errorMessage = "Video save timed out. Please try again."
                    self.recordingState = .idle
                }
            } catch {
                // Task was cancelled (normal completion path)
                print("[VideoCaptureViewModel] WATCHDOG: Cancelled (normal)")
            }
        }
    }

    private func cancelWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// Cancel recording and clean up
    func cancelRecording() {
        timerCancellable?.cancel()
        videoCapture?.cancelRecording()
        dataManager.cancelSession()

        recordingState = .idle
        elapsedTime = 0
        isStopEnabled = false
        captureData = nil
        isRecordingFinalized = false

        print("[VideoCaptureViewModel] Recording cancelled")
    }

    /// Get the data manager for passing to photo capture (Story 2.6)
    func getCaptureDataManager() -> AICaptureDataManager {
        return dataManager
    }

    // MARK: - Tracking Recovery Actions (Story 6.7)

    /// Save partial scan data when tracking fails
    /// Per Story 6.7 - Task 6.1, 6.3
    func savePartialAndContinue() {
        // Stop the timer
        timerCancellable?.cancel()
        trackingRecoveryCancellable?.cancel()

        // Stop video recording
        Task {
            await finalizePartialRecording()
        }
    }

    /// Restart capture when tracking fails
    /// Per Story 6.7 - Task 6.4
    func restartCapture() {
        // Stop the timer
        timerCancellable?.cancel()
        trackingRecoveryCancellable?.cancel()

        // Cancel video recording
        videoCapture?.cancelRecording()

        // Discard session
        dataManager.discardSession()

        // Reset state
        recordingState = .idle
        elapsedTime = 0
        isStopEnabled = false
        captureData = nil
        isRecordingFinalized = false
        showTrackingFailedSheet = false
        showTrackingRecoveryToast = false
        trackingRecoveryState = .normal

        // Stop AR session
        sessionManager.stopSession()

        print("[VideoCaptureViewModel] Capture restarted due to tracking failure")
    }

    /// Finalize partial recording when tracking fails
    private func finalizePartialRecording() async {
        guard let videoCapture = videoCapture else {
            errorMessage = "Video capture not available"
            return
        }

        // Update state
        await MainActor.run {
            recordingState = .stopped
            showTrackingFailedSheet = false
        }

        do {
            // Stop recording and get video URL
            let tempVideoURL = try await videoCapture.stopRecording()

            // Export pose data from AR session
            let poseData = sessionManager.exportPoseData()
            exportedPoseData = poseData

            // Save poses first
            _ = try dataManager.savePoseDataFromExport(poseData)

            // Persist video to session directory
            _ = try await dataManager.saveVideo(from: tempVideoURL)

            // Use savePartialSession() to properly finalize partial capture (H2 fix)
            // Per Story 6.7 - Task 6.1: Call AICaptureDataManager.savePartialSession()
            let coverageState = AICoverageState(capturedZones: [])
            captureData = try dataManager.savePartialSession(
                videoDuration: elapsedTime,
                photoCount: 0,
                qualityMetrics: nil,
                coverageState: coverageState
            )

            // Signal that recording is finalized
            await MainActor.run {
                isRecordingFinalized = true
            }

            let poseCount = poseData["poseCount"] as? Int ?? 0
            print("[VideoCaptureViewModel] Partial recording finalized via savePartialSession - poses: \(poseCount)")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save partial recording: \(error.localizedDescription)"
                recordingState = .idle
            }
            print("[VideoCaptureViewModel] Failed to finalize partial recording: \(error)")
        }
    }

    /// Get last good pose for guidance display
    func getLastGoodPose() -> AIPose? {
        return sessionManager.getLastGoodPose()
    }

    /// Update zoom level (AC3)
    /// - Parameter newZoom: The new zoom factor (clamped to 0.5-2.0)
    func updateZoom(_ newZoom: CGFloat) {
        // Clamp to valid range per FR11
        let clampedZoom = min(max(newZoom, 0.5), 2.0)

        // Only update if changed significantly
        if abs(clampedZoom - zoomLevel) > 0.01 {
            zoomLevel = clampedZoom

            // Update AR session manager for per-pose tracking (Story 2.1 integration)
            sessionManager.setZoomFactor(clampedZoom)

            // Apply zoom to video capture device
            videoCapture?.setZoom(clampedZoom)

            // Selection haptic for zoom change
            selectionHaptic.selectionChanged()

            print("[VideoCaptureViewModel] Zoom updated to: \(clampedZoom)")
        }
    }

    // MARK: - Private Methods

    /// Start the elapsed time timer
    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.recordingState == .recording else { return }
                self.elapsedTime += 0.1

                // Enable stop after minimum duration (AC2)
                if self.elapsedTime >= Self.minimumDuration && !self.isStopEnabled {
                    self.isStopEnabled = true
                    print("[VideoCaptureViewModel] Minimum duration reached, stop enabled")
                }

                // Auto-stop at maximum duration (AC4)
                if self.elapsedTime >= Self.maximumDuration {
                    self.showMaxDurationToast = true
                    self.stopRecording()
                    print("[VideoCaptureViewModel] Maximum duration reached, auto-stopping")
                }
            }
    }

    /// Finalize recording and prepare capture data
    /// Has overall timeout protection to prevent infinite hangs
    private func finalizeRecording() async {
        guard let videoCapture = videoCapture else {
            print("[VideoCaptureViewModel] ERROR: Video capture not available")
            errorMessage = "Video capture not available"
            recordingState = .idle
            return
        }

        print("[VideoCaptureViewModel] Starting finalizeRecording...")

        do {
            // Overall timeout for entire finalization process (45 seconds)
            let result = try await withOverallTimeout(seconds: 45) {
                // Step 1: Stop recording and get video URL
                print("[VideoCaptureViewModel] Step 1: Stopping video recording...")
                let tempVideoURL = try await videoCapture.stopRecording()
                print("[VideoCaptureViewModel] Step 1 complete: Got temp URL \(tempVideoURL.lastPathComponent)")

                // Step 2: Export pose data from AR session
                print("[VideoCaptureViewModel] Step 2: Exporting pose data...")
                let poseData = await MainActor.run { self.sessionManager.exportPoseData() }
                let poseCount = poseData["poseCount"] as? Int ?? 0
                print("[VideoCaptureViewModel] Step 2 complete: Exported \(poseCount) poses")

                // Step 3: Save poses FIRST (smaller, faster)
                print("[VideoCaptureViewModel] Step 3: Saving pose data...")
                _ = try self.dataManager.savePoseDataFromExport(poseData)
                print("[VideoCaptureViewModel] Step 3 complete: Pose data saved")

                // Step 4: Persist video to session directory
                print("[VideoCaptureViewModel] Step 4: Saving video to session directory...")
                let persistedVideoURL = try await self.dataManager.saveVideo(from: tempVideoURL)
                print("[VideoCaptureViewModel] Step 4 complete: Video saved to \(persistedVideoURL.lastPathComponent)")

                return (persistedVideoURL, poseData)
            }

            let (persistedVideoURL, poseData) = result

            // Create capture session data with persisted URLs
            captureData = AICaptureSessionData(
                videoURL: persistedVideoURL,
                photos: [], // Will be filled in photo capture phase
                metadata: AICaptureMetadata(
                    deviceModel: UIDevice.current.model,
                    osVersion: UIDevice.current.systemVersion,
                    captureDate: Date(),
                    videoDuration: elapsedTime,
                    photoCount: 0,
                    averageLighting: nil
                )
            )

            // Cancel watchdog since we succeeded
            cancelWatchdog()

            // Signal that recording is finalized and ready for navigation
            isRecordingFinalized = true

            let poseCount = poseData["poseCount"] as? Int ?? 0
            print("[VideoCaptureViewModel] Recording finalized successfully - video: \(persistedVideoURL.lastPathComponent), poses: \(poseCount)")
        } catch {
            print("[VideoCaptureViewModel] ERROR in finalizeRecording: \(error)")
            // Cancel watchdog
            cancelWatchdog()
            // Direct property access since we're @MainActor
            errorMessage = "Failed to save recording: \(error.localizedDescription)"
            recordingState = .idle
            print("[VideoCaptureViewModel] State reset to idle, errorMessage set")
        }
    }

    /// Execute an async operation with timeout protection
    private func withOverallTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "VideoCaptureViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Operation timed out after \(Int(seconds)) seconds"
                ])
            }

            guard let result = try await group.next() else {
                throw NSError(domain: "VideoCaptureViewModel", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Unexpected error during finalization"
                ])
            }
            group.cancelAll()
            return result
        }
    }

    /// Cancel the finalization process (called from UI if user wants to abort)
    func cancelFinalization() {
        print("[VideoCaptureViewModel] User cancelled finalization")
        videoCapture?.cancelRecording()
        errorMessage = nil
        recordingState = .idle
        captureData = nil
        isRecordingFinalized = false
    }

    // MARK: - Computed Properties

    /// Formatted elapsed time string (M:SS)
    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Progress toward minimum duration (0.0 to 1.0)
    var minimumDurationProgress: Double {
        min(elapsedTime / Self.minimumDuration, 1.0)
    }

    /// Whether the start button should be enabled
    var canStartRecording: Bool {
        recordingState == .idle
    }

    /// Whether currently in pre-recording state
    var isPreRecording: Bool {
        recordingState == .idle || recordingState == .waitingForAR
    }

    /// Status text for pre-recording state
    var preRecordingStatusText: String {
        switch recordingState {
        case .waitingForAR:
            return "Initializing camera..."
        case .idle:
            return isARReady ? "Position yourself in a corner of the kitchen" : "Initializing camera..."
        default:
            return ""
        }
    }
}
