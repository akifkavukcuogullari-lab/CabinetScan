//
//  ConfidenceScorer.swift
//  cabinetscan
//
//  Created for Story 4.8: Confidence Scoring System
//

import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Confidence Scorer Protocol (Task 1.2)

/// Protocol for confidence scoring implementations.
/// Enables testing with mock scorers.
protocol ConfidenceScorerProtocol {
    /// Calculates confidence scores for all detected objects.
    ///
    /// **Pipeline Order:** This scorer runs AFTER all detection phases:
    /// RoomDetector → CabinetDetector → ... → OpeningDetector → MeasurementExtractor → ConfidenceScorer
    ///
    /// - Parameters:
    ///   - cabinetResult: Cabinet detection result
    ///   - applianceResult: Appliance detection result
    ///   - islandPeninsulaResult: Island/peninsula detection result
    ///   - countertopResult: Countertop detection result
    ///   - openingResult: Opening detection result (Story 4.9 ADR-3)
    ///   - measurementResult: Measurement extraction result for factor calculation
    /// - Returns: Confidence scoring result with per-object and overall scores
    /// - Throws: `ConfidenceScoringError` if scoring fails
    func calculateConfidence(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?,
        openingResult: OpeningDetectionResult?,
        measurementResult: MeasurementExtractionResult?
    ) async throws -> ConfidenceScoringResult
}

// MARK: - Confidence Object Type (Task 1.4)

/// Type of object being scored for confidence.
enum ConfidenceObjectType: String, Codable, CaseIterable {
    case cabinet = "Cabinet"
    case appliance = "Appliance"
    case island = "Island"
    case peninsula = "Peninsula"
    case countertop = "Countertop"
    case window = "Window"      // Story 4.9 ADR-3
    case door = "Door"          // Story 4.9 ADR-3

    /// Display name for UI
    var displayText: String {
        rawValue
    }
}

// MARK: - Confidence Factors (Task 1.3)

/// Confidence factors with their weights per AC2.
///
/// **Factor Weights (AC2):**
/// - Segmentation clarity: 35%
/// - Depth consistency: 30%
/// - Pose accuracy: 20%
/// - Standard size match: 15%
///
/// **Usage:**
/// ```swift
/// let factors = ConfidenceFactors(
///     segmentationClarity: 0.9,
///     depthConsistency: 0.8,
///     poseAccuracy: 0.7,
///     standardSizeMatch: 0.6
/// )
/// let score = factors.weightedScore // 0.795
/// ```
struct ConfidenceFactors: Equatable, Codable {

    // MARK: - Weight Constants

    /// Static weight values per AC2
    enum Weights {
        /// Segmentation clarity weight (35%)
        static let segmentationClarity: Float = 0.35

        /// Depth consistency weight (30%)
        static let depthConsistency: Float = 0.30

        /// Pose accuracy weight (20%)
        static let poseAccuracy: Float = 0.20

        /// Standard size match weight (15%)
        static let standardSizeMatch: Float = 0.15
    }

    // MARK: - Factor Values (0.0 - 1.0)

    /// Edge definition and boundary clarity (35% weight)
    /// - 1.0: Sharp, well-defined edges
    /// - 0.7: Mostly clear with some uncertainty
    /// - 0.4: Fuzzy boundaries
    /// - <0.4: Very poor edge definition
    let segmentationClarity: Float

    /// Multi-view depth agreement (30% weight)
    /// - 1.0: <2% variance across views
    /// - 0.7: 2-5% variance
    /// - 0.4: 5-10% variance
    /// - <0.4: >10% variance or single-view
    let depthConsistency: Float

    /// ARKit tracking quality during capture (20% weight)
    /// - 1.0: >90% normal tracking
    /// - 0.7: 70-90% normal tracking
    /// - 0.4: 50-70% normal tracking
    /// - <0.4: <50% normal tracking
    let poseAccuracy: Float

