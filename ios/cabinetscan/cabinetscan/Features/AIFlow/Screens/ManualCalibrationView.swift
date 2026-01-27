//
//  ManualCalibrationView.swift
//  cabinetscan
//
//  Created for Story 3.6: Manual Calibration Fallback
//

// TODO: [L2] Localization - Strings in this file are hardcoded in English.
// Consider using LocalizedStringKey or NSLocalizedString for i18n support.
// Affected strings: titles, subtitles, button labels, help text.

import SwiftUI

/// Manual calibration view displayed when automatic calibration fails.
///
/// Provides two calibration options:
/// 1. Door width calibration (preferred) - uses standard US door widths
/// 2. Ceiling height calibration - uses standard US ceiling heights
///
/// **UX Design Reference:** UX-6 ManualCalibrationView
struct ManualCalibrationView: View {
    @StateObject var viewModel: ManualCalibrationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.selectedOption {
                case .none:
                    optionSelectionView
                case .door:
                    doorWidthSelectionView
                case .ceiling:
                    ceilingHeightSelectionView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .alert("Calibration Error", isPresented: $viewModel.showError) {
                Button("Retry") {
                    viewModel.retry()
                }
                Button("Continue Anyway") {
                    viewModel.continueWithEstimate()
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .overlay {
                if viewModel.isCalibrating {
                    calibrationProgressOverlay
                }
            }
        }
    }

    // MARK: - Option Selection View

    private var optionSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            Text("Let's calibrate your measurements")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            // Subtitle
            Text("We need a reference to measure accurately.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            // Option buttons
            VStack(spacing: 16) {
                // Door option (recommended)
                CalibrationOptionButton(
                    option: .door,
                    isRecommended: true
                ) {
                    viewModel.selectOption(.door)
                }

                // Ceiling option
                CalibrationOptionButton(
                    option: .ceiling,
                    isRecommended: false
                ) {
                    viewModel.selectOption(.ceiling)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Door Width Selection View

    private var doorWidthSelectionView: some View {
        VStack(spacing: 24) {
            // Back button
            HStack {
                Button {
                    withAnimation {
                        viewModel.selectedOption = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Title
            Text("Select door width")
                .font(.title2.weight(.semibold))

            // Photo preview (if available)
            // MVP Note: AC2 specifies showing "detected door (if found)" but door detection
            // in the mesh is not implemented for MVP. This shows a generic photo preview.
            // Future enhancement: Add door detection overlay highlighting.
            if let photoURL = viewModel.previewPhotoURL {
                AsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(4/3, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(maxHeight: 200)
                .padding(.horizontal, 24)
            }

            // Door width options
            HStack(spacing: 12) {
                ForEach(DoorWidth.allCases, id: \.self) { width in
                    SelectionButton(
                        title: width.displayString,
                        isSelected: viewModel.selectedDoorWidth == width,
                        accessibilityContext: "Door width"
                    ) {
                        viewModel.selectDoorWidth(width)
                    }
                }
            }
            .padding(.horizontal, 24)

            Text("Most interior doors are 32\"")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Continue button
            Button {
                Task {
                    await viewModel.performCalibration()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(viewModel.canContinue ? Color.accentColor : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canContinue)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Ceiling Height Selection View

    private var ceilingHeightSelectionView: some View {
        VStack(spacing: 24) {
            // Back button
            HStack {
                Button {
                    withAnimation {
                        viewModel.selectedOption = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.accentColor)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Title
            Text("Select ceiling height")
                .font(.title2.weight(.semibold))

            // Ceiling height options
            HStack(spacing: 12) {
                ForEach(CeilingHeight.allCases, id: \.self) { height in
                    SelectionButton(
                        title: height.feetString,
                        subtitle: "\(Int(height.rawValue))\"",
                        isSelected: viewModel.selectedCeilingHeight == height,
                        accessibilityContext: "Ceiling height"
                    ) {
                        viewModel.selectCeilingHeight(height)
                    }
                }
            }
            .padding(.horizontal, 24)

            Text("Standard ceiling height is 8'")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Continue button
            Button {
                Task {
                    await viewModel.performCalibration()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(viewModel.canContinue ? Color.accentColor : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canContinue)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Calibration Progress Overlay

    private var calibrationProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Calibrating...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
    }
}

// MARK: - Calibration Option Button

/// Large button for selecting calibration option (door or ceiling)
private struct CalibrationOptionButton: View {
    let option: ManualCalibrationOption
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: option.systemImage)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if isRecommended {
                        Text("Recommended")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .accessibilityLabel("\(option.title)\(isRecommended ? ", Recommended" : "")")
    }
}

// MARK: - Selection Button

/// Reusable selection button for door widths and ceiling heights
struct SelectionButton: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var accessibilityContext: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .accessibilityLabel(buildAccessibilityLabel())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func buildAccessibilityLabel() -> String {
        var label = ""
        if let context = accessibilityContext {
            label = "\(context): "
        }
        label += title
        if let subtitle = subtitle {
            label += ", \(subtitle)"
        }
        return label
    }
}

// MARK: - Preview

#Preview("Option Selection") {
    let input = ManualCalibrationInput(
        fusionResult: TSDFFusionResult(
            mesh: .empty,
            boundingBox: TSDFBoundingBox(min: .zero, max: .one),
            voxelSize: 0.02,
            integratedCloudCount: 10,
            totalPointsProcessed: 1000,
            processingTimeMs: 500,
            qualityMetrics: TSDFQualityMetrics(
                coveragePercentage: 0.8,
                averageVoxelWeight: 5.0,
                totalVoxelCount: 10000,
                isMeshManifold: true
            )
        ),
        floorPlane: AIPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0),
        failureReason: "No countertop detected",
        previewPhotoURL: nil
    )
    let calibrator = ScaleCalibrator()
    let viewModel = ManualCalibrationViewModel(input: input, calibrator: calibrator)

    ManualCalibrationView(viewModel: viewModel)
}
