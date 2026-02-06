//
//  AIFlowUploader.swift
//  cabinetscan
//
//  Created for AI Flow Pipeline Fix - Phase 2
//  Uploads AI flow video and photos to Supabase storage
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Uploaded Video Data

/// Contains metadata and URLs for an uploaded video
struct AIUploadedVideoData {
    let videoUrl: String
    let thumbnailUrl: String?
    let durationSeconds: Int
    let sizeBytes: Int64
    let resolution: String
}

// MARK: - Upload Error

enum AIFlowUploadError: LocalizedError {
    case videoFileNotFound
    case videoUploadFailed(String)
    case photoUploadFailed(String)
    case thumbnailExtractionFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .videoFileNotFound:
            return "Video file not found"
        case .videoUploadFailed(let reason):
            return "Failed to upload video: \(reason)"
        case .photoUploadFailed(let reason):
            return "Failed to upload photo: \(reason)"
        case .thumbnailExtractionFailed:
            return "Failed to extract video thumbnail"
        case .compressionFailed:
            return "Failed to compress video"
        }
    }
}

// MARK: - AI Flow Uploader

/// Handles uploading AI flow capture data (video and photos) to Supabase storage.
///
/// This class bridges the gap between local capture files and cloud storage,
/// ensuring the dashboard can display AI flow media just like LiDAR flow media.
///
/// **Usage:**
/// ```swift
/// let uploader = AIFlowUploader()
/// let videoData = try await uploader.uploadVideo(from: localVideoURL, showroomCode: "DEMO")
/// let photoURLs = try await uploader.uploadPhotos(capturedPhotos, showroomCode: "DEMO")
/// ```
final class AIFlowUploader {

    // MARK: - Constants

    private enum Constants {
        /// Maximum video size before compression (20MB)
        static let maxVideoSizeBeforeCompression: Int64 = 20_000_000
        /// JPEG compression quality for photos
        static let photoCompressionQuality: CGFloat = 0.5
        /// JPEG compression quality for thumbnails
        static let thumbnailCompressionQuality: CGFloat = 0.5
        /// Maximum photo dimension (resize if larger)
        static let maxPhotoDimension: CGFloat = 1920
        /// Time in video to extract thumbnail (1 second)
        static let thumbnailTimeSeconds: Double = 1.0
        /// Storage bucket name
        static let storageBucket = "scans"
    }

    // MARK: - Progress Tracking

    /// Callback for upload progress updates
    var onProgressUpdate: ((String) -> Void)?

    // MARK: - Initialization

    init() {}

    // MARK: - Video Upload

    /// Uploads a video file to Supabase storage.
    ///
    /// This method:
    /// 1. Validates the video file exists
    /// 2. Extracts video metadata (duration, resolution)
    /// 3. Compresses if > 20MB
    /// 4. Uploads to Supabase storage
    /// 5. Extracts and uploads thumbnail
    /// 6. Cleans up temporary files
    ///
    /// - Parameters:
    ///   - localURL: Local file URL of the video
    ///   - showroomCode: Showroom code for storage path
    /// - Returns: Uploaded video data with Supabase URL
    /// - Throws: AIFlowUploadError if upload fails
    func uploadVideo(from localURL: URL, showroomCode: String) async throws -> AIUploadedVideoData {
        print("[AIFlowUploader] Starting video upload from: \(localURL.lastPathComponent)")
        onProgressUpdate?("Preparing video...")

        // 1. Validate file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw AIFlowUploadError.videoFileNotFound
        }

        // 2. Get video metadata
        let metadata = try await getVideoMetadata(from: localURL)
        print("[AIFlowUploader] Video metadata: duration=\(metadata.durationSeconds)s, size=\(metadata.sizeMB)MB, resolution=\(metadata.resolution)")

        // 3. Compress if needed
        var videoToUpload = localURL
        var compressedURL: URL?

