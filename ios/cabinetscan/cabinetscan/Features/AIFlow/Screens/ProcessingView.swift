//
//  ProcessingView.swift
//  cabinetscan
//
//  Created for Story 3.8: Processing Pipeline Orchestration
//  Extended for Story 3.9: Performance Validation
//  Per UX Spec Section 3.4
//

import SwiftUI

// MARK: - Processing View (Task 9)

/// Displays processing progress during AI pipeline execution.
///
/// **UX Spec (Section 3.4):**
/// - Showroom logo at top (80pt)
/// - Spinner with continuous rotation (60pt)
/// - "Analyzing your kitchen..." title
/// - Progress bar with percentage
/// - Stage description caption
/// - Cancel link (after 5 seconds)
/// - Error state with retry option
struct ProcessingView: View {

    // MARK: - Dependencies

    @ObservedObject var orchestrator: AIPipelineOrchestrator

    /// Showroom logo URL (optional)
    let showroomLogoURL: URL?

    /// Callback when processing completes successfully
    let onComplete: (AIPipelineResult) -> Void

    /// Callback when user cancels
    let onCancel: () -> Void

    /// Callback when user wants to retry after error
    let onRetry: () -> Void

    /// Callback when user wants to start over after error
    let onStartOver: () -> Void

    /// Callback when manual calibration is needed (AC7)
    let onNeedManualCalibration: ((ManualCalibrationInput) -> Void)?

    /// Coordinator for timeout data preservation (Story 6.8)
    weak var coordinator: AIFlowCoordinator?

    // MARK: - State

    /// Whether cancel button is visible (shown after 5 seconds)
    @State private var showCancelButton = false

    /// Whether to show cancel confirmation (shown if progress > 50%)
    @State private var showCancelConfirmation = false

    /// Timer for showing cancel button
    @State private var cancelButtonTimer: Timer?

    /// Last announced progress percentage for VoiceOver (Story 6.5)
    @State private var lastAnnouncedProgress: Int = 0

    /// Last announced phase for VoiceOver (Story 6.5)
    @State private var lastAnnouncedPhase: AIPipelinePhase = .frameExtraction

    /// Reduce Motion environment (Story 6.5)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Timeout State (Story 6.8 Task 5)

    /// Timeout manager for 60s/90s warnings
    @StateObject private var timeoutManager = ProcessingTimeoutManager()

    /// Whether to show timeout warning sheet (Task 5.2)
    @State private var showTimeoutWarningSheet = false

    /// Current timeout warning level (Task 5.3)
    @State private var timeoutWarningLevel: TimeoutWarningLevel?

    // MARK: - Constants

