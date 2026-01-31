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
    @StateObject private var pipelineOrchestrator = AIPipelineOrchestrator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Show confidence warning sheet if there are warnings
    @State private var showConfidenceWarningSheet = false

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
                // Story 3.8: Processing view with pipeline orchestration
                // Story 5.6: Output adapter integration via onComplete callback
                ProcessingView(
                    orchestrator: pipelineOrchestrator,
                    showroomLogoURL: appState.showroomConfig?.branding.logoUrl.flatMap { URL(string: $0) },
                    onComplete: { pipelineResult in
                        // Story 5.6: Use output adapter to convert and store result
                        Task {
                            await coordinator.onProcessingComplete(
                                pipelineResult: pipelineResult,
                                appState: appState
                            )
                            // Check for warnings to display
                            if !coordinator.outputWarnings.isEmpty {
                                showConfidenceWarningSheet = true
                            } else {
                                viewModel.advanceToNextStep()
                            }
                        }
                    },
                    onCancel: {
                        coordinator.cancelCapture()
                        viewModel.backToIntro()
                    },
                    onRetry: {
                        // Retry processing with same capture data
                        if let captureData = coordinator.captureSessionData {
                            Task {
                                do {
                                    _ = try await pipelineOrchestrator.process(captureData: captureData)
                                } catch {
                                    // Error is handled by orchestrator state
                                    print("[AIFlowEntryPoint] Retry failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    },
                    onStartOver: {
                        coordinator.reset()
                        viewModel.currentStep = .intro
                    },
                    onNeedManualCalibration: { input in
                        coordinator.triggerManualCalibration(input: input)
                    }
                )
                .onAppear {
                    // Start processing when view appears
                    if let captureData = coordinator.captureSessionData {
                        Task {
                            do {
                                _ = try await pipelineOrchestrator.process(captureData: captureData)
                            } catch {
                                // Error is handled by orchestrator state
                                print("[AIFlowEntryPoint] Processing failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }

            case .complete:
                // Story 5.6/5.7: Complete state with confidence warnings
                // Brief transition state - will route to Selection/Review
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Scan Complete!")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.primary)

                    ProgressView()
                        .scaleEffect(0.8)
                }
                .onAppear {
                    // AppState.setMeasurementData already routes to next screen
                    // This view is just a brief transition
                }
            }

            // Story 5.7: Low confidence warning is handled via ConfidenceWarningSheet
            // (see .sheet modifier below)

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
        // Story 5.7: Confidence warning sheet for low confidence scans
        .sheet(isPresented: $showConfidenceWarningSheet) {
            ConfidenceWarningSheet(
                scoringResult: createMinimalScoringResult(),
                onDismiss: {
                    // AC2: Continue flow - clear warnings and proceed to results
                    showConfidenceWarningSheet = false
                    coordinator.clearOutputWarnings()
                    viewModel.advanceToNextStep()
                },
                onRescan: {
                    // AC3: Rescan flow - reset and return to intro
                    showConfidenceWarningSheet = false
                    coordinator.reset()
                    viewModel.currentStep = .intro
                }
            )
            .presentationDetents(coordinator.outputWarnings.count > 3 ? [.large] : [.medium, .large])
            .accessibilityIdentifier("ConfidenceWarningSheet")
        }
    }

    // MARK: - Story 5.7: Confidence Warning Helper

    /// Confidence threshold below which warnings are shown (matching AIOutputAdapter)
    private static let lowConfidenceThreshold: Float = 0.6

    /// Creates minimal ConfidenceScoringResult for warning sheet display.
    ///
    /// Uses outputWarnings from coordinator since full scoring result isn't stored.
    /// We know confidence is below the threshold because warnings were generated.
    ///
    /// Per ADR-5.7.1: This minimal adapter avoids storing full scoring data in coordinator
    /// while still providing the sheet with all the information it needs to display.
    private func createMinimalScoringResult() -> ConfidenceScoringResult {
        // Use a representative low score (below threshold) since actual score isn't stored
        let representativeLowScore = Self.lowConfidenceThreshold - 0.1

        return ConfidenceScoringResult(
            objectScores: [],  // Not needed for warning display
            overallScore: representativeLowScore,
            overallLevel: .low,
            quoteReadiness: .notRecommended,
            itemsNeedingVerification: coordinator.outputWarnings.count,
            warnings: coordinator.outputWarnings,
            processingTimeMs: 0,  // Not needed for display
            limitingObjectId: nil
        )
    }
}

#Preview {
    AIFlowEntryPoint()
        .environmentObject(AppState())
}