    /// Match to standard cabinet sizes (15% weight)
    /// - 1.0: Exact match (0-0.5" difference)
    /// - 0.8: Within tolerance (0.5-1.5")
    /// - 0.5: Near tolerance (1.5-3")
    /// - 0.3: Custom size (>3")
    /// - <0.3: Suspicious measurement
    let standardSizeMatch: Float

    // MARK: - Computed Properties

    /// Weighted score combining all factors (0.0 - 1.0)
    var weightedScore: Float {
        return segmentationClarity * Weights.segmentationClarity +
               depthConsistency * Weights.depthConsistency +
               poseAccuracy * Weights.poseAccuracy +
               standardSizeMatch * Weights.standardSizeMatch
    }

    /// Factor breakdown for debugging/display
    var breakdown: String {
        """
        Segmentation: \(String(format: "%.0f%%", segmentationClarity * 100))
        Depth: \(String(format: "%.0f%%", depthConsistency * 100))
        Pose: \(String(format: "%.0f%%", poseAccuracy * 100))
        Size Match: \(String(format: "%.0f%%", standardSizeMatch * 100))
        """
    }

    /// Returns the weakest factor name and value
    var weakestFactor: (name: String, value: Float) {
        let factors: [(String, Float)] = [
            ("segmentation", segmentationClarity),
            ("depth", depthConsistency),
            ("pose", poseAccuracy),
            ("size match", standardSizeMatch)
        ]
        return factors.min { $0.1 < $1.1 } ?? ("unknown", 0)
    }

    // MARK: - Initialization

    init(
        segmentationClarity: Float,
        depthConsistency: Float,
        poseAccuracy: Float,
        standardSizeMatch: Float
    ) {
        self.segmentationClarity = max(0, min(1, segmentationClarity))
        self.depthConsistency = max(0, min(1, depthConsistency))
        self.poseAccuracy = max(0, min(1, poseAccuracy))
        self.standardSizeMatch = max(0, min(1, standardSizeMatch))
    }

    /// Creates factors with all values set to the same level
    static func uniform(_ value: Float) -> ConfidenceFactors {
        ConfidenceFactors(
            segmentationClarity: value,
            depthConsistency: value,
            poseAccuracy: value,
            standardSizeMatch: value
        )
    }
}

// MARK: - Object Confidence Score (Task 1.4)

/// Confidence score for a single detected object.
///
/// **Usage:**
/// ```swift
/// let score = ObjectConfidenceScore(
///     objectId: cabinet.id,
///     objectType: .cabinet,
///     rawScore: 0.75,
///     factors: factors,
///     warnings: ["edges unclear"],
///     widthInches: 36.0
/// )
/// print(score.level) // .medium
/// ```
struct ObjectConfidenceScore: Identifiable, Equatable, Codable {

    /// Unique identifier for this score
    let id: UUID

    /// Reference to the source object
    let objectId: UUID

    /// Type of object scored
    let objectType: ConfidenceObjectType

    /// Raw confidence score (0.0 - 1.0)
    let rawScore: Float

    /// Confidence level classification
    var level: AIConfidenceLevel {
        AIConfidenceLevel.from(score: rawScore)
    }

    /// Factor breakdown explaining the score
    let factors: ConfidenceFactors

    /// Warnings specific to this object
    let warnings: [String]

    /// Width in inches (used for quote impact weighting per AC6)
    /// Large cabinets (>30") get 2x weight in overall score
    let widthInches: Float?

    // MARK: - Computed Properties

    /// Display percentage (e.g., "75%")
    var displayPercentage: String {
        String(format: "%.0f%%", rawScore * 100)
    }

    /// Whether this object needs verification (LOW confidence)
    var needsVerification: Bool {
        level == .low
    }

    /// Whether this is a large cabinet (>30" width) per AC6
    var isLargeCabinet: Bool {
        guard objectType == .cabinet, let width = widthInches else { return false }
        return width > 30.0
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        objectId: UUID,
        objectType: ConfidenceObjectType,
        rawScore: Float,
        factors: ConfidenceFactors,
        warnings: [String],
        widthInches: Float? = nil
    ) {
        self.id = id
        self.objectId = objectId
        self.objectType = objectType
        self.rawScore = max(0, min(1, rawScore))
        self.factors = factors
        self.warnings = warnings
        self.widthInches = widthInches
    }
}

