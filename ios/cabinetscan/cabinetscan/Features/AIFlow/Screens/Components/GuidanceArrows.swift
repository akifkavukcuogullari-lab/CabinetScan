//
//  GuidanceArrows.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

// MARK: - Guidance Arrows View

/// Directional arrow overlay for capture guidance.
/// Shows pulsing arrows pointing toward uncaptured areas.
/// Per Story 2.3 - Task 5, UX-9
/// Story 6.5: Respects Reduce Motion accessibility preference
///
/// **Features:**
/// - Directional arrows (left, right, up, down)
/// - Pulsing animation to draw attention (respects Reduce Motion)
/// - Hides when no guidance needed
/// - Full accessibility support
struct GuidanceArrows: View {
    /// Direction to point (nil = no arrow shown)
    let direction: AIGuidanceDirection?

    /// Animation state for pulsing effect
    @State private var isPulsing = false

    /// Scaled arrow size for accessibility
    @ScaledMetric(relativeTo: .title) private var arrowSize: CGFloat = 40

    /// Story 6.5: Reduce Motion environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let direction = direction {
                    arrowView(for: direction, in: geometry.size)
                        .transition(.opacity.animation(reduceMotion ? .none : .easeInOut(duration: 0.3)))
                }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: direction)
        .onAppear {
            if !reduceMotion {
                startPulsingAnimation()
            }
        }
    }

    // MARK: - Arrow View

    @ViewBuilder
    private func arrowView(for direction: AIGuidanceDirection, in size: CGSize) -> some View {
        HStack(spacing: 8) {
            Image(systemName: direction.arrowSymbol)
                .font(.system(size: arrowSize, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            if let text = textForDirection(direction) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.8))
                .shadow(color: .blue.opacity(0.4), radius: 8, y: 2)
        )
        // Story 6.5: Respect Reduce Motion for pulsing animation
        .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.05 : 1.0))
        .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.85))
        .position(positionForDirection(direction, in: size))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(direction.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Text Labels

    private func textForDirection(_ direction: AIGuidanceDirection) -> String? {
        switch direction {
        case .forward:
            return "Scan ahead"
        case .right:
            return "Turn right"
        case .backward:
            return "Look behind"
        case .left:
            return "Turn left"
        }
    }

    // MARK: - Positioning

    /// Get position for arrow based on direction and container size
    /// Arrows appear at the edge of the screen in the direction they point
    private func positionForDirection(_ direction: AIGuidanceDirection, in size: CGSize) -> CGPoint {
        switch direction {
        case .forward:
            return CGPoint(x: size.width / 2, y: 120)
        case .backward:
            return CGPoint(x: size.width / 2, y: size.height - 200)
        case .left:
            return CGPoint(x: 80, y: size.height / 2)
        case .right:
            return CGPoint(x: size.width - 80, y: size.height / 2)
        }
    }

    // MARK: - Animation

    private func startPulsingAnimation() {
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}

// MARK: - Alternative Compact Arrow

/// Compact arrow indicator for tight spaces
/// Story 6.5: Respects Reduce Motion accessibility preference
struct CompactGuidanceArrow: View {
    let direction: AIGuidanceDirection

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: direction.arrowSymbol)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Circle().fill(Color.blue.opacity(0.8)))
            .shadow(color: .blue.opacity(0.4), radius: 4, y: 2)
            .scaleEffect(reduceMotion ? 1.0 : (isPulsing ? 1.1 : 1.0))
            .onAppear {
                if !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .accessibilityLabel(direction.accessibilityLabel)
    }
}

// MARK: - Preview

#Preview("Guidance Arrows") {
    ZStack {
        Color.black

        VStack(spacing: 40) {
            GuidanceArrows(direction: .forward)
                .frame(height: 100)

            GuidanceArrows(direction: .right)
                .frame(height: 100)

            GuidanceArrows(direction: .left)
                .frame(height: 100)

            GuidanceArrows(direction: .backward)
                .frame(height: 100)
        }
    }
    .ignoresSafeArea()
}

#Preview("Compact Arrows") {
    ZStack {
        Color.black

        HStack(spacing: 30) {
            CompactGuidanceArrow(direction: .left)
            CompactGuidanceArrow(direction: .forward)
            CompactGuidanceArrow(direction: .right)
            CompactGuidanceArrow(direction: .backward)
        }
    }
}

#Preview("No Direction") {
    ZStack {
        Color.black

        GuidanceArrows(direction: nil)
    }
}
