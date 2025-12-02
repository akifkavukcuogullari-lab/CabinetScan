import Foundation
import AVFoundation
import UIKit
import CoreMedia

public protocol VideoRecorderDelegate: AnyObject {
    func videoRecorderDidStartRecording(_ recorder: VideoRecorder)
    func videoRecorderDidStopRecording(_ recorder: VideoRecorder, outputURL: URL?, error: Error?)
    func videoRecorderDidUpdateDuration(_ recorder: VideoRecorder, duration: TimeInterval)
}

public struct VideoMetadata {
    public let durationSeconds: Int
    public let sizeBytes: Int64
    public let sizeMB: Double
    public let resolution: String
}

public final class VideoRecorder {
    public weak var delegate: VideoRecorderDelegate?

    private let maxDurationSeconds: TimeInterval?
    private let maxSizeMB: Double?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    public private(set) var isCurrentlyRecording: Bool = false

    private var startTime: CFTimeInterval?
    private var lastDurationReport: TimeInterval = 0
    private var outputURL: URL?
    private var expectedSizeBytes: Int64 = 0

    private let queue = DispatchQueue(label: "VideoRecorder.queue")

    private let captureSettings: VideoCaptureSettings?

    public init(captureSettings: VideoCaptureSettings?) {
        self.captureSettings = captureSettings
        self.maxDurationSeconds = captureSettings?.maxDurationSeconds
        self.maxSizeMB = captureSettings?.maxSizeMB
    }

    public func prepare() throws {
        try queue.sync {
            expectedSizeBytes = 0
            startTime = nil
            lastDurationReport = 0
            outputURL = try makeTempURL()

            assetWriter = try AVAssetWriter(outputURL: outputURL!, fileType: .mp4)

            let width = 1920
            let height = 1080
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            videoInput.transform = .identity

            guard assetWriter!.canAdd(videoInput) else {
                throw NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
            assetWriter!.add(videoInput)
            self.videoInput = videoInput

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        }
    }

    public func startRecording() throws {
        try queue.sync {
            guard let assetWriter = assetWriter else {
                throw NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "AssetWriter not prepared"])
            }
            if !assetWriter.startWriting() {
                throw NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
            }
            assetWriter.startSession(atSourceTime: CMTime.zero)
            startTime = CACurrentMediaTime()
            isCurrentlyRecording = true
            expectedSizeBytes = 0
            lastDurationReport = 0
            delegate?.videoRecorderDidStartRecording(self)
        }
    }

    public func stopRecording() {
        queue.async {
            guard self.isCurrentlyRecording else { return }
            self.isCurrentlyRecording = false
            self.videoInput?.markAsFinished()
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }
                var error: Error? = nil
                if let writer = self.assetWriter, writer.status != .completed {
                    if writer.status == .failed {
                        error = writer.error
                    } else {
                        error = NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown finish writing status"])
                    }
                }
                self.delegate?.videoRecorderDidStopRecording(self, outputURL: self.outputURL, error: error)
            }
        }
    }

    public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        queue.async {
            guard self.isCurrentlyRecording,
                  let adaptor = self.pixelBufferAdaptor,
                  let input = self.videoInput,
                  input.isReadyForMoreMediaData else {
                return
            }
            let cmTime = CMTime(value: CMTimeValue(timestamp * 30), timescale: 30)
            if !adaptor.append(pixelBuffer, withPresentationTime: cmTime) {
                // Append failed silently
            } else {
                self.expectedSizeBytes += Int64(CVPixelBufferGetDataSize(pixelBuffer))
                let duration = CMTimeGetSeconds(cmTime)
                if duration - self.lastDurationReport >= 1.0 {
                    self.lastDurationReport = duration
                    self.delegate?.videoRecorderDidUpdateDuration(self, duration: duration)
                }
                if let maxDuration = self.maxDurationSeconds, duration >= maxDuration {
                    self.stopRecording()
                } else if let maxMB = self.maxSizeMB, Double(self.expectedSizeBytes) >= maxMB * 1024 * 1024 {
                    self.stopRecording()
                }
            }
        }
    }

    public func getVideoMetadata() -> VideoMetadata? {
        return queue.sync {
            guard let outputURL = outputURL else { return nil }
            let asset = AVAsset(url: outputURL)
            guard let track = asset.tracks(withMediaType: .video).first else { return nil }
            let durationSeconds = Int(CMTimeGetSeconds(asset.duration).rounded())
            var sizeBytes: Int64 = 0
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                sizeBytes = attrs[.size] as? Int64 ?? 0
            } catch {
                sizeBytes = 0
            }
            let sizeMB = Double(sizeBytes) / (1024.0 * 1024.0)
            let resolution = "\(Int(track.naturalSize.width))x\(Int(track.naturalSize.height))"
            return VideoMetadata(durationSeconds: durationSeconds, sizeBytes: sizeBytes, sizeMB: sizeMB, resolution: resolution)
        }
    }

    public func extractThumbnail(at timeSeconds: Double) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let outputURL = self.outputURL else {
                    continuation.resume(returning: nil)
                    return
                }
                let asset = AVAsset(url: outputURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                    if let cgImage = cgImage {
                        let image = UIImage(cgImage: cgImage)
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    private func makeTempURL() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileName = UUID().uuidString + ".mp4"
        let url = tempDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }
}

// Minimal stub for VideoCaptureSettings to make the file self-contained.
// This can be replaced by the actual definition elsewhere.
public struct VideoCaptureSettings {
    public let maxDurationSeconds: TimeInterval?
    public let maxSizeMB: Double?

    public init(maxDurationSeconds: TimeInterval?, maxSizeMB: Double?) {
        self.maxDurationSeconds = maxDurationSeconds
        self.maxSizeMB = maxSizeMB
    }
}
