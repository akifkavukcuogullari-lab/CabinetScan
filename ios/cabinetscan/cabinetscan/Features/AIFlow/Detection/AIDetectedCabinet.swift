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
struct AIDetectedCabinet: Identifiable, Equatable, Codable {
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

    /// Detailed corner cabinet measurements (nil if not a corner cabinet)
    /// Contains wall-specific dimensions and corner angle for quote accuracy
    let cornerDetails: AICornerCabinetDetails?

    // MARK: - Special Cabinet Properties

    /// Whether this is a stacked cabinet (part of a double-row upper configuration)
    /// When true, this cabinet is either the upper or lower row of a stacked pair
    let isStacked: Bool

    /// Special cabinet type classification (nil for standard cabinets)
    /// Used for pricing adjustments and special dimension expectations
    let specialType: CabinetSpecialType?

    /// ID of the cabinet this one is stacked with (for stacked pairs)
    /// The lower cabinet links to upper, and upper links to lower
    let stackedWithCabinetId: UUID?

    /// ID of the appliance this cabinet hosts (for appliance housing cabinets)
    /// Used for microwave housing and oven housing cabinets
    let hostingApplianceId: UUID?

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
    var isCornerCabinet: Bool { cornerType != nil && cornerDetails != nil }

    /// Corner cabinet wall 1 length (nil if not corner cabinet)
    var cornerWall1LengthInches: Float? { cornerDetails?.wall1LengthInches }

    /// Corner cabinet wall 2 length (nil if not corner cabinet)
    var cornerWall2LengthInches: Float? { cornerDetails?.wall2LengthInches }

    // MARK: - Special Cabinet Computed Properties

    /// Whether this cabinet has a special configuration affecting pricing
    var isSpecialCabinet: Bool {
        isStacked || (specialType != nil && specialType != .standard)
    }

    /// Whether this cabinet hosts an appliance
    var isApplianceHousing: Bool {
        hostingApplianceId != nil
    }

    /// Whether this is a refrigerator upper cabinet (24" depth)
    var isRefrigeratorCabinet: Bool {
        specialType == .refrigeratorUpper
    }

    /// Whether this is a microwave housing cabinet
    var isMicrowaveCabinet: Bool {
        specialType == .microwaveHousing
    }

    /// Whether this is an oven housing cabinet
    var isOvenCabinet: Bool {
        specialType == .ovenHousing
    }

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
        cornerDetails: AICornerCabinetDetails? = nil,
        isStacked: Bool = false,
        specialType: CabinetSpecialType? = nil,
        stackedWithCabinetId: UUID? = nil,
        hostingApplianceId: UUID? = nil,
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
        self.cornerDetails = cornerDetails
        self.isStacked = isStacked
        self.specialType = specialType
        self.stackedWithCabinetId = stackedWithCabinetId
        self.hostingApplianceId = hostingApplianceId
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

// MARK: - Cabinet Special Type

/// Classification of special cabinet configurations.
///
/// Special cabinets require different pricing and may have unique dimensions.
/// Used for stacked cabinets, above-appliance cabinets, and appliance housing.
enum CabinetSpecialType: String, Codable, CaseIterable {
    /// Standard cabinet with no special configuration
    case standard

    /// Stacked upper cabinet (short upper above standard upper)
    /// Typically 12"-24" height, mounted above standard 30"-42" upper
    case stacked

    /// Upper cabinet above refrigerator
    /// Deeper than standard (24" vs 12"), height 12"-24"
    case refrigeratorUpper

    /// Upper or tall cabinet housing a built-in microwave
    case microwaveHousing

    /// Tall cabinet housing a wall oven (single or double)
    case ovenHousing

    /// Human-readable description
    var displayText: String {
        switch self {
        case .standard: return "Standard"
        case .stacked: return "Stacked Upper"
        case .refrigeratorUpper: return "Refrigerator Upper"
        case .microwaveHousing: return "Microwave Housing"
        case .ovenHousing: return "Oven Housing"
        }
    }

    /// Whether this special type affects quote pricing
    var affectsPricing: Bool {
        switch self {
        case .standard: return false
        case .stacked, .refrigeratorUpper, .microwaveHousing, .ovenHousing: return true
        }
    }

