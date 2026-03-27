//
//  AIARSessionManager.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import ARKit
import Combine
import simd

// MARK: - AI AR Frame Delegate

/// Protocol for receiving ARFrame updates from the AR session.
/// Used by AIVideoCapture to record frames via AVAssetWriter.
protocol AIARFrameDelegate: AnyObject {
    func arSessionManager(_ manager: AIARSessionManager, didUpdateFrame frame: ARFrame)
}

// MARK: - AI AR Session Manager

/// Manages ARKit session for camera pose tracking during AI flow capture.
/// Provides 60Hz pose data for video frame synchronization and reconstruction.
///
/// **Usage:**
/// 1. Create instance and observe `isReadyForCapture`
/// 2. Call `startSession()` to begin tracking
/// 3. Wait for `isReadyForCapture == true` before starting video recording
/// 4. Use `getPoseAt(timestamp:)` to sync poses with video frames
/// 5. Call `stopSession()` when capture completes
///
/// **Threading Model (ADR-003):**
/// - Poses stored via dedicated serial queue for thread safety
/// - Only state CHANGES dispatched to main thread
/// - Use `poseQueue` for thread-safe pose history access
class AIARSessionManager: NSObject, ObservableObject {

    // MARK: - Published Properties (ADR-006: Only rarely-changing state)

    /// Current ARKit tracking state
    @Published private(set) var trackingState: AITrackingState = .notAvailable

    /// Whether session is ready for video capture (tracking achieved .normal at least once)
    @Published private(set) var isReadyForCapture: Bool = false

    /// Whether session is currently interrupted (app backgrounded, phone call, etc.)
    @Published private(set) var isInterrupted: Bool = false

    /// Fatal session error, if any
    @Published private(set) var sessionError: Error?

    // MARK: - Tracking Recovery Properties (Story 6.7)

    /// Detailed tracking recovery state with reason information
    /// Per Story 6.7 - Task 1.2, 1.3
    @Published private(set) var trackingRecoveryState: TrackingRecoveryState = .normal

    /// Current tracking limited reason (if applicable)
    /// Per Story 6.7 - Task 1.1
    @Published private(set) var trackingLimitedReason: TrackingLimitedReason?

    // MARK: - Publishers

    /// Pose update events for guidance system (timestamp, pose)
    /// Published at 60Hz during active tracking for real-time guidance
    let poseUpdatePublisher = PassthroughSubject<(timestamp: TimeInterval, pose: AIPose), Never>()

    /// Tracking recovery state changes publisher
    /// Per Story 6.7 - Task 1.3
    let trackingRecoveryPublisher = PassthroughSubject<TrackingRecoveryState, Never>()

    // MARK: - Frame Delegate

    /// Delegate for receiving ARFrame updates (one consumer at a time)
    weak var frameDelegate: AIARFrameDelegate?

    // MARK: - ARKit Session

    /// The ARKit session instance
    private let session = ARSession()

    /// Read-only access to the ARSession for ARSCNView preview
    var arSession: ARSession { session }

    /// Dedicated delegate queue for ARKit callbacks (ADR-003)
    private let delegateQueue = DispatchQueue(label: "com.cabinetscan.arkit.delegate", qos: .userInteractive)

    // MARK: - Pose Storage (ADR-002)

    /// Serial queue for thread-safe pose history access
    private let poseQueue = DispatchQueue(label: "com.cabinetscan.aiflow.poseHistory")

    /// Pose history with timestamps for frame synchronization (accessed only via poseQueue)
    private var _poseHistory: [(timestamp: TimeInterval, pose: AIPose)] = []

    /// Maximum pose count (120 seconds at 60Hz)
    private let maxPoseCount = 7200

    /// Batch size for trimming (avoids O(n) removeFirst() calls)
    private let trimBatchSize = 1000

    /// Timestamp tolerance for pose lookup (50ms)
    private let poseTimestampTolerance: TimeInterval = 0.050

    // MARK: - State Tracking

    /// Last published tracking state (to avoid redundant dispatches) - accessed from delegate queue
    private var _lastPublishedState: AITrackingState = .notAvailable

    /// Whether tracking has ever achieved .normal state
    private var _hasEverBeenReady = false

