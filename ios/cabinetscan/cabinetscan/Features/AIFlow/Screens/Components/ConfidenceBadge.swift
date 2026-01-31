//
//  ConfidenceBadge.swift
//  cabinetscan
//
//  Created for Story 4.8: Confidence Scoring System
//

import SwiftUI

// MARK: - Confidence Badge (Task 11)

/// Visual badge component for displaying confidence levels per AC4.
///
/// **Badge Styles (AC4):**
/// - HIGH: Green badge, checkmark icon
/// - MEDIUM: Yellow badge, warning icon
/// - LOW: Red badge, exclamation icon, pulsing animation
///
/// **Usage:**
/// ```swift
/// ConfidenceBadge(level: .high)
/// ConfidenceBadge(level: .low, showLabel: true)
/// ConfidenceBadge(score: objectScore) // From ObjectConfidenceScore
/// ```
struct ConfidenceBadge: View {

    // MARK: - Properties

    /// Confidence level to display
    let level: AIConfidenceLevel

    /// Optional score for tooltip display
    let score: ObjectConfidenceScore?

    /// Whether to show the label text
    let showLabel: Bool

    /// Whether to show the pulsing animation for LOW
    let animated: Bool

    /// Size of the badge
    let size: BadgeSize

    // MARK: - State

    @State private var isPulsing = false
    @State private var showingDetail = false

    // MARK: - Environment

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Size Enum

    enum BadgeSize {
        case small
        case medium
        case large

        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 14
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }

    // MARK: - Initialization

    init(
        level: AIConfidenceLevel,
        score: ObjectConfidenceScore? = nil,
        showLabel: Bool = false,
        animated: Bool = true,
        size: BadgeSize = .medium
    ) {
        self.level = level
        self.score = score
        self.showLabel = showLabel
        self.animated = animated
        self.size = size
    }

    /// Convenience initializer from ObjectConfidenceScore
    init(
        score: ObjectConfidenceScore,
        showLabel: Bool = false,
        animated: Bool = true,
        size: BadgeSize = .medium
    ) {
        self.level = score.level
        self.score = score
        self.showLabel = showLabel
        self.animated = animated
        self.size = size
    }

    // MARK: - Body

