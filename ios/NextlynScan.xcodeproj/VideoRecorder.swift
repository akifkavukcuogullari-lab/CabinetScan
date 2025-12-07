import Foundation
import AVFoundation
import UIKit

public struct VideoCaptureSettings {
    public var maxDurationSeconds: TimeInterval?
    public var maxSizeMB: Double?
    
    public init(maxDurationSeconds: TimeInterval? = nil, maxSizeMB: Double? = nil) {
        self.maxDurationSeconds = maxDurationSeconds
        self.maxSizeMB = maxSizeMB
    }
}

public protocol VideoRecorderDelegate: AnyObject {
    func videoRecorderDidStartRecording(_ recorder: VideoRecorder)
    func videoRecorderDidStopRecording(_ recorder: VideoRecorder, outputURL: URL?, error: Error?)
    func videoRecorderDidUpdateDuration(_ recorder: VideoRecorder, duration: TimeInterval)
}

public enum VideoRecorderError: Error {
    case notPrepared
    case alreadyRecording
    case writerFailed(String)
}

public final class VideoRecorder {
    
    private let captureSettings: VideoCaptureSettings?
    public weak var delegate: VideoRecorderDelegate?
    
    private let queue = DispatchQueue(label: "VideoRecorder.Writer")
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var startTimestamp: CMTime?
    private var lastTimestamp: CMTime?
    private var currentDuration: TimeInterval = 0
    private var outputURL: URL?
    
    public private(set) var isCurrentlyRecording: Bool = false
    
    private let videoWidth: Int32 = 1920
    private let videoHeight: Int32 = 1080
    
    public init(captureSettings: VideoCaptureSettings? = nil) {
        self.captureSettings = captureSettings
    }
    
    public func prepare() throws {
        try queue.sync {
            if isCurrentlyRecording {
                throw VideoRecorderError.alreadyRecording
            }
            currentDuration = 0
            startTimestamp = nil
            lastTimestamp = nil
            outputURL = nil
            assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
            
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let fileName = UUID().uuidString + ".mp4"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            do {
                assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            } catch {
                throw VideoRecorderError.writerFailed("Failed to create AVAssetWriter: \(error.localizedDescription)")
            }
            
            guard let assetWriter = assetWriter else {
                throw VideoRecorderError.writerFailed("AVAssetWriter is nil after creation")
            }
            
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: NSNumber(value: videoWidth),
                AVVideoHeightKey: NSNumber(value: videoHeight),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: NSNumber(value: 6_000_000),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            videoInput.expectsMediaDataInRealTime = true
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: NSNumber(value: videoWidth),
                kCVPixelBufferHeightKey as String: NSNumber(value: videoHeight),
                kCVPixelFormatOpenGLESCompatibility as String: true
            ]
            
            let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
                                                                          sourcePixelBufferAttributes: sourcePixelBufferAttributes)
            
            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                throw VideoRecorderError.writerFailed("Cannot add video input to asset writer")
            }
            
            self.videoInput = videoInput
            self.pixelBufferAdaptor = pixelBufferAdaptor
            self.outputURL = fileURL
        }
    }
    
    public func startRecording() throws {
        try queue.sync {
            guard let assetWriter = assetWriter,
                  let videoInput = videoInput else {
                throw VideoRecorderError.notPrepared
            }
            if isCurrentlyRecording {
                throw VideoRecorderError.alreadyRecording
            }
            
            if FileManager.default.fileExists(atPath: assetWriter.outputURL.path) {
                try? FileManager.default.removeItem(at: assetWriter.outputURL)
            }
            
            let started = assetWriter.startWriting()
            if !started {
                throw VideoRecorderError.writerFailed("Failed to start writing: \(assetWriter.error?.localizedDescription ?? "unknown error")")
            }
            // startSession(atSourceTime:) will be called on first appendPixelBuffer
            
            isCurrentlyRecording = true
            currentDuration = 0
            startTimestamp = nil
            lastTimestamp = nil
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.videoRecorderDidStartRecording(self)
            }
        }
    }
    
    public func stopRecording() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentlyRecording else { return }
            self.isCurrentlyRecording = false
            
            guard let assetWriter = self.assetWriter else {
                DispatchQueue.main.async {
                    self.delegate?.videoRecorderDidStopRecording(self, outputURL: nil, error: VideoRecorderError.notPrepared)
                }
                return
            }
            
            self.videoInput?.markAsFinished()
            assetWriter.finishWriting { [weak self] in
                guard let self = self else { return }
                let error = assetWriter.error
                DispatchQueue.main.async {
                    self.delegate?.videoRecorderDidStopRecording(self, outputURL: self.outputURL, error: error)
                }
            }
        }
    }
    
    public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.isCurrentlyRecording,
                  let assetWriter = self.assetWriter,
                  let videoInput = self.videoInput,
                  let pixelBufferAdaptor = self.pixelBufferAdaptor else {
                return
            }
            
            let cmTimestamp = CMTime(seconds: timestamp, preferredTimescale: 600)
            
            if assetWriter.status == .unknown {
                assetWriter.startSession(atSourceTime: cmTimestamp)
                self.startTimestamp = cmTimestamp
            }
            
            guard assetWriter.status == .writing else {
                return
            }
            
            guard videoInput.isReadyForMoreMediaData else {
                return
            }
            
            if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: cmTimestamp) {
                // Append failed
                return
            }
            
            self.lastTimestamp = cmTimestamp
            
            if let start = self.startTimestamp {
                let duration = CMTimeSubtract(cmTimestamp, start)
                let durationSeconds = CMTimeGetSeconds(duration)
                self.currentDuration = durationSeconds
                DispatchQueue.main.async {
                    self.delegate?.videoRecorderDidUpdateDuration(self, duration: durationSeconds)
                }
                
                if let maxDuration = self.captureSettings?.maxDurationSeconds,
                   durationSeconds >= maxDuration {
                    self.stopRecording()
                }
            }
        }
    }
    
    public func getVideoMetadata() -> (durationSeconds: Int, sizeBytes: Int64, sizeMB: Double, resolution: String)? {
        guard let url = outputURL else {
            return nil
        }
        
        var durationSecondsInt = 0
        if let last = lastTimestamp, let start = startTimestamp {
            let duration = CMTimeSubtract(last, start)
            durationSecondsInt = Int(CMTimeGetSeconds(duration))
        } else if currentDuration > 0 {
            durationSecondsInt = Int(currentDuration)
        }
        
        let resolutionString = "\(videoWidth)x\(videoHeight)"
        
        let fileSize: Int64
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attr[FileAttributeKey.size] as? Int64 ?? 0
        } catch {
            return nil
        }
        let sizeMB = Double(fileSize) / 1_000_000
        
        return (durationSecondsInt, fileSize, sizeMB, resolutionString)
    }
    
    public func extractThumbnail(at time: TimeInterval) async -> UIImage? {
        guard let url = outputURL else { return nil }
        
        return await withCheckedContinuation { continuation in
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, result, error in
                if let cgImage = cgImage, result == .succeeded {
                    let uiImage = UIImage(cgImage: cgImage)
                    continuation.resume(returning: uiImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