    /// Current zoom factor (for reconstruction pipeline)
    private var _currentZoomFactor: CGFloat = 1.0

    /// Most recent pose (for getCurrentPose())
    private var _latestPose: AIPose?

    /// Lock for state tracking properties
    private let stateLock = NSLock()

    // MARK: - Tracking Recovery State (Story 6.7)

    /// Last good pose before tracking was lost
    /// Per Story 6.7 - Task 1.5
    private var _lastGoodPose: AIPose?

    /// Timer for recovery timeout (10 seconds)
    /// Per Story 6.7 - Task 1.4
    private var recoveryTimer: Timer?

    /// Time when tracking was lost (for elapsed calculation)
    private var _trackingLostTime: Date?

    /// Recovery timeout duration in seconds
    private static let recoveryTimeoutDuration: TimeInterval = 10.0

    /// Last published recovery state (to avoid redundant dispatches)
    private var _lastPublishedRecoveryState: TrackingRecoveryState = .normal

    // MARK: - Plane Detection (Server Pipeline V2)

    /// Detected ARKit plane anchors, keyed by identifier for deduplication.
    /// Updated on delegate queue, exported via `exportPlanesJSON()`.
    private var _detectedPlanes: [UUID: ARPlaneAnchor] = [:]

    /// Serial queue for thread-safe plane access
    private let planeQueue = DispatchQueue(label: "com.cabinetscan.aiflow.planeHistory")

    /// Number of currently detected planes (observable, updated on main thread)
    @Published private(set) var detectedPlaneCount: Int = 0

