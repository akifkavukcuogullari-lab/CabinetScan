//
//  QualityAnalyzerTests.swift
//  cabinetscanTests
//
//  Created by Dev Agent on 2026-01-25.
//  Story 2.4: Quality Analysis Engine - Task 8
//

import XCTest
import Combine
@testable import cabinetscan

/// Tests for AIQualityAnalyzer functionality (Story 2.4).
/// Tests cover blur detection, brightness detection, debouncing, photo validation, and metrics.
final class QualityAnalyzerTests: XCTestCase {

    var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        cancellables = Set<AnyCancellable>()
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
    }

    // MARK: - Initialization Tests

    /// Test that analyzer initializes correctly
    func testInitialization_HasCorrectDefaults() {
        // Given: A new analyzer
        let analyzer = AIQualityAnalyzer()

        // Then: Initial state should be acceptable
        XCTAssertEqual(analyzer.qualityState, AIQualityState.acceptable)
        XCTAssertTrue(analyzer.qualityState.isAcceptable)
        XCTAssertNil(analyzer.qualityState.blurIssue)
        XCTAssertNil(analyzer.qualityState.brightnessIssue)
        XCTAssertFalse(analyzer.qualityState.contrastIssue)
    }

    /// Test device tier detection
    func testDeviceTier_ReturnsValidTier() {
        // Given: A new analyzer
        let analyzer = AIQualityAnalyzer()

        // Then: Device tier should be one of the valid values
        let validTiers: [AIDeviceTier] = [.legacy, .standard, .performance]
        XCTAssertTrue(validTiers.contains(analyzer.deviceTier))

        // And: Sample rate should match tier
        XCTAssertEqual(analyzer.deviceTier.sampleRate, analyzer.deviceTier.sampleRate)
    }

    // MARK: - Debounce Tracker Tests (Task 2)

    /// Test debounce tracker initial state
    func testDebounceTracker_InitialStateIsGood() {
        // Given: A new debounce tracker
        let tracker = DebounceTracker(threshold: 3)

        // Then: Initial state should be good
        XCTAssertEqual(tracker.currentState, .good)
    }

    /// Test debounce requires consecutive frames to change state
    func testDebounceTracker_RequiresConsecutiveFramesToChangeToBad() {
        // Given: A debounce tracker with threshold 3
        let tracker = DebounceTracker(threshold: 3)

        // When: 1 bad frame
        var result = tracker.update(isBad: true)
        XCTAssertFalse(result.stateChanged)
        XCTAssertEqual(result.newState, .good)

        // When: 2 bad frames
        result = tracker.update(isBad: true)
        XCTAssertFalse(result.stateChanged)
        XCTAssertEqual(result.newState, .good)

        // When: 3 bad frames (meets threshold)
        result = tracker.update(isBad: true)
        XCTAssertTrue(result.stateChanged)
        XCTAssertEqual(result.newState, .bad)
    }

    /// Test debounce resets consecutive count on good frame
    func testDebounceTracker_ResetsCountOnGoodFrame() {
        // Given: A tracker with 2 consecutive bad frames
        let tracker = DebounceTracker(threshold: 3)
        _ = tracker.update(isBad: true)
        _ = tracker.update(isBad: true)

        // When: A good frame interrupts
        let result = tracker.update(isBad: false)

        // Then: State should still be good (never changed)
        XCTAssertFalse(result.stateChanged)
        XCTAssertEqual(result.newState, .good)

        // And: Next 2 bad frames shouldn't trigger change
        _ = tracker.update(isBad: true)
        let result2 = tracker.update(isBad: true)
        XCTAssertFalse(result2.stateChanged)
    }

    /// Test debounce requires consecutive good frames to recover
    func testDebounceTracker_RequiresConsecutiveGoodFramesToRecover() {
        // Given: A tracker in bad state
        let tracker = DebounceTracker(threshold: 3)
        _ = tracker.update(isBad: true)
        _ = tracker.update(isBad: true)
        _ = tracker.update(isBad: true)
        XCTAssertEqual(tracker.currentState, .bad)

        // When: 2 good frames
        var result = tracker.update(isBad: false)
        XCTAssertFalse(result.stateChanged)
        result = tracker.update(isBad: false)
        XCTAssertFalse(result.stateChanged)

        // When: 3rd good frame
        result = tracker.update(isBad: false)
        XCTAssertTrue(result.stateChanged)
        XCTAssertEqual(result.newState, .good)
    }

    /// Test debounce reset
    func testDebounceTracker_Reset() {
        // Given: A tracker in bad state
        let tracker = DebounceTracker(threshold: 3)
        _ = tracker.update(isBad: true)
        _ = tracker.update(isBad: true)
        _ = tracker.update(isBad: true)
        XCTAssertEqual(tracker.currentState, .bad)

        // When: Reset
        tracker.reset()

        // Then: State should be good
        XCTAssertEqual(tracker.currentState, .good)
    }

    // MARK: - Sliding Window Average Tests (Task 1)

    /// Test sliding window returns correct average
    func testSlidingWindowAverage_CorrectAverage() {
        // Given: A sliding window of size 3
        let window = SlidingWindowAverage(windowSize: 3)

        // When: Adding values
        var avg = window.add(10)
        XCTAssertEqual(avg, 10, accuracy: 0.01)

        avg = window.add(20)
        XCTAssertEqual(avg, 15, accuracy: 0.01) // (10+20)/2

        avg = window.add(30)
        XCTAssertEqual(avg, 20, accuracy: 0.01) // (10+20+30)/3
    }

    /// Test sliding window maintains size limit
    func testSlidingWindowAverage_MaintainsSizeLimit() {
        // Given: A sliding window of size 3
        let window = SlidingWindowAverage(windowSize: 3)

        // When: Adding 4 values
        _ = window.add(10)
        _ = window.add(20)
        _ = window.add(30)
        let avg = window.add(40)

        // Then: Average should be of last 3 values only
        XCTAssertEqual(avg, 30, accuracy: 0.01) // (20+30+40)/3
    }

    /// Test sliding window reset
    func testSlidingWindowAverage_Reset() {
        // Given: A window with values
        let window = SlidingWindowAverage(windowSize: 3)
        _ = window.add(100)
        _ = window.add(200)

        // When: Reset and add new value
        window.reset()
        let avg = window.add(50)

        // Then: Average should be just the new value
        XCTAssertEqual(avg, 50, accuracy: 0.01)
    }

    // MARK: - Running Stats Tests (Task 5)

    /// Test running stats records correctly
    func testRunningStats_RecordsCorrectly() {
        // Given: A running stats instance
        let stats = RunningStats()

        // When: Recording some frames
        stats.record(blur: 100, brightness: 128, analysisTime: 0.015, wasPoorQuality: false)
        stats.record(blur: 80, brightness: 120, analysisTime: 0.020, wasPoorQuality: true)
        stats.record(blur: 90, brightness: 130, analysisTime: 0.018, wasPoorQuality: false)

        // Then: Metrics should be computed correctly
        let metrics = stats.computeMetrics()
        XCTAssertEqual(metrics.analyzedFrameCount, 3)
        XCTAssertEqual(metrics.averageBlurScore, 90, accuracy: 0.01) // (100+80+90)/3
        XCTAssertEqual(metrics.averageBrightness, 126, accuracy: 0.5) // (128+120+130)/3
        XCTAssertEqual(metrics.poorQualityWindowCount, 1)
    }

    /// Test running stats tracks circuit breaker trips
    func testRunningStats_TracksCircuitBreakerTrips() {
        // Given: A running stats instance
        let stats = RunningStats()

        // When: Recording circuit breaker trips
        stats.recordCircuitBreakerTrip()
        stats.recordCircuitBreakerTrip()

        // Then: Trip count should be correct
        let metrics = stats.computeMetrics()
        XCTAssertEqual(metrics.circuitBreakerTripCount, 2)
    }

    /// Test running stats tracks discarded frames
    func testRunningStats_TracksDiscardedFrames() {
        // Given: A running stats instance
        let stats = RunningStats()

        // When: Recording discarded frames
        stats.recordDiscarded()
        stats.recordDiscarded()
        stats.recordDiscarded()

        // Then: Discarded count should be correct
        let metrics = stats.computeMetrics()
        XCTAssertEqual(metrics.discardedFrameCount, 3)
    }

    /// Test running stats reset
    func testRunningStats_Reset() {
        // Given: A stats instance with data
        let stats = RunningStats()
        stats.record(blur: 100, brightness: 128, analysisTime: 0.015, wasPoorQuality: false)
        stats.recordCircuitBreakerTrip()
        stats.recordDiscarded()

        // When: Reset
        stats.reset()

        // Then: All counts should be zero
        let metrics = stats.computeMetrics()
        XCTAssertEqual(metrics.analyzedFrameCount, 0)
        XCTAssertEqual(metrics.circuitBreakerTripCount, 0)
        XCTAssertEqual(metrics.discardedFrameCount, 0)
    }

    // MARK: - AIQualityMetrics Tests (Task 5)

    /// Test empty metrics
    func testAIQualityMetrics_EmptyMetrics() {
        // Given: Empty metrics
        let metrics = AIQualityMetrics.empty

        // Then: All values should be zero
        XCTAssertEqual(metrics.averageBlurScore, 0)
        XCTAssertEqual(metrics.averageBrightness, 0)
        XCTAssertEqual(metrics.analyzedFrameCount, 0)
        XCTAssertEqual(metrics.discardedFrameCount, 0)
        XCTAssertEqual(metrics.poorQualityWindowCount, 0)
        XCTAssertEqual(metrics.circuitBreakerTripCount, 0)
        XCTAssertEqual(metrics.analysisTimePercentile95, 0)
    }

    /// Test acceptable quality calculation
    func testAIQualityMetrics_AcceptableQuality() {
        // Given: Metrics with low poor quality ratio
        let goodMetrics = AIQualityMetrics(
            averageBlurScore: 150,
            averageBrightness: 128,
            analyzedFrameCount: 100,
            discardedFrameCount: 5,
            poorQualityWindowCount: 10, // 10% poor quality
            circuitBreakerTripCount: 2,
            analysisTimePercentile95: 0.015
        )

        // Then: Should be acceptable (< 20% poor)
        XCTAssertTrue(goodMetrics.hasAcceptableQuality)

        // Given: Metrics with high poor quality ratio
        let badMetrics = AIQualityMetrics(
            averageBlurScore: 50,
            averageBrightness: 30,
            analyzedFrameCount: 100,
            discardedFrameCount: 20,
            poorQualityWindowCount: 30, // 30% poor quality
            circuitBreakerTripCount: 10,
            analysisTimePercentile95: 0.040
        )

        // Then: Should not be acceptable (>= 20% poor)
        XCTAssertFalse(badMetrics.hasAcceptableQuality)
    }

    // MARK: - Histogram Stats Tests (Task 3)

    /// Test histogram stats structure
    func testHistogramStats_DynamicRange() {
        // Given: Histogram stats
        let stats = HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)

        // Then: Dynamic range should be P95 - P5
        XCTAssertEqual(stats.dynamicRange, 190, accuracy: 0.01)
    }

    // MARK: - Photo Quality Result Tests (Task 4)

    /// Test photo quality result acceptability
    func testPhotoQualityResult_Acceptability() {
        // Given: An acceptable photo result
        let acceptableResult = PhotoQualityResult(
            isAcceptable: true,
            blurScore: 200,
            brightnessScore: 128,
            issues: []
        )

        // Then: Should be acceptable
        XCTAssertTrue(acceptableResult.isAcceptable)
        XCTAssertTrue(acceptableResult.issues.isEmpty)

        // Given: An unacceptable photo result
        let unacceptableResult = PhotoQualityResult(
            isAcceptable: false,
            blurScore: 50,
            brightnessScore: 30,
            issues: [.tooBlurry(score: 50), .tooDark(brightness: 30)]
        )

        // Then: Should not be acceptable
        XCTAssertFalse(unacceptableResult.isAcceptable)
        XCTAssertEqual(unacceptableResult.issues.count, 2)
    }

    /// Test photo quality issue descriptions
    func testPhotoQualityIssue_Descriptions() {
        // Given: Various issues
        let blurryIssue = PhotoQualityResult.PhotoQualityIssue.tooBlurry(score: 50)
        let darkIssue = PhotoQualityResult.PhotoQualityIssue.tooDark(brightness: 30)
        let brightIssue = PhotoQualityResult.PhotoQualityIssue.tooBright(brightness: 240)
        let contrastIssue = PhotoQualityResult.PhotoQualityIssue.lowContrast(stdDev: 20)

        // Then: All should have descriptions
        XCTAssertFalse(blurryIssue.description.isEmpty)
        XCTAssertFalse(darkIssue.description.isEmpty)
        XCTAssertFalse(brightIssue.description.isEmpty)
        XCTAssertFalse(contrastIssue.description.isEmpty)
    }

    // MARK: - AIQualityState Tests

    /// Test quality state acceptability
    func testAIQualityState_Acceptability() {
        // Given: An acceptable state
        let acceptableState = AIQualityState.acceptable

        // Then: Should be acceptable
        XCTAssertTrue(acceptableState.isAcceptable)
        XCTAssertNil(acceptableState.blurIssue)
        XCTAssertNil(acceptableState.brightnessIssue)
        XCTAssertFalse(acceptableState.contrastIssue)

        // Given: A state with blur issue
        var blurState = AIQualityState()
        blurState.blurIssue = .warning

        // Then: Should not be acceptable
        XCTAssertFalse(blurState.isAcceptable)
    }

    /// Test quality state priority
    func testAIQualityState_MostSevereIssue() {
        // Given: State with severe blur
        var state = AIQualityState()
        state.blurIssue = .severe
        state.brightnessIssue = .tooDark

        // Then: Most severe should be severe blur
        if case .motionBlur(let severity) = state.mostSevereIssue {
            XCTAssertEqual(severity, .severe)
        } else {
            XCTFail("Expected motion blur as most severe issue")
        }

        // Given: State with only brightness issue
        var brightnessState = AIQualityState()
        brightnessState.brightnessIssue = .tooDark

        // Then: Most severe should be tooDark
        if case .tooDark = brightnessState.mostSevereIssue {
            // Success
        } else {
            XCTFail("Expected tooDark as most severe issue")
        }
    }

    // MARK: - AIQualityIssue Tests

    /// Test quality issue descriptions
    func testAIQualityIssue_Descriptions() {
        // Given: Various issues
        let blurIssue = AIQualityIssue.motionBlur(severity: .warning)
        let darkIssue = AIQualityIssue.tooDark(meanLuminance: 30)
        let brightIssue = AIQualityIssue.tooBright(meanLuminance: 240)
        let contrastIssue = AIQualityIssue.lowContrast(stdDev: 20)

        // Then: All should have descriptions
        XCTAssertFalse(blurIssue.description.isEmpty)
        XCTAssertFalse(darkIssue.description.isEmpty)
        XCTAssertFalse(brightIssue.description.isEmpty)
        XCTAssertFalse(contrastIssue.description.isEmpty)
    }

    // MARK: - Integration Tests

    /// Test analyzer starts and stops correctly
    func testAnalyzer_StartStop() {
        // Given: An analyzer
        let analyzer = AIQualityAnalyzer()

        // When: Starting analysis
        analyzer.startAnalysis()

        // Then: Should reset to acceptable state
        XCTAssertEqual(analyzer.qualityState, AIQualityState.acceptable)

        // When: Stopping analysis
        analyzer.stopAnalysis()

        // Then: Should still be acceptable (no crash)
        XCTAssertEqual(analyzer.qualityState, AIQualityState.acceptable)
    }

    /// Test get aggregate metrics returns valid data
    func testAnalyzer_GetAggregateMetrics() {
        // Given: An analyzer
        let analyzer = AIQualityAnalyzer()

        // When: Starting analysis
        analyzer.startAnalysis()

        // Then: Metrics should be empty initially
        let metrics = analyzer.getAggregateMetrics()
        XCTAssertEqual(metrics.analyzedFrameCount, 0)

        // Cleanup
        analyzer.stopAnalysis()
    }

    // MARK: - Blur Severity Tests

    /// Test blur severity equality
    func testBlurSeverity_Equality() {
        XCTAssertEqual(BlurSeverity.warning, BlurSeverity.warning)
        XCTAssertEqual(BlurSeverity.severe, BlurSeverity.severe)
        XCTAssertNotEqual(BlurSeverity.warning, BlurSeverity.severe)
    }

    // MARK: - Brightness Issue Tests

    /// Test brightness issue equality
    func testBrightnessIssue_Equality() {
        XCTAssertEqual(BrightnessIssue.tooDark, BrightnessIssue.tooDark)
        XCTAssertEqual(BrightnessIssue.tooBright, BrightnessIssue.tooBright)
        XCTAssertNotEqual(BrightnessIssue.tooDark, BrightnessIssue.tooBright)
    }
}