    /// Expected depth for this cabinet type (inches)
    /// Returns nil for standard (use type-based depth)
    var expectedDepthInches: Float? {
        switch self {
        case .standard: return nil
        case .stacked: return 12.0 // Same as standard upper
        case .refrigeratorUpper: return 24.0 // Deeper to match fridge depth
        case .microwaveHousing: return nil // Varies by installation type
        case .ovenHousing: return 24.0 // Full depth for oven
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

    /// Dead corner (non-functional space, no cabinet installed)
    case deadCorner

    /// Human-readable description
    var displayText: String {
        switch self {
        case .lazySusan: return "Lazy Susan"
        case .blindCorner: return "Blind Corner"
        case .diagonal: return "Diagonal"
        case .deadCorner: return "Dead Corner"
        }
    }
}

// MARK: - Corner Cabinet Details

/// Detailed measurements and information for corner cabinets.
///
/// Corner cabinets span two perpendicular walls and require special measurement
/// capturing both wall dimensions and the corner angle.
///
/// **Quote Impact:**
/// - Lazy Susan typically costs 2-3x regular base cabinet
/// - Blind corner requires special filler pieces
/// - Diagonal affects adjacent cabinet sizing
///
/// **Usage:**
/// ```swift
/// let cornerDetails = AICornerCabinetDetails(
///     wall1Id: wall1.id,
///     wall2Id: wall2.id,
///     wall1LengthInches: 36.0,
///     wall2LengthInches: 36.0,
///     cornerAngleDegrees: 90.0,
///     isUpper: false
/// )
/// ```
struct AICornerCabinetDetails: Equatable, Codable {
    /// First wall this cabinet attaches to
    let wall1Id: UUID

    /// Second wall (perpendicular to first)
    let wall2Id: UUID

    /// Cabinet length along first wall from corner (inches)
    let wall1LengthInches: Float

    /// Cabinet length along second wall from corner (inches)
    let wall2LengthInches: Float

    /// For diagonal type: width of angled face (inches)
    /// Nil for Lazy Susan and Blind Corner types
    let diagonalWidthInches: Float?

    /// Measured corner angle in degrees (nominally 90°)
    /// Used to verify corner is suitable for standard cabinet (should be within ±2° of 90°)
    let cornerAngleDegrees: Float

    /// Whether this is an upper or base corner cabinet
    let isUpper: Bool

    /// Raw measurements before snapping (wall1, wall2) in inches
    let rawWallLengths: SIMD2<Float>

    /// Snapped measurements after standard size matching (wall1, wall2) in inches
    let snappedWallLengths: SIMD2<Float>

    // MARK: - Computed Properties

    /// Whether both wall dimensions match standard corner cabinet sizes.
    /// A corner cabinet is "standard" if the snapped values match standard sizes exactly.
    /// This is used for quote accuracy - only truly standard sizes should be marked as such.
    var isStandardCornerSize: Bool {
        // Use tight tolerance for "is standard" check (0.5" allows for float precision)
        // This is different from snapping tolerance (1.5") which is for finding nearest standard
        let matchTolerance: Float = 0.5

        // Get all possible standard sizes based on cabinet type
        let standardSizes: [Float]
        if isUpper {
            // Upper corner cabinets: Lazy Susan 24", Diagonal 24"
            standardSizes = StandardCornerCabinetSizes.lazySusanUpper + [StandardCornerCabinetSizes.diagonalWallFace]
        } else {
            // Base corner cabinets: Lazy Susan 33/36", Blind Corner 24-27/36-42", Diagonal 24"
            standardSizes = StandardCornerCabinetSizes.lazySusanBase +
                            StandardCornerCabinetSizes.blindCornerDoorSideWidths +
                            StandardCornerCabinetSizes.blindCornerBlindSideWidths +
                            [StandardCornerCabinetSizes.diagonalWallFace]
        }

        // Check if wall1 matches any standard size exactly
        let wall1IsStandard = standardSizes.contains { abs($0 - snappedWallLengths.x) <= matchTolerance }

        // Check if wall2 matches any standard size exactly
        let wall2IsStandard = standardSizes.contains { abs($0 - snappedWallLengths.y) <= matchTolerance }

        return wall1IsStandard && wall2IsStandard
    }

    /// Whether the corner angle is within tolerance of 90° (±2°)
    var isRightAngle: Bool {
        abs(cornerAngleDegrees - 90.0) <= 2.0
    }

    /// Total wall coverage in inches (sum of both walls)
    var totalWallCoverageInches: Float {
        wall1LengthInches + wall2LengthInches
    }

    // MARK: - Initialization

    init(
        wall1Id: UUID,
        wall2Id: UUID,
        wall1LengthInches: Float,
        wall2LengthInches: Float,
        diagonalWidthInches: Float? = nil,
        cornerAngleDegrees: Float,
        isUpper: Bool,
        rawWallLengths: SIMD2<Float>? = nil,
        snappedWallLengths: SIMD2<Float>? = nil
    ) {
        self.wall1Id = wall1Id
        self.wall2Id = wall2Id
        self.wall1LengthInches = wall1LengthInches
        self.wall2LengthInches = wall2LengthInches
        self.diagonalWidthInches = diagonalWidthInches
        self.cornerAngleDegrees = cornerAngleDegrees
        self.isUpper = isUpper
        self.rawWallLengths = rawWallLengths ?? SIMD2(wall1LengthInches, wall2LengthInches)
        self.snappedWallLengths = snappedWallLengths ?? SIMD2(wall1LengthInches, wall2LengthInches)
    }
}

// MARK: - 3D Bounding Box

/// A 3D axis-aligned bounding box.
struct AIBoundingBox3D: Equatable, Codable {
    /// Center point of the bounding box (x, y, z in inches)
    let center: SIMD3<Float>

    /// Size of the bounding box (width, height, depth in inches)
    let size: SIMD3<Float>

    /// Rotation quaternion components (ix, iy, iz, r) - identity for axis-aligned
    private let rotationComponents: SIMD4<Float>

    /// Rotation quaternion (identity for axis-aligned)
    var rotation: simd_quatf {
        simd_quatf(ix: rotationComponents.x, iy: rotationComponents.y, iz: rotationComponents.z, r: rotationComponents.w)
    }

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
        self.rotationComponents = SIMD4<Float>(rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real)
    }

    /// Creates a bounding box from min and max corners
    init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.center = (min + max) / 2
        self.size = max - min
        self.rotationComponents = SIMD4<Float>(0, 0, 0, 1)  // Identity quaternion
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

    /// Corner cabinets only (base and upper combined)
    var cornerCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isCornerCabinet }
    }

