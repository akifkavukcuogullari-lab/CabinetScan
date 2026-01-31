//
//  TrackingRecoveryToast.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-31.
//  Story 6.7: Error Recovery - Tracking Lost
//  Per AC1, AC2: Toast notifications for tracking state changes
//

import SwiftUI

// MARK: - Tracking Recovery Toast

/// Toast component for displaying ARKit tracking state warnings.
/// Shows appropriate messages for limited tracking and tracking lost states.
///
/// **Per Story 6.7 AC1, AC2:**
/// - Limited tracking: "Move slowly, tracking limited" (yellow warning)
/// - Tracking lost: "Tracking lost - move back to scanned area" (yellow warning)
///
/// **Accessibility:**
/// - Respects Reduce Motion preference
/// - VoiceOver announcements for state changes
/// - Dynamic Type support via @ScaledMetric
struct TrackingRecoveryToast: View {

    // MARK: - Properties

    /// The current tracking recovery state
    let recoveryState: TrackingRecoveryState

    /// Whether the toast is visible
    let isVisible: Bool

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Scaled Metrics (Dynamic Type support)

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var horizontalPadding: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 12

    // MARK: - Body

    var body: some View {
        if isVisible && shouldShowToast {
            HStack(spacing: 10) {
                // Warning icon
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                // Message text
                VStack(alignment: .leading, spacing: 2) {
                    Text(messageTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = messageSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            // Accessibility
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isStaticText)
            // Animation
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: - Computed Properties

    /// Whether toast should be shown for this state
    private var shouldShowToast: Bool {
        switch recoveryState {
        case .normal:
            return false
        case .limited, .lost, .failed:
            return true
        }
    }

    /// SF Symbol icon name based on state
    private var iconName: String {
        switch recoveryState {
        case .normal:
            return "checkmark.circle.fill"
        case .limited(let reason):
            return reason.iconName
        case .lost:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    /// Main message title
    private var messageTitle: String {
        switch recoveryState {
        case .normal:
            return "Tracking normal"
        case .limited(let reason):
            return reason.userMessage
        case .lost:
            return "Tracking lost"
        case .failed:
            return "Tracking failed"
        }
    }

    /// Optional subtitle with additional context
    private var messageSubtitle: String? {
        switch recoveryState {
        case .normal:
            return nil
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "Slow down your movement"
            case .insufficientFeatures:
                return "Point camera at textured surfaces"
            case .relocalizing:
                return "Return to previously scanned area"
            default:
                return nil
            }
        case .lost(let elapsed):
            let remaining = max(0, 10 - Int(elapsed))
            return "Move back to scanned area (\(remaining)s)"
        case .failed:
            return "Save partial scan or restart"
        }
    }

    /// Background color based on state severity
    private var backgroundColor: Color {
        switch recoveryState {
        case .normal:
            return Color.green.opacity(0.85)
        case .limited:
            return Color.orange.opacity(0.9)
        case .lost:
            return Color.orange.opacity(0.9)
        case .failed:
            return Color.red.opacity(0.9)
        }
    }

    /// Full accessibility label
    private var accessibilityLabel: String {
        switch recoveryState {
        case .normal:
            return "Tracking recovered"
        case .limited(let reason):
            return "Warning: \(reason.userMessage)"
        case .lost(let elapsed):
            let remaining = max(0, 10 - Int(elapsed))
            return "Warning: Tracking lost. Move back to scanned area. \(remaining) seconds until timeout."
        case .failed:
            return "Error: Tracking failed. Choose to save partial scan or restart."
        }
    }
}

// MARK: - Tracking Recovery Toast Container

/// Container that manages toast display with auto-dismiss and accessibility announcements.
/// Per Story 6.7 - Task 2.5, 2.6
struct TrackingRecoveryToastContainer: View {

    // MARK: - Properties

    /// The tracking recovery state to display
    let recoveryState: TrackingRecoveryState

    /// Whether the toast should be visible
    @Binding var isVisible: Bool

    /// Auto-dismiss delay for limited tracking (seconds)
    private let limitedDismissDelay: TimeInterval = 5.0

    // MARK: - State

    @State private var dismissTask: Task<Void, Never>?

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        TrackingRecoveryToast(
            recoveryState: recoveryState,
            isVisible: isVisible
        )
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isVisible)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: recoveryState)
        .onChange(of: recoveryState) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: - Private Methods

    /// Handle state changes for auto-dismiss and accessibility
    private func handleStateChange(from oldState: TrackingRecoveryState, to newState: TrackingRecoveryState) {
        // Cancel any pending dismiss
        dismissTask?.cancel()

        switch newState {
        case .normal:
            // Tracking recovered - announce for accessibility but don't show toast
            // (L2 fix: Toast itself returns false for shouldShowToast when .normal)
            announceForVoiceOver("Tracking recovered")

            // Dismiss any visible toast after brief delay
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                if !Task.isCancelled {
                    await MainActor.run {
                        isVisible = false
                    }
                }
            }

        case .limited(let reason):
            isVisible = true
            announceForVoiceOver("Warning: \(reason.userMessage)")

            // Auto-dismiss after delay if tracking stabilizes
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(limitedDismissDelay * 1_000_000_000))
                // Only dismiss if still in limited state
                if !Task.isCancelled, case .limited = recoveryState {
                    // Don't auto-dismiss - let state change handle it
                }
            }

        case .lost(let elapsed):
            isVisible = true
            if elapsed < 1 { // Only announce on first detection
                announceForVoiceOver("Warning: Tracking lost. Move back to scanned area.")
            }

        case .failed:
            isVisible = true
            announceForVoiceOver("Error: Tracking failed after timeout.")
        }
    }

    /// Post VoiceOver announcement
    private func announceForVoiceOver(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Predefined Toast Messages (Story 6.7)

extension GuidanceToastMessage {
    /// Tracking limited - excessive motion (UX-21)
    static let trackingLimitedMotion = GuidanceToastMessage(
        id: "tracking_limited_motion",
        message: "Move slowly, tracking limited",
        icon: "hand.raised.fill",
        type: .warning
    )

    /// Tracking limited - insufficient features
    static let trackingLimitedFeatures = GuidanceToastMessage(
        id: "tracking_limited_features",
        message: "Point at a textured area",
        icon: "viewfinder",
        type: .warning
    )

    /// Tracking lost (UX-22)
    static let trackingLost = GuidanceToastMessage(
        id: "tracking_lost",
        message: "Tracking lost - move back to scanned area",
        icon: "exclamationmark.triangle.fill",
        type: .warning
    )

    /// Tracking recovered
    static let trackingRecovered = GuidanceToastMessage(
        id: "tracking_recovered",
        message: "Tracking recovered",
        icon: "checkmark.circle.fill",
        type: .info
    )
}

// MARK: - Preview

#Preview("Limited - Excessive Motion") {
    ZStack {
        Color.black

        TrackingRecoveryToast(
            recoveryState: .limited(reason: .excessiveMotion),
            isVisible: true
        )
    }
}

#Preview("Limited - Insufficient Features") {
    ZStack {
        Color.black

        TrackingRecoveryToast(
            recoveryState: .limited(reason: .insufficientFeatures),
            isVisible: true
        )
    }
}

#Preview("Tracking Lost") {
    ZStack {
        Color.black

        TrackingRecoveryToast(
            recoveryState: .lost(elapsedSeconds: 3),
            isVisible: true
        )
    }
}

#Preview("Tracking Failed") {
    ZStack {
        Color.black

        TrackingRecoveryToast(
            recoveryState: .failed,
            isVisible: true
        )
    }
}
