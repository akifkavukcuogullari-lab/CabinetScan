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

        do {
            // Start persistence session (Story 2.6)
            try dataManager.startSession()
            dataManager.cleanupOldSessions(keepLatest: 3)

            try videoCapture?.prepare()
            try videoCapture?.startRecording()

            // Trigger haptic feedback (AC1)
            hapticGenerator.impactOccurred()

            // Update state
            recordingState = .recording
            elapsedTime = 0
            isStopEnabled = false

            // Start timer for UI updates
            startTimer()

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

        // Stop video recording asynchronously
        Task {
            await finalizeRecording()
        }
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
    private func finalizeRecording() async {
        guard let videoCapture = videoCapture else {
            errorMessage = "Video capture not available"
            return
        }

        do {
            // Stop recording and get video URL
            let tempVideoURL = try await videoCapture.stopRecording()

            // Export pose data from AR session
            let poseData = sessionManager.exportPoseData()
            exportedPoseData = poseData

            // Issue #5 fix: Save poses FIRST (smaller, faster) to minimize
            // window for inconsistent state if app crashes between operations
            _ = try dataManager.savePoseDataFromExport(poseData)

            // Persist video to session directory (Story 2.6)
            let persistedVideoURL = try await dataManager.saveVideo(from: tempVideoURL)

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

            // Signal that recording is finalized and ready for navigation
            isRecordingFinalized = true

            let poseCount = poseData["poseCount"] as? Int ?? 0
            print("[VideoCaptureViewModel] Recording finalized and persisted - video: \(persistedVideoURL.lastPathComponent), poses: \(poseCount)")
        } catch {
            await MainActor.run {
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
                recordingState = .idle
            }
            print("[VideoCaptureViewModel] Failed to finalize recording: \(error)")
        }
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