    // MARK: - App Lifecycle Observers

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = delegateQueue
        setupAppLifecycleObservers()
    }

    deinit {
        // Clean up session when manager is deallocated
        session.pause()
    }

    // MARK: - Session Control

    /// Start the ARKit session with battery-optimized configuration (ADR-001)
    func startSession() {
        // Reset state
        stateLock.lock()
        _hasEverBeenReady = false
        _lastPublishedState = .notAvailable
        _latestPose = nil
        _lastGoodPose = nil
        _trackingLostTime = nil
        _lastPublishedRecoveryState = .normal
        stateLock.unlock()

        // Cancel any existing recovery timer
        cancelRecoveryTimer()

        DispatchQueue.main.async { [weak self] in
            self?.isReadyForCapture = false
            self?.isInterrupted = false
            self?.sessionError = nil
            self?.trackingState = .notAvailable
            self?.trackingRecoveryState = .normal
            self?.trackingLimitedReason = nil
        }

        // Clear pose history and planes
        poseQueue.async { [weak self] in
            self?._poseHistory.removeAll()
        }
        planeQueue.async { [weak self] in
            self?._detectedPlanes.removeAll()
            DispatchQueue.main.async { self?.detectedPlaneCount = 0 }
        }

        // Configure ARKit (ADR-001: Battery-optimized settings)
        let configuration = ARWorldTrackingConfiguration()

        // ADR-001: Use .gravity (NOT .gravityAndHeading)
        // Reason: .gravityAndHeading requires magnetometer calibration which:
        // - Drains battery faster
        // - Can cause tracking hiccups during calibration
        // - We don't need compass direction for depth reconstruction
        configuration.worldAlignment = .gravity

        configuration.isAutoFocusEnabled = true

        // Server Pipeline V2: Enable plane detection for wall measurement
        // Vertical planes → wall segments, horizontal planes → floor/countertop reference
        configuration.planeDetection = [.horizontal, .vertical]
        // Note: environmentTexturing left at default (automatic) as .none is deprecated
        // Note: sceneReconstruction left at default as .none is unavailable - it's LiDAR-only anyway
        configuration.frameSemantics = []           // No body/person detection needed

        // Run session
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        print("[AIARSessionManager] Session started with plane detection enabled (horizontal + vertical)")
    }

    /// Pause the ARKit session (preserves tracking state for resume)
    func pauseSession() {
        session.pause()
        print("[AIARSessionManager] Session paused")
    }

    /// Stop the ARKit session and clean up resources
    func stopSession() {
        session.pause()

        // Cancel recovery timer (Story 6.7)
        cancelRecoveryTimer()

        // Clear pose history and planes
        poseQueue.async { [weak self] in
            self?._poseHistory.removeAll()
        }
        planeQueue.async { [weak self] in
            self?._detectedPlanes.removeAll()
            DispatchQueue.main.async { self?.detectedPlaneCount = 0 }
        }

        // Reset state
        stateLock.lock()
        _hasEverBeenReady = false
        _lastPublishedState = .notAvailable
        _latestPose = nil
        _lastGoodPose = nil
        _trackingLostTime = nil
        _lastPublishedRecoveryState = .normal
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.isReadyForCapture = false
            self?.trackingState = .notAvailable
            self?.trackingRecoveryState = .normal
            self?.trackingLimitedReason = nil
        }

        print("[AIARSessionManager] Session stopped and resources cleaned up")
    }

    // MARK: - Pose Access

    /// Get the current/latest pose (NOT @Published to avoid 60 updates/sec - ADR-006)
    func getCurrentPose() -> AIPose? {
        stateLock.lock()
        let pose = _latestPose
        stateLock.unlock()
        return pose
    }

    /// Get pose at specific timestamp with nearest-neighbor lookup (ADR-002)
    /// - Parameter timestamp: The video frame timestamp to find pose for
    /// - Returns: Nearest pose within 50ms tolerance, or nil if no valid pose exists
    func getPoseAt(timestamp: TimeInterval) -> AIPose? {
        poseQueue.sync {
            // Find nearest pose by timestamp
            guard let nearest = _poseHistory.min(by: {
                abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
            }) else { return nil }

            // Return nil if beyond tolerance (stale data indicator)
            if abs(nearest.timestamp - timestamp) > poseTimestampTolerance {
                return nil
            }
            return nearest.pose
        }
    }

    /// Export all pose data for JSON serialization
    /// Note: This creates a full copy in memory. For very long captures (>2min),
    /// consider using streaming export to avoid memory pressure.
    func exportPoseData() -> [String: Any] {
        return poseQueue.sync {
            var poses: [[String: Any]] = []

            for (timestamp, pose) in _poseHistory {
                let poseDict: [String: Any] = [
                    "timestamp": timestamp,
                    "transform": transformToArray(pose.transform),
                    "intrinsics": [
                        "fx": pose.intrinsics.fx,
                        "fy": pose.intrinsics.fy,
                        "cx": pose.intrinsics.cx,
                        "cy": pose.intrinsics.cy
                    ],
                    "trackingState": trackingStateToString(pose.trackingState),
                    "zoomFactor": pose.zoomFactor  // Per-pose zoom factor (ADR-005)
                ]
                poses.append(poseDict)
            }

            return [
                "poseCount": _poseHistory.count,
                "poses": poses
            ]
        }
    }

    // MARK: - Plane Export (Server Pipeline V2)

    /// Export all detected plane anchors as JSON data for server pipeline.
    /// Each plane includes identifier, alignment, center, extent, and 4x4 transform.
    /// - Returns: JSON-serialized Data containing an array of plane dictionaries
    func exportPlanesJSON() -> Data {
        return planeQueue.sync {
            let planes = _detectedPlanes.values.map { anchor -> [String: Any] in
                [
                    "identifier": anchor.identifier.uuidString,
                    "alignment": anchor.alignment == .horizontal ? "horizontal" : "vertical",
                    "center": [anchor.center.x, anchor.center.y, anchor.center.z],
                    "extent": [anchor.extent.x, anchor.extent.y, anchor.extent.z],
                    "transform": transformToArray(anchor.transform)
                ]
            }
            return (try? JSONSerialization.data(withJSONObject: planes, options: [])) ?? Data("[]".utf8)
        }
    }

    /// Get the current number of detected planes (thread-safe)
    func getDetectedPlaneCount() -> Int {
        planeQueue.sync { _detectedPlanes.count }
    }

    // MARK: - Zoom Factor (ADR-005)

    /// Set current zoom factor for reconstruction pipeline
    /// - Parameter zoomFactor: The camera zoom factor (1.0 = no zoom)
    func setZoomFactor(_ zoomFactor: CGFloat) {
        stateLock.lock()
        _currentZoomFactor = zoomFactor
        stateLock.unlock()
        print("[AIARSessionManager] Zoom factor set to \(zoomFactor)")
    }

    /// Get current zoom factor
    func getZoomFactor() -> CGFloat {
        stateLock.lock()
        let zoom = _currentZoomFactor
        stateLock.unlock()
        return zoom
    }

    // MARK: - Tracking Recovery Methods (Story 6.7)

    /// Get the last good pose before tracking was lost
    /// Per Story 6.7 - Task 1.5
    func getLastGoodPose() -> AIPose? {
        stateLock.lock()
        let pose = _lastGoodPose
        stateLock.unlock()
        return pose
    }

    /// Attempt to relocalize the session
    /// Per Story 6.7 - Task 1.6
    /// Note: ARKit handles relocalization automatically, this method logs the attempt
    func attemptRelocalization() {
        print("[AIARSessionManager] Relocalization in progress - ARKit handling automatically")
        // ARKit automatically attempts relocalization when tracking is lost
        // We don't need to do anything here, but we track it for debugging
    }

    // MARK: - Private Helpers

    /// Setup observers for app lifecycle events (ADR-004)
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)
    }

    private func handleAppWillResignActive() {
        print("[AIARSessionManager] App will resign active - ARKit session will pause automatically")
        // ARKit automatically pauses when app backgrounds
        // We don't need to do anything here, but we track it
    }

    private func handleAppDidBecomeActive() {
        print("[AIARSessionManager] App did become active - ARKit session resuming")
        // ARKit automatically resumes when app returns
        // Session will attempt to relocalize
    }

    /// Trim pose history when over limit (batch approach for O(1) amortized)
    /// Must be called from poseQueue
    private func trimPoseHistoryIfNeeded() {
        // Only trim when significantly over limit (batch approach)
        if _poseHistory.count > maxPoseCount + trimBatchSize {
            _poseHistory.removeFirst(trimBatchSize)
            print("[AIARSessionManager] Trimmed \(trimBatchSize) old poses, count now: \(_poseHistory.count)")
        }
    }

    /// Convert transform matrix to array for JSON export
    private func transformToArray(_ transform: simd_float4x4) -> [[Float]] {
        return [
            [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w],
            [transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w],
            [transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w],
            [transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
        ]
    }

    /// Convert tracking state to string for JSON export
    private func trackingStateToString(_ state: AITrackingState) -> String {
        switch state {
        case .normal: return "normal"
        case .limited: return "limited"
        case .notAvailable: return "notAvailable"
        }
    }

    // MARK: - Tracking Recovery Handling (Story 6.7)

    /// Start the recovery timeout timer
    /// Per Story 6.7 - Task 1.4
    private func startRecoveryTimer() {
        // Cancel any existing timer
        recoveryTimer?.invalidate()

        stateLock.lock()
        _trackingLostTime = Date()
        stateLock.unlock()

        // Create timer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.recoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.recoveryTimeoutDuration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleRecoveryTimeout()
                }
            }

            print("[AIARSessionManager] Recovery timer started - 10 second timeout")
        }
    }

    /// Cancel the recovery timer
    private func cancelRecoveryTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.recoveryTimer?.invalidate()
            self?.recoveryTimer = nil
        }

        stateLock.lock()
        _trackingLostTime = nil
        stateLock.unlock()

        print("[AIARSessionManager] Recovery timer cancelled")
    }

    /// Handle recovery timeout (10 seconds elapsed)
    private func handleRecoveryTimeout() {
        print("[AIARSessionManager] Recovery timeout reached - tracking failed")

        updateTrackingRecoveryState(.failed)
    }

    /// Update tracking recovery state and publish changes
    private func updateTrackingRecoveryState(_ newState: TrackingRecoveryState) {
        stateLock.lock()
        let lastState = _lastPublishedRecoveryState
        let shouldUpdate = newState != lastState
        if shouldUpdate {
            _lastPublishedRecoveryState = newState
        }
        stateLock.unlock()

        if shouldUpdate {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.trackingRecoveryState = newState
                self.trackingRecoveryPublisher.send(newState)
                print("[AIARSessionManager] Recovery state changed: \(newState)")
            }
        }
    }

    /// Convert ARKit tracking reason to our enum
    private func convertTrackingReason(_ reason: ARCamera.TrackingState.Reason) -> TrackingLimitedReason {
        switch reason {
        case .initializing:
            return .initializing
        case .excessiveMotion:
            return .excessiveMotion
        case .insufficientFeatures:
            return .insufficientFeatures
        case .relocalizing:
            return .relocalizing
        @unknown default:
            return .unknown
        }
    }

    /// Get elapsed time since tracking was lost
    private func getElapsedRecoveryTime() -> TimeInterval {
        stateLock.lock()
        let lostTime = _trackingLostTime
        stateLock.unlock()

        guard let lostTime = lostTime else { return 0 }
        return Date().timeIntervalSince(lostTime)
    }
}

