//
//  AICoverageAnalyzerTests.swift
//  cabinetscanTests
//
//  Created for Story 6.2: Partial Capture Handling
//

import XCTest
@testable import cabinetscan

final class AICoverageAnalyzerTests: XCTestCase {

    var analyzer: AICoverageAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = AICoverageAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Full Coverage Tests (AC1)

    func testFullCoverage_AllFourZones_ReturnsFullLevel() {
        // Given: Coverage state with all 4 zones captured
        let state = AICoverageState(capturedZones: Set(AICaptureZone.allCases))

        // When
        let result = analyzer.analyze(coverageState: state)

        // Then
        XCTAssertEqual(result.level, .full)
        XCTAssertEqual(result.coveragePercentage, 1.0)
        XCTAssertTrue(result.uncapturedZones.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty, "Full coverage should have no warnings")
    }

    func testFullCoverage_NilState_AssumesFullCoverage() {
        // Given: nil coverage state (backwards compatibility)

        // When
        let result = analyzer.analyze(coverageState: nil)

        // Then
        XCTAssertEqual(result.level, .full)
        XCTAssertEqual(result.coveragePercentage, 1.0)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - Partial Coverage Tests (AC3)

    func testPartialCoverage_ThreeZones_ReturnsPartialLevel() {
        // Given: Coverage state with 3 zones captured (75%)
        let state = AICoverageState(capturedZones: [.front, .right, .back])

        // When
        let result = analyzer.analyze(coverageState: state)

        // Then
        XCTAssertEqual(result.level, .partial)
        XCTAssertEqual(result.coveragePercentage, 0.75)
        XCTAssertEqual(result.uncapturedZones, [.left])
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("Some areas not captured"))
        XCTAssertTrue(result.warnings[0].contains("75%"))
    }

    func testPartialCoverage_TwoZones_ReturnsPartialLevel() {
        // Given: Coverage state with 2 zones captured (50%)
        let state = AICoverageState(capturedZones: [.front, .right])

        // When
        let result = analyzer.analyze(coverageState: state)

        // Then
        XCTAssertEqual(result.level, .partial)
        XCTAssertEqual(result.coveragePercentage, 0.5)
        XCTAssertEqual(result.uncapturedZones, [.back, .left])
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("50%"))
    }

    // MARK: - Severe Partial Coverage Tests (AC4)

    func testSevereCoverage_OneZone_ReturnsSevereLevel() {
        // Given: Coverage state with only 1 zone captured (25%)
        let state = AICoverageState(capturedZones: [.front])

        // When
        let result = analyzer.analyze(coverageState: state)

        // Then
        XCTAssertEqual(result.level, .severe)
        XCTAssertEqual(result.coveragePercentage, 0.25)
        XCTAssertEqual(result.uncapturedZones.count, 3)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertTrue(result.warnings.contains { $0.contains("Some areas not captured") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Incomplete scan - consider rescanning") })
    }

    func testSevereCoverage_NoZones_ReturnsSevereLevel() {
        // Given: Coverage state with no zones captured (0%)
        let state = AICoverageState(capturedZones: [])

        // When
        let result = analyzer.analyze(coverageState: state)

        // Then
        XCTAssertEqual(result.level, .severe)
        XCTAssertEqual(result.coveragePercentage, 0.0)
        XCTAssertEqual(result.uncapturedZones.count, 4)
        XCTAssertEqual(result.warnings.count, 2)
    }

    // MARK: - Quote Sufficiency Tests

    func testQuoteSufficiency_FullCoverage_IsSufficient() {
        let state = AICoverageState(capturedZones: Set(AICaptureZone.allCases))
        let result = analyzer.analyze(coverageState: state)
        XCTAssertTrue(result.isSufficientForQuote)
    }

    func testQuoteSufficiency_PartialCoverage_IsSufficient() {
        let state = AICoverageState(capturedZones: [.front, .right, .back])
        let result = analyzer.analyze(coverageState: state)
        XCTAssertTrue(result.isSufficientForQuote)
    }

    func testQuoteSufficiency_SevereCoverage_IsNotSufficient() {
        let state = AICoverageState(capturedZones: [.front])
        let result = analyzer.analyze(coverageState: state)
        XCTAssertFalse(result.isSufficientForQuote)
    }

    // MARK: - Coverage Description Tests

    func testCoverageDescription_FormatsCorrectly() {
        let state = AICoverageState(capturedZones: [.front, .right, .back])
        let result = analyzer.analyze(coverageState: state)
        XCTAssertEqual(result.coverageDescription, "75% coverage")
    }

    // MARK: - Boundary Condition Tests

    func testBoundaryCondition_Exactly50Percent_IsPartial() {
        // Given: Coverage exactly at 50% threshold
        let result = analyzer.analyze(coveragePercentage: 0.5)

        // Then: Should be partial (threshold is >= 0.5)
        XCTAssertEqual(result.level, .partial)
        XCTAssertEqual(result.warnings.count, 1, "50% should have only 1 warning (partial)")
        XCTAssertTrue(result.warnings[0].contains("Some areas not captured"))
    }

    func testBoundaryCondition_JustBelow50Percent_IsSevere() {
        // Given: Coverage just below 50% threshold (49%)
        let result = analyzer.analyze(coveragePercentage: 0.49)

        // Then: Should be severe (< 0.5)
        XCTAssertEqual(result.level, .severe)
        XCTAssertEqual(result.warnings.count, 2, "49% should have 2 warnings (severe)")
        XCTAssertTrue(result.warnings.contains { $0.contains("Some areas not captured") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Incomplete scan") })
    }

    func testBoundaryCondition_Exactly100Percent_IsFull() {
        // Given: Coverage exactly at 100%
        let result = analyzer.analyze(coveragePercentage: 1.0)

        // Then: Should be full with no warnings
        XCTAssertEqual(result.level, .full)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testBoundaryCondition_JustBelow100Percent_IsPartial() {
        // Given: Coverage just below 100% (99%)
        let result = analyzer.analyze(coveragePercentage: 0.99)

        // Then: Should be partial with 1 warning
        XCTAssertEqual(result.level, .partial)
        XCTAssertEqual(result.warnings.count, 1)
    }

    // MARK: - Analyze by Percentage Tests

    func testAnalyzeByPercentage_FullCoverage() {
        let result = analyzer.analyze(coveragePercentage: 1.0)
        XCTAssertEqual(result.level, .full)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testAnalyzeByPercentage_PartialCoverage() {
        let result = analyzer.analyze(coveragePercentage: 0.75)
        XCTAssertEqual(result.level, .partial)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testAnalyzeByPercentage_SevereCoverage() {
        let result = analyzer.analyze(coveragePercentage: 0.25)
        XCTAssertEqual(result.level, .severe)
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testAnalyzeByPercentage_NilPercentage_AssumesFullCoverage() {
        let result = analyzer.analyze(coveragePercentage: nil)
        XCTAssertEqual(result.level, .full)
        XCTAssertTrue(result.warnings.isEmpty)
    }
}
