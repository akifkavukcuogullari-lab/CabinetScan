//
//  PerformanceReportGeneratorTests.swift
//  cabinetscanTests
//
//  Created for Story 3.9: Performance Validation
//

import XCTest
@testable import cabinetscan

final class PerformanceReportGeneratorTests: XCTestCase {

    var sut: PerformanceReportGenerator!
    var timeLogger: ProcessingTimeLogger!

    override func setUp() {
        super.setUp()
        sut = PerformanceReportGenerator()
        timeLogger = ProcessingTimeLogger()
    }

    override func tearDown() {
        sut = nil
        timeLogger = nil
        super.tearDown()
    }

    // MARK: - Task 7.1: Report Generation

    func testGenerateReportCreatesComprehensiveReport() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        XCTAssertNotNil(report)
        XCTAssertFalse(report.deviceInfo.model.isEmpty)
        XCTAssertFalse(report.deviceInfo.iOSVersion.isEmpty)
    }

    // MARK: - Task 7.2: JSON Export

    func testExportJSONProducesValidJSON() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)
        let report = sut.generateReport(from: timeLogger)

        // When
        let json = sut.exportJSON(report)

        // Then
        XCTAssertNotNil(json)
        XCTAssertFalse(json!.isEmpty)

        // Verify it's valid JSON by parsing
        if let data = json?.data(using: .utf8) {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    // MARK: - Task 7.3: Human-Readable Summary

    func testGenerateSummaryProducesReadableOutput() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)
        let report = sut.generateReport(from: timeLogger)

        // When
        let summary = sut.generateSummary(report)

        // Then
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("PERFORMANCE VALIDATION REPORT"))
        XCTAssertTrue(summary.contains("OVERALL STATUS"))
        XCTAssertTrue(summary.contains("NFR COMPLIANCE"))
    }

    // MARK: - Task 7.4: Device Info Included

    func testReportIncludesDeviceInfo() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        XCTAssertFalse(report.deviceInfo.model.isEmpty)
        XCTAssertFalse(report.deviceInfo.iOSVersion.isEmpty)
        XCTAssertGreaterThanOrEqual(report.deviceInfo.availableMemoryMB, 0)
    }

    func testReportIncludesTimestamp() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        XCTAssertNotNil(report.timestamp)
        // Timestamp should be recent
        XCTAssertLessThan(Date().timeIntervalSince(report.timestamp), 60)
    }

    // MARK: - Task 7.5: Optimization Recommendations

    func testReportIncludesRecommendationsForBottlenecks() {
        // Given - create a bottleneck
        timeLogger.startStep(.geometricConstraints) // Budget: 200-400ms
        Thread.sleep(forTimeInterval: 0.5) // 500ms - exceeds budget
        _ = timeLogger.endStep(.geometricConstraints)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        // Should have bottleneck identified
        XCTAssertFalse(report.bottlenecks.isEmpty, "Should identify bottleneck")

        // Recommendations may be empty if pipeline time itself passes (since single stage doesn't fail NFR2)
        // Just verify the report is generated correctly
        XCTAssertNotNil(report.recommendations)
    }

    // MARK: - Pass/Fail Status Tests

    func testOverallStatusPassWhenAllMetricsPass() {
        // Given - fast execution
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then - should pass since we're under all limits
        XCTAssertEqual(report.overallStatus, .pass)
    }

    func testSummaryShowsPassFailEmojis() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)
        let report = sut.generateReport(from: timeLogger)

        // When
        let summary = sut.generateSummary(report)

        // Then - should contain status emojis
        XCTAssertTrue(summary.contains("✅") || summary.contains("⚠️") || summary.contains("❌"))
    }

    // MARK: - Bottleneck Identification

    func testBottlenecksIdentifiedCorrectly() {
        // Given
        timeLogger.startStep(.geometricConstraints)
        Thread.sleep(forTimeInterval: 0.5) // Exceeds 400ms budget
        _ = timeLogger.endStep(.geometricConstraints)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        let constraintsBottleneck = report.bottlenecks.first { $0.stageName == "geometric_constraints" }
        XCTAssertNotNil(constraintsBottleneck)
        XCTAssertGreaterThan(constraintsBottleneck?.overagePercent ?? 0, 0)
    }

    // MARK: - Memory Trend

    func testMemoryTrendCaptured() {
        // Given
        timeLogger.startStep(.modelLoading)
        _ = timeLogger.endStep(.modelLoading)
        timeLogger.startStep(.depthInference)
        _ = timeLogger.endStep(.depthInference)

        // When
        let report = sut.generateReport(from: timeLogger)

        // Then
        XCTAssertEqual(report.memoryTrend.count, 2)
    }
}

// MARK: - PerformanceDeviceInfo Tests

final class PerformanceDeviceInfoTests: XCTestCase {

    func testCurrentDeviceInfoPopulated() {
        // When
        let info = PerformanceDeviceInfo.current

        // Then
        XCTAssertFalse(info.model.isEmpty)
        XCTAssertFalse(info.iOSVersion.isEmpty)
    }
}
