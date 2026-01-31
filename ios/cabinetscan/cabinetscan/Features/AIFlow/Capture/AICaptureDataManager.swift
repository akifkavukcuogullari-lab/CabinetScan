//
//  AICaptureDataManager.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//  Story 2.6: Capture Session Data Management
//

import Foundation
import UIKit
import simd

// MARK: - Pose Frame Models (Task 2)

/// A single pose frame with all associated data for reconstruction.
/// Codable for JSON serialization to disk.
struct AIPoseFrame: Codable, Sendable {
    /// Timestamp relative to session start
    let timestamp: TimeInterval

    /// 4x4 transform matrix as flat array (column-major)
    let transform: [Float]

    /// Camera intrinsic parameters
    let intrinsics: AIPoseIntrinsics

    /// Tracking state at capture time
    let trackingState: String

    /// Zoom factor at capture time
    let zoomFactor: CGFloat

    /// Initialize from AIPose
    init(timestamp: TimeInterval, pose: AIPose) {
        self.timestamp = timestamp
        self.transform = Self.flattenTransform(pose.transform)
        self.intrinsics = AIPoseIntrinsics(from: pose.intrinsics)
        self.trackingState = Self.trackingStateString(pose.trackingState)
        self.zoomFactor = pose.zoomFactor
    }

    /// Convert simd_float4x4 to flat array
    private static func flattenTransform(_ matrix: simd_float4x4) -> [Float] {
        return [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    /// Convert tracking state to string
    private static func trackingStateString(_ state: AITrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .limited: return "limited"
        case .notAvailable: return "notAvailable"
        }
    }

    /// Reconstruct simd_float4x4 from flat array
    func toTransformMatrix() -> simd_float4x4? {
        guard transform.count == 16 else { return nil }
        return simd_float4x4(
            SIMD4<Float>(transform[0], transform[1], transform[2], transform[3]),
            SIMD4<Float>(transform[4], transform[5], transform[6], transform[7]),
            SIMD4<Float>(transform[8], transform[9], transform[10], transform[11]),
            SIMD4<Float>(transform[12], transform[13], transform[14], transform[15])
        )
    }
}

/// Codable version of camera intrinsics
struct AIPoseIntrinsics: Codable, Sendable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float

    init(from intrinsics: AICameraIntrinsics) {
        self.fx = intrinsics.fx
        self.fy = intrinsics.fy
        self.cx = intrinsics.cx
        self.cy = intrinsics.cy
    }

    func toAICameraIntrinsics() -> AICameraIntrinsics {
        return AICameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy)
    }
}

/// Wrapper for pose data file with metadata
struct AIPoseDataFile: Codable {
    let sessionId: String
    let frameCount: Int
    let captureDate: Date
    let frames: [AIPoseFrame]

    /// Create from session manager export
    static func from(sessionId: String, poses: [(timestamp: TimeInterval, pose: AIPose)]) -> AIPoseDataFile {
        let frames = poses.map { AIPoseFrame(timestamp: $0.timestamp, pose: $0.pose) }
        return AIPoseDataFile(
            sessionId: sessionId,
            frameCount: frames.count,
            captureDate: Date(),
            frames: frames
        )
    }
}

// MARK: - Photo Pose File

/// Pose data for a single photo
struct AIPhotoPoseFile: Codable {
    let photoIndex: Int
    let timestamp: TimeInterval
    let pose: AIPoseFrame
}

// MARK: - Session Metadata

/// Extended session metadata for persistence
struct AISessionMetadataFile: Codable {
    let sessionId: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let startTimestamp: Date
    var endTimestamp: Date?
    var videoDuration: TimeInterval?
    var photoCount: Int
    var persistenceState: String
    var qualityMetrics: AIQualityMetrics?

    static func create(sessionId: String) -> AISessionMetadataFile {
        return AISessionMetadataFile(
            sessionId: sessionId,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            startTimestamp: Date(),
            endTimestamp: nil,
            videoDuration: nil,
            photoCount: 0,
            persistenceState: AISessionPersistenceState.none.rawValue,
            qualityMetrics: nil
        )
    }
}

// MARK: - Session Persistence State (Task 3)

/// State of session data persistence
enum AISessionPersistenceState: String, Codable {
    case none = "none"              // No data saved yet
    case videoOnly = "videoOnly"    // Video saved, photos pending
    case complete = "complete"      // All data saved
}