    /// Corner base cabinets only
    var cornerBaseCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isCornerCabinet && $0.type == .base }
    }

    /// Corner upper cabinets only
    var cornerUpperCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isCornerCabinet && $0.type == .upper }
    }

    /// Count of corner cabinets by type
    var cornerCountByType: [AICornerCabinetType: Int] {
        Dictionary(grouping: cornerCabinets.compactMap { $0.cornerType }, by: { $0 })
            .mapValues { $0.count }
    }

    /// Total count of all cabinets
    var totalCount: Int { cabinets.count }

    /// Whether no cabinets were detected (empty kitchen scenario - Story 6.1)
    var isEmpty: Bool { cabinets.isEmpty }

    /// Count of corner cabinets
    var cornerCount: Int { cornerCabinets.count }

    // MARK: - Special Cabinet Filtering

    /// Stacked upper cabinets only
    var stackedCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isStacked }
    }

    /// Refrigerator upper cabinets only
    var refrigeratorCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isRefrigeratorCabinet }
    }

    /// Microwave housing cabinets only
    var microwaveCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isMicrowaveCabinet }
    }

    /// Oven housing cabinets only
    var ovenCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isOvenCabinet }
    }

    /// All special cabinets (stacked, refrigerator, appliance housing)
    var specialCabinets: [AIDetectedCabinet] {
        cabinets.filter { $0.isSpecialCabinet }
    }

    /// Count of stacked cabinets
    var stackedCount: Int { stackedCabinets.count }

    /// Count of special cabinets
    var specialCount: Int { specialCabinets.count }

    /// Count by special cabinet type
    var countBySpecialType: [CabinetSpecialType: Int] {
        Dictionary(grouping: cabinets.compactMap { $0.specialType }, by: { $0 })
            .mapValues { $0.count }
    }

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

// MARK: - Standard Corner Cabinet Sizes

/// Standard US corner cabinet sizes for snapping and validation.
///
/// Corner cabinets have different sizing rules than regular cabinets:
/// - Lazy Susan: Equal dimensions on both walls
/// - Blind Corner: Asymmetric - longer door side, shorter blind side
/// - Diagonal: Standard wall face length with angled front
enum StandardCornerCabinetSizes {
    // MARK: - Lazy Susan Sizes

    /// Standard Lazy Susan base cabinet sizes (wall length on each side, inches)
    /// Lazy Susan cabinets have equal dimensions on both walls
    static let lazySusanBase: [Float] = [33, 36]

    /// Standard Lazy Susan upper cabinet sizes (wall length on each side, inches)
    static let lazySusanUpper: [Float] = [24]

    // MARK: - Blind Corner Sizes

    /// Standard blind corner door side range (inches)
    /// The door side is the accessible side with the cabinet door
    static let blindCornerDoorSideRange: ClosedRange<Float> = 36...42

    /// Standard blind corner blind side range (inches)
    /// The blind side extends into the corner and is not directly accessible
    static let blindCornerBlindSideRange: ClosedRange<Float> = 24...27

