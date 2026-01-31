//
//  PhotoCaptureButton.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI
import UIKit

/// Capture button for photo mode with haptic feedback and press animation.
/// Per Story 2.5 - Task 6.3, 6.4, Task 7.1, 7.2, UX-8, UX-12
/// Story 6.5: Enhanced accessibility with remaining photo count per AC1
struct PhotoCaptureButton: View {
    /// Action to perform when button is tapped
    let action: () -> Void

    /// Whether the button is enabled
    var isEnabled: Bool = true

    /// Current photo count for accessibility (Story 6.5 - AC1)
    var currentPhotoCount: Int = 0

    /// Total photos required for accessibility (Story 6.5 - AC1)
    var totalPhotosRequired: Int = 5

    /// Whether to show flash effect
    @State private var showFlash = false

    /// Press state for animation
    @State private var isPressed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    /// Outer ring diameter (UX-8)
    private let outerDiameter: CGFloat = 70

    /// Inner circle diameter (UX-8)
    private let innerDiameter: CGFloat = 60

    /// Ring stroke width
    private let strokeWidth: CGFloat = 4

    var body: some View {
        Button {
            performCapture()
        } label: {
            ZStack {
                // Flash overlay (appears briefly on capture)
                if showFlash {
                    Circle()
                        .fill(Color.white)
                        .frame(width: outerDiameter + 20, height: outerDiameter + 20)
                        .opacity(0.8)
                }

                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: strokeWidth)
                    .frame(width: outerDiameter, height: outerDiameter)

                // Inner filled circle
                Circle()
                    .fill(isEnabled ? Color.white : Color.white.opacity(0.5))
                    .frame(width: innerDiameter, height: innerDiameter)
                    .scaleEffect(isPressed ? 0.85 : 1.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else { return }
                    if !reduceMotion {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    guard isEnabled else { return }
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isEnabled ? "Double tap to take a photo" : "Capture is disabled")
        .accessibilityAddTraits(isEnabled ? .isButton : [.isButton, .isStaticText])
    }

    // MARK: - Accessibility

    /// Dynamic accessibility label including remaining photo count per AC1
    private var accessibilityLabelText: String {
        let remaining = totalPhotosRequired - currentPhotoCount
        if remaining > 0 {
            return "Capture photo, \(remaining) of \(totalPhotosRequired) remaining"
        } else {
            return "All photos captured"
        }
    }

    // MARK: - Capture Action

    private func performCapture() {
        // Light haptic feedback (UX-12)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Flash effect (Task 7.2)
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.1)) {
                showFlash = true
            }
            // Remove flash after brief duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.1)) {
                    showFlash = false
                }
            }
        }

        // Trigger capture action
        action()
    }
}

// MARK: - Preview

#Preview("Capture Button - Enabled") {
    ZStack {
        Color.black
        PhotoCaptureButton(action: { print("Captured!") })
    }
}

#Preview("Capture Button - Disabled") {
    ZStack {
        Color.black
        PhotoCaptureButton(action: { print("Captured!") }, isEnabled: false)
    }
}
