//
//  ConfidenceWarningSheet.swift
//  cabinetscan
//
//  Created for Story 4.8: Confidence Scoring System
//  Per AC3/FR34: Shown when overall confidence <60%
//

import SwiftUI

// MARK: - Confidence Warning Sheet (AC3, FR34)

/// Warning sheet displayed when overall scan confidence is below 60%.
///
/// **Per AC3:** If overall confidence <60%, this sheet is shown to warn
/// the user that the scan results may not be reliable for quoting.
///
/// **Usage:**
/// ```swift
/// .sheet(isPresented: $showWarning) {
///     ConfidenceWarningSheet(
///         scoringResult: result,
///         onDismiss: { showWarning = false },
///         onRescan: { startNewScan() }
///     )
/// }
/// ```
struct ConfidenceWarningSheet: View {

    // MARK: - Properties

    /// The confidence scoring result
    let scoringResult: ConfidenceScoringResult

    /// Action when user dismisses (proceeds anyway)
    let onDismiss: () -> Void

    /// Action when user chooses to rescan
    let onRescan: (() -> Void)?

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(
        scoringResult: ConfidenceScoringResult,
        onDismiss: @escaping () -> Void,
        onRescan: (() -> Void)? = nil
    ) {
        self.scoringResult = scoringResult
        self.onDismiss = onDismiss
        self.onRescan = onRescan
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning icon
                    warningHeader

                    // Main message
                    messageSection

                    // Items needing verification
                    if !scoringResult.warnings.isEmpty {
                        issuesSection
                    }

                    // Quote readiness
                    quoteReadinessSection

                    // Actions
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Low Confidence Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var warningHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            // Story 6.5: Combined accessibility for warning icon and percentage
            .accessibilityHidden(true)

            Text("Low Confidence Scan")
                .font(.title2)
                .fontWeight(.bold)

            Text(scoringResult.displayPercentage)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.red)
        }
        // Story 6.5: Combined accessibility element for header
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Low confidence scan at \(scoringResult.displayPercentage)")
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What This Means")
                .font(.headline)

            Text("The scan results have low confidence and may not be accurate enough for quoting. Some measurements may be incorrect or missing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Quote readiness message
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)

                Text(scoringResult.quoteReadiness.displayMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Items Needing Verification")
                    .font(.headline)

                Spacer()

                Text("\(scoringResult.itemsNeedingVerification)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(scoringResult.warnings.prefix(5).enumerated()), id: \.offset) { index, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .accessibilityHidden(true)

                        Text(warning)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    // Story 6.5: Individual accessibility label for each issue
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Issue \(index + 1): \(warning)")
                }

                if scoringResult.warnings.count > 5 {
                    Text("+ \(scoringResult.warnings.count - 5) more issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quoteReadinessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                recommendationRow(
                    icon: "arrow.clockwise",
                    text: "Consider rescanning with better lighting and slower movement"
                )

                recommendationRow(
                    icon: "ruler",
                    text: "Verify all measurements manually before quoting"
                )

                recommendationRow(
                    icon: "checkmark.shield",
                    text: "Include field verification disclaimer in any quotes"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendationRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        // Story 6.5: Combined accessibility for better VoiceOver grouping
        .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary action: Proceed anyway
            Button(action: {
                onDismiss()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Proceed with Caution")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            // Story 6.5: Accessibility hint for proceed button
            .accessibilityHint("Continues with current scan results despite low confidence. Manual verification recommended.")

            // Secondary action: Rescan (if available)
            if let onRescan = onRescan {
                Button(action: {
                    onRescan()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Rescan Kitchen")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                // Story 6.5: Accessibility hint for rescan button
                .accessibilityHint("Starts a new scan to improve accuracy")
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Preview

#if DEBUG
struct ConfidenceWarningSheet_Previews: PreviewProvider {
    static var previews: some View {
        ConfidenceWarningSheet(
            scoringResult: ConfidenceScoringResult(
                objectScores: [],
                overallScore: 0.45,
                overallLevel: .low,
                quoteReadiness: .notRecommended,
                itemsNeedingVerification: 3,
                warnings: [
                    "Cabinet #1: low confidence - verify width",
                    "edges unclear, check boundaries",
                    "Cabinet #3: low confidence - verify width",
                    "depth inconsistent, verify with tape measure",
                    "Field verification recommended for 3 item(s)"
                ],
                processingTimeMs: 42,
                limitingObjectId: nil
            ),
            onDismiss: {},
            onRescan: {}
        )
    }
}
#endif
