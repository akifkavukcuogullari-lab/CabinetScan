//
//  ServerResultAdapter.swift
//  cabinetscan
//
//  Phase 2.2: Convert server pipeline results to MeasurementData.
//  Server Pipeline V2
//

import Foundation

// MARK: - Upload Context

/// Context from the upload phase needed to populate MeasurementData fields.
struct UploadContext {
    let videoUrl: String
    let videoThumbnailUrl: String?
    let videoDurationSeconds: Int
    let videoSizeBytes: Int64
    let videoResolution: String
    let photoUrls: [String]
}

// MARK: - Server Result Adapter

/// Converts `ServerPipelineResult` into `MeasurementData` compatible with the existing
/// LiDAR flow format, ensuring the dashboard and submit-project edge function work unchanged.
///
/// Key contract:
/// - All measurement values are in **FEET** (not inches)
/// - `scanMethod` is always `.aiFlow`
/// - `aiMetadata` is populated from server response
/// - `roomplanData` is an empty dictionary (no RoomPlan used)
struct ServerResultAdapter {

    /// Convert server pipeline result to MeasurementData.
    ///
    /// - Parameters:
    ///   - result: Server pipeline processing result
    ///   - uploadContext: Upload URLs and video metadata
    /// - Returns: MeasurementData ready for AppState.setMeasurementData()
    func convert(
        result: ServerPipelineResult,
        uploadContext: UploadContext
    ) -> MeasurementData {
        let data = result.measurementsData

        // Extract room-level measurements (values in FEET from server)
        let roomName = data["room_name"] as? String ?? "Kitchen"
        let roomType = data["room_type"] as? String ?? "kitchen"
        let totalLinearFt = data["total_linear_ft"] as? Double
        let totalSqFt = data["total_sq_ft"] as? Double
        let wallCount = data["wall_count"] as? Int
        let windowCount = data["window_count"] as? Int
        let doorCount = data["door_count"] as? Int

        // Extract detailed measurements dictionary
        let measurements: [String: AnyCodable]?
        if let rawMeasurements = data["measurements"] as? [String: Any] {
            measurements = rawMeasurements.mapValues { AnyCodable($0) }
        } else {
            measurements = nil
        }

        // Build AI metadata from server response
        let aiMetadata = buildAIMetadata(from: result, data: data)

        return MeasurementData(
            roomName: roomName,
            roomType: roomType,
            roomplanData: [:],  // No RoomPlan data in AI flow
            totalLinearFt: totalLinearFt,
            totalSqFt: totalSqFt,
            wallCount: wallCount,
            windowCount: windowCount,
            doorCount: doorCount,
            measurements: measurements,
            usdzFileUrl: nil,  // No USDZ in AI flow
            glbFileUrl: nil,
            previewImageUrl: result.floorPlanURL,
            videoUrl: uploadContext.videoUrl,
            videoThumbnailUrl: uploadContext.videoThumbnailUrl,
            videoDurationSeconds: uploadContext.videoDurationSeconds,
            videoSizeBytes: uploadContext.videoSizeBytes,
            videoResolution: uploadContext.videoResolution,
            videoFormat: "mp4",
            visualizationPhotoUrls: uploadContext.photoUrls,
            scanMethod: .aiFlow,
            aiMetadata: aiMetadata
        )
    }

    // MARK: - Helpers

    private func buildAIMetadata(
        from result: ServerPipelineResult,
        data: [String: Any]
    ) -> AIMetadata {
        // Extract model versions from server response
        let modelVersions: [String: String]
        if let versions = data["model_versions"] as? [String: String] {
            modelVersions = versions
        } else {
            modelVersions = [
                "depth": "video_depth_anything_v2",
                "segmentation": "sam3",
                "pipeline": result.pipelineVersion ?? "v2"
            ]
        }

        // Map scale confidence to numeric value
        let confidenceValue: Double
        switch result.scaleConfidence?.lowercased() {
        case "high":
            confidenceValue = 0.9
        case "medium":
            confidenceValue = 0.7
        case "low":
            confidenceValue = 0.5
        default:
            confidenceValue = 0.7
        }

        return AIMetadata(
            calibrationMethod: data["calibration_method"] as? String ?? "multi_reference",
            calibrationConfidence: confidenceValue,
            overallConfidence: data["overall_confidence"] as? Double ?? confidenceValue,
            processingTimeMs: result.processingTimeMs,
            modelVersions: modelVersions,
            needsVerification: !result.validationPassed,
            frameCount: data["frame_count"] as? Int ?? 0,
            photoCount: data["photo_count"] as? Int ?? 0,
            scaleFactor: data["scale_factor"] as? Double ?? 1.0,
            coveragePercentage: data["coverage_percentage"] as? Double ?? 0,
            warnings: result.validationIssues.isEmpty ? nil : result.validationIssues
        )
    }
}
