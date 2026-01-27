//
//  ManualCalibrationViewModel.swift
//  cabinetscan
//
//  Created for Story 3.6: Manual Calibration Fallback
//

import Foundation
import Combine
import os.log

/// ViewModel for ManualCalibrationView.
///
/// Manages the manual calibration flow including option selection,
/// door width / ceiling height selection, and scale calculation.
///
/// **Usage:**
/// ```swift
/// let viewModel = ManualCalibrationViewModel(input: input, calibrator: calibrator)
/// // User selects door option
/// viewModel.selectOption(.door)
/// // User selects door width
/// viewModel.selectDoorWidth(.thirtyTwo)
/// // Calculate and apply scale
/// await viewModel.performCalibration()
/// ```
@MainActor
final class ManualCalibrationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Currently selected calibration option (door or ceiling)
    @Published var selectedOption: ManualCalibrationOption?

    /// Selected door width (when using door calibration)
    @Published var selectedDoorWidth: DoorWidth? = .thirtyTwo  // Default to most common

    /// Selected ceiling height (when using ceiling calibration)
    @Published var selectedCeilingHeight: CeilingHeight? = .eight  // Default to most common

    /// Current state of the calibration process
    @Published private(set) var calibrationState: ManualCalibrationState = .idle

    /// Whether calibration is currently in progress
    @Published private(set) var isCalibrating: Bool = false

    /// Error message to display (if any)
    @Published var errorMessage: String?

    /// Whether to show the error alert (for proper SwiftUI alert binding)
    @Published var showError: Bool = false

    // MARK: - Properties

    /// Input data for manual calibration
    let input: ManualCalibrationInput

    /// Reference to the scale calibrator (extended with manual methods)
    private let calibrator: ScaleCalibrator

    /// Callback when calibration completes successfully
    var onCalibrationComplete: ((ScaleCalibrationResult) -> Void)?

    /// Callback when user cancels calibration
    var onCancel: (() -> Void)?

    private let logger = Logger(subsystem: "com.cabinetscan", category: "ManualCalibrationViewModel")

    // MARK: - Computed Properties

    /// Whether the Continue button should be enabled
    var canContinue: Bool {
        switch selectedOption {
        case .door:
            return selectedDoorWidth != nil
        case .ceiling:
            return selectedCeilingHeight != nil
        case .none:
            return false
        }
    }

    /// Preview photo URL from captured session
    var previewPhotoURL: URL? {
        input.previewPhotoURL
    }

    /// Reason why auto-calibration failed
    var failureReason: String {
        input.failureReason
    }

    // MARK: - Initialization

    init(input: ManualCalibrationInput, calibrator: ScaleCalibrator) {
        self.input = input
        self.calibrator = calibrator
        logger.info("ManualCalibrationViewModel initialized. Failure reason: \(input.failureReason)")
    }

    // MARK: - Public Methods

    /// Selects a calibration option (door or ceiling)
    func selectOption(_ option: ManualCalibrationOption) {
        selectedOption = option
        errorMessage = nil
        logger.info("Selected calibration option: \(option.rawValue)")
    }

    /// Selects a door width for door-based calibration
    func selectDoorWidth(_ width: DoorWidth) {
        selectedDoorWidth = width
        errorMessage = nil
        logger.info("Selected door width: \(width.rawValue)\"")
    }

    /// Selects a ceiling height for ceiling-based calibration
    func selectCeilingHeight(_ height: CeilingHeight) {
        selectedCeilingHeight = height
        errorMessage = nil
        logger.info("Selected ceiling height: \(height.rawValue)\"")
    }

    /// Performs the manual calibration based on selected option and value
    func performCalibration() async {
        guard !isCalibrating else { return }

        isCalibrating = true
        calibrationState = .calculating
        errorMessage = nil

        logger.info("Starting manual calibration...")

        do {
            let result: ScaleCalibrationResult

            switch selectedOption {
            case .door:
                guard let doorWidth = selectedDoorWidth else {
                    throw ManualCalibrationError.noDoorWidthSelected
                }
                result = try await calibrator.calibrateManualDoor(
                    mesh: input.fusionResult.mesh,
                    floorPlane: input.floorPlane,
                    selectedWidthInches: doorWidth.rawValue,
                    failureReason: input.failureReason
                )

            case .ceiling:
                guard let ceilingHeight = selectedCeilingHeight else {
                    throw ManualCalibrationError.noCeilingHeightSelected
                }
                result = try await calibrator.calibrateManualCeiling(
                    mesh: input.fusionResult.mesh,
                    floorPlane: input.floorPlane,
                    selectedHeightInches: ceilingHeight.rawValue,
                    failureReason: input.failureReason
                )

            case .none:
                throw ManualCalibrationError.noOptionSelected
            }

            logger.info("Manual calibration complete: scaleFactor=\(result.scaleFactor), method=\(String(describing: result.calibrationMethod))")

            calibrationState = .complete(result)
            isCalibrating = false
            onCalibrationComplete?(result)

        } catch {
            logger.error("Manual calibration failed: \(error.localizedDescription)")

            let errorString = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            calibrationState = .error(errorString)
            errorMessage = errorString
            showError = true
            isCalibrating = false
        }
    }

    /// Retries calibration after an error
    func retry() {
        calibrationState = .idle
        errorMessage = nil
        showError = false
    }

    /// Continues with estimated scale when calibration fails but user chooses to proceed
    func continueWithEstimate() {
        logger.warning("User chose to continue with estimated scale")

        // Estimate scale based on mesh bounding box height assuming 8' (96") ceiling
        // This is better than 1.0 which would leave measurements in mesh units
        let meshHeight = input.fusionResult.boundingBox.max.y - input.fusionResult.boundingBox.min.y
        let estimatedScaleFactor: Float
        if meshHeight > 0 {
            // Assume room height is approximately 96" (8' ceiling)
            estimatedScaleFactor = 96.0 / meshHeight
        } else {
            // Fallback to 1.0 only if mesh height is invalid
            estimatedScaleFactor = 1.0
        }

        logger.info("Using estimated scale factor: \(estimatedScaleFactor) (mesh height: \(meshHeight))")

        // Create a result with LOW confidence using the estimated scale
        let estimatedResult = ScaleCalibrationResult(
            scaleFactor: estimatedScaleFactor,
            calibrationMethod: selectedOption == .door ? .manualDoor : .manualCeiling,
            confidenceLevel: .low,
            countertopHeightInches: nil,
            ceilingHeightInches: 96.0,  // Assumed ceiling height
            floorPlane: input.floorPlane,
            validationResults: .empty,
            processingTimeMs: 0,
            autoCalibrationFailureReason: input.failureReason
        )

        calibrationState = .complete(estimatedResult)
        showError = false
        onCalibrationComplete?(estimatedResult)
    }

    /// Cancels the calibration flow
    func cancel() {
        logger.info("Manual calibration cancelled by user")
        onCancel?()
    }
}

// MARK: - Manual Calibration Errors

enum ManualCalibrationError: LocalizedError {
    case noOptionSelected
    case noDoorWidthSelected
    case noCeilingHeightSelected
    case planeDetectionFailed

    var errorDescription: String? {
        switch self {
        case .noOptionSelected:
            return "Please select a calibration option"
        case .noDoorWidthSelected:
            return "Please select a door width"
        case .noCeilingHeightSelected:
            return "Please select a ceiling height"
        case .planeDetectionFailed:
            return "Could not detect floor or ceiling planes in the scan"
        }
    }
}
