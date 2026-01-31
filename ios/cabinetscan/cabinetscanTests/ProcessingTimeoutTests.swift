//
//  ProcessingTimeoutTests.swift
//  cabinetscanTests
//
//  Story 6.8: Error Recovery - Processing Timeout
//  Tests for ProcessingTimeoutManager and timeout recovery logic
//

import XCTest
import Combine
@testable import cabinetscan

// MARK: - ProcessingTimeoutManager Tests (Task 7.1-7.7)

@MainActor
final class ProcessingTimeoutManagerTests: XCTestCase {

    var sut: ProcessingTimeoutManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = ProcessingTimeoutManager()
        cancellables = []
    }

    override func tearDown() {
        sut.stopMonitoring()
        sut = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Task 7.2: State Transitions Tests

    /// Test initial state is normal
    func testInitialStateIsNormal() {
        XCTAssertEqual(sut.timeoutState, .normal)
    }

    /// Test state transitions from normal → warning → critical
    func testStateTransitions_NormalToWarningToCritical() async {
        // Given
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.1,
            criticalThreshold: 0.2
        )
        var observedStates: [TimeoutState] = []

        let expectation = XCTestExpectation(description: "Critical state reached")

        testManager.$timeoutState
            .dropFirst() // Skip initial value
            .sink { state in
                observedStates.append(state)
                if case .critical = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        testManager.startMonitoring()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)

        // Verify we got warning before critical
        XCTAssertGreaterThanOrEqual(observedStates.count, 2)

        // Find warning and critical in order
        var foundWarning = false
        var foundCritical = false
        for state in observedStates {
            if case .warning = state {
                foundWarning = true
            }
            if case .critical = state {
                foundCritical = true
                XCTAssertTrue(foundWarning, "Warning should come before critical")
            }
        }
        XCTAssertTrue(foundCritical, "Should reach critical state")

        testManager.stopMonitoring()
    }

    // MARK: - Task 7.3: 60-Second Warning Threshold Tests

    /// Test warning state includes elapsed time
    func testWarningStateIncludesElapsedTime() async {
        // Given
        let expectation = XCTestExpectation(description: "Warning state")
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.1,
            criticalThreshold: 10.0
        )

        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning(let elapsed) = state {
                    XCTAssertGreaterThanOrEqual(elapsed, 0.1)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        testManager.startMonitoring()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        testManager.stopMonitoring()
    }

    // MARK: - Task 7.4: 90-Second Critical Threshold Tests

    /// Test critical state includes elapsed time
    func testCriticalStateIncludesElapsedTime() async {
        // Given
        let expectation = XCTestExpectation(description: "Critical state")
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.05,
            criticalThreshold: 0.1
        )

        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .critical(let elapsed) = state {
                    XCTAssertGreaterThanOrEqual(elapsed, 0.1)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        testManager.startMonitoring()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        testManager.stopMonitoring()
    }

    // MARK: - Task 7.7: Continue Waiting Resets Timeout Tests

    /// Test resetTimers resets state to normal
    func testResetTimersResetsStateToNormal() async {
        // Given - first reach warning state
        let warningExpectation = XCTestExpectation(description: "Reach warning")
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.1,
            criticalThreshold: 10.0
        )

        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning = state {
                    warningExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        testManager.startMonitoring()
        await fulfillment(of: [warningExpectation], timeout: 1.0)

        // When
        testManager.resetTimers()

        // Then
        XCTAssertEqual(testManager.timeoutState, .normal)
        testManager.stopMonitoring()
    }

    /// Test resetTimers restarts monitoring from scratch
    func testResetTimersRestartsMonitoring() async {
        // Given - reach warning state
        let warningExpectation = XCTestExpectation(description: "Reach warning again")
        warningExpectation.expectedFulfillmentCount = 2 // Should fire twice

        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.1,
            criticalThreshold: 10.0
        )

        var warningCount = 0
        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning = state {
                    warningCount += 1
                    warningExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - start, wait for warning, reset, wait for warning again
        testManager.startMonitoring()

        // Wait for first warning, then reset
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        testManager.resetTimers()

        // Then - should fire warning twice
        await fulfillment(of: [warningExpectation], timeout: 1.0)
        XCTAssertEqual(warningCount, 2)
        testManager.stopMonitoring()
    }

    // MARK: - Start/Stop Monitoring Tests

    /// Test stopMonitoring resets state to normal
    func testStopMonitoringResetsState() async {
        // Given
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.05,
            criticalThreshold: 0.1
        )
        let expectation = XCTestExpectation(description: "Reach warning")

        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        testManager.startMonitoring()
        await fulfillment(of: [expectation], timeout: 1.0)

        // Verify we're in warning state
        if case .warning = testManager.timeoutState {
            // Good
        } else {
            XCTFail("Should be in warning state")
        }

        // When
        testManager.stopMonitoring()

        // Then
        XCTAssertEqual(testManager.timeoutState, .normal)
    }

    /// Test multiple startMonitoring calls don't create duplicate timers
    func testMultipleStartMonitoringCallsAreSafe() async {
        // Given
        let expectation = XCTestExpectation(description: "Single warning")
        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.1,
            criticalThreshold: 10.0
        )

        var warningCount = 0
        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning = state {
                    warningCount += 1
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When - call startMonitoring multiple times
        testManager.startMonitoring()
        testManager.startMonitoring()
        testManager.startMonitoring()

        // Then - should only get one warning
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertEqual(warningCount, 1)
        testManager.stopMonitoring()
    }

    // MARK: - Edge Cases

    /// Test warning is skipped if already critical
    func testWarningNotReShownAfterCritical() async {
        // This tests edge case #1 from story: user dismisses 60s warning, hits 90s
        // After reaching critical, going back to warning shouldn't happen

        let testManager = ProcessingTimeoutManager(
            warningThreshold: 0.05,
            criticalThreshold: 0.1
        )

        let expectation = XCTestExpectation(description: "Critical reached")
        var stateHistory: [TimeoutState] = []

        testManager.$timeoutState
            .sink { state in
                stateHistory.append(state)
                if case .critical = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        testManager.startMonitoring()
        await fulfillment(of: [expectation], timeout: 1.0)

        // Verify state never went from critical back to warning
        var reachedCritical = false
        for state in stateHistory {
            if case .critical = state {
                reachedCritical = true
            }
            if reachedCritical {
                if case .warning = state {
                    XCTFail("Should not transition from critical back to warning")
                }
            }
        }

        testManager.stopMonitoring()
    }
}

