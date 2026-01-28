//
//  AIDetectedCabinet.swift
//  cabinetscan
//
//  Created for Story 4.2: Cabinet Detection (Base, Upper, Tall)
//

import Foundation
import simd

// MARK: - Detected Cabinet

/// A cabinet detected in the kitchen scan.
///
/// **Coordinate System:**
/// - All dimensions are in inches (calibrated via ScaleCalibrator)
/// - `positionOnWallInches` is distance from wall start point
/// - Raw dimensions are NEVER modified after measurement
///
/// **Usage:**
/// ```swift
/// let cabinet = AIDetectedCabinet(
///     type: .base,
///     wallId: wall.id,
///     rawDimensions: SIMD3(36.2, 34.5, 24.1),
///     ...
/// )
/// ```
struct AIDetectedCabinet: Identifiable, Equatable {
    /// Unique identifier for this cabinet
    let id: UUID

    /// 3D bounding box of the cabinet
    let boundingBox: AIBoundingBox3D

    /// Cabinet type classification
    let type: AICabinetType

    /// Reference to the wall this cabinet is attached to
    let wallId: UUID

    /// Position along the wall from wall start point (inches)
    let positionOnWallInches: Float

    /// Raw measured dimensions (width, height, depth) in inches
    /// These are NEVER modified - always preserve original measurements
    let rawDimensions: SIMD3<Float>

    /// Dimensions after standard size snapping (width, height, depth) in inches
    /// May equal rawDimensions if not snapped to standard
    let snappedDimensions: SIMD3<Float>

    /// Detection confidence level
    let confidence: AIConfidenceLevel

    /// Whether dimensions match standard cabinet sizes
    let isStandardSize: Bool

    /// Corner cabinet type (nil if not a corner cabinet)
    let cornerType: AICornerCabinetType?

    /// Notes about the detection (e.g., "Custom size", "Verify dimensions")
    let notes: [String]

    // MARK: - Computed Properties

    /// Raw width in inches
    var rawWidthInches: Float { rawDimensions.x }

    /// Raw height in inches
    var rawHeightInches: Float { rawDimensions.y }

    /// Raw depth in inches
    var rawDepthInches: Float { rawDimensions.z }

    /// Snapped width in inches
    var widthInches: Float { snappedDimensions.x }

    /// Snapped height in inches
    var heightInches: Float { snappedDimensions.y }

    /// Snapped depth in inches
    var depthInches: Float { snappedDimensions.z }

    /// Width in feet (computed from snapped)
    var widthFeet: Double { Double(widthInches) / 12.0 }

    /// Whether this is a corner cabinet
    var isCornerCabinet: Bool { cornerType != nil }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        boundingBox: AIBoundingBox3D,
        type: AICabinetType,
        wallId: UUID,
        positionOnWallInches: Float,
        rawDimensions: SIMD3<Float>,
        snappedDimensions: SIMD3<Float>,
        confidence: AIConfidenceLevel,
        isStandardSize: Bool,
        cornerType: AICornerCabinetType? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.type = type
        self.wallId = wallId
        self.positionOnWallInches = positionOnWallInches
        self.rawDimensions = rawDimensions
        self.snappedDimensions = snappedDimensions
        self.confidence = confidence
        self.isStandardSize = isStandardSize
        self.cornerType = cornerType
        self.notes = notes
    }
}

// MARK: - Cabinet Type

/// Classification of cabinet type.
enum AICabinetType: String, Codable, CaseIterable {
    /// Base cabinet (below countertop, ~34.5" height)
    case base

    /// Upper/wall cabinet (above countertop, mounted on wall)
    case upper

    /// Tall/pantry cabinet (floor to near-ceiling, >72" height)
    case tall

    /// Human-readable description
    var displayText: String {
        switch self {
        case .base: return "Base Cabinet"
        case .upper: return "Upper Cabinet"
        case .tall: return "Tall Cabinet"
        }
    }

    /// Standard height for this cabinet type (inches)
    var standardHeightInches: Float {
        switch self {
        case .base: return 34.5
        case .upper: return 30.0  // Most common upper height
        case .tall: return 84.0   // Most common tall height
        }
    }

    /// Standard depth for this cabinet type (inches)
    var standardDepthInches: Float {
        switch self {
        case .base: return 24.0
        case .upper: return 12.0
        case .tall: return 24.0
        }
    }
}

