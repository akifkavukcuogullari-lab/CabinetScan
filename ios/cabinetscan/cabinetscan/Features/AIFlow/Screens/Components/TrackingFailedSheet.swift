//
//  TrackingFailedSheet.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-31.
//  Story 6.7: Error Recovery - Tracking Lost
//  Per AC3: Recovery prompt after 10-second timeout
//

import SwiftUI

// MARK: - Tracking Failed Sheet

/// Recovery prompt sheet displayed when ARKit tracking fails after 10-second timeout.
///
/// **Per Story 6.7 AC3:**
/// - Shows "Tracking Failed" title with error icon
/// - "Save partial scan" button (primary) - saves current capture data
/// - "Restart" button (secondary) - returns to intro screen
///
/// **Accessibility:**
/// - Full VoiceOver support with labels and hints
/// - Minimum 44pt touch targets
/// - Dynamic Type support
struct TrackingFailedSheet: View {

    // MARK: - Properties

    /// Action when user chooses to save partial scan
    let onSavePartial: () -> Void

    /// Action when user chooses to restart
    let onRestart: () -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Scaled Metrics (Dynamic Type support)

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 60
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 56

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Error icon and title
                errorHeader

                // Explanation text
                explanationSection

                Spacer()

                // Action buttons
                actionButtons

                Spacer()
                    .frame(height: 20)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Tracking Failed")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled() // Prevent accidental dismissal
        }
    }

    // MARK: - Sections

    private var errorHeader: some View {
        VStack(spacing: 16) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: iconSize + 30, height: iconSize + 30)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.red)
            }
            .accessibilityHidden(true)

            // Title
            Text("Tracking Lost")
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)

            // Subtitle
            Text("ARKit could not recover camera tracking")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: ARKit tracking lost and could not recover")
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happened?")
                .font(.headline)

            Text("The camera lost track of your position and couldn't relocalize. This can happen when:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                explanationRow(icon: "figure.walk", text: "Moving too quickly")
                explanationRow(icon: "lightbulb.slash", text: "Poor lighting conditions")
                explanationRow(icon: "square.dashed", text: "Blank walls or featureless areas")
                explanationRow(icon: "hand.raised", text: "Camera was blocked")
            }

            Text("You can save what you've captured so far, or restart the scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func explanationRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.orange)
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
            // Primary: Save partial scan
            Button(action: {
                onSavePartial()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Partial Scan")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: buttonHeight)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Save partial scan")
            .accessibilityHint("Saves the captured data so far and continues to processing. Results may be incomplete.")

            // Secondary: Restart
            Button(action: {
                onRestart()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Restart Scan")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: buttonHeight)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Restart scan")
            .accessibilityHint("Discards current capture and returns to the intro screen")
        }
    }
}

// MARK: - Preview

#Preview("Tracking Failed Sheet") {
    TrackingFailedSheet(
        onSavePartial: { print("Save partial") },
        onRestart: { print("Restart") }
    )
}

#Preview("Tracking Failed Sheet - Dark") {
    TrackingFailedSheet(
        onSavePartial: { print("Save partial") },
        onRestart: { print("Restart") }
    )
    .preferredColorScheme(.dark)
}
