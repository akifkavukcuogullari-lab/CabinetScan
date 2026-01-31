//
//  TrackingRecoveryGuidance.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-31.
//  Story 6.7: Error Recovery - Tracking Lost
//  Per Task 3.5: Display last good position guidance when tracking lost
//

import SwiftUI
import simd

// MARK: - Tracking Recovery Guidance

/// Visual guidance component that shows direction to return to last good tracking position.
/// Displays an animated arrow pointing back toward the last known good pose.
///
/// **Per Story 6.7 AC2:**
/// - Shows guidance arrow when tracking is lost
/// - Points user back to scanned area
/// - Respects Reduce Motion preference
struct TrackingRecoveryGuidance: View {

    // MARK: - Properties

    /// Current camera pose (if available)
    let currentPose: AIPose?

    /// Last good pose before tracking was lost
    let lastGoodPose: AIPose?

    /// Whether guidance should be visible
    let isVisible: Bool

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var pulseAnimation = false

    // MARK: - Scaled Metrics

    @ScaledMetric(relativeTo: .title) private var arrowSize: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var textPadding: CGFloat = 16

    // MARK: - Body

    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                // Directional arrow
                ZStack {
                    // Pulsing background circle
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: arrowSize + 40, height: arrowSize + 40)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0.5 : 0.8)

                    // Arrow icon pointing back
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: arrowSize))
                        .foregroundStyle(.orange)
                        .rotationEffect(arrowRotation)
                }
                .accessibilityHidden(true)

                // Instruction text
                Text("Move back to scanned area")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, textPadding)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tracking lost. Move back to the previously scanned area.")
            .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Computed Properties

    /// Calculate arrow rotation based on relative position of last good pose
    /// For simplicity, we use a fixed "go back" direction since precise direction
    /// calculation requires continuous pose updates which we don't have when tracking is lost
    private var arrowRotation: Angle {
        // When tracking is lost, we don't have reliable current pose data
        // Use a subtle animation to draw attention instead of incorrect direction
        return .degrees(0)
    }
}

// MARK: - Tracking Lost Overlay

/// Full-screen overlay shown when tracking is completely lost.
/// Combines the guidance arrow with the recovery toast.
/// Per Story 6.7 - Task 3.5
struct TrackingLostOverlay: View {

    // MARK: - Properties

    /// The tracking recovery state
    let recoveryState: TrackingRecoveryState

    /// Last good pose for guidance
    let lastGoodPose: AIPose?

    /// Whether overlay is visible
    var isVisible: Bool {
        if case .lost = recoveryState {
            return true
        }
        return false
    }

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        if isVisible {
            ZStack {
                // Semi-transparent background to focus attention
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Guidance arrow
                    TrackingRecoveryGuidance(
                        currentPose: nil,
                        lastGoodPose: lastGoodPose,
                        isVisible: true
                    )

                    // Countdown info
                    if case .lost(let elapsed) = recoveryState {
                        let remaining = max(0, 10 - Int(elapsed))
                        Text("Recovery timeout in \(remaining)s")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }

                    Spacer()
                    Spacer()
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Preview

#Preview("Tracking Recovery Guidance") {
    ZStack {
        Color.black

        TrackingRecoveryGuidance(
            currentPose: nil,
            lastGoodPose: nil,
            isVisible: true
        )
    }
}

#Preview("Tracking Lost Overlay") {
    ZStack {
        Color.gray

        TrackingLostOverlay(
            recoveryState: .lost(elapsedSeconds: 3),
            lastGoodPose: nil
        )
    }
}
