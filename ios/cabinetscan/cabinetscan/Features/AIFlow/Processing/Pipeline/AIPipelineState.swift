//
//  AIPipelineState.swift
//  cabinetscan
//
//  Created for Story 3.8: Processing Pipeline Orchestration
//

import Foundation

// MARK: - Pipeline State Machine (Task 1.2)

/// State machine for the AI processing pipeline.
///
/// **State Transitions:**
/// ```
/// idle → running → completed
///                ↘ awaitingManualCalibration → running → completed
///                ↘ failed
///                ↘ cancelled
/// ```
enum AIPipelineState: Equatable {
    /// Pipeline is idle, not processing
    case idle

    /// Pipeline is actively processing
    case running

    /// Pipeline is paused waiting for manual calibration (AC7)
    /// Contains the input data needed for manual calibration UI
    case awaitingManualCalibration(ManualCalibrationInput)

    /// Pipeline is paused (user-initiated)
    case paused

    /// Pipeline completed successfully
    case completed

    /// Pipeline failed with an error
    case failed(AIPipelineError)

    /// Pipeline was cancelled by user
    case cancelled

    // MARK: - Equatable

    static func == (lhs: AIPipelineState, rhs: AIPipelineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.running, .running),
             (.paused, .paused),
             (.completed, .completed),
             (.cancelled, .cancelled):
            return true
        case (.awaitingManualCalibration, .awaitingManualCalibration):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }

    // MARK: - State Properties

    /// Whether the pipeline is actively processing
    var isProcessing: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

    /// Whether the pipeline can be cancelled
    var isCancellable: Bool {
        switch self {
        case .running, .awaitingManualCalibration:
            return true
        default:
            return false
        }
    }

    /// Whether the pipeline has finished (success, failure, or cancellation)
    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Pipeline Phase (Task 1.3)

/// Processing phases with progress percentages per Architecture 3.1.
///
/// **Progress Mapping:**
/// | Stage | Progress | User-Friendly Text |
/// |-------|----------|-------------------|
/// | Model Loading | 0-10% | "Preparing..." |
/// | Frame Extraction | 10-20% | "Processing video..." |
/// | Depth Estimation | 20-50% | "Analyzing depth..." |
/// | Point Cloud Gen | 50-65% | "Building 3D model..." |
/// | TSDF Fusion | 65-80% | "Combining views..." |
/// | Scale Calibration | 80-88% | "Measuring dimensions..." |
/// | Geometric Constraints | 88-94% | "Refining walls..." |
/// | Room Detection | 94-96% | "Detecting room..." |
/// | Cabinet Detection | 96-99% | "Finding cabinets..." |
/// | Complete | 99-100% | "Finalizing..." |
enum AIPipelinePhase: String, CaseIterable {
    case idle = "Idle"
    case modelLoading = "Model Loading"
    case frameExtraction = "Frame Extraction"
    case depthEstimation = "Depth Estimation"
    case pointCloudGeneration = "Point Cloud Generation"
    case tsdfFusion = "TSDF Fusion"
    case scaleCalibration = "Scale Calibration"
    case geometricConstraints = "Geometric Constraints"
    case roomDetection = "Room Detection"
    case cabinetDetection = "Cabinet Detection"
    case complete = "Complete"

    // MARK: - Progress Range

    /// Start percentage for this phase (0.0 to 1.0)
    var startProgress: Double {
        switch self {
        case .idle: return 0.0
        case .modelLoading: return 0.0
        case .frameExtraction: return 0.10
        case .depthEstimation: return 0.20
        case .pointCloudGeneration: return 0.50
        case .tsdfFusion: return 0.65
        case .scaleCalibration: return 0.80
        case .geometricConstraints: return 0.88
        case .roomDetection: return 0.94
        case .cabinetDetection: return 0.96
        case .complete: return 0.99
        }
    }

    /// End percentage for this phase (0.0 to 1.0)
    var endProgress: Double {
        switch self {
        case .idle: return 0.0
        case .modelLoading: return 0.10
        case .frameExtraction: return 0.20
        case .depthEstimation: return 0.50
        case .pointCloudGeneration: return 0.65
        case .tsdfFusion: return 0.80
        case .scaleCalibration: return 0.88
        case .geometricConstraints: return 0.94
        case .roomDetection: return 0.96
        case .cabinetDetection: return 0.99
        case .complete: return 1.0
        }
    }

    /// Progress range for this phase
    var progressRange: Double {
        return endProgress - startProgress
    }

    // MARK: - User-Friendly Display