    private static let cancelButtonDelay: TimeInterval = 5.0
    private static let cancelConfirmationThreshold: Double = 0.50
    /// NFR2: Processing time warning threshold (15 seconds)
    private static let processingTimeWarningThresholdMs = 15000

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                // Main content based on state
                switch orchestrator.state {
                case .running:
                    processingContent

                case .awaitingManualCalibration(let input):
                    // AC7: Show waiting state and notify coordinator for manual calibration
                    awaitingManualCalibrationContent
                        .onAppear {
                            // Notify coordinator to present ManualCalibrationView
                            onNeedManualCalibration?(input)
                        }

                case .failed(let error):
                    errorContent(error: error)

                case .cancelled:
                    cancelledContent

                case .completed:
                    // Should transition away, but show complete state briefly
                    completedContent

                default:
                    processingContent
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
        .onAppear {
            startCancelButtonTimer()
            // Story 6.8 Task 5.4: Start timeout monitoring
            timeoutManager.startMonitoring()
        }
        .onDisappear {
            cancelButtonTimer?.invalidate()
            // Story 6.8: Stop timeout monitoring
            timeoutManager.stopMonitoring()
        }
        // Issue #3 fix: Monitor state changes to call onComplete when processing finishes
        .onChange(of: orchestrator.state) { _, newState in
            if case .completed = newState {
                // Story 6.8 Edge case #2: Auto-dismiss timeout sheet if processing completes
                if showTimeoutWarningSheet {
                    showTimeoutWarningSheet = false
                    timeoutWarningLevel = nil
                }
                // Stop timeout monitoring on completion
                timeoutManager.stopMonitoring()

                // Story 6.5: Announce completion for VoiceOver
                announceForVoiceOver("Processing complete")
                // Brief delay to show the complete UI, then notify coordinator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let result = orchestrator.result {
                        onComplete(result)
                    }
                }
            } else if case .failed(let error) = newState {
                // Story 6.8: Stop timeout monitoring on failure
                timeoutManager.stopMonitoring()
                // Story 6.5: Announce error for VoiceOver
                announceForVoiceOver("Processing failed. \(error.userFriendlyMessage)")
            } else if case .cancelled = newState {
                // Story 6.8: Stop timeout monitoring on cancellation
                timeoutManager.stopMonitoring()
                // Story 6.5: Announce cancellation for VoiceOver
                announceForVoiceOver("Processing cancelled")
            }
        }
        // Story 6.5: Announce progress at 20% intervals for VoiceOver
        .onChange(of: orchestrator.progress) { _, newProgress in
            announceProgressIfNeeded(newProgress)
        }
        // Story 6.5: Announce phase transitions for VoiceOver
        .onChange(of: orchestrator.currentPhase) { oldPhase, newPhase in
            if newPhase != oldPhase {
                lastAnnouncedPhase = newPhase
                announceForVoiceOver(newPhase.accessibilityDescription)
            }
        }
        // Story 6.8 Task 5.4: Monitor timeout state changes
        .onChange(of: timeoutManager.timeoutState) { _, newState in
            handleTimeoutStateChange(newState)
        }
        // Story 6.8 Task 5.5: Timeout warning sheet (ADR-5: sheet overlay)
        .sheet(isPresented: $showTimeoutWarningSheet) {
            if let level = timeoutWarningLevel {
                TimeoutWarningSheet(
                    level: level,
                    onContinueWaiting: handleContinueWaiting,
                    onRetry: handleTimeoutRetry,
                    onCancel: handleTimeoutCancel
                )
                .presentationDetents([.medium])
            }
        }
        .confirmationDialog(
            "Cancel Processing?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Processing", role: .cancel) { }
            Button("Cancel", role: .destructive) {
                orchestrator.cancel()
                onCancel()
            }
        } message: {
            Text("Processing is \(Int(orchestrator.progress * 100))% complete. Cancel anyway?")
        }
    }

    // MARK: - Processing Content (Task 9.1-9.7)

    private var processingContent: some View {
        VStack(spacing: 24) {
            // Task 9.2: Showroom logo (80pt)
            if let logoURL = showroomLogoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                    case .failure, .empty:
                        logoPlaceholder
                    @unknown default:
                        logoPlaceholder
                    }
                }
            } else {
                logoPlaceholder
            }

            // Task 9.3: Spinner with continuous rotation (60pt)
            SpinnerView()
                .frame(width: 60, height: 60)

            // Task 9.4: Title
            Text("Analyzing your kitchen...")
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            // Task 9.5: Progress bar with percentage
            progressBar

            // Task 9.6: Stage description caption
            // War Room Enhancement: Show "Almost done..." only at 98%+ to reduce anxiety
            Text(stageDisplayText)
                .font(.caption)
                .foregroundColor(.secondary)

            // Task 9.10: Estimated time remaining
            // War Room Enhancement: Show static ETA before 20%, then calculated ETA after
            if orchestrator.progress <= 0.20 {
                Text("Usually takes 10-15 seconds")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let eta = orchestrator.estimatedTimeRemaining {
                Text("About \(formatTimeRemaining(eta)) remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Task 9.7: Cancel link (after 5 seconds delay)
            if showCancelButton {
                Button("Cancel") {
                    handleCancelTap()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Progress Bar (Task 9.5, 9.9)

    private var progressBar: some View {
        VStack(spacing: 8) {
            // Progress bar with smooth animation (Task 9.9)
            // Story 6.5: Respect Reduce Motion preference
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(
                            width: max(0, geometry.size.width * orchestrator.progress),
                            height: 8
                        )
                        .animation(reduceMotion ? .none : .linear(duration: 0.3), value: orchestrator.progress)
                }
            }
            .frame(height: 8)
            // Story 6.5: Accessibility for progress bar
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Processing progress")
            .accessibilityValue("\(Int(orchestrator.progress * 100)) percent")

            // Percentage text
            Text("\(Int(orchestrator.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .accessibilityHidden(true) // Already announced via progress bar
        }
    }

    // MARK: - Error Content (Task 9.8)

    private func errorContent(error: AIPipelineError) -> some View {
        VStack(spacing: 24) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            // Title
            Text("Processing Failed")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)

            // Error message (user-friendly)
            Text(error.userFriendlyMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                // Retry button (if retryable)
                if error.isRetryable {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(10)
                    }
                }

                // Start over button
                Button(action: onStartOver) {
                    Text("Start Over")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Awaiting Manual Calibration Content (AC7)

    private var awaitingManualCalibrationContent: some View {
        VStack(spacing: 24) {
            // Showroom logo
            if let logoURL = showroomLogoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                    case .failure, .empty:
                        logoPlaceholder
                    @unknown default:
                        logoPlaceholder
                    }
                }
            } else {
                logoPlaceholder
            }

            // Info icon
            Image(systemName: "ruler.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            // Title
            Text("Manual Calibration Needed")
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            // Description
            Text("We couldn't automatically determine the scale. Please help us calibrate by selecting a reference object.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Loading indicator while transitioning
            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Cancelled Content

    private var cancelledContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Processing Cancelled")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)

            Button(action: onStartOver) {
                Text("Start Over")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Completed Content

    private var completedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Processing Complete")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)

            // Story 3.9 Task 10.3: Show warning if processing exceeded 15s (DEBUG only)
            #if DEBUG
            if let result = orchestrator.result, result.processingTimeMs > Self.processingTimeWarningThresholdMs {
                Text("Processing took longer than expected (\(result.processingTimeMs / 1000)s)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            #endif

            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Logo Placeholder

    private var logoPlaceholder: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 40))
            .foregroundColor(.secondary)
            .frame(height: 80)
    }

    // MARK: - Computed Properties

    /// Stage display text with progress-aware "Almost done..." messaging
    /// War Room Enhancement: Only show "Almost done..." at 98%+ to reduce user anxiety
    private var stageDisplayText: String {
        if orchestrator.progress >= 0.98 {
            return "Almost done..."
        }
        return orchestrator.currentPhase.displayText
    }

    // MARK: - Helpers

    private func startCancelButtonTimer() {
        // Story 6.5: Capture reduceMotion preference for Timer callback
        let shouldAnimate = !reduceMotion
        cancelButtonTimer = Timer.scheduledTimer(
            withTimeInterval: Self.cancelButtonDelay,
            repeats: false
        ) { _ in
            if shouldAnimate {
                withAnimation {
                    showCancelButton = true
                }
            } else {
                showCancelButton = true
            }
        }
    }

    private func handleCancelTap() {
        // Task 6.6: Show confirmation if progress > 50%
        if orchestrator.progress > Self.cancelConfirmationThreshold {
            showCancelConfirmation = true
        } else {
            orchestrator.cancel()
            onCancel()
        }
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) seconds"
        } else {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            if secs == 0 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s")"
            } else {
                return "\(minutes):\(String(format: "%02d", secs))"
            }
        }
    }

    // MARK: - Timeout Handlers (Story 6.8 Task 5)

    /// Handle timeout state changes (Task 5.4)
    private func handleTimeoutStateChange(_ state: TimeoutState) {
        switch state {
        case .normal:
            // Don't auto-close sheet - user action required
            break

        case .warning:
            // Task 5.5: Show 60s warning sheet
            if !showTimeoutWarningSheet {
                timeoutWarningLevel = .warning
                showTimeoutWarningSheet = true
                // Story 6.5: Announce for VoiceOver
                announceForVoiceOver("Processing taking longer than expected")
            }

        case .critical:
            // Task 5.5: Update to critical warning
            // Edge case #1: Show critical even if warning was dismissed
            timeoutWarningLevel = .critical
            if !showTimeoutWarningSheet {
                showTimeoutWarningSheet = true
            }
            // Story 6.5: Announce for VoiceOver
            announceForVoiceOver("Processing may have encountered an issue")
        }
    }

    /// Handle "Continue Waiting" action (Task 5.8)
    private func handleContinueWaiting() {
        showTimeoutWarningSheet = false
        timeoutWarningLevel = nil
        timeoutManager.resetTimers()
    }

    /// Handle "Retry" action (Task 5.7)
    ///
    /// **Per Story 6.8 AC3:**
    /// Processing restarts from last checkpoint without re-capturing.
    private func handleTimeoutRetry() {
        showTimeoutWarningSheet = false
        timeoutWarningLevel = nil

        // Use coordinator for retry with checkpoint if available
        if let coordinator = coordinator {
            coordinator.setPipelineOrchestrator(orchestrator)
            _ = coordinator.onTimeoutRetry()
        } else {
            // Fallback to basic retry callback
            onRetry()
        }
    }

    /// Handle "Cancel" from timeout sheet (Task 5.6)
    ///
    /// **Per Story 6.8 AC4:**
    /// Captured data is saved for potential later use.
    ///
    /// **Per Dev Notes Edge Case #3:**
    /// Wait for any pending checkpoint save before cancelling.
    private func handleTimeoutCancel() {
        showTimeoutWarningSheet = false
        timeoutWarningLevel = nil

        // Save data for later recovery before cancelling
        if let coordinator = coordinator {
            coordinator.onTimeoutCancel(checkpoint: orchestrator.lastCheckpoint)
        }

        orchestrator.cancel()
        onCancel()
    }

    // MARK: - Accessibility Helpers (Story 6.5)

    /// Announce message for VoiceOver users
    private func announceForVoiceOver(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Announce progress at 20% intervals for VoiceOver users
    private func announceProgressIfNeeded(_ progress: Double) {
        let currentPercent = Int(progress * 100)
        // Announce at 20%, 40%, 60%, 80%, 100%
        let milestones = [20, 40, 60, 80, 100]

        for milestone in milestones {
            if currentPercent >= milestone && lastAnnouncedProgress < milestone {
                lastAnnouncedProgress = milestone
                announceForVoiceOver("Processing \(milestone) percent complete")
                break
            }
        }
    }
}

// MARK: - Spinner View

/// Custom spinner with continuous rotation animation.
/// Story 6.5: Respects Reduce Motion accessibility preference
private struct SpinnerView: View {
    @State private var isAnimating = false
    @State private var opacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Static spinner with pulsing opacity for Reduce Motion users
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .opacity(opacity)
                    .onAppear {
                        // Gentle opacity pulse instead of rotation
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            opacity = 0.5
                        }
                    }
            } else {
                // Normal rotating spinner
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                    .onAppear {
                        isAnimating = true
                    }
            }
        }
        .accessibilityHidden(true) // Decorative element
    }
}

// MARK: - Preview

#if DEBUG
struct ProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        let coordinator = AIFlowCoordinator()
        return ProcessingView(
            orchestrator: AIPipelineOrchestrator(),
            showroomLogoURL: nil,
            onComplete: { _ in },
            onCancel: { },
            onRetry: { },
            onStartOver: { },
            onNeedManualCalibration: nil,
            coordinator: coordinator
        )
    }
}
#endif