// MARK: - Corner Cabinet Type

/// Classification of corner cabinet type.
enum AICornerCabinetType: String, Codable, CaseIterable {
    /// Lazy Susan (rotating shelves, typically 33"-36" each side)
    case lazySusan

    /// Blind corner (extends into corner, door on one side only)
    case blindCorner

    /// Diagonal (angled 45° front across corner)
    case diagonal

    /// Human-readable description
    var displayText: String {
        switch self {
        case .lazySusan: return "Lazy Susan"
        case .blindCorner: return "Blind Corner"
        case .diagonal: return "Diagonal"
        }
    }
}

// MARK: - 3D Bounding Box

/// A 3D axis-aligned bounding box.
struct AIBoundingBox3D: Equatable {
    /// Center point of the bounding box (x, y, z in inches)
    let center: SIMD3<Float>

    /// Size of the bounding box (width, height, depth in inches)
    let size: SIMD3<Float>

    /// Rotation quaternion (identity for axis-aligned)
    let rotation: simd_quatf

    /// Minimum corner of the bounding box
    var min: SIMD3<Float> {
        center - size / 2
    }

    /// Maximum corner of the bounding box
    var max: SIMD3<Float> {
        center + size / 2
    }

    /// Creates an axis-aligned bounding box
    init(center: SIMD3<Float>, size: SIMD3<Float>, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) {
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    /// Creates a bounding box from min and max corners
    init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.center = (min + max) / 2
        self.size = max - min
        self.rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }
}

// MARK: - Cabinet Detection Result

/// Result of cabinet detection containing all detected cabinets and metadata.
struct CabinetDetectionResult: Equatable {
    /// All detected cabinets
    let cabinets: [AIDetectedCabinet]

    /// Base cabinets only
    var baseCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.type == .base }
    }

    /// Upper cabinets only
    var upperCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.type == .upper }
    }

    /// Tall cabinets only
    var tallCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.type == .tall }
    }

    /// Total count of all cabinets
    var totalCount: Int { cabinets.count }

    /// Count by cabinet type
    var countByType: [AICabinetType: Int] {
        Dictionary(grouping: cabinets, by: { $0.type })
            .mapValues { $0.count }
    }

    /// Total linear feet of base cabinets
    var baseLinearFeetTotal: Double {
        baseCabinets.reduce(0) { $0 + Double($1.widthInches) } / 12.0
    }

    /// Total linear feet of upper cabinets
    var upperLinearFeetTotal: Double {
        upperCabinets.reduce(0) { $0 + Double($1.widthInches) } / 12.0
    }

    /// Total linear inches of base cabinets (for accuracy validation)
    var baseLinearInchesTotal: Float {
        baseCabinets.reduce(0) { $0 + $1.widthInches }
    }

    /// Total linear inches of upper cabinets (for accuracy validation)
    var upperLinearInchesTotal: Float {
        upperCabinets.reduce(0) { $0 + $1.widthInches }
    }

    /// Cabinet run validation per wall
    let wallCoverageValidation: [WallCoverageValidation]

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection
    let warnings: [String]

    /// Overall detection confidence
    var overallConfidence: AIConfidenceLevel {
        guard !cabinets.isEmpty else { return .low }

        let highCount = cabinets.filter { $0.confidence == .high }.count
        let mediumCount = cabinets.filter { $0.confidence == .medium }.count

        let highRatio = Float(highCount) / Float(cabinets.count)
        let mediumRatio = Float(mediumCount) / Float(cabinets.count)

        if highRatio >= 0.7 {
            return .high
        } else if highRatio + mediumRatio >= 0.7 {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Wall Coverage Validation

/// Validation result for cabinet coverage on a single wall.
struct WallCoverageValidation: Equatable {
    /// Wall ID this validation applies to
    let wallId: UUID

    /// Total wall length available for cabinets (inches)
    let wallLengthInches: Float

    /// Sum of base cabinet widths on this wall (inches)
    let baseCabinetTotalInches: Float

    /// Sum of upper cabinet widths on this wall (inches)
    let upperCabinetTotalInches: Float

    /// Gaps between base cabinets (inches)
    let baseGaps: [CabinetGap]

    /// Gaps between upper cabinets (inches)
    let upperGaps: [CabinetGap]

    /// Discrepancy between wall length and cabinet coverage (inches)
    var coverageDiscrepancyInches: Float {
        wallLengthInches - baseCabinetTotalInches
    }

    /// Whether coverage is within expected range
    var isValid: Bool {
        // Allow up to 10% discrepancy or 6" gap (whichever is larger)
        let maxDiscrepancy = max(wallLengthInches * 0.1, 6.0)
        return abs(coverageDiscrepancyInches) <= maxDiscrepancy
    }
}

// MARK: - Cabinet Gap

/// A gap between cabinets on a wall.
struct CabinetGap: Equatable {
    /// Start position on wall (inches)
    let startInches: Float

    /// End position on wall (inches)
    let endInches: Float

    /// Gap width (inches)
    var widthInches: Float {
        endInches - startInches
    }
}

// MARK: - Cabinet Detection Error

/// Errors that can occur during cabinet detection.
enum CabinetDetectionError: LocalizedError, Equatable {
    case noRoomStructure
    case noPointCloud
    case noWallsDetected
    case detectionFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noRoomStructure:
            return "Room structure is required for cabinet detection"
        case .noPointCloud:
            return "Point cloud is empty - cannot detect cabinets"
        case .noWallsDetected:
            return "No walls detected - cabinets require walls for placement"
        case .detectionFailed(let reason):
            return "Cabinet detection failed: \(reason)"
        case .cancelled:
            return "Cabinet detection was cancelled"
        }
    }
}