// MARK: - Capture Data Manager Errors

enum AICaptureDataError: LocalizedError {
    case sessionNotStarted
    case directoryCreationFailed
    case videoSaveFailed(Error)
    case poseSaveFailed(Error)
    case photoSaveFailed(Error)
    case metadataSaveFailed(Error)
    case sessionNotFound
    case dataCorrupted(String)
    case fileOperationTimeout

    var errorDescription: String? {
        switch self {
        case .sessionNotStarted:
            return "No capture session has been started"
        case .directoryCreationFailed:
            return "Failed to create session directory"
        case .videoSaveFailed(let error):
            return "Failed to save video: \(error.localizedDescription)"
        case .poseSaveFailed(let error):
            return "Failed to save pose data: \(error.localizedDescription)"
        case .photoSaveFailed(let error):
            return "Failed to save photo: \(error.localizedDescription)"
        case .metadataSaveFailed(let error):
            return "Failed to save metadata: \(error.localizedDescription)"
        case .sessionNotFound:
            return "Session not found"
        case .dataCorrupted(let reason):
            return "Session data corrupted: \(reason)"
        case .fileOperationTimeout:
            return "File operation timed out"
        }
    }
}

// MARK: - Validation Result (Task 6)

/// Result of session data validation
struct AISessionValidationResult {
    let isValid: Bool
    let issues: [AIValidationIssue]

    var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .blocking }
    }

    static let valid = AISessionValidationResult(isValid: true, issues: [])
}

struct AIValidationIssue {
    enum Severity {
        case warning    // Can proceed but may affect quality
        case blocking   // Cannot proceed with processing
    }

    let severity: Severity
    let description: String
    let affectedFile: String?
}

// MARK: - AI Capture Data Manager (Task 1)

/// Manages persistent storage of capture session data.
/// Handles video, poses, photos, and metadata with resilience to interruptions.
///
/// **Directory Structure:**
/// ```
/// Documents/AIFlowCaptures/
/// ├── session_{timestamp}/
/// │   ├── metadata.json
/// │   ├── video.mp4
/// │   ├── poses.json
/// │   ├── photo_0.jpg
/// │   ├── photo_0_pose.json
/// │   └── ...
/// ```
///
/// **Usage:**
/// 1. Call `startSession()` to create a new session directory
/// 2. Call `saveVideo()` when video recording completes
/// 3. Call `savePoseData()` to persist pose frames
/// 4. Call `savePhotoWithPose()` for each captured photo
/// 5. Call `finalizeSession()` when capture is complete
/// 6. Use `cleanupOldSessions()` to manage disk space
class AICaptureDataManager {

    // MARK: - Constants

    /// Base directory name for captures
    private static let capturesDirectoryName = "AIFlowCaptures"

    /// Maximum number of sessions to keep
    private static let maxSessionsToKeep = 3

    /// File operation timeout in seconds
    private static let fileOperationTimeout: TimeInterval = 10.0

    // MARK: - Properties

    /// Lock for thread-safe access to session properties (Issue #1 fix)
    private let sessionLock = NSLock()

