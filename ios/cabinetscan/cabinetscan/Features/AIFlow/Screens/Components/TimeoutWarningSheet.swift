//
//  TimeoutWarningSheet.swift
//  cabinetscan
//
//  Story 6.8: Error Recovery - Processing Timeout
//  Task 2: Timeout warning sheet component
//

import SwiftUI

// MARK: - Timeout Warning Level

/// Level of timeout warning for sheet display.
enum TimeoutWarningLevel {
    /// 60-second warning (AC1)
    case warning

    /// 90-second critical warning (AC2)
    case critical

}

// MARK: - Timeout Warning Sheet (Task 2)

/// Recovery sheet displayed when processing timeout thresholds are reached.
///
/// **Per Story 6.8:**
/// - **60-second warning (AC1):** "Processing is taking longer than expected"
///   - "Continue Waiting" button (primary)
///   - "Cancel" button (secondary)
/// - **90-second critical (AC2):** "Processing may have encountered an issue"
///   - "Retry" button (primary)
///   - "Cancel" button (secondary)
///
/// **Accessibility (UX-16 to UX-19):**
/// - Full VoiceOver support with labels and hints
/// - Minimum 44pt touch targets
/// - Dynamic Type support with `@ScaledMetric`
/// - Reduce Motion: fade animations only
struct TimeoutWarningSheet: View {

    // MARK: - Properties

    /// Warning level determines UI content
    let level: TimeoutWarningLevel

    /// Called when user selects "Continue Waiting" (60s warning only)
    let onContinueWaiting: () -> Void

    /// Called when user selects "Retry" (90s critical only)
    let onRetry: () -> Void

    /// Called when user selects "Cancel"
    let onCancel: () -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Scaled Metrics (Task 2.9 - Dynamic Type)

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 60
    /// Button height: 56pt exceeds 44pt minimum for better accessibility (Task 2.9)
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 56

    // MARK: - Haptic Feedback (Story 6.7 consistency)

    /// Haptic feedback generator for button taps
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Warning icon and title (Task 2.2)
                warningHeader

                // Explanation text
                explanationSection

                Spacer()

                // Action buttons (Task 2.5, 2.6, 2.7)
                actionButtons

                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 24)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // Prevent accidental dismissal
        }
    }

    // MARK: - Computed Properties

    /// Navigation title based on warning level
    private var navigationTitle: String {
        switch level {
        case .warning:
            return "Processing Slow"
        case .critical:
            return "Processing Issue"
        }
    }

    /// Icon color based on warning level (Task 2.2)
    private var iconColor: Color {
        switch level {
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    /// Icon background color
    private var iconBackgroundColor: Color {
        switch level {
        case .warning:
            return .orange.opacity(0.15)
        case .critical:
            return .red.opacity(0.15)
        }
    }

    /// Main title text (Task 2.3, 2.4)
    private var titleText: String {
        switch level {
        case .warning:
            return "Taking Longer Than Expected"
        case .critical:
            return "May Have Encountered an Issue"
        }
    }

    /// Subtitle text
    private var subtitleText: String {
        switch level {
        case .warning:
            return "Processing is still running but taking longer than usual"
        case .critical:
            return "Processing may be stuck or having trouble completing"
        }
    }

    // MARK: - Sections

    private var warningHeader: some View {
        VStack(spacing: 16) {
            // Warning icon (Task 2.2 - 60pt, orange/red)
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: iconSize + 30, height: iconSize + 30)

                Image(systemName: level == .critical ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)

            // Title
            Text(titleText)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityHeaderLabel)
    }

    /// Accessibility label for header
    private var accessibilityHeaderLabel: String {
        switch level {
        case .warning:
            return "Warning: Processing is taking longer than expected. It is still running but taking longer than usual."
        case .critical:
            return "Alert: Processing may have encountered an issue. It may be stuck or having trouble completing."
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What you can do")
                .font(.headline)

            switch level {
            case .warning:
                Text("This can happen with complex kitchens or on older devices. You can:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    explanationRow(icon: "clock", text: "Continue waiting for processing to complete")
                    explanationRow(icon: "xmark.circle", text: "Cancel and try again later")
                }

            case .critical:
                Text("Processing seems to have stalled. We recommend:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    explanationRow(icon: "arrow.clockwise", text: "Retry from the last checkpoint")
                    explanationRow(icon: "xmark.circle", text: "Cancel and your capture will be saved")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func explanationRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch level {
            case .warning:
                // Task 2.5: "Continue Waiting" button (primary)
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    onContinueWaiting()
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text("Continue Waiting")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: buttonHeight)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Continue waiting")
                .accessibilityHint("Dismisses this alert and waits for processing to complete")

            case .critical:
                // Task 2.7: "Retry" button (primary)
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    onRetry()
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry from Checkpoint")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: buttonHeight)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Retry from checkpoint")
                .accessibilityHint("Restarts processing from the last saved point without re-capturing")
            }

            // Task 2.6: "Cancel" button (secondary) - both levels
            Button(action: {
                feedbackGenerator.impactOccurred()
                onCancel()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                    Text("Cancel")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: buttonHeight)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Cancel processing")
            .accessibilityHint("Saves your capture data and returns to the start screen. You can try again later.")
        }
    }
}

// MARK: - Preview

#Preview("60-Second Warning") {
    TimeoutWarningSheet(
        level: .warning,
        onContinueWaiting: { print("Continue waiting") },
        onRetry: { print("Retry") },
        onCancel: { print("Cancel") }
    )
}

#Preview("90-Second Critical") {
    TimeoutWarningSheet(
        level: .critical,
        onContinueWaiting: { print("Continue waiting") },
        onRetry: { print("Retry") },
        onCancel: { print("Cancel") }
    )
}

#Preview("60-Second Warning - Dark") {
    TimeoutWarningSheet(
        level: .warning,
        onContinueWaiting: { print("Continue waiting") },
        onRetry: { print("Retry") },
        onCancel: { print("Cancel") }
    )
    .preferredColorScheme(.dark)
}

#Preview("90-Second Critical - Dark") {
    TimeoutWarningSheet(
        level: .critical,
        onContinueWaiting: { print("Continue waiting") },
        onRetry: { print("Retry") },
        onCancel: { print("Cancel") }
    )
    .preferredColorScheme(.dark)
}
