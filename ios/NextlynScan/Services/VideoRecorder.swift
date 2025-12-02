import Foundation
import AVFoundation
import CoreVideo
import UIKit

// MARK: - Video Recorder Delegate
protocol VideoRecorderDelegate: AnyObject {
    func videoRecorderDidStartRecording(_ recorder: VideoRecorder)
    func videoRecorderDidStopRecording(_ recorder: VideoRecorder, outputURL: URL?, error: Error?)
    func videoRecorderDidUpdateDuration(_ recorder: VideoRecorder, duration: TimeInterval)
}

// MARK: - Video Recorder
/// Records video from ARSession frames during RoomPlan scanning
class VideoRecorder {

    // MARK: - Properties
    weak var delegate: VideoRecorderDelegate?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var startTime: CMTime?
    private var frameCount: Int = 0
    private var lastFrameTime: CMTime?

    private let outputURL: URL
    private let videoSettings: VideoSettings

    private let processingQueue = DispatchQueue(label: "com.cabinetscan.videorecorder", qos: .userInitiated)

    // Track frame rate (target 30fps, drop frames if necessary)
    private let targetFrameRate: Double = 30.0
    private var lastRecordedFrameTime: TimeInterval = 0
    private var minFrameInterval: TimeInterval { 1.0 / targetFrameRate }

    // Duration tracking
    private var recordingStartDate: Date?
    private var durationTimer: Timer?

    // MARK: - Video Settings
    struct VideoSettings {
        let width: Int
        let height: Int
        let maxDurationSeconds: Int
        let maxSizeMB: Int

        static let defaultHD = VideoSettings(
            width: 1920,
            height: 1080,
            maxDurationSeconds: 300,
            maxSizeMB: 500
        )

        static let defaultSD = VideoSettings(
            width: 1280,
            height: 720,
            maxDurationSeconds: 300,
            maxSizeMB: 500
        )

        init(width: Int, height: Int, maxDurationSeconds: Int, maxSizeMB: Int) {
            self.width = width
            self.height = height
            self.maxDurationSeconds = maxDurationSeconds
            self.maxSizeMB = maxSizeMB
        }

        init(from captureSettings: VideoCaptureSettings?) {
            // Use HD settings for PRO, SD for lower tiers
            let useHD = captureSettings?.maxSizeMb ?? 0 >= 500

            self.width = useHD ? 1920 : 1280
            self.height = useHD ? 1080 : 720
            self.maxDurationSeconds = captureSettings?.maxDurationSeconds ?? 300
            self.maxSizeMB = captureSettings?.maxSizeMb ?? 500
        }
    }

    // MARK: - Initialization

    init(settings: VideoSettings = .defaultHD) {
        self.videoSettings = settings

        // Create temp file URL for video
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomId = UUID().uuidString.prefix(8)
        self.outputURL = tempDir.appendingPathComponent("scan_video_\(timestamp)_\(randomId).mp4")
    }

    convenience init(captureSettings: VideoCaptureSettings?) {
        let settings = VideoSettings(from: captureSettings)
        self.init(settings: settings)
    }

    // MARK: - Public Methods

    /// Prepare the recorder for recording
    func prepare() throws {
        // Remove any existing file at the output URL
        try? FileManager.default.removeItem(at: outputURL)

        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video settings for H.264 encoding
        let videoOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoSettings.width,
            AVVideoHeightKey: videoSettings.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000, // 8 Mbps for good quality
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        videoInput?.expectsMediaDataInRealTime = true

        // Pixel buffer adaptor for efficient frame writing
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoSettings.width,
            kCVPixelBufferHeightKey as String: videoSettings.height
        ]

        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if assetWriter!.canAdd(videoInput!) {
            assetWriter!.add(videoInput!)
        } else {
            throw VideoRecorderError.cannotAddInput
        }

