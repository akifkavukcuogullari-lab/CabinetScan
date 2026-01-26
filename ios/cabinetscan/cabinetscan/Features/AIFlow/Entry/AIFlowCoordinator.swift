//
//  AIFlowCoordinator.swift
//  cabinetscan
//
//  Created by Dev Agent on 2026-01-25.
//

import SwiftUI
import Combine

// MARK: - Coordinator Protocol

/// Protocol defining AI Flow coordination capabilities.
/// Per Architecture Section 6.2 Key Interfaces.
///
/// Note: This protocol references `MeasurementData` from `Models/ProjectSubmission.swift`.
/// This is an intentional dependency as AI Flow must produce output compatible with the
/// existing LiDAR flow's data model. Per ARCH-3, MeasurementData will be extended
/// (additive only) in Story 5.4 to include AI-specific metadata.
protocol AIFlowCoordinatorProtocol {
    /// Start the capture process (video + photos)
    func startCapture() async

    /// Cancel ongoing capture and return to initial state
    func cancelCapture()

    /// Process captured data and return measurement results
    func processCapture() async throws -> MeasurementData

    /// Current state of the capture flow
    var captureState: AICaptureState { get }

    /// Processing progress (0.0 to 1.0)
    var processingProgress: Double { get }
}

// MARK: - Capture State

/// State machine for AI capture flow.
/// Tracks the current phase of capture and processing.
/// Per Architecture Section 6.2 Key Interfaces.
enum AICaptureState: Equatable {
    case idle
    case calibrating
    case recordingVideo
    case capturingPhotos
    case processing
    case complete
    case error(Error)

    static func == (lhs: AICaptureState, rhs: AICaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.calibrating, .calibrating),
             (.recordingVideo, .recordingVideo),
             (.capturingPhotos, .capturingPhotos),
             (.processing, .processing),
             (.complete, .complete):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            // Compare by localized description since Error doesn't conform to Equatable
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - AI Flow Error

/// Errors that can occur during AI flow capture and processing
enum AIFlowError: LocalizedError {
    case captureNotReady
    case processingFailed(String)
    case calibrationFailed
    case insufficientData
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .captureNotReady:
            return "Capture session is not ready"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .calibrationFailed:
            return "Could not calibrate measurements"
        case .insufficientData:
            return "Not enough data captured for accurate measurements"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
}

// MARK: - Coordinator Implementation

/// Coordinates navigation and state within the AI Flow.
/// Manages the lifecycle of capture sessions and processing pipeline.
@MainActor
class AIFlowCoordinator: ObservableObject, AIFlowCoordinatorProtocol {
    @Published private(set) var captureState: AICaptureState = .idle
    @Published private(set) var processingProgress: Double = 0.0

    /// Start capture sequence
    func startCapture() async {
        captureState = .recordingVideo
        // Implementation in future stories (Epic 2)
    }

    /// Cancel ongoing capture
    func cancelCapture() {
        captureState = .idle
        processingProgress = 0.0
        // Implementation in future stories (Epic 2)
    }

    /// Process captured data into measurements
    func processCapture() async throws -> MeasurementData {
        captureState = .processing
        // Placeholder - will be implemented in Epic 3
        throw AIFlowError.notImplemented
    }

    /// Update processing progress
    func updateProgress(_ progress: Double) {
        processingProgress = min(max(progress, 0.0), 1.0)
    }

    /// Transition to error state
    func setError(_ error: Error) {
        captureState = .error(error)
    }

    /// Reset to initial state
    func reset() {
        captureState = .idle
        processingProgress = 0.0
    }
}
