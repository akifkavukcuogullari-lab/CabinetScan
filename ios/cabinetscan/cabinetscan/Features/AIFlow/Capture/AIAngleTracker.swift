//
//  AIAngleTracker.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-26.
//

import Foundation
import simd

// MARK: - Angle Similarity Result

/// Result of checking angle similarity
struct AngleSimilarityResult {
    /// Whether the current angle is too similar to a previous photo
    let isSimilar: Bool

    /// Suggested direction to move if too similar
    let suggestion: String?

    /// Index of the most similar photo (-1 if not similar)
    let similarPhotoIndex: Int
}

// MARK: - AI Angle Tracker

/// Tracks camera orientations to encourage diverse photo angles.
/// Per Story 2.5 - Task 5
///
/// **Usage:**
/// 1. Call `isAngleTooSimilar(currentPose:)` before allowing capture
/// 2. If too similar, show the suggestion to user
/// 3. Call `recordCapture(pose:)` after each successful capture
class AIAngleTracker {

    // MARK: - Types

    /// Captured orientation in degrees
    private struct CapturedOrientation {
        let yaw: Float    // Left/right rotation
        let pitch: Float  // Up/down tilt
    }

    // MARK: - Constants

    /// Minimum angle difference in degrees to consider distinct
    /// Photos within 20 degrees on both axes are considered too similar
    private let minimumAngleDifference: Float = 20.0

    // MARK: - Properties

    /// Recorded orientations from previous photos
    private var capturedOrientations: [CapturedOrientation] = []

    // MARK: - Public Methods

    /// Check if current angle is too similar to existing photos
    /// - Parameter currentPose: The current camera pose
    /// - Returns: Similarity result with suggestion if too similar
    func isAngleTooSimilar(currentPose: AIPose) -> AngleSimilarityResult {
        // No previous photos - any angle is fine
        guard !capturedOrientations.isEmpty else {
            return AngleSimilarityResult(isSimilar: false, suggestion: nil, similarPhotoIndex: -1)
        }

        let currentOrientation = extractOrientation(from: currentPose)

        // Find most similar photo
        var mostSimilarIndex = -1
        var smallestDifference: Float = Float.greatestFiniteMagnitude

        for (index, captured) in capturedOrientations.enumerated() {
            let yawDiff = abs(normalizeAngle(currentOrientation.yaw - captured.yaw))
            let pitchDiff = abs(currentOrientation.pitch - captured.pitch)

            let totalDiff = yawDiff + pitchDiff

            if totalDiff < smallestDifference {
                smallestDifference = totalDiff
                mostSimilarIndex = index
            }

            // Check if within minimum difference threshold
            if yawDiff < minimumAngleDifference && pitchDiff < minimumAngleDifference {
                // Generate suggestion based on which axis has more room
                let suggestion = generateSuggestion(
                    from: currentOrientation,
                    comparedTo: captured,
                    yawDiff: yawDiff,
                    pitchDiff: pitchDiff
                )
                return AngleSimilarityResult(
                    isSimilar: true,
                    suggestion: suggestion,
                    similarPhotoIndex: index
                )
            }
        }

        // Not too similar to any existing photo
        return AngleSimilarityResult(isSimilar: false, suggestion: nil, similarPhotoIndex: -1)
    }

    /// Record a captured photo's orientation
    /// - Parameter pose: The pose at capture time
    func recordCapture(pose: AIPose) {
        let orientation = extractOrientation(from: pose)
        capturedOrientations.append(orientation)
        print("[AIAngleTracker] Recorded capture - yaw: \(Int(orientation.yaw))°, pitch: \(Int(orientation.pitch))° (total: \(capturedOrientations.count))")
    }

    /// Remove the last recorded capture (for undo/delete)
    func removeLastCapture() {
        guard !capturedOrientations.isEmpty else { return }
        capturedOrientations.removeLast()
        print("[AIAngleTracker] Removed last capture (remaining: \(capturedOrientations.count))")
    }

    /// Remove capture at specific index
    func removeCapture(at index: Int) {
        guard index >= 0 && index < capturedOrientations.count else { return }
        capturedOrientations.remove(at: index)
        print("[AIAngleTracker] Removed capture at index \(index) (remaining: \(capturedOrientations.count))")
    }

    /// Reset all recorded orientations
    func reset() {
        capturedOrientations.removeAll()
        print("[AIAngleTracker] Reset all captures")
    }

    /// Number of recorded captures
    var captureCount: Int {
        capturedOrientations.count
    }

    // MARK: - Private Methods

    /// Extract camera orientation angles from pose transform using forward vector
    /// This approach is more robust than Euler angle decomposition as it directly
    /// measures where the camera is pointing, independent of rotation order.
    private func extractOrientation(from pose: AIPose) -> CapturedOrientation {
        let transform = pose.transform

        // ARKit camera looks along the -Z axis in local space
        // The third column of the rotation matrix gives us the camera's forward direction
        // (negated because camera looks down -Z)
        let forwardX = -transform.columns.2.x
        let forwardY = -transform.columns.2.y
        let forwardZ = -transform.columns.2.z

        // Calculate yaw: angle in the XZ plane (horizontal rotation / pan)
        // atan2(x, z) gives angle from Z axis toward X axis
        let yaw = atan2(forwardX, forwardZ) * 180 / Float.pi

        // Calculate pitch: angle from horizontal plane (vertical tilt)
        // Using the Y component of the normalized forward vector
        let horizontalLength = sqrt(forwardX * forwardX + forwardZ * forwardZ)
        let pitch = atan2(forwardY, horizontalLength) * 180 / Float.pi

        return CapturedOrientation(yaw: yaw, pitch: pitch)
    }

    /// Normalize angle to -180 to 180 range
    private func normalizeAngle(_ angle: Float) -> Float {
        var normalized = angle
        while normalized > 180 { normalized -= 360 }
        while normalized < -180 { normalized += 360 }
        return normalized
    }

    /// Generate suggestion for which direction to move
    private func generateSuggestion(
        from current: CapturedOrientation,
        comparedTo captured: CapturedOrientation,
        yawDiff: Float,
        pitchDiff: Float
    ) -> String {
        // Determine which axis needs more movement
        let yawRoom = minimumAngleDifference - yawDiff
        let pitchRoom = minimumAngleDifference - pitchDiff

        // Suggest the direction with more room to move
        if yawRoom > pitchRoom {
            // Need to move left/right
            let yawDelta = current.yaw - captured.yaw
            if yawDelta < 0 {
                return "Try moving right"
            } else {
                return "Try moving left"
            }
        } else {
            // Need to tilt up/down
            let pitchDelta = current.pitch - captured.pitch
            if pitchDelta < 0 {
                return "Try pointing up"
            } else {
                return "Try pointing down"
            }
        }
    }
}
