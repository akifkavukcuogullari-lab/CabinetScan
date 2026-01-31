//
//  AIPipelineOrchestrator.swift
//  cabinetscan
//
//  Created for Story 3.8: Processing Pipeline Orchestration
//

import Foundation
import Combine
import os.log

// MARK: - AI Pipeline Orchestrator (Task 3)

/// Central orchestrator for the AI 3D reconstruction pipeline.
///
/// **Pipeline Stages (AC1):**
/// 1. Model loading (10%)
/// 2. Frame extraction (20%)
/// 3. Depth estimation (50%)
/// 4. Point cloud generation (65%)
/// 5. TSDF fusion (80%)
/// 6. Scale calibration (90%)
/// 7. Geometric constraints (95%)
/// 8. Detection ready (100%)
///
/// **Critical Architecture Notes:**
/// - All processors are injected (testable)
/// - State-based manual calibration fallback (AC7)
/// - Memory management with autoreleasepool (NFR13)
/// - Cancellation support at stage boundaries (AC3)
///
/// **Usage:**
/// ```swift
/// let orchestrator = AIPipelineOrchestrator()
/// let result = try await orchestrator.process(captureData: sessionData)
/// ```
@MainActor
final class AIPipelineOrchestrator: ObservableObject {

    // MARK: - Constants

    /// Memory limit in bytes (1.5GB per NFR13/AC5)
    private static let memoryLimit: UInt64 = 1_500_000_000

    /// Minimum frames before adding warning
    private static let minimumFrameCount = 20

    /// Minimum coverage percentage before adding warning
    private static let minimumCoveragePercentage = 10.0

    /// Maximum point count before downsampling
    private static let maxPointCount = 2_000_000

    // MARK: - Published Properties (Task 3.2)

    /// Current progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0.0

    /// Current processing phase
    @Published private(set) var currentPhase: AIPipelinePhase = .idle

    /// Current pipeline state
    @Published private(set) var state: AIPipelineState = .idle

    /// Current error (if failed)
    @Published private(set) var error: AIPipelineError?

    /// Estimated time remaining in seconds (only valid after 20% progress)
    @Published private(set) var estimatedTimeRemaining: TimeInterval?

    /// Final result (set on successful completion) - Issue #3 fix
    @Published private(set) var result: AIPipelineResult?

    // MARK: - Dependencies (Task 3.3)

    private let modelManager: DepthModelManager
    private let depthEstimator: DepthEstimator
    private let pointCloudGenerator: PointCloudGenerator
    private let tsdfFusion: TSDFFusion
    private let scaleCalibrator: ScaleCalibrator
    private let geometricConstraints: GeometricConstraints
    private let roomDetector: RoomDetector
    private let cabinetDetector: CabinetDetector
    private let specialCabinetDetector: SpecialCabinetDetector
    private let applianceDetector: ApplianceDetector
    private let islandPeninsulaDetector: IslandPeninsulaDetector
    private let countertopDetector: CountertopDetector
    private let openingDetector: OpeningDetector
    private let measurementExtractor: MeasurementExtractor
    private let reflectiveSurfaceDetector: ReflectiveSurfaceDetector  // Story 6.4
    private let confidenceScorer: ConfidenceScorer

    private let logger = Logger(subsystem: "com.cabinetscan", category: "AIPipelineOrchestrator")

    // MARK: - Internal State

    /// Time logger for performance tracking
    #if DEBUG
    private let timeLogger = ProcessingTimeLogger()
    /// Performance validator for end-to-end NFR validation (Story 6.9 Task 4)
    private let performanceValidator = EndToEndPerformanceValidator()
    #endif

    /// Pipeline start time for ETA calculation
    private var startTime: CFAbsoluteTime?

    /// Warnings accumulated during processing
    private var warnings: [PipelineWarning] = []

    /// Partial results for debugging (saved on failure)
    private var partialResults: PartialPipelineResults?

    /// Tracks actual frame count from depth estimation (Issue #7 fix)
    private var actualFrameCount: Int = 0

    /// Continuation for manual calibration pause/resume
    private var manualCalibrationContinuation: CheckedContinuation<ScaleCalibrationResult, Error>?

    // MARK: - Checkpoint State (Story 6.8 Task 3)

    /// Last saved checkpoint for retry capability (ADR-2: in-memory)
    private(set) var lastCheckpoint: PipelineCheckpoint?

    /// Cached intermediate results for checkpoint restore
    private var cachedDepthFrames: [AIDepthFrame]?
    private var cachedPointClouds: [AIPointCloud]?
    private var cachedFusionResult: TSDFFusionResult?
    private var cachedCalibrationResult: ScaleCalibrationResult?

    // MARK: - Initialization

    /// Creates a pipeline orchestrator with default dependencies.
    init() {
        self.modelManager = DepthModelManager.shared
        self.depthEstimator = DepthEstimator(modelManager: DepthModelManager.shared)
        self.pointCloudGenerator = PointCloudGenerator()
        self.tsdfFusion = TSDFFusion()
        self.scaleCalibrator = ScaleCalibrator()
        self.geometricConstraints = GeometricConstraints()
        self.roomDetector = RoomDetector()
        self.cabinetDetector = CabinetDetector()
        self.specialCabinetDetector = SpecialCabinetDetector()
        self.applianceDetector = ApplianceDetector()
        self.islandPeninsulaDetector = IslandPeninsulaDetector()
        self.countertopDetector = CountertopDetector()
        self.openingDetector = OpeningDetector()
        self.measurementExtractor = MeasurementExtractor()
        self.reflectiveSurfaceDetector = ReflectiveSurfaceDetector()  // Story 6.4
        self.confidenceScorer = ConfidenceScorer()
    }

    /// Creates a pipeline orchestrator with injected dependencies (for testing).
    init(
        modelManager: DepthModelManager,
        depthEstimator: DepthEstimator,
        pointCloudGenerator: PointCloudGenerator,
        tsdfFusion: TSDFFusion,
        scaleCalibrator: ScaleCalibrator,
        geometricConstraints: GeometricConstraints,
        roomDetector: RoomDetector,
        cabinetDetector: CabinetDetector,
        specialCabinetDetector: SpecialCabinetDetector,
        applianceDetector: ApplianceDetector,
        islandPeninsulaDetector: IslandPeninsulaDetector,
        countertopDetector: CountertopDetector,
        openingDetector: OpeningDetector,
        measurementExtractor: MeasurementExtractor,
        reflectiveSurfaceDetector: ReflectiveSurfaceDetector,  // Story 6.4
        confidenceScorer: ConfidenceScorer
    ) {
        self.modelManager = modelManager
        self.depthEstimator = depthEstimator
        self.pointCloudGenerator = pointCloudGenerator
        self.tsdfFusion = tsdfFusion
        self.scaleCalibrator = scaleCalibrator
        self.geometricConstraints = geometricConstraints
        self.roomDetector = roomDetector
        self.cabinetDetector = cabinetDetector
        self.specialCabinetDetector = specialCabinetDetector
        self.applianceDetector = applianceDetector
        self.islandPeninsulaDetector = islandPeninsulaDetector
        self.countertopDetector = countertopDetector
        self.openingDetector = openingDetector
        self.measurementExtractor = measurementExtractor
        self.reflectiveSurfaceDetector = reflectiveSurfaceDetector  // Story 6.4
        self.confidenceScorer = confidenceScorer
    }

    // MARK: - Main Entry Point (Task 3.4)