// MARK: - ARSessionDelegate

extension AIARSessionManager: ARSessionDelegate {

    /// Called when a new frame is available (60Hz)
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Extract pose data
        let transform = frame.camera.transform
        let intrinsicsMatrix = frame.camera.intrinsics
        let timestamp = frame.timestamp

        let intrinsics = AICameraIntrinsics(
            fx: intrinsicsMatrix[0, 0],
            fy: intrinsicsMatrix[1, 1],
            cx: intrinsicsMatrix[2, 0],
            cy: intrinsicsMatrix[2, 1]
        )

        // Extract gravity vector from ARKit
        // With worldAlignment = .gravity, the world Y-axis is aligned with gravity (pointing up)
        // So gravity vector in world coordinates is (0, -1, 0)
        // We also capture the actual estimated gravity for validation/debugging
        let gravityVector: SIMD3<Float>
        if let worldGravity = frame.worldMappingStatus == .mapped ? SIMD3<Float>(0, -1, 0) : nil {
            gravityVector = worldGravity
        } else {
            // Default gravity direction when using .gravity world alignment
            // ARKit aligns Y-axis with gravity, so gravity points in -Y direction
            gravityVector = SIMD3<Float>(0, -1, 0)
        }

        // Map tracking state and handle recovery (Story 6.7)
        let newState: AITrackingState
        var newRecoveryState: TrackingRecoveryState = .normal
        var limitedReason: TrackingLimitedReason?

