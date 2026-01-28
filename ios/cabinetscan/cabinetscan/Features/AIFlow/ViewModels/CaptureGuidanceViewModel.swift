//
//  CaptureGuidanceViewModel.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import Combine
import AVFoundation

// MARK: - Guidance Preferences (ADR-005)

/// User preferences for capture guidance.
/// Stores flags like "has completed scan" to reduce guidance for repeat users.
/// Per Story 2.3 - Task 10, ADR-005
class GuidancePreferences {
    /// UserDefaults key for completed scan flag
    private static let hasCompletedScanKey = "ai_flow_has_completed_scan"

    /// UserDefaults key for tooltip shown flag
    private static let hasShownCornerTooltipKey = "ai_flow_has_shown_corner_tooltip"

    /// Whether user has completed at least one successful scan
    static var hasCompletedScan: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedScanKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedScanKey) }
    }

    /// Whether the corner indicator tooltip has been shown
    static var hasShownCornerTooltip: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownCornerTooltipKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownCornerTooltipKey) }
    }

    /// Reset all preferences (for testing)
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: hasCompletedScanKey)
        UserDefaults.standard.removeObject(forKey: hasShownCornerTooltipKey)
    }
}

// MARK: - Timed Prompt Phase

/// Phases for timed guidance prompts (first-time users only)
/// Per Story 2.3 - Task 9.2
private enum TimedPromptPhase: CaseIterable {
    case moveSlowly       // 0-10s
    case pointAtFloor     // 10-20s
    case pointAtCeiling   // 20-30s
    case moveCloser       // 30-45s
    case keepGoing        // 45s+

    var timeRange: ClosedRange<TimeInterval> {
        switch self {
        case .moveSlowly: return 0...10
        case .pointAtFloor: return 10...20
        case .pointAtCeiling: return 20...30
        case .moveCloser: return 30...45
        case .keepGoing: return 45...Double.infinity
        }
    }

    var toastMessage: GuidanceToastMessage {
        switch self {
        case .moveSlowly: return .moveSlowly
        case .pointAtFloor: return .pointAtFloor
        case .pointAtCeiling: return .pointAtCeiling
        case .moveCloser: return .moveCloser
        case .keepGoing: return .keepGoing
        }
    }

    /// Get phase for elapsed time
    static func phase(for time: TimeInterval) -> TimedPromptPhase? {
        for phase in allCases {
            if phase.timeRange.contains(time) {
                return phase
            }
        }
        return nil
    }
}

// MARK: - Capture Guidance ViewModel

/// Manages capture guidance state and coordinates toast display.
/// Per Story 2.3 - Task 7
///
/// **Responsibilities:**
/// - Coordinates quality analyzer and coverage tracker
/// - Manages toast queue with priority and cooldown
/// - Handles timed prompts for first-time users
/// - Tracks whether to show corner tooltip
/// - Receives video frames for quality analysis via AIVideoCaptureFrameDelegate
@MainActor
class CaptureGuidanceViewModel: ObservableObject, AIVideoCaptureFrameDelegate {

    // MARK: - Published Properties

    /// Current toast to display (nil = no toast)
    @Published private(set) var currentToast: GuidanceToastMessage?

    /// Guidance direction for arrows (nil = no arrow)
    @Published private(set) var guidanceDirection: AIGuidanceDirection?

    /// Set of captured zones for corner indicators
    @Published private(set) var capturedZones: Set<AICaptureZone> = []

    /// Current quality state
    @Published private(set) var qualityState: AIQualityState = .acceptable

    /// Whether to show corner indicator tooltip
    @Published private(set) var showCornerTooltip: Bool = false

    // MARK: - Constants

    /// Cooldown between same toast type (10 seconds per user research)
    private let toastCooldown: TimeInterval = 10.0

    /// Duration before auto-dismissing toast (3 seconds)
    private let toastDuration: TimeInterval = 3.0

    // MARK: - Dependencies

    /// Quality analyzer service
    let qualityAnalyzer: AIQualityAnalyzer

    /// Capture guidance service (coverage + orientation)
    let captureGuidance: AICaptureGuidance

    /// AR session manager for pose data
    private weak var sessionManager: AIARSessionManager?

