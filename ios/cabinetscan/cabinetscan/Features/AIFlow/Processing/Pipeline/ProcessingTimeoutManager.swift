//
//  ProcessingTimeoutManager.swift
//  cabinetscan
//
//  Story 6.8: Error Recovery - Processing Timeout
//  Task 1: Timeout monitoring manager
//

import Foundation
import Combine

// MARK: - Timeout State (Task 1.2)

/// State of processing timeout monitoring.
///
/// **Per Story 6.8 AC1/AC2:**
/// - `.normal`: Processing within expected time
/// - `.warning(elapsed:)`: 60-second threshold reached (UX-22)
/// - `.critical(elapsed:)`: 90-second threshold reached
enum TimeoutState: Equatable {
    /// Processing is within expected time - no timeout
    case normal

    /// 60-second warning threshold reached (AC1)
    /// Associated value is elapsed time in seconds
    case warning(elapsed: TimeInterval)

    /// 90-second critical threshold reached (AC2)
    /// Associated value is elapsed time in seconds
    case critical(elapsed: TimeInterval)

    // MARK: - Computed Properties

    /// Whether this is the warning state
    var isWarning: Bool {
        if case .warning = self { return true }
        return false
    }

    /// Whether this is the critical state
    var isCritical: Bool {
        if case .critical = self { return true }
        return false
    }

    /// Whether timeout has occurred (warning or critical)
    var isTimeout: Bool {
        switch self {
        case .normal: return false
        case .warning, .critical: return true
        }
    }

    /// Elapsed time if in timeout state, nil otherwise
    var elapsedTime: TimeInterval? {
        switch self {
        case .normal:
            return nil
        case .warning(let elapsed), .critical(let elapsed):
            return elapsed
        }
    }

    // MARK: - Equatable