    /// Current session ID (thread-safe via sessionLock)
    private var _currentSessionId: String?
    var currentSessionId: String? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _currentSessionId
    }

    /// Current session directory URL (thread-safe via sessionLock)
    private var _currentSessionDirectory: URL?
    var currentSessionDirectory: URL? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _currentSessionDirectory
    }

    /// Thread-safe setter for session properties
    private func setCurrentSession(id: String?, directory: URL?) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        _currentSessionId = id
        _currentSessionDirectory = directory
    }

    /// File manager instance
    private let fileManager = FileManager.default

    /// JSON encoder configured for pretty printing
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// JSON decoder
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Serial queue for file operations
    private let fileQueue = DispatchQueue(label: "com.cabinetscan.aiflow.capturedata", qos: .userInitiated)

    /// Callback for session recovery prompt
    var onRecoverableSessionFound: ((String, AISessionPersistenceState) -> Void)?

    // MARK: - Initialization

    init() {
        setupAppLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - App Lifecycle (Task 8)

    /// Setup observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Save current session state when app backgrounds
    @objc private func handleAppWillResignActive() {
        guard let sessionId = currentSessionId else { return }

        do {
            // Save current session state to metadata
            var metadata = try loadMetadata(for: sessionId)
            // Mark as interrupted if not complete
            if metadata.persistenceState != AISessionPersistenceState.complete.rawValue {
                try saveMetadata(metadata)
            }
            print("[AICaptureDataManager] Session state saved for backgrounding: \(sessionId)")
        } catch {
            print("[AICaptureDataManager] Failed to save session state for backgrounding: \(error)")
        }
    }

    /// Check for recoverable sessions when app returns to foreground
    @objc private func handleAppDidBecomeActive() {
        // Only check if we don't have an active session
        guard currentSessionId == nil else { return }

        let recoverableSessions = findRecoverableSessions()
        if let (sessionId, state) = recoverableSessions.first {
            print("[AICaptureDataManager] Found recoverable session: \(sessionId) in state: \(state)")
            onRecoverableSessionFound?(sessionId, state)
        }
    }

    // MARK: - Directory Management

    /// Get the base captures directory URL
    private var capturesBaseDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent(Self.capturesDirectoryName)
    }

    /// Create the base captures directory if it doesn't exist
    private func ensureBaseDirectoryExists() throws {
        if !fileManager.fileExists(atPath: capturesBaseDirectory.path) {
            try fileManager.createDirectory(at: capturesBaseDirectory, withIntermediateDirectories: true)
            print("[AICaptureDataManager] Created base captures directory")
        }
    }

    // MARK: - Session Lifecycle (Task 1.3)

    /// Start a new capture session
    /// - Returns: The session ID for the new session
    @discardableResult
    func startSession() throws -> String {
        // Generate session ID with timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        let sessionId = "session_\(timestamp)"

        // Ensure base directory exists
        try ensureBaseDirectoryExists()

        // Create session directory
        let sessionDir = capturesBaseDirectory.appendingPathComponent(sessionId)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        // Store current session (thread-safe)
        setCurrentSession(id: sessionId, directory: sessionDir)

        // Create initial metadata file
        let metadata = AISessionMetadataFile.create(sessionId: sessionId)
        try saveMetadata(metadata)

        print("[AICaptureDataManager] Started session: \(sessionId)")
        return sessionId
    }

    /// Finalize the current session
    /// - Parameter videoDuration: Total video duration in seconds
    func finalizeSession(videoDuration: TimeInterval, photoCount: Int, qualityMetrics: AIQualityMetrics?) throws {
        guard let sessionId = currentSessionId else {
            throw AICaptureDataError.sessionNotStarted
        }

        // Update metadata
        var metadata = try loadMetadata(for: sessionId)
        metadata.endTimestamp = Date()
        metadata.videoDuration = videoDuration
        metadata.photoCount = photoCount
        metadata.persistenceState = AISessionPersistenceState.complete.rawValue
        metadata.qualityMetrics = qualityMetrics
        try saveMetadata(metadata)

        print("[AICaptureDataManager] Finalized session: \(sessionId)")
    }

    /// Cancel and cleanup the current session
    func cancelSession() {
        guard let sessionDir = currentSessionDirectory else { return }

        // Remove session directory
        try? fileManager.removeItem(at: sessionDir)

        // Clear session state (thread-safe)
        setCurrentSession(id: nil, directory: nil)

        print("[AICaptureDataManager] Cancelled and cleaned up current session")
    }

    /// Discard the current session and reset state
    /// Per Story 6.7 - Task 6.4
    func discardSession() {
        cancelSession()
        print("[AICaptureDataManager] Session discarded")
    }

    // MARK: - Timeout Data Preservation (Story 6.8 Task 6)

    /// Save session for later retry after timeout cancellation.
    ///
    /// **Per Story 6.8 AC4:**
    /// User selects "Cancel" → captured data is saved for potential later use
    ///
    /// **Per ADR-2:**
    /// Only serialize checkpoint to disk when user selects "Cancel" for "save for later"
    ///
    /// - Parameters:
    ///   - videoDuration: Duration of video captured so far
    ///   - photoCount: Number of photos captured
    ///   - checkpoint: Pipeline checkpoint with progress state (optional)
    ///   - qualityMetrics: Quality metrics (if available)
    /// - Returns: The saved session data with timeout marker
    @discardableResult
    func saveSessionForLater(
        videoDuration: TimeInterval,
        photoCount: Int,
        checkpoint: PipelineCheckpoint?,
        qualityMetrics: AIQualityMetrics?
    ) throws -> AICaptureSessionData {
        guard let sessionId = currentSessionId,
              let sessionDir = currentSessionDirectory else {
            throw AICaptureDataError.sessionNotStarted
        }

        // Task 6.2: Serialize checkpoint to disk if present
        if let checkpoint = checkpoint {
            let checkpointURL = sessionDir.appendingPathComponent("checkpoint.json")
            do {
                let data = try jsonEncoder.encode(checkpoint)
                try data.write(to: checkpointURL)
                print("[AICaptureDataManager] Checkpoint saved: \(checkpoint.description)")
            } catch {
                // Log but don't fail - checkpoint is optional for recovery
                print("[AICaptureDataManager] Failed to save checkpoint: \(error)")
            }
        }

        // Task 6.3: Update metadata with timeoutCancelled marker
        var metadata = try loadMetadata(for: sessionId)
        metadata.endTimestamp = Date()
        metadata.videoDuration = videoDuration
        metadata.photoCount = photoCount
        // Mark as timeout cancelled with checkpoint phase info
        metadata.persistenceState = "timeoutCancelled:\(checkpoint?.phase.rawValue ?? "none")"
        metadata.qualityMetrics = qualityMetrics
        try saveMetadata(metadata)

        // Check for video
        let videoURL = sessionDir.appendingPathComponent("video.mp4")
        let hasVideo = fileManager.fileExists(atPath: videoURL.path)

        // Load photos
        var photos: [AICapturedPhoto] = []
        for i in 0..<photoCount {
            let photoURL = sessionDir.appendingPathComponent("photo_\(i).jpg")
            let poseURL = sessionDir.appendingPathComponent("photo_\(i)_pose.json")

            if fileManager.fileExists(atPath: photoURL.path),
               fileManager.fileExists(atPath: poseURL.path),
               let poseData = try? Data(contentsOf: poseURL),
               let photoPose = try? jsonDecoder.decode(AIPhotoPoseFile.self, from: poseData),
               let transform = photoPose.pose.toTransformMatrix() {

                let pose = AIPose(
                    transform: transform,
                    intrinsics: photoPose.pose.intrinsics.toAICameraIntrinsics(),
                    trackingState: .normal,
                    zoomFactor: photoPose.pose.zoomFactor
                )
                photos.append(AICapturedPhoto(url: photoURL, pose: pose, timestamp: photoPose.timestamp))
            }
        }

        let captureMetadata = AICaptureMetadata(
            deviceModel: metadata.deviceModel,
            osVersion: metadata.osVersion,
            captureDate: metadata.startTimestamp,
            videoDuration: videoDuration,
            photoCount: photoCount,
            averageLighting: nil
        )

        let sessionData = AICaptureSessionData(
            videoURL: hasVideo ? videoURL : nil,
            photos: photos,
            metadata: captureMetadata,
            qualityMetrics: qualityMetrics
        )

        print("[AICaptureDataManager] Session saved for later retry: \(sessionId), checkpoint: \(checkpoint?.description ?? "none")")
        return sessionData
    }

    /// Check if a session was cancelled due to timeout and can be resumed.
    ///
    /// - Parameter sessionId: The session ID to check
    /// - Returns: The checkpoint if session was timeout-cancelled and has checkpoint, nil otherwise
    func getTimeoutCheckpoint(for sessionId: String) -> PipelineCheckpoint? {
        let sessionDir = capturesBaseDirectory.appendingPathComponent(sessionId)
        let checkpointURL = sessionDir.appendingPathComponent("checkpoint.json")

        guard fileManager.fileExists(atPath: checkpointURL.path),
              let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? jsonDecoder.decode(PipelineCheckpoint.self, from: data) else {
            return nil
        }

        return checkpoint
    }

    /// Find sessions that were cancelled due to timeout (for recovery prompt).
    ///
    /// - Returns: Array of session IDs that were timeout-cancelled
    func findTimeoutCancelledSessions() -> [String] {
        do {
            try ensureBaseDirectoryExists()

            let contents = try fileManager.contentsOfDirectory(
                at: capturesBaseDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var timeoutSessions: [String] = []

            for sessionDir in contents where sessionDir.lastPathComponent.hasPrefix("session_") {
                let sessionId = sessionDir.lastPathComponent
                if let metadata = try? loadMetadata(for: sessionId),
                   metadata.persistenceState.hasPrefix("timeoutCancelled") {
                    timeoutSessions.append(sessionId)
                }
            }

            return timeoutSessions
        } catch {
            print("[AICaptureDataManager] Failed to find timeout-cancelled sessions: \(error)")
            return []
        }
    }

    /// Save partial session data when tracking fails
    /// Per Story 6.7 - Task 6.1, 6.2
    /// - Parameters:
    ///   - videoDuration: Duration of video captured so far
    ///   - photoCount: Number of photos captured
    ///   - qualityMetrics: Quality metrics (if available)
    ///   - coverageState: Coverage state for partial capture handling
    /// - Returns: The saved session data
    @discardableResult
    func savePartialSession(
        videoDuration: TimeInterval,
        photoCount: Int,
        qualityMetrics: AIQualityMetrics?,
        coverageState: AICoverageState?
    ) throws -> AICaptureSessionData {
        guard let sessionId = currentSessionId,
              let sessionDir = currentSessionDirectory else {
            throw AICaptureDataError.sessionNotStarted
        }

        // Update metadata to mark as partial
        var metadata = try loadMetadata(for: sessionId)
        metadata.endTimestamp = Date()
        metadata.videoDuration = videoDuration
        metadata.photoCount = photoCount
        metadata.persistenceState = AISessionPersistenceState.complete.rawValue
        metadata.qualityMetrics = qualityMetrics
        try saveMetadata(metadata)

        // Check for video
        let videoURL = sessionDir.appendingPathComponent("video.mp4")
        let hasVideo = fileManager.fileExists(atPath: videoURL.path)

        // Load photos
        var photos: [AICapturedPhoto] = []
        for i in 0..<photoCount {
            let photoURL = sessionDir.appendingPathComponent("photo_\(i).jpg")
            let poseURL = sessionDir.appendingPathComponent("photo_\(i)_pose.json")

            if fileManager.fileExists(atPath: photoURL.path),
               fileManager.fileExists(atPath: poseURL.path),
               let poseData = try? Data(contentsOf: poseURL),
               let photoPose = try? jsonDecoder.decode(AIPhotoPoseFile.self, from: poseData),
               let transform = photoPose.pose.toTransformMatrix() {

                let pose = AIPose(
                    transform: transform,
                    intrinsics: photoPose.pose.intrinsics.toAICameraIntrinsics(),
                    trackingState: .normal,
                    zoomFactor: photoPose.pose.zoomFactor
                )
                photos.append(AICapturedPhoto(url: photoURL, pose: pose, timestamp: photoPose.timestamp))
            }
        }

        // Create capture session data with partial coverage state
        let captureMetadata = AICaptureMetadata(
            deviceModel: metadata.deviceModel,
            osVersion: metadata.osVersion,
            captureDate: metadata.startTimestamp,
            videoDuration: videoDuration,
            photoCount: photoCount,
            averageLighting: nil
        )

        var sessionData = AICaptureSessionData(
            videoURL: hasVideo ? videoURL : nil,
            photos: photos,
            metadata: captureMetadata,
            qualityMetrics: qualityMetrics
        )

        // Mark as partial via coverage state (Story 6.2 handles display)
        sessionData.coverageState = coverageState

        print("[AICaptureDataManager] Partial session saved: \(sessionId), video: \(hasVideo), photos: \(photoCount)")
        return sessionData
    }

    // MARK: - Timeout Helper (Issue #2 fix)

    /// Execute an async operation with timeout protection
    /// - Parameters:
    ///   - seconds: Timeout in seconds
    ///   - operation: The async operation to execute
    /// - Returns: Result of the operation
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AICaptureDataError.fileOperationTimeout
            }

            guard let result = try await group.next() else {
                throw AICaptureDataError.fileOperationTimeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Video Persistence (Task 1.4)

    /// Save video file to session directory
    /// - Parameter sourceURL: URL of the recorded video file
    /// - Returns: URL of the saved video in session directory
    func saveVideo(from sourceURL: URL) async throws -> URL {
        guard let sessionDir = currentSessionDirectory,
              let sessionId = currentSessionId else {
            throw AICaptureDataError.sessionNotStarted
        }

        let destinationURL = sessionDir.appendingPathComponent("video.mp4")

        // Wrap file operation with timeout protection (Issue #2 fix)
        return try await withTimeout(seconds: Self.fileOperationTimeout) { [weak self] in
            guard let self = self else {
                throw AICaptureDataError.sessionNotStarted
            }

            return try await withCheckedThrowingContinuation { continuation in
                self.fileQueue.async {
                    do {
                        // Remove existing file if present
                        if self.fileManager.fileExists(atPath: destinationURL.path) {
                            try self.fileManager.removeItem(at: destinationURL)
                        }

                        // Copy video to session directory (move would fail across volumes)
                        try self.fileManager.copyItem(at: sourceURL, to: destinationURL)

                        // Update metadata
                        var metadata = try self.loadMetadata(for: sessionId)
                        metadata.persistenceState = AISessionPersistenceState.videoOnly.rawValue
                        try self.saveMetadata(metadata)

                        print("[AICaptureDataManager] Video saved: \(destinationURL.lastPathComponent)")
                        continuation.resume(returning: destinationURL)
                    } catch {
                        print("[AICaptureDataManager] Failed to save video: \(error)")
                        continuation.resume(throwing: AICaptureDataError.videoSaveFailed(error))
                    }
                }
            }
        }
    }

    // MARK: - Pose Data Persistence (Task 1.5)

    /// Save pose data to session directory as JSON
    /// - Parameter poses: Array of timestamped poses from AR session
    /// - Returns: URL of the saved poses file
    func savePoseData(_ poses: [(timestamp: TimeInterval, pose: AIPose)]) throws -> URL {
        guard let sessionDir = currentSessionDirectory,
              let sessionId = currentSessionId else {
            throw AICaptureDataError.sessionNotStarted
        }

        let poseFile = AIPoseDataFile.from(sessionId: sessionId, poses: poses)
        let poseURL = sessionDir.appendingPathComponent("poses.json")

        do {
            let data = try jsonEncoder.encode(poseFile)
            try data.write(to: poseURL)
            print("[AICaptureDataManager] Pose data saved: \(poseFile.frameCount) frames")
            return poseURL
        } catch {
            throw AICaptureDataError.poseSaveFailed(error)
        }
    }

    /// Save pose data from exported dictionary (for backward compatibility)
    /// - Parameter exportedData: Dictionary from AIARSessionManager.exportPoseData()
    /// - Returns: URL of the saved poses file
    func savePoseDataFromExport(_ exportedData: [String: Any]) throws -> URL {
        guard let sessionDir = currentSessionDirectory,
              let sessionId = currentSessionId else {
            throw AICaptureDataError.sessionNotStarted
        }

        let poseURL = sessionDir.appendingPathComponent("poses.json")

        do {
            // Wrap with session metadata
            var dataWithMetadata = exportedData
            dataWithMetadata["sessionId"] = sessionId
            dataWithMetadata["captureDate"] = ISO8601DateFormatter().string(from: Date())

            let jsonData = try JSONSerialization.data(withJSONObject: dataWithMetadata, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: poseURL)

            let poseCount = exportedData["poseCount"] as? Int ?? 0
            print("[AICaptureDataManager] Pose data saved from export: \(poseCount) frames")
            return poseURL
        } catch {
            throw AICaptureDataError.poseSaveFailed(error)
        }
    }

    // MARK: - Photo Persistence (Task 5)

    /// Save photo pose data alongside the photo
    /// - Parameters:
    ///   - photoURL: URL of the already-saved photo
    ///   - pose: Camera pose at capture time
    ///   - index: Photo index (0-4)
    func savePhotoPose(for photoURL: URL, pose: AIPose, index: Int, timestamp: TimeInterval) throws {
        guard let sessionDir = currentSessionDirectory else {
            throw AICaptureDataError.sessionNotStarted
        }

        let poseFrame = AIPoseFrame(timestamp: timestamp, pose: pose)
        let photoPose = AIPhotoPoseFile(photoIndex: index, timestamp: timestamp, pose: poseFrame)

        let poseURL = sessionDir.appendingPathComponent("photo_\(index)_pose.json")

        do {
            let data = try jsonEncoder.encode(photoPose)
            try data.write(to: poseURL)
            print("[AICaptureDataManager] Photo \(index) pose saved")
        } catch {
            throw AICaptureDataError.photoSaveFailed(error)
        }
    }

    /// Copy photo to session directory with standardized name
    /// - Parameters:
    ///   - sourceURL: URL of the captured photo
    ///   - index: Photo index (0-4)
    /// - Returns: URL of the photo in session directory
    func copyPhotoToSession(from sourceURL: URL, index: Int) throws -> URL {
        guard let sessionDir = currentSessionDirectory else {
            throw AICaptureDataError.sessionNotStarted
        }

        let destinationURL = sessionDir.appendingPathComponent("photo_\(index).jpg")

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        // Copy photo
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        print("[AICaptureDataManager] Photo \(index) copied to session")
        return destinationURL
    }

    // MARK: - Metadata Management (Task 7)

    /// Save metadata to session directory
    private func saveMetadata(_ metadata: AISessionMetadataFile) throws {
        guard let sessionDir = currentSessionDirectory else {
            throw AICaptureDataError.sessionNotStarted
        }

        let metadataURL = sessionDir.appendingPathComponent("metadata.json")

        do {
            let data = try jsonEncoder.encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            throw AICaptureDataError.metadataSaveFailed(error)
        }
    }

    /// Load metadata for a session
    private func loadMetadata(for sessionId: String) throws -> AISessionMetadataFile {
        let sessionDir = capturesBaseDirectory.appendingPathComponent(sessionId)
        let metadataURL = sessionDir.appendingPathComponent("metadata.json")

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw AICaptureDataError.sessionNotFound
        }

        let data = try Data(contentsOf: metadataURL)
        return try jsonDecoder.decode(AISessionMetadataFile.self, from: data)
    }

    // MARK: - Session Cleanup (Task 1.6, 1.7)

    /// Clean up old sessions, keeping only the most recent ones
    /// - Parameter keepLatest: Number of sessions to keep (default: 3)
    func cleanupOldSessions(keepLatest: Int = 3) {
        do {
            // Get all session directories
            let contents = try fileManager.contentsOfDirectory(
                at: capturesBaseDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Filter to session directories only
            let sessionDirs = contents.filter { $0.lastPathComponent.hasPrefix("session_") }

            // Sort by creation date (newest first)
            let sorted = sessionDirs.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }

            // Remove sessions beyond keepLatest (excluding current session)
            let toRemove = sorted.dropFirst(keepLatest).filter { $0.lastPathComponent != currentSessionId }

            for sessionDir in toRemove {
                try fileManager.removeItem(at: sessionDir)
                print("[AICaptureDataManager] Cleaned up old session: \(sessionDir.lastPathComponent)")
            }

            if !toRemove.isEmpty {
                print("[AICaptureDataManager] Cleaned up \(toRemove.count) old sessions")
            }
        } catch {
            print("[AICaptureDataManager] Failed to cleanup sessions: \(error)")
        }
    }

    // MARK: - Session Recovery (Task 3)

    /// Find any incomplete sessions that can be recovered
    /// - Returns: Array of recoverable session IDs with their persistence state
    func findRecoverableSessions() -> [(sessionId: String, state: AISessionPersistenceState)] {
        do {
            try ensureBaseDirectoryExists()

            let contents = try fileManager.contentsOfDirectory(
                at: capturesBaseDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var recoverable: [(String, AISessionPersistenceState)] = []

            for sessionDir in contents where sessionDir.lastPathComponent.hasPrefix("session_") {
                let sessionId = sessionDir.lastPathComponent
                if let metadata = try? loadMetadata(for: sessionId),
                   let state = AISessionPersistenceState(rawValue: metadata.persistenceState),
                   state != .complete {
                    recoverable.append((sessionId, state))
                }
            }

            return recoverable
        } catch {
            print("[AICaptureDataManager] Failed to find recoverable sessions: \(error)")
            return []
        }
    }

    /// Recover a session by its ID
    /// - Parameter sessionId: The session ID to recover
    /// - Returns: Recovered session data, or nil if not recoverable
    func recoverSession(sessionId: String) -> AICaptureSessionData? {
        let sessionDir = capturesBaseDirectory.appendingPathComponent(sessionId)

        guard fileManager.fileExists(atPath: sessionDir.path) else {
            return nil
        }

        // Check for video
        let videoURL = sessionDir.appendingPathComponent("video.mp4")
        let hasVideo = fileManager.fileExists(atPath: videoURL.path)

        // Load photos
        var photos: [AICapturedPhoto] = []
        for i in 0..<5 {
            let photoURL = sessionDir.appendingPathComponent("photo_\(i).jpg")
            let poseURL = sessionDir.appendingPathComponent("photo_\(i)_pose.json")

            if fileManager.fileExists(atPath: photoURL.path),
               fileManager.fileExists(atPath: poseURL.path),
               let poseData = try? Data(contentsOf: poseURL),
               let photoPose = try? jsonDecoder.decode(AIPhotoPoseFile.self, from: poseData),
               let transform = photoPose.pose.toTransformMatrix() {

                let pose = AIPose(
                    transform: transform,
                    intrinsics: photoPose.pose.intrinsics.toAICameraIntrinsics(),
                    trackingState: .normal,
                    zoomFactor: photoPose.pose.zoomFactor
                )
                photos.append(AICapturedPhoto(url: photoURL, pose: pose, timestamp: photoPose.timestamp))
            }
        }

        // Load metadata
        let metadata: AICaptureMetadata?
        if let metadataFile = try? loadMetadata(for: sessionId) {
            metadata = AICaptureMetadata(
                deviceModel: metadataFile.deviceModel,
                osVersion: metadataFile.osVersion,
                captureDate: metadataFile.startTimestamp,
                videoDuration: metadataFile.videoDuration ?? 0,
                photoCount: photos.count,
                averageLighting: nil
            )
        } else {
            metadata = nil
        }

        // Verify directory still exists before setting as current (Issue #4 fix)
        guard fileManager.fileExists(atPath: sessionDir.path) else {
            print("[AICaptureDataManager] Session directory no longer exists during recovery")
            return nil
        }

        // Set as current session for continuation (thread-safe)
        setCurrentSession(id: sessionId, directory: sessionDir)

        return AICaptureSessionData(
            videoURL: hasVideo ? videoURL : nil,
            photos: photos,
            metadata: metadata,
            qualityMetrics: nil
        )
    }

    // MARK: - Data Validation (Task 6)

    /// Validate session data integrity before processing
    /// - Parameter data: The capture session data to validate
    /// - Returns: Validation result with any issues found
    func validateSessionData(_ data: AICaptureSessionData) -> AISessionValidationResult {
        var issues: [AIValidationIssue] = []

        // Check video file
        if let videoURL = data.videoURL {
            if !fileManager.fileExists(atPath: videoURL.path) {
                issues.append(AIValidationIssue(
                    severity: .blocking,
                    description: "Video file not found",
                    affectedFile: videoURL.lastPathComponent
                ))
            } else {
                // Check video size (should be > 100KB for a valid recording)
                if let attrs = try? fileManager.attributesOfItem(atPath: videoURL.path),
                   let size = attrs[.size] as? Int64,
                   size < 100_000 {
                    issues.append(AIValidationIssue(
                        severity: .blocking,
                        description: "Video file too small (\(size) bytes), may be corrupted",
                        affectedFile: videoURL.lastPathComponent
                    ))
                }
            }
        } else {
            issues.append(AIValidationIssue(
                severity: .blocking,
                description: "No video file in session data",
                affectedFile: nil
            ))
        }

        // Check photo count
        if data.photos.count < AICaptureSessionData.minimumPhotoCount {
            issues.append(AIValidationIssue(
                severity: .blocking,
                description: "Insufficient photos: \(data.photos.count)/\(AICaptureSessionData.minimumPhotoCount)",
                affectedFile: nil
            ))
        }

        // Check each photo
        for (index, photo) in data.photos.enumerated() {
            if !fileManager.fileExists(atPath: photo.url.path) {
                issues.append(AIValidationIssue(
                    severity: .blocking,
                    description: "Photo \(index) file not found",
                    affectedFile: photo.url.lastPathComponent
                ))
            }
        }

        // Check pose data file if session directory is known
        if let sessionDir = currentSessionDirectory {
            let poseURL = sessionDir.appendingPathComponent("poses.json")
            if !fileManager.fileExists(atPath: poseURL.path) {
                issues.append(AIValidationIssue(
                    severity: .warning,
                    description: "Pose data file not found",
                    affectedFile: "poses.json"
                ))
            }
        }

        let isValid = !issues.contains { $0.severity == .blocking }
        return AISessionValidationResult(isValid: isValid, issues: issues)
    }

    // MARK: - Utility Methods

    /// Get the current session directory URL
    func getSessionDirectory() -> URL? {
        return currentSessionDirectory
    }

    /// Check if a session is currently active
    var hasActiveSession: Bool {
        return currentSessionId != nil
    }
}
