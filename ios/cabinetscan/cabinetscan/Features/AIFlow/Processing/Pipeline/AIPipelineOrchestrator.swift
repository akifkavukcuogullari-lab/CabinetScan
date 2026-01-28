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

    private let logger = Logger(subsystem: "com.cabinetscan", category: "AIPipelineOrchestrator")

    // MARK: - Internal State

    /// Time logger for performance tracking
    #if DEBUG
    private let timeLogger = ProcessingTimeLogger()
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
        cabinetDetector: CabinetDetector
    ) {
        self.modelManager = modelManager
        self.depthEstimator = depthEstimator
        self.pointCloudGenerator = pointCloudGenerator
        self.tsdfFusion = tsdfFusion
        self.scaleCalibrator = scaleCalibrator
        self.geometricConstraints = geometricConstraints
        self.roomDetector = roomDetector
        self.cabinetDetector = cabinetDetector
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

            // Stage 10: Complete (Task 4.8)
            // Issue #7 fix: Use actualFrameCount from depth estimation, not empty frames array
            let result = buildFinalResult(
                constraintResult: constraintResult,
                calibration: calibrationResult,
                fusionResult: fusionResult,
                roomStructure: roomStructure,
                cabinetResult: cabinetResult,
                frameCount: actualFrameCount,
                photoCount: captureData.photos.count
            )

            // Mark complete
            state = .completed
            progress = 1.0
            currentPhase = .complete

            // Issue #3 fix: Store result so ProcessingView can access it
            self.result = result

            #if DEBUG
            timeLogger.logSummary()
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

    // MARK: - Stage 10: Build Final Result (Task 4.8)

    private func buildFinalResult(
        constraintResult: GeometricConstraintsResult,
        calibration: ScaleCalibrationResult,
        fusionResult: TSDFFusionResult,
        roomStructure: AIRoomStructure?,
        cabinetResult: CabinetDetectionResult?,
        frameCount: Int,
        photoCount: Int
    ) -> AIPipelineResult {
        let processingTime = startTime.map { Int((CFAbsoluteTimeGetCurrent() - $0) * 1000) } ?? 0

        let coverageQuality = CoverageQuality(
            coveragePercentage: fusionResult.qualityMetrics.coveragePercentage
        )

        return AIPipelineResult(
            constrainedMesh: constraintResult.regularizedMesh,
            walls: constraintResult.walls,
            corners: constraintResult.corners,
            calibration: calibration,
            roomStructure: roomStructure,
            detectedCabinets: cabinetResult,
            processingTimeMs: processingTime,
            frameCount: frameCount,
            photoCount: photoCount,
            fusionQuality: fusionResult.qualityMetrics,
            constraintValidation: constraintResult.validation,
            coverageQuality: coverageQuality,
            warnings: warnings,
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
    }
}

// MARK: - Partial Pipeline Results

/// Container for partial results saved on failure (for debugging).
private struct PartialPipelineResults {
    let fusionResult: TSDFFusionResult
}