        switch frame.camera.trackingState {
        case .normal:
            newState = .normal
            newRecoveryState = .normal

            // Story 6.7: Tracking recovered - save as last good pose and cancel timer
            stateLock.lock()
            _lastGoodPose = AIPose(
                transform: transform,
                intrinsics: intrinsics,
                trackingState: .normal,
                zoomFactor: _currentZoomFactor,
                gravityVector: gravityVector
            )
            let wasLost = _trackingLostTime != nil
            stateLock.unlock()

            if wasLost {
                cancelRecoveryTimer()
                print("[AIARSessionManager] Tracking recovered!")
            }

        case .limited(let reason):
            newState = .limited
            limitedReason = convertTrackingReason(reason)
            newRecoveryState = .limited(reason: limitedReason!)

            // Log reason for debugging (only on state change to avoid spam)
            stateLock.lock()
            let shouldLog = _lastPublishedState != .limited
            // Save last good pose before tracking becomes limited (if we had normal tracking)
            if _lastPublishedState == .normal, let latestPose = _latestPose {
                _lastGoodPose = latestPose
            }
            stateLock.unlock()

            if shouldLog {
                switch reason {
                case .excessiveMotion:
                    print("[AIARSessionManager] Tracking limited: excessive motion")
                case .insufficientFeatures:
                    print("[AIARSessionManager] Tracking limited: insufficient features")
                case .initializing:
                    print("[AIARSessionManager] Tracking limited: initializing")
                case .relocalizing:
                    print("[AIARSessionManager] Tracking limited: relocalizing")
                    // Story 6.7: Relocalizing means tracking was lost - start recovery timer
                    startRecoveryTimer()
                @unknown default:
                    print("[AIARSessionManager] Tracking limited: unknown reason")
                }
            }

        case .notAvailable:
            newState = .notAvailable
            let elapsed = getElapsedRecoveryTime()
            newRecoveryState = .lost(elapsedSeconds: elapsed)

            // Story 6.7: Tracking completely lost - start recovery timer if not already started
            stateLock.lock()
            let timerStarted = _trackingLostTime != nil
            // Save last good pose if we have one
            if _lastPublishedState == .normal || _lastPublishedState == .limited, let latestPose = _latestPose {
                _lastGoodPose = latestPose
            }
            stateLock.unlock()

            if !timerStarted {
                startRecoveryTimer()
            }
        }

