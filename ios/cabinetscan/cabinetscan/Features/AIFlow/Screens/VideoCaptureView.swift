//
//  VideoCaptureView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Video capture screen for AI flow.
/// Displays camera preview with recording controls, timer, zoom, and guidance overlays.
/// Per Story 2.2 & 2.3 - All Acceptance Criteria
struct VideoCaptureView: View {

    // MARK: - Timing Constants

    /// Toast auto-dismiss delay in nanoseconds (3 seconds)
    private static let toastDismissDelay: UInt64 = 3_000_000_000

    /// Zoom indicator auto-dismiss delay in nanoseconds (2 seconds)
    private static let zoomDismissDelay: UInt64 = 2_000_000_000

    // MARK: - Properties

    /// Callback when user wants to go back to intro
    let onBack: () -> Void

    /// Callback when recording is complete (includes video capture for session sharing)
    let onComplete: (AICaptureSessionData, AIVideoCapture?) -> Void

    /// View model for video capture state
    @StateObject private var viewModel: VideoCaptureViewModel

    /// View model for capture guidance (Story 2.3)
    @StateObject private var guidanceViewModel: CaptureGuidanceViewModel

    /// Whether zoom indicator is visible
    @State private var showZoomIndicator = false

    /// Current pinch gesture scale
    @GestureState private var pinchScale: CGFloat = 1.0

    /// Base zoom level before pinch
    @State private var baseZoom: CGFloat = 1.0

    /// Last announced time for periodic VoiceOver announcements (every 10s)
    @State private var lastAnnouncedTime: Int = 0

