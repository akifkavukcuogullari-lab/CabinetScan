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

    /// Detected windows (Story 4.9)
    var windows: [AIDetectedWindow] = []

    /// Detected doors (Story 4.9)
    var doors: [AIDetectedDoor] = []

    /// Detected islands (Story 4.5)
    var islands: [AIDetectedIsland] = []

    /// Detected peninsulas (Story 4.5)
    var peninsulas: [AIDetectedPeninsula] = []

    /// Overall confidence score
    var overallConfidence: AIConfidenceLevel = .low

    /// Processing metadata
    var processingMetadata: AIProcessingMetadata?

    // MARK: - Computed Properties (Story 4.5 & 4.9)

    /// Total count of windows detected
    var totalWindowCount: Int { windows.count }

    /// Total count of doors detected
    var totalDoorCount: Int { doors.count }

    /// Windows above countertop level (sink windows)
    var windowsAboveCountertop: [AIDetectedWindow] {
        windows.filter { $0.sillHeightInches >= 36.0 }
    }

    /// Doors that may need filler panels (based on notes)
    var doorsWithClearanceIssues: [AIDetectedDoor] {
        doors.filter { door in
            door.notes.contains { $0.lowercased().contains("filler") || $0.lowercased().contains("clearance") }
        }
    }

    /// Total count of islands detected (Story 4.5)
    var totalIslandCount: Int { islands.count }

    /// Total count of peninsulas detected (Story 4.5)
    var totalPeninsulaCount: Int { peninsulas.count }

    /// Total island countertop area in square feet (Story 4.5)
    var islandCountertopAreaSquareFeet: Float {
        islands.reduce(0) { $0 + $1.countertopAreaSquareFeet }
    }

    /// Total peninsula countertop area in square feet (Story 4.5)
    var peninsulaCountertopAreaSquareFeet: Float {
        peninsulas.reduce(0) { $0 + $1.countertopAreaSquareFeet }
    }
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

// Note: AIDetectedCabinet and AICabinetType are defined in
// Features/AIFlow/Detection/AIDetectedCabinet.swift (Story 4.2/4.3)

// Note: AIDetectedAppliance, AIApplianceType, AIApplianceSubType are defined in
// Features/AIFlow/Detection/ApplianceDetector.swift (Story 4.4)

/// Placeholder for detected countertop
struct AIDetectedCountertop {
    // Will be fully defined in Epic 4
    var polygon: [SIMD2<Float>] = []
    var height: Float = 36.0
    var confidence: AIConfidenceLevel = .low
}

// MARK: - Opening Type

/// Type of wall opening.
enum AIOpeningType: String, Codable {
    case window
    case door
    case doorway     // No door, just opening
    case slidingDoor
    case frenchDoor
}

// MARK: - Door Swing Direction

/// Direction a door swings open.
enum DoorSwingDirection: String, Codable {
    case left
    case right
    case unknown
}

// MARK: - Detected Opening Protocol (ADR-2)

/// Protocol for shared properties between windows and doors.
/// Provides type safety while sharing common interface.
protocol DetectedOpeningProtocol: Identifiable, Equatable, Codable {
    var id: UUID { get }
    var type: AIOpeningType { get }
    var wallId: UUID { get }
    var positionOnWallInches: Float { get }
    var heightFromFloorInches: Float { get }
    var boundingBox: AIBoundingBox3D { get }
    var rawDimensions: SIMD3<Float> { get }
    var snappedDimensions: SIMD3<Float> { get }
    var confidence: AIConfidenceLevel { get }
    var isStandardSize: Bool { get }
    var notes: [String] { get }
    var widthInches: Float { get }
    var heightInches: Float { get }
}

// MARK: - AIDetectedWindow

