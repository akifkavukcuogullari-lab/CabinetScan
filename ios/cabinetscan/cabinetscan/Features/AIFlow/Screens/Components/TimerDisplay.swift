//
//  TimerDisplay.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Timer display component for video recording.
/// Shows red recording dot and elapsed time.
/// Per UX-11 in Story 2.2 - Task 4.1
struct TimerDisplay: View {
    /// Elapsed time in seconds
    let seconds: TimeInterval

    /// Whether minimum duration has been reached
    let minimumReached: Bool

    /// Scaled dot size for accessibility
    @ScaledMetric(relativeTo: .headline) private var dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            // Recording indicator dot (red, pulsing)
            Circle()
                .fill(.red)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: .red.opacity(0.5), radius: 2)

            // Time display - supports Dynamic Type
            Text(formattedTime)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording time \(formattedTimeAccessible)")
        .accessibilityValue(minimumReached ? "Ready to stop" : "Recording minimum not reached")
    }

    /// Format time as M:SS
    private var formattedTime: String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Accessible time format
    private var formattedTimeAccessible: String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") \(secs) second\(secs == 1 ? "" : "s")"
        }
        return "\(secs) second\(secs == 1 ? "" : "s")"
    }
}

// MARK: - Minimum Duration Progress

/// Progress indicator showing progress toward minimum recording duration.
/// Shows a circular progress ring that fills as recording approaches 10 seconds.
/// Per Story 2.2 AC2 - Task 4.5
/// Story 6.5: Respects Reduce Motion accessibility preference
struct MinimumDurationProgress: View {
    /// Progress from 0.0 to 1.0
    let progress: Double

    /// Diameter of the progress ring
    var diameter: CGFloat = 24

    /// Story 6.5: Reduce Motion accessibility preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3)

            // Progress arc
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    progress >= 1.0 ? Color.green : Color.white,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Story 6.5: Respect Reduce Motion preference
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.1), value: progress)

            // Checkmark when complete
            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.4, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(progress >= 1.0 ? "Minimum duration reached" : "Recording progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

// MARK: - Preview

#Preview("Timer Display - Recording") {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            TimerDisplay(seconds: 5, minimumReached: false)
            TimerDisplay(seconds: 32, minimumReached: true)
            TimerDisplay(seconds: 119, minimumReached: true)
        }
    }
}

#Preview("Minimum Duration Progress") {
    ZStack {
        Color.black
        HStack(spacing: 20) {
            MinimumDurationProgress(progress: 0.0)
            MinimumDurationProgress(progress: 0.3)
            MinimumDurationProgress(progress: 0.7)
            MinimumDurationProgress(progress: 1.0)
        }
    }
}
