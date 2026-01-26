//
//  AIFlowModels.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import simd

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
struct AIPose {
    /// 4x4 transformation matrix (column-major)
    let transform: simd_float4x4

    /// Camera intrinsics
    let intrinsics: AICameraIntrinsics

    /// Tracking quality at capture time
    let trackingState: AITrackingState
}

/// Camera intrinsic parameters
struct AICameraIntrinsics {
    let fx: Float  // Focal length X
    let fy: Float  // Focal length Y
    let cx: Float  // Principal point X
    let cy: Float  // Principal point Y
}

/// ARKit tracking state simplified for AI flow
enum AITrackingState {
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

/// 3D point cloud generated from depth frames
struct AIPointCloud {
    /// Array of 3D points
    var points: [SIMD3<Float>] = []

    /// Colors for each point (optional)
    var colors: [SIMD3<Float>]?

    /// Normals for each point (optional)
    var normals: [SIMD3<Float>]?

    /// Number of points in the cloud
    var count: Int { points.count }

    /// Whether the point cloud is empty
    var isEmpty: Bool { points.isEmpty }
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
    case manualDoor
    case manualCeiling
    case failed
}
