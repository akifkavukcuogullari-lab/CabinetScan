//
//  InstructionCard.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// A reusable instruction card component displaying an icon, title, and description.
/// Used in AIFlowIntroView to explain the scanning process steps.
struct InstructionCard: View {
    let icon: String
    let title: String
    let description: String

    /// Scales icon size with Dynamic Type accessibility settings
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var iconFrameSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.blue)
                .frame(width: iconFrameSize, height: iconFrameSize)
                .accessibilityHidden(true) // Icon is decorative, title is descriptive

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

#Preview {
    VStack(spacing: 12) {
        InstructionCard(
            icon: "video.fill",
            title: "Record a Video",
            description: "Walk around your kitchen (30-60 seconds)"
        )
        InstructionCard(
            icon: "camera.fill",
            title: "Capture Photos",
            description: "Take 5 photos from different angles"
        )
        InstructionCard(
            icon: "ruler",
            title: "Get Results",
            description: "We'll measure your kitchen automatically"
        )
    }
    .padding()
}