// MARK: - Quote Readiness Level (Task 2.2, 2.3)

/// Quote readiness based on overall confidence per AC9.
enum QuoteReadinessLevel: String, Codable, CaseIterable {
    /// <60% - NOT recommended for quoting
    case notRecommended = "Not Recommended"

    /// 60-80% - Quote with verification caveats
    case withCaveats = "With Caveats"

    /// >80% - Quote-ready with standard disclaimers
    case ready = "Ready"

    /// User-friendly message per AC9
    var displayMessage: String {
        switch self {
        case .notRecommended:
            return "NOT recommended for quoting without verification"
        case .withCaveats:
            return "Quote with caveats - some items need verification"
        case .ready:
            return "Quote-ready with standard disclaimers"
        }
    }

    /// Short status label
    var shortLabel: String {
        switch self {
        case .notRecommended:
            return "Verify First"
        case .withCaveats:
            return "Needs Review"
        case .ready:
            return "Quote Ready"
        }
    }

    /// Determines quote readiness from overall score
    static func from(overallScore: Float) -> QuoteReadinessLevel {
        if overallScore >= 0.80 {
            return .ready
        } else if overallScore >= 0.60 {
            return .withCaveats
        } else {
            return .notRecommended
        }
    }
}

// MARK: - Confidence Scoring Result (Task 1.5)

/// Result of confidence scoring containing all scores and warnings.
struct ConfidenceScoringResult: Equatable {

    /// Per-object confidence scores
    let objectScores: [ObjectConfidenceScore]

    /// Overall weighted confidence score (0.0 - 1.0)
    let overallScore: Float

    /// Overall confidence level
    let overallLevel: AIConfidenceLevel

    /// Quote readiness assessment
    let quoteReadiness: QuoteReadinessLevel

    /// Count of items needing verification (LOW confidence)
    let itemsNeedingVerification: Int

    /// Aggregated warnings for all objects
    let warnings: [String]

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Object limiting overall score (if minimum-confidence rule applied)
    let limitingObjectId: UUID?

    // MARK: - Computed Properties

    /// Display percentage for overall score
    var displayPercentage: String {
        String(format: "%.0f%%", overallScore * 100)
    }

    /// Summary text for UI display
    var summary: String {
        if itemsNeedingVerification == 0 {
            return "All measurements verified"
        } else {
            return "\(itemsNeedingVerification) item(s) need verification before quoting"
        }
    }

    /// Whether any object has LOW confidence
    var hasLowConfidenceItems: Bool {
        itemsNeedingVerification > 0
    }
}

// MARK: - Confidence Scoring Error

/// Errors that can occur during confidence scoring.
enum ConfidenceScoringError: LocalizedError, Equatable {
    case scoringFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .scoringFailed(let reason):
            return "Confidence scoring failed: \(reason)"
        case .cancelled:
            return "Confidence scoring was cancelled"
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .scoringFailed:
            return "Couldn't calculate confidence scores. Results may need manual review."
        case .cancelled:
            return "Confidence scoring was cancelled."
        }
    }
}

// MARK: - AIConfidenceLevel Extensions (Task 2.1, 2.4)

extension AIConfidenceLevel {

    /// Threshold constants per AC1
    static let highThreshold: Float = 0.80
    static let mediumThreshold: Float = 0.60

    /// Creates confidence level from raw score per AC1
    /// - Parameter score: Raw score (0.0 - 1.0)
    /// - Returns: HIGH (>=80%), MEDIUM (60-79%), LOW (<60%)
    static func from(score: Float) -> AIConfidenceLevel {
        if score >= highThreshold {
            return .high
        } else if score >= mediumThreshold {
            return .medium
        } else {
            return .low
        }
    }

    /// Badge color per AC4
    var badgeColor: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .yellow
        case .low:
            return .red
        }
    }
}

// MARK: - Confidence Scorer Implementation