/// A detected window with dimensions and cabinet placement guidance.
///
/// Per Story 4.9 AC3, AC5: Windows are detected with ±1" accuracy,
/// distance from countertop is measured, and upper cabinet placement
/// options are calculated.
struct AIDetectedWindow: DetectedOpeningProtocol {
    // MARK: - Protocol Properties

    let id: UUID
    let wallId: UUID
    let positionOnWallInches: Float
    let heightFromFloorInches: Float
    let boundingBox: AIBoundingBox3D
    let rawDimensions: SIMD3<Float>
    let snappedDimensions: SIMD3<Float>
    let confidence: AIConfidenceLevel
    let isStandardSize: Bool
    let notes: [String]

    // MARK: - Window-Specific Properties

    /// Sill height from floor in inches
    let sillHeightInches: Float

    /// Distance from countertop to window sill (nil if not above countertop)
    let distanceFromCountertopInches: Float?

    /// Whether window has visible frame
    let hasFrame: Bool

    /// Available height for upper cabinets above window (ADR-4)
    /// Calculated as: ceilingHeight - windowTop - 18" min clearance
    let availableUpperCabinetHeight: Float?

    /// Recommendation for upper cabinet placement (ADR-4)
    /// e.g., "Standard 30\" upper cabinets possible", "18\" upper cabinets possible", "No upper cabinets above window"
    let upperCabinetRecommendation: String?

    // MARK: - Protocol Computed Properties

    var type: AIOpeningType { .window }
    var widthInches: Float { snappedDimensions.x }
    var heightInches: Float { snappedDimensions.y }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, wallId, positionOnWallInches, heightFromFloorInches
        case boundingBox, rawDimensions, snappedDimensions
        case confidence, isStandardSize, notes
        case sillHeightInches, distanceFromCountertopInches, hasFrame
        case availableUpperCabinetHeight, upperCabinetRecommendation
    }
}

// MARK: - AIDetectedDoor

/// A detected door with dimensions and swing direction.
///
/// Per Story 4.9 AC2, AC4, AC6: Doors are detected with standard
/// width captured (32", 36"), swing direction noted if detectable,
/// and clearance to adjacent cabinets measured for filler calculations.
struct AIDetectedDoor: DetectedOpeningProtocol {
    // MARK: - Protocol Properties

    let id: UUID
    let type: AIOpeningType  // .door, .slidingDoor, .frenchDoor, .doorway
    let wallId: UUID
    let positionOnWallInches: Float
    let heightFromFloorInches: Float
    let boundingBox: AIBoundingBox3D
    let rawDimensions: SIMD3<Float>
    let snappedDimensions: SIMD3<Float>
    let confidence: AIConfidenceLevel
    let isStandardSize: Bool
    let notes: [String]

    // MARK: - Door-Specific Properties

    /// Swing direction (left, right, or unknown)
    /// Best-effort detection, defaults to .unknown
    let swingDirection: DoorSwingDirection?

    /// Whether this is a full-height door (>84")
    let isFullHeight: Bool

    /// Clearance to adjacent cabinet (nil if no adjacent cabinet)
    /// Used for filler/spacer calculations
    let clearanceToAdjacentCabinet: Float?

    // MARK: - Protocol Computed Properties

    var widthInches: Float { snappedDimensions.x }
    var heightInches: Float { snappedDimensions.y }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, wallId, positionOnWallInches, heightFromFloorInches
        case boundingBox, rawDimensions, snappedDimensions
        case confidence, isStandardSize, notes
        case swingDirection, isFullHeight, clearanceToAdjacentCabinet
    }
}

// MARK: - Legacy Placeholder (deprecated)

/// Placeholder for detected opening (door/window) - deprecated, use AIDetectedWindow or AIDetectedDoor
@available(*, deprecated, message: "Use AIDetectedWindow or AIDetectedDoor instead")
struct AIDetectedOpening {
    var type: AIOpeningType = .door
    var bounds: AIBoundingBox = AIBoundingBox()
    var confidence: AIConfidenceLevel = .low
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
