//
//  AIFlowIntroView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Introduction screen for AI Flow explaining the scanning process.
/// Displays showroom logo, instructions, and navigation buttons.
struct AIFlowIntroView: View {
    @EnvironmentObject var appState: AppState
    let onStartScanning: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Showroom Logo
                showroomLogo
                    .padding(.top, 40)

                // Title and subtitle
                VStack(spacing: 8) {
                    Text("Scan Your Kitchen")
                        .font(.title2.weight(.semibold))

                    Text("We'll guide you through scanning your kitchen using your camera")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Instruction cards
                VStack(spacing: 12) {
                    InstructionCard(
                        icon: "video.fill",
                        title: "Record a Video",
                        description: "Walk around your kitchen (30-60 seconds)"
                    )
                    .accessibilitySortPriority(3)

                    InstructionCard(
                        icon: "camera.fill",
                        title: "Capture Photos",
                        description: "Take 5 photos from different angles"
                    )
                    .accessibilitySortPriority(2)

                    InstructionCard(
                        icon: "ruler",
                        title: "Get Results",
                        description: "We'll measure your kitchen automatically"
                    )
                    .accessibilitySortPriority(1)
                }
                .padding(.horizontal, 16)

                // Time estimate
                Text("This takes about 2 minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 40)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        triggerHaptic(.medium)
                        onStartScanning()
                    } label: {
                        Text("Start Scanning")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Begins the kitchen scanning process")

                    Button {
                        triggerHaptic(.light)
                        onCancel()
                    } label: {
                        Text("Cancel")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Returns to customer info screen")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Showroom Logo

    @ViewBuilder
    private var showroomLogo: some View {
        if let config = appState.showroomConfig {
            ShowroomLogoLarge(
                logoUrl: config.branding.logoUrl,
                logoDarkUrl: config.branding.logoDarkUrl
            )
        } else {
            Image(systemName: "building.2")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Showroom logo placeholder")
        }
    }

    // MARK: - Haptic Feedback

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

#Preview {
    AIFlowIntroView(
        onStartScanning: { print("Start Scanning") },
        onCancel: { print("Cancel") }
    )
    .environmentObject(AppState())
}
