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
                    onBack: {
                        viewModel.backToIntro()
                    }
                )

            case .photoCapture:
                // Placeholder - will be implemented in Story 2.5
                Text("Photo Capture - Coming Soon")
                    .font(.title2)

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
