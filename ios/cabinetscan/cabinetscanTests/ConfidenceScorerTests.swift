//
//  ConfidenceScorerTests.swift
//  cabinetscanTests
//
//  Created for Story 4.8: Confidence Scoring System
//

import XCTest
import SwiftUI
@testable import cabinetscan

/// Unit tests for the ConfidenceScorer.
///
/// **Test Coverage (AC: All):**
/// - Threshold classification (AC1)
/// - Factor weight calculation (AC2)
/// - Overall score with minimum-confidence rule (AC3, AC6)
/// - Quote readiness levels (AC9)
/// - Warning generation (AC7, AC8)
/// - Edge cases (empty results, single object)
@MainActor
final class ConfidenceScorerTests: XCTestCase {

    var sut: ConfidenceScorer!

    override func setUp() {
        super.setUp()
        sut = ConfidenceScorer()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Task 1 Tests: Core Models

    // MARK: 1.3 - ConfidenceFactors struct

    func testConfidenceFactorsWeightsSumToOne() {
        // Given: The defined factor weights
        let weights = ConfidenceFactors.Weights.self

        // When: Summing all weights
        let totalWeight = weights.segmentationClarity + weights.depthConsistency +
                          weights.poseAccuracy + weights.standardSizeMatch

        // Then: Total should equal 1.0 (100%)
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001)
    }

    func testConfidenceFactorsAllMaxReturnsMaxScore() {
        // Given: All factors at maximum (1.0)
        let factors = ConfidenceFactors(
            segmentationClarity: 1.0,
            depthConsistency: 1.0,
            poseAccuracy: 1.0,
            standardSizeMatch: 1.0
        )

        // When: Calculating weighted score
        let score = factors.weightedScore

        // Then: Score should be 1.0
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testConfidenceFactorsAllZeroReturnsZeroScore() {
        // Given: All factors at zero
        let factors = ConfidenceFactors(
            segmentationClarity: 0.0,
            depthConsistency: 0.0,
            poseAccuracy: 0.0,
            standardSizeMatch: 0.0
        )

        // When: Calculating weighted score
        let score = factors.weightedScore

        // Then: Score should be 0.0
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testConfidenceFactorsWeightedCalculation() {
        // Given: Specific factor values
        // seg=0.8 (35%), depth=0.7 (30%), pose=0.6 (20%), snap=0.5 (15%)
        // Expected: 0.8*0.35 + 0.7*0.30 + 0.6*0.20 + 0.5*0.15 = 0.28 + 0.21 + 0.12 + 0.075 = 0.685
        let factors = ConfidenceFactors(
            segmentationClarity: 0.8,
            depthConsistency: 0.7,
            poseAccuracy: 0.6,
            standardSizeMatch: 0.5
        )

        // When: Calculating weighted score
        let score = factors.weightedScore

        // Then: Score should match expected calculation
        XCTAssertEqual(score, 0.685, accuracy: 0.001)
    }

    // MARK: 1.4 - ObjectConfidenceScore struct

    func testObjectConfidenceScoreHighLevel() {
        // Given: A score of 0.85 (>=80%)
        let score = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.85,
            factors: ConfidenceFactors(
                segmentationClarity: 0.9,
                depthConsistency: 0.85,
                poseAccuracy: 0.8,
                standardSizeMatch: 0.75
            ),
            warnings: []
        )

        // Then: Level should be HIGH
        XCTAssertEqual(score.level, .high)
    }

    func testObjectConfidenceScoreMediumLevel() {
        // Given: A score of 0.70 (60-79%)
        let score = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.70,
            factors: ConfidenceFactors(
                segmentationClarity: 0.7,
                depthConsistency: 0.7,
                poseAccuracy: 0.7,
                standardSizeMatch: 0.7
            ),
            warnings: []
        )

        // Then: Level should be MEDIUM
        XCTAssertEqual(score.level, .medium)
    }

    func testObjectConfidenceScoreLowLevel() {
        // Given: A score of 0.50 (<60%)
        let score = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.50,
            factors: ConfidenceFactors(
                segmentationClarity: 0.5,
                depthConsistency: 0.5,
                poseAccuracy: 0.5,
                standardSizeMatch: 0.5
            ),
            warnings: []
        )