    /// User-friendly description for UI display (per UX-4).
    /// Uses non-technical language that conveys momentum.
    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .modelLoading: return "Preparing..."
        case .frameExtraction: return "Processing video..."
        case .depthEstimation: return "Analyzing depth..."
        case .pointCloudGeneration: return "Building 3D model..."
        case .tsdfFusion: return "Combining views..."
        case .scaleCalibration: return "Measuring dimensions..."
        case .geometricConstraints: return "Refining walls..."
        case .roomDetection: return "Detecting room..."
        case .cabinetDetection: return "Finding cabinets..."
        case .complete: return "Almost done..."
        }
    }

    // MARK: - Sub-Progress Mapping

    /// Converts sub-processor progress (0.0-1.0) to overall pipeline progress.
    ///
    /// Formula: `overallProgress = stageStart + (subProgress * progressRange)`
    ///
    /// Example: Depth estimation (20-50%, 30% range)
    /// If depthEstimator.progress = 0.5, overall = 0.20 + (0.5 * 0.30) = 0.35
    ///
    /// - Parameter subProgress: Progress within this phase (0.0 to 1.0)
    /// - Returns: Overall pipeline progress (0.0 to 1.0)
    func mapSubProgress(_ subProgress: Double) -> Double {
        return startProgress + (subProgress * progressRange)
    }
}

// MARK: - Pipeline Error (Task 1.4)

/// Stage-specific pipeline errors with user-friendly messages.
///
/// Each error case includes:
/// - Technical `reason` for logging/debugging
/// - `userFriendlyMessage` for UI display (no technical jargon)
enum AIPipelineError: LocalizedError, Equatable {
    case modelLoadingFailed(reason: String)
    case frameExtractionFailed(reason: String)
    case depthEstimationFailed(reason: String)
    case pointCloudGenerationFailed(reason: String)
    case fusionFailed(reason: String)
    case calibrationFailed(reason: String)
    case constraintsFailed(reason: String)
    case roomDetectionFailed(reason: String)
    case cabinetDetectionFailed(reason: String)
    case cancelled
    case memoryLimitExceeded

    // MARK: - User-Friendly Messages

    /// User-friendly error message suitable for UI display.
    /// No technical jargon - focuses on what user can do.
    var userFriendlyMessage: String {
        switch self {
        case .modelLoadingFailed:
            return "Please restart the app and try again."
        case .frameExtractionFailed:
            return "Video was corrupted. Please scan again."
        case .depthEstimationFailed:
            return "Couldn't analyze the video. Try with better lighting."
        case .pointCloudGenerationFailed:
            return "Couldn't build 3D model. Move slower during scan."
        case .fusionFailed:
            return "Couldn't combine views. Ensure full room coverage."
        case .calibrationFailed:
            return "Couldn't determine scale. Please try manual calibration."
        case .constraintsFailed:
            return "Error processing room geometry."
        case .roomDetectionFailed:
            return "Couldn't detect room structure. Ensure walls are visible."
        case .cabinetDetectionFailed:
            return "Couldn't detect cabinets. Ensure cabinets are visible in scan."
        case .cancelled:
            return "Processing was cancelled."
        case .memoryLimitExceeded:
            return "Not enough memory. Close other apps and try again."
        }
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .modelLoadingFailed(let reason):
            return "Model loading failed: \(reason)"
        case .frameExtractionFailed(let reason):
            return "Frame extraction failed: \(reason)"
        case .depthEstimationFailed(let reason):
            return "Depth estimation failed: \(reason)"
        case .pointCloudGenerationFailed(let reason):
            return "Point cloud generation failed: \(reason)"
        case .fusionFailed(let reason):
            return "TSDF fusion failed: \(reason)"
        case .calibrationFailed(let reason):
            return "Scale calibration failed: \(reason)"
        case .constraintsFailed(let reason):
            return "Geometric constraints failed: \(reason)"
        case .roomDetectionFailed(let reason):
            return "Room detection failed: \(reason)"
        case .cabinetDetectionFailed(let reason):
            return "Cabinet detection failed: \(reason)"
        case .cancelled:
            return "Pipeline was cancelled"
        case .memoryLimitExceeded:
            return "Memory limit exceeded during processing"
        }
    }

    // MARK: - Equatable

    static func == (lhs: AIPipelineError, rhs: AIPipelineError) -> Bool {
        switch (lhs, rhs) {
        case (.modelLoadingFailed(let a), .modelLoadingFailed(let b)),
             (.frameExtractionFailed(let a), .frameExtractionFailed(let b)),
             (.depthEstimationFailed(let a), .depthEstimationFailed(let b)),
             (.pointCloudGenerationFailed(let a), .pointCloudGenerationFailed(let b)),
             (.fusionFailed(let a), .fusionFailed(let b)),
             (.calibrationFailed(let a), .calibrationFailed(let b)),
             (.constraintsFailed(let a), .constraintsFailed(let b)),
             (.roomDetectionFailed(let a), .roomDetectionFailed(let b)),
             (.cabinetDetectionFailed(let a), .cabinetDetectionFailed(let b)):
            return a == b
        case (.cancelled, .cancelled),
             (.memoryLimitExceeded, .memoryLimitExceeded):
            return true
        default:
            return false
        }
    }

    // MARK: - Recovery Suggestions

    /// Whether this error can be retried
    var isRetryable: Bool {
        switch self {
        case .modelLoadingFailed, .memoryLimitExceeded:
            return true
        case .calibrationFailed:
            return true  // Can retry with manual calibration
        case .cancelled:
            return false
        default:
            return true  // Most errors can be retried with new capture
        }
    }

    /// The phase where this error occurred
    var failedPhase: AIPipelinePhase {
        switch self {
        case .modelLoadingFailed: return .modelLoading
        case .frameExtractionFailed: return .frameExtraction
        case .depthEstimationFailed: return .depthEstimation
        case .pointCloudGenerationFailed: return .pointCloudGeneration
        case .fusionFailed: return .tsdfFusion
        case .calibrationFailed: return .scaleCalibration
        case .constraintsFailed: return .geometricConstraints
        case .roomDetectionFailed: return .roomDetection
        case .cabinetDetectionFailed: return .cabinetDetection
        case .cancelled, .memoryLimitExceeded: return .idle
        }
    }
}

