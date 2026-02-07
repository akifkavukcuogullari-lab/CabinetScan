//
//  CapturePackageBuilder.swift
//  cabinetscan
//
//  Phase 1.2: Bundle capture data for server pipeline.
//  Server Pipeline V2
//

import Foundation
import ARKit
import UIKit

// MARK: - Capture Package

/// Bundle of all data needed by the server processing pipeline.
/// Built after photo capture completes, before upload begins.
struct CapturePackage {
    /// Local URL to the captured video file (MP4)
    let videoURL: URL

    /// JSON-serialized camera poses from ARKit (60Hz)
    let posesData: Data

    /// JSON-serialized ARKit plane anchors (horizontal + vertical)
    let planesData: Data

    /// Capture metadata for server context
    let metadata: CapturePackageMetadata

    /// Captured photos with their URLs (for upload)
    let photos: [AICapturedPhoto]
}

// MARK: - Capture Package Metadata

/// Metadata about the capture session, sent to server alongside video/poses/planes.
struct CapturePackageMetadata: Codable {
    let deviceModel: String
    let osVersion: String
    let captureDate: Date
    let videoDuration: TimeInterval
    let frameCount: Int
    let photoCount: Int
    let showroomId: String
    let hasLiDAR: Bool
    let planeCount: Int

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case captureDate = "capture_date"
        case videoDuration = "video_duration"
        case frameCount = "frame_count"
        case photoCount = "photo_count"
        case showroomId = "showroom_id"
        case hasLiDAR = "has_lidar"
        case planeCount = "plane_count"
    }
}

// MARK: - Capture Package Builder

/// Builds a `CapturePackage` from the current session state.
///
/// Usage:
/// ```swift
/// let builder = CapturePackageBuilder(sessionManager: arSessionManager)
/// let package = builder.build(
///     videoURL: videoURL,
///     sessionData: captureSessionData,
///     showroomId: "showroom-uuid"
/// )
/// ```
final class CapturePackageBuilder {

    private let sessionManager: AIARSessionManager

    init(sessionManager: AIARSessionManager) {
        self.sessionManager = sessionManager
    }

    /// Build a capture package from the current session data.
    ///
    /// - Parameters:
    ///   - videoURL: Local URL to the recorded video file
    ///   - sessionData: Accumulated capture session data (video + photos + metadata)
    ///   - showroomId: Showroom identifier for server context
    /// - Returns: A `CapturePackage` ready for upload
    func build(
        videoURL: URL,
        sessionData: AICaptureSessionData,
        showroomId: String
    ) -> CapturePackage {
        // Export poses as JSON
        let poseDict = sessionManager.exportPoseData()
        let posesData = (try? JSONSerialization.data(withJSONObject: poseDict, options: [])) ?? Data("{}".utf8)

        // Export planes as JSON
        let planesData = sessionManager.exportPlanesJSON()

        // Build metadata
        let metadata = CapturePackageMetadata(
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            captureDate: sessionData.metadata?.captureDate ?? Date(),
            videoDuration: sessionData.metadata?.videoDuration ?? 0,
            frameCount: (poseDict["poseCount"] as? Int) ?? 0,
            photoCount: sessionData.photos.count,
            showroomId: showroomId,
            hasLiDAR: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            planeCount: sessionManager.getDetectedPlaneCount()
        )

        return CapturePackage(
            videoURL: videoURL,
            posesData: posesData,
            planesData: planesData,
            metadata: metadata,
            photos: sessionData.photos
        )
    }
}
