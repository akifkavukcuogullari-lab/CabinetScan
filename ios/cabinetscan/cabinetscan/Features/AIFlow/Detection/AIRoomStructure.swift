//
//  AIRoomStructure.swift
//  cabinetscan
//
//  Created for Story 4.1: Room Structure Detection
//

import Foundation
import simd

// MARK: - Room Structure Output

/// Complete room structure detected from the calibrated 3D model.
///
/// **Usage:**
/// This is the output of `RoomDetector.detect(from:)` and contains all
/// room geometry needed for cabinet detection in subsequent stories.
///
/// **Coordinate System:**
/// - Floor is at Y = 0 (after geometric constraints)
/// - Dimensions are in inches (calibrated via ScaleCalibrator)
/// - X-Z plane is horizontal (top-down view)
struct AIRoomStructure {
    /// The detected floor plane (Y = 0 after alignment)
    let floorPlane: RoomPlane3D

    /// Ceiling height in inches above floor
    let ceilingHeightInches: Double

    /// All detected walls in the room
    let walls: [AIWall]

    /// Room boundary polygon in 2D (X, Z coordinates in inches)
    /// Points are ordered counter-clockwise when viewed from above
    let boundaryPolygon: [SIMD2<Float>]

    /// Classified room shape
    let roomShape: RoomShape

    /// Room dimension measurements
    let dimensions: RoomDimensions

    /// Open boundaries (no wall - open to adjacent room)
    let openBoundaries: [OpenBoundary]

    /// Overall detection confidence
    let confidence: DetectionConfidence

    /// Processing time in milliseconds
    let processingTimeMs: Int

    /// Warnings generated during detection (e.g., ceiling height clamped)
    /// Empty array means no warnings
    let warnings: [String]
}

// MARK: - Wall Structure

/// A single wall detected in the room.
///
/// Walls are vertical planes projected to 2D (X-Z plane) for boundary polygon.
struct AIWall {
    /// Unique identifier for this wall
    let id: UUID

    /// The 3D plane equation for this wall
    let plane: RoomPlane3D

    /// Start point in 2D (X, Z) in inches
    let startPoint: SIMD2<Float>

    /// End point in 2D (X, Z) in inches
    let endPoint: SIMD2<Float>

    /// Wall length in inches
    let lengthInches: Double

    /// Wall height in inches (floor to ceiling)
    let heightInches: Double

    /// Outward-facing normal direction in 2D (X, Z)
    let normalDirection: SIMD2<Float>

    /// Boundary type (wall or open)
    let boundaryType: BoundaryType
}

// MARK: - Room Dimensions

/// Aggregate room dimension measurements.
///
/// For non-rectangular rooms (L-shape, U-shape), width and length
/// represent the bounding box dimensions.
struct RoomDimensions {
    /// Room width in inches (bounding box X extent)
    let widthInches: Double

    /// Room length in inches (bounding box Z extent)
    let lengthInches: Double

    /// Ceiling height in inches
    let ceilingHeightInches: Double

    /// Total floor area in square inches
    let areaSquareInches: Double

    /// Total perimeter in inches (sum of all wall lengths)
    let perimeterInches: Double

    /// Width in feet (computed)
    var widthFeet: Double { widthInches / 12.0 }

    /// Length in feet (computed)
    var lengthFeet: Double { lengthInches / 12.0 }

    /// Area in square feet (computed)
    var areaSquareFeet: Double { areaSquareInches / 144.0 }

    /// Perimeter in feet (computed)
    var perimeterFeet: Double { perimeterInches / 12.0 }
}

// MARK: - Room Shape Classification

/// Classification of room shape based on boundary polygon.
enum RoomShape: String, Codable {
    /// Standard rectangular room (4 walls, 90-degree corners)
    case rectangle

    /// L-shaped room (6 walls, one interior corner)
    case lShape

    /// U-shaped room (8 walls, two interior corners)
    case uShape

    /// Galley (narrow corridor-like kitchen)
    case galley

    /// Open-concept (has open boundaries to adjacent spaces)
    case open

    /// Non-standard shape
    case irregular

    /// Human-readable description
    var displayText: String {
        switch self {
        case .rectangle: return "Rectangular"
        case .lShape: return "L-Shaped"
        case .uShape: return "U-Shaped"
        case .galley: return "Galley"
        case .open: return "Open Concept"
        case .irregular: return "Custom Shape"
        }
    }
}

// MARK: - Boundary Type

/// Type of room boundary segment.
enum BoundaryType: String, Codable {
    /// Physical wall boundary
    case wall

    /// Open boundary (open to adjacent room, no wall)
    case open
}

// MARK: - Open Boundary

/// An open boundary segment where the kitchen opens to another room.
struct OpenBoundary {
    /// Start point in 2D (X, Z) in inches
    let startPoint: SIMD2<Float>

    /// End point in 2D (X, Z) in inches
    let endPoint: SIMD2<Float>

    /// Width of the opening in inches
    let widthInches: Double
}

// MARK: - 3D Plane

/// A 3D plane defined by normal vector and distance from origin.
///
/// Plane equation: `ax + by + cz + d = 0`
/// where `(a, b, c)` is the normal and `d` is the distance.
struct RoomPlane3D {
    /// Normal vector (a, b, c) in plane equation
    let normal: SIMD3<Float>

    /// Distance from origin (d in plane equation)
    let distance: Float

    /// Centroid of points used to fit this plane
    let center: SIMD3<Float>

    /// Calculates signed distance from a point to this plane.
    /// Positive = point is on the same side as normal.
    func signedDistance(to point: SIMD3<Float>) -> Float {
        return simd_dot(normal, point) + distance
    }

    /// Calculates absolute distance from a point to this plane.
    func absoluteDistance(to point: SIMD3<Float>) -> Float {
        return abs(signedDistance(to: point))
    }
}

// MARK: - Detection Confidence

/// Confidence level for room detection results.
struct DetectionConfidence {
    /// Floor detection confidence (0.0 to 1.0)
    let floorConfidence: Float

    /// Wall detection confidence (0.0 to 1.0)
    let wallConfidence: Float

    /// Boundary polygon confidence (0.0 to 1.0)
    let boundaryConfidence: Float

    /// Overall confidence (average of components)
    var overall: Float {
        (floorConfidence + wallConfidence + boundaryConfidence) / 3.0
    }

    /// Confidence level category
    var level: AIConfidenceLevel {
        if overall >= 0.8 {
            return .high
        } else if overall >= 0.6 {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Room Detection Error

/// Errors that can occur during room detection.
enum RoomDetectionError: LocalizedError, Equatable {
    case emptyPointCloud
    case floorDetectionFailed
    case insufficientWalls
    case boundaryExtractionFailed
    case dimensionCalculationFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptyPointCloud:
            return "Point cloud is empty - cannot detect room structure"
        case .floorDetectionFailed:
            return "Failed to detect floor plane in the point cloud"
        case .insufficientWalls:
            return "Detected fewer than 3 walls - room boundary incomplete"
        case .boundaryExtractionFailed:
            return "Failed to extract room boundary polygon"
        case .dimensionCalculationFailed:
            return "Failed to calculate room dimensions"
        case .cancelled:
            return "Room detection was cancelled"
        }
    }
}