    /// Common blind corner door side widths (inches)
    static let blindCornerDoorSideWidths: [Float] = [36, 39, 42]

    /// Common blind corner blind side widths (inches)
    static let blindCornerBlindSideWidths: [Float] = [24, 27]

    // MARK: - Diagonal Sizes

    /// Standard diagonal cabinet wall face length (inches)
    /// Diagonal cabinets have equal length along each wall from the corner
    static let diagonalWallFace: Float = 24

    /// Standard diagonal cabinet angled face width (inches)
    /// The front face of a diagonal corner cabinet (at 45°)
    static let diagonalFaceWidth: Float = 34

    // MARK: - Tolerances

    /// Tolerance for equal side check when detecting Lazy Susan (inches)
    /// If both wall dimensions are within this tolerance, classify as Lazy Susan
    static let equalSideTolerance: Float = 3.0

    /// Tolerance for snapping to standard sizes (inches)
    /// If a measurement is within this tolerance of a standard size, snap to it
    static let snappingTolerance: Float = 1.5

    /// Tolerance for corner angle check (degrees)
    /// Corner must be within this tolerance of 90° to be a valid corner cabinet location
    static let cornerAngleTolerance: Float = 15.0

    /// Strict corner angle tolerance for assuming exact 90° (degrees)
    static let rightAngleTolerance: Float = 2.0

    // MARK: - Helper Methods

    /// Finds the nearest standard Lazy Susan size.
    ///
    /// - Parameters:
    ///   - wallLength: The measured wall length in inches
    ///   - isUpper: Whether this is an upper cabinet
    /// - Returns: Tuple of (nearest standard size, difference)
    static func nearestLazySusanSize(
        wallLength: Float,
        isUpper: Bool
    ) -> (standard: Float, difference: Float) {
        let sizes = isUpper ? lazySusanUpper : lazySusanBase
        let nearest = sizes.min(by: { abs($0 - wallLength) < abs($1 - wallLength) }) ?? wallLength
        return (nearest, abs(nearest - wallLength))
    }

    /// Finds the nearest standard blind corner door side size.
    ///
    /// - Parameter doorSideLength: The measured door side length in inches
    /// - Returns: Tuple of (nearest standard size, difference)
    static func nearestBlindCornerDoorSide(
        _ doorSideLength: Float
    ) -> (standard: Float, difference: Float) {
        let nearest = blindCornerDoorSideWidths.min(by: {
            abs($0 - doorSideLength) < abs($1 - doorSideLength)
        }) ?? doorSideLength
        return (nearest, abs(nearest - doorSideLength))
    }

    /// Finds the nearest standard blind corner blind side size.
    ///
    /// - Parameter blindSideLength: The measured blind side length in inches
    /// - Returns: Tuple of (nearest standard size, difference)
    static func nearestBlindCornerBlindSide(
        _ blindSideLength: Float
    ) -> (standard: Float, difference: Float) {
        let nearest = blindCornerBlindSideWidths.min(by: {
            abs($0 - blindSideLength) < abs($1 - blindSideLength)
        }) ?? blindSideLength
        return (nearest, abs(nearest - blindSideLength))
    }

    /// Checks if two wall lengths are equal within tolerance (for Lazy Susan detection).
    ///
    /// - Parameters:
    ///   - wall1: First wall length in inches
    ///   - wall2: Second wall length in inches
    /// - Returns: True if walls are equal within equalSideTolerance
    static func areWallsEqual(_ wall1: Float, _ wall2: Float) -> Bool {
        abs(wall1 - wall2) <= equalSideTolerance
    }

    /// Checks if dimensions match blind corner pattern (asymmetric).
    ///
    /// - Parameters:
    ///   - wall1: First wall length in inches
    ///   - wall2: Second wall length in inches
    /// - Returns: Tuple of (isBlindCorner, doorSideWall) where doorSideWall is 1 or 2
    static func isBlindCornerPattern(
        wall1: Float,
        wall2: Float
    ) -> (isBlindCorner: Bool, doorSideWall: Int?) {
        // Check if wall1 is door side, wall2 is blind side
        if blindCornerDoorSideRange.contains(wall1) && blindCornerBlindSideRange.contains(wall2) {
            return (true, 1)
        }
        // Check if wall2 is door side, wall1 is blind side
        if blindCornerDoorSideRange.contains(wall2) && blindCornerBlindSideRange.contains(wall1) {
            return (true, 2)
        }
        return (false, nil)
    }

