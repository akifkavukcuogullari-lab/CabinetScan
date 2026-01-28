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

    // MARK: - Publishers

    /// Pose update events for guidance system (timestamp, pose)
    /// Published at 60Hz during active tracking for real-time guidance
    let poseUpdatePublisher = PassthroughSubject<(timestamp: TimeInterval, pose: AIPose), Never>()

    // MARK: - ARKit Session

    /// The ARKit session instance
    private let session = ARSession()

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
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.isReadyForCapture = false
            self?.isInterrupted = false
            self?.sessionError = nil
            self?.trackingState = .notAvailable
        }

        // Clear pose history
        poseQueue.async { [weak self] in
            self?._poseHistory.removeAll()
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

        // ADR-001: Explicitly disable ALL optional features
        configuration.planeDetection = []           // We only need poses, not planes
        // Note: environmentTexturing left at default (automatic) as .none is deprecated
        // Note: sceneReconstruction left at default as .none is unavailable - it's LiDAR-only anyway
        configuration.frameSemantics = []           // No body/person detection needed

        // Run session
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        print("[AIARSessionManager] Session started with battery-optimized configuration")
    }

    /// Pause the ARKit session (preserves tracking state for resume)
    func pauseSession() {
        session.pause()
        print("[AIARSessionManager] Session paused")
    }

    /// Stop the ARKit session and clean up resources
    func stopSession() {
        session.pause()

        // Clear pose history
        poseQueue.async { [weak self] in
            self?._poseHistory.removeAll()
        }

        // Reset state
        stateLock.lock()
        _hasEverBeenReady = false
        _lastPublishedState = .notAvailable
        _latestPose = nil
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.isReadyForCapture = false
            self?.trackingState = .notAvailable
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

        // Map tracking state
        let newState: AITrackingState
        switch frame.camera.trackingState {
        case .normal:
            newState = .normal
        case .limited(let reason):
            newState = .limited
            // Log reason for debugging (only on state change to avoid spam)
            stateLock.lock()
            let shouldLog = _lastPublishedState != .limited
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
                @unknown default:
                    print("[AIARSessionManager] Tracking limited: unknown reason")
                }
            }
        case .notAvailable:
            newState = .notAvailable
        }

        // Get current zoom factor for this pose (ADR-005: store per-pose)
        stateLock.lock()
        let zoomForPose = _currentZoomFactor
        stateLock.unlock()

        let pose = AIPose(
            transform: transform,
            intrinsics: intrinsics,
            trackingState: newState,
            zoomFactor: zoomForPose
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
