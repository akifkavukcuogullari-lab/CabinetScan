//
//  PhotoCaptureView.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import SwiftUI
import AVFoundation

/// Photo capture screen for AI flow.
/// Allows user to capture 5 detail photos from different angles.
/// Per Story 2.5 - All Acceptance Criteria
struct PhotoCaptureView: View {

    // MARK: - Properties

    /// Callback when user wants to go back to video capture
    let onBack: () -> Void

    /// Callback when all photos are captured and user continues
    let onComplete: ([AICapturedPhoto]) -> Void

    /// AR session manager (passed from video capture)
    let sessionManager: AIARSessionManager

    /// Capture session from video capture (shared)
    let captureSession: AVCaptureSession

    /// View model for photo capture state
    @StateObject private var viewModel: PhotoCaptureViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Capture data manager (shared with video capture - Issue #7 fix)
    let dataManager: AICaptureDataManager

    // MARK: - Initialization

    /// Initialize with AR session manager, data manager, and callbacks
    /// - Parameters:
    ///   - sessionManager: The AR session manager for pose tracking
    ///   - captureSession: The capture session from video capture
    ///   - dataManager: The capture data manager for persistence (Issue #7 fix - required)
    ///   - onBack: Callback when user taps back
    ///   - onComplete: Callback when photos are captured and user continues
    init(
        sessionManager: AIARSessionManager,
        captureSession: AVCaptureSession,
        dataManager: AICaptureDataManager,
        onBack: @escaping () -> Void,
        onComplete: @escaping ([AICapturedPhoto]) -> Void
    ) {
        self.sessionManager = sessionManager
        self.captureSession = captureSession
        self.dataManager = dataManager
        self.onBack = onBack
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: PhotoCaptureViewModel(
            sessionManager: sessionManager,
            captureSession: captureSession,
            dataManager: dataManager
        ))
    }

