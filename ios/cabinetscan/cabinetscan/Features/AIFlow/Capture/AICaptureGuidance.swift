//
//  AICaptureGuidance.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import Foundation
import Combine
import simd

// MARK: - Capture Zone (ADR-004)

/// Direction-based capture zones for coverage tracking
/// Per Story 2.3 - Task 4, ADR-004
enum AICaptureZone: String, CaseIterable, Equatable {
    case front
    case right
    case back
    case left

    /// Convert zone to guidance direction
    func toGuidanceDirection() -> AIGuidanceDirection {
        switch self {
        case .front: return .forward
        case .right: return .right
        case .back: return .backward
        case .left: return .left
        }
    }
}

// MARK: - Guidance Direction

/// Direction for guidance arrows
enum AIGuidanceDirection: String, Equatable {
    case forward
    case right
    case backward
    case left

    /// SF Symbol name for the direction arrow
    var arrowSymbol: String {
        switch self {
        case .forward: return "arrow.up"
        case .right: return "arrow.right"
        case .backward: return "arrow.down"
        case .left: return "arrow.left"
        }
    }

    /// Accessibility description
    var accessibilityLabel: String {
        switch self {
        case .forward: return "Move camera forward"
        case .right: return "Move camera right"
        case .backward: return "Move camera backward"
        case .left: return "Move camera left"
        }
    }
}

// MARK: - Orientation Issue

/// Camera orientation issues (pointing at floor/ceiling too long)
enum AIOrientationIssue: Equatable {
    case pointingAtFloor
    case pointingAtCeiling

    var description: String {
        switch self {
        case .pointingAtFloor: return "Camera pointing at floor"
        case .pointingAtCeiling: return "Camera pointing at ceiling"
        }
    }
}

// MARK: - Coverage State

/// Current capture coverage state
struct AICoverageState: Equatable {
    /// Set of captured zones
    var capturedZones: Set<AICaptureZone>

    /// Coverage percentage (0.0 to 1.0)
    var coveragePercentage: Float {
        Float(capturedZones.count) / Float(AICaptureZone.allCases.count)
    }

    /// Whether all zones are captured
    var isComplete: Bool {
        capturedZones.count == AICaptureZone.allCases.count
    }

    /// Next uncaptured zone for guidance
    var nextUncapturedZone: AICaptureZone? {
        AICaptureZone.allCases.first { !capturedZones.contains($0) }
    }

    static let empty = AICoverageState(capturedZones: [])
}

// MARK: - Capture Guidance

/// Tracks camera orientation and capture coverage for guidance system.
/// Per Story 2.3 - Tasks 3 & 4, ADR-004
///
/// **Camera Orientation Tracking (Task 3):**
/// - Analyzes camera pitch from ARKit transform
/// - Detects when camera points at floor/ceiling too long (>3 seconds)
/// - Triggers guidance to point at cabinets
///
/// **Coverage Zone Tracking (Task 4, ADR-004):**
/// - Tracks camera DIRECTION (not position)
/// - 4 direction-based zones: front, right, back, left
/// - Zone marked "captured" after 1+ second cumulative dwell time
class AICaptureGuidance: ObservableObject {

    // MARK: - Published Properties

    /// Current coverage state
    @Published private(set) var coverageState: AICoverageState = .empty

    /// Current guidance direction (nil = no guidance needed)
    @Published private(set) var guidanceDirection: AIGuidanceDirection?

    /// Current orientation issue (nil = good orientation)
    @Published private(set) var orientationIssue: AIOrientationIssue?

    // MARK: - Publishers

    /// Orientation issue events for toast system
    let orientationIssuePublisher = PassthroughSubject<AIOrientationIssue, Never>()

    /// Coverage milestone events
    let coverageMilestonePublisher = PassthroughSubject<Int, Never>() // Number of zones captured

    // MARK: - Constants

    /// Pitch angle threshold for "looking at floor" (45 degrees down in radians)
    private let floorPitchThreshold: Float = -0.785 // -45 degrees