    /// Processes capture data through the full 3D reconstruction pipeline.
    ///
    /// - Parameter captureData: The capture session data containing video and photos
    /// - Returns: Pipeline result with constrained mesh and metadata
    /// - Throws: `AIPipelineError` if processing fails
    func process(captureData: AICaptureSessionData) async throws -> AIPipelineResult {
        logger.info("Starting AI pipeline processing")

        // Reset state
        reset()
        state = .running
        startTime = CFAbsoluteTimeGetCurrent()

        #if DEBUG
        timeLogger.reset()
        performanceValidator.startValidation()

        // Story 6.9 Task 3.5: Memory headroom validation before processing
        let deviceProfile = DevicePerformanceProfile.forCurrentDevice()
        let memoryCheck = deviceProfile.checkMemoryHeadroom()
        if !memoryCheck.sufficient {
            logger.warning("⚠️ Low memory detected before processing: \(String(format: "%.0f", memoryCheck.availableMB))MB available, \(String(format: "%.0f", memoryCheck.requiredMB))MB required")
            // Continue but log warning - don't fail immediately as memory may be freed during processing
        }
        #endif

        do {
            // Stage 1: Load models (Task 4.1)
            try await executeModelLoading()

            // Stage 2: Extract frames (Task 4.2)
            let (frames, poses) = try await executeFrameExtraction(from: captureData)

            // Stage 3: Depth estimation (Task 4.3)
            let depthResult = try await executeDepthEstimation(
                sessionData: captureData,
                poses: poses
            )

            // Stage 4: Point cloud generation (Task 4.4)
            let pointClouds = try await executePointCloudGeneration(
                depthFrames: depthResult.allDepthFrames,
                videoFrameCount: depthResult.videoDepthFrames.count
            )

            // Stage 5: TSDF fusion (Task 4.5)
            let fusionResult = try await executeTSDFFusion(
                pointClouds: pointClouds,
                videoCount: depthResult.videoDepthFrames.count
            )

            // Stage 6: Scale calibration (Task 4.6)
            let calibrationResult = try await executeScaleCalibration(
                fusionResult: fusionResult,
                captureData: captureData
            )

            // Stage 7: Geometric constraints (Task 4.7)
            let constraintResult = try await executeGeometricConstraints(
                fusionResult: fusionResult,
                calibration: calibrationResult
            )

            // Stage 8: Room detection (Story 4.1)
            let roomStructure = try await executeRoomDetection(
                pointClouds: pointClouds,
                calibration: calibrationResult
            )

            // Stage 9: Cabinet detection (Story 4.2)
            let cabinetResult = try await executeCabinetDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult
            )

            // Stage 10: Appliance detection (Story 4.4)
            let applianceResult = try await executeApplianceDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult,
                cabinetResult: cabinetResult
            )

