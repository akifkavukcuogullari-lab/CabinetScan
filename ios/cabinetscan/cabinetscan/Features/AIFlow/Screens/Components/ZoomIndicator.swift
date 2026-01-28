//
//  ZoomIndicator.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Zoom level indicator overlay.
/// Shows current zoom factor with auto-dismiss.
/// Per Story 2.2 AC3 - Task 3.5
struct ZoomIndicator: View {
    /// Current zoom level (1.0 = no zoom)
    let zoomLevel: CGFloat

    /// Whether the indicator should be visible
    @Binding var isVisible: Bool

    /// Auto-dismiss timer
    @State private var dismissTask: Task<Void, Never>?

    /// Auto-dismiss delay in nanoseconds (2 seconds)
    private static let dismissDelay: UInt64 = 2_000_000_000

    var body: some View {
        Text(formattedZoom)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
            .onChange(of: zoomLevel) { _, _ in
                showAndScheduleDismiss()
            }
            .accessibilityElement()
            .accessibilityLabel("Zoom level")
            .accessibilityValue(formattedZoomAccessible)
    }

    /// Format zoom as "1.0x"
    private var formattedZoom: String {
        String(format: "%.1fx", zoomLevel)
    }

    /// Accessible zoom format
    private var formattedZoomAccessible: String {
        String(format: "%.1f times", zoomLevel)
    }

    /// Show the indicator and schedule auto-dismiss after 2 seconds
    private func showAndScheduleDismiss() {
        // Cancel any pending dismiss
        dismissTask?.cancel()

        // Show indicator
        isVisible = true

        // Schedule dismiss after delay
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: Self.dismissDelay)
            if !Task.isCancelled {
                await MainActor.run {
                    isVisible = false
                }
            }
        }
    }
}

/// Compact zoom indicator without auto-dismiss (always visible when recording)
struct ZoomBadge: View {
    /// Current zoom level
    let zoomLevel: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)

            Text(formattedZoom)
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Zoom")
        .accessibilityValue(formattedZoomAccessible)
    }

    private var formattedZoom: String {
        String(format: "%.1fx", zoomLevel)
    }

    private var formattedZoomAccessible: String {
        String(format: "%.1f times zoom", zoomLevel)
    }
}

// MARK: - Preview

#Preview("Zoom Indicator") {
    ZStack {
        Color.black

        VStack(spacing: 20) {
            ZoomIndicator(zoomLevel: 1.0, isVisible: .constant(true))
            ZoomIndicator(zoomLevel: 1.5, isVisible: .constant(true))
            ZoomIndicator(zoomLevel: 2.0, isVisible: .constant(true))
        }
    }
}

#Preview("Zoom Badge") {
    ZStack {
        Color.black

        HStack(spacing: 20) {
            ZoomBadge(zoomLevel: 0.5)
            ZoomBadge(zoomLevel: 1.0)
            ZoomBadge(zoomLevel: 1.5)
            ZoomBadge(zoomLevel: 2.0)
        }
    }
}
