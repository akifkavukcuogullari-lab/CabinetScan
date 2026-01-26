//
//  CameraPermissionView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Error screen displayed when camera permission is denied.
/// Provides user with option to open Settings and grant permission.
struct CameraPermissionView: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Camera Access Required")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("CabinetScan needs camera access to scan your kitchen and measure your cabinets.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    triggerHaptic(.medium)
                    onOpenSettings()
                } label: {
                    Text("Open Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens iOS Settings to enable camera access")

                Button {
                    triggerHaptic(.light)
                    onCancel()
                } label: {
                    Text("Cancel")
                }
                .foregroundStyle(.secondary)
                .accessibilityHint("Returns to previous screen")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

#Preview {
    CameraPermissionView(
        onOpenSettings: { print("Open Settings") },
        onCancel: { print("Cancel") }
    )
}
