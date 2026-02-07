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

    /// Show confidence warning sheet if there are warnings
    @State private var showConfidenceWarningSheet = false

    /// Pending measurement data (held while confidence warning is shown)
    @State private var pendingMeasurementData: MeasurementData?

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
                    dataManager: coordinator.captureDataManager,
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
                        dataManager: coordinator.captureDataManager,
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
                ProcessingView(
                    showroomLogoURL: appState.showroomConfig?.branding.logoUrl.flatMap { URL(string: $0) },
                    onCancel: {
                        coordinator.cancelCapture()
                        viewModel.backToIntro()
                    },
                    onStartOver: {
                        coordinator.reset()
                        viewModel.currentStep = .intro
                    },
                    onRetry: {
                        startServerProcessing()
                    },
                    coordinator: coordinator
                )
                .onAppear {
                    startServerProcessing()
                }

            case .complete:
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
        // Confidence warning sheet for low confidence scans
        .sheet(isPresented: $showConfidenceWarningSheet) {
            ConfidenceWarningSheet(
                scoringResult: createMinimalScoringResult(),
                onDismiss: {
                    showConfidenceWarningSheet = false
                    coordinator.clearOutputWarnings()
                    if let data = pendingMeasurementData {
                        pendingMeasurementData = nil
                        appState.setMeasurementData(data)
                    }
                },
                onRescan: {
                    showConfidenceWarningSheet = false
                    coordinator.reset()
                    viewModel.currentStep = .intro
                }
            )
            .presentationDetents(coordinator.outputWarnings.count > 3 ? [.large] : [.medium, .large])
            .accessibilityIdentifier("ConfidenceWarningSheet")
        }
    }

    // MARK: - Server Processing

    /// Processing task reference for cancellation
    @State private var processingTask: Task<Void, Never>?

    /// Start the server pipeline processing.
    /// Handles success (navigate to selection) and error (show in ProcessingView).
    private func startServerProcessing() {
        guard let showroomId = appState.showroomConfig?.id,
              let showroomCode = appState.showroomConfig?.showroomCode else {
            coordinator.setError(AIFlowError.processingFailed("Showroom configuration not available"))
            return
        }

        // Cancel any existing processing task
        processingTask?.cancel()

        processingTask = Task {
            do {
                let measurementData = try await coordinator.processCapture(
                    showroomId: showroomId,
                    showroomCode: showroomCode
                )

                // Check for validation warnings before navigating
                if !coordinator.outputWarnings.isEmpty {
                    pendingMeasurementData = measurementData
                    showConfidenceWarningSheet = true
                } else {
                    appState.setMeasurementData(measurementData)
                }
            } catch is CancellationError {
                print("[AIFlowEntryPoint] Processing cancelled")
            } catch {
                print("[AIFlowEntryPoint] Processing failed: \(error.localizedDescription)")
                coordinator.setError(error)
            }
        }
    }

    // MARK: - Confidence Warning Helper

    private static let lowConfidenceThreshold: Float = 0.6

    /// Creates minimal ConfidenceScoringResult for warning sheet display.
    private func createMinimalScoringResult() -> ConfidenceScoringResult {
        let representativeLowScore = Self.lowConfidenceThreshold - 0.1

        return ConfidenceScoringResult(
            objectScores: [],
            overallScore: representativeLowScore,
            overallLevel: .low,
            quoteReadiness: .notRecommended,
            itemsNeedingVerification: coordinator.outputWarnings.count,
            warnings: coordinator.outputWarnings,
            processingTimeMs: 0,
            limitingObjectId: nil
        )
    }
}

#Preview {
    AIFlowEntryPoint()
        .environmentObject(AppState())
}
