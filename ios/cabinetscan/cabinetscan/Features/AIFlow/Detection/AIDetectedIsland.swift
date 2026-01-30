//
//  AIDetectedIsland.swift
//  cabinetscan
//
//  Created for Story 4.5: Island and Peninsula Detection
//

import Foundation
import simd

// MARK: - Detected Island

/// A freestanding kitchen island detected in the scan.
///
/// **Definition:** An island is a counter surface that is walkable on all 4 sides,
/// with >18" clearance from all walls.
///
/// **Coordinate System:**
/// - All dimensions are in inches (calibrated via ScaleCalibrator)
/// - `position` is the center point in room coordinates (x, z)
/// - `rotation` is the angle relative to room orientation in degrees
///
/// **Quote Impact (CRITICAL):**
/// - Countertop area calculated from lengthInches × widthInches
/// - Seating overhang may require different material
/// - Cutouts for sink/cooktop affect installation complexity
///
/// **Usage:**
/// ```swift
/// let island = AIDetectedIsland(
///     id: UUID(),
///     position: SIMD2(120, 84),  // Center position
///     lengthInches: 60,           // 5 feet
///     widthInches: 36,            // 3 feet
///     heightInches: 36,           // Standard counter height
///     ...
/// )
/// ```
struct AIDetectedIsland: Identifiable, Equatable, Codable {
    /// Unique identifier for this island
    let id: UUID

    /// 3D bounding box of the island
    let boundingBox: AIBoundingBox3D

    /// Center position in room coordinates (x, z) in inches
    let position: SIMD2<Float>

    /// Length (longer horizontal dimension) in inches
    let lengthInches: Float

    /// Width (shorter horizontal dimension) in inches
    let widthInches: Float

    /// Height from floor to top surface in inches (typically 36" standard or 42" bar)
    let heightInches: Float

    /// Rotation angle relative to room orientation in degrees
    let rotation: Float

    /// Whether this island has seating overhang
    let hasSeating: Bool

    /// Depth of seating overhang in inches (nil if no seating)
    let seatingOverhangInches: Float?

    /// Length of seating area in inches (nil if no seating)
    let seatingLengthInches: Float?

    /// Appliances located on this island (sink, cooktop, dishwasher)
    let appliancesOnIsland: [AIIslandAppliance]

    /// Detection confidence level
    let confidence: AIConfidenceLevel

    /// Whether dimensions match standard island sizes
    let isStandardSize: Bool

    /// Raw measured dimensions before snapping (length, width, height)
    let rawDimensions: SIMD3<Float>

    /// Notes about the detection
    let notes: [String]

    // MARK: - Computed Properties

    /// Countertop area in square inches
    var countertopAreaSquareInches: Float {
        lengthInches * widthInches
    }

    /// Countertop area in square feet
    var countertopAreaSquareFeet: Float {
        countertopAreaSquareInches / 144.0
    }

    /// Perimeter (edge length) in inches for edge treatment pricing
    var perimeterInches: Float {
        2 * (lengthInches + widthInches)
    }

    /// Perimeter in linear feet
    var perimeterLinearFeet: Float {
        perimeterInches / 12.0
    }

    /// Whether this is a bar-height island (42" vs standard 36")
    var isBarHeight: Bool {
        heightInches >= 40.0
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        boundingBox: AIBoundingBox3D,
        position: SIMD2<Float>,
        lengthInches: Float,
        widthInches: Float,
        heightInches: Float,
        rotation: Float = 0,
        hasSeating: Bool = false,
        seatingOverhangInches: Float? = nil,
        seatingLengthInches: Float? = nil,
        appliancesOnIsland: [AIIslandAppliance] = [],
        confidence: AIConfidenceLevel = .medium,
        isStandardSize: Bool = false,
        rawDimensions: SIMD3<Float>? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.position = position
        self.lengthInches = lengthInches
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.rotation = rotation
        self.hasSeating = hasSeating
        self.seatingOverhangInches = seatingOverhangInches
        self.seatingLengthInches = seatingLengthInches
        self.appliancesOnIsland = appliancesOnIsland
        self.confidence = confidence
        self.isStandardSize = isStandardSize
        self.rawDimensions = rawDimensions ?? SIMD3(lengthInches, heightInches, widthInches)
        self.notes = notes
    }

