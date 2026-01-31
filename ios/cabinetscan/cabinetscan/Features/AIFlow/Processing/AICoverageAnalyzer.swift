//
//  AICoverageAnalyzer.swift
//  cabinetscan
//
//  Created for Story 6.2: Partial Capture Handling
//

import Foundation

// MARK: - Coverage Level

/// Coverage level classification based on percentage of zones captured.
/// Per ADR-6.2.1, coverage is calculated from 4 directional zones.
enum AICoverageLevel: String, Equatable {
    /// Full coverage: all 4 zones captured (100%)
    case full

    /// Partial coverage: 2-3 zones captured (50-99%)
    case partial

    /// Severe partial: only 0-1 zones captured (<50%)
    case severe

    /// Display text for UI
    var displayText: String {
        switch self {
        case .full:
            return "Complete"
        case .partial:
            return "Partial"
        case .severe:
            return "Incomplete"
        }
    }
}

// MARK: - Coverage Analysis Result

/// Result of coverage analysis containing level, percentage, and warnings.
/// Used by ConfidenceScorer and UI to display appropriate messaging.
struct CoverageAnalysisResult: Equatable {
    /// Coverage level classification
    let level: AICoverageLevel

    /// Coverage percentage (0.0 to 1.0)
    let coveragePercentage: Float

    /// Set of zones that were captured
    let capturedZones: Set<AICaptureZone>

    /// Set of zones that were NOT captured
    let uncapturedZones: Set<AICaptureZone>

    /// Warnings generated based on coverage level
    let warnings: [String]

    /// Whether the coverage is sufficient for a reliable quote
    var isSufficientForQuote: Bool {
        level == .full || level == .partial
    }

    /// Human-readable coverage description
    var coverageDescription: String {
        let percentage = Int(coveragePercentage * 100)
        return "\(percentage)% coverage"
    }
}

// MARK: - AI Coverage Analyzer

/// Analyzes capture coverage to determine completeness and generate warnings.
///
/// Per Story 6.2, this analyzer:
/// - Calculates coverage percentage from captured zones (AC1)
/// - Determines coverage level: full (100%), partial (50-99%), severe (<50%) (AC1, AC4)
/// - Generates appropriate warnings for partial/severe coverage (AC3, AC4)
///
/// **Usage:**
/// ```swift
/// let analyzer = AICoverageAnalyzer()
/// let result = analyzer.analyze(coverageState: captureData.coverageState)
/// if !result.warnings.isEmpty {
///     // Show warnings to user
/// }
/// ```
final class AICoverageAnalyzer {

    // MARK: - Constants

    /// Threshold for partial coverage (50% = 2/4 zones)
    private static let partialThreshold: Float = 0.5

    /// Warning message for partial coverage (AC3)
    static let partialCoverageWarning = "Some areas not captured"

    /// Warning message for severe partial coverage (AC4)
    static let severeCoverageWarning = "Incomplete scan - consider rescanning"

    // MARK: - Initialization

    init() {}

    // MARK: - Analysis

    /// Analyzes coverage state to determine level and generate warnings.
    ///
    /// - Parameter coverageState: The coverage state from capture phase
    /// - Returns: Analysis result with level, percentage, and warnings
    func analyze(coverageState: AICoverageState?) -> CoverageAnalysisResult {
        // Handle nil state (assume full coverage for backwards compatibility)
        guard let state = coverageState else {
            return CoverageAnalysisResult(
                level: .full,
                coveragePercentage: 1.0,
                capturedZones: Set(AICaptureZone.allCases),
                uncapturedZones: [],
                warnings: []
            )
        }

        let coveragePercentage = state.coveragePercentage
        let capturedZones = state.capturedZones
        let uncapturedZones = Set(AICaptureZone.allCases).subtracting(capturedZones)

        // Determine level
        let level: AICoverageLevel
        if coveragePercentage >= 1.0 {
            level = .full
        } else if coveragePercentage >= Self.partialThreshold {
            level = .partial
        } else {
            level = .severe
        }

        // Generate warnings
        let warnings = generateWarnings(level: level, coveragePercentage: coveragePercentage)

        return CoverageAnalysisResult(
            level: level,
            coveragePercentage: coveragePercentage,
            capturedZones: capturedZones,
            uncapturedZones: uncapturedZones,
            warnings: warnings
        )
    }

    /// Convenience method to analyze coverage from percentage directly.
    ///
    /// - Parameter coveragePercentage: Coverage percentage (0.0 to 1.0)
    /// - Returns: Analysis result with level and warnings
    func analyze(coveragePercentage: Float?) -> CoverageAnalysisResult {
        guard let percentage = coveragePercentage else {
            return CoverageAnalysisResult(
                level: .full,
                coveragePercentage: 1.0,
                capturedZones: Set(AICaptureZone.allCases),
                uncapturedZones: [],
                warnings: []
            )
        }

        // Reconstruct approximate zone count from percentage
        let zoneCount = Int((percentage * 4).rounded())
        let capturedZones: Set<AICaptureZone>

        switch zoneCount {
        case 4:
            capturedZones = Set(AICaptureZone.allCases)
        case 3:
            capturedZones = [.front, .right, .back]
        case 2:
            capturedZones = [.front, .right]
        case 1:
            capturedZones = [.front]
        default:
            capturedZones = []
        }

        // Determine level
        let level: AICoverageLevel
        if percentage >= 1.0 {
            level = .full
        } else if percentage >= Self.partialThreshold {
            level = .partial
        } else {
            level = .severe
        }

        let warnings = generateWarnings(level: level, coveragePercentage: percentage)

        return CoverageAnalysisResult(
            level: level,
            coveragePercentage: percentage,
            capturedZones: capturedZones,
            uncapturedZones: Set(AICaptureZone.allCases).subtracting(capturedZones),
            warnings: warnings
        )
    }

    // MARK: - Private Helpers

    /// Generates warnings based on coverage level.
    ///
    /// - Parameters:
    ///   - level: Coverage level
    ///   - coveragePercentage: Coverage percentage
    /// - Returns: Array of warning messages
    private func generateWarnings(level: AICoverageLevel, coveragePercentage: Float) -> [String] {
        var warnings: [String] = []

        switch level {
        case .full:
            // No warnings for full coverage
            break

        case .partial:
            // AC3: Add warning for partial coverage
            let percentage = Int(coveragePercentage * 100)
            warnings.append("\(Self.partialCoverageWarning) (\(percentage)% coverage)")

        case .severe:
            // AC3 + AC4: Add both warnings for severe coverage
            let percentage = Int(coveragePercentage * 100)
            warnings.append("\(Self.partialCoverageWarning) (\(percentage)% coverage)")
            warnings.append(Self.severeCoverageWarning)
        }

        return warnings
    }
}
