//
//  CornerIndicators.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

// MARK: - Corner Indicators View

/// Displays 4 corner indicators showing capture coverage status.
/// Shows green checkmarks for captured zones, gray outlines for uncaptured.
/// Per Story 2.3 - Task 6, UX-9
///
/// **Features:**
/// - 4 indicators matching capture zones (front, right, back, left)
/// - Green checkmark for captured zones
/// - Gray outline for uncaptured zones
/// - Positioned in screen corners (respects safe areas)
/// - First-time tooltip explaining the indicators
/// - Minimum 24pt size for visibility
struct CornerIndicators: View {
    /// Set of captured zones
    let capturedZones: Set<AICaptureZone>

    /// Whether to show the first-time tooltip
    let showTooltip: Bool

    /// Callback when tooltip should be dismissed
    let onTooltipDismiss: () -> Void

    /// Indicator size (minimum 24pt per accessibility requirement)
    @ScaledMetric(relativeTo: .title) private var indicatorSize: CGFloat = 28

    /// Padding from screen edges
    private let edgePadding: CGFloat = 16

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Top-left indicator (Front zone)
                cornerIndicator(for: .front)
                    .position(
                        x: geometry.safeAreaInsets.leading + edgePadding + indicatorSize / 2,
                        y: geometry.safeAreaInsets.top + edgePadding + indicatorSize / 2
                    )

                // Top-right indicator (Right zone)
                cornerIndicator(for: .right)
                    .position(
                        x: geometry.size.width - geometry.safeAreaInsets.trailing - edgePadding - indicatorSize / 2,
                        y: geometry.safeAreaInsets.top + edgePadding + indicatorSize / 2
                    )

                // Bottom-left indicator (Left zone)
                cornerIndicator(for: .left)
                    .position(
                        x: geometry.safeAreaInsets.leading + edgePadding + indicatorSize / 2,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - 150 - indicatorSize / 2
                    )

                // Bottom-right indicator (Back zone)
                cornerIndicator(for: .back)
                    .position(
                        x: geometry.size.width - geometry.safeAreaInsets.trailing - edgePadding - indicatorSize / 2,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - 150 - indicatorSize / 2
                    )

                // First-time tooltip
                if showTooltip {
                    tooltipView
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.safeAreaInsets.top + 80
                        )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(coverageAccessibilityLabel)
    }

    // MARK: - Accessibility

    private var coverageAccessibilityLabel: String {
        let captured = capturedZones.count
        let total = AICaptureZone.allCases.count
        return "Coverage status: \(captured) of \(total) areas captured"
    }

    // MARK: - Corner Indicator

    @ViewBuilder
    private func cornerIndicator(for zone: AICaptureZone) -> some View {
        let isCaptured = capturedZones.contains(zone)

        ZStack {
            if isCaptured {
                // Captured: Green checkmark
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: indicatorSize, height: indicatorSize)
                    .shadow(color: .green.opacity(0.4), radius: 4, y: 2)

                Image(systemName: "checkmark")
                    .font(.system(size: indicatorSize * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                // Uncaptured: Gray outline
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: indicatorSize, height: indicatorSize)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                    )
            }
        }
        // Story 6.5: Respect Reduce Motion preference
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: isCaptured)
        .accessibilityElement()
        .accessibilityLabel("\(zone.rawValue.capitalized) area")
        .accessibilityValue(isCaptured ? "Captured" : "Not captured")
    }

    // MARK: - Tooltip

    @ViewBuilder
    private var tooltipView: some View {
        TooltipContent(onDismiss: onTooltipDismiss)
    }
}

// MARK: - Tooltip Content (separate view for proper lifecycle)

/// Separate view to properly manage tooltip auto-dismiss lifecycle
private struct TooltipContent: View {
    let onDismiss: () -> Void

    /// Task for auto-dismiss timer
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.body.weight(.semibold))

            Text("Capture all 4 areas for best results")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .onTapGesture {
            dismissTask?.cancel()
            onDismiss()
        }
        .onAppear {
            // Auto-dismiss after 5 seconds
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        onDismiss()
                    }
                }
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel("Capture all 4 areas for best results. Tap to dismiss.")
    }
}

// MARK: - Compact Corner Indicator

/// Single corner indicator for use in custom layouts
struct SingleCornerIndicator: View {
    let zone: AICaptureZone
    let isCaptured: Bool

    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 24

    var body: some View {
        ZStack {
            if isCaptured {
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: size, height: size)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.black.opacity(0.3)))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(zone.rawValue.capitalized) area")
        .accessibilityValue(isCaptured ? "Captured" : "Not captured")
    }
}

// MARK: - Coverage Progress Bar

/// Horizontal progress bar showing overall coverage
struct CoverageProgressBar: View {
    let capturedCount: Int
    let totalCount: Int = 4

    var progress: Float {
        Float(capturedCount) / Float(totalCount)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<totalCount, id: \.self) { index in
                    Rectangle()
                        .fill(index < capturedCount ? Color.green : Color.white.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .clipShape(Capsule())

            Text("\(capturedCount)/\(totalCount) areas")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coverage progress")
        .accessibilityValue("\(capturedCount) of \(totalCount) areas captured")
    }
}

// MARK: - Preview

#Preview("Corner Indicators - None Captured") {
    ZStack {
        Color.black

        CornerIndicators(
            capturedZones: [],
            showTooltip: true,
            onTooltipDismiss: { print("Tooltip dismissed") }
        )
    }
    .ignoresSafeArea()
}

#Preview("Corner Indicators - Some Captured") {
    ZStack {
        Color.black

        CornerIndicators(
            capturedZones: [.front, .right],
            showTooltip: false,
            onTooltipDismiss: {}
        )
    }
    .ignoresSafeArea()
}

#Preview("Corner Indicators - All Captured") {
    ZStack {
        Color.black

        CornerIndicators(
            capturedZones: Set(AICaptureZone.allCases),
            showTooltip: false,
            onTooltipDismiss: {}
        )
    }
    .ignoresSafeArea()
}

#Preview("Single Indicators") {
    ZStack {
        Color.black

        HStack(spacing: 20) {
            SingleCornerIndicator(zone: .front, isCaptured: true)
            SingleCornerIndicator(zone: .right, isCaptured: false)
            SingleCornerIndicator(zone: .back, isCaptured: true)
            SingleCornerIndicator(zone: .left, isCaptured: false)
        }
    }
}

#Preview("Coverage Progress Bar") {
    ZStack {
        Color.black

        VStack(spacing: 20) {
            CoverageProgressBar(capturedCount: 0)
            CoverageProgressBar(capturedCount: 2)
            CoverageProgressBar(capturedCount: 4)
        }
        .padding()
    }
}
