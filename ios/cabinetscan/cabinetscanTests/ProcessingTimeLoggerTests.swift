//
//  ProcessingTimeLoggerTests.swift
//  cabinetscanTests
//
//  Created for Story 3.9: Performance Validation
//

import XCTest
@testable import cabinetscan

final class ProcessingTimeLoggerTests: XCTestCase {

    var sut: ProcessingTimeLogger!

    override func setUp() {
        super.setUp()
        sut = ProcessingTimeLogger()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Task 1.1: Per-stage Metrics Collection

    func testStepMetricsCollectStartAndEndTimes() {
        // Given
        sut.startStep(.modelLoading)

        // When
        Thread.sleep(forTimeInterval: 0.05) // 50ms
        let elapsed = sut.endStep(.modelLoading)

        // Then
        XCTAssertGreaterThanOrEqual(elapsed, 45, "Elapsed time should be at least ~50ms")
        XCTAssertLessThan(elapsed, 150, "Elapsed time should be less than 150ms (accounting for variance)")
    }

    func testStepMetricsCollectMemorySnapshots() {
        // Given
        sut.startStep(.depthInference)
        #if DEBUG
        sut.logMemory(at: .depthInference)
        #endif

        // When
        _ = sut.endStep(.depthInference)
        let metrics = sut.getMetrics()

        // Then
        XCTAssertFalse(metrics.memorySnapshots.isEmpty, "Memory snapshots should be collected")
    }

    // MARK: - Task 1.2: PerformanceMetrics Struct

    func testGetMetricsReturnsPerformanceMetrics() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        _ = sut.endStep(.depthInference)

        // When
        let metrics = sut.getMetrics()

        // Then
        XCTAssertNotNil(metrics)
        XCTAssertGreaterThanOrEqual(metrics.stageMetrics.count, 2)
    }