// MARK: - Standard Cabinet Sizes

/// Standard US cabinet sizes for snapping and validation.
enum StandardCabinetSizes {
    /// Standard cabinet widths in inches
    static let widths: [Float] = [9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 42, 48]

    /// Standard upper cabinet heights in inches
    static let upperHeights: [Float] = [12, 15, 18, 24, 30, 36, 42]

    /// Standard base cabinet height in inches (without countertop)
    static let baseHeight: Float = 34.5

    /// Standard tall/pantry cabinet heights in inches
    static let tallHeights: [Float] = [84, 90, 96]

    /// Standard upper cabinet depths in inches
    static let upperDepths: [Float] = [12, 13, 14]

    /// Standard base cabinet depth in inches
    static let baseDepth: Float = 24

    /// Standard tall cabinet depth in inches
    static let tallDepth: Float = 24

    /// Finds the nearest standard width to a raw measurement.
    ///
    /// - Parameter rawWidth: The raw measured width in inches
    /// - Returns: Tuple of (nearest standard width, difference)
    static func nearestWidth(to rawWidth: Float) -> (standard: Float, difference: Float) {
        let nearest = widths.min(by: { abs($0 - rawWidth) < abs($1 - rawWidth) }) ?? rawWidth
        return (nearest, abs(nearest - rawWidth))
    }

    /// Finds the nearest standard height for a cabinet type.
    ///
    /// - Parameters:
    ///   - rawHeight: The raw measured height in inches
    ///   - type: The cabinet type
    /// - Returns: Tuple of (nearest standard height, difference)
    static func nearestHeight(to rawHeight: Float, type: AICabinetType) -> (standard: Float, difference: Float) {
        let heights: [Float]
        switch type {
        case .base:
            heights = [baseHeight]
        case .upper:
            heights = upperHeights
        case .tall:
            heights = tallHeights
        }

        let nearest = heights.min(by: { abs($0 - rawHeight) < abs($1 - rawHeight) }) ?? rawHeight
        return (nearest, abs(nearest - rawHeight))
    }

    /// Finds the nearest standard depth for a cabinet type.
    ///
    /// - Parameters:
    ///   - rawDepth: The raw measured depth in inches
    ///   - type: The cabinet type
    /// - Returns: Tuple of (nearest standard depth, difference)
    static func nearestDepth(to rawDepth: Float, type: AICabinetType) -> (standard: Float, difference: Float) {
        let depths: [Float]
        switch type {
        case .base:
            depths = [baseDepth]
        case .upper:
            depths = upperDepths
        case .tall:
            depths = [tallDepth]
        }

        let nearest = depths.min(by: { abs($0 - rawDepth) < abs($1 - rawDepth) }) ?? rawDepth
        return (nearest, abs(nearest - rawDepth))
    }
}
