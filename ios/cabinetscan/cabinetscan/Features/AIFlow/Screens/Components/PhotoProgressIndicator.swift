//
//  PhotoProgressIndicator.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI

/// Progress indicator showing photo count as filled/empty circles.
/// Per Story 2.5 - Task 6.1, 6.2, UX-9
struct PhotoProgressIndicator: View {
    /// Number of photos captured
    let count: Int

    /// Total photos required
    let total: Int

    /// Whether to show the completion celebration
    var showCelebration: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.accentColor : Color.white.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .scaleEffect(showCelebration && index < count ? 1.2 : 1.0)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.05),
                        value: showCelebration
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if count >= total {
            return "All \(total) photos captured"
        }
        return "\(count) photos captured, \(total - count) remaining"
    }
}

// MARK: - Preview

#Preview("Progress - 0/5") {
    ZStack {
        Color.black
        PhotoProgressIndicator(count: 0, total: 5)
    }
}

#Preview("Progress - 3/5") {
    ZStack {
        Color.black
        PhotoProgressIndicator(count: 3, total: 5)
    }
}

#Preview("Progress - 5/5 Celebration") {
    ZStack {
        Color.black
        PhotoProgressIndicator(count: 5, total: 5, showCelebration: true)
    }
}