        if metadata.sizeBytes > Constants.maxVideoSizeBeforeCompression {
            onProgressUpdate?("Compressing video...")
            print("[AIFlowUploader] Video exceeds 20MB, compressing...")

            if let compressed = try? await compressVideo(at: localURL) {
                compressedURL = compressed
                videoToUpload = compressed
                let compressedSize = (try? FileManager.default.attributesOfItem(atPath: compressed.path)[.size] as? Int64) ?? 0
                print("[AIFlowUploader] Compressed to: \(Double(compressedSize) / 1_000_000)MB")
            } else {
                print("[AIFlowUploader] Compression failed, using original")
            }
        }

        // 4. Upload video
        onProgressUpdate?("Uploading video...")
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        let videoFilename = "ai_video_\(timestamp)_\(randomId).mp4"
        let videoPath = "\(showroomCode.lowercased())/\(videoFilename)"

        let uploadedVideoUrl: String
        do {
            let videoData = try Data(contentsOf: videoToUpload)
            let finalSizeMB = Double(videoData.count) / (1024 * 1024)
            print("[AIFlowUploader] Uploading video: \(String(format: "%.2f", finalSizeMB))MB")

            uploadedVideoUrl = try await APIService.shared.uploadFile(
                bucket: Constants.storageBucket,
                path: videoPath,
                data: videoData,
                contentType: "video/mp4"
            )
            print("[AIFlowUploader] Video uploaded: \(uploadedVideoUrl)")
        } catch {
            // Clean up compressed file
            if let compressed = compressedURL {
                try? FileManager.default.removeItem(at: compressed)
            }
            throw AIFlowUploadError.videoUploadFailed(error.localizedDescription)
        }

        // 5. Extract and upload thumbnail
        onProgressUpdate?("Creating thumbnail...")
        var thumbnailUrl: String?

        if let thumbnail = await extractThumbnail(from: localURL, atTime: Constants.thumbnailTimeSeconds) {
            if let thumbnailData = thumbnail.jpegData(compressionQuality: Constants.thumbnailCompressionQuality) {
                let thumbnailFilename = "ai_video_thumb_\(timestamp)_\(randomId).jpg"
                let thumbnailPath = "\(showroomCode.lowercased())/\(thumbnailFilename)"

                do {
                    thumbnailUrl = try await APIService.shared.uploadFile(
                        bucket: Constants.storageBucket,
                        path: thumbnailPath,
                        data: thumbnailData,
                        contentType: "image/jpeg"
                    )
                    print("[AIFlowUploader] Thumbnail uploaded: \(thumbnailUrl ?? "nil")")
                } catch {
                    print("[AIFlowUploader] Thumbnail upload failed: \(error.localizedDescription)")
                    // Non-fatal - continue without thumbnail
                }
            }
        }

