//
//  CameraPreviewView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import AVFoundation

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer.
/// Used to display camera preview during AI flow video capture.
/// Per Story 2.2 AC6 - Task 6.1, 6.2, 6.3
struct AIVideoCameraPreviewView: UIViewRepresentable {
    /// The video capture service providing the preview layer
    let videoCapture: AIVideoCapture?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoCapture = videoCapture
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.videoCapture = videoCapture
    }
}

/// UIView subclass for camera preview.
/// Manages the AVCaptureVideoPreviewLayer lifecycle.
class CameraPreviewUIView: UIView {
    /// Preview layer from video capture
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// Video capture service
    var videoCapture: AIVideoCapture? {
        didSet {
            updatePreviewLayer()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func updatePreviewLayer() {
        // Remove existing layer
        previewLayer?.removeFromSuperlayer()

        // Add new layer if video capture is available
        if let videoCapture = videoCapture {
            let layer = videoCapture.previewLayer
            layer.frame = bounds
            layer.videoGravity = .resizeAspectFill

            // Lock to portrait orientation (Task 6.3)
            if let connection = layer.connection {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }

            self.layer.addSublayer(layer)
            previewLayer = layer
        }
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