// MARK: - TimeoutState Equatable Tests

final class TimeoutStateTests: XCTestCase {

    func testNormalEquality() {
        XCTAssertEqual(TimeoutState.normal, TimeoutState.normal)
    }

    func testWarningEquality() {
        XCTAssertEqual(TimeoutState.warning(elapsed: 60), TimeoutState.warning(elapsed: 60))
        XCTAssertNotEqual(TimeoutState.warning(elapsed: 60), TimeoutState.warning(elapsed: 90))
    }

    func testCriticalEquality() {
        XCTAssertEqual(TimeoutState.critical(elapsed: 90), TimeoutState.critical(elapsed: 90))
        XCTAssertNotEqual(TimeoutState.critical(elapsed: 90), TimeoutState.critical(elapsed: 120))
    }

    func testDifferentStatesNotEqual() {
        XCTAssertNotEqual(TimeoutState.normal, TimeoutState.warning(elapsed: 60))
        XCTAssertNotEqual(TimeoutState.warning(elapsed: 60), TimeoutState.critical(elapsed: 90))
    }

    func testWarningIsWarningProperty() {
        XCTAssertFalse(TimeoutState.normal.isWarning)
        XCTAssertTrue(TimeoutState.warning(elapsed: 60).isWarning)
        XCTAssertFalse(TimeoutState.critical(elapsed: 90).isWarning)
    }

    func testCriticalIsCriticalProperty() {
        XCTAssertFalse(TimeoutState.normal.isCritical)
        XCTAssertFalse(TimeoutState.warning(elapsed: 60).isCritical)
        XCTAssertTrue(TimeoutState.critical(elapsed: 90).isCritical)
    }
}

// MARK: - Task 7.6: Checkpoint Serialization Tests

final class PipelineCheckpointSerializationTests: XCTestCase {

    /// Test PipelineCheckpoint can be encoded to JSON
    func testCheckpointEncodesToJSON() throws {
        // Given
        let checkpoint = PipelineCheckpoint(
            phase: .depthEstimation,
            progress: 0.50,
            timestamp: Date(),
            depthFrameCount: 30,
            hasPointClouds: false,
            hasFusionResult: false,
            hasCalibrationResult: false,
            hasDetectionResults: false
        )

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checkpoint)

        // Then
        XCTAssertGreaterThan(data.count, 0)