    /// Pitch angle threshold for "looking at ceiling" (45 degrees up in radians)
    private let ceilingPitchThreshold: Float = 0.785 // 45 degrees

    /// Time threshold before showing orientation guidance (3 seconds)
    private let orientationTimeThreshold: TimeInterval = 3.0

    /// Time threshold to mark zone as captured (1 second per ADR-004)
    private let zoneCaptureThreshold: TimeInterval = 1.0

    /// Zone angle width (90 degrees = π/2 radians)
    private let zoneAngleWidth: Float = .pi / 2

    // MARK: - State Properties

    /// Initial heading when recording started (for zone calculation)
    private var initialHeading: Float?

    /// Cumulative dwell time per zone
    private var zoneDwellTime: [AICaptureZone: TimeInterval] = [:]

    /// Time spent in bad orientation
    private var badOrientationTime: TimeInterval = 0

    /// Current bad orientation type being tracked
    private var currentBadOrientation: AIOrientationIssue?

    /// Last pose timestamp for delta time calculation
    private var lastPoseTimestamp: TimeInterval?

    /// Whether tracking is active
    private var isTracking = false

    /// Lock for thread-safe access
    private let stateLock = NSLock()

    // MARK: - Initialization

    init() {
        print("[AICaptureGuidance] Initialized")
    }

    // MARK: - Public Methods

    /// Start capture guidance tracking
    func startTracking() {
        stateLock.lock()
        isTracking = true
        initialHeading = nil
        zoneDwellTime = [:]
        badOrientationTime = 0
        currentBadOrientation = nil
        lastPoseTimestamp = nil
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.coverageState = .empty
            self?.guidanceDirection = nil
            self?.orientationIssue = nil
        }

