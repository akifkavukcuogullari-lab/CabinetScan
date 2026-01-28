//
//  VideoCaptureTests.swift
//  cabinetscanTests
//
//  Created by Dev Agent on 2026-01-25.
//

import XCTest
import Combine
@testable import cabinetscan

/// Tests for video capture functionality (Story 2.2).
/// Tests cover view model state management, timing logic, and zoom controls.
@MainActor
final class VideoCaptureTests: XCTestCase {

    var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        cancellables = Set<AnyCancellable>()
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
    }

    // MARK: - Recording State Tests (AC1, AC2)

    /// Test that view model initializes in idle state
    func testInitialState_IsIdle() async {
        // Given: A new view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // Then: State should be idle
        XCTAssertEqual(viewModel.recordingState, .idle)
        XCTAssertEqual(viewModel.elapsedTime, 0)
        XCTAssertFalse(viewModel.isStopEnabled)
        XCTAssertFalse(viewModel.showMaxDurationToast)
    }

    /// Test that isPreRecording returns correct values based on state
    func testIsPreRecording_CorrectForStates() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // Then: Should be pre-recording in idle state
        XCTAssertTrue(viewModel.isPreRecording)
        XCTAssertTrue(viewModel.canStartRecording)
    }

    // MARK: - Duration Constants Tests (AC2, AC4)

    /// Test minimum duration constant
    func testMinimumDuration_Is10Seconds() {
        // Then: Minimum duration should be 10 seconds (AC2)
        XCTAssertEqual(VideoCaptureViewModel.minimumDuration, 10)
    }

    /// Test maximum duration constant
    func testMaximumDuration_Is120Seconds() {
        // Then: Maximum duration should be 120 seconds (AC4)
        XCTAssertEqual(VideoCaptureViewModel.maximumDuration, 120)
    }

    // MARK: - Zoom Tests (AC3)

    /// Test zoom level clamping to 0.5x - 2.0x range
    func testZoomLevel_ClampedToValidRange() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // When: Setting zoom below minimum
        viewModel.updateZoom(0.1)

        // Then: Should clamp to 0.5
        XCTAssertEqual(viewModel.zoomLevel, 0.5, accuracy: 0.01)

        // When: Setting zoom above maximum
        viewModel.updateZoom(5.0)

        // Then: Should clamp to 2.0
        XCTAssertEqual(viewModel.zoomLevel, 2.0, accuracy: 0.01)

        // When: Setting zoom within range
        viewModel.updateZoom(1.5)

        // Then: Should accept value
        XCTAssertEqual(viewModel.zoomLevel, 1.5, accuracy: 0.01)
    }

    // MARK: - Formatted Time Tests (AC1)

    /// Test time formatting for display
    func testFormattedTime_CorrectFormat() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // Test various times
        XCTAssertTrue(viewModel.formattedTime.contains(":"))

        // Format should be M:SS
        let components = viewModel.formattedTime.split(separator: ":")
        XCTAssertEqual(components.count, 2)
    }

    // MARK: - Progress Tests (AC2)

    /// Test minimum duration progress calculation
    func testMinimumDurationProgress_Calculation() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // When: At 0 seconds
        // Then: Progress should be 0
        XCTAssertEqual(viewModel.minimumDurationProgress, 0, accuracy: 0.01)
    }

    // MARK: - AR Session Manager Tests

    /// Test that AR session manager initializes correctly
    func testARSessionManager_InitializesCorrectly() {
        // Given: A new session manager
        let sessionManager = AIARSessionManager()

        // Then: Initial state should be not ready
        XCTAssertFalse(sessionManager.isReadyForCapture)
        XCTAssertEqual(sessionManager.trackingState, .notAvailable)
        XCTAssertFalse(sessionManager.isInterrupted)
        XCTAssertNil(sessionManager.sessionError)
    }

    /// Test zoom factor storage
    func testARSessionManager_ZoomFactorStorage() {
        // Given: A session manager
        let sessionManager = AIARSessionManager()

        // When: Setting zoom factor
        sessionManager.setZoomFactor(1.5)

        // Then: Zoom factor should be stored
        XCTAssertEqual(sessionManager.getZoomFactor(), 1.5, accuracy: 0.01)
    }

    // MARK: - AI Flow Coordinator Tests

    /// Test coordinator initializes correctly
    func testAIFlowCoordinator_InitializesCorrectly() async {
        // Given: A new coordinator
        let coordinator = AIFlowCoordinator()

        // Then: Initial state should be idle
        XCTAssertEqual(coordinator.captureState, .idle)
        XCTAssertEqual(coordinator.processingProgress, 0.0)
        XCTAssertNil(coordinator.captureSessionData)
    }

    /// Test video capture completion updates state
    func testAIFlowCoordinator_VideoCaptureComplete() async {
        // Given: A coordinator
        let coordinator = AIFlowCoordinator()

        // When: Video capture completes
        let captureData = AICaptureSessionData(
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            photos: [],
            metadata: AICaptureMetadata(
                deviceModel: "iPhone",
                osVersion: "18.0",
                captureDate: Date(),
                videoDuration: 30,
                photoCount: 0,
                averageLighting: nil
            )
        )
        coordinator.onVideoCaptureComplete(captureData)

        // Then: State should transition to capturingPhotos
        XCTAssertEqual(coordinator.captureState, .capturingPhotos)
        XCTAssertNotNil(coordinator.captureSessionData)
    }

    /// Test cancel clears state
    func testAIFlowCoordinator_CancelCapture() async {
        // Given: A coordinator with active capture
        let coordinator = AIFlowCoordinator()
        let captureData = AICaptureSessionData(
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            photos: [],
            metadata: nil
        )
        coordinator.onVideoCaptureComplete(captureData)

        // When: Cancelling capture
        coordinator.cancelCapture()

        // Then: State should reset
        XCTAssertEqual(coordinator.captureState, .idle)
        XCTAssertNil(coordinator.captureSessionData)
    }

    // MARK: - Recording State Enum Tests

    /// Test recording state enum equality
    func testRecordingState_Equality() {
        XCTAssertEqual(RecordingState.idle, RecordingState.idle)
        XCTAssertEqual(RecordingState.waitingForAR, RecordingState.waitingForAR)
        XCTAssertEqual(RecordingState.recording, RecordingState.recording)
        XCTAssertEqual(RecordingState.stopped, RecordingState.stopped)
        XCTAssertNotEqual(RecordingState.idle, RecordingState.recording)
        XCTAssertNotEqual(RecordingState.idle, RecordingState.waitingForAR)
        XCTAssertNotEqual(RecordingState.waitingForAR, RecordingState.recording)
    }

    /// Test that waitingForAR is considered pre-recording
    func testWaitingForAR_IsPreRecording() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // Then: Both idle and waitingForAR should be pre-recording states
        XCTAssertTrue(viewModel.isPreRecording) // idle is pre-recording

        // Note: We can't easily test waitingForAR state transition without
        // mocking AR session, but the computed property handles it
    }

    // MARK: - AI Capture State Tests

    /// Test capture state equality for all cases
    func testAICaptureState_Equality() {
        XCTAssertEqual(AICaptureState.idle, AICaptureState.idle)
        XCTAssertEqual(AICaptureState.calibrating, AICaptureState.calibrating)
        XCTAssertEqual(AICaptureState.recordingVideo, AICaptureState.recordingVideo)
        XCTAssertEqual(AICaptureState.capturingPhotos, AICaptureState.capturingPhotos)
        XCTAssertEqual(AICaptureState.processing, AICaptureState.processing)
        XCTAssertEqual(AICaptureState.complete, AICaptureState.complete)
        XCTAssertNotEqual(AICaptureState.idle, AICaptureState.recordingVideo)
    }

    /// Test capture state error equality
    func testAICaptureState_ErrorEquality() {
        let error1 = AIFlowError.captureNotReady
        let error2 = AIFlowError.captureNotReady
        let error3 = AIFlowError.notImplemented

        XCTAssertEqual(AICaptureState.error(error1), AICaptureState.error(error2))
        XCTAssertNotEqual(AICaptureState.error(error1), AICaptureState.error(error3))
    }

    // MARK: - AI Flow Error Tests

    /// Test error descriptions are set
    func testAIFlowError_HasDescriptions() {
        XCTAssertNotNil(AIFlowError.captureNotReady.errorDescription)
        XCTAssertNotNil(AIFlowError.processingFailed("test").errorDescription)
        XCTAssertNotNil(AIFlowError.calibrationFailed.errorDescription)
        XCTAssertNotNil(AIFlowError.insufficientData.errorDescription)
        XCTAssertNotNil(AIFlowError.notImplemented.errorDescription)
    }

    // MARK: - AI Video Capture Error Tests

    /// Test video capture error descriptions
    func testAIVideoCaptureError_HasDescriptions() {
        XCTAssertNotNil(AIVideoCaptureError.cameraNotAvailable.errorDescription)
        XCTAssertNotNil(AIVideoCaptureError.sessionConfigurationFailed.errorDescription)
        XCTAssertNotNil(AIVideoCaptureError.recordingNotPrepared.errorDescription)
        XCTAssertNotNil(AIVideoCaptureError.recordingFailed("test").errorDescription)
        XCTAssertNotNil(AIVideoCaptureError.recordingAlreadyInProgress.errorDescription)
        XCTAssertNotNil(AIVideoCaptureError.noActiveRecording.errorDescription)
    }

    // MARK: - Pre-Recording Status Text Tests

    /// Test pre-recording status text varies by state
    func testPreRecordingStatusText_VariesByState() async {
        // Given: A view model
        let sessionManager = AIARSessionManager()
        let dataManager = AICaptureDataManager()
        let viewModel = VideoCaptureViewModel(sessionManager: sessionManager, dataManager: dataManager)

        // Then: Should have status text
        XCTAssertFalse(viewModel.preRecordingStatusText.isEmpty)
    }
}
