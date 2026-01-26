//
//  AIQualityAnalyzer.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//  Extended by Story 2.4: Quality Analysis Engine
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import CoreVideo
import UIKit

// MARK: - Quality Issue Types

/// Types of quality issues detected during capture
enum AIQualityIssue: Equatable {
    /// Motion blur detected (variance below threshold)
    case motionBlur(severity: BlurSeverity)

    /// Insufficient lighting
    case tooDark(meanLuminance: Float)

    /// Overexposed (rare, but possible)
    case tooBright(meanLuminance: Float)

    /// Low contrast (flat image)
    case lowContrast(stdDev: Float)

    /// Device tier for logging
    var description: String {
        switch self {
        case .motionBlur(let severity):
            return "Motion blur (\(severity))"
        case .tooDark(let luminance):
            return "Too dark (luminance: \(luminance))"
        case .tooBright(let luminance):
            return "Too bright (luminance: \(luminance))"
        case .lowContrast(let stdDev):
            return "Low contrast (stdDev: \(stdDev))"
        }
    }
}

/// Blur severity levels per ADR-002
enum BlurSeverity: String, Equatable {
    case warning   // variance < 100
    case severe    // variance < 50
}

// MARK: - Photo Quality Result (Story 2.4 - Task 4)

/// Result of photo quality analysis
struct PhotoQualityResult {
    /// Whether the photo is acceptable quality
    let isAcceptable: Bool

    /// Blur score (Laplacian variance) - higher is sharper
    let blurScore: Float

    /// Mean brightness (0-255)
    let brightnessScore: Float

    /// List of detected quality issues
    let issues: [PhotoQualityIssue]

    /// Photo quality issue types
    enum PhotoQualityIssue: Equatable {
        case tooBlurry(score: Float)
        case tooDark(brightness: Float)
        case tooBright(brightness: Float)
        case lowContrast(stdDev: Float)

        var description: String {
            switch self {
            case .tooBlurry(let score):
                return "Too blurry (score: \(score))"
            case .tooDark(let brightness):
                return "Too dark (brightness: \(brightness))"
            case .tooBright(let brightness):
                return "Too bright (brightness: \(brightness))"
            case .lowContrast(let stdDev):
                return "Low contrast (stdDev: \(stdDev))"
            }
        }
    }
}

// MARK: - Histogram Statistics (Story 2.4 - Task 3)

/// Statistics derived from luminance histogram
struct HistogramStats {
    /// Mean luminance (0-255)
    let mean: Float

    /// Standard deviation (contrast indicator)
    let stdDev: Float

    /// 5th percentile (shadows)
    let percentile5: Float

    /// 95th percentile (highlights)
    let percentile95: Float

    /// Dynamic range (P95 - P5)
    var dynamicRange: Float { percentile95 - percentile5 }
}

// MARK: - Quality State

/// Aggregate quality state for UI updates
struct AIQualityState: Equatable {
    /// Current blur status
    var blurIssue: BlurSeverity?

    /// Current brightness issue
    var brightnessIssue: BrightnessIssue?

    /// Current contrast issue (Story 2.4)
    var contrastIssue: Bool = false

    /// Whether quality is acceptable for capture
    var isAcceptable: Bool {
        blurIssue == nil && brightnessIssue == nil && !contrastIssue
    }

    /// Most severe issue for toast priority
    var mostSevereIssue: AIQualityIssue? {
        // Severe blur takes priority
        if blurIssue == .severe {
            return .motionBlur(severity: .severe)
        }
        // Then darkness
        if let brightness = brightnessIssue, brightness == .tooDark {
            return .tooDark(meanLuminance: 0)
        }
        // Then warning blur
        if blurIssue == .warning {
            return .motionBlur(severity: .warning)
        }
        // Then overexposure
        if let brightness = brightnessIssue, brightness == .tooBright {
            return .tooBright(meanLuminance: 255)
        }
        // Then low contrast
        if contrastIssue {
            return .lowContrast(stdDev: 0)
        }
        return nil
    }

    static let acceptable = AIQualityState(blurIssue: nil, brightnessIssue: nil, contrastIssue: false)
}

/// Brightness issue types
enum BrightnessIssue: Equatable {
    case tooDark
    case tooBright
}

// MARK: - Debounce Tracker (Story 2.4 - Task 2)