        // Update tracking limited reason
        DispatchQueue.main.async { [weak self] in
            self?.trackingLimitedReason = limitedReason
        }

        // Update recovery state (Story 6.7)
        updateTrackingRecoveryState(newRecoveryState)

        // Get current zoom factor for this pose (ADR-005: store per-pose)
        stateLock.lock()
        let zoomForPose = _currentZoomFactor
        stateLock.unlock()

        let pose = AIPose(
            transform: transform,
            intrinsics: intrinsics,
            trackingState: newState,
            zoomFactor: zoomForPose,
            gravityVector: gravityVector
        )

        // Store pose with thread-safe access
        poseQueue.async { [weak self] in
            guard let self = self else { return }
            self._poseHistory.append((timestamp: timestamp, pose: pose))
            self.trimPoseHistoryIfNeeded()
        }

        // Publish pose for guidance system (Story 2.3)
        poseUpdatePublisher.send((timestamp: timestamp, pose: pose))

        // Update latest pose and check for state changes atomically
        stateLock.lock()
        _latestPose = pose
        let lastState = _lastPublishedState
        let shouldUpdateState = newState != lastState
        var shouldTriggerReady = false

        if shouldUpdateState {
            _lastPublishedState = newState
            // Check if this is the first time achieving .normal (fix race condition)
            if newState == .normal && !_hasEverBeenReady {
                _hasEverBeenReady = true
                shouldTriggerReady = true
            }
        }
        stateLock.unlock()

        // Only dispatch to main for STATE CHANGES (not every frame! - ADR-003)
        if shouldUpdateState {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.trackingState = newState

                // Trigger ready for capture if this was the first .normal state
                if shouldTriggerReady {
                    self.isReadyForCapture = true
                    print("[AIARSessionManager] Session ready for capture - tracking achieved normal state")
                }
            }
        }

        // Deliver frame to delegate (for video recording / quality analysis)
        frameDelegate?.arSessionManager(self, didUpdateFrame: frame)
    }

    // MARK: - Anchor Handling (Server Pipeline V2 — Plane Detection)

    /// Called when new anchors are added to the session
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        var addedPlanes = false
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                planeQueue.async { [weak self] in
                    self?._detectedPlanes[planeAnchor.identifier] = planeAnchor
                }
                addedPlanes = true
            }
        }
        if addedPlanes {
            updatePlaneCount()
        }
    }

    /// Called when existing anchors are updated
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        var updatedPlanes = false
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                planeQueue.async { [weak self] in
                    self?._detectedPlanes[planeAnchor.identifier] = planeAnchor
                }
                updatedPlanes = true
            }
        }
        if updatedPlanes {
            updatePlaneCount()
        }
    }

    /// Called when anchors are removed from the session
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        var removedPlanes = false
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                planeQueue.async { [weak self] in
                    self?._detectedPlanes.removeValue(forKey: planeAnchor.identifier)
                }
                removedPlanes = true
            }
        }
        if removedPlanes {
            updatePlaneCount()
        }
    }

    /// Update published plane count on main thread
    private func updatePlaneCount() {
        planeQueue.async { [weak self] in
            guard let self = self else { return }
            let count = self._detectedPlanes.count
            DispatchQueue.main.async {
                self.detectedPlaneCount = count
            }
        }
    }

    /// Called when session is interrupted (phone call, app backgrounded, etc.)
    func sessionWasInterrupted(_ session: ARSession) {
        print("[AIARSessionManager] Session was interrupted")

        DispatchQueue.main.async { [weak self] in
            self?.isInterrupted = true
        }
        // Note: Do NOT stop recording - let UI decide what to show
    }

    /// Called when session interruption ends
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[AIARSessionManager] Session interruption ended - attempting to relocalize")

        DispatchQueue.main.async { [weak self] in
            self?.isInterrupted = false
        }
        // Session will attempt to relocalize automatically
    }

    /// Called when session encounters a fatal error
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[AIARSessionManager] Session failed with error: \(error.localizedDescription)")

        DispatchQueue.main.async { [weak self] in
            self?.sessionError = error
            self?.trackingState = .notAvailable
        }
    }
}
