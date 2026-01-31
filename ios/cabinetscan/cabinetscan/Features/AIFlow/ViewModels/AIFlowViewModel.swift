//
//  AIFlowViewModel.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import Combine
import AVFoundation

/// Root view model for AI Flow, managing overall flow state and camera permissions.
/// Coordinates between capture, processing, and output phases.
@MainActor
class AIFlowViewModel: ObservableObject {
    @Published var currentStep: AIFlowStep = .intro
    @Published var cameraPermissionStatus: CameraPermissionStatus = .notDetermined
    @Published var showCameraPermissionError: Bool = false

    private var cancellables = Set<AnyCancellable>()

    /// Flow steps for AI-based measurement
    enum AIFlowStep {
        case intro
        case videoCapture
        case photoCapture
        case processing
        case complete
    }

    /// Camera permission states
    enum CameraPermissionStatus: Equatable {
        case authorized
        case notDetermined
        case denied
    }

    init() {
        setupForegroundObserver()
        checkCameraPermission()
    }

    // MARK: - Navigation

    /// Navigate to the next step in the flow
    func advanceToNextStep() {
        switch currentStep {
        case .intro:
            currentStep = .videoCapture
        case .videoCapture:
            currentStep = .photoCapture
        case .photoCapture:
            currentStep = .processing
        case .processing:
            currentStep = .complete
        case .complete:
            break // Already at final step
        }
    }

    /// Reset flow to initial state
    func reset() {
        currentStep = .intro
        showCameraPermissionError = false
    }

    /// Go back to intro from video capture
    func backToIntro() {
        currentStep = .intro
    }

    // MARK: - Camera Permission

    /// Check current camera permission status
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionStatus = .authorized
        case .notDetermined:
            cameraPermissionStatus = .notDetermined
        case .denied, .restricted:
            cameraPermissionStatus = .denied
        @unknown default:
            cameraPermissionStatus = .denied
        }
    }

    /// Request camera permission and handle result
    func requestCameraPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        checkCameraPermission()
        return granted
    }

    /// Attempt to start scanning - handles permission flow
    func attemptStartScanning() async {
        switch cameraPermissionStatus {
        case .authorized:
            advanceToNextStep()
        case .notDetermined:
            let granted = await requestCameraPermission()
            if granted {
                advanceToNextStep()
            } else {
                showCameraPermissionError = true
            }
        case .denied:
            showCameraPermissionError = true
        }
    }

    /// Open iOS Settings app
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Dismiss camera permission error and stay on intro
    func dismissPermissionError() {
        showCameraPermissionError = false
    }

    // MARK: - Foreground Observer

    /// Listen for app returning to foreground to recheck permission
    private func setupForegroundObserver() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.checkCameraPermission()
                    // If permission was granted while in Settings, dismiss the error
                    if self.cameraPermissionStatus == .authorized {
                        self.showCameraPermissionError = false
                    }
                }
            }
            .store(in: &cancellables)
    }
}