        print("[AICaptureGuidance] Tracking started")
    }

    /// Stop capture guidance tracking
    func stopTracking() {
        stateLock.lock()
        isTracking = false
        stateLock.unlock()

        print("[AICaptureGuidance] Tracking stopped - final coverage: \(coverageState.capturedZones.count)/4 zones")
    }

    /// Process a new pose from ARKit
    /// - Parameters:
    ///   - pose: The camera pose to process
    ///   - timestamp: Pose timestamp for delta time calculation
    func processPose(_ pose: AIPose, timestamp: TimeInterval) {
        stateLock.lock()
        guard isTracking else {
            stateLock.unlock()
            return
        }

        // Calculate delta time
        let deltaTime: TimeInterval
        if let lastTimestamp = lastPoseTimestamp {
            deltaTime = timestamp - lastTimestamp
        } else {
            deltaTime = 0
        }
        lastPoseTimestamp = timestamp

        // Calibrate initial heading on first pose
        if initialHeading == nil {
            initialHeading = calculateHeading(from: pose.transform)
            print("[AICaptureGuidance] Calibrated initial heading: \(initialHeading! * 180 / .pi) degrees")
        }

        stateLock.unlock()

        // Process orientation
        processOrientation(pose: pose, deltaTime: deltaTime)

        // Process zone coverage
        processZoneCoverage(pose: pose, deltaTime: deltaTime)
    }

    // MARK: - Orientation Tracking (Task 3)

    /// Process camera orientation for floor/ceiling detection
    private func processOrientation(pose: AIPose, deltaTime: TimeInterval) {
        let pitch = calculatePitch(from: pose.transform)

        stateLock.lock()

        // Determine current orientation issue
        let newOrientation: AIOrientationIssue?
        if pitch < floorPitchThreshold {
            newOrientation = .pointingAtFloor
        } else if pitch > ceilingPitchThreshold {
            newOrientation = .pointingAtCeiling
        } else {
            newOrientation = nil
        }

        // Track time in bad orientation
        if let issue = newOrientation {
            if currentBadOrientation == issue {
                // Same bad orientation - accumulate time
                badOrientationTime += deltaTime
            } else {
                // Different bad orientation - reset
                currentBadOrientation = issue
                badOrientationTime = deltaTime
            }
        } else {
            // Good orientation - reset
            currentBadOrientation = nil
            badOrientationTime = 0
        }

        let shouldTriggerGuidance = badOrientationTime >= orientationTimeThreshold
        let currentIssue = currentBadOrientation
        stateLock.unlock()

        // Update published state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if shouldTriggerGuidance, let issue = currentIssue {
                if self.orientationIssue != issue {
                    self.orientationIssue = issue
                    self.orientationIssuePublisher.send(issue)
                    print("[AICaptureGuidance] Orientation issue triggered: \(issue.description)")
                }
            } else if self.orientationIssue != nil && newOrientation == nil {
                self.orientationIssue = nil
            }
        }
    }

    // MARK: - Zone Coverage Tracking (Task 4)

    /// Process zone coverage based on camera heading
    private func processZoneCoverage(pose: AIPose, deltaTime: TimeInterval) {
        stateLock.lock()
        guard let initialHeading = initialHeading else {
            stateLock.unlock()
            return
        }

        // Calculate current heading relative to initial
        let currentHeading = calculateHeading(from: pose.transform)
        let relativeAngle = normalizeAngle(currentHeading - initialHeading)

        // Determine which zone we're facing
        let zone = mapAngleToZone(relativeAngle)

        // Accumulate dwell time for this zone
        zoneDwellTime[zone, default: 0] += deltaTime

        // Check for newly captured zones
        var newlyCapturedZones: [AICaptureZone] = []
        var allCapturedZones = Set<AICaptureZone>()

        for (z, time) in zoneDwellTime {
            if time >= zoneCaptureThreshold {
                allCapturedZones.insert(z)
                if !coverageState.capturedZones.contains(z) {
                    newlyCapturedZones.append(z)
                }
            }
        }

        // Determine guidance direction (next uncaptured zone)
        let nextDirection = AICaptureZone.allCases
            .first { !allCapturedZones.contains($0) }?
            .toGuidanceDirection()

        stateLock.unlock()

        // Update published state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update coverage state if changed
            if self.coverageState.capturedZones != allCapturedZones {
                self.coverageState = AICoverageState(capturedZones: allCapturedZones)

                // Emit milestone events for newly captured zones
                for newZone in newlyCapturedZones {
                    print("[AICaptureGuidance] Zone captured: \(newZone.rawValue) (total: \(allCapturedZones.count)/4)")
                    self.coverageMilestonePublisher.send(allCapturedZones.count)
                }
            }

            // Update guidance direction
            if self.guidanceDirection != nextDirection {
                self.guidanceDirection = nextDirection
            }
        }
    }

    // MARK: - Math Helpers

    /// Calculate camera heading (yaw) from transform matrix
    private func calculateHeading(from transform: simd_float4x4) -> Float {
        // Extract forward vector (negative z-axis in camera space)
        let forward = -transform.columns.2
        // Calculate heading angle (rotation around Y axis)
        return atan2(forward.x, forward.z)
    }

    /// Calculate camera pitch from transform matrix
    private func calculatePitch(from transform: simd_float4x4) -> Float {
        // Extract forward vector
        let forward = -transform.columns.2
        // Calculate pitch angle (angle from horizontal plane)
        // Negative = looking down, Positive = looking up
        return atan2(forward.y, sqrt(forward.x * forward.x + forward.z * forward.z))
    }

    /// Normalize angle to [-π, π] range
    private func normalizeAngle(_ angle: Float) -> Float {
        var normalized = angle
        while normalized > .pi {
            normalized -= 2 * .pi
        }
        while normalized < -.pi {
            normalized += 2 * .pi
        }
        return normalized
    }

    /// Map relative angle to capture zone
    /// Front: -45° to 45°
    /// Right: 45° to 135°
    /// Back: 135° to 180° or -180° to -135°
    /// Left: -135° to -45°
    private func mapAngleToZone(_ angle: Float) -> AICaptureZone {
        let quarterPi = Float.pi / 4

        if angle >= -quarterPi && angle < quarterPi {
            return .front
        } else if angle >= quarterPi && angle < 3 * quarterPi {
            return .right
        } else if angle >= 3 * quarterPi || angle < -3 * quarterPi {
            return .back
        } else {
            return .left
        }
    }
}