    /// Default tolerance for bounds checking in inches (matches attached distance threshold)
    static let defaultContainsTolerance: Float = 6.0

    /// Checks if a point is within the island bounds (with tolerance).
    ///
    /// - Parameters:
    ///   - point: 2D point to check (x, z coordinates)
    ///   - tolerance: Distance tolerance in inches (defaults to 6" per StandardIslandSizes)
    /// - Returns: True if point is within island bounds
    func contains(point: SIMD2<Float>, tolerance: Float = AIDetectedIsland.defaultContainsTolerance) -> Bool {
        let halfLength = lengthInches / 2 + tolerance
        let halfWidth = widthInches / 2 + tolerance
        return abs(point.x - position.x) <= halfLength &&
               abs(point.y - position.y) <= halfWidth
    }
}

// MARK: - Detected Peninsula

/// A kitchen peninsula detected in the scan - attached to wall on one end.
///
/// **Definition:** A peninsula is a counter surface attached to a wall on ONE end,
/// with the other end extending into the room (walkable on 3 sides).
///
/// **Coordinate System:**
/// - All dimensions are in inches (calibrated via ScaleCalibrator)
/// - `attachedWallId` identifies which wall the peninsula is attached to
/// - `attachmentPointInches` is the distance along that wall from its start
/// - `lengthInches` is measured from wall to free end
///
/// **Quote Impact (CRITICAL):**
/// - Countertop area calculated from lengthInches × widthInches
/// - Edge treatment needed on 3 sides (not attached side)
/// - Seating overhang at end is common configuration
///
/// **Usage:**
/// ```swift
/// let peninsula = AIDetectedPeninsula(
///     id: UUID(),
///     attachedWallId: wall.id,
///     attachmentPointInches: 72,    // 6 feet from wall start
///     lengthInches: 48,             // 4 feet into room
///     widthInches: 24,              // 2 feet wide
///     ...
/// )
/// ```
struct AIDetectedPeninsula: Identifiable, Equatable, Codable {
    /// Unique identifier for this peninsula
    let id: UUID

    /// 3D bounding box of the peninsula
    let boundingBox: AIBoundingBox3D

    /// ID of the wall this peninsula is attached to
    let attachedWallId: UUID

    /// Position along the attached wall where peninsula connects (inches from wall start)
    let attachmentPointInches: Float

    /// Length extending from wall into room in inches
    let lengthInches: Float

    /// Width (perpendicular to length) in inches
    let widthInches: Float

    /// Height from floor to top surface in inches
    let heightInches: Float

    /// Direction peninsula extends from the wall
    let extendsDirection: AIPeninsulaDirection

    /// Whether this peninsula has seating overhang
    let hasSeating: Bool

    /// Depth of seating overhang in inches (nil if no seating)
    let seatingOverhangInches: Float?

    /// Which side of the peninsula has seating
    let seatingOnSide: AIPeninsulaSeatingSide?

    /// Appliances located on this peninsula (sink, cooktop, dishwasher)
    let appliancesOnPeninsula: [AIIslandAppliance]

    /// Detection confidence level
    let confidence: AIConfidenceLevel

    /// Whether dimensions match standard peninsula sizes
    let isStandardSize: Bool

    /// Raw measured dimensions before snapping (length, width, height)
    let rawDimensions: SIMD3<Float>

    /// Notes about the detection
    let notes: [String]

    // MARK: - Computed Properties

    /// Countertop area in square inches
    var countertopAreaSquareInches: Float {
        lengthInches * widthInches
    }

    /// Countertop area in square feet
    var countertopAreaSquareFeet: Float {
        countertopAreaSquareInches / 144.0
    }

    /// Exposed edge length in inches (3 sides - not attached side)
    /// For edge treatment pricing
    var exposedEdgeInches: Float {
        2 * lengthInches + widthInches
    }

    /// Exposed edge in linear feet
    var exposedEdgeLinearFeet: Float {
        exposedEdgeInches / 12.0
    }