/// Tracks consecutive frames to prevent quality state flicker
/// Requires N consecutive bad/good frames before changing state
class DebounceTracker {
    /// Number of consecutive frames required to change state
    private let threshold: Int

    /// Current consecutive bad frame count
    private var consecutiveBadCount: Int = 0

    /// Current consecutive good frame count
    private var consecutiveGoodCount: Int = 0

    /// Current quality state
    private(set) var currentState: QualityState = .good

    enum QualityState { case good, bad }

    init(threshold: Int = 3) {
        self.threshold = threshold
    }

    /// Update with new frame quality
    /// - Parameter isBad: Whether the current frame has quality issues
    /// - Returns: Tuple of (stateChanged, newState)
    func update(isBad: Bool) -> (stateChanged: Bool, newState: QualityState) {
        if isBad {
            consecutiveBadCount += 1
            consecutiveGoodCount = 0

            if currentState == .good && consecutiveBadCount >= threshold {
                currentState = .bad
                return (true, .bad)
            }
        } else {
            consecutiveGoodCount += 1
            consecutiveBadCount = 0

            if currentState == .bad && consecutiveGoodCount >= threshold {
                currentState = .good
                return (true, .good)
            }
        }
        return (false, currentState)
    }

    /// Reset the tracker to initial state
    func reset() {
        consecutiveBadCount = 0
        consecutiveGoodCount = 0
        currentState = .good
    }
}

// MARK: - Sliding Window Average (Story 2.4 - Task 1)

/// Maintains a sliding window of values for noise reduction
class SlidingWindowAverage {
    private var values: [Float] = []
    private let windowSize: Int

    init(windowSize: Int = 5) {
        self.windowSize = windowSize
    }

    /// Add a value and return the windowed average
    func add(_ value: Float) -> Float {
        values.append(value)
        if values.count > windowSize {
            values.removeFirst()
        }
        return values.reduce(0, +) / Float(values.count)
    }

    /// Reset the window
    func reset() {
        values.removeAll()
    }
}

// MARK: - Running Statistics (Story 2.4 - Task 5)

/// Collects running statistics during analysis session
class RunningStats {
    private var blurScores: [Float] = []
    private var brightnessScores: [Float] = []
    private var analysisTimes: [TimeInterval] = []
    private(set) var discardedCount: Int = 0
    private(set) var poorQualityCount: Int = 0
    private(set) var circuitBreakerTrips: Int = 0

    /// Record a frame analysis result
    func record(blur: Float, brightness: Float, analysisTime: TimeInterval, wasPoorQuality: Bool) {
        blurScores.append(blur)
        brightnessScores.append(brightness)
        analysisTimes.append(analysisTime)
        if wasPoorQuality { poorQualityCount += 1 }
    }

    /// Record a discarded frame
    func recordDiscarded() {
        discardedCount += 1
    }

    /// Record a circuit breaker trip
    func recordCircuitBreakerTrip() {
        circuitBreakerTrips += 1
    }

    /// Compute aggregate metrics
    func computeMetrics() -> AIQualityMetrics {
        let avgBlur = blurScores.isEmpty ? 0 : blurScores.reduce(0, +) / Float(blurScores.count)
        let avgBrightness = brightnessScores.isEmpty ? 0 : brightnessScores.reduce(0, +) / Float(brightnessScores.count)

        // Calculate P95 of analysis times
        let sortedTimes = analysisTimes.sorted()
        let p95Index = Int(Double(sortedTimes.count) * 0.95)
        let p95Time = sortedTimes.isEmpty ? 0 : sortedTimes[min(p95Index, sortedTimes.count - 1)]

        return AIQualityMetrics(
            averageBlurScore: avgBlur,
            averageBrightness: avgBrightness,
            analyzedFrameCount: blurScores.count,
            discardedFrameCount: discardedCount,
            poorQualityWindowCount: poorQualityCount,
            circuitBreakerTripCount: circuitBreakerTrips,
            analysisTimePercentile95: p95Time
        )
    }

    /// Reset all statistics
    func reset() {
        blurScores.removeAll()
        brightnessScores.removeAll()
        analysisTimes.removeAll()
        discardedCount = 0
        poorQualityCount = 0
        circuitBreakerTrips = 0
    }
}

// MARK: - Device Tier (ADR-001)