    /// Checks if angle is within valid corner cabinet range (90° ± 15°).
    ///
    /// - Parameter angle: Corner angle in degrees
    /// - Returns: True if angle is between 75° and 105°
    static func isValidCornerAngle(_ angle: Float) -> Bool {
        abs(angle - 90.0) <= cornerAngleTolerance
    }
}

// MARK: - Standard Special Cabinet Sizes

/// Standard US special cabinet sizes for detection and validation.
///
/// Special cabinets include stacked uppers, refrigerator uppers, and appliance housing.
/// These have different dimension expectations than standard cabinets.
enum StandardSpecialCabinetSizes {
    // MARK: - Stacked Upper Cabinet Sizes

    /// Standard stacked upper cabinet heights (inches)
    /// Stacked uppers are shorter than standard uppers
    static let stackedUpperHeights: [Float] = [12, 15, 18, 24]

    /// Standard stacked upper cabinet depth (inches)
    /// Same as standard upper depth
    static let stackedUpperDepth: Float = 12.0

    /// Minimum gap above standard upper to detect stacked row (inches)
    static let stackedMinGapAbove: Float = 0.0

    /// Maximum gap above standard upper to detect stacked row (inches)
    static let stackedMaxGapAbove: Float = 6.0

    // MARK: - Refrigerator Upper Cabinet Sizes

    /// Standard refrigerator upper cabinet heights (inches)
    static let refrigeratorUpperHeights: [Float] = [12, 15, 18, 24]

    /// Standard refrigerator upper cabinet depth (inches)
    /// Deeper than standard to match refrigerator depth
    static let refrigeratorUpperDepth: Float = 24.0

    /// Tolerance for refrigerator upper depth matching (inches)
    static let refrigeratorDepthTolerance: Float = 3.0

    // MARK: - Microwave Housing Sizes

    /// Standard built-in microwave widths (inches)
    static let microwaveWidths: [Float] = [24, 27, 30]

    /// Standard microwave housing heights (inches)
    static let microwaveHousingHeights: [Float] = [15, 18]

    /// Standard microwave housing depths (inches)
    static let microwaveHousingDepths: [Float] = [12, 15, 18]

    // MARK: - Wall Oven Housing Sizes

    /// Standard single wall oven cutout heights (inches)
    static let singleOvenCutoutHeights: [Float] = [27, 29, 30]

    /// Standard double wall oven cutout heights (inches)
    static let doubleOvenCutoutHeights: [Float] = [50, 51, 53, 54]

    /// Standard wall oven housing widths (inches)
    static let ovenHousingWidths: [Float] = [27, 30]

    /// Standard wall oven housing depth (inches)
    static let ovenHousingDepth: Float = 24.0

    /// Minimum cabinet height for double oven (inches)
    static let doubleOvenMinCabinetHeight: Float = 84.0

    // MARK: - Detection Tolerances

    /// Tolerance for height matching (inches)
    static let heightTolerance: Float = 2.0

    /// Tolerance for depth matching (inches)
    static let depthTolerance: Float = 2.0

    // MARK: - Helper Methods

    /// Checks if height matches stacked upper pattern.
    ///
    /// - Parameter height: Cabinet height in inches
    /// - Returns: True if height is within stacked upper range (12"-24")
    static func isStackedUpperHeight(_ height: Float) -> Bool {
        height >= 12.0 - heightTolerance && height <= 24.0 + heightTolerance
    }

    /// Checks if depth matches refrigerator upper pattern (24" depth).
    ///
    /// - Parameter depth: Cabinet depth in inches
    /// - Returns: True if depth is within refrigerator upper range
    static func isRefrigeratorUpperDepth(_ depth: Float) -> Bool {
        abs(depth - refrigeratorUpperDepth) <= refrigeratorDepthTolerance
    }

    /// Checks if dimensions match microwave housing pattern.
    ///
    /// - Parameters:
    ///   - width: Cabinet width in inches
    ///   - height: Cabinet height in inches
    /// - Returns: True if dimensions match microwave housing
    static func isMicrowaveHousingSize(width: Float, height: Float) -> Bool {
        let widthMatches = microwaveWidths.contains { abs($0 - width) <= depthTolerance }
        let heightMatches = microwaveHousingHeights.contains { abs($0 - height) <= heightTolerance }
        return widthMatches && heightMatches
    }

    /// Checks if dimensions suggest double oven (vs single).
    ///
    /// - Parameter cutoutHeight: Oven cutout height in inches
    /// - Returns: True if cutout height suggests double oven
    static func isDoubleOvenHeight(_ cutoutHeight: Float) -> Bool {
        cutoutHeight >= 48.0 // Double ovens are typically 50"+ cutout
    }
}
