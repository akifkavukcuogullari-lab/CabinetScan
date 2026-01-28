//
//  AIFlowModels.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import simd
import Metal

// MARK: - AI Flow Internal Models
// These types are internal to AIFlow module and not shared with existing app code.
// Actual implementations will be added as each Epic progresses.

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

/// Metadata about the capture session
struct AICaptureMetadata {
    let deviceModel: String
    let osVersion: String
    let captureDate: Date
    let videoDuration: TimeInterval
    let photoCount: Int
    let averageLighting: Float?
}

// MARK: - Depth Frame Data

/// A single depth frame with associated metadata
struct AIDepthFrame {
    /// Depth values as a 2D array (height x width)
    let depthData: [[Float]]

    /// Width of the depth map
    let width: Int

    /// Height of the depth map
    let height: Int

    /// Timestamp relative to session start
    let timestamp: TimeInterval

    /// Camera pose at capture time
    let pose: AIPose

    /// Confidence level for this frame
    let confidence: AIConfidenceLevel
}

// MARK: - Point Cloud Data

/// 3D point cloud generated from depth frames.
///
/// **ADR-002: Zero-Copy GPU Pipeline**
/// When `metalBuffer` is set, prefer using it directly over `points` array
/// to avoid GPU→CPU→GPU round-trips. TSDF fusion (Story 3.4) should consume
/// the Metal buffer directly when available.
struct AIPointCloud {
    /// Array of 3D points (populated lazily from metalBuffer if needed)
    var points: [SIMD3<Float>] = []

    /// Colors for each point (optional)
    var colors: [SIMD3<Float>]?

    /// Normals for each point (optional)
    var normals: [SIMD3<Float>]?

    /// Metal buffer for zero-copy GPU pipeline (ADR-002).
    /// When set, prefer this over `points` array to avoid GPU→CPU→GPU copies.
    var metalBuffer: MTLBuffer?

    /// Cached point count (avoids recomputing from buffer)
    private var _pointCount: Int = 0

    /// Number of valid points in the cloud.
    /// Uses cached count if metalBuffer is present.
    var count: Int {
        if metalBuffer != nil {
            return _pointCount
        }
        return points.count
    }

    /// Whether the point cloud is empty
    var isEmpty: Bool { count == 0 }

    /// Initializes a point cloud with optional components.
    init(
        points: [SIMD3<Float>] = [],
        colors: [SIMD3<Float>]? = nil,
        normals: [SIMD3<Float>]? = nil,
        metalBuffer: MTLBuffer? = nil,
        pointCount: Int = 0
    ) {
        self.points = points
        self.colors = colors
        self.normals = normals
        self.metalBuffer = metalBuffer
        self._pointCount = pointCount > 0 ? pointCount : points.count
    }

    /// Lazily converts metalBuffer to Swift array only when needed.
    /// Call this only when you need CPU access to points.
    mutating func getPoints() -> [SIMD3<Float>] {
        if points.isEmpty, let buffer = metalBuffer, _pointCount > 0 {
            // Convert only when explicitly needed
            let pointer = buffer.contents().bindMemory(
                to: SIMD3<Float>.self,
                capacity: _pointCount
            )
            points = Array(UnsafeBufferPointer(start: pointer, count: _pointCount))
        }
        return points
    }
}

// MARK: - Detection Results

/// Results from the object detection pipeline
struct AIDetectionResults {
    /// Detected room structure
    var room: AIDetectedRoom?

    /// Detected cabinets
    var cabinets: [AIDetectedCabinet] = []

    /// Detected appliances
    var appliances: [AIDetectedAppliance] = []

    /// Detected countertops
    var countertops: [AIDetectedCountertop] = []

    /// Detected openings (doors, windows)
    var openings: [AIDetectedOpening] = []

    /// Overall confidence score
    var overallConfidence: AIConfidenceLevel = .low

    /// Processing metadata
    var processingMetadata: AIProcessingMetadata?
}

// MARK: - Detected Objects (Placeholders)

/// Placeholder for detected room structure
struct AIDetectedRoom {
    // Will be fully defined in Epic 4
    var boundaryPolygon: [SIMD2<Float>] = []
    var walls: [AIDetectedWall] = []
    var floorPlane: AIPlane?
}

struct AIDetectedWall {
    var startPoint: SIMD2<Float>
    var endPoint: SIMD2<Float>
    var height: Float
    var isOpen: Bool
}

struct AIPlane {
    var normal: SIMD3<Float>
    var distance: Float
}

/// Placeholder for detected cabinet
struct AIDetectedCabinet {
    // Will be fully defined in Epic 4
    var type: AICabinetType = .base
    var bounds: AIBoundingBox = AIBoundingBox()
    var confidence: AIConfidenceLevel = .low
}

enum AICabinetType {
    case base
    case upper
    case tall
    case corner
}

/// Placeholder for detected appliance
struct AIDetectedAppliance {
    // Will be fully defined in Epic 4
    var type: AIApplianceType = .other
    var position: SIMD3<Float> = .zero
    var confidence: AIConfidenceLevel = .low
}

enum AIApplianceType {
    case refrigerator
    case range
    case dishwasher
    case microwave
    case hood
    case sink
    case other
}

/// Placeholder for detected countertop
struct AIDetectedCountertop {
    // Will be fully defined in Epic 4
    var polygon: [SIMD2<Float>] = []
    var height: Float = 36.0
    var confidence: AIConfidenceLevel = .low
}

