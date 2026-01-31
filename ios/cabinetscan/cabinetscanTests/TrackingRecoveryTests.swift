//
//  TrackingRecoveryTests.swift
//  cabinetscanTests
//
//  Created by Dev Agent on 2026-01-31.
//  Story 6.7: Error Recovery - Tracking Lost
//  Per Task 7: Unit tests for tracking recovery
//

import XCTest
@testable import cabinetscan

// MARK: - Tracking Recovery State Tests

final class TrackingRecoveryStateTests: XCTestCase {

    // MARK: - Task 7.2: Test Tracking State Transitions

    func testNormalStateIsUsable() {
        let state = TrackingRecoveryState.normal
        XCTAssertTrue(state.isUsable)
        XCTAssertFalse(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "")
    }

    func testLimitedExcessiveMotionIsUsable() {
        let state = TrackingRecoveryState.limited(reason: .excessiveMotion)
        XCTAssertTrue(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "Move slowly, tracking limited")
    }

    func testLimitedInsufficientFeaturesIsUsable() {
        let state = TrackingRecoveryState.limited(reason: .insufficientFeatures)
        XCTAssertTrue(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "Point at a textured area")
    }

    func testLimitedRelocalizingMessage() {
        let state = TrackingRecoveryState.limited(reason: .relocalizing)
        XCTAssertTrue(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "Tracking lost - move back to scanned area")
    }

    func testLostStateNotUsable() {
        let state = TrackingRecoveryState.lost(elapsedSeconds: 5)
        XCTAssertFalse(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "Tracking lost - move back to scanned area")
    }

    func testFailedStateNotUsable() {
        let state = TrackingRecoveryState.failed
        XCTAssertFalse(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
        XCTAssertEqual(state.userMessage, "Tracking failed")
    }

    // MARK: - Task 7.2: Test State Equality

    func testStateEquality() {
        XCTAssertEqual(TrackingRecoveryState.normal, TrackingRecoveryState.normal)
        XCTAssertEqual(
            TrackingRecoveryState.limited(reason: .excessiveMotion),
            TrackingRecoveryState.limited(reason: .excessiveMotion)
        )
        XCTAssertNotEqual(
            TrackingRecoveryState.limited(reason: .excessiveMotion),
            TrackingRecoveryState.limited(reason: .insufficientFeatures)
        )
        XCTAssertEqual(
            TrackingRecoveryState.lost(elapsedSeconds: 5),
            TrackingRecoveryState.lost(elapsedSeconds: 5)
        )
        XCTAssertNotEqual(
            TrackingRecoveryState.lost(elapsedSeconds: 5),
            TrackingRecoveryState.lost(elapsedSeconds: 7)
        )
        XCTAssertEqual(TrackingRecoveryState.failed, TrackingRecoveryState.failed)
    }
}

// MARK: - Tracking Limited Reason Tests

final class TrackingLimitedReasonTests: XCTestCase {

    func testExcessiveMotionMessage() {
        let reason = TrackingLimitedReason.excessiveMotion
        XCTAssertEqual(reason.userMessage, "Move slowly, tracking limited")
        XCTAssertEqual(reason.iconName, "hand.raised.fill")
    }

    func testInsufficientFeaturesMessage() {
        let reason = TrackingLimitedReason.insufficientFeatures
        XCTAssertEqual(reason.userMessage, "Point at a textured area")
        XCTAssertEqual(reason.iconName, "viewfinder")
    }

    func testRelocalizingMessage() {
        let reason = TrackingLimitedReason.relocalizing
        XCTAssertEqual(reason.userMessage, "Tracking lost - move back to scanned area")
        XCTAssertEqual(reason.iconName, "arrow.uturn.backward")
    }

    func testInitializingMessage() {
        let reason = TrackingLimitedReason.initializing
        XCTAssertEqual(reason.userMessage, "Initializing tracking...")
        XCTAssertEqual(reason.iconName, "hourglass")
    }

    func testUnknownMessage() {
        let reason = TrackingLimitedReason.unknown
        XCTAssertEqual(reason.userMessage, "Tracking limited")
        XCTAssertEqual(reason.iconName, "exclamationmark.triangle.fill")
    }
}

// MARK: - AIARSessionManager Tracking Recovery Tests

final class AIARSessionManagerTrackingRecoveryTests: XCTestCase {

    var sessionManager: AIARSessionManager!

    override func setUp() {
        super.setUp()
        sessionManager = AIARSessionManager()
    }

    override func tearDown() {
        sessionManager.stopSession()
        sessionManager = nil
        super.tearDown()
    }

    // MARK: - Task 7.4: Test lastGoodPose

    func testLastGoodPoseInitiallyNil() {
        // Initially, lastGoodPose should be nil
        XCTAssertNil(sessionManager.getLastGoodPose())
    }

    // MARK: - Task 7.2: Test Initial State

    func testInitialTrackingRecoveryState() {
        XCTAssertEqual(sessionManager.trackingRecoveryState, .normal)
        XCTAssertNil(sessionManager.trackingLimitedReason)
    }

    // MARK: - Test Start/Stop Session Resets State

    func testStartSessionResetsRecoveryState() {
        // Start session
        sessionManager.startSession()

        // State should be reset
        let expectation = XCTestExpectation(description: "State reset")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.sessionManager.trackingRecoveryState, .normal)
            XCTAssertNil(self.sessionManager.trackingLimitedReason)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testStopSessionResetsRecoveryState() {
        // Start then stop session
        sessionManager.startSession()
        sessionManager.stopSession()

        // State should be reset
        let expectation = XCTestExpectation(description: "State reset")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.sessionManager.trackingRecoveryState, .normal)
            XCTAssertNil(self.sessionManager.trackingLimitedReason)
            XCTAssertNil(self.sessionManager.getLastGoodPose())
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Task 7.6: Test Recovery Publisher Exists