    /// Whether this is a bar-height peninsula (42" vs standard 36")
    var isBarHeight: Bool {
        heightInches >= 40.0
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        boundingBox: AIBoundingBox3D,
        attachedWallId: UUID,
        attachmentPointInches: Float,
        lengthInches: Float,
        widthInches: Float,
        heightInches: Float,
        extendsDirection: AIPeninsulaDirection,
        hasSeating: Bool = false,
        seatingOverhangInches: Float? = nil,
        seatingOnSide: AIPeninsulaSeatingSide? = nil,
        appliancesOnPeninsula: [AIIslandAppliance] = [],
        confidence: AIConfidenceLevel = .medium,
        isStandardSize: Bool = false,
        rawDimensions: SIMD3<Float>? = nil,
        notes: [String] = []
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.attachedWallId = attachedWallId
        self.attachmentPointInches = attachmentPointInches
        self.lengthInches = lengthInches
        self.widthInches = widthInches
        self.heightInches = heightInches
        self.extendsDirection = extendsDirection
        self.hasSeating = hasSeating
        self.seatingOverhangInches = seatingOverhangInches
        self.seatingOnSide = seatingOnSide
        self.appliancesOnPeninsula = appliancesOnPeninsula
        self.confidence = confidence
        self.isStandardSize = isStandardSize
        self.rawDimensions = rawDimensions ?? SIMD3(lengthInches, heightInches, widthInches)
        self.notes = notes
    }

    /// Checks if a point is within the peninsula bounds (with tolerance).
    ///
    /// - Parameters:
    ///   - point: 2D point to check (x, z coordinates)
    ///   - tolerance: Distance tolerance in inches (defaults to 6" per StandardIslandSizes)
    /// - Returns: True if point is within peninsula bounds
    func contains(point: SIMD2<Float>, tolerance: Float = AIDetectedIsland.defaultContainsTolerance) -> Bool {
        let halfLength = lengthInches / 2 + tolerance
        let halfWidth = widthInches / 2 + tolerance
        // Use bounding box center for position
        let center = SIMD2(boundingBox.center.x, boundingBox.center.z)
        return abs(point.x - center.x) <= halfLength &&
               abs(point.y - center.y) <= halfWidth
    }
}

// MARK: - Peninsula Direction

/// Direction a peninsula extends from its attached wall.
enum AIPeninsulaDirection: String, Codable, CaseIterable {
    /// Extends left when facing the wall
    case left

    /// Extends right when facing the wall
    case right

    /// Extends perpendicular from wall into room (most common)
    case outward

    var displayText: String {
        switch self {
        case .left: return "Extends Left"
        case .right: return "Extends Right"
        case .outward: return "Extends Outward"
        }
    }
}

// MARK: - Peninsula Seating Side

/// Which side of a peninsula has seating overhang.
enum AIPeninsulaSeatingSide: String, Codable, CaseIterable {
    /// Seating on the left side (when viewing from wall)
    case left

    /// Seating on the right side (when viewing from wall)
    case right

    /// Seating at the end (away from wall) - most common
    case end

    var displayText: String {
        switch self {
        case .left: return "Left Side"
        case .right: return "Right Side"
        case .end: return "End"
        }
    }
}

// MARK: - Island Appliance

/// An appliance located on an island or peninsula.
///
/// This is a simplified representation for quote purposes,
/// linking back to the full AIDetectedAppliance.
struct AIIslandAppliance: Identifiable, Equatable, Codable {
    /// Unique identifier
    let id: UUID

    /// Type of appliance
    let type: AIIslandApplianceType

    /// Position relative to island/peninsula center in inches
    let positionOnSurface: SIMD2<Float>

    /// Width of the appliance/cutout in inches
    let widthInches: Float

    /// Depth of the appliance/cutout in inches
    let depthInches: Float

    /// Reference to the full appliance detection (if available)
    let applianceId: UUID?

    // MARK: - Computed Properties

    /// Cutout area in square inches
    var cutoutAreaSquareInches: Float {
        widthInches * depthInches
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        type: AIIslandApplianceType,
        positionOnSurface: SIMD2<Float>,
        widthInches: Float,
        depthInches: Float,
        applianceId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.positionOnSurface = positionOnSurface
        self.widthInches = widthInches
        self.depthInches = depthInches
        self.applianceId = applianceId
    }
}

// MARK: - Island Appliance Type

/// Types of appliances that can be on an island or peninsula.
enum AIIslandApplianceType: String, Codable, CaseIterable {
    /// Kitchen sink (requires cutout)
    case sink

