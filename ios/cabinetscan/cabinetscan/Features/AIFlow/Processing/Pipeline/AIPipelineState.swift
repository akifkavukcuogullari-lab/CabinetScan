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
/// | Room Detection | 94-95% | "Detecting room..." |
/// | Cabinet Detection | 95-96% | "Finding cabinets..." |
/// | Appliance Detection | 96-97% | "Finding appliances..." |
/// | Island/Peninsula Detection | 97-98% | "Finding islands..." |
/// | Countertop Detection | 98-98.3% | "Calculating countertops..." |
/// | Opening Detection | 98.3-98.6% | "Detecting openings..." |
/// | Measurement Extraction | 98.6-99% | "Extracting measurements..." |
/// | Confidence Scoring | 99-99.5% | "Scoring accuracy..." |
/// | Complete | 99.5-100% | "Finalizing..." |
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
    case applianceDetection = "Appliance Detection"
    case islandPeninsulaDetection = "Island/Peninsula Detection"
    case countertopDetection = "Countertop Detection"
    case openingDetection = "Opening Detection"
    case measurementExtraction = "Measurement Extraction"
    case confidenceScoring = "Confidence Scoring"
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
        case .cabinetDetection: return 0.95
        case .applianceDetection: return 0.96
        case .islandPeninsulaDetection: return 0.97
        case .countertopDetection: return 0.98
        case .openingDetection: return 0.983
        case .measurementExtraction: return 0.986
        case .confidenceScoring: return 0.99
        case .complete: return 0.995
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
        case .roomDetection: return 0.95
        case .cabinetDetection: return 0.96
        case .applianceDetection: return 0.97
        case .islandPeninsulaDetection: return 0.98
        case .countertopDetection: return 0.983
        case .openingDetection: return 0.986
        case .measurementExtraction: return 0.99
        case .confidenceScoring: return 0.995
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
        case .applianceDetection: return "Finding appliances..."
        case .islandPeninsulaDetection: return "Detecting islands..."
        case .countertopDetection: return "Calculating countertops..."
        case .openingDetection: return "Detecting openings..."
        case .measurementExtraction: return "Extracting measurements..."
        case .confidenceScoring: return "Scoring accuracy..."
        case .complete: return "Almost done..."
        }
    }

    /// VoiceOver accessibility description for stage transitions (Story 6.5).
    /// More descriptive than displayText for audio announcement.
    var accessibilityDescription: String {
        switch self {
        case .idle: return "Ready to process"
        case .modelLoading: return "Preparing AI model"
        case .frameExtraction: return "Now processing video frames"
        case .depthEstimation: return "Now analyzing depth information"
        case .pointCloudGeneration: return "Now building 3D model"
        case .tsdfFusion: return "Now combining multiple views"
        case .scaleCalibration: return "Now measuring dimensions"
        case .geometricConstraints: return "Now refining wall positions"
        case .roomDetection: return "Now detecting room structure"
        case .cabinetDetection: return "Now finding cabinets"
        case .applianceDetection: return "Now finding appliances"
        case .islandPeninsulaDetection: return "Now detecting islands and peninsulas"
        case .countertopDetection: return "Now calculating countertops"
        case .openingDetection: return "Now detecting windows and doors"
        case .measurementExtraction: return "Now extracting measurements"
        case .confidenceScoring: return "Now scoring accuracy"
        case .complete: return "Processing almost complete"
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
    case applianceDetectionFailed(reason: String)
    case islandPeninsulaDetectionFailed(reason: String)
    case countertopDetectionFailed(reason: String)
    case openingDetectionFailed(reason: String)
    case measurementExtractionFailed(reason: String)
    case confidenceScoringFailed(reason: String)
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
        case .applianceDetectionFailed:
            return "Couldn't detect appliances. You can add them manually."
        case .islandPeninsulaDetectionFailed:
            return "Couldn't detect islands. You can add them manually."
        case .countertopDetectionFailed:
            return "Couldn't calculate countertop totals. You can review manually."
        case .openingDetectionFailed:
            return "Couldn't detect windows and doors. You can add them manually."
        case .measurementExtractionFailed:
            return "Couldn't extract measurements. You can enter them manually."
        case .confidenceScoringFailed:
            return "Couldn't calculate confidence scores. Results may need manual review."
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
        case .applianceDetectionFailed(let reason):
            return "Appliance detection failed: \(reason)"
        case .islandPeninsulaDetectionFailed(let reason):
            return "Island/peninsula detection failed: \(reason)"
        case .countertopDetectionFailed(let reason):
            return "Countertop detection failed: \(reason)"
        case .openingDetectionFailed(let reason):
            return "Opening detection failed: \(reason)"
        case .measurementExtractionFailed(let reason):
            return "Measurement extraction failed: \(reason)"
        case .confidenceScoringFailed(let reason):
            return "Confidence scoring failed: \(reason)"
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
             (.cabinetDetectionFailed(let a), .cabinetDetectionFailed(let b)),
             (.applianceDetectionFailed(let a), .applianceDetectionFailed(let b)),
             (.islandPeninsulaDetectionFailed(let a), .islandPeninsulaDetectionFailed(let b)),
             (.countertopDetectionFailed(let a), .countertopDetectionFailed(let b)),
             (.openingDetectionFailed(let a), .openingDetectionFailed(let b)),
             (.measurementExtractionFailed(let a), .measurementExtractionFailed(let b)),
             (.confidenceScoringFailed(let a), .confidenceScoringFailed(let b)):
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
        case .applianceDetectionFailed: return .applianceDetection
        case .islandPeninsulaDetectionFailed: return .islandPeninsulaDetection
        case .countertopDetectionFailed: return .countertopDetection
        case .openingDetectionFailed: return .openingDetection
        case .measurementExtractionFailed: return .measurementExtraction
        case .confidenceScoringFailed: return .confidenceScoring
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

    /// Detected appliances (Story 4.4)
    /// Contains all detected kitchen appliances with dimensions
    let detectedAppliances: ApplianceDetectionResult?

    /// Detected islands and peninsulas (Story 4.5)
    /// Contains all detected islands and peninsulas with countertop data
    let detectedIslandsPeninsulas: IslandPeninsulaDetectionResult?

    /// Detected countertops (Story 4.6)
    /// Contains wall countertops and aggregated summary for quotes
    let detectedCountertops: CountertopDetectorResult?

    /// Detected openings (Story 4.9)
    /// Contains windows and doors with dimensions for floor plan and clearance calculations
    let detectedOpenings: OpeningDetectionResult?

    /// Extracted measurements (Story 4.7)
    /// Contains all measurements with raw/snapped values for quotes
    let extractedMeasurements: MeasurementExtractionResult?

    /// Confidence scores (Story 4.8)
    /// Contains per-object and overall confidence scores for quote reliability
    let confidenceScores: ConfidenceScoringResult?

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

    // MARK: - Coverage Metrics (Story 6.2)

    /// Coverage percentage from capture phase (0.0 to 1.0).
    /// Calculated from AICaptureGuidance zones:
    /// - 1.0 = all 4 zones captured (full coverage)
    /// - 0.75 = 3 zones captured
    /// - 0.50 = 2 zones captured
    /// - 0.25 = 1 zone captured
    /// - 0.0 = no zones captured (should not happen in practice)
    let coveragePercentage: Float?

    /// Set of zones that were NOT captured during the session.
    /// Used by floor plan renderer to show hatched/faded unscanned areas.
    /// Empty set means full coverage.
    let uncapturedZones: Set<AICaptureZone>?

    /// Original mesh before constraints (DEBUG only)
    let originalMesh: AIMesh?

    // MARK: - Computed Properties (Story 6.1)

    /// Whether this is an empty kitchen (no cabinets detected).
    /// Used for empty kitchen handling - room dimensions only scenario.
    ///
    /// Returns `nil` if cabinet detection was not run (unknown state).
    /// Returns `true` if detection ran and found no cabinets.
    /// Returns `false` if detection ran and found cabinets.
    var isEmptyKitchen: Bool? {
        guard let cabinets = detectedCabinets else {
            return nil  // Detection not run - unknown state
        }
        return cabinets.isEmpty
    }
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

// MARK: - Pipeline Checkpoint (Story 6.8)

/// Checkpoint saved during pipeline processing for retry capability.
///
/// **Per Story 6.8 ADR-1 (Checkpoint Granularity):**
/// Checkpoints are saved after 4 major stages:
/// - Depth estimation (50%)
/// - TSDF fusion (80%)
/// - Scale calibration (88%)
/// - Detection complete (98%)
///
/// **Per Story 6.8 ADR-2 (Checkpoint Storage):**
/// - In-memory during active processing (fast retry)
/// - Only serialized to disk on "Cancel" for "save for later"
struct PipelineCheckpoint: Codable {

    // MARK: - State Info

    /// Phase where checkpoint was created
    let phase: AIPipelinePhase

    /// Progress value at checkpoint (0.0 to 1.0)
    let progress: Double

    /// Timestamp when checkpoint was created
    let timestamp: Date

    // MARK: - Intermediate Results

    /// Depth frames (after depth estimation)
    let depthFrameCount: Int?

    /// Whether point clouds have been generated
    let hasPointClouds: Bool

    /// Whether TSDF fusion is complete
    let hasFusionResult: Bool

    /// Whether scale calibration is complete
    let hasCalibrationResult: Bool

    /// Whether detection stages are complete
    let hasDetectionResults: Bool

    // MARK: - Computed Properties

    /// Next phase to resume from after this checkpoint
    var nextPhase: AIPipelinePhase {
        switch phase {
        case .depthEstimation:
            return .pointCloudGeneration
        case .tsdfFusion:
            return .scaleCalibration
        case .scaleCalibration:
            return .geometricConstraints
        case .geometricConstraints:
            return .roomDetection
        case .roomDetection:
            return .cabinetDetection
        case .cabinetDetection:
            return .applianceDetection
        case .applianceDetection:
            return .islandPeninsulaDetection
        case .islandPeninsulaDetection:
            return .countertopDetection
        case .countertopDetection:
            return .openingDetection
        case .openingDetection:
            return .measurementExtraction
        case .measurementExtraction:
            return .confidenceScoring
        case .confidenceScoring:
            return .complete
        case .complete:
            return .complete  // Already at end
        default:
            // For early phases (idle, modelLoading, frameExtraction, pointCloudGeneration),
            // restart from beginning since we don't checkpoint these
            return .modelLoading
        }
    }

    /// Human-readable description of checkpoint
    var description: String {
        "Checkpoint at \(phase.displayText) (\(Int(progress * 100))%)"
    }
}

// MARK: - AIPipelinePhase Codable

extension AIPipelinePhase: Codable {
    // Default Codable implementation uses rawValue
}
