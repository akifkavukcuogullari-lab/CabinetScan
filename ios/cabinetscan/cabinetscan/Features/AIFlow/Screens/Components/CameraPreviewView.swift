//
//  CameraPreviewView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//  Rewritten to use ARSCNView for AR session camera preview.
//

import SwiftUI
import ARKit
import SceneKit

/// SwiftUI wrapper for ARSCNView.
/// Displays the AR camera feed during AI flow capture.
/// Replaces the previous AVCaptureVideoPreviewLayer-based preview.
struct AIVideoCameraPreviewView: UIViewRepresentable {
    /// The ARSession to display
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = false
        // Render only the camera feed, no scene content
        view.scene = SCNScene()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Session is set once at creation; no updates needed
    }
}

/// Loading overlay shown while camera initializes.
/// Per Task 6.4 - "Initializing camera..." indicator
struct CameraLoadingOverlay: View {
    /// Status message to display
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

// MARK: - Preview

#Preview("Camera Loading Overlay") {
    ZStack {
        Color.gray

        CameraLoadingOverlay(message: "Initializing camera...")
    }
}