    /// Accessibility: Interval for periodic time announcements (10 seconds)
    private static let timeAnnouncementInterval: Int = 10

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Initialize with AR session manager, data manager, and callbacks
    /// - Parameters:
    ///   - sessionManager: The AR session manager for pose tracking
    ///   - dataManager: The capture data manager for persistence (Issue #7 fix - required)
    ///   - onBack: Callback when user taps back
    ///   - onComplete: Callback when recording completes with capture data and video capture
    init(
        sessionManager: AIARSessionManager,
        dataManager: AICaptureDataManager,
        onBack: @escaping () -> Void,
        onComplete: @escaping (AICaptureSessionData, AIVideoCapture?) -> Void
    ) {
        self.onBack = onBack
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager))
        _guidanceViewModel = StateObject(wrappedValue: CaptureGuidanceViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen)
            cameraPreviewLayer

            // Overlays based on state
            if viewModel.isPreRecording {
                preRecordingOverlay
            } else if viewModel.recordingState == .recording {
                recordingOverlay
            } else if viewModel.recordingState == .stopped {
                // Show saving overlay while finalizing recording
                savingOverlay
            }

            // Max duration toast
            if viewModel.showMaxDurationToast {
                maxDurationToast
            }

            // Tracking recovery toast (Story 6.7) - Use container for proper accessibility
            VStack {
                TrackingRecoveryToastContainer(
                    recoveryState: viewModel.trackingRecoveryState,
                    isVisible: $viewModel.showTrackingRecoveryToast
                )
                .padding(.top, 100)

                Spacer()
            }

            // Tracking lost overlay with guidance arrow (Story 6.7 - Task 3.5)
            TrackingLostOverlay(
                recoveryState: viewModel.trackingRecoveryState,
                lastGoodPose: viewModel.getLastGoodPose()
            )

            // Error overlay
            if let error = viewModel.errorMessage {
                errorOverlay(message: error)
            }
        }
        // Tracking failed sheet (Story 6.7)
        .sheet(isPresented: $viewModel.showTrackingFailedSheet) {
            TrackingFailedSheet(
                onSavePartial: { viewModel.savePartialAndContinue() },
                onRestart: { viewModel.restartCapture() }
            )
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.onViewAppear()
        }
        .onDisappear {
            viewModel.onViewDisappear()
            guidanceViewModel.stopGuidance()
        }
        .onChange(of: viewModel.isRecordingFinalized) { _, isFinalized in
            if isFinalized, let data = viewModel.captureData {
                guidanceViewModel.markScanCompleted()
                // Pass video capture to completion handler for session sharing with photo capture
                onComplete(data, viewModel.videoCapture)
            }
        }
        .onChange(of: viewModel.showMaxDurationToast) { _, show in
            if show {
                // Auto-dismiss toast after delay
                Task {
                    try? await Task.sleep(nanoseconds: Self.toastDismissDelay)
                    viewModel.showMaxDurationToast = false
                }
            }
        }
        .onChange(of: viewModel.recordingState) { oldState, newState in
            // Start/stop guidance based on recording state
            if newState == .recording && oldState != .recording {
                // Connect guidance to video capture for frame analysis
                guidanceViewModel.setVideoCapture(viewModel.videoCapture)
                guidanceViewModel.startGuidance()
                // Accessibility: Announce recording started
                announceForVoiceOver("Recording started")
            } else if newState != .recording && oldState == .recording {
                guidanceViewModel.stopGuidance()
                guidanceViewModel.setVideoCapture(nil)
                // Accessibility: Announce recording stopped
                if newState == .stopped {
                    announceForVoiceOver("Recording stopped, saving video")
                }
            }
        }
        .onChange(of: viewModel.elapsedTime) { _, newTime in
            // Process elapsed time for timed prompts
            guidanceViewModel.processElapsedTime(newTime)
            // Accessibility: Announce time periodically for VoiceOver users
            announceTimeIfNeeded(newTime)
        }
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreviewLayer: some View {
        ZStack {
            // Camera preview - zoom gesture only enabled during recording
            AIVideoCameraPreviewView(videoCapture: viewModel.videoCapture)
                .gesture(viewModel.recordingState == .recording ? zoomGesture : nil)

            // Loading overlay when camera not ready
            if !viewModel.isARReady && viewModel.isPreRecording {
                CameraLoadingOverlay(message: viewModel.preRecordingStatusText)
            }
        }
    }

    // MARK: - Pre-Recording Overlay (AC6)

    @ViewBuilder
    private var preRecordingOverlay: some View {
        VStack {
            // Top bar with back button
            HStack {
                Button {
                    viewModel.cancelRecording()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Returns to intro screen")

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 60)

            Spacer()

            // Guidance text
            if viewModel.isARReady {
                Text(viewModel.preRecordingStatusText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)
            }

            // Start recording button
            Button {
                viewModel.startRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                    Text("Start Recording")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
            }
            .disabled(!viewModel.isARReady && viewModel.recordingState != .waitingForAR)
            .opacity(viewModel.isARReady || viewModel.recordingState == .waitingForAR ? 1.0 : 0.5)
            .accessibilityLabel("Start Recording")
            .accessibilityHint(viewModel.isARReady ? "Starts video recording" : "Waiting for camera to initialize")
            .padding(.bottom, 50)
        }
    }

    // MARK: - Recording Overlay (AC1-AC5 from 2.2, AC1-AC6 from 2.3)

    @ViewBuilder
    private var recordingOverlay: some View {
        ZStack {
            // Corner indicators at corners (Story 2.3 - AC1)
            CornerIndicators(
                capturedZones: guidanceViewModel.capturedZones,
                showTooltip: guidanceViewModel.showCornerTooltip,
                onTooltipDismiss: { guidanceViewModel.dismissCornerTooltip() }
            )

            // Guidance arrows in center area (Story 2.3 - AC1)
            if let direction = guidanceViewModel.guidanceDirection {
                GuidanceArrows(direction: direction)
            }

            VStack {
                Spacer()

                // Guidance toast above control bar (Story 2.3 - AC2, AC3, AC4, AC5)
                if let toast = guidanceViewModel.currentToast {
                    GuidanceToastContainer(
                        toast: toast,
                        onDismiss: { guidanceViewModel.dismissToast() }
                    )
                    .padding(.bottom, 20)
                }

                // Bottom control bar
                bottomControlBar
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
    }

    /// Bottom control bar with timer, stop button, and zoom indicator
    @ViewBuilder
    private var bottomControlBar: some View {
        HStack(alignment: .center) {
            // Timer display with quality indicator (left)
            HStack(spacing: 8) {
                TimerDisplay(
                    seconds: viewModel.elapsedTime,
                    minimumReached: viewModel.isStopEnabled
                )

                // Quality state indicator (AC3 - shows yellow/red when quality issues)
                QualityIndicatorBadge(qualityState: guidanceViewModel.qualityState)

                // Minimum duration progress (only shown before 10s)
                if !viewModel.isStopEnabled {
                    MinimumDurationProgress(progress: viewModel.minimumDurationProgress)
                }
            }

            Spacer()

            // Stop button (center)
            Button {
                viewModel.stopRecording()
            } label: {
                Text("STOP")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(viewModel.isStopEnabled ? Color.red : Color.gray)
                    .clipShape(Capsule())
            }
            .disabled(!viewModel.isStopEnabled)
            .accessibilityLabel(stopButtonAccessibilityLabel)
            .accessibilityHint(viewModel.isStopEnabled ? "Double tap to stop video recording" : "Recording must be at least 10 seconds")

            Spacer()

            // Zoom indicator (right)
            ZoomBadge(zoomLevel: viewModel.zoomLevel)

            // Floating zoom indicator (shows briefly on change)
            ZoomIndicator(zoomLevel: viewModel.zoomLevel, isVisible: $showZoomIndicator)
                .offset(y: -60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Zoom Gesture (AC3)

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onChanged { value in
                let newZoom = baseZoom * value
                viewModel.updateZoom(newZoom)
                showZoomIndicator = true
            }
            .onEnded { value in
                baseZoom = viewModel.zoomLevel
                // Schedule hide after gesture ends
                Task {
                    try? await Task.sleep(nanoseconds: Self.zoomDismissDelay)
                    showZoomIndicator = false
                }
            }
    }

    // MARK: - Saving Overlay (shown while finalizing recording)

    @ViewBuilder
    private var savingOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Saving video...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
    }

    // MARK: - Toast & Error Views

    @ViewBuilder
    private var maxDurationToast: some View {
        VStack {
            Text("Maximum recording time reached")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.orange)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.top, 100)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        // Story 6.5: Respect Reduce Motion preference
        .animation(reduceMotion ? .none : .spring(response: 0.3), value: viewModel.showMaxDurationToast)
    }

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Accessibility Helpers

    /// Dynamic accessibility label for stop button including elapsed time
    private var stopButtonAccessibilityLabel: String {
        let totalSeconds = Int(viewModel.elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "Stop recording, \(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s") recorded"
        } else {
            return "Stop recording, \(seconds) second\(seconds == 1 ? "" : "s") recorded"
        }
    }

    /// Announce message for VoiceOver users
    private func announceForVoiceOver(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Announce time periodically for VoiceOver users (every 10 seconds)
    private func announceTimeIfNeeded(_ time: TimeInterval) {
        let currentSeconds = Int(time)
        let intervalSeconds = Self.timeAnnouncementInterval

        // Check if we've crossed a 10-second boundary
        if currentSeconds > 0 && currentSeconds % intervalSeconds == 0 && currentSeconds != lastAnnouncedTime {
            lastAnnouncedTime = currentSeconds
            let minutes = currentSeconds / 60
            let seconds = currentSeconds % 60

            let timeString: String
            if minutes > 0 {
                timeString = "\(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s")"
            } else {
                timeString = "\(seconds) seconds"
            }

            announceForVoiceOver("\(timeString) recorded")
        }
    }
}

// MARK: - Preview

#Preview("Pre-Recording") {
    VideoCaptureView(
        sessionManager: AIARSessionManager(),
        dataManager: AICaptureDataManager(),
        onBack: { print("Back") },
        onComplete: { _, _ in print("Complete") }
    )
}