    // MARK: - State

    /// Whether guidance is currently active
    private var isActive = false

    /// Whether this is a first-time user (no completed scans)
    private var isFirstTimeUser: Bool

    /// Last shown time per toast ID (for cooldown)
    private var lastShownTime: [String: Date] = [:]

    /// Currently shown timed prompt phase
    private var currentTimedPhase: TimedPromptPhase?

    /// Subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(sessionManager: AIARSessionManager) {
        self.sessionManager = sessionManager
        self.qualityAnalyzer = AIQualityAnalyzer()
        self.captureGuidance = AICaptureGuidance()
        self.isFirstTimeUser = !GuidancePreferences.hasCompletedScan
        self.showCornerTooltip = !GuidancePreferences.hasShownCornerTooltip

        setupBindings()
        setupPoseSubscription()

        print("[CaptureGuidanceViewModel] Initialized - first time user: \(isFirstTimeUser)")
    }

    /// Subscribe to pose updates from AR session manager for coverage/orientation tracking
    private func setupPoseSubscription() {
        sessionManager?.poseUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (timestamp, pose) in
                guard let self = self, self.isActive else { return }
                self.captureGuidance.processPose(pose, timestamp: timestamp)
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupBindings() {
        // Quality state changes
        qualityAnalyzer.$qualityState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.qualityState = state
                self?.handleQualityStateChange(state)
            }
            .store(in: &cancellables)

        // Quality issues for toasts (now debounced by AIQualityAnalyzer)
        qualityAnalyzer.qualityIssuePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] issue in
                self?.handleQualityIssue(issue)
            }
            .store(in: &cancellables)

        // Quality recovery events (Story 2.4 - Task 6)
        qualityAnalyzer.qualityRecoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleQualityRecovery()
            }
            .store(in: &cancellables)

        // Coverage state changes
        captureGuidance.$coverageState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.capturedZones = state.capturedZones
            }
            .store(in: &cancellables)

        // Guidance direction changes
        captureGuidance.$guidanceDirection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] direction in
                self?.guidanceDirection = direction
            }
            .store(in: &cancellables)

        // Orientation issues for toasts
        captureGuidance.orientationIssuePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] issue in
                self?.handleOrientationIssue(issue)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Start guidance tracking
    func startGuidance() {
        guard !isActive else { return }
        isActive = true

        qualityAnalyzer.startAnalysis()
        captureGuidance.startTracking()

        // Reset state
        currentToast = nil
        lastShownTime = [:]
        currentTimedPhase = nil

        // Show tooltip for first-time users who haven't seen it
        if !GuidancePreferences.hasShownCornerTooltip {
            showCornerTooltip = true
        }

        print("[CaptureGuidanceViewModel] Guidance started")
    }

    /// Stop guidance tracking
    func stopGuidance() {
        guard isActive else { return }
        isActive = false

        qualityAnalyzer.stopAnalysis()
        captureGuidance.stopTracking()

        currentToast = nil

        print("[CaptureGuidanceViewModel] Guidance stopped")
    }

    /// Process a new pose from AR session
    /// - Parameters:
    ///   - pose: Camera pose
    ///   - timestamp: Pose timestamp
    func processPose(_ pose: AIPose, timestamp: TimeInterval) {
        guard isActive else { return }
        captureGuidance.processPose(pose, timestamp: timestamp)
    }

    /// Process elapsed recording time for timed prompts
    /// - Parameter elapsedTime: Seconds since recording started
    func processElapsedTime(_ elapsedTime: TimeInterval) {
        guard isActive else { return }
        guard isFirstTimeUser else { return } // Skip timed prompts for repeat users (AC6)

        // Determine current phase
        guard let phase = TimedPromptPhase.phase(for: elapsedTime) else { return }

        // Only show each phase once
        if phase != currentTimedPhase {
            currentTimedPhase = phase

            // Only show if no higher-priority toast is active
            if currentToast == nil || currentToast?.type == .info {
                showToast(phase.toastMessage)
            }
        }
    }

    /// Dismiss the current toast
    func dismissToast() {
        currentToast = nil
    }

    /// Dismiss the corner tooltip
    func dismissCornerTooltip() {
        showCornerTooltip = false
        GuidancePreferences.hasShownCornerTooltip = true
    }

    /// Mark scan as completed (for future reduced guidance)
    func markScanCompleted() {
        GuidancePreferences.hasCompletedScan = true
        print("[CaptureGuidanceViewModel] Scan marked as completed - future sessions will have reduced guidance")
    }

    /// Set video capture for frame analysis
    /// - Parameter videoCapture: The video capture instance to receive frames from
    func setVideoCapture(_ videoCapture: AIVideoCapture?) {
        videoCapture?.frameDelegate = self
    }

    // MARK: - AIVideoCaptureFrameDelegate

    nonisolated func videoCapture(_ capture: AIVideoCapture, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
        // Forward to quality analyzer (runs on its own analysis queue)
        Task { @MainActor in
            qualityAnalyzer.processSampleBuffer(sampleBuffer)
        }
    }

    // MARK: - Toast Management

    /// Handle quality state changes
    private func handleQualityStateChange(_ state: AIQualityState) {
        // Quality state updates are handled via qualityIssuePublisher
        // This is for UI state binding only
    }

    /// Handle quality issues from analyzer (now debounced)
    private func handleQualityIssue(_ issue: AIQualityIssue) {
        let toast: GuidanceToastMessage

        switch issue {
        case .motionBlur:
            toast = .motionBlur
        case .tooDark:
            toast = .tooDark
        case .tooBright:
            // Overexposure is rare, use generic message
            toast = GuidanceToastMessage(
                id: "too_bright",
                message: "Move away from direct light",
                icon: "sun.max.fill",
                type: .warning
            )
        case .lowContrast:
            // Low contrast - scene might be too uniform
            toast = GuidanceToastMessage(
                id: "low_contrast",
                message: "Move to an area with more detail",
                icon: "circle.lefthalf.filled",
                type: .warning
            )
        }

        // Quality warnings always shown (AC6) but with cooldown
        // Note: Issues are now debounced by AIQualityAnalyzer (Story 2.4)
        // Toast only appears after 3+ consecutive bad frames
        showToastWithCooldown(toast)
    }

    /// Handle quality recovery (Story 2.4 - Task 6)
    /// Shows encouraging toast when quality improves after a bad state
    private func handleQualityRecovery() {
        guard isActive else { return }

        // Only show recovery toast if we haven't shown one recently
        let recoveryToast = GuidanceToastMessage(
            id: "quality_improved",
            message: "Looking good! Keep going",
            icon: "checkmark.circle.fill",
            type: .info
        )

        // Use cooldown to prevent spamming recovery toasts
        showToastWithCooldown(recoveryToast)
    }

    /// Handle orientation issues from guidance
    private func handleOrientationIssue(_ issue: AIOrientationIssue) {
        let toast: GuidanceToastMessage

        switch issue {
        case .pointingAtFloor:
            toast = .pointAtCabinetsFromFloor
        case .pointingAtCeiling:
            toast = .pointAtCabinetsFromCeiling
        }

        // Orientation warnings always shown but with cooldown
        showToastWithCooldown(toast)
    }

    /// Show a toast with cooldown check
    private func showToastWithCooldown(_ toast: GuidanceToastMessage) {
        guard shouldShowToast(toast) else { return }

        // Higher priority toasts replace lower priority
        if let current = currentToast {
            if toast.type.priority < current.type.priority {
                return // Don't replace higher priority toast
            }
        }

        showToast(toast)
    }

    /// Show a toast (updates last shown time)
    private func showToast(_ toast: GuidanceToastMessage) {
        currentToast = toast
        lastShownTime[toast.id] = Date()

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(toastDuration * 1_000_000_000))
            await MainActor.run {
                if self.currentToast?.id == toast.id {
                    self.currentToast = nil
                }
            }
        }
    }

    /// Check if toast should be shown (cooldown check)
    private func shouldShowToast(_ toast: GuidanceToastMessage) -> Bool {
        guard let lastTime = lastShownTime[toast.id] else {
            return true // Never shown
        }

        let elapsed = Date().timeIntervalSince(lastTime)
        return elapsed >= toastCooldown
    }
}