    var body: some View {
        ZStack {
            // Camera preview (full screen background)
            cameraPreview
                .ignoresSafeArea()

            // Main UI overlay
            VStack(spacing: 0) {
                // Top: Back button and progress indicator
                topBar
                    .padding(.top, 60)
                    .padding(.horizontal, 20)

                Spacer()

                // Bottom: Thumbnail strip and capture/continue button
                bottomControls
                    .padding(.bottom, 50)
            }

            // Toast overlays
            toastOverlays

            // Tracking recovery toast (Story 6.7) - Use container for proper accessibility
            VStack {
                TrackingRecoveryToastContainer(
                    recoveryState: viewModel.trackingRecoveryState,
                    isVisible: $viewModel.showTrackingRecoveryToast
                )
                .padding(.top, 100)

                Spacer()
            }

            // Completion celebration overlay (AC6)
            if viewModel.showCompletionCelebration {
                completionOverlay
            }

            // Error overlay
            if let error = viewModel.errorMessage {
                errorOverlay(message: error)
            }
        }
        .onAppear {
            viewModel.setupPhotoCapture(with: captureSession)
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(item: $viewModel.currentPreviewPhoto) { preview in
            PhotoPreviewSheet(
                photo: preview,
                onDelete: {
                    viewModel.deletePhoto(at: preview.index)
                },
                onDismiss: {
                    viewModel.dismissPreview()
                }
            )
        }
        // Story 6.5: Accessibility announcements for photo capture
        .onChange(of: viewModel.photoCount) { oldCount, newCount in
            // Announce photo capture success with remaining count
            if newCount > oldCount {
                let remaining = PhotoCaptureViewModel.requiredPhotoCount - newCount
                if remaining > 0 {
                    announceForVoiceOver("Photo captured, \(remaining) remaining")
                }
            }
        }
        .onChange(of: viewModel.showCompletionCelebration) { _, showCelebration in
            // Announce completion celebration
            if showCelebration {
                announceForVoiceOver("All \(PhotoCaptureViewModel.requiredPhotoCount) photos captured. Tap Continue to process.")
            }
        }
        .onChange(of: viewModel.showBlurWarning) { _, showWarning in
            // Announce blur warning for VoiceOver users
            if showWarning {
                announceForVoiceOver("Warning: Photo may be blurry. Consider retaking.")
            }
        }
    }

    // MARK: - Accessibility Helpers

    /// Announce message for VoiceOver users
    private func announceForVoiceOver(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreview: some View {
        // Reuse the existing camera preview component
        CameraSessionPreviewView(session: captureSession)
    }

    // MARK: - Top Bar (AC1)

    @ViewBuilder
    private var topBar: some View {
        HStack {
            // Back button
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to video capture")

            Spacer()

            // Progress indicator (UX-9)
            PhotoProgressIndicator(
                count: viewModel.photoCount,
                total: PhotoCaptureViewModel.requiredPhotoCount,
                showCelebration: viewModel.showCompletionCelebration
            )

            Spacer()

            // Spacer for symmetry (same width as back button)
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Bottom Controls (AC1, AC2, AC6)

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 24) {
            // Instruction text
            if !viewModel.canContinue {
                Text("Capture photos from different angles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
            }

            // Thumbnail strip (AC3)
            PhotoThumbnailStrip(
                photos: viewModel.getThumbnailItems(),
                onTap: { index in
                    viewModel.showPreview(for: index)
                }
            )

            // Capture button or Continue button
            if viewModel.canContinue {
                // Continue button (AC6)
                Button {
                    onComplete(viewModel.getPhotosForSession())
                } label: {
                    HStack(spacing: 8) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
                }
                .accessibilityLabel("Continue to processing")
                .accessibilityHint("All photos captured, tap to continue")
                .transition(.scale.combined(with: .opacity))
            } else {
                // Capture button (UX-8, UX-12) - Story 6.5: Pass count for accessibility
                // Story 6.7: Disable when tracking is lost
                VStack(spacing: 8) {
                    PhotoCaptureButton(
                        action: {
                            viewModel.capturePhoto()
                        },
                        isEnabled: !viewModel.isCapturing && !viewModel.isCaptureDisabledByTracking,
                        currentPhotoCount: viewModel.photoCount,
                        totalPhotosRequired: PhotoCaptureViewModel.requiredPhotoCount
                    )
                    .opacity(viewModel.isCapturing || viewModel.isCaptureDisabledByTracking ? 0.5 : 1.0)

                    // Show tracking lost message (Story 6.7 - Task 4.2)
                    if viewModel.isCaptureDisabledByTracking {
                        Text(viewModel.captureDisabledMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.3), value: viewModel.canContinue)
    }

    // MARK: - Toast Overlays (AC4, AC5)

    @ViewBuilder
    private var toastOverlays: some View {
        VStack {
            Spacer()

            // Blur warning toast (AC5)
            if viewModel.showBlurWarning {
                GuidanceToast(
                    message: "Photo is blurry, consider retaking",
                    icon: "camera.metering.unknown",
                    type: .warning
                )
                .padding(.bottom, 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Angle suggestion toast (AC4)
            if viewModel.showAngleSuggestion {
                GuidanceToast(
                    message: viewModel.angleSuggestionText,
                    icon: "arrow.triangle.turn.up.right.diamond",
                    type: .info
                )
                .padding(.bottom, 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.3), value: viewModel.showBlurWarning)
        .animation(reduceMotion ? .none : .spring(response: 0.3), value: viewModel.showAngleSuggestion)
    }

    // MARK: - Completion Overlay (AC6, Task 7.4)

    @ViewBuilder
    private var completionOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .scaleEffect(reduceMotion ? 1.0 : 1.2)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.5),
                        value: viewModel.showCompletionCelebration
                    )

                Text("All photos captured!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Error Overlay

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Button("Dismiss") {
                    viewModel.errorMessage = nil
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Camera Session Preview View

/// UIViewRepresentable for AVCaptureSession preview
private struct CameraSessionPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Preview

#Preview {
    PhotoCaptureView(
        sessionManager: AIARSessionManager(),
        captureSession: AVCaptureSession(),
        dataManager: AICaptureDataManager(),
        onBack: { print("Back") },
        onComplete: { photos in print("Complete with \(photos.count) photos") }
    )
}