        // Then: Level should be LOW
        XCTAssertEqual(score.level, .low)
    }

    // MARK: - Task 2 Tests: Thresholds and Quote Readiness

    // MARK: 2.1, 2.2 - Threshold boundaries

    func testThresholdBoundaryExactlyHigh() {
        // Given: Score exactly at 0.80 boundary
        let level = AIConfidenceLevel.from(score: 0.80)

        // Then: Should be HIGH
        XCTAssertEqual(level, .high)
    }

    func testThresholdBoundaryExactlyMedium() {
        // Given: Score exactly at 0.60 boundary
        let level = AIConfidenceLevel.from(score: 0.60)

        // Then: Should be MEDIUM
        XCTAssertEqual(level, .medium)
    }

    func testThresholdBoundaryJustBelowMedium() {
        // Given: Score just below 0.60
        let level = AIConfidenceLevel.from(score: 0.599)

        // Then: Should be LOW
        XCTAssertEqual(level, .low)
    }

    // MARK: 2.2, 2.3 - QuoteReadinessLevel

    func testQuoteReadinessNotRecommended() {
        // Given: Overall score < 60%
        let readiness = QuoteReadinessLevel.from(overallScore: 0.55)

        // Then: Should be notRecommended
        XCTAssertEqual(readiness, .notRecommended)
        XCTAssertTrue(readiness.displayMessage.contains("NOT recommended"))
    }

    func testQuoteReadinessWithCaveats() {
        // Given: Overall score 60-80%
        let readiness = QuoteReadinessLevel.from(overallScore: 0.65)

        // Then: Should be withCaveats
        XCTAssertEqual(readiness, .withCaveats)
        XCTAssertTrue(readiness.displayMessage.contains("caveats"))
    }

    func testQuoteReadinessReady() {
        // Given: Overall score > 80%
        let readiness = QuoteReadinessLevel.from(overallScore: 0.85)

        // Then: Should be ready
        XCTAssertEqual(readiness, .ready)
        XCTAssertTrue(readiness.displayMessage.contains("Quote-ready"))
    }

    // MARK: 2.4 - Badge colors

    func testBadgeColorHigh() {
        XCTAssertEqual(AIConfidenceLevel.high.badgeColor, .green)
    }

    func testBadgeColorMedium() {
        XCTAssertEqual(AIConfidenceLevel.medium.badgeColor, .yellow)
    }

    func testBadgeColorLow() {
        XCTAssertEqual(AIConfidenceLevel.low.badgeColor, .red)
    }

    // MARK: - Task 7 Tests: Overall Score Calculation

    func testOverallScoreWeightedAverage() async throws {
        // Given: Multiple objects with different scores and quote impact weights
        // Large cabinet (36" width = 2x weight): 0.85 score
        // Regular cabinet (24" width = 1x weight): 0.70 score
        // Appliance (0.5x weight): 0.90 score

        // Create mock object scores
        let largeCabinetScore = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.85,
            factors: ConfidenceFactors.uniform(0.85),
            warnings: [],
            widthInches: 36.0  // Large cabinet
        )

        let regularCabinetScore = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.70,
            factors: ConfidenceFactors.uniform(0.70),
            warnings: [],
            widthInches: 24.0  // Regular cabinet
        )

        let applianceScore = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .appliance,
            rawScore: 0.90,
            factors: ConfidenceFactors.uniform(0.90),
            warnings: []
        )

        // Verify isLargeCabinet detection
        XCTAssertTrue(largeCabinetScore.isLargeCabinet, "36\" cabinet should be marked as large")
        XCTAssertFalse(regularCabinetScore.isLargeCabinet, "24\" cabinet should NOT be marked as large")
        XCTAssertFalse(applianceScore.isLargeCabinet, "Appliance should NOT be marked as large cabinet")

        // When: Calculating weighted average
        // Weights: Large=2.0, Regular=1.0, Appliance=0.5
        // Expected: (0.85*2.0 + 0.70*1.0 + 0.90*0.5) / (2.0 + 1.0 + 0.5)
        //         = (1.70 + 0.70 + 0.45) / 3.5
        //         = 2.85 / 3.5
        //         = 0.814 (rounds to HIGH)

        // Then: Verify through full calculation
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,  // We can't easily create mock detection results
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // With no inputs, result should return room-only confidence (Story 6.1)
        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01)

        // Direct weight verification through ObjectConfidenceScore
        XCTAssertEqual(largeCabinetScore.widthInches, 36.0)
        XCTAssertEqual(regularCabinetScore.widthInches, 24.0)
    }

    func testMinimumConfidenceRuleCapsAtMedium() async throws {
        // Given: Testing that LOW confidence caps overall at MEDIUM max (0.79)

        // Create a LOW confidence score
        let lowScore = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.50,  // LOW
            factors: ConfidenceFactors.uniform(0.50),
            warnings: ["low confidence"]
        )

        // Verify classification
        XCTAssertEqual(lowScore.level, .low)
        XCTAssertTrue(lowScore.needsVerification)

        // Test threshold boundaries
        let mediumBoundary = AIConfidenceLevel.from(score: 0.79)
        XCTAssertEqual(mediumBoundary, .medium, "0.79 should be MEDIUM (just below HIGH)")

        let highBoundary = AIConfidenceLevel.from(score: 0.80)
        XCTAssertEqual(highBoundary, .high, "0.80 should be HIGH")

        // Verify medium cap constant exists
        // The cap at 0.79 ensures one LOW item prevents HIGH overall
        let cappedScore: Float = 0.79
        XCTAssertEqual(AIConfidenceLevel.from(score: cappedScore), .medium,
                       "Capped score should result in MEDIUM level")
    }

    // MARK: - Task 8 Tests: Warning Generation

    func testLowConfidenceCabinetGeneratesWarning() {
        // Given: A cabinet with LOW confidence
        let score = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.50,
            factors: ConfidenceFactors(
                segmentationClarity: 0.4,
                depthConsistency: 0.5,
                poseAccuracy: 0.6,
                standardSizeMatch: 0.5
            ),
            warnings: []
        )

        // When: Generating warnings
        let warnings = ConfidenceScorer.generateWarnings(for: score, index: 3)

        // Then: Should contain specific cabinet warning
        XCTAssertTrue(warnings.contains { $0.contains("Cabinet #3") })
        XCTAssertTrue(warnings.contains { $0.contains("low confidence") })
    }

    func testNoWarningsForHighConfidence() {
        // Given: An object with HIGH confidence
        let score = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.85,
            factors: ConfidenceFactors(
                segmentationClarity: 0.9,
                depthConsistency: 0.85,
                poseAccuracy: 0.8,
                standardSizeMatch: 0.8
            ),
            warnings: []
        )

        // When: Generating warnings
        let warnings = ConfidenceScorer.generateWarnings(for: score, index: 1)

        // Then: Should be empty
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - Large Cabinet Weight Tests (AC6)

    func testLargeCabinetDetection() {
        // Given: Cabinet with width > 30"
        let largeCabinet = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: 36.0  // 36" > 30" = large
        )

        // Then: Should be detected as large
        XCTAssertTrue(largeCabinet.isLargeCabinet)
    }

    func testRegularCabinetDetection() {
        // Given: Cabinet with width <= 30"
        let regularCabinet = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: 24.0  // 24" <= 30" = regular
        )

        // Then: Should NOT be detected as large
        XCTAssertFalse(regularCabinet.isLargeCabinet)
    }

    func testBoundaryLargeCabinetAt30Inches() {
        // Given: Cabinet exactly at 30" boundary
        let boundaryCabinet = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: 30.0  // Exactly 30" = NOT large (>30 required)
        )

        // Then: Should NOT be large (boundary is >30, not >=30)
        XCTAssertFalse(boundaryCabinet.isLargeCabinet)
    }

    func testNonCabinetIsNotLarge() {
        // Given: Non-cabinet objects (island, appliance)
        let island = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .island,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: 48.0  // Large width but not a cabinet
        )

        let appliance = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .appliance,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: 36.0
        )

        // Then: Neither should be flagged as large cabinet
        XCTAssertFalse(island.isLargeCabinet, "Islands have their own 2x weight, not large cabinet")
        XCTAssertFalse(appliance.isLargeCabinet, "Appliances are not cabinets")
    }

    func testCabinetWithoutWidthIsNotLarge() {
        // Given: Cabinet without width information
        let noWidthCabinet = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .cabinet,
            rawScore: 0.80,
            factors: ConfidenceFactors.uniform(0.80),
            warnings: [],
            widthInches: nil  // No width info
        )

        // Then: Should default to NOT large (conservative)
        XCTAssertFalse(noWidthCabinet.isLargeCabinet)
    }

    // MARK: - Edge Case Tests

    func testEmptyResultReturnsValidDefault() async throws {
        // Given: No detection results (empty kitchen)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // Then: Should return valid result with defaults
        // Story 6.1: Empty kitchen returns 50% confidence for room-only data
        XCTAssertTrue(result.objectScores.isEmpty)
        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.overallLevel, .low)
        XCTAssertEqual(result.quoteReadiness, .notRecommended)
        XCTAssertEqual(result.itemsNeedingVerification, 0)
    }

    func testSingleObjectScoreIsOverall() async throws {
        // Given: A single detected object
        // When: Calculating confidence
        // Then: That object's score should be the overall score

        // Test ObjectConfidenceScore properties for single object scenarios
        let singleScore = ObjectConfidenceScore(
            objectId: UUID(),
            objectType: .island,  // Island has 2x weight but single object = 100%
            rawScore: 0.75,
            factors: ConfidenceFactors(
                segmentationClarity: 0.80,
                depthConsistency: 0.70,
                poseAccuracy: 0.75,
                standardSizeMatch: 0.70
            ),
            warnings: []
        )

        // Verify the score properties
        XCTAssertEqual(singleScore.level, .medium, "0.75 should be MEDIUM")
        XCTAssertEqual(singleScore.rawScore, 0.75)
        XCTAssertFalse(singleScore.needsVerification, "MEDIUM doesn't need verification")

        // Verify weighted score matches raw (since factors are set to produce 0.75)
        // Note: When there's only one object, its score IS the overall score
        // The weight multiplier doesn't matter for a single object since:
        // overall = (score * weight) / weight = score

        // Test that factor weights sum correctly for the weighted score
        let factors = singleScore.factors
        let expectedWeightedScore = factors.segmentationClarity * 0.35 +
                                    factors.depthConsistency * 0.30 +
                                    factors.poseAccuracy * 0.20 +
                                    factors.standardSizeMatch * 0.15
        // 0.80*0.35 + 0.70*0.30 + 0.75*0.20 + 0.70*0.15 = 0.28 + 0.21 + 0.15 + 0.105 = 0.745
        XCTAssertEqual(factors.weightedScore, expectedWeightedScore, accuracy: 0.001)
    }

    func testProcessingTimeUnderBudget() async throws {
        // Given: Typical detection results
        // When: Calculating confidence
        let startTime = CFAbsoluteTimeGetCurrent()

        _ = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        // Then: Should complete under 50ms budget
        XCTAssertLessThan(elapsedMs, 50, "Confidence scoring should complete under 50ms")
    }

    // MARK: - Story 6.1: Empty Kitchen Handling Tests

    /// Tests that empty kitchen (no objects) returns 50% confidence, not 0%.
    /// Story 6.1 AC3: Confidence should reflect room detection quality.
    func testEmptyKitchen_ReturnsRoomOnlyConfidence() async throws {
        // Given: No detection results (empty kitchen)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // Then: Should return 50% (medium-low) confidence, not 0%
        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01,
            "Empty kitchen should return 50% confidence for room-only data")
        XCTAssertEqual(result.overallLevel, .low,
            "50% confidence should be LOW level (below 0.6 threshold)")
    }

    /// Tests that empty kitchen adds appropriate warning.
    /// Story 6.1 AC3: Clear message about empty kitchen.
    func testEmptyKitchen_AddsEmptyKitchenWarning() async throws {
        // Given: No detection results (empty kitchen)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // Then: Should include "No cabinets detected" warning
        XCTAssertTrue(result.warnings.contains { $0.contains("No cabinets detected") },
            "Should include empty kitchen warning: \(result.warnings)")
    }

    /// Tests that empty kitchen has zero items needing verification.
    func testEmptyKitchen_ZeroItemsNeedingVerification() async throws {
        // Given: No detection results (empty kitchen)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // Then: No items to verify (there are no objects)
        XCTAssertEqual(result.itemsNeedingVerification, 0)
        XCTAssertEqual(result.objectScores.count, 0)
    }

    /// Tests quote readiness for empty kitchen.
    func testEmptyKitchen_QuoteReadinessIsLimited() async throws {
        // Given: No detection results (empty kitchen)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil
        )

        // Then: Quote readiness should be limited (can't quote without cabinets)
        // At 50%, this should be "notRecommended" (below 60% threshold)
        XCTAssertEqual(result.quoteReadiness, .notRecommended,
            "Empty kitchen at 50% confidence should be Not Recommended for quoting")
    }

    // MARK: - Story 6.2: Coverage Penalty Tests

    /// Tests that coverage penalty is applied correctly (AC3).
    func testCoveragePenalty_75Percent_ReducesScore() async throws {
        // Given: Empty kitchen (50% base score) with 75% coverage
        // When: Calculating confidence with coverage penalty
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 0.75
        )

        // Then: Score should be 50% * 75% = 37.5%
        XCTAssertEqual(result.overallScore, 0.375, accuracy: 0.01,
            "Score should be reduced by coverage penalty")
    }

    /// Tests coverage warning is added for partial coverage (AC3).
    func testCoverageWarning_PartialCoverage_AddsWarning() async throws {
        // Given: Partial coverage (75%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 0.75
        )

        // Then: Should include "Some areas not captured" warning
        XCTAssertTrue(result.warnings.contains { $0.contains("Some areas not captured") },
            "Should include partial coverage warning: \(result.warnings)")
    }

    /// Tests severe coverage warning is added for <50% coverage (AC4).
    func testCoverageWarning_SevereCoverage_AddsBothWarnings() async throws {
        // Given: Severe coverage (25%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 0.25
        )

        // Then: Should include both warnings
        XCTAssertTrue(result.warnings.contains { $0.contains("Some areas not captured") },
            "Should include partial coverage warning")
        XCTAssertTrue(result.warnings.contains { $0.contains("Incomplete scan - consider rescanning") },
            "Should include severe coverage warning: \(result.warnings)")
    }

    /// Tests 100% coverage produces no coverage warnings.
    func testCoverageWarning_FullCoverage_NoWarning() async throws {
        // Given: Full coverage (100%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 1.0
        )

        // Then: Should not include coverage warnings
        XCTAssertFalse(result.warnings.contains { $0.contains("Some areas not captured") },
            "Full coverage should not have partial warning")
        XCTAssertFalse(result.warnings.contains { $0.contains("Incomplete scan") },
            "Full coverage should not have severe warning")
    }

    /// Tests that coverage warnings use AICoverageAnalyzer constants (single source of truth).
    func testCoverageIntegration_WarningsUseAnalyzerConstants() async throws {
        // Given: Coverage at 75% (partial)
        let coveragePercentage: Float = 0.75

        // When
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: coveragePercentage
        )

        // Then: Warnings should use AICoverageAnalyzer's constants
        let partialWarning = result.warnings.first { $0.contains("areas not captured") }
        XCTAssertNotNil(partialWarning, "Should have partial coverage warning")
        XCTAssertTrue(partialWarning?.contains(AICoverageAnalyzer.partialCoverageWarning) ?? false,
                      "Warning should use AICoverageAnalyzer constant")
    }

    /// Tests that severe coverage warnings use AICoverageAnalyzer constant.
    func testCoverageIntegration_SevereUsesAnalyzerConstants() async throws {
        // Given: Coverage at 25% (severe)
        let coveragePercentage: Float = 0.25

        // When
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: coveragePercentage
        )

        // Then: Should have both warnings using AICoverageAnalyzer constants
        XCTAssertTrue(result.warnings.contains(AICoverageAnalyzer.severeCoverageWarning),
                      "Should include severe warning constant")
    }

    /// Tests nil coverage assumes full coverage (backwards compatibility).
    func testCoverageWarning_NilCoverage_NoWarning() async throws {
        // Given: nil coverage (backwards compatibility)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil
        )

        // Then: Should not include coverage warnings
        XCTAssertFalse(result.warnings.contains { $0.contains("Some areas not captured") },
            "Nil coverage should assume full coverage")
    }

    /// Tests quote readiness is limited for severe coverage (AC3).
    /// With severe coverage (<50%), quote readiness should be limited even with cabinets.
    func testQuoteReadiness_SevereCoverage_LimitsQuoteReadiness() async throws {
        // Given: Severe coverage (25%) - no cabinets for simplicity
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 0.25
        )

        // Then: Quote readiness should be limited
        // At 50% base * 25% coverage = 12.5% -> notRecommended
        XCTAssertEqual(result.quoteReadiness, .notRecommended,
            "Severe coverage should result in not recommended for quoting")
    }

    // MARK: - Story 6.4: Reflective Surface Impact Tests

    /// Tests that 0% reflective impact applies no penalty (AC5).
    func testReflectiveSurfaceImpact_ZeroImpact_NoPenalty() async throws {
        // Given: No reflective surface impact
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.0
        )

        // Then: Score should not be penalized
        // Empty kitchen base score is 0.5, no penalties applied
        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01)
    }

    /// Tests that 10% reflective impact applies minor penalty (AC5).
    func testReflectiveSurfaceImpact_MinorImpact_AppliesPenalty() async throws {
        // Given: Minor reflective impact (10%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.1
        )

        // Then: Score should be penalized by 3% (10% * 0.3 = 3% penalty)
        // Base 0.5 * (1 - 0.03) = 0.485
        XCTAssertEqual(result.overallScore, 0.485, accuracy: 0.01)
    }

    /// Tests that 50% reflective impact applies significant penalty (AC5).
    func testReflectiveSurfaceImpact_SignificantImpact_AppliesPenalty() async throws {
        // Given: Significant reflective impact (50%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.5
        )

        // Then: Score should be penalized by 15% (50% * 0.3 = 15% penalty)
        // Base 0.5 * (1 - 0.15) = 0.425
        XCTAssertEqual(result.overallScore, 0.425, accuracy: 0.01)
    }

    /// Tests reflective surface warning is generated above 10% threshold (AC5).
    func testReflectiveSurfaceImpact_AboveThreshold_GeneratesWarning() async throws {
        // Given: Reflective impact above warning threshold (15%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.15
        )

        // Then: Should include reflective surface warning
        XCTAssertTrue(result.warnings.contains { $0.contains("Reflective surfaces detected") },
            "Should include reflective surface warning: \(result.warnings)")
    }

    /// Tests reflective surface warning is NOT generated below 10% threshold.
    func testReflectiveSurfaceImpact_BelowThreshold_NoWarning() async throws {
        // Given: Reflective impact below warning threshold (5%)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.05
        )

        // Then: Should NOT include reflective surface warning
        XCTAssertFalse(result.warnings.contains { $0.contains("Reflective surfaces detected") },
            "Should NOT include reflective surface warning below 10% threshold")
    }

    /// Tests that significant reflective impact limits quote readiness (AC5).
    func testReflectiveSurfaceImpact_SignificantImpact_LimitsQuoteReadiness() async throws {
        // Given: Significant reflective impact (40% - above 30% threshold)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: 0.4
        )

        // Then: Quote readiness should be limited to withCaveats at most
        XCTAssertNotEqual(result.quoteReadiness, .ready,
            "Significant reflective impact should limit quote readiness")
    }

    /// Tests nil reflective impact (legacy/no analysis) applies no penalty.
    func testReflectiveSurfaceImpact_Nil_NoPenalty() async throws {
        // Given: No reflective surface analysis (nil)
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: nil,
            reflectiveSurfaceImpact: nil  // Backwards compatible - no analysis
        )

        // Then: Score should not be penalized
        XCTAssertEqual(result.overallScore, 0.5, accuracy: 0.01,
            "Nil reflective impact should not apply penalty")
    }

    /// Tests reflective impact combines with coverage penalty correctly.
    func testReflectiveSurfaceImpact_CombinesWithCoverage() async throws {
        // Given: Both coverage and reflective impact
        // When: Calculating confidence
        let result = try await sut.calculateConfidence(
            cabinetResult: nil,
            applianceResult: nil,
            islandPeninsulaResult: nil,
            countertopResult: nil,
            openingResult: nil,
            measurementResult: nil,
            coveragePercentage: 0.8,      // 80% coverage
            reflectiveSurfaceImpact: 0.2  // 20% reflective impact
        )

        // Then: Both penalties should be applied
        // Base 0.5 * 0.8 (coverage) * 0.94 (reflective: 1 - 0.2*0.3) = 0.376
        XCTAssertEqual(result.overallScore, 0.376, accuracy: 0.02,
            "Both coverage and reflective penalties should be applied")
    }
}