/// Device performance tiers for adaptive frame sampling
enum AIDeviceTier: String {
    /// A11 and older (iPhone X/XR) - every 15th frame (2 fps analysis)
    case legacy

    /// A12-A14 (iPhone XS to 12) - every 6th frame (5 fps analysis)
    case standard

    /// A15+ (iPhone 13+) - every 3rd frame (10 fps analysis)
    case performance

    /// Frame sample rate (analyze every Nth frame)
    var sampleRate: Int {
        switch self {
        case .legacy: return 15
        case .standard: return 6
        case .performance: return 3
        }
    }

    /// Detect current device tier
    static var current: AIDeviceTier {
        // Get device model identifier
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr)
            }
        } ?? ""

        // Parse iPhone model number (e.g., "iPhone14,5" = iPhone 13)
        if modelCode.hasPrefix("iPhone") {
            let components = modelCode.dropFirst(6).split(separator: ",")
            if let majorStr = components.first, let major = Int(majorStr) {
                // iPhone 14+ (A15+) = performance tier
                if major >= 14 {
                    return .performance
                }
                // iPhone 11-13 (A12-A14) = standard tier
                if major >= 11 {
                    return .standard
                }
                // iPhone 10 and older (A11-) = legacy tier
                return .legacy
            }
        }

        // Simulator or unknown - assume standard
        #if targetEnvironment(simulator)
        return .standard
        #else
        return .standard
        #endif
    }
}

// MARK: - Quality Analyzer