/// Calculates confidence scores for all detected objects.
///
/// **Architecture Notes:**
/// - Runs after all detection phases complete
/// - Provides factor-based analysis explaining confidence
/// - Generates actionable warnings for quote reliability
///
/// **Performance Budget:** <50ms per Architecture 9.3
///
/// **Usage:**
/// ```swift
/// let scorer = ConfidenceScorer()
/// let result = try await scorer.calculateConfidence(
///     cabinetResult: cabinets,
///     applianceResult: appliances,
///     islandPeninsulaResult: islands,
///     countertopResult: countertops,
///     measurementResult: measurements
/// )
/// ```
@MainActor
final class ConfidenceScorer: ObservableObject, ConfidenceScorerProtocol {

    // MARK: - Constants

    /// Quote impact weights per AC6
    private enum QuoteImpactWeights {
        /// Large cabinets (>30") get 2x weight
        static let largeCabinet: Float = 2.0

        /// Islands get 2x weight
        static let island: Float = 2.0

        /// Peninsulas get 1.5x weight
        static let peninsula: Float = 1.5

        /// Regular cabinets get 1x weight
        static let regularCabinet: Float = 1.0

        /// Appliances get 0.5x weight (less critical for quote)
        static let appliance: Float = 0.5

        /// Large cabinet width threshold (inches)
        static let largeCabinetThreshold: Float = 30.0
    }

    /// Medium confidence cap when any LOW object exists (AC3)
    private static let mediumCap: Float = 0.79

    // MARK: - Published Properties

    /// Current scoring progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    // MARK: - Private Properties

    private let logger: Logger

    // MARK: - Initialization

    init() {
        self.logger = Logger(subsystem: "com.cabinetscan", category: "ConfidenceScorer")
        #if DEBUG
        logger.debug("ConfidenceScorer initialized")
        #endif
    }

    // MARK: - Main Scoring (AC: All)

    /// Calculates confidence scores for all detected objects.
    func calculateConfidence(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?,
        openingResult: OpeningDetectionResult?,
        measurementResult: MeasurementExtractionResult?
    ) async throws -> ConfidenceScoringResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.info("Starting confidence scoring")
        progress = 0.1

        var objectScores: [ObjectConfidenceScore] = []
        var allWarnings: [String] = []

        // Step 1: Score cabinets (Task 9.2)
        progress = 0.15
        if let cabinetResult = cabinetResult {
            let cabinetScores = scoreCabinets(
                from: cabinetResult,
                measurementResult: measurementResult
            )
            objectScores.append(contentsOf: cabinetScores)
        }

        try Task.checkCancellation()

        // Step 2: Score appliances (Task 9.3)
        progress = 0.30
        if let applianceResult = applianceResult {
            let applianceScores = scoreAppliances(from: applianceResult)
            objectScores.append(contentsOf: applianceScores)
        }

        try Task.checkCancellation()

        // Step 3: Score islands/peninsulas (Task 9.4)
        progress = 0.45
        if let islandPeninsulaResult = islandPeninsulaResult {
            let islandScores = scoreIslandsAndPeninsulas(from: islandPeninsulaResult)
            objectScores.append(contentsOf: islandScores)
        }

        try Task.checkCancellation()

        // Step 4: Score countertops (Task 9.5)
        progress = 0.60
        if let countertopResult = countertopResult {
            let countertopScores = scoreCountertops(from: countertopResult)
            objectScores.append(contentsOf: countertopScores)
        }

        try Task.checkCancellation()

        // Step 5: Score openings - windows and doors (Story 4.9 ADR-3)
        progress = 0.75
        if let openingResult = openingResult {
            let openingScores = scoreOpenings(from: openingResult)
            objectScores.append(contentsOf: openingScores)
        }

        try Task.checkCancellation()

        // Step 6: Calculate overall score (Task 7)
        progress = 0.85
        let (overallScore, limitingObjectId) = calculateOverallScore(from: objectScores)
        let overallLevel = AIConfidenceLevel.from(score: overallScore)
        let quoteReadiness = QuoteReadinessLevel.from(overallScore: overallScore)