/// Placeholder for detected opening (door/window)
struct AIDetectedOpening {
    // Will be fully defined in Epic 4
    var type: AIOpeningType = .door
    var bounds: AIBoundingBox = AIBoundingBox()
    var confidence: AIConfidenceLevel = .low
}

enum AIOpeningType {
    case door
    case window
}

// MARK: - Supporting Types

/// 3D bounding box
struct AIBoundingBox {
    var center: SIMD3<Float> = .zero
    var extents: SIMD3<Float> = .zero

    var width: Float { extents.x * 2 }
    var height: Float { extents.y * 2 }
    var depth: Float { extents.z * 2 }
}

/// Confidence levels for measurements and detections
enum AIConfidenceLevel: Comparable {
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
}

/// Metadata about the processing pipeline
struct AIProcessingMetadata {
    let processingTimeMs: Int
    let modelVersions: [String: String]
    let calibrationMethod: AICalibrationMethod
    let calibrationConfidence: Float
}

enum AICalibrationMethod {
    case autoCountertop
    case autoCeiling
    case manualDoor
    case manualCeiling
    case failed
}

// MARK: - Scale Calibration Results (Story 3.5)

/// Result of automatic scale calibration.
///
/// After calibration, multiply any mesh coordinate by `scaleFactor` to convert
/// from mesh units to inches.
struct ScaleCalibrationResult {
    /// Scale factor to convert mesh units to inches.
    /// Multiply any mesh coordinate by this value to get inches.
    let scaleFactor: Float

    /// Method used for calibration
    let calibrationMethod: AICalibrationMethod

    /// Confidence level based on validation
    let confidenceLevel: AIConfidenceLevel

    /// Detected countertop height in inches (should be ~36")
    let countertopHeightInches: Float?

    /// Detected ceiling height in inches (if available)
    let ceilingHeightInches: Float?

    /// Detected floor plane (after alignment)
    let floorPlane: AIPlane

    /// Detailed validation results
    let validationResults: CalibrationValidation

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Reason for auto-calibration failure (Story 3.6)
    /// Only set when calibrationMethod == .failed and manual calibration was triggered
    var autoCalibrationFailureReason: String?
}

/// Validation results for scale calibration.
///
/// Uses multiple reference points (upper cabinet height, ceiling height)
/// to validate the scale factor derived from countertop detection.
struct CalibrationValidation {
    /// Whether upper cabinet check passed (~54" height)
    let upperCabinetHeightValid: Bool

    /// Detected upper cabinet bottom height in inches
    let upperCabinetHeightInches: Float?

    /// Whether ceiling check passed (96"-108")
    let ceilingHeightValid: Bool

    /// Detected ceiling height in inches
    let ceilingHeightInches: Float?

    /// Number of validation checks that passed (0, 1, or 2)
    var passedChecks: Int {
        (upperCabinetHeightValid ? 1 : 0) + (ceilingHeightValid ? 1 : 0)
    }

    /// Empty validation result (all checks failed)
    static let empty = CalibrationValidation(
        upperCabinetHeightValid: false,
        upperCabinetHeightInches: nil,
        ceilingHeightValid: false,
        ceilingHeightInches: nil
    )
}

// MARK: - Manual Calibration Types (Story 3.6)

/// Manual calibration option selected by user
enum ManualCalibrationOption: String, CaseIterable {
    case door = "door"
    case ceiling = "ceiling"

    var title: String {
        switch self {
        case .door: return "I have a door in the scan"
        case .ceiling: return "Use ceiling height"
        }
    }

    var subtitle: String? {
        switch self {
        case .door: return "Recommended"
        case .ceiling: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .door: return "door.left.hand.open"
        case .ceiling: return "ruler"
        }
    }
}

/// Standard US interior door widths
enum DoorWidth: Float, CaseIterable {
    case thirty = 30
    case thirtyTwo = 32
    case thirtySix = 36

    var displayString: String {
        return "\(Int(rawValue))\""
    }

    /// Standard US interior door height (6'8")
    static let standardDoorHeightInches: Float = 80
}

/// Standard US ceiling heights
enum CeilingHeight: Float, CaseIterable {
    case eight = 96    // 8 feet
    case nine = 108    // 9 feet
    case ten = 120     // 10 feet

    var displayString: String {
        let feet = Int(rawValue / 12)
        return "\(feet)' (\(Int(rawValue))\")"
    }

    var feetString: String {
        let feet = Int(rawValue / 12)
        return "\(feet)'"
    }
}

/// State of manual calibration process
enum ManualCalibrationState {
    case idle
    case calculating
    case complete(ScaleCalibrationResult)
    case error(String)
}

extension ManualCalibrationState: Equatable {
    static func == (lhs: ManualCalibrationState, rhs: ManualCalibrationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.calculating, .calculating),
             (.complete, .complete):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

/// Input data needed for manual calibration
struct ManualCalibrationInput {
    /// The fusion result containing the mesh
    let fusionResult: TSDFFusionResult

    /// Already-detected floor plane (from auto-calibration attempt)
    let floorPlane: AIPlane

    /// Reason why auto-calibration failed
    let failureReason: String

    /// One of the captured photos to show as preview
    let previewPhotoURL: URL?
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