        // 6. Get final uploaded size
        let uploadedSizeBytes: Int64
        if let compressed = compressedURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: compressed.path),
           let size = attrs[.size] as? Int64 {
            uploadedSizeBytes = size
        } else {
            uploadedSizeBytes = metadata.sizeBytes
        }

        // 7. Clean up compressed file (keep original for potential retry)
        if let compressed = compressedURL {
            try? FileManager.default.removeItem(at: compressed)
        }

        onProgressUpdate?("Video upload complete")

        return AIUploadedVideoData(
            videoUrl: uploadedVideoUrl,
            thumbnailUrl: thumbnailUrl,
            durationSeconds: metadata.durationSeconds,
            sizeBytes: uploadedSizeBytes,
            resolution: metadata.resolution
        )
    }

    // MARK: - Photo Upload

    /// Uploads photos to Supabase storage.
    ///
    /// Photos are compressed and resized before upload for optimal storage.
    ///
    /// - Parameters:
    ///   - photos: Array of captured photos with local URLs
    ///   - showroomCode: Showroom code for storage path
    /// - Returns: Array of Supabase URLs for uploaded photos
    /// - Throws: AIFlowUploadError if all uploads fail
    func uploadPhotos(_ photos: [AICapturedPhoto], showroomCode: String) async throws -> [String] {
        guard !photos.isEmpty else {
            print("[AIFlowUploader] No photos to upload")
            return []
        }

        print("[AIFlowUploader] Starting upload of \(photos.count) photos")
        var uploadedUrls: [String] = []
        var lastError: Error?

        for (index, photo) in photos.enumerated() {
            onProgressUpdate?("Uploading photo \(index + 1) of \(photos.count)...")

            do {
                // Load and compress photo
                let imageData: Data
                if let image = UIImage(contentsOfFile: photo.url.path) {
                    // Resize if needed
                    let resizedImage = resizeImageIfNeeded(image, maxDimension: Constants.maxPhotoDimension)
                    // Compress
                    guard let compressed = resizedImage.jpegData(compressionQuality: Constants.photoCompressionQuality) else {
                        print("[AIFlowUploader] Failed to compress photo \(index + 1)")
                        continue
                    }
                    imageData = compressed
                } else {
                    // Fallback to raw file data
                    imageData = try Data(contentsOf: photo.url)
                }

                let timestamp = Int(Date().timeIntervalSince1970)
                let randomId = UUID().uuidString.prefix(8)
                let filename = "ai_photo_\(timestamp)_\(randomId)_\(index + 1).jpg"
                let storagePath = "\(showroomCode.lowercased())/\(filename)"

                print("[AIFlowUploader] Uploading photo \(index + 1)/\(photos.count) - size: \(imageData.count / 1024)KB")

                let uploadedUrl = try await APIService.shared.uploadFile(
                    bucket: Constants.storageBucket,
                    path: storagePath,
                    data: imageData,
                    contentType: "image/jpeg"
                )

                print("[AIFlowUploader] Photo \(index + 1) uploaded: \(uploadedUrl)")
                uploadedUrls.append(uploadedUrl)
            } catch {
                print("[AIFlowUploader] Failed to upload photo \(index + 1): \(error.localizedDescription)")
                lastError = error
                // Continue with other photos
            }
        }

        print("[AIFlowUploader] Completed: \(uploadedUrls.count)/\(photos.count) photos uploaded")

        // If no photos uploaded at all, throw error
        if uploadedUrls.isEmpty && !photos.isEmpty {
            throw AIFlowUploadError.photoUploadFailed(lastError?.localizedDescription ?? "All uploads failed")
        }

        onProgressUpdate?("Photos uploaded")
        return uploadedUrls
    }

    // MARK: - Video Metadata

    private struct VideoMetadata {
        let durationSeconds: Int
        let sizeBytes: Int64
        let sizeMB: Double
        let resolution: String
    }

    private func getVideoMetadata(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        // Get duration
        let duration = try await asset.load(.duration)
        let durationSeconds = Int(CMTimeGetSeconds(duration))

        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let sizeBytes = attrs[.size] as? Int64 ?? 0
        let sizeMB = Double(sizeBytes) / (1024 * 1024)

        // Get resolution
        var resolution = "unknown"
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let videoSize = size.applying(transform)
            let width = Int(abs(videoSize.width))
            let height = Int(abs(videoSize.height))
            resolution = "\(width)x\(height)"
        }

        return VideoMetadata(
            durationSeconds: durationSeconds,
            sizeBytes: sizeBytes,
            sizeMB: sizeMB,
            resolution: resolution
        )
    }

    // MARK: - Video Compression

    private func compressVideo(at url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)

        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString.prefix(8)).mp4")

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw AIFlowUploadError.compressionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Export
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw AIFlowUploadError.compressionFailed
        case .cancelled:
            throw AIFlowUploadError.compressionFailed
        default:
            throw AIFlowUploadError.compressionFailed
        }
    }

    // MARK: - Thumbnail Extraction

    private func extractThumbnail(from videoURL: URL, atTime time: Double) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 480, height: 854) // Thumbnail size

        let time = CMTime(seconds: time, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("[AIFlowUploader] Thumbnail extraction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Image Resizing

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Check if resizing is needed
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        // Calculate new size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        // Render resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