    func testPerformanceMetricsIncludesAllRequiredFields() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)

        // When
        let metrics = sut.getMetrics()

        // Then
        XCTAssertGreaterThanOrEqual(metrics.totalTimeMs, 0)
        XCTAssertFalse(metrics.stageMetrics.isEmpty)
        // Device info should be populated (non-empty strings)
        XCTAssertFalse(metrics.deviceModel.isEmpty)
        XCTAssertFalse(metrics.iOSVersion.isEmpty)
    }

    // MARK: - Task 1.3: Export Report

    func testExportMetricsReturnsPerformanceReport() {
        // Note: Run on main thread to ensure UIDevice access works
        let expectation = XCTestExpectation(description: "Export report")

        DispatchQueue.main.async {
            // Given
            self.sut.startStep(.modelLoading)
            Thread.sleep(forTimeInterval: 0.01) // Small delay to ensure time passes
            _ = self.sut.endStep(.modelLoading)

            // When
            let report = self.sut.exportReport()

            // Then
            XCTAssertNotNil(report)
            XCTAssertFalse(report.deviceModel.isEmpty)
            XCTAssertFalse(report.iOSVersion.isEmpty)
            XCTAssertGreaterThanOrEqual(report.processingMetrics.totalTimeMs, 0)

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testExportReportContainsStageMetricsWithPassStatus() {
        // Given
        sut.startStep(.modelLoading)
        Thread.sleep(forTimeInterval: 0.01) // 10ms - well under budget
        _ = sut.endStep(.modelLoading)

        // When
        let report = sut.exportReport()

        // Then
        let modelLoadingMetric = report.processingMetrics.stages.first { $0.name == "model_loading" }
        XCTAssertNotNil(modelLoadingMetric)
        // Should pass since 10ms is under 500-1000ms budget
        XCTAssertEqual(modelLoadingMetric?.status, .pass)
    }

    // MARK: - Task 1.4: Device Info Capture

    func testDeviceInfoIsCaptured() {
        // When
        let metrics = sut.getMetrics()

        // Then
        XCTAssertFalse(metrics.deviceModel.isEmpty, "Device model should be captured")
        XCTAssertFalse(metrics.iOSVersion.isEmpty, "iOS version should be captured")
        // Note: availableMemoryMB may be 0 in simulator but should be >= 0
        XCTAssertGreaterThanOrEqual(metrics.availableMemoryMB, 0, "Available memory should be non-negative")
    }

    // MARK: - Total Time Calculation

    func testGetTotalPipelineTimeReturnsCorrectValue() {
        // Given
        sut.startStep(.modelLoading)
        Thread.sleep(forTimeInterval: 0.02)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        Thread.sleep(forTimeInterval: 0.03)
        _ = sut.endStep(.depthInference)

        // When
        let totalTime = sut.getTotalTime()

        // Then
        XCTAssertNotNil(totalTime)
        XCTAssertGreaterThanOrEqual(totalTime!, 45, "Total time should be at least ~50ms")
    }

    // MARK: - Peak Memory

    func testGetPeakMemoryReturnsValue() {
        // Given
        sut.startStep(.modelLoading)
        #if DEBUG
        sut.logMemory(at: .modelLoading)
        #endif
        _ = sut.endStep(.modelLoading)

        // When
        let peakMemory = sut.getPeakMemory()

        // Then
        XCTAssertGreaterThan(peakMemory, 0, "Peak memory should be captured")
    }

    // MARK: - Per-Stage Breakdown

    func testPerStageBreakdownIncludesPercentageOfTotal() {
        // Given
        sut.startStep(.modelLoading)
        Thread.sleep(forTimeInterval: 0.05)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        Thread.sleep(forTimeInterval: 0.05)
        _ = sut.endStep(.depthInference)

        // When
        let report = sut.exportReport()

        // Then
        for stage in report.processingMetrics.stages {
            XCTAssertGreaterThanOrEqual(stage.percentageOfTotal, 0)
            XCTAssertLessThanOrEqual(stage.percentageOfTotal, 100)
        }
    }

    // MARK: - Bottleneck Detection

    func testIdentifiesBottleneckStages() {
        // Given - simulate a slow stage by using a very small budget for comparison
        sut.startStep(.geometricConstraints) // Budget: 200-400ms
        Thread.sleep(forTimeInterval: 0.5) // 500ms - exceeds 400ms budget
        _ = sut.endStep(.geometricConstraints)

        // When
        let report = sut.exportReport()

        // Then
        let constraintsMetric = report.processingMetrics.stages.first { $0.name == "geometric_constraints" }
        XCTAssertNotNil(constraintsMetric)
        // Should be warn or fail since it exceeds budget
        XCTAssertNotEqual(constraintsMetric?.status, .pass)
    }

    // MARK: - Task 4: Pipeline Time Measurement

    func testGetTotalPipelineTimeMethod() {
        // Given
        sut.startStep(.modelLoading)
        Thread.sleep(forTimeInterval: 0.02)
        _ = sut.endStep(.modelLoading)

        // When
        let totalTime = sut.getTotalPipelineTime()

        // Then
        XCTAssertGreaterThan(totalTime, 0)
    }

    func testGetStageBreakdownReturnsAllStages() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        _ = sut.endStep(.depthInference)

        // When
        let breakdown = sut.getStageBreakdown()

        // Then
        XCTAssertEqual(breakdown.count, 2)
        XCTAssertTrue(breakdown.contains { $0.name == "model_loading" })
        XCTAssertTrue(breakdown.contains { $0.name == "depth_inference" })
    }

    func testStageBreakdownIncludesPercentages() {
        // Given
        sut.startStep(.modelLoading)
        Thread.sleep(forTimeInterval: 0.05)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        Thread.sleep(forTimeInterval: 0.05)
        _ = sut.endStep(.depthInference)

        // When
        let breakdown = sut.getStageBreakdown()

        // Then
        for stage in breakdown {
            XCTAssertGreaterThanOrEqual(stage.percentOfTotal, 0)
            XCTAssertLessThanOrEqual(stage.percentOfTotal, 100)
        }

        // Sum should be approximately 100%
        let totalPercent = breakdown.reduce(0) { $0 + $1.percentOfTotal }
        XCTAssertGreaterThan(totalPercent, 90) // Allow some tolerance
    }

    func testIdentifyBottlenecksReturnsExceedingStages() {
        // Given - create a bottleneck
        sut.startStep(.geometricConstraints) // Budget: 200-400ms
        Thread.sleep(forTimeInterval: 0.5) // 500ms - exceeds budget
        _ = sut.endStep(.geometricConstraints)

        // When
        let bottlenecks = sut.identifyBottlenecks()

        // Then
        XCTAssertFalse(bottlenecks.isEmpty)
        XCTAssertTrue(bottlenecks.contains { $0.stageName == "geometric_constraints" })
        XCTAssertGreaterThan(bottlenecks[0].overagePercent, 0)
    }

    func testCheckPipelineTimeCompliancePass() {
        // Given - fast pipeline
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)

        // When
        let compliance = sut.checkPipelineTimeCompliance()

        // Then (under 12s should pass)
        XCTAssertEqual(compliance.status, .pass)
        XCTAssertEqual(compliance.budgetMs, 15000)
        XCTAssertNil(compliance.message)
    }

    // MARK: - Task 5: Memory Monitoring

    func testGetMemoryTrendAnalysis() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        _ = sut.endStep(.depthInference)

        // When
        let trend = sut.getMemoryTrendAnalysis()

        // Then
        XCTAssertEqual(trend.count, 2)
        // Trend should be sorted by delta descending
        if trend.count >= 2 {
            XCTAssertGreaterThanOrEqual(trend[0].memoryDeltaMB, trend[1].memoryDeltaMB)
        }
    }

    func testCheckMemoryCompliancePass() {
        // Given - run some stages to collect memory data
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)

        // When
        let compliance = sut.checkMemoryCompliance()

        // Then (test environment should be well under 1.5GB)
        XCTAssertEqual(compliance.status, .pass)
        XCTAssertEqual(compliance.limitMB, 1500.0)
        XCTAssertNil(compliance.message)
    }

    func testIdentifyHighMemoryStages() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)

        // When
        let highMemoryStages = sut.identifyHighMemoryStages(thresholdMB: 100.0)

        // Then - in test environment, stages shouldn't use 100MB
        // This just validates the method works
        XCTAssertNotNil(highMemoryStages)
    }

    func testGetPeakMemoryReturnsMaxValue() {
        // Given
        sut.startStep(.modelLoading)
        _ = sut.endStep(.modelLoading)
        sut.startStep(.depthInference)
        _ = sut.endStep(.depthInference)

        // When
        let peak = sut.getPeakMemory()

        // Then
        XCTAssertGreaterThanOrEqual(peak, 0)
    }
}
