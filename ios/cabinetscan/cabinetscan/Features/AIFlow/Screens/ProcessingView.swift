//
//  ProcessingView.swift
//  cabinetscan
//
//  Placeholder for server pipeline processing.
//  Will be replaced with upload + server status UI.
//

import SwiftUI

// MARK: - Processing View

/// Displays processing progress during server pipeline execution.
///
/// Currently a placeholder that shows upload and processing status.
/// Will be fully implemented when server pipeline is integrated.
struct ProcessingView: View {

    // MARK: - Dependencies

    /// Showroom logo URL (optional)
    let showroomLogoURL: URL?

    /// Callback when user cancels
    let onCancel: () -> Void

    /// Callback when user wants to start over after error
    let onStartOver: () -> Void

    /// Coordinator for upload and state management
    @ObservedObject var coordinator: AIFlowCoordinator

    // MARK: - State

    /// Whether cancel button is visible (shown after 5 seconds)
    @State private var showCancelButton = false

    /// Timer for showing cancel button
    @State private var cancelButtonTimer: Timer?

    /// Reduce Motion environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    private static let cancelButtonDelay: TimeInterval = 5.0

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                if let error = coordinator.captureState.error {
                    errorContent(error: error)
                } else {
                    processingContent
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
        .onAppear {
            startCancelButtonTimer()
        }
        .onDisappear {
            cancelButtonTimer?.invalidate()
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        VStack(spacing: 24) {
            // Showroom logo
            if let logoURL = showroomLogoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 80)
                    case .failure, .empty:
                        logoPlaceholder
                    @unknown default:
                        logoPlaceholder
                    }
                }
            } else {
                logoPlaceholder
            }

            // Spinner
            SpinnerView()
                .frame(width: 60, height: 60)

            // Title
            Text(statusTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            // Progress bar
            if coordinator.processingProgress > 0 {
                progressBar
            }

            // Status description
            if let status = coordinator.uploadStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Preparing your scan data...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cancel link (after delay)
            if showCancelButton {
                Button("Cancel") {
                    onCancel()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Status Title

    private var statusTitle: String {
        if let status = coordinator.uploadStatus {
            if status.contains("video") {
                return "Uploading video..."
            } else if status.contains("photo") {
                return "Uploading photos..."
            } else {
                return "Processing..."
            }
        }
        return "Analyzing your kitchen..."
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(
                            width: max(0, geometry.size.width * coordinator.processingProgress),
                            height: 8
                        )
                        .animation(reduceMotion ? .none : .linear(duration: 0.3), value: coordinator.processingProgress)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Processing progress")
            .accessibilityValue("\(Int(coordinator.processingProgress * 100)) percent")

            Text("\(Int(coordinator.processingProgress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Error Content

    private func errorContent(error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Processing Failed")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onStartOver) {
                Text("Start Over")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 48)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Logo Placeholder

    private var logoPlaceholder: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 40))
            .foregroundColor(.secondary)
            .frame(height: 80)
    }

    // MARK: - Helpers

    private func startCancelButtonTimer() {
        let shouldAnimate = !reduceMotion
        cancelButtonTimer = Timer.scheduledTimer(
            withTimeInterval: Self.cancelButtonDelay,
            repeats: false
        ) { _ in
            if shouldAnimate {
                withAnimation {
                    showCancelButton = true
                }
            } else {
                showCancelButton = true
            }
        }
    }
}

// MARK: - AICaptureState Extension

private extension AICaptureState {
    var error: Error? {
        if case .error(let error) = self {
            return error
        }
        return nil
    }
}

// MARK: - Spinner View

private struct SpinnerView: View {
    @State private var isAnimating = false
    @State private var opacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            opacity = 0.5
                        }
                    }
            } else {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                    .onAppear {
                        isAnimating = true
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#if DEBUG
struct ProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        let coordinator = AIFlowCoordinator()
        return ProcessingView(
            showroomLogoURL: nil,
            onCancel: { },
            onStartOver: { },
            coordinator: coordinator
        )
    }
}
#endif
