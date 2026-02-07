//
//  AIFlowModels.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import simd
import SwiftUI

// MARK: - AI Flow Internal Models
// These types are internal to AIFlow module and not shared with existing app code.

// MARK: - Capture Session Data

/// Container for all data captured during a single AI flow session.
/// Includes video, photos, and associated pose/metadata.
struct AICaptureSessionData {
    /// Minimum number of photos required for accurate reconstruction
    static let minimumPhotoCount = 5

    /// URL to the captured video file
    var videoURL: URL?

    /// URLs to captured photos with their pose data
    var photos: [AICapturedPhoto] = []

    /// Capture metadata
    var metadata: AICaptureMetadata?

    /// Quality metrics collected during capture (Story 2.4 - Task 5.4)
    var qualityMetrics: AIQualityMetrics?

    /// Coverage state at end of capture (Story 6.2)
    /// Contains the captured zones for partial capture handling.
    /// If nil, assumes full coverage (backwards compatibility).
    var coverageState: AICoverageState?

    /// Whether the session has minimum required data
    var hasMinimumData: Bool {
        videoURL != nil && photos.count >= Self.minimumPhotoCount
    }
}

/// A single captured photo with associated pose data
struct AICapturedPhoto {
    let url: URL
    let pose: AIPose
    let timestamp: TimeInterval
}

/// Camera pose at capture time
struct AIPose: Sendable {
    /// 4x4 transformation matrix (column-major)
    let transform: simd_float4x4

    /// Camera intrinsics
    let intrinsics: AICameraIntrinsics

    /// Tracking quality at capture time
    let trackingState: AITrackingState

    /// Zoom factor at capture time (1.0 = no zoom)
    /// Used by reconstruction pipeline to know zoom level per pose
    let zoomFactor: CGFloat

    /// Gravity vector in world coordinates (from ARKit).
    /// Points downward (negative Y in gravity-aligned coordinate system).
    /// If nil, assumes default gravity direction (0, -1, 0).
    let gravityVector: SIMD3<Float>?

    /// Creates a pose with all parameters including gravity.
    init(
        transform: simd_float4x4,
        intrinsics: AICameraIntrinsics,
        trackingState: AITrackingState,
        zoomFactor: CGFloat,
        gravityVector: SIMD3<Float>? = nil
    ) {
        self.transform = transform
        self.intrinsics = intrinsics
        self.trackingState = trackingState
        self.zoomFactor = zoomFactor
        self.gravityVector = gravityVector
    }
}

/// Camera intrinsic parameters
struct AICameraIntrinsics: Sendable {
    let fx: Float  // Focal length X
    let fy: Float  // Focal length Y
    let cx: Float  // Principal point X
    let cy: Float  // Principal point Y
}

/// ARKit tracking state simplified for AI flow
enum AITrackingState: Sendable {
    case normal
    case limited
    case notAvailable
}

// MARK: - Tracking Recovery State (Story 6.7)

/// Detailed tracking state for recovery handling.
/// Extends AITrackingState with reason information and recovery timing.
/// Per Story 6.7 - Task 1.2
enum TrackingRecoveryState: Equatable, Sendable {
    /// Normal tracking - no issues
    case normal

    /// Limited tracking with specific reason
    case limited(reason: TrackingLimitedReason)

    /// Tracking completely lost, attempting recovery
    /// - Parameter elapsedSeconds: Time since tracking was lost
    case lost(elapsedSeconds: TimeInterval)

    /// Recovery failed after timeout (10 seconds)
    case failed

    /// Whether tracking is usable (normal or limited)
    var isUsable: Bool {
        switch self {
        case .normal, .limited:
            return true
        case .lost, .failed:
            return false
        }
    }

    /// Whether this state requires user attention
    var requiresUserAction: Bool {
        switch self {
        case .normal:
            return false
        case .limited, .lost:
            return true
        case .failed:
            return true
        }
    }

    /// User-facing message for this state
    var userMessage: String {
        switch self {
        case .normal:
            return ""
        case .limited(let reason):
            return reason.userMessage
        case .lost:
            return "Tracking lost - move back to scanned area"
        case .failed:
            return "Tracking failed"
        }
    }
}

/// Reason for limited tracking state.
/// Maps to ARCamera.TrackingState.Reason from ARKit.
enum TrackingLimitedReason: Equatable, Sendable {
    /// ARKit is initializing
    case initializing

    /// User is moving too fast
    case excessiveMotion

    /// Not enough visual features in the environment
    case insufficientFeatures

    /// Attempting to relocalize after interruption
    case relocalizing

    /// Unknown reason
    case unknown

    /// User-facing message for this reason
    var userMessage: String {
        switch self {
        case .initializing:
            return "Initializing tracking..."
        case .excessiveMotion:
            return "Move slowly, tracking limited"
        case .insufficientFeatures:
            return "Point at a textured area"
        case .relocalizing:
            return "Tracking lost - move back to scanned area"
        case .unknown:
            return "Tracking limited"
        }
    }