    static func == (lhs: TimeoutState, rhs: TimeoutState) -> Bool {
        switch (lhs, rhs) {
        case (.normal, .normal):
            return true
        case (.warning(let a), .warning(let b)):
            return a == b
        case (.critical(let a), .critical(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Processing Timeout Manager (Task 1)

/// Monitors processing duration and triggers timeout warnings.
///
/// **Per Story 6.8:**
/// - 60-second warning: "Processing is taking longer than expected" (AC1)
/// - 90-second critical: "Processing may have encountered an issue" (AC2)
///
/// **ADR-3:** Separate class following Story 6.7 pattern.
/// Orchestrator remains focused on pipeline logic.
///
/// **Usage:**
/// ```swift
/// @StateObject var timeoutManager = ProcessingTimeoutManager()
///
/// timeoutManager.startMonitoring()
/// // Observe timeoutManager.$timeoutState for changes
/// timeoutManager.stopMonitoring()
/// ```
@MainActor
final class ProcessingTimeoutManager: ObservableObject {

    // MARK: - Constants

    /// Default warning threshold (60 seconds per AC1)
    static let defaultWarningThreshold: TimeInterval = 60.0

    /// Default critical threshold (90 seconds per AC2)
    static let defaultCriticalThreshold: TimeInterval = 90.0

    // MARK: - Published Properties (Task 1.2)

    /// Current timeout state
    /// View subscribes to this via `$timeoutState` for UI updates
    @Published private(set) var timeoutState: TimeoutState = .normal

    // MARK: - Configuration

    /// Warning threshold in seconds (default: 60)
    let warningThreshold: TimeInterval

    /// Critical threshold in seconds (default: 90)
    let criticalThreshold: TimeInterval

    // MARK: - Private State

    /// Timer for warning threshold (Task 1.3)
    private var warningTimer: Timer?

    /// Timer for critical threshold (Task 1.4)
    private var criticalTimer: Timer?

    /// Whether monitoring is currently active
    private var isMonitoring = false

    /// Start time for elapsed calculation (since current timer cycle)
    private var startTime: Date?

    /// Cumulative elapsed time from previous timer cycles (before resets)
    /// Used to maintain accurate total elapsed time when "Continue Waiting" is pressed
    private var cumulativeElapsedTime: TimeInterval = 0

    // MARK: - Initialization

    /// Creates a timeout manager with default thresholds.
    init() {
        self.warningThreshold = Self.defaultWarningThreshold
        self.criticalThreshold = Self.defaultCriticalThreshold
    }

    /// Creates a timeout manager with custom thresholds (for testing).
    ///
    /// - Parameters:
    ///   - warningThreshold: Seconds before warning (default: 60)
    ///   - criticalThreshold: Seconds before critical (default: 90)
    init(warningThreshold: TimeInterval, criticalThreshold: TimeInterval) {
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    // MARK: - Public Methods (Task 1.6)

    /// Starts timeout monitoring.
    ///
    /// Schedules timers for warning (60s) and critical (90s) thresholds.
    /// Safe to call multiple times - cancels any existing timers first.
    func startMonitoring() {
        // Cancel any existing timers first (safe for multiple calls)
        stopTimersOnly()

        isMonitoring = true
        startTime = Date()
        cumulativeElapsedTime = 0  // Reset cumulative time on fresh start
        timeoutState = .normal

        // Task 1.3: Schedule warning timer (60 seconds)
        warningTimer = Timer.scheduledTimer(
            withTimeInterval: warningThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWarningTimeout()
            }
        }

        // Task 1.4: Schedule critical timer (90 seconds)
        criticalTimer = Timer.scheduledTimer(
            withTimeInterval: criticalThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleCriticalTimeout()
            }
        }
    }

    /// Stops timeout monitoring and resets state to normal.
    func stopMonitoring() {
        stopTimersOnly()
        isMonitoring = false
        startTime = nil
        cumulativeElapsedTime = 0
        timeoutState = .normal
    }

    /// Resets timers and restarts monitoring from scratch (Task 1.7).
    ///
    /// Called when user selects "Continue Waiting" to give more time.
    /// Resets state to normal and starts fresh timeout countdown.
    ///
    /// **Note:** Cumulative elapsed time is preserved so that when the next timeout
    /// occurs, the elapsed time reflects total wait time, not just time since reset.
    func resetTimers() {
        // Stop current timers
        stopTimersOnly()

        // Accumulate elapsed time from this cycle before resetting
        if let start = startTime {
            cumulativeElapsedTime += Date().timeIntervalSince(start)
        }

        // Reset state to normal
        timeoutState = .normal

        // Restart monitoring if was active
        if isMonitoring {
            startTime = Date()  // Fresh start time for new cycle

            // Reschedule warning timer
            warningTimer = Timer.scheduledTimer(
                withTimeInterval: warningThreshold,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWarningTimeout()
                }
            }

            // Reschedule critical timer
            criticalTimer = Timer.scheduledTimer(
                withTimeInterval: criticalThreshold,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleCriticalTimeout()
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Stops timers without resetting monitoring state.
    private func stopTimersOnly() {
        warningTimer?.invalidate()
        warningTimer = nil
        criticalTimer?.invalidate()
        criticalTimer = nil
    }

    /// Handles warning timeout (60 seconds reached).
    private func handleWarningTimeout() {
        // Only transition to warning if currently normal
        // Edge case #1: Don't go back to warning from critical
        guard case .normal = timeoutState else { return }

        // Include cumulative time from previous cycles for accurate total elapsed time
        let currentCycleElapsed = startTime.map { Date().timeIntervalSince($0) } ?? warningThreshold
        let totalElapsed = cumulativeElapsedTime + currentCycleElapsed
        timeoutState = .warning(elapsed: totalElapsed)
    }

    /// Handles critical timeout (90 seconds reached).
    private func handleCriticalTimeout() {
        // Can transition to critical from normal or warning
        guard !timeoutState.isCritical else { return }

        // Include cumulative time from previous cycles for accurate total elapsed time
        let currentCycleElapsed = startTime.map { Date().timeIntervalSince($0) } ?? criticalThreshold
        let totalElapsed = cumulativeElapsedTime + currentCycleElapsed
        timeoutState = .critical(elapsed: totalElapsed)
    }
}

// MARK: - Task 1.5: Publisher Extension

extension ProcessingTimeoutManager {
    /// Publisher for timeout state changes.
    ///
    /// Use this for custom subscriptions beyond SwiftUI's `@ObservedObject`.
    var timeoutStatePublisher: AnyPublisher<TimeoutState, Never> {
        $timeoutState.eraseToAnyPublisher()
    }
}