/// Analyzes video frame quality for blur and lighting.
/// Uses Accelerate framework for efficient image processing.
/// Per Story 2.3 - Task 2, ADR-001, ADR-002, ADR-003
/// Extended by Story 2.4 with debouncing, histogram analysis, photo validation, and metrics
///
/// **Threading Model (ADR-003):**
/// - Analysis runs on dedicated serial queue
/// - Quality state published on main thread (batched, not per-frame)
///
/// **Frame Sampling (ADR-001):**
/// - Adaptive sampling based on device tier
/// - Circuit breaker skips frames if analysis takes >30ms
///
/// **Blur Thresholds (ADR-002):**
/// - Warning: Laplacian variance < 100
/// - Severe: Laplacian variance < 50
///
/// **Debouncing (Story 2.4):**
/// - Requires 3+ consecutive bad/good frames to change state
/// - Uses sliding window averaging for noise reduction
class AIQualityAnalyzer: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Current quality state (updated when significant change occurs)
    @Published private(set) var qualityState: AIQualityState = .acceptable

    /// Quality issue events for guidance toast system
    let qualityIssuePublisher = PassthroughSubject<AIQualityIssue, Never>()

    /// Quality recovery event (when quality improves after bad state)
    let qualityRecoveryPublisher = PassthroughSubject<Void, Never>()

    // MARK: - Constants

    /// Blur thresholds (ADR-002)
    private struct BlurThresholds {
        static let warning: Float = 100.0   // variance < 100 = warning
        static let severe: Float = 50.0     // variance < 50 = severe blur
        static let photoReject: Float = 150.0 // Photo blur threshold (stricter)
    }

    /// Brightness thresholds
    private struct BrightnessThresholds {
        static let tooDark: Float = 40.0    // mean luminance < 40
        static let tooBright: Float = 220.0 // mean luminance > 220
    }

    /// Histogram-based thresholds (Story 2.4 - Task 3)
    private struct HistogramThresholds {
        static let underexposedP95: Float = 100.0  // P95 < 100 = shadows dominate
        static let overexposedP5: Float = 200.0    // P5 > 200 = highlights blown
        static let lowContrastStdDev: Float = 30.0 // stdDev < 30 = flat image
    }

    /// Circuit breaker threshold (30ms per ADR-001)
    private let circuitBreakerThreshold: TimeInterval = 0.030

    /// Number of frames to skip after circuit breaker trips (ADR-001)
    private let circuitBreakerSkipCount = 2

    // MARK: - Properties

    /// Device performance tier
    let deviceTier: AIDeviceTier

    /// Frame sample rate (analyze every Nth frame)
    private let frameSampleRate: Int

    /// Analysis queue (dedicated serial queue per ADR-003)
    private let analysisQueue = DispatchQueue(
        label: "com.cabinetscan.aiflow.qualityAnalysis",
        qos: .userInitiated
    )

    /// Current frame counter
    private var frameCount = 0

    /// Circuit breaker skip counter
    private var skipCount = 0

    /// Whether analysis is currently active
    private var isAnalyzing = false

    /// Last published quality state (to avoid redundant updates)
    private var lastPublishedState: AIQualityState = .acceptable

    /// Lock for thread-safe state access
    private let stateLock = NSLock()

    // MARK: - Story 2.4 Properties

    /// Debounce tracker for blur issues
    private let blurDebouncer = DebounceTracker(threshold: 3)

    /// Debounce tracker for brightness issues
    private let brightnessDebouncer = DebounceTracker(threshold: 3)

    /// Sliding window average for blur scores (noise reduction)
    private let blurWindow = SlidingWindowAverage(windowSize: 5)

    /// Sliding window average for brightness scores (noise reduction)
    private let brightnessWindow = SlidingWindowAverage(windowSize: 5)

    /// Running statistics collector
    private let runningStats = RunningStats()

    /// Whether debounced blur state is currently bad
    private var debouncedBlurBad = false

    /// Whether debounced brightness state is currently bad
    private var debouncedBrightnessBad = false

    // MARK: - Initialization

    override init() {
        self.deviceTier = AIDeviceTier.current
        self.frameSampleRate = deviceTier.sampleRate
        super.init()
        print("[AIQualityAnalyzer] Initialized with device tier: \(deviceTier.rawValue), sample rate: every \(frameSampleRate) frames")
    }

    // MARK: - Public Methods

    /// Start quality analysis
    func startAnalysis() {
        stateLock.lock()
        isAnalyzing = true
        frameCount = 0
        skipCount = 0
        lastPublishedState = .acceptable
        debouncedBlurBad = false
        debouncedBrightnessBad = false
        stateLock.unlock()

        // Reset debouncing and statistics
        blurDebouncer.reset()
        brightnessDebouncer.reset()
        blurWindow.reset()
        brightnessWindow.reset()
        runningStats.reset()

        DispatchQueue.main.async { [weak self] in
            self?.qualityState = .acceptable
        }

        print("[AIQualityAnalyzer] Analysis started")
    }

    /// Stop quality analysis
    func stopAnalysis() {
        stateLock.lock()
        isAnalyzing = false
        stateLock.unlock()

        print("[AIQualityAnalyzer] Analysis stopped")
    }

    /// Get aggregate metrics from the current session (Story 2.4 - Task 5)
    /// - Returns: Aggregate quality metrics
    func getAggregateMetrics() -> AIQualityMetrics {
        return runningStats.computeMetrics()
    }

    /// Analyze a single photo for quality (Story 2.4 - Task 4)
    /// Runs synchronously - blocking is OK for single photo validation
    /// - Parameter image: The photo to analyze
    /// - Returns: Photo quality result
    func analyzePhoto(_ image: UIImage) -> PhotoQualityResult {
        guard let cgImage = image.cgImage else {
            return PhotoQualityResult(
                isAcceptable: false,
                blurScore: 0,
                brightnessScore: 0,
                issues: [.tooBlurry(score: 0)]
            )
        }

        // Analyze at full resolution for photos
        let blurScore = calculateBlurScoreFromCGImage(cgImage)
        let histogramStats = calculateHistogramStatsFromCGImage(cgImage)

        var issues: [PhotoQualityResult.PhotoQualityIssue] = []

        // Photo blur threshold is stricter than video (150 vs 100)
        if blurScore < BlurThresholds.photoReject {
            issues.append(.tooBlurry(score: blurScore))
        }

        // Check brightness from histogram
        if histogramStats.percentile95 < HistogramThresholds.underexposedP95 {
            issues.append(.tooDark(brightness: histogramStats.mean))
        }
        if histogramStats.percentile5 > HistogramThresholds.overexposedP5 {
            issues.append(.tooBright(brightness: histogramStats.mean))
        }
        if histogramStats.stdDev < HistogramThresholds.lowContrastStdDev {
            issues.append(.lowContrast(stdDev: histogramStats.stdDev))
        }

        let isAcceptable = issues.isEmpty

        print("[AIQualityAnalyzer] Photo analysis - blur: \(blurScore), brightness: \(histogramStats.mean), acceptable: \(isAcceptable)")

        return PhotoQualityResult(
            isAcceptable: isAcceptable,
            blurScore: blurScore,
            brightnessScore: histogramStats.mean,
            issues: issues
        )
    }

    /// Process a video frame for quality analysis
    /// - Parameter sampleBuffer: The video sample buffer to analyze
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        stateLock.lock()
        guard isAnalyzing else {
            stateLock.unlock()
            return
        }

        frameCount += 1
        let currentFrame = frameCount

        // Circuit breaker: skip if previous analysis was too slow
        if skipCount > 0 {
            skipCount -= 1
            stateLock.unlock()
            runningStats.recordDiscarded()
            return
        }

        // Sample rate: only analyze every Nth frame
        guard currentFrame % frameSampleRate == 0 else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        // Get pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Perform analysis on dedicated queue (ADR-003)
        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            // Lock pixel buffer for reading
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            // Analyze quality
            let rawBlurVariance = self.calculateBlurScore(pixelBuffer: pixelBuffer)
            let histogramStats = self.calculateHistogramStats(pixelBuffer: pixelBuffer)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Apply sliding window averaging for noise reduction (Story 2.4 - Task 1)
            let smoothedBlur = self.blurWindow.add(rawBlurVariance)
            let smoothedBrightness = self.brightnessWindow.add(histogramStats.mean)

            // Circuit breaker: if >30ms, skip next 2 analyses (ADR-001)
            if elapsed > self.circuitBreakerThreshold {
                self.stateLock.lock()
                self.skipCount = self.circuitBreakerSkipCount
                self.stateLock.unlock()
                self.runningStats.recordCircuitBreakerTrip()
                print("[AIQualityAnalyzer] Circuit breaker tripped - analysis took \(Int(elapsed * 1000))ms, skipping next \(self.circuitBreakerSkipCount) frames")
            }

            // Determine quality issues using histogram-based evaluation
            let newState = self.evaluateQualityWithHistogram(
                blurVariance: smoothedBlur,
                histogramStats: histogramStats
            )

            // Apply debouncing (Story 2.4 - Task 2)
            let debouncedState = self.applyDebouncing(rawState: newState, smoothedBlur: smoothedBlur, smoothedBrightness: smoothedBrightness)

            // Record statistics (Story 2.4 - Task 5)
            self.runningStats.record(
                blur: smoothedBlur,
                brightness: smoothedBrightness,
                analysisTime: elapsed,
                wasPoorQuality: !debouncedState.isAcceptable
            )

            // Publish if changed significantly
            self.publishStateIfChanged(debouncedState)
        }
    }

    // MARK: - Blur Detection (Laplacian Variance)

    /// Calculate blur score using Laplacian variance
    /// Lower variance = more blur
    /// - Parameter pixelBuffer: The pixel buffer to analyze
    /// - Returns: Laplacian variance score
    private func calculateBlurScore(pixelBuffer: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // For performance, analyze a center crop (1/4 of image)
        let analysisWidth = width / 2
        let analysisHeight = height / 2
        let offsetX = (width - analysisWidth) / 2
        let offsetY = (height - analysisHeight) / 2

        // Get base address and bytes per row
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 1000 // Return high value (not blurry) on error
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Create grayscale buffer from Y channel (assuming BGRA format)
        // For 420YpCbCr8BiPlanarVideoRange, use plane 0 (Y)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var grayscaleData: [Float]

        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            // Bi-planar format - Y plane is plane 0
            guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                return 1000
            }
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPlaneHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

            // Extract grayscale from Y plane center region
            grayscaleData = extractGrayscaleFromYPlane(
                yPlaneAddress: yPlaneAddress,
                bytesPerRow: yBytesPerRow,
                fullWidth: width,
                fullHeight: yPlaneHeight,
                cropX: offsetX,
                cropY: offsetY,
                cropWidth: analysisWidth,
                cropHeight: analysisHeight
            )
        } else {
            // BGRA format - extract luminance
            grayscaleData = extractGrayscaleFromBGRA(
                baseAddress: baseAddress,
                bytesPerRow: bytesPerRow,
                cropX: offsetX,
                cropY: offsetY,
                cropWidth: analysisWidth,
                cropHeight: analysisHeight
            )
        }

        // Apply Laplacian kernel and calculate variance
        return calculateLaplacianVariance(
            grayscaleData: grayscaleData,
            width: analysisWidth,
            height: analysisHeight
        )
    }

    /// Extract grayscale data from Y plane
    private func extractGrayscaleFromYPlane(
        yPlaneAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        fullWidth: Int,
        fullHeight: Int,
        cropX: Int,
        cropY: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> [Float] {
        var grayscale = [Float](repeating: 0, count: cropWidth * cropHeight)

        let yPtr = yPlaneAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<cropHeight {
            let srcY = cropY + y
            guard srcY < fullHeight else { continue }

            for x in 0..<cropWidth {
                let srcX = cropX + x
                guard srcX < fullWidth else { continue }

                let srcOffset = srcY * bytesPerRow + srcX
                let dstOffset = y * cropWidth + x
                grayscale[dstOffset] = Float(yPtr[srcOffset])
            }
        }

        return grayscale
    }

    /// Extract grayscale data from BGRA buffer
    private func extractGrayscaleFromBGRA(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        cropX: Int,
        cropY: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> [Float] {
        var grayscale = [Float](repeating: 0, count: cropWidth * cropHeight)

        let bgraPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let srcX = cropX + x
                let srcY = cropY + y
                let srcOffset = srcY * bytesPerRow + srcX * 4

                // Luminance formula: 0.299*R + 0.587*G + 0.114*B
                let b = Float(bgraPtr[srcOffset])
                let g = Float(bgraPtr[srcOffset + 1])
                let r = Float(bgraPtr[srcOffset + 2])

                let dstOffset = y * cropWidth + x
                grayscale[dstOffset] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        return grayscale
    }

    /// Calculate Laplacian variance using Accelerate framework
    /// Laplacian kernel: [0, 1, 0], [1, -4, 1], [0, 1, 0]
    private func calculateLaplacianVariance(grayscaleData: [Float], width: Int, height: Int) -> Float {
        guard width > 2 && height > 2 else { return 1000 }

        // Output buffer for Laplacian result
        var laplacianResult = [Float](repeating: 0, count: (width - 2) * (height - 2))

        // Apply Laplacian kernel manually (simpler than vImage for 3x3)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = grayscaleData[y * width + x]
                let top = grayscaleData[(y - 1) * width + x]
                let bottom = grayscaleData[(y + 1) * width + x]
                let left = grayscaleData[y * width + (x - 1)]
                let right = grayscaleData[y * width + (x + 1)]

                // Laplacian: -4*center + top + bottom + left + right
                let laplacian = -4 * center + top + bottom + left + right
                laplacianResult[(y - 1) * (width - 2) + (x - 1)] = laplacian
            }
        }

        // Calculate variance using vDSP
        var mean: Float = 0
        var variance: Float = 0
        let count = vDSP_Length(laplacianResult.count)

        // Calculate mean
        vDSP_meanv(laplacianResult, 1, &mean, count)

        // Calculate mean square
        var meanSquare: Float = 0
        vDSP_measqv(laplacianResult, 1, &meanSquare, count)

        // Variance = E[X^2] - E[X]^2
        variance = meanSquare - (mean * mean)

        return variance
    }

    // MARK: - Histogram Analysis (Story 2.4 - Task 3)

    /// Calculate histogram statistics for a pixel buffer
    private func calculateHistogramStats(pixelBuffer: CVPixelBuffer) -> HistogramStats {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return calculateHistogramStatsFromYPlane(pixelBuffer: pixelBuffer)
        }

        return calculateHistogramStatsFromBGRA(pixelBuffer: pixelBuffer)
    }

    /// Calculate histogram from Y plane
    private func calculateHistogramStatsFromYPlane(pixelBuffer: CVPixelBuffer) -> HistogramStats {
        guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        // Sample every 4th pixel for performance
        let sampleStep = 4
        var histogram = [Int](repeating: 0, count: 256)
        var sampleCount = 0

        let yPtr = yPlaneAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x
                let value = Int(yPtr[offset])
                histogram[value] += 1
                sampleCount += 1
            }
        }

        return computeStatsFromHistogram(histogram, sampleCount: sampleCount)
    }

    /// Calculate histogram from BGRA buffer
    private func calculateHistogramStatsFromBGRA(pixelBuffer: CVPixelBuffer) -> HistogramStats {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let sampleStep = 4
        var histogram = [Int](repeating: 0, count: 256)
        var sampleCount = 0

        let bgraPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * 4
                let b = Float(bgraPtr[offset])
                let g = Float(bgraPtr[offset + 1])
                let r = Float(bgraPtr[offset + 2])
                let luminance = Int(0.299 * r + 0.587 * g + 0.114 * b)
                histogram[min(255, max(0, luminance))] += 1
                sampleCount += 1
            }
        }

        return computeStatsFromHistogram(histogram, sampleCount: sampleCount)
    }

    /// Compute statistics from histogram
    private func computeStatsFromHistogram(_ histogram: [Int], sampleCount: Int) -> HistogramStats {
        guard sampleCount > 0 else {
            return HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)
        }

        // Calculate mean
        var sum: Float = 0
        for (bin, count) in histogram.enumerated() {
            sum += Float(bin) * Float(count)
        }
        let mean = sum / Float(sampleCount)

        // Calculate standard deviation
        var varianceSum: Float = 0
        for (bin, count) in histogram.enumerated() {
            let diff = Float(bin) - mean
            varianceSum += diff * diff * Float(count)
        }
        let stdDev = sqrt(varianceSum / Float(sampleCount))

        // Calculate percentiles from cumulative histogram
        let p5Target = Int(Float(sampleCount) * 0.05)
        let p95Target = Int(Float(sampleCount) * 0.95)

        var cumulative = 0
        var percentile5: Float = 0
        var percentile95: Float = 255

        for (bin, count) in histogram.enumerated() {
            cumulative += count
            if percentile5 == 0 && cumulative >= p5Target {
                percentile5 = Float(bin)
            }
            if cumulative >= p95Target {
                percentile95 = Float(bin)
                break
            }
        }

        return HistogramStats(
            mean: mean,
            stdDev: stdDev,
            percentile5: percentile5,
            percentile95: percentile95
        )
    }

    /// Calculate histogram stats from CGImage (for photo analysis)
    /// Uses autoreleasepool to prevent memory accumulation during batch photo analysis
    private func calculateHistogramStatsFromCGImage(_ cgImage: CGImage) -> HistogramStats {
        return autoreleasepool {
            let width = cgImage.width
            let height = cgImage.height

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let data = context.data else {
                return HistogramStats(mean: 128, stdDev: 50, percentile5: 30, percentile95: 220)
            }

            let pixelData = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

            // Sample every 8th pixel for performance on high-res photos
            let sampleStep = 8
            var histogram = [Int](repeating: 0, count: 256)
            var sampleCount = 0

            for y in stride(from: 0, to: height, by: sampleStep) {
                for x in stride(from: 0, to: width, by: sampleStep) {
                    let offset = (y * width + x) * 4
                    let r = Float(pixelData[offset])
                    let g = Float(pixelData[offset + 1])
                    let b = Float(pixelData[offset + 2])
                    let luminance = Int(0.299 * r + 0.587 * g + 0.114 * b)
                    histogram[min(255, max(0, luminance))] += 1
                    sampleCount += 1
                }
            }

            return computeStatsFromHistogram(histogram, sampleCount: sampleCount)
        }
    }

    /// Calculate blur score from CGImage (for photo analysis)
    /// Uses autoreleasepool to prevent memory accumulation during batch photo analysis
    private func calculateBlurScoreFromCGImage(_ cgImage: CGImage) -> Float {
        return autoreleasepool {
            let width = cgImage.width
            let height = cgImage.height

            // For photos, analyze center 1/4 at full resolution
            let analysisWidth = width / 2
            let analysisHeight = height / 2
            let offsetX = (width - analysisWidth) / 2
            let offsetY = (height - analysisHeight) / 2

            guard let context = CGContext(
                data: nil,
                width: analysisWidth,
                height: analysisHeight,
                bitsPerComponent: 8,
                bytesPerRow: analysisWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return 1000 // Return high value (not blurry) on error
            }

            // Draw cropped center region
            context.draw(cgImage, in: CGRect(
                x: -offsetX,
                y: -offsetY,
                width: width,
                height: height
            ))

            guard let data = context.data else {
                return 1000
            }

            let pixelData = data.bindMemory(to: UInt8.self, capacity: analysisWidth * analysisHeight * 4)

            // Convert to grayscale
            var grayscale = [Float](repeating: 0, count: analysisWidth * analysisHeight)
            for y in 0..<analysisHeight {
                for x in 0..<analysisWidth {
                    let offset = (y * analysisWidth + x) * 4
                    let r = Float(pixelData[offset])
                    let g = Float(pixelData[offset + 1])
                    let b = Float(pixelData[offset + 2])
                    grayscale[y * analysisWidth + x] = 0.299 * r + 0.587 * g + 0.114 * b
                }
            }

            return calculateLaplacianVariance(grayscaleData: grayscale, width: analysisWidth, height: analysisHeight)
        }
    }

    // MARK: - Quality Evaluation

    /// Evaluate quality using histogram statistics (Story 2.4 - Task 3)
    private func evaluateQualityWithHistogram(blurVariance: Float, histogramStats: HistogramStats) -> AIQualityState {
        var state = AIQualityState()

        // Evaluate blur (ADR-002: two-tier thresholds)
        if blurVariance < BlurThresholds.severe {
            state.blurIssue = .severe
        } else if blurVariance < BlurThresholds.warning {
            state.blurIssue = .warning
        }

        // Evaluate brightness using histogram percentiles (more robust than mean)
        if histogramStats.percentile95 < HistogramThresholds.underexposedP95 {
            state.brightnessIssue = .tooDark
        } else if histogramStats.percentile5 > HistogramThresholds.overexposedP5 {
            state.brightnessIssue = .tooBright
        }

        // Evaluate contrast
        if histogramStats.stdDev < HistogramThresholds.lowContrastStdDev {
            state.contrastIssue = true
        }

        return state
    }

    /// Apply debouncing to raw quality state (Story 2.4 - Task 2)
    /// Thread-safe: uses stateLock to protect debouncedBlurBad/debouncedBrightnessBad
    private func applyDebouncing(rawState: AIQualityState, smoothedBlur: Float, smoothedBrightness: Float) -> AIQualityState {
        var debouncedState = AIQualityState()
        var shouldEmitBlurRecovery = false
        var shouldEmitBrightnessRecovery = false

        // Debounce blur
        let blurResult = blurDebouncer.update(isBad: rawState.blurIssue != nil)

        stateLock.lock()
        if blurResult.stateChanged {
            if blurResult.newState == .good && debouncedBlurBad {
                shouldEmitBlurRecovery = true
            }
            debouncedBlurBad = (blurResult.newState == .bad)
        }
        let currentBlurBad = debouncedBlurBad
        stateLock.unlock()

        // Apply debounced blur state
        if currentBlurBad || blurDebouncer.currentState == .bad {
            debouncedState.blurIssue = rawState.blurIssue ?? .warning
        }

        // Debounce brightness
        let brightnessResult = brightnessDebouncer.update(isBad: rawState.brightnessIssue != nil)

        stateLock.lock()
        if brightnessResult.stateChanged {
            if brightnessResult.newState == .good && debouncedBrightnessBad {
                shouldEmitBrightnessRecovery = true
            }
            debouncedBrightnessBad = (brightnessResult.newState == .bad)
        }
        let currentBrightnessBad = debouncedBrightnessBad
        stateLock.unlock()

        // Apply debounced brightness state
        if currentBrightnessBad || brightnessDebouncer.currentState == .bad {
            debouncedState.brightnessIssue = rawState.brightnessIssue ?? .tooDark
        }

        // Emit recovery events outside of lock to avoid potential deadlock
        if shouldEmitBlurRecovery || shouldEmitBrightnessRecovery {
            DispatchQueue.main.async { [weak self] in
                self?.qualityRecoveryPublisher.send()
            }
        }

        // Contrast doesn't need debouncing (less variable)
        debouncedState.contrastIssue = rawState.contrastIssue

        return debouncedState
    }

    /// Publish quality state if changed significantly
    private func publishStateIfChanged(_ newState: AIQualityState) {
        stateLock.lock()
        let shouldPublish = newState != lastPublishedState
        if shouldPublish {
            lastPublishedState = newState
        }
        stateLock.unlock()

        guard shouldPublish else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.qualityState = newState

            // Emit quality issue for toast system
            if let issue = newState.mostSevereIssue {
                self.qualityIssuePublisher.send(issue)
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension AIQualityAnalyzer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processSampleBuffer(sampleBuffer)
    }
}