    /// Cooktop (requires cutout)
    case cooktop

    /// Dishwasher (no countertop cutout, but affects base cabinet)
    case dishwasher

    /// No appliance (placeholder)
    case none

    var displayText: String {
        switch self {
        case .sink: return "Sink"
        case .cooktop: return "Cooktop"
        case .dishwasher: return "Dishwasher"
        case .none: return "None"
        }
    }

    /// Whether this appliance requires a countertop cutout
    var requiresCutout: Bool {
        switch self {
        case .sink, .cooktop: return true
        case .dishwasher, .none: return false
        }
    }
}

// MARK: - Island Countertop

/// Countertop details for an island, for quote purposes.
struct AIIslandCountertop: Equatable, Codable {
    /// Reference to the parent island
    let islandId: UUID

    /// Total length in inches
    let lengthInches: Float

    /// Total width in inches
    let widthInches: Float

    /// Height from floor in inches
    let heightFromFloorInches: Float

    /// Seating overhang depth if present
    let overhangInches: Float?

    /// Cutouts for sink, cooktop, etc.
    let cutouts: [AICountertopCutout]

    /// Detection confidence
    let confidence: AIConfidenceLevel

    // MARK: - Computed Properties

    /// Gross area before cutouts in square inches
    var grossAreaSquareInches: Float {
        lengthInches * widthInches
    }

    /// Total cutout area in square inches
    var cutoutAreaSquareInches: Float {
        cutouts.reduce(0) { $0 + $1.widthInches * $1.depthInches }
    }

    /// Net countertop area (gross - cutouts) in square inches
    var netAreaSquareInches: Float {
        grossAreaSquareInches - cutoutAreaSquareInches
    }

    /// Net area in square feet
    var netAreaSquareFeet: Float {
        netAreaSquareInches / 144.0
    }

    /// Total perimeter for edge treatment in inches
    var perimeterInches: Float {
        2 * (lengthInches + widthInches)
    }
}

// MARK: - Peninsula Countertop

/// Countertop details for a peninsula, for quote purposes.
struct AIPeninsulaCountertop: Equatable, Codable {
    /// Reference to the parent peninsula
    let peninsulaId: UUID

    /// Length from wall to end in inches
    let lengthInches: Float

    /// Width in inches
    let widthInches: Float

    /// Height from floor in inches
    let heightFromFloorInches: Float

    /// Seating overhang depth if present
    let overhangInches: Float?

    /// Cutouts for sink, cooktop, etc.
    let cutouts: [AICountertopCutout]

    /// Detection confidence
    let confidence: AIConfidenceLevel

    // MARK: - Computed Properties

    /// Gross area before cutouts in square inches
    var grossAreaSquareInches: Float {
        lengthInches * widthInches
    }

    /// Total cutout area in square inches
    var cutoutAreaSquareInches: Float {
        cutouts.reduce(0) { $0 + $1.widthInches * $1.depthInches }
    }

    /// Net countertop area (gross - cutouts) in square inches
    var netAreaSquareInches: Float {
        grossAreaSquareInches - cutoutAreaSquareInches
    }

    /// Net area in square feet
    var netAreaSquareFeet: Float {
        netAreaSquareInches / 144.0
    }

    /// Exposed edge (3 sides, not attached side) in inches
    var exposedEdgeInches: Float {
        2 * lengthInches + widthInches
    }
}

// MARK: - Countertop Cutout

/// A cutout in countertop for sink, cooktop, etc.
struct AICountertopCutout: Equatable, Codable {
    /// Type of cutout
    let type: AICutoutType

    /// Distance from countertop start in inches
    let positionFromStartInches: Float

    /// Distance from front edge in inches
    let positionFromFrontInches: Float

    /// Cutout width in inches
    let widthInches: Float

    /// Cutout depth in inches
    let depthInches: Float

    /// Area in square inches
    var areaSquareInches: Float {
        widthInches * depthInches
    }
}

// MARK: - Cutout Type

/// Type of countertop cutout.
enum AICutoutType: String, Codable, CaseIterable {
    case sink
    case cooktop
    case other

    var displayText: String {
        switch self {
        case .sink: return "Sink"
        case .cooktop: return "Cooktop"
        case .other: return "Other"
        }
    }
}