        let jsonString = String(data: data, encoding: .utf8)
        XCTAssertNotNil(jsonString)
        // Phase raw value is "Depth Estimation" (with space)
        XCTAssertTrue(jsonString!.contains("Depth Estimation"), "JSON should contain phase: \(jsonString!)")
        XCTAssertTrue(jsonString!.contains("0.5"), "JSON should contain progress: \(jsonString!)")
        XCTAssertTrue(jsonString!.contains("30"), "JSON should contain depthFrameCount: \(jsonString!)")
    }

    /// Test PipelineCheckpoint can be decoded from JSON
    func testCheckpointDecodesFromJSON() throws {
        // Given
        let originalCheckpoint = PipelineCheckpoint(
            phase: .tsdfFusion,
            progress: 0.80,
            timestamp: Date(timeIntervalSince1970: 1706700000),
            depthFrameCount: 45,
            hasPointClouds: true,
            hasFusionResult: true,
            hasCalibrationResult: false,
            hasDetectionResults: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(originalCheckpoint)

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedCheckpoint = try decoder.decode(PipelineCheckpoint.self, from: data)

        // Then
        XCTAssertEqual(decodedCheckpoint.phase, .tsdfFusion)
        XCTAssertEqual(decodedCheckpoint.progress, 0.80, accuracy: 0.001)
        XCTAssertEqual(decodedCheckpoint.depthFrameCount, 45)
        XCTAssertTrue(decodedCheckpoint.hasPointClouds)
        XCTAssertTrue(decodedCheckpoint.hasFusionResult)
        XCTAssertFalse(decodedCheckpoint.hasCalibrationResult)
    }

    /// Test checkpoint nextPhase computed property
    func testCheckpointNextPhase() {
        // Depth estimation → point cloud generation
        let depthCheckpoint = PipelineCheckpoint(
            phase: .depthEstimation,
            progress: 0.50,
            timestamp: Date(),
            depthFrameCount: 30,
            hasPointClouds: false,
            hasFusionResult: false,
            hasCalibrationResult: false,
            hasDetectionResults: false
        )
        XCTAssertEqual(depthCheckpoint.nextPhase, .pointCloudGeneration)

        // TSDF fusion → scale calibration
        let fusionCheckpoint = PipelineCheckpoint(
            phase: .tsdfFusion,
            progress: 0.80,
            timestamp: Date(),
            depthFrameCount: 45,
            hasPointClouds: true,
            hasFusionResult: true,
            hasCalibrationResult: false,
            hasDetectionResults: false
        )
        XCTAssertEqual(fusionCheckpoint.nextPhase, .scaleCalibration)

        // Scale calibration → geometric constraints
        let calibrationCheckpoint = PipelineCheckpoint(
            phase: .scaleCalibration,
            progress: 0.88,
            timestamp: Date(),
            depthFrameCount: 45,
            hasPointClouds: true,
            hasFusionResult: true,
            hasCalibrationResult: true,
            hasDetectionResults: false
        )
        XCTAssertEqual(calibrationCheckpoint.nextPhase, .geometricConstraints)
    }

    /// Test checkpoint description
    func testCheckpointDescription() {
        let checkpoint = PipelineCheckpoint(
            phase: .depthEstimation,
            progress: 0.50,
            timestamp: Date(),
            depthFrameCount: 30,
            hasPointClouds: false,
            hasFusionResult: false,
            hasCalibrationResult: false,
            hasDetectionResults: false
        )

        XCTAssertEqual(checkpoint.description, "Checkpoint at Analyzing depth... (50%)")
    }
}

// MARK: - Cumulative Elapsed Time Tests

@MainActor
final class ProcessingTimeoutCumulativeTimeTests: XCTestCase {

    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    /// Test that elapsed time accumulates across timer resets
    /// When user clicks "Continue Waiting" after 60s warning, then another 60s passes,
    /// the total elapsed time should be ~120s, not 60s
    func testCumulativeElapsedTimeAfterReset() async {
        // Given - short thresholds for testing
        let warningThreshold: TimeInterval = 0.1
        let testManager = ProcessingTimeoutManager(
            warningThreshold: warningThreshold,
            criticalThreshold: 10.0 // Don't want critical during this test
        )

        var recordedElapsedTime: TimeInterval = 0
        let firstWarning = XCTestExpectation(description: "First warning")
        let secondWarning = XCTestExpectation(description: "Second warning")

        var warningCount = 0
        testManager.$timeoutState
            .dropFirst()
            .sink { state in
                if case .warning(let elapsed) = state {
                    warningCount += 1
                    recordedElapsedTime = elapsed
                    if warningCount == 1 {
                        firstWarning.fulfill()
                    } else if warningCount == 2 {
                        secondWarning.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        // When - start monitoring, wait for first warning
        testManager.startMonitoring()
        await fulfillment(of: [firstWarning], timeout: 1.0)

        // Reset (simulates "Continue Waiting")
        testManager.resetTimers()

        // Wait for second warning
        await fulfillment(of: [secondWarning], timeout: 1.0)

        // Then - elapsed time should include time from both cycles
        // First cycle: ~0.1s, Second cycle: ~0.1s = ~0.2s total
        XCTAssertGreaterThanOrEqual(
            recordedElapsedTime,
            warningThreshold * 1.5, // Allow some tolerance, should be ~2x but at least 1.5x
            "Elapsed time should accumulate across resets. Got \(recordedElapsedTime), expected >= \(warningThreshold * 1.5)"
        )

        testManager.stopMonitoring()
    }
}