        // Step 7: Generate warnings (Task 8)
        progress = 0.92
        let itemsNeedingVerification = objectScores.filter { $0.needsVerification }.count

        // Generate per-item warnings
        for (index, score) in objectScores.enumerated() {
            let itemWarnings = Self.generateWarnings(for: score, index: index + 1)
            allWarnings.append(contentsOf: itemWarnings)
        }

        // Add field verification note if any LOW items
        if itemsNeedingVerification > 0 {
            allWarnings.append("Field verification recommended for \(itemsNeedingVerification) item(s)")
        }

        let processingTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        progress = 1.0

        logger.info("Confidence scoring complete in \(processingTimeMs)ms: \(objectScores.count) objects scored, overall \(String(format: "%.0f", overallScore * 100))%")

        return ConfidenceScoringResult(
            objectScores: objectScores,
            overallScore: overallScore,
            overallLevel: overallLevel,
            quoteReadiness: quoteReadiness,
            itemsNeedingVerification: itemsNeedingVerification,
            warnings: allWarnings,
            processingTimeMs: processingTimeMs,
            limitingObjectId: limitingObjectId
        )
    }

    // MARK: - Cabinet Scoring (Task 3-6, 9.2)

    /// Scores cabinets with factor breakdown.
    private func scoreCabinets(
        from result: CabinetDetectionResult,
        measurementResult: MeasurementExtractionResult?
    ) -> [ObjectConfidenceScore] {
        result.cabinets.enumerated().map { index, cabinet in
            // Task 3: Segmentation clarity
            let segmentationClarity = calculateSegmentationClarity(
                isStandardSize: cabinet.isStandardSize,
                confidence: cabinet.confidence
            )

            // Task 4: Depth consistency
            let depthConsistency = calculateDepthConsistency(
                rawDimensions: cabinet.rawDimensions,
                snappedDimensions: cabinet.snappedDimensions
            )

            // Task 5: Pose accuracy (use cabinet's existing confidence as proxy)
            let poseAccuracy = calculatePoseAccuracy(from: cabinet.confidence)

            // Task 6: Standard size match
            let snapDifference = findSnapDifference(
                for: cabinet.id,
                in: measurementResult
            )
            let standardSizeMatch = calculateStandardSizeMatch(
                snapDifferenceInches: snapDifference,
                isStandardSize: cabinet.isStandardSize
            )

            let factors = ConfidenceFactors(
                segmentationClarity: segmentationClarity,
                depthConsistency: depthConsistency,
                poseAccuracy: poseAccuracy,
                standardSizeMatch: standardSizeMatch
            )

            var warnings: [String] = []
            if factors.weightedScore < AIConfidenceLevel.mediumThreshold {
                let weakest = factors.weakestFactor
                warnings.append("\(weakest.name): \(Self.factorHint(for: weakest.name))")
            }

            // Get cabinet width in inches for quote impact weighting (AC6)
            // snappedDimensions.x is width in inches
            let cabinetWidthInches = cabinet.snappedDimensions.x

            return ObjectConfidenceScore(
                objectId: cabinet.id,
                objectType: .cabinet,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: warnings,
                widthInches: cabinetWidthInches
            )
        }
    }

    // MARK: - Appliance Scoring (Task 9.3)

    /// Scores appliances.
    private func scoreAppliances(
        from result: ApplianceDetectionResult
    ) -> [ObjectConfidenceScore] {
        result.appliances.map { appliance in
            // Appliances have simpler scoring - primarily based on detection confidence
            let baseScore = confidenceToScore(appliance.confidence)

            let factors = ConfidenceFactors(
                segmentationClarity: baseScore,
                depthConsistency: baseScore * 0.9, // Slightly lower depth certainty
                poseAccuracy: baseScore,
                standardSizeMatch: 0.8 // Appliances have standard sizes
            )

            return ObjectConfidenceScore(
                objectId: appliance.id,
                objectType: .appliance,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: []
            )
        }
    }

    // MARK: - Island/Peninsula Scoring (Task 9.4)

    /// Scores islands and peninsulas.
    private func scoreIslandsAndPeninsulas(
        from result: IslandPeninsulaDetectionResult
    ) -> [ObjectConfidenceScore] {
        var scores: [ObjectConfidenceScore] = []

        // Score islands
        for island in result.islands {
            let baseScore = confidenceToScore(island.confidence)
            let factors = ConfidenceFactors(
                segmentationClarity: baseScore,
                depthConsistency: baseScore * 0.85,
                poseAccuracy: baseScore * 0.9,
                standardSizeMatch: 0.7 // Islands are custom-sized
            )

            scores.append(ObjectConfidenceScore(
                objectId: island.id,
                objectType: .island,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: []
            ))
        }

        // Score peninsulas
        for peninsula in result.peninsulas {
            let baseScore = confidenceToScore(peninsula.confidence)
            let factors = ConfidenceFactors(
                segmentationClarity: baseScore,
                depthConsistency: baseScore * 0.85,
                poseAccuracy: baseScore * 0.9,
                standardSizeMatch: 0.7
            )

            scores.append(ObjectConfidenceScore(
                objectId: peninsula.id,
                objectType: .peninsula,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: []
            ))
        }

        return scores
    }

    // MARK: - Countertop Scoring (Task 9.5)

    /// Scores countertops.
    private func scoreCountertops(
        from result: CountertopDetectorResult
    ) -> [ObjectConfidenceScore] {
        // Score wall countertops
        return result.wallCountertops.map { countertop in
            let baseScore = confidenceToScore(countertop.confidence)
            let factors = ConfidenceFactors(
                segmentationClarity: baseScore * 0.9,
                depthConsistency: baseScore,
                poseAccuracy: baseScore * 0.95,
                standardSizeMatch: 0.85 // Countertops have standard depths
            )

            return ObjectConfidenceScore(
                objectId: countertop.id,
                objectType: .countertop,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: []
            )
        }
    }

    // MARK: - Opening Scoring (Story 4.9 ADR-3)

    /// Scores windows and doors from opening detection result.
    ///
    /// Per ADR-3: Opening detection results feed into ConfidenceScorer for overall quote readiness.
    /// Openings with LOW confidence impact quote reliability.
    private func scoreOpenings(
        from result: OpeningDetectionResult
    ) -> [ObjectConfidenceScore] {
        var scores: [ObjectConfidenceScore] = []

        // Score windows
        for window in result.windows {
            let baseScore = confidenceToScore(window.confidence)

            // Windows use multi-signal detection, so segmentation is usually good
            let segmentationClarity = window.hasFrame ? baseScore * 1.1 : baseScore * 0.9
            let depthConsistency = baseScore * 0.9 // Windows are wall openings, depth less relevant
            let poseAccuracy = baseScore
            let standardSizeMatch: Float = window.isStandardSize ? 0.9 : 0.6

            let factors = ConfidenceFactors(
                segmentationClarity: min(1.0, segmentationClarity),
                depthConsistency: depthConsistency,
                poseAccuracy: poseAccuracy,
                standardSizeMatch: standardSizeMatch
            )

            var warnings: [String] = []
            if factors.weightedScore < AIConfidenceLevel.mediumThreshold {
                warnings.append("Window dimensions may need verification")
            }

            scores.append(ObjectConfidenceScore(
                objectId: window.id,
                objectType: .window,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: warnings,
                widthInches: window.widthInches
            ))
        }

        // Score doors
        for door in result.doors {
            let baseScore = confidenceToScore(door.confidence)

            let segmentationClarity = baseScore
            let depthConsistency = baseScore * 0.85 // Doors may have swing detection uncertainty
            let poseAccuracy = baseScore * 0.95
            let standardSizeMatch: Float = door.isStandardSize ? 0.95 : 0.5

            let factors = ConfidenceFactors(
                segmentationClarity: segmentationClarity,
                depthConsistency: depthConsistency,
                poseAccuracy: poseAccuracy,
                standardSizeMatch: standardSizeMatch
            )

            var warnings: [String] = []
            if factors.weightedScore < AIConfidenceLevel.mediumThreshold {
                warnings.append("Door dimensions may need verification")
            }
            if door.swingDirection == .unknown {
                warnings.append("Door swing direction not detected")
            }

            scores.append(ObjectConfidenceScore(
                objectId: door.id,
                objectType: .door,
                rawScore: factors.weightedScore,
                factors: factors,
                warnings: warnings,
                widthInches: door.widthInches
            ))
        }

        return scores
    }

    // MARK: - Factor Calculations (Tasks 3-6)

    /// Task 3.1, 3.2: Calculate segmentation clarity factor.
    private func calculateSegmentationClarity(
        isStandardSize: Bool,
        confidence: AIConfidenceLevel
    ) -> Float {
        var score: Float = confidenceToScore(confidence)

        // Task 3.3: Standard size is a positive signal
        if isStandardSize {
            score = min(1.0, score + 0.1)
        }

        return score
    }

    /// Task 4.1, 4.2: Calculate depth consistency factor.
    private func calculateDepthConsistency(
        rawDimensions: SIMD3<Float>,
        snappedDimensions: SIMD3<Float>
    ) -> Float {
        // Task 4.3: Use dimension difference as proxy for consistency
        let widthDiff = abs(rawDimensions.x - snappedDimensions.x)
        let heightDiff = abs(rawDimensions.y - snappedDimensions.y)
        let depthDiff = abs(rawDimensions.z - snappedDimensions.z)
        let avgDiff = (widthDiff + heightDiff + depthDiff) / 3.0

        // Convert to percentage of dimension (assume 36" average)
        let variancePercent = (avgDiff / 36.0) * 100

        if variancePercent < 2 {
            return 1.0
        } else if variancePercent < 5 {
            return 0.7
        } else if variancePercent < 10 {
            return 0.4
        } else {
            return max(0.2, 0.4 - (variancePercent - 10) * 0.02)
        }
    }

    /// Task 5.1, 5.2: Calculate pose accuracy factor.
    private func calculatePoseAccuracy(from confidence: AIConfidenceLevel) -> Float {
        // Use detection confidence as proxy for tracking quality
        return confidenceToScore(confidence)
    }

    /// Task 6.1, 6.2: Calculate standard size match factor.
    private func calculateStandardSizeMatch(
        snapDifferenceInches: Float,
        isStandardSize: Bool
    ) -> Float {
        // Task 6.3: Handle custom cabinets gracefully
        if !isStandardSize {
            // Custom size but valid - don't penalize too harshly
            return 0.5
        }

        if snapDifferenceInches <= 0.5 {
            return 1.0  // Exact match
        } else if snapDifferenceInches <= 1.5 {
            return 0.8  // Within snap tolerance
        } else if snapDifferenceInches <= 3.0 {
            return 0.5  // Near tolerance
        } else {
            return max(0.2, 0.3 - (snapDifferenceInches - 3.0) * 0.02)
        }
    }

    // MARK: - Overall Score Calculation (Task 7)

    /// Task 7.1-7.4: Calculate weighted overall score with minimum-confidence rule.
    private func calculateOverallScore(
        from objectScores: [ObjectConfidenceScore]
    ) -> (score: Float, limitingObjectId: UUID?) {
        guard !objectScores.isEmpty else {
            return (0.0, nil)
        }

        var weightedSum: Float = 0.0
        var totalWeight: Float = 0.0
        var hasLowConfidence = false
        var limitingObjectId: UUID?

        for score in objectScores {
            // Task 7.2: Determine quote impact weight
            let weight = quoteImpactWeight(for: score)

            weightedSum += score.rawScore * weight
            totalWeight += weight

            // Task 7.3: Track if any LOW confidence
            if score.level == .low {
                hasLowConfidence = true
                if limitingObjectId == nil {
                    limitingObjectId = score.objectId
                }
            }
        }

        // Task 7.1: Calculate weighted average
        var overallScore = totalWeight > 0 ? weightedSum / totalWeight : 0.0

        // Task 7.3: Apply minimum-confidence rule
        if hasLowConfidence {
            overallScore = min(overallScore, Self.mediumCap)
        }

        return (overallScore, limitingObjectId)
    }

    /// Task 7.2: Determine quote impact weight for an object.
    /// Per AC6: Large cabinets (>30") get 2x weight, islands 2x, peninsulas 1.5x
    private func quoteImpactWeight(for score: ObjectConfidenceScore) -> Float {
        switch score.objectType {
        case .island:
            return QuoteImpactWeights.island
        case .peninsula:
            return QuoteImpactWeights.peninsula
        case .cabinet:
            // AC6: Large cabinets (>30") get 2x weight
            return score.isLargeCabinet ? QuoteImpactWeights.largeCabinet : QuoteImpactWeights.regularCabinet
        case .appliance:
            return QuoteImpactWeights.appliance
        case .countertop:
            // Countertops use regular weight (1x) - similar quote impact to regular cabinets
            return QuoteImpactWeights.regularCabinet
        case .window:
            // Windows affect upper cabinet placement decisions
            return QuoteImpactWeights.regularCabinet
        case .door:
            // Doors affect filler calculations
            return QuoteImpactWeights.regularCabinet
        }
    }

    // MARK: - Warning Generation (Task 8)

    /// Task 8.1-8.4: Generate warnings for a scored object.
    static func generateWarnings(for score: ObjectConfidenceScore, index: Int) -> [String] {
        guard score.level == .low else {
            return [] // No warnings for HIGH/MEDIUM
        }

        var warnings: [String] = []

        // Task 8.1: Generate specific warning per object type
        switch score.objectType {
        case .cabinet:
            warnings.append("Cabinet #\(index): low confidence - verify width")
        case .island:
            warnings.append("Island: low confidence - verify dimensions")
        case .peninsula:
            warnings.append("Peninsula: low confidence - verify dimensions")
        case .appliance:
            warnings.append("Appliance #\(index): verify position")
        case .countertop:
            warnings.append("Countertop #\(index): verify measurements")
        case .window:
            warnings.append("Window #\(index): low confidence - verify dimensions")
        case .door:
            warnings.append("Door #\(index): low confidence - verify width and clearance")
        }

        // Task 8.4: Add factor-specific hints
        let weakest = score.factors.weakestFactor
        warnings.append(Self.factorHint(for: weakest.name))

        return warnings
    }

    /// Task 8.4: Generate hint for weak factor.
    private static func factorHint(for factorName: String) -> String {
        switch factorName {
        case "segmentation":
            return "edges unclear, check boundaries"
        case "depth":
            return "depth inconsistent, verify with tape measure"
        case "pose":
            return "tracking was unstable, rescan recommended"
        case "size match":
            return "non-standard size, confirm with catalog"
        default:
            return "manual verification recommended"
        }
    }

    // MARK: - Helper Methods

    /// Converts AIConfidenceLevel to numeric score.
    private func confidenceToScore(_ confidence: AIConfidenceLevel) -> Float {
        switch confidence {
        case .high: return 0.85
        case .medium: return 0.70
        case .low: return 0.50
        }
    }

    /// Finds snap difference from measurement result for a specific object.
    ///
    /// - Returns: Snap difference in inches, or 2.0 if not found (indicates uncertainty,
    ///   maps to ~0.5 score in calculateStandardSizeMatch - medium confidence)
    private func findSnapDifference(
        for objectId: UUID,
        in measurementResult: MeasurementExtractionResult?
    ) -> Float {
        // If no measurement data, return 2.0 (near tolerance) to indicate uncertainty
        // This avoids falsely inflating confidence when data is missing
        guard let result = measurementResult else { return 2.0 }

        if let measurement = result.allMeasurements.first(where: { $0.objectId == objectId }) {
            return measurement.snapDifferenceInches
        }

        // Object not found in measurements - return uncertainty value
        return 2.0
    }
}
