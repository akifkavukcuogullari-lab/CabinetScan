//
//  AIFlowEntryPoint.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI

/// Entry point for AI-based measurement flow on non-LiDAR devices.
/// Called from FlowRouter when device doesn't support RoomPlan.
///
/// This view serves as the root of the AI Flow module and coordinates
/// navigation between capture, processing, and results phases.
struct AIFlowEntryPoint: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = AIFlowViewModel()
    @StateObject private var coordinator = AIFlowCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Main navigation based on current step
            switch viewModel.currentStep {
            case .intro:
                AIFlowIntroView(
                    onStartScanning: {
                        Task {
                            await viewModel.attemptStartScanning()
                        }
                    },
                    onCancel: {
                        appState.currentScreen = .customerInfo
                    }
                )
                .environmentObject(appState)

            case .videoCapture:
                VideoCaptureView(
                    sessionManager: coordinator.arSessionManager,
                    dataManager: coordinator.captureDataManager,  // Issue #7 fix - pass shared manager
                    onBack: {
                        coordinator.onVideoCaptureBack()
                        viewModel.backToIntro()
                    },
                    onComplete: { captureData, videoCapture in
                        // Store video capture for session sharing with photo capture
                        if let videoCapture = videoCapture {
                            coordinator.setVideoCapture(videoCapture)
                        }
                        coordinator.onVideoCaptureComplete(captureData)
                        viewModel.advanceToNextStep()
                    }
                )

            case .photoCapture:
                // Photo capture - Story 2.5
                if let videoCapture = coordinator.videoCapture {
                    PhotoCaptureView(
                        sessionManager: coordinator.arSessionManager,
                        captureSession: videoCapture.captureSession,
                        dataManager: coordinator.captureDataManager,  // Issue #7 fix - pass shared manager
                        onBack: {
                            coordinator.onPhotoCaptureBack()
                            viewModel.currentStep = .videoCapture
                        },
                        onComplete: { photos in
                            coordinator.onPhotoCaptureComplete(photos)
                            viewModel.advanceToNextStep()
                        }
                    )
                } else {
                    // Fallback if video capture not available
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)

                        Text("Camera Error")
                            .font(.title2.bold())

                        Text("Video capture session not available")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Button("Back to Video Capture") {
                            coordinator.onPhotoCaptureBack()
                            viewModel.currentStep = .videoCapture
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }

            case .processing:
                // Placeholder - will be implemented in Story 3.8
                Text("Processing - Coming Soon")
                    .font(.title2)

            case .complete:
                // Placeholder - will be implemented in Story 5.8
                Text("Complete - Coming Soon")
                    .font(.title2)
            }

            // Camera permission error overlay
            if viewModel.showCameraPermissionError {
                CameraPermissionView(
                    onOpenSettings: {
                        viewModel.openSettings()
                    },
                    onCancel: {
                        viewModel.dismissPermissionError()
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: viewModel.showCameraPermissionError)
    }
}

#Preview {
    AIFlowEntryPoint()
        .environmentObject(AppState())
}
