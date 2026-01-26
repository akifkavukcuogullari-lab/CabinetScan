//
//  VideoCaptureView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Placeholder for video capture screen.
/// Full implementation will be done in Story 2.2.
struct VideoCaptureView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "video.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Video Capture")
                    .font(.title2.bold())

                Text("Full implementation in Story 2.2")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onBack()
            } label: {
                Text("Back to Intro")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
            .accessibilityHint("Returns to the intro screen")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    VideoCaptureView(onBack: { print("Back") })
}