    /// SF Symbol icon name for this reason
    var iconName: String {
        switch self {
        case .initializing:
            return "hourglass"
        case .excessiveMotion:
            return "hand.raised.fill"
        case .insufficientFeatures:
            return "viewfinder"
        case .relocalizing:
            return "arrow.uturn.backward"
        case .unknown:
            return "exclamationmark.triangle.fill"
        }
    }
}

/// Metadata about the capture session
struct AICaptureMetadata {
    let deviceModel: String
    let osVersion: String
    let captureDate: Date
    let videoDuration: TimeInterval
    let photoCount: Int
    let averageLighting: Float?
}

// MARK: - Supporting Types

/// Confidence levels for measurements and detections
enum AIConfidenceLevel: String, Comparable, Codable {
    case low      // < 60%
    case medium   // 60-79%
    case high     // >= 80%

    var threshold: Float {
        switch self {
        case .low: return 0.0
        case .medium: return 0.6
        case .high: return 0.8
        }
    }

    // Comparable conformance
    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: AIConfidenceLevel, rhs: AIConfidenceLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var badgeColor: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}

// MARK: - Object Confidence Score (stub for ConfidenceBadge UI)

/// Per-object confidence score with factor breakdown.
/// Used by ConfidenceBadge/ConfidenceDetailView for detailed drill-down.
/// In the server pipeline, per-object scores come from the Python backend.
struct ObjectConfidenceScore {
    let level: AIConfidenceLevel
    let objectType: ObjectType
    let score: Float
    let factors: ConfidenceFactors
    let warnings: [String]

    var displayPercentage: String {
        "\(Int(score * 100))%"
    }

    enum ObjectType {
        case baseCabinet, upperCabinet, appliance, wall, other

        var displayText: String {
            switch self {
            case .baseCabinet: return "Base Cabinet"
            case .upperCabinet: return "Upper Cabinet"
            case .appliance: return "Appliance"
            case .wall: return "Wall"
            case .other: return "Object"
            }
        }
    }
}

/// Factor breakdown for a confidence score.
struct ConfidenceFactors {
    let segmentationClarity: Float
    let depthConsistency: Float
    let poseAccuracy: Float
    let standardSizeMatch: Float

    enum Weights {
        static let segmentationClarity: Float = 0.3
        static let depthConsistency: Float = 0.3
        static let poseAccuracy: Float = 0.2
        static let standardSizeMatch: Float = 0.2
    }
}

/// Quote readiness level for QuoteReadinessBadge UI.
enum QuoteReadinessLevel {
    case ready
    case withCaveats
    case notRecommended

    var shortLabel: String {
        switch self {
        case .ready: return "Quote Ready"
        case .withCaveats: return "With Caveats"
        case .notRecommended: return "Not Recommended"
        }
    }
}

// MARK: - Quality Metrics (Story 2.4)

/// Aggregate quality metrics collected during a capture session.
/// Per Story 2.4 - Task 5
struct AIQualityMetrics: Codable, Equatable {
    /// Average blur score across analyzed frames (Laplacian variance)
    let averageBlurScore: Float

    /// Average brightness across analyzed frames (0-255)
    let averageBrightness: Float

    /// Total number of frames analyzed
    let analyzedFrameCount: Int

    /// Number of frames discarded due to quality issues
    let discardedFrameCount: Int

    /// Number of times quality warnings were shown
    let poorQualityWindowCount: Int

    /// Number of times circuit breaker tripped (analysis took >30ms)
    let circuitBreakerTripCount: Int

    /// 95th percentile of analysis time per frame
    let analysisTimePercentile95: TimeInterval

    /// Empty metrics for initialization
    static let empty = AIQualityMetrics(
        averageBlurScore: 0,
        averageBrightness: 0,
        analyzedFrameCount: 0,
        discardedFrameCount: 0,
        poorQualityWindowCount: 0,
        circuitBreakerTripCount: 0,
        analysisTimePercentile95: 0
    )

    /// Whether capture had acceptable quality overall
    var hasAcceptableQuality: Bool {
        // Consider acceptable if <20% of frames were poor quality
        guard analyzedFrameCount > 0 else { return false }
        let poorRatio = Float(poorQualityWindowCount) / Float(analyzedFrameCount)
        return poorRatio < 0.2
    }
}

// MARK: - Confidence Scoring (for UI display)

/// Quote readiness level based on confidence scoring
enum QuoteReadiness: String {
    case recommended
    case withCaution
    case notRecommended

    var displayMessage: String {
        switch self {
        case .recommended:
            return "Results are ready for quoting"
        case .withCaution:
            return "Results may need manual verification before quoting"
        case .notRecommended:
            return "Manual verification strongly recommended before quoting"
        }
    }
}

/// Confidence scoring result used by UI to display warnings.
/// Minimal version — full scoring will come from server pipeline.
struct ConfidenceScoringResult {
    let objectScores: [Any]
    let overallScore: Float
    let overallLevel: AIConfidenceLevel
    let quoteReadiness: QuoteReadiness
    let itemsNeedingVerification: Int
    let warnings: [String]
    let processingTimeMs: Int
    let limitingObjectId: UUID?

    var displayPercentage: String {
        "\(Int(overallScore * 100))%"
    }
}