    var body: some View {
        Button(action: {
            if score != nil {
                showingDetail = true
            }
        }) {
            HStack(spacing: 4) {
                // Icon
                icon
                    .font(.system(size: size.iconSize, weight: .semibold))
                    .foregroundColor(foregroundColor)

                // Optional label
                if showLabel {
                    Text(level.displayText)
                        .font(.system(size: size.fontSize, weight: .medium))
                        .foregroundColor(foregroundColor)
                }
            }
            .padding(.horizontal, size.padding)
            .padding(.vertical, size.padding / 2)
            .background(backgroundColor)
            .cornerRadius(size.iconSize)
            .overlay(
                RoundedRectangle(cornerRadius: size.iconSize)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isPulsing ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(score != nil ? "Double tap for details" : "")
        .onAppear {
            // Story 6.5: Only animate if Reduce Motion is not enabled
            if animated && level == .low && !reduceMotion {
                startPulsingAnimation()
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let score = score {
                ConfidenceDetailView(score: score)
            }
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var icon: some View {
        switch level {
        case .high:
            Image(systemName: "checkmark.circle.fill")
        case .medium:
            Image(systemName: "exclamationmark.triangle.fill")
        case .low:
            Image(systemName: "exclamationmark.circle.fill")
        }
    }

    // MARK: - Colors

    private var foregroundColor: Color {
        switch level {
        case .high: return .white
        case .medium: return .black.opacity(0.8)
        case .low: return .white
        }
    }

    private var backgroundColor: Color {
        switch level {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }

    private var borderColor: Color {
        switch level {
        case .high: return .green.opacity(0.3)
        case .medium: return .yellow.opacity(0.3)
        case .low: return .red.opacity(0.3)
        }
    }

    // MARK: - Animation

    private func startPulsingAnimation() {
        withAnimation(
            Animation.easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch level {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence, may need verification"
        case .low:
            return "Low confidence, verification required"
        }
    }
}

// MARK: - AIConfidenceLevel Extension

extension AIConfidenceLevel {
    /// Display text for UI
    var displayText: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

// MARK: - Confidence Detail View (Task 11.3)

/// Detail view showing factor breakdown for a confidence score.
struct ConfidenceDetailView: View {

    let score: ObjectConfidenceScore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    // Overall score
                    overallScoreSection

                    // Factor breakdown
                    factorBreakdownSection

                    // Warnings
                    if !score.warnings.isEmpty {
                        warningsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Confidence Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Text(score.objectType.displayText)
                .font(.headline)

            Spacer()

            ConfidenceBadge(level: score.level, showLabel: true, size: .large)
        }
    }

    private var overallScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Score")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(score.displayPercentage)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(score.level.badgeColor)
        }
    }

    private var factorBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Factor Breakdown")
                .font(.subheadline)
                .foregroundColor(.secondary)

            FactorRow(
                name: "Segmentation Clarity",
                value: score.factors.segmentationClarity,
                weight: ConfidenceFactors.Weights.segmentationClarity,
                hint: "Edge definition sharpness"
            )

            FactorRow(
                name: "Depth Consistency",
                value: score.factors.depthConsistency,
                weight: ConfidenceFactors.Weights.depthConsistency,
                hint: "Multi-view agreement"
            )

            FactorRow(
                name: "Pose Accuracy",
                value: score.factors.poseAccuracy,
                weight: ConfidenceFactors.Weights.poseAccuracy,
                hint: "Tracking quality"
            )

            FactorRow(
                name: "Size Match",
                value: score.factors.standardSizeMatch,
                weight: ConfidenceFactors.Weights.standardSizeMatch,
                hint: "Standard size conformance"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warnings")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(score.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Factor Row

/// Row displaying a single confidence factor.
private struct FactorRow: View {
    let name: String
    let value: Float
    let weight: Float
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)

                Spacer()

                Text(String(format: "%.0f%%", value * 100))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorForValue)

                Text(String(format: "(%.0f%%)", weight * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(colorForValue)
                        .frame(width: geometry.size.width * CGFloat(value), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)

            Text(hint)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var colorForValue: Color {
        if value >= 0.8 {
            return .green
        } else if value >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Quote Readiness Badge

/// Badge showing quote readiness status per AC9.
/// Story 6.5: Added accessibility label
struct QuoteReadinessBadge: View {

    let readiness: QuoteReadinessLevel

    var body: some View {
        HStack(spacing: 6) {
            icon
                .font(.system(size: 14))

            Text(readiness.shortLabel)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(8)
        // Story 6.5: Accessibility label with full context
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch readiness {
        case .ready:
            return "Quote ready: Scan results are reliable for quoting"
        case .withCaveats:
            return "Quote with caveats: Some items may need verification"
        case .notRecommended:
            return "Quote not recommended: Scan results have low confidence"
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch readiness {
        case .ready:
            Image(systemName: "checkmark.seal.fill")
        case .withCaveats:
            Image(systemName: "exclamationmark.triangle.fill")
        case .notRecommended:
            Image(systemName: "xmark.seal.fill")
        }
    }

    private var foregroundColor: Color {
        switch readiness {
        case .ready: return .white
        case .withCaveats: return .black.opacity(0.8)
        case .notRecommended: return .white
        }
    }

    private var backgroundColor: Color {
        switch readiness {
        case .ready: return .green
        case .withCaveats: return .yellow
        case .notRecommended: return .red
        }
    }
}

// MARK: - Previews

#if DEBUG
struct ConfidenceBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Badge variations
            HStack(spacing: 16) {
                ConfidenceBadge(level: .high)
                ConfidenceBadge(level: .medium)
                ConfidenceBadge(level: .low)
            }

            // With labels
            HStack(spacing: 16) {
                ConfidenceBadge(level: .high, showLabel: true)
                ConfidenceBadge(level: .medium, showLabel: true)
                ConfidenceBadge(level: .low, showLabel: true)
            }

            // Different sizes
            HStack(spacing: 16) {
                ConfidenceBadge(level: .high, size: .small)
                ConfidenceBadge(level: .high, size: .medium)
                ConfidenceBadge(level: .high, size: .large)
            }

            // Quote readiness
            VStack(spacing: 8) {
                QuoteReadinessBadge(readiness: .ready)
                QuoteReadinessBadge(readiness: .withCaveats)
                QuoteReadinessBadge(readiness: .notRecommended)
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