// MARK: - Pipeline Result (Task 1.5)

/// Result of successful pipeline execution.
///
/// Contains all outputs needed for Epic 4 (Detection) plus quality metrics.
struct AIPipelineResult {
    // MARK: - Final Outputs

    /// Constrained mesh after geometric regularization
    let constrainedMesh: AIMesh

    /// Detected and regularized walls from GeometricConstraints
    let walls: [DetectedWall]

    /// Detected and regularized corners from GeometricConstraints
    let corners: [DetectedCorner]

    /// Scale calibration result with scale factor
    let calibration: ScaleCalibrationResult

    /// Detected room structure (Story 4.1)
    /// Contains walls, floor, boundaries, dimensions for kitchen detection
    let roomStructure: AIRoomStructure?

    /// Detected cabinets (Story 4.2)
    /// Contains all base, upper, and tall cabinets with dimensions
    let detectedCabinets: CabinetDetectionResult?

    // MARK: - Metadata

    /// Total processing time in milliseconds
    let processingTimeMs: Int

    /// Number of video frames processed
    let frameCount: Int

    /// Number of photos processed
    let photoCount: Int

    // MARK: - Quality Metrics

    /// TSDF fusion quality metrics
    let fusionQuality: TSDFQualityMetrics

    /// Constraint validation results
    let constraintValidation: ConstraintValidation

    /// Overall coverage quality assessment
    let coverageQuality: CoverageQuality

    /// Warnings surfaced during processing (displayed in UI if non-empty)
    let warnings: [PipelineWarning]

    // MARK: - Debug Outputs

    /// Original mesh before constraints (DEBUG only)
    let originalMesh: AIMesh?
}

// MARK: - Coverage Quality

/// Assessment of scan coverage quality.
enum CoverageQuality {
    /// Good coverage (≥30%)
    case good
    /// Fair coverage (≥10%)
    case fair
    /// Poor coverage (<10%)
    case poor

    /// Creates coverage quality from percentage
    init(coveragePercentage: Double) {
        if coveragePercentage >= 30.0 {
            self = .good
        } else if coveragePercentage >= 10.0 {
            self = .fair
        } else {
            self = .poor
        }
    }

    /// User-friendly description
    var displayText: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

// MARK: - Pipeline Warning

/// Warning generated during pipeline processing.
/// Surfaced to UI when non-empty.
struct PipelineWarning {
    /// Phase where warning occurred
    let stage: AIPipelinePhase

    /// User-friendly warning message
    let message: String

    /// Severity of the warning
    let severity: WarningSeverity
}

// MARK: - Warning Severity

/// Severity levels for pipeline warnings.
enum WarningSeverity {
    /// Informational warning (e.g., "Limited frames")
    case info

    /// Caution warning (e.g., "Result may be incomplete")
    case caution
}