            // Stage 10.5: Special cabinet detection (Story 4.10)
            // Detects stacked uppers, refrigerator cabinets, appliance housing
            let updatedCabinetResult = try await executeSpecialCabinetDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult,
                cabinetResult: cabinetResult,
                applianceResult: applianceResult
            )

            // Stage 11: Island/Peninsula detection (Story 4.5)
            let islandPeninsulaResult = try await executeIslandPeninsulaDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult,
                cabinetResult: updatedCabinetResult,
                applianceResult: applianceResult
            )

            // Stage 12: Countertop detection (Story 4.6)
            let countertopResult = try await executeCountertopDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult,
                cabinetResult: updatedCabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult
            )

            // Stage 13: Opening detection (Story 4.9)
            let openingResult = try await executeOpeningDetection(
                roomStructure: roomStructure,
                pointClouds: pointClouds,
                calibration: calibrationResult,
                cabinetResult: updatedCabinetResult
            )

            // Stage 14: Measurement extraction (Story 4.7)
            let measurementResult = try await executeMeasurementExtraction(
                cabinetResult: updatedCabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult,
                countertopResult: countertopResult,
                openingResult: openingResult
            )

            // Stage 15: Confidence scoring (Story 4.8)
            // Story 6.2: Pass coverage percentage for confidence penalty
            // Story 6.4: Pass reflective surface impact from TSDF analysis
            let reflectiveSurfaceImpact = fusionResult.reflectiveSurfaceAnalysis?.confidenceImpact
            let confidenceScoringResult = try await executeConfidenceScoring(
                cabinetResult: updatedCabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult,
                countertopResult: countertopResult,
                openingResult: openingResult,
                measurementResult: measurementResult,
                coveragePercentage: captureData.coverageState?.coveragePercentage,
                reflectiveSurfaceImpact: reflectiveSurfaceImpact
            )

            // Stage 16: Complete (Task 4.8)
            // Issue #7 fix: Use actualFrameCount from depth estimation, not empty frames array
            // Story 6.2: Pass coverage state from capture phase for partial capture handling
            let result = buildFinalResult(
                constraintResult: constraintResult,
                calibration: calibrationResult,
                fusionResult: fusionResult,
                roomStructure: roomStructure,
                cabinetResult: updatedCabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult,
                countertopResult: countertopResult,
                openingResult: openingResult,
                measurementResult: measurementResult,
                confidenceScores: confidenceScoringResult,
                frameCount: actualFrameCount,
                photoCount: captureData.photos.count,
                coverageState: captureData.coverageState
            )

            // Mark complete
            state = .completed
            progress = 1.0
            currentPhase = .complete

            // Issue #3 fix: Store result so ProcessingView can access it
            self.result = result

            #if DEBUG
            timeLogger.logSummary()

            // Story 6.9 Task 4: End-to-end performance validation
            let validationResult = performanceValidator.finishValidation(timeLogger: timeLogger)
            if validationResult.hasFailures {
                logger.warning("⚠️ Performance validation has failures: \(validationResult.overallStatus.rawValue)")
                for rec in validationResult.recommendations {
                    logger.warning("  → \(rec)")
                }
            } else if validationResult.overallStatus == .warn {
                logger.info("⚠️ Performance validation has warnings")
            } else {
                logger.info("✅ Performance validation passed all NFRs")
            }
            #endif

            logger.info("Pipeline completed successfully in \(result.processingTimeMs)ms")

            return result

        } catch is CancellationError {
            logger.info("Pipeline was cancelled")
            state = .cancelled
            throw AIPipelineError.cancelled

        } catch let pipelineError as AIPipelineError {
            logger.error("Pipeline failed: \(pipelineError.localizedDescription)")
            state = .failed(pipelineError)
            error = pipelineError
            savePartialResults()
            throw pipelineError

        } catch {
            logger.error("Pipeline failed with unexpected error: \(error.localizedDescription)")
            let pipelineError = mapToPipelineError(error)
            state = .failed(pipelineError)
            self.error = pipelineError
            savePartialResults()
            throw pipelineError
        }
    }

    // MARK: - Stage 1: Model Loading (Task 4.1)

    private func executeModelLoading() async throws {
        currentPhase = .modelLoading
        progress = AIPipelinePhase.modelLoading.startProgress

        #if DEBUG
        timeLogger.startStep(.modelLoading)
        #endif

        logger.info("Stage 1: Loading models...")

        do {
            try Task.checkCancellation()

            // Load models with retry
            try await modelManager.loadModelsWithRetry()

            progress = AIPipelinePhase.modelLoading.endProgress

            #if DEBUG
            timeLogger.endStep(.modelLoading)
            timeLogger.logMemory(at: .modelLoading)
            #endif

            logger.info("Models loaded successfully")

        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIPipelineError.modelLoadingFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Stage 2: Frame Extraction (Task 4.2)

    private func executeFrameExtraction(
        from captureData: AICaptureSessionData
    ) async throws -> (frames: [Any], poses: [TimestampedPose]) {
        currentPhase = .frameExtraction
        progress = AIPipelinePhase.frameExtraction.startProgress

        #if DEBUG
        timeLogger.startStep(.frameExtraction)
        #endif

        logger.info("Stage 2: Extracting frames...")

        try Task.checkCancellation()

        // Frame extraction is handled internally by DepthEstimator
        // We just need to prepare the poses from photos
        let poses = captureData.photos.map { photo in
            TimestampedPose(timestamp: photo.timestamp, pose: photo.pose)
        }

        // Task 4.2.1: Validate we have sufficient frames
        // Note: Actual frame count validation happens in depth estimation
        // Here we just check if we have video data
        guard captureData.videoURL != nil else {
            throw AIPipelineError.frameExtractionFailed(reason: "No video file in capture data")
        }

        progress = AIPipelinePhase.frameExtraction.endProgress

        #if DEBUG
        timeLogger.endStep(.frameExtraction)
        timeLogger.logMemory(at: .frameExtraction)
        #endif

        logger.info("Frame extraction setup complete with \(poses.count) photo poses")

        // Return empty frames array - actual extraction happens in DepthEstimator
        return (frames: [], poses: poses)
    }

    // MARK: - Stage 3: Depth Estimation (Task 4.3)

    private func executeDepthEstimation(
        sessionData: AICaptureSessionData,
        poses: [TimestampedPose]
    ) async throws -> DepthEstimationResult {
        currentPhase = .depthEstimation
        progress = AIPipelinePhase.depthEstimation.startProgress

        #if DEBUG
        timeLogger.startStep(.depthInference)
        #endif

        logger.info("Stage 3: Estimating depth...")

        // Subscribe to depth estimator progress
        var cancellable: AnyCancellable?

        cancellable = depthEstimator.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.depthEstimation.mapSubProgress(subProgress)
                self.updateEstimatedTime()
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let result = try await depthEstimator.estimateDepth(
                from: sessionData,
                poses: poses
            )

            // Task 4.3.1: Validate depth estimation
            if result.allDepthFrames.isEmpty {
                throw AIPipelineError.depthEstimationFailed(
                    reason: "No valid depth data - try with better lighting"
                )
            }

            // Add warning if frame count is low
            if result.videoDepthFrames.count < Self.minimumFrameCount {
                warnings.append(PipelineWarning(
                    stage: .depthEstimation,
                    message: "Limited video frames may reduce accuracy",
                    severity: .info
                ))
            }

            progress = AIPipelinePhase.depthEstimation.endProgress

            // Issue #7 fix: Track actual frame count for final result
            actualFrameCount = result.totalFrameCount

            #if DEBUG
            timeLogger.endStep(.depthInference)
            timeLogger.logMemory(at: .depthInference)
            #endif

            logger.info("Depth estimation complete: \(result.totalFrameCount) frames processed")

            // Story 6.8: Cache depth frames and save checkpoint (ADR-1: 50%)
            cachedDepthFrames = result.allDepthFrames
            saveCheckpoint(at: .depthEstimation)

            return result

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIPipelineError {
            throw error
        } catch {
            throw AIPipelineError.depthEstimationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Stage 4: Point Cloud Generation (Task 4.4)

    private func executePointCloudGeneration(
        depthFrames: [AIDepthFrame],
        videoFrameCount: Int
    ) async throws -> [AIPointCloud] {
        currentPhase = .pointCloudGeneration
        progress = AIPipelinePhase.pointCloudGeneration.startProgress

        #if DEBUG
        timeLogger.startStep(.pointCloudGeneration)
        #endif

        logger.info("Stage 4: Generating point clouds from \(depthFrames.count) depth frames...")

        // Subscribe to point cloud generator progress
        var cancellable: AnyCancellable?

        cancellable = pointCloudGenerator.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.pointCloudGeneration.mapSubProgress(subProgress)
                self.updateEstimatedTime()
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Task 8.3: Use autoreleasepool for batch processing to control memory
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PointCloudGenerationResult, Error>) in
                Task { @MainActor in
                    do {
                        let res = try await self.pointCloudGenerator.generatePointClouds(
                            from: depthFrames,
                            videoFrameCount: videoFrameCount
                        )
                        continuation.resume(returning: res)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            var pointClouds = result.pointClouds

            // Task 4.4.1: Validate point clouds
            let totalPoints = pointClouds.reduce(0) { $0 + $1.count }

            if totalPoints == 0 {
                throw AIPipelineError.pointCloudGenerationFailed(
                    reason: "All point clouds are empty"
                )
            }

            // Apply voxel downsampling if excessive points (>2M)
            // Task 8.3: Process in batches with autoreleasepool
            if totalPoints > Self.maxPointCount {
                logger.warning("Point count (\(totalPoints)) exceeds limit, applying downsampling")
                var downsampledClouds: [AIPointCloud] = []
                downsampledClouds.reserveCapacity(pointClouds.count)

                // Process in batches with autoreleasepool for memory management
                let batchSize = 10
                for batchStart in stride(from: 0, to: pointClouds.count, by: batchSize) {
                    autoreleasepool {
                        let batchEnd = min(batchStart + batchSize, pointClouds.count)
                        for i in batchStart..<batchEnd {
                            let downsampled = pointCloudGenerator.downsamplePointCloud(pointClouds[i], factor: 2)
                            downsampledClouds.append(downsampled)
                        }
                    }
                }
                pointClouds = downsampledClouds
            }

            progress = AIPipelinePhase.pointCloudGeneration.endProgress

            #if DEBUG
            timeLogger.endStep(.pointCloudGeneration)
            timeLogger.logMemory(at: .pointCloudGeneration)
            #endif

            logger.info("Point cloud generation complete: \(pointClouds.count) clouds, \(totalPoints) total points")

            // Story 6.8: Cache point clouds for checkpoint restore
            cachedPointClouds = pointClouds

            return pointClouds

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIPipelineError {
            throw error
        } catch {
            throw AIPipelineError.pointCloudGenerationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Stage 5: TSDF Fusion (Task 4.5)

    private func executeTSDFFusion(
        pointClouds: [AIPointCloud],
        videoCount: Int
    ) async throws -> TSDFFusionResult {
        currentPhase = .tsdfFusion
        progress = AIPipelinePhase.tsdfFusion.startProgress

        #if DEBUG
        timeLogger.startStep(.tsdfFusion)
        #endif

        logger.info("Stage 5: Fusing \(pointClouds.count) point clouds...")

        // Subscribe to TSDF fusion progress
        var cancellable: AnyCancellable?

        cancellable = tsdfFusion.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.tsdfFusion.mapSubProgress(subProgress)
                self.updateEstimatedTime()
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Memory check before heavy operation
            try checkMemoryUsage()

            let result = try await tsdfFusion.fuse(
                pointClouds: pointClouds,
                videoCount: videoCount
            )

            // Task 4.5.1: Validate fusion quality
            if result.qualityMetrics.coveragePercentage < Self.minimumCoveragePercentage {
                warnings.append(PipelineWarning(
                    stage: .tsdfFusion,
                    message: "Limited coverage - result may be incomplete",
                    severity: .caution
                ))
            }

            if result.mesh.isEmpty {
                throw AIPipelineError.fusionFailed(reason: "Mesh extraction produced empty mesh")
            }

            // Store partial result for debugging
            partialResults = PartialPipelineResults(fusionResult: result)

            progress = AIPipelinePhase.tsdfFusion.endProgress

            #if DEBUG
            timeLogger.endStep(.tsdfFusion)
            timeLogger.logMemory(at: .tsdfFusion)
            #endif

            logger.info("TSDF fusion complete: \(result.mesh.triangleCount) triangles, \(String(format: "%.1f", result.qualityMetrics.coveragePercentage))% coverage")

            // Story 6.8: Cache fusion result and save checkpoint (ADR-1: 80%)
            cachedFusionResult = result
            saveCheckpoint(at: .tsdfFusion)

            return result

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIPipelineError {
            throw error
        } catch {
            throw AIPipelineError.fusionFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Stage 6: Scale Calibration (Task 4.6)

    private func executeScaleCalibration(
        fusionResult: TSDFFusionResult,
        captureData: AICaptureSessionData
    ) async throws -> ScaleCalibrationResult {
        currentPhase = .scaleCalibration
        progress = AIPipelinePhase.scaleCalibration.startProgress

        #if DEBUG
        timeLogger.startStep(.scaleCalibration)
        #endif

        logger.info("Stage 6: Calibrating scale...")

        // Subscribe to scale calibrator progress
        var cancellable: AnyCancellable?

        cancellable = scaleCalibrator.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.scaleCalibration.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let calibrationResult = try await scaleCalibrator.calibrate(fusionResult: fusionResult)

            // Task 4.6.1: Handle manual calibration fallback (AC7)
            if calibrationResult.calibrationMethod == .failed {
                logger.warning("Auto-calibration failed, requesting manual calibration")

                // Prepare manual calibration input
                let manualInput = ManualCalibrationInput(
                    fusionResult: fusionResult,
                    floorPlane: calibrationResult.floorPlane,
                    failureReason: calibrationResult.autoCalibrationFailureReason ?? "Unknown",
                    previewPhotoURL: captureData.photos.first?.url
                )

                // Signal need for manual calibration (state-based approach per Dev Notes)
                state = .awaitingManualCalibration(manualInput)

                // Wait for manual calibration result
                let manualResult = try await waitForManualCalibration()

                // Resume with manual result
                state = .running
                progress = AIPipelinePhase.scaleCalibration.endProgress

                #if DEBUG
                timeLogger.endStep(.scaleCalibration)
                #endif

                logger.info("Manual calibration complete: scale factor = \(manualResult.scaleFactor)")

                return manualResult
            }

            progress = AIPipelinePhase.scaleCalibration.endProgress

            #if DEBUG
            timeLogger.endStep(.scaleCalibration)
            timeLogger.logMemory(at: .scaleCalibration)
            #endif

            logger.info("Scale calibration complete: factor = \(calibrationResult.scaleFactor), confidence = \(String(describing: calibrationResult.confidenceLevel))")

            // Story 6.8: Cache calibration result and save checkpoint (ADR-1: 88%)
            cachedCalibrationResult = calibrationResult
            saveCheckpoint(at: .scaleCalibration)

            return calibrationResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIPipelineError {
            throw error
        } catch {
            throw AIPipelineError.calibrationFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Stage 7: Geometric Constraints (Task 4.7)

    private func executeGeometricConstraints(
        fusionResult: TSDFFusionResult,
        calibration: ScaleCalibrationResult
    ) async throws -> GeometricConstraintsResult {
        currentPhase = .geometricConstraints
        progress = AIPipelinePhase.geometricConstraints.startProgress

        #if DEBUG
        timeLogger.startStep(.geometricConstraints)
        #endif

        logger.info("Stage 7: Applying geometric constraints...")

        // Subscribe to geometric constraints progress
        var cancellable: AnyCancellable?

        cancellable = geometricConstraints.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.geometricConstraints.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let result = try await geometricConstraints.apply(
                to: fusionResult,
                calibration: calibration
            )

            progress = AIPipelinePhase.geometricConstraints.endProgress

            #if DEBUG
            timeLogger.endStep(.geometricConstraints)
            timeLogger.logMemory(at: .geometricConstraints)
            #endif

            logger.info("Geometric constraints complete: \(result.walls.count) walls, \(result.corners.count) corners")

            return result

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIPipelineError {
            throw error
        } catch {
            throw AIPipelineError.constraintsFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Point Cloud Helper

    /// Creates a calibrated point cloud from multiple point clouds by merging and scaling.
    ///
    /// - Parameters:
    ///   - pointClouds: Array of point clouds to merge
    ///   - calibration: Calibration result containing scale factor
    /// - Returns: Single merged and calibrated point cloud in inches
    private func createCalibratedPointCloud(
        from pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult
    ) -> AIPointCloud {
        // Merge point clouds into a single cloud
        var mergedPoints: [SIMD3<Float>] = []
        for var cloud in pointClouds {
            mergedPoints.append(contentsOf: cloud.getPoints())
        }

        // Apply scale factor to convert to inches
        let scaledPoints = mergedPoints.map { point in
            SIMD3<Float>(
                point.x * calibration.scaleFactor,
                point.y * calibration.scaleFactor,
                point.z * calibration.scaleFactor
            )
        }

        return AIPointCloud(points: scaledPoints)
    }

    // MARK: - Stage 8: Room Detection (Story 4.1)

    private func executeRoomDetection(
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult
    ) async throws -> AIRoomStructure? {
        currentPhase = .roomDetection
        progress = AIPipelinePhase.roomDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.roomDetection)
        #endif

        logger.info("Stage 8: Detecting room structure...")

        // Subscribe to room detector progress
        var cancellable: AnyCancellable?

        cancellable = roomDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.roomDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let roomStructure = try await roomDetector.detect(from: calibratedCloud)

            progress = AIPipelinePhase.roomDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.roomDetection)
            timeLogger.logMemory(at: .roomDetection)
            #endif

            logger.info("Room detection complete: \(roomStructure.roomShape.rawValue) room, \(roomStructure.walls.count) walls")

            return roomStructure

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RoomDetectionError {
            // Room detection failure is non-fatal - we can continue without it
            logger.warning("Room detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .roomDetection,
                message: "Room detection failed - cabinet detection may be less accurate",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Room detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .roomDetection,
                message: "Room detection failed - cabinet detection may be less accurate",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 9: Cabinet Detection (Story 4.2)

    private func executeCabinetDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult
    ) async throws -> CabinetDetectionResult? {
        currentPhase = .cabinetDetection
        progress = AIPipelinePhase.cabinetDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.cabinetDetection)
        #endif

        logger.info("Stage 9: Detecting cabinets...")

        // Subscribe to cabinet detector progress
        var cancellable: AnyCancellable?

        cancellable = cabinetDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.cabinetDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Cabinet detection requires room structure
            guard let roomStructure = roomStructure else {
                logger.warning("Cabinet detection skipped - no room structure available")
                warnings.append(PipelineWarning(
                    stage: .cabinetDetection,
                    message: "Cabinet detection skipped - room not detected",
                    severity: .caution
                ))
                return nil
            }

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let cabinetResult = try await cabinetDetector.detect(
                roomStructure: roomStructure,
                pointCloud: calibratedCloud
            )

            progress = AIPipelinePhase.cabinetDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.cabinetDetection)
            timeLogger.logMemory(at: .cabinetDetection)
            #endif

            logger.info("Cabinet detection complete: \(cabinetResult.totalCount) cabinets (\(cabinetResult.baseCabinets.count) base, \(cabinetResult.upperCabinets.count) upper, \(cabinetResult.tallCabinets.count) tall)")

            // Add any warnings from cabinet detection
            for warning in cabinetResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .cabinetDetection,
                    message: warning,
                    severity: .info
                ))
            }

            return cabinetResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CabinetDetectionError {
            // Cabinet detection failure is non-fatal - we can continue without it
            logger.warning("Cabinet detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .cabinetDetection,
                message: "Cabinet detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Cabinet detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .cabinetDetection,
                message: "Cabinet detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 10: Appliance Detection (Story 4.4)

    private func executeApplianceDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult,
        cabinetResult: CabinetDetectionResult?
    ) async throws -> ApplianceDetectionResult? {
        currentPhase = .applianceDetection
        progress = AIPipelinePhase.applianceDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.applianceDetection)
        #endif

        logger.info("Stage 10: Detecting appliances...")

        // Subscribe to appliance detector progress
        var cancellable: AnyCancellable?

        cancellable = applianceDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.applianceDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Appliance detection requires room structure and cabinets
            guard let roomStructure = roomStructure else {
                logger.warning("Appliance detection skipped - no room structure available")
                warnings.append(PipelineWarning(
                    stage: .applianceDetection,
                    message: "Appliance detection skipped - room not detected",
                    severity: .caution
                ))
                return nil
            }

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let applianceResult = try await applianceDetector.detect(
                roomStructure: roomStructure,
                pointCloud: calibratedCloud,
                cabinets: cabinetResult ?? CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
                islands: [] // Islands detected in next stage
            )

            progress = AIPipelinePhase.applianceDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.applianceDetection)
            timeLogger.logMemory(at: .applianceDetection)
            #endif

            logger.info("Appliance detection complete: \(applianceResult.appliances.count) appliances")

            // Add any warnings from appliance detection
            for warning in applianceResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .applianceDetection,
                    message: warning,
                    severity: .info
                ))
            }

            return applianceResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ApplianceDetectionError {
            // Appliance detection failure is non-fatal
            logger.warning("Appliance detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .applianceDetection,
                message: "Appliance detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Appliance detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .applianceDetection,
                message: "Appliance detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 10.5: Special Cabinet Detection (Story 4.10)

    private func executeSpecialCabinetDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult,
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?
    ) async throws -> CabinetDetectionResult? {
        // Special cabinet detection requires cabinet results
        guard let cabinetResult = cabinetResult else {
            logger.info("Special cabinet detection skipped - no cabinet result")
            return nil
        }

        guard let roomStructure = roomStructure else {
            logger.warning("Special cabinet detection skipped - no room structure")
            return cabinetResult
        }

        if applianceResult == nil {
            logger.info("Special cabinet detection - no appliance result (proceeding without appliance cabinets)")
        }

        logger.info("Stage 10.5: Detecting special cabinets (stacked, refrigerator upper, appliance housing)...")

        do {
            try Task.checkCancellation()

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let specialResult = await specialCabinetDetector.detect(
                cabinets: cabinetResult.cabinets,
                appliances: applianceResult ?? ApplianceDetectionResult(
                    appliances: [],
                    processingTimeMs: 0,
                    warnings: []
                ),
                roomStructure: roomStructure,
                pointCloud: calibratedCloud
            )

            // Create updated cabinet detection result with special cabinets
            let updatedResult = CabinetDetectionResult(
                cabinets: specialResult.cabinets,
                wallCoverageValidation: cabinetResult.wallCoverageValidation,
                processingTimeMs: cabinetResult.processingTimeMs + specialResult.processingTimeMs,
                warnings: cabinetResult.warnings + specialResult.warnings
            )

            logger.info("Special cabinet detection complete: \(specialResult.stackedCount) stacked, \(specialResult.refrigeratorUpperCount) fridge upper, \(specialResult.microwaveHousingCount) microwave housing, \(specialResult.ovenHousingCount) oven housing")

            // Add warnings for empty spaces
            for emptySpace in specialResult.emptySpacesAboveRefrigerator {
                warnings.append(PipelineWarning(
                    stage: .cabinetDetection,
                    message: "Empty space above \(emptySpace.applianceType) - upsell opportunity",
                    severity: .info
                ))
            }

            // Add any warnings from special detection
            for warning in specialResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .cabinetDetection,
                    message: warning,
                    severity: .info
                ))
            }

            return updatedResult

        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("Special cabinet detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .cabinetDetection,
                message: "Special cabinet detection failed - stacked/appliance cabinets may not be flagged",
                severity: .caution
            ))
            return cabinetResult
        }
    }

    // MARK: - Stage 11: Island/Peninsula Detection (Story 4.5)

    private func executeIslandPeninsulaDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult,
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?
    ) async throws -> IslandPeninsulaDetectionResult? {
        currentPhase = .islandPeninsulaDetection
        progress = AIPipelinePhase.islandPeninsulaDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.islandPeninsulaDetection)
        #endif

        logger.info("Stage 11: Detecting islands and peninsulas...")

        // Subscribe to island/peninsula detector progress
        var cancellable: AnyCancellable?

        cancellable = islandPeninsulaDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.islandPeninsulaDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Island detection requires room structure
            guard let roomStructure = roomStructure else {
                logger.warning("Island/peninsula detection skipped - no room structure available")
                warnings.append(PipelineWarning(
                    stage: .islandPeninsulaDetection,
                    message: "Island detection skipped - room not detected",
                    severity: .caution
                ))
                return nil
            }

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let islandResult = try await islandPeninsulaDetector.detect(
                roomStructure: roomStructure,
                pointCloud: calibratedCloud,
                cabinets: cabinetResult ?? CabinetDetectionResult(cabinets: [], wallCoverageValidation: [], processingTimeMs: 0, warnings: []),
                appliances: applianceResult ?? ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: [])
            )

            progress = AIPipelinePhase.islandPeninsulaDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.islandPeninsulaDetection)
            timeLogger.logMemory(at: .islandPeninsulaDetection)
            #endif

            logger.info("Island/peninsula detection complete: \(islandResult.islands.count) islands, \(islandResult.peninsulas.count) peninsulas")

            // Add any warnings from island detection
            for warning in islandResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .islandPeninsulaDetection,
                    message: warning,
                    severity: .info
                ))
            }

            return islandResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as IslandPeninsulaDetectionError {
            // Island detection failure is non-fatal
            logger.warning("Island/peninsula detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .islandPeninsulaDetection,
                message: "Island detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Island/peninsula detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .islandPeninsulaDetection,
                message: "Island detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 12: Countertop Detection (Story 4.6)

    private func executeCountertopDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult,
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?
    ) async throws -> CountertopDetectorResult? {
        currentPhase = .countertopDetection
        progress = AIPipelinePhase.countertopDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.countertopDetection)
        #endif

        logger.info("Stage 12: Detecting countertops...")

        // Subscribe to countertop detector progress
        var cancellable: AnyCancellable?

        cancellable = countertopDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.countertopDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Countertop detection requires room structure and cabinets
            guard let roomStructure = roomStructure else {
                logger.warning("Countertop detection skipped - no room structure available")
                warnings.append(PipelineWarning(
                    stage: .countertopDetection,
                    message: "Countertop calculation skipped - room not detected",
                    severity: .caution
                ))
                return nil
            }

            guard let cabinetResult = cabinetResult else {
                logger.warning("Countertop detection skipped - no cabinets detected")
                warnings.append(PipelineWarning(
                    stage: .countertopDetection,
                    message: "Countertop calculation skipped - no cabinets detected",
                    severity: .caution
                ))
                return nil
            }

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let countertopResult = try await countertopDetector.detect(
                roomStructure: roomStructure,
                pointCloud: calibratedCloud,
                cabinets: cabinetResult,
                appliances: applianceResult ?? ApplianceDetectionResult(appliances: [], processingTimeMs: 0, warnings: []),
                islandPeninsulaResult: islandPeninsulaResult ?? IslandPeninsulaDetectionResult.empty
            )

            progress = AIPipelinePhase.countertopDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.countertopDetection)
            timeLogger.logMemory(at: .countertopDetection)
            #endif

            logger.info("Countertop detection complete: \(countertopResult.wallCountertops.count) wall countertops, total \(String(format: "%.1f", countertopResult.countertopSummary.totalSquareFeet)) sq ft")

            // Add any warnings from countertop detection
            for warning in countertopResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .countertopDetection,
                    message: warning,
                    severity: .info
                ))
            }

            // Add prominent warning if confidence is low (AC9)
            if countertopResult.overallConfidence == .low {
                warnings.append(PipelineWarning(
                    stage: .countertopDetection,
                    message: "Countertop measurements have low confidence - field verification strongly recommended",
                    severity: .caution
                ))
            }

            return countertopResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CountertopDetectionError {
            // Countertop detection failure is non-fatal
            logger.warning("Countertop detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .countertopDetection,
                message: "Countertop calculation failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Countertop detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .countertopDetection,
                message: "Countertop calculation failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 13: Opening Detection (Story 4.9)

    private func executeOpeningDetection(
        roomStructure: AIRoomStructure?,
        pointClouds: [AIPointCloud],
        calibration: ScaleCalibrationResult,
        cabinetResult: CabinetDetectionResult?
    ) async throws -> OpeningDetectionResult? {
        currentPhase = .openingDetection
        progress = AIPipelinePhase.openingDetection.startProgress

        #if DEBUG
        timeLogger.startStep(.openingDetection)
        #endif

        logger.info("Stage 13: Detecting windows and doors...")

        // Subscribe to opening detector progress
        var cancellable: AnyCancellable?

        cancellable = openingDetector.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.openingDetection.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            // Opening detection requires room structure
            guard let roomStructure = roomStructure else {
                logger.warning("Opening detection skipped - no room structure available")
                warnings.append(PipelineWarning(
                    stage: .openingDetection,
                    message: "Opening detection skipped - room not detected",
                    severity: .caution
                ))
                return nil
            }

            let calibratedCloud = createCalibratedPointCloud(from: pointClouds, calibration: calibration)

            let openingResult = try await openingDetector.detect(
                roomStructure: roomStructure,
                pointCloud: calibratedCloud,
                cabinets: cabinetResult?.cabinets ?? []
            )

            progress = AIPipelinePhase.openingDetection.endProgress

            #if DEBUG
            timeLogger.endStep(.openingDetection)
            timeLogger.logMemory(at: .openingDetection)
            #endif

            logger.info("Opening detection complete: \(openingResult.windows.count) windows, \(openingResult.doors.count) doors")

            // Add any warnings from opening detection
            for warning in openingResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .openingDetection,
                    message: warning,
                    severity: .info
                ))
            }

            // Add warning for doors with clearance issues
            if !openingResult.doorsWithClearanceIssues.isEmpty {
                warnings.append(PipelineWarning(
                    stage: .openingDetection,
                    message: "\(openingResult.doorsWithClearanceIssues.count) door(s) may need fillers for adjacent cabinets",
                    severity: .info
                ))
            }

            return openingResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpeningDetectionError {
            // Opening detection failure is non-fatal
            logger.warning("Opening detection failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .openingDetection,
                message: error.userFriendlyMessage,
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Opening detection failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .openingDetection,
                message: "Opening detection failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 14: Measurement Extraction (Story 4.7)

    private func executeMeasurementExtraction(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?,
        openingResult: OpeningDetectionResult?
    ) async throws -> MeasurementExtractionResult? {
        currentPhase = .measurementExtraction
        progress = AIPipelinePhase.measurementExtraction.startProgress

        #if DEBUG
        timeLogger.startStep(.measurementExtraction)
        #endif

        logger.info("Stage 13: Extracting measurements...")

        // Subscribe to measurement extractor progress
        var cancellable: AnyCancellable?

        cancellable = measurementExtractor.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.measurementExtraction.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let measurementResult = try await measurementExtractor.extract(
                cabinetResult: cabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult,
                countertopResult: countertopResult
            )

            progress = AIPipelinePhase.measurementExtraction.endProgress

            #if DEBUG
            timeLogger.endStep(.measurementExtraction)
            timeLogger.logMemory(at: .measurementExtraction)
            #endif

            logger.info("Measurement extraction complete: \(measurementResult.allMeasurements.count) measurements, \(measurementResult.customSizeCount) custom sizes")

            // Add any warnings from measurement extraction
            for warning in measurementResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .measurementExtraction,
                    message: warning,
                    severity: .info
                ))
            }

            // Add discrepancy warnings
            if measurementResult.hasDiscrepancies {
                warnings.append(PipelineWarning(
                    stage: .measurementExtraction,
                    message: "Linear footage totals have discrepancies - review recommended",
                    severity: .caution
                ))
            }

            return measurementResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MeasurementExtractionError {
            // Measurement extraction failure is non-fatal
            logger.warning("Measurement extraction failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .measurementExtraction,
                message: "Measurement extraction failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Measurement extraction failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .measurementExtraction,
                message: "Measurement extraction failed - manual entry may be required",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 15: Confidence Scoring (Story 4.8)

    /// Calculates confidence scores for all detected objects.
    /// - Parameter coveragePercentage: Coverage percentage from capture phase (Story 6.2)
    private func executeConfidenceScoring(
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?,
        openingResult: OpeningDetectionResult?,
        measurementResult: MeasurementExtractionResult?,
        coveragePercentage: Float? = nil,
        reflectiveSurfaceImpact: Float? = nil  // Story 6.4
    ) async throws -> ConfidenceScoringResult? {
        currentPhase = .confidenceScoring
        progress = AIPipelinePhase.confidenceScoring.startProgress

        #if DEBUG
        timeLogger.startStep(.confidenceScoring)
        #endif

        logger.info("Stage 15: Calculating confidence scores...")

        // Subscribe to confidence scorer progress
        var cancellable: AnyCancellable?

        cancellable = confidenceScorer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subProgress in
                guard let self = self else { return }
                self.progress = AIPipelinePhase.confidenceScoring.mapSubProgress(subProgress)
            }

        defer { cancellable?.cancel() }

        do {
            try Task.checkCancellation()

            let scoringResult = try await confidenceScorer.calculateConfidence(
                cabinetResult: cabinetResult,
                applianceResult: applianceResult,
                islandPeninsulaResult: islandPeninsulaResult,
                countertopResult: countertopResult,
                openingResult: openingResult,
                measurementResult: measurementResult,
                coveragePercentage: coveragePercentage,
                reflectiveSurfaceImpact: reflectiveSurfaceImpact  // Story 6.4
            )

            progress = AIPipelinePhase.confidenceScoring.endProgress

            #if DEBUG
            timeLogger.endStep(.confidenceScoring)
            timeLogger.logMemory(at: .confidenceScoring)
            #endif

            logger.info("Confidence scoring complete: \(scoringResult.objectScores.count) objects scored, overall \(String(format: "%.0f", scoringResult.overallScore * 100))% (\(scoringResult.overallLevel.rawValue))")

            // Story 6.8: Save checkpoint after detection complete (ADR-1: 98%)
            saveCheckpoint(at: .confidenceScoring)

            // Add any warnings from confidence scoring
            for warning in scoringResult.warnings {
                warnings.append(PipelineWarning(
                    stage: .confidenceScoring,
                    message: warning,
                    severity: scoringResult.itemsNeedingVerification > 0 ? .caution : .info
                ))
            }

            return scoringResult

        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ConfidenceScoringError {
            // Confidence scoring failure is non-fatal
            logger.warning("Confidence scoring failed (non-fatal): \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .confidenceScoring,
                message: "Confidence scoring failed - results may need manual review",
                severity: .caution
            ))
            return nil
        } catch {
            logger.warning("Confidence scoring failed with unexpected error: \(error.localizedDescription)")
            warnings.append(PipelineWarning(
                stage: .confidenceScoring,
                message: "Confidence scoring failed - results may need manual review",
                severity: .caution
            ))
            return nil
        }
    }

    // MARK: - Stage 16: Build Final Result (Task 4.8)

    private func buildFinalResult(
        constraintResult: GeometricConstraintsResult,
        calibration: ScaleCalibrationResult,
        fusionResult: TSDFFusionResult,
        roomStructure: AIRoomStructure?,
        cabinetResult: CabinetDetectionResult?,
        applianceResult: ApplianceDetectionResult?,
        islandPeninsulaResult: IslandPeninsulaDetectionResult?,
        countertopResult: CountertopDetectorResult?,
        openingResult: OpeningDetectionResult?,
        measurementResult: MeasurementExtractionResult?,
        confidenceScores: ConfidenceScoringResult?,
        frameCount: Int,
        photoCount: Int,
        coverageState: AICoverageState?
    ) -> AIPipelineResult {
        let processingTime = startTime.map { Int((CFAbsoluteTimeGetCurrent() - $0) * 1000) } ?? 0

        let coverageQuality = CoverageQuality(
            coveragePercentage: fusionResult.qualityMetrics.coveragePercentage
        )

        // Story 6.2: Calculate coverage percentage and uncaptured zones from capture phase
        let coveragePercentage: Float?
        let uncapturedZones: Set<AICaptureZone>?

        if let state = coverageState {
            coveragePercentage = state.coveragePercentage
            // Compute uncaptured zones as all zones minus captured zones
            uncapturedZones = Set(AICaptureZone.allCases).subtracting(state.capturedZones)
        } else {
            // Backwards compatibility: nil means unknown (assume full coverage)
            coveragePercentage = nil
            uncapturedZones = nil
        }

        return AIPipelineResult(
            constrainedMesh: constraintResult.regularizedMesh,
            walls: constraintResult.walls,
            corners: constraintResult.corners,
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: cabinetResult,
            detectedAppliances: applianceResult,
            detectedIslandsPeninsulas: islandPeninsulaResult,
            detectedCountertops: countertopResult,
            detectedOpenings: openingResult,
            extractedMeasurements: measurementResult,
            confidenceScores: confidenceScores,
            processingTimeMs: processingTime,
            frameCount: frameCount,
            photoCount: photoCount,
            fusionQuality: fusionResult.qualityMetrics,
            constraintValidation: constraintResult.validation,
            coverageQuality: coverageQuality,
            warnings: warnings,
            coveragePercentage: coveragePercentage,
            uncapturedZones: uncapturedZones,
            originalMesh: constraintResult.originalMesh
        )
    }

    // MARK: - Cancellation Support (Task 6)

    /// Cancels the current processing.
    /// Called by ProcessingView when user taps cancel.
    func cancel() {
        logger.info("Cancel requested")
        state = .cancelled

        // Resume any waiting continuation with cancellation
        manualCalibrationContinuation?.resume(throwing: CancellationError())
        manualCalibrationContinuation = nil
    }

    // MARK: - Checkpoint Support (Story 6.8 Task 3)

    /// Saves a checkpoint at the current phase (Task 3.1).
    ///
    /// **Per ADR-1 (Checkpoint Granularity):**
    /// Called after 4 major stages: depth estimation (50%), TSDF fusion (80%),
    /// scale calibration (88%), detection complete (98%).
    ///
    /// - Parameter phase: The phase that just completed
    private func saveCheckpoint(at phase: AIPipelinePhase) {
        let checkpoint = PipelineCheckpoint(
            phase: phase,
            progress: progress,
            timestamp: Date(),
            depthFrameCount: cachedDepthFrames?.count,
            hasPointClouds: cachedPointClouds != nil,
            hasFusionResult: cachedFusionResult != nil,
            hasCalibrationResult: cachedCalibrationResult != nil,
            hasDetectionResults: phase == .confidenceScoring
        )

        lastCheckpoint = checkpoint
        logger.info("Checkpoint saved: \(checkpoint.description)")
    }

    /// Restores state from a checkpoint for retry (Task 3.4).
    ///
    /// **Per ADR-4 (Retry Behavior):**
    /// - Restores saved intermediate data
    /// - Creates FRESH processor instances (handled by caller)
    /// - Returns the phase to resume from
    ///
    /// - Parameter checkpoint: The checkpoint to restore from
    /// - Returns: The phase to resume processing from
    private func restoreFromCheckpoint(_ checkpoint: PipelineCheckpoint) -> AIPipelinePhase {
        // Restore progress state
        progress = checkpoint.progress
        currentPhase = checkpoint.phase

        logger.info("Restored from checkpoint: \(checkpoint.description)")

        return checkpoint.nextPhase
    }

    /// Retries processing from the last checkpoint (Task 4).
    ///
    /// **Per Story 6.8 AC3:**
    /// User selects "Retry" → processing restarts from last checkpoint
    /// → user doesn't have to re-capture.
    ///
    /// **Per ADR-4:**
    /// - Fresh processor instances avoid stuck state
    /// - Restored data preserves work already done
    ///
    /// **Implementation Note:**
    /// The cached intermediate results (depthFrames, pointClouds, fusionResult, calibrationResult)
    /// are preserved in memory on this orchestrator instance. When retry is called, we skip
    /// the stages that produced these cached results and resume from the checkpoint phase.
    ///
    /// - Parameter captureData: Original capture data to resume with
    /// - Returns: Pipeline result on success
    /// - Throws: AIPipelineError if retry fails
    func retry(captureData: AICaptureSessionData) async throws -> AIPipelineResult {
        guard let checkpoint = lastCheckpoint else {
            logger.warning("Retry called but no checkpoint available - starting fresh")
            return try await process(captureData: captureData)
        }

        logger.info("Retrying from checkpoint: \(checkpoint.description) at phase \(checkpoint.phase.rawValue)")

        // Reset state but DO NOT clear cached data (unlike full reset())
        state = .running
        error = nil
        warnings = []
        partialResults = nil
        manualCalibrationContinuation = nil
        result = nil
        startTime = CFAbsoluteTimeGetCurrent()

        // Restore progress from checkpoint
        progress = checkpoint.progress
        currentPhase = checkpoint.phase

        #if DEBUG
        timeLogger.reset()
        #endif

        do {
            // Resume processing from the checkpoint phase using cached data
            return try await resumeFromCheckpoint(checkpoint, captureData: captureData)
        } catch is CancellationError {
            logger.info("Retry pipeline was cancelled")
            state = .cancelled
            throw AIPipelineError.cancelled
        } catch let pipelineError as AIPipelineError {
            logger.error("Retry pipeline failed: \(pipelineError.localizedDescription)")
            state = .failed(pipelineError)
            error = pipelineError
            throw pipelineError
        } catch {
            logger.error("Retry pipeline failed with unexpected error: \(error.localizedDescription)")
            let pipelineError = mapToPipelineError(error)
            state = .failed(pipelineError)
            self.error = pipelineError
            throw pipelineError
        }
    }

    /// Resumes processing from a checkpoint using cached intermediate results.
    ///
    /// This method skips stages that have already been completed (as indicated by the checkpoint)
    /// and uses the cached results from those stages. It then continues processing from the
    /// checkpoint's next phase.
    ///
    /// - Parameters:
    ///   - checkpoint: The checkpoint to resume from
    ///   - captureData: Original capture data
    /// - Returns: Pipeline result on success
    private func resumeFromCheckpoint(
        _ checkpoint: PipelineCheckpoint,
        captureData: AICaptureSessionData
    ) async throws -> AIPipelineResult {
        logger.info("Resuming from checkpoint phase: \(checkpoint.phase.rawValue)")

        // Verify we have the cached data we need based on checkpoint phase
        switch checkpoint.phase {
        case .depthEstimation:
            // Checkpoint at 50% - we have depth frames, need to continue from point cloud generation
            guard let depthFrames = cachedDepthFrames, !depthFrames.isEmpty else {
                logger.warning("No cached depth frames for checkpoint - starting fresh")
                return try await process(captureData: captureData)
            }
            return try await continueFromPointCloudGeneration(
                depthFrames: depthFrames,
                captureData: captureData
            )

        case .tsdfFusion:
            // Checkpoint at 80% - we have fusion result, need to continue from scale calibration
            guard let fusionResult = cachedFusionResult,
                  let pointClouds = cachedPointClouds else {
                logger.warning("No cached fusion result for checkpoint - starting fresh")
                return try await process(captureData: captureData)
            }
            return try await continueFromScaleCalibration(
                fusionResult: fusionResult,
                pointClouds: pointClouds,
                captureData: captureData
            )

        case .scaleCalibration:
            // Checkpoint at 88% - we have calibration, need to continue from geometric constraints
            guard let fusionResult = cachedFusionResult,
                  let calibrationResult = cachedCalibrationResult,
                  let pointClouds = cachedPointClouds else {
                logger.warning("No cached calibration result for checkpoint - starting fresh")
                return try await process(captureData: captureData)
            }
            return try await continueFromGeometricConstraints(
                fusionResult: fusionResult,
                calibrationResult: calibrationResult,
                pointClouds: pointClouds,
                captureData: captureData
            )

        case .confidenceScoring:
            // Checkpoint at 98% - detection complete, just need to finalize
            // This is rare - if we timed out at 98%, something is very wrong
            logger.warning("Checkpoint at confidence scoring - restarting from scratch")
            return try await process(captureData: captureData)

        default:
            // For other phases, start fresh
            logger.warning("Checkpoint at unexpected phase \(checkpoint.phase.rawValue) - starting fresh")
            return try await process(captureData: captureData)
        }
    }

    /// Continues processing from point cloud generation stage using cached depth frames.
    private func continueFromPointCloudGeneration(
        depthFrames: [AIDepthFrame],
        captureData: AICaptureSessionData
    ) async throws -> AIPipelineResult {
        logger.info("Continuing from point cloud generation with \(depthFrames.count) cached depth frames")

        // Stage 4: Point cloud generation (using cached depth frames)
        let pointClouds = try await executePointCloudGeneration(
            depthFrames: depthFrames,
            videoFrameCount: depthFrames.count
        )

        // Continue with remaining stages
        return try await continueFromTSDFFusion(
            pointClouds: pointClouds,
            captureData: captureData
        )
    }

    /// Continues processing from TSDF fusion stage using cached point clouds.
    private func continueFromTSDFFusion(
        pointClouds: [AIPointCloud],
        captureData: AICaptureSessionData
    ) async throws -> AIPipelineResult {
        // Stage 5: TSDF fusion
        let fusionResult = try await executeTSDFFusion(
            pointClouds: pointClouds,
            videoCount: pointClouds.count
        )

        return try await continueFromScaleCalibration(
            fusionResult: fusionResult,
            pointClouds: pointClouds,
            captureData: captureData
        )
    }

    /// Continues processing from scale calibration stage.
    private func continueFromScaleCalibration(
        fusionResult: TSDFFusionResult,
        pointClouds: [AIPointCloud],
        captureData: AICaptureSessionData
    ) async throws -> AIPipelineResult {
        // Stage 6: Scale calibration
        let calibrationResult = try await executeScaleCalibration(
            fusionResult: fusionResult,
            captureData: captureData
        )

        return try await continueFromGeometricConstraints(
            fusionResult: fusionResult,
            calibrationResult: calibrationResult,
            pointClouds: pointClouds,
            captureData: captureData
        )
    }

    /// Continues processing from geometric constraints stage.
    private func continueFromGeometricConstraints(
        fusionResult: TSDFFusionResult,
        calibrationResult: ScaleCalibrationResult,
        pointClouds: [AIPointCloud],
        captureData: AICaptureSessionData
    ) async throws -> AIPipelineResult {
        // Stage 7: Geometric constraints
        let constraintResult = try await executeGeometricConstraints(
            fusionResult: fusionResult,
            calibration: calibrationResult
        )

        // Stage 8: Room detection
        let roomStructure = try await executeRoomDetection(
            pointClouds: pointClouds,
            calibration: calibrationResult
        )

        // Stage 9: Cabinet detection
        let cabinetResult = try await executeCabinetDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult
        )

        // Stage 10: Appliance detection
        let applianceResult = try await executeApplianceDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult,
            cabinetResult: cabinetResult
        )

        // Stage 10.5: Special cabinet detection
        let updatedCabinetResult = try await executeSpecialCabinetDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult,
            cabinetResult: cabinetResult,
            applianceResult: applianceResult
        )

        // Stage 11: Island/Peninsula detection
        let islandPeninsulaResult = try await executeIslandPeninsulaDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult,
            cabinetResult: updatedCabinetResult,
            applianceResult: applianceResult
        )

        // Stage 12: Countertop detection
        let countertopResult = try await executeCountertopDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult,
            cabinetResult: updatedCabinetResult,
            applianceResult: applianceResult,
            islandPeninsulaResult: islandPeninsulaResult
        )

        // Stage 13: Opening detection
        let openingResult = try await executeOpeningDetection(
            roomStructure: roomStructure,
            pointClouds: pointClouds,
            calibration: calibrationResult,
            cabinetResult: updatedCabinetResult
        )

        // Stage 14: Measurement extraction
        let measurementResult = try await executeMeasurementExtraction(
            cabinetResult: updatedCabinetResult,
            applianceResult: applianceResult,
            islandPeninsulaResult: islandPeninsulaResult,
            countertopResult: countertopResult,
            openingResult: openingResult
        )

        // Stage 15: Confidence scoring
        let reflectiveSurfaceImpact = fusionResult.reflectiveSurfaceAnalysis?.confidenceImpact
        let confidenceScoringResult = try await executeConfidenceScoring(
            cabinetResult: updatedCabinetResult,
            applianceResult: applianceResult,
            islandPeninsulaResult: islandPeninsulaResult,
            countertopResult: countertopResult,
            openingResult: openingResult,
            measurementResult: measurementResult,
            coveragePercentage: captureData.coverageState?.coveragePercentage,
            reflectiveSurfaceImpact: reflectiveSurfaceImpact
        )

        // Stage 16: Build final result
        let result = buildFinalResult(
            constraintResult: constraintResult,
            calibration: calibrationResult,
            fusionResult: fusionResult,
            roomStructure: roomStructure,
            cabinetResult: updatedCabinetResult,
            applianceResult: applianceResult,
            islandPeninsulaResult: islandPeninsulaResult,
            countertopResult: countertopResult,
            openingResult: openingResult,
            measurementResult: measurementResult,
            confidenceScores: confidenceScoringResult,
            frameCount: actualFrameCount,
            photoCount: captureData.photos.count,
            coverageState: captureData.coverageState
        )

        // Mark complete
        state = .completed
        progress = 1.0
        currentPhase = .complete
        self.result = result

        #if DEBUG
        timeLogger.logSummary()

        // Story 6.9 Task 4: End-to-end performance validation for retry path
        let validationResult = performanceValidator.finishValidation(timeLogger: timeLogger)
        if validationResult.hasFailures {
            logger.warning("⚠️ Retry performance validation has failures: \(validationResult.overallStatus.rawValue)")
        }
        #endif

        logger.info("Retry pipeline completed successfully in \(result.processingTimeMs)ms")

        return result
    }

    // MARK: - Manual Calibration Support (AC7)

    /// Waits for manual calibration result.
    /// Called when auto-calibration fails and pipeline is paused.
    private func waitForManualCalibration() async throws -> ScaleCalibrationResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.manualCalibrationContinuation = continuation
        }
    }

    /// Resumes pipeline with manual calibration result.
    /// Called by coordinator after user completes manual calibration.
    ///
    /// - Parameter result: The manual calibration result
    func resumeWithManualCalibration(_ result: ScaleCalibrationResult) {
        logger.info("Resuming pipeline with manual calibration result")
        manualCalibrationContinuation?.resume(returning: result)
        manualCalibrationContinuation = nil
    }

    // MARK: - Memory Management (Task 8)

    /// Checks memory usage and throws if exceeding limit.
    private func checkMemoryUsage() throws {
        let usage = getMemoryUsage()

        if usage > Self.memoryLimit {
            logger.error("Memory limit exceeded: \(usage / (1024 * 1024))MB > \(Self.memoryLimit / (1024 * 1024))MB")
            throw AIPipelineError.memoryLimitExceeded
        }

        #if DEBUG
        logger.debug("Memory usage: \(usage / (1024 * 1024))MB")
        #endif
    }

    /// Returns current memory usage in bytes.
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    // MARK: - Progress Estimation (Task 5.3)

    /// Updates estimated time remaining based on elapsed time and progress.
    private func updateEstimatedTime() {
        // Only show ETA after 20% progress (per Dev Notes)
        guard progress > 0.20, let startTime = startTime else {
            estimatedTimeRemaining = nil
            return
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let totalEstimate = elapsed / progress
        let remaining = totalEstimate - elapsed

        // Only update if estimate is reasonable (> 1 second)
        estimatedTimeRemaining = remaining > 1.0 ? remaining : nil
    }

    // MARK: - Error Mapping (Task 7)

    /// Maps underlying errors to pipeline errors.
    private func mapToPipelineError(_ error: Error) -> AIPipelineError {
        switch error {
        case let modelError as ModelError:
            return .modelLoadingFailed(reason: modelError.localizedDescription)
        case let depthError as DepthEstimationError:
            return .depthEstimationFailed(reason: depthError.localizedDescription)
        case let pcError as PointCloudGenerationError:
            return .pointCloudGenerationFailed(reason: pcError.localizedDescription)
        case let fusionError as TSDFFusionError:
            return .fusionFailed(reason: fusionError.localizedDescription)
        case let calibrationError as ScaleCalibrationError:
            return .calibrationFailed(reason: calibrationError.localizedDescription)
        case let constraintError as GeometricConstraintsError:
            return .constraintsFailed(reason: constraintError.localizedDescription)
        case let roomError as RoomDetectionError:
            return .roomDetectionFailed(reason: roomError.localizedDescription ?? "Unknown error")
        case let cabinetError as CabinetDetectionError:
            return .cabinetDetectionFailed(reason: cabinetError.localizedDescription ?? "Unknown error")
        case let applianceError as ApplianceDetectionError:
            return .applianceDetectionFailed(reason: applianceError.localizedDescription ?? "Unknown error")
        case let islandError as IslandPeninsulaDetectionError:
            return .islandPeninsulaDetectionFailed(reason: islandError.localizedDescription)
        case let countertopError as CountertopDetectionError:
            return .countertopDetectionFailed(reason: countertopError.localizedDescription ?? "Unknown error")
        case let openingError as OpeningDetectionError:
            return .openingDetectionFailed(reason: openingError.localizedDescription ?? "Unknown error")
        case let measurementError as MeasurementExtractionError:
            return .measurementExtractionFailed(reason: measurementError.localizedDescription ?? "Unknown error")
        default:
            // Map based on current phase
            switch currentPhase {
            case .modelLoading:
                return .modelLoadingFailed(reason: error.localizedDescription)
            case .frameExtraction:
                return .frameExtractionFailed(reason: error.localizedDescription)
            case .depthEstimation:
                return .depthEstimationFailed(reason: error.localizedDescription)
            case .pointCloudGeneration:
                return .pointCloudGenerationFailed(reason: error.localizedDescription)
            case .tsdfFusion:
                return .fusionFailed(reason: error.localizedDescription)
            case .scaleCalibration:
                return .calibrationFailed(reason: error.localizedDescription)
            case .geometricConstraints:
                return .constraintsFailed(reason: error.localizedDescription)
            case .roomDetection:
                return .roomDetectionFailed(reason: error.localizedDescription)
            case .cabinetDetection:
                return .cabinetDetectionFailed(reason: error.localizedDescription)
            case .applianceDetection:
                return .applianceDetectionFailed(reason: error.localizedDescription)
            case .islandPeninsulaDetection:
                return .islandPeninsulaDetectionFailed(reason: error.localizedDescription)
            case .countertopDetection:
                return .countertopDetectionFailed(reason: error.localizedDescription)
            case .openingDetection:
                return .openingDetectionFailed(reason: error.localizedDescription)
            case .measurementExtraction:
                return .measurementExtractionFailed(reason: error.localizedDescription)
            default:
                return .fusionFailed(reason: error.localizedDescription)
            }
        }
    }

    // MARK: - Partial Results (Task 7.2)

    /// Saves partial results for debugging on failure.
    private func savePartialResults() {
        #if DEBUG
        if let partial = partialResults {
            logger.debug("Partial results saved: mesh with \(partial.fusionResult.mesh.triangleCount) triangles")
        }
        #endif
    }

    // MARK: - Reset

    /// Resets the orchestrator to initial state.
    private func reset() {
        progress = 0.0
        currentPhase = .idle
        state = .idle
        error = nil
        estimatedTimeRemaining = nil
        warnings = []
        partialResults = nil
        startTime = nil
        manualCalibrationContinuation = nil
        actualFrameCount = 0
        result = nil

        // Story 6.8: Clear checkpoint data on fresh start
        lastCheckpoint = nil
        cachedDepthFrames = nil
        cachedPointClouds = nil
        cachedFusionResult = nil
        cachedCalibrationResult = nil
    }
}

// MARK: - Partial Pipeline Results

/// Container for partial results saved on failure (for debugging).
private struct PartialPipelineResults {
    let fusionResult: TSDFFusionResult
}