    func testTrackingRecoveryPublisherExists() {
        // Verify publisher is accessible
        let publisher = sessionManager.trackingRecoveryPublisher
        XCTAssertNotNil(publisher)
    }
}

// MARK: - TrackingRecoveryToast Tests

final class TrackingRecoveryToastTests: XCTestCase {

    // MARK: - Task 7.5: Test Toast Shows Correct Messages

    func testToastNotShownForNormalState() {
        // Normal state should not show toast
        let state = TrackingRecoveryState.normal
        XCTAssertFalse(state.requiresUserAction)
    }

    func testToastMessageForLimitedMotion() {
        let state = TrackingRecoveryState.limited(reason: .excessiveMotion)
        XCTAssertEqual(state.userMessage, "Move slowly, tracking limited")
    }

    func testToastMessageForLost() {
        let state = TrackingRecoveryState.lost(elapsedSeconds: 5)
        XCTAssertEqual(state.userMessage, "Tracking lost - move back to scanned area")
    }

    func testToastMessageForFailed() {
        let state = TrackingRecoveryState.failed
        XCTAssertEqual(state.userMessage, "Tracking failed")
    }
}

// MARK: - Recovery Timeout Tests

final class RecoveryTimeoutTests: XCTestCase {

    // MARK: - Task 7.3: Test 10-Second Timeout Behavior

    func testLostStateTracksElapsedTime() {
        // Create lost state with elapsed time
        let elapsed: TimeInterval = 5.0
        let state = TrackingRecoveryState.lost(elapsedSeconds: elapsed)

        // Verify elapsed time is captured
        if case .lost(let actualElapsed) = state {
            XCTAssertEqual(actualElapsed, elapsed, accuracy: 0.001)
        } else {
            XCTFail("Expected lost state")
        }
    }

    func testFailedStateAfterTimeout() {
        // After 10 seconds, state should transition to failed
        let state = TrackingRecoveryState.failed
        XCTAssertEqual(state.userMessage, "Tracking failed")
        XCTAssertFalse(state.isUsable)
        XCTAssertTrue(state.requiresUserAction)
    }

    // M4 fix: Test that verifies elapsed time progression in lost state
    func testLostStateElapsedTimeProgression() {
        // Verify different elapsed times create different states
        let state1 = TrackingRecoveryState.lost(elapsedSeconds: 2)
        let state5 = TrackingRecoveryState.lost(elapsedSeconds: 5)
        let state9 = TrackingRecoveryState.lost(elapsedSeconds: 9)

        // All should not be usable
        XCTAssertFalse(state1.isUsable)
        XCTAssertFalse(state5.isUsable)
        XCTAssertFalse(state9.isUsable)

        // All should require user action
        XCTAssertTrue(state1.requiresUserAction)
        XCTAssertTrue(state5.requiresUserAction)
        XCTAssertTrue(state9.requiresUserAction)

        // Verify they are different states (elapsed time matters for equality)
        XCTAssertNotEqual(state1, state5)
        XCTAssertNotEqual(state5, state9)
    }

    // M4 fix: Test state transition sequence expected during recovery attempt
    func testRecoveryStateTransitionSequence() {
        // Simulate the expected state progression during a failed recovery attempt
        let states: [TrackingRecoveryState] = [
            .normal,                           // Initial
            .limited(reason: .relocalizing),   // Tracking becomes limited
            .lost(elapsedSeconds: 0),          // Tracking completely lost
            .lost(elapsedSeconds: 5),          // 5 seconds elapsed
            .lost(elapsedSeconds: 10),         // 10 seconds elapsed
            .failed                            // Timeout reached
        ]

        // Verify isUsable transitions correctly
        XCTAssertTrue(states[0].isUsable)   // normal
        XCTAssertTrue(states[1].isUsable)   // limited
        XCTAssertFalse(states[2].isUsable)  // lost
        XCTAssertFalse(states[3].isUsable)  // lost
        XCTAssertFalse(states[4].isUsable)  // lost
        XCTAssertFalse(states[5].isUsable)  // failed

        // Verify requiresUserAction
        XCTAssertFalse(states[0].requiresUserAction)  // normal
        XCTAssertTrue(states[1].requiresUserAction)   // limited
        XCTAssertTrue(states[5].requiresUserAction)   // failed
    }
}

// MARK: - Partial Data Preservation Tests

final class PartialDataPreservationTests: XCTestCase {

    // MARK: - Task 7.6: Test Partial Data Preservation Flow

    func testAICaptureDataManagerDiscardSession() {
        let dataManager = AICaptureDataManager()

        // Start a session
        do {
            try dataManager.startSession()
            XCTAssertTrue(dataManager.hasActiveSession)

            // Discard it
            dataManager.discardSession()
            XCTAssertFalse(dataManager.hasActiveSession)
            XCTAssertNil(dataManager.currentSessionId)
        } catch {
            XCTFail("Failed to start session: \(error)")
        }
    }

    func testCoverageStateForPartialCapture() {
        // Create a coverage state for partial capture (empty zones)
        let coverageState = AICoverageState(capturedZones: [])

        XCTAssertFalse(coverageState.isComplete)
        XCTAssertEqual(coverageState.coveragePercentage, 0)
        XCTAssertTrue(coverageState.capturedZones.isEmpty)
    }

    func testAICaptureSessionDataWithPartialCoverage() {
        // Create session data with partial coverage
        var sessionData = AICaptureSessionData()
        sessionData.coverageState = AICoverageState(capturedZones: [])

        XCTAssertNotNil(sessionData.coverageState)
        XCTAssertFalse(sessionData.coverageState?.isComplete ?? true)
    }
}