        print("[VideoRecorder] Prepared for recording at \(videoSettings.width)x\(videoSettings.height)")
    }

    /// Start recording
    func startRecording() throws {
        guard let assetWriter = assetWriter else {
            throw VideoRecorderError.notPrepared
        }

        guard assetWriter.status == .unknown else {
            throw VideoRecorderError.invalidState
        }

        assetWriter.startWriting()
        isRecording = true
        frameCount = 0
        startTime = nil
        lastRecordedFrameTime = 0
        recordingStartDate = Date()

        // Start duration tracking timer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, let startDate = self.recordingStartDate else { return }
                let duration = Date().timeIntervalSince(startDate)
                self.delegate?.videoRecorderDidUpdateDuration(self, duration: duration)

                // Check if max duration exceeded
                if Int(duration) >= self.videoSettings.maxDurationSeconds {
                    self.stopRecording()
                }
            }
        }

        delegate?.videoRecorderDidStartRecording(self)
        print("[VideoRecorder] Started recording")
    }

    /// Append a pixel buffer (ARFrame.capturedImage) to the video
    func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        guard isRecording,
              let videoInput = videoInput,
              let adaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData else {
            return
        }

        // Frame rate limiting - only record at target frame rate
        let currentTime = timestamp
        if currentTime - lastRecordedFrameTime < minFrameInterval {
            return
        }
        lastRecordedFrameTime = currentTime

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Start the session on first frame
            if self.startTime == nil {
                let time = CMTime(seconds: timestamp, preferredTimescale: 600)
                self.assetWriter?.startSession(atSourceTime: time)
                self.startTime = time
            }

            // Calculate presentation time relative to start
            let presentationTime = CMTime(seconds: timestamp, preferredTimescale: 600)

            // Resize pixel buffer if needed
            if let resizedBuffer = self.resizePixelBuffer(pixelBuffer) {
                if adaptor.append(resizedBuffer, withPresentationTime: presentationTime) {
                    self.frameCount += 1
                    self.lastFrameTime = presentationTime
                }
            }
        }
    }

    /// Stop recording and finalize the video file
    func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        // Stop duration timer
        DispatchQueue.main.async { [weak self] in
            self?.durationTimer?.invalidate()
            self?.durationTimer = nil
        }

        processingQueue.async { [weak self] in
            guard let self = self,
                  let assetWriter = self.assetWriter else {
                return
            }

            self.videoInput?.markAsFinished()

            assetWriter.finishWriting { [weak self] in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if assetWriter.status == .completed {
                        print("[VideoRecorder] Recording completed: \(self.frameCount) frames")
                        self.delegate?.videoRecorderDidStopRecording(self, outputURL: self.outputURL, error: nil)
                    } else {
                        let error = assetWriter.error ?? VideoRecorderError.writingFailed
                        print("[VideoRecorder] Recording failed: \(error.localizedDescription)")
                        self.delegate?.videoRecorderDidStopRecording(self, outputURL: nil, error: error)
                    }
                }
            }
        }
    }

    /// Cancel recording and cleanup
    func cancelRecording() {
        isRecording = false

        DispatchQueue.main.async { [weak self] in
            self?.durationTimer?.invalidate()
            self?.durationTimer = nil
        }

        assetWriter?.cancelWriting()
        cleanup()
    }

    /// Get the current recording duration
    var currentDuration: TimeInterval {
        guard let startDate = recordingStartDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }

    /// Check if currently recording
    var isCurrentlyRecording: Bool {
        return isRecording
    }

    // MARK: - Private Methods

    private func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        // If already correct size, return original
        if sourceWidth == videoSettings.width && sourceHeight == videoSettings.height {
            return pixelBuffer
        }

        // Create a new pixel buffer with target size
        var newPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            videoSettings.width,
            videoSettings.height,
            kCVPixelFormatType_32BGRA,
            nil,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = newPixelBuffer else {
            return nil
        }

        // Use Core Image for efficient resizing
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = CGFloat(videoSettings.width) / CGFloat(sourceWidth)
        let scaleY = CGFloat(videoSettings.height) / CGFloat(sourceHeight)
        let scale = min(scaleX, scaleY)

        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center the scaled image
        let offsetX = (CGFloat(videoSettings.width) - scaledImage.extent.width) / 2
        let offsetY = (CGFloat(videoSettings.height) - scaledImage.extent.height) / 2
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        let context = CIContext()
        context.render(centeredImage, to: outputBuffer)

        return outputBuffer
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: outputURL)
    }

    // MARK: - Video Metadata

    /// Get video file metadata after recording completes
    func getVideoMetadata() -> VideoMetadata? {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            let asset = AVAsset(url: outputURL)
            let duration = CMTimeGetSeconds(asset.duration)

            // Get video track info
            var resolution = "\(videoSettings.width)x\(videoSettings.height)"
            if let videoTrack = asset.tracks(withMediaType: .video).first {
                let size = videoTrack.naturalSize
                resolution = "\(Int(size.width))x\(Int(size.height))"
            }

            return VideoMetadata(
                url: outputURL,
                durationSeconds: Int(duration),
                sizeBytes: fileSize,
                resolution: resolution,
                format: "mp4"
            )
        } catch {
            print("[VideoRecorder] Error getting metadata: \(error)")
            return nil
        }
    }

    /// Extract thumbnail from video at specified time
    func extractThumbnail(at time: TimeInterval = 0) async -> UIImage? {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        let asset = AVAsset(url: outputURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 640, height: 360)

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: cmTime, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("[VideoRecorder] Error extracting thumbnail: \(error)")
            return nil
        }
    }
}

// MARK: - Video Metadata
struct VideoMetadata {
    let url: URL
    let durationSeconds: Int
    let sizeBytes: Int64
    let resolution: String
    let format: String

    var sizeMB: Double {
        return Double(sizeBytes) / (1024 * 1024)
    }
}

// MARK: - Errors
enum VideoRecorderError: LocalizedError {
    case notPrepared
    case cannotAddInput
    case invalidState
    case writingFailed
    case maxDurationExceeded

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Video recorder is not prepared"
        case .cannotAddInput:
            return "Cannot add video input to asset writer"
        case .invalidState:
            return "Video recorder is in invalid state"
        case .writingFailed:
            return "Failed to write video file"
        case .maxDurationExceeded:
            return "Maximum video duration exceeded"
        }
    }
}
